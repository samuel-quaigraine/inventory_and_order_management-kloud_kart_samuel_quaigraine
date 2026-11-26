# Data findings — Kloud Kart

## Summary

An audit of Kloud Kart's live PostgreSQL 18 extract (`159,384` orders, `336,559` order items, `40,420` customers, `4,023` products, `94` categories, and `282,352` inventory log entries) identified **eight material data-integrity and schema-absence faults** that directly corrupt the numbers Nana Adjei and Adwoa rely on. The root cause across all eight is that `schema.sql` enforces only primary keys—leaving foreign keys, uniqueness, domain checks, and ledger consistency entirely unenforced.

Ranked by danger to Kloud Kart's operations rather than raw row count:
1. **Unnormalized `orders.status` (`116,394` non-canonical rows)** silently drops **`273,128,670.24` (80.4%)** of completed revenue if queried naively (`status = 'completed'`).
2. **Stock-ledger drift (`144` products, `3,865,699.34` absolute inventory value drift)** and **negative stock (`14` products, `-27` units)** prove that `products.stock_quantity` and `inventory_log` have diverged under historical overselling and manual edits.
3. **Order total mismatches (`2,426` orders, `5,291,591.64` absolute discrepancy)** and **missing/zero line prices (`300` items)** break header-to-line financial reconciliation.
4. **A 2-node category cycle (`9001 <-> 9002`, holding `6` products / `440` units)** and **orphan parent (`9003 -> 8999`)** will hang or corrupt any unguarded recursive low-stock rollup.
5. **Duplicate normalized customer emails (`533` groups / `535` extra accounts)** split **`9,714,556.53`** of fulfilled spend and displace **`1`** top buyer from Adwoa's Top-100 ranking.

Six other patterns that initially look suspicious (negative `inventory_log.change_qty` on outward movements, zero-delta `stock_take` rows, uncategorised products, historical price variance, cosmetic customer formatting, and split `(order_id, product_id)` lines) were verified as intentional or harmless and should **not** be "fixed."

## Reconciliation

| Stage | Rows | Delta | Reason |
|---|---:|---:|---|
| Raw `orders` loaded | 159,384 | — | Full extract (`487,063,959.81` gross across all statuses) |
| Naive `status = 'completed'` filter | 22,091 | -137,293 | Drops `89,260` valid completed orders (`273,128,670.24`) due to casing, leading spaces, and `'complete'` spelling |
| Canonical fulfilled (`completed`/`complete`/`shipped`) | 124,199 | +102,108 vs naive | True fulfilled volume (`380,566,270.90` revenue) |
| Fulfilled `orders` with valid `customer_id` | 124,043 | -156 fulfilled (-210 all) | `210` total orders (`427,668.87` fulfilled; `665,180.61` gross) lack a matching `customers` row |
| Orders within bulk extract window (`<= 2026-08-31`) | 159,360 | -24 | `24` sparse rogue orders (`68,040.02`) dated `2026-09-06` to `2027-08-20` |
| Unique customers by `customer_id` vs `lower(trim(email))` | 40,420 / 39,885 | -535 | `533` duplicate normalized email groups spanning `1,068` rows |
| `order_items` linked to valid `orders` | 335,867 | -692 | `692` orphan `order_items` (`968` units, `826,327.80`) have no row in `orders` |
| `products` matching `SUM(inventory_log.change_qty)` | 3,879 | -144 | `144` products disagree with their ledger sum by `2,553` absolute units (`-2,375` net) |
| `categories` valid acyclic hierarchy | 91 | -3 | `2` cyclic nodes (`9001`, `9002`) and `1` orphan parent (`9003 -> 8999`) |

## Findings, ranked by risk

### F-01: Unnormalized free-text `orders.status` — Severity: Critical

- **What it is:** Missing `CHECK` constraint (or lookup foreign key) and input normalization on `orders.status` (`text`). Fifteen raw spellings, casings, and whitespace-padded strings represent five logical states (`completed`, `pending`, `shipped`, `refunded`, `cancelled`).
- **How I detected it:** `SELECT status, count(*), round(sum(total_amount), 2) FROM orders GROUP BY 1 ORDER BY 2 DESC;` (`CHK-10` and `Q1` in `01_setup_and_audit/integrity_checks.sql`).
- **Scale:** `116,394` of `159,384` orders (`73.0%`) have non-canonical values (`22,395` `' completed'` with a leading space, `22,392` `'COMPLETED'`, `22,285` `'complete'`, `22,188` `'Completed'`, `8,081` `'Pending'`, `6,332` `'Shipped'`, `3,262` `'Refunded'`, `3,209` `'canceled'`, `3,131` `'Cancelled'`, `3,119` `'CANCELLED'`).
- **Effect on the client's number:** Any report or Monday spend query filtering `WHERE status = 'completed'` captures only `22,091` orders (`66,480,695.79`) and silently omits `89,260` valid completed orders worth **`273,128,670.24` (80.4% of completed revenue)**—plus `6,332` `'Shipped'` orders worth `20,780,169.69`.
- **What I did about it:** In Phase 2 (`02_schema_and_remediation/schema_hardening.sql`), normalize all existing `orders.status` values to five lowercase canonical values (`completed`, `pending`, `shipped`, `refunded`, `cancelled`) and add `CHECK (status IN ('completed','pending','shipped','refunded','cancelled'))`. Risk: any legacy app code still writing `'complete'` or `'COMPLETED'` will error on `INSERT`/`UPDATE` until updated (or unless normalized in `place_order()` / trigger).
- **Residual risk:** Historical rows labeled `'complete'` vs `'completed'` are assumed semantically identical; if a legacy workflow used `'complete'` for a distinct fulfillment stage, merging them masks that distinction.

### F-02: Stock-ledger drift and negative `stock_quantity` — Severity: Critical

- **What it is:** Missing `CHECK (stock_quantity >= 0)`, missing atomic order-to-ledger coupling, and missing row-level locking allowed `products.stock_quantity` to go negative and diverge from `SUM(inventory_log.change_qty)`.
- **How I detected it:** `CHK-11`, `CHK-18`, `Q2`, and `Q3` in `01_setup_and_audit/integrity_checks.sql` comparing `products.stock_quantity` against `inventory_log` aggregations.
- **Scale:** `144` products disagree with their `inventory_log` net movement (`2,553` absolute unit drift; `-2,375` net unit drift; **`3,865,699.34`** in absolute catalog stock value). `14` products currently hold negative `stock_quantity` (`-27` total units, lowest `-4`), involved in `1,138` historical orders.
- **Effect on the client's number:** Directly explains why Nana no longer trusts stock counts or low-stock alerts: `14` negative-stock SKUs falsely inflate urgency or indicate unfulfilled oversold orders, while `144` products cannot be reconciled to an audit trail (`3,865,699.34` of stock valuation lacks ledger backing).
- **What I did about it:** In Phase 2, add `CHECK (stock_quantity >= 0)` (after quarantining/adjusting the `14` negative SKUs with explicit `correction` audit entries) and reconcile/baseline the `144` drifted SKUs with documented opening-reconciliation log notes (`remediation`) rather than silently overwriting `stock_quantity`. In Phase 3, enforce atomic stock decrement + `inventory_log` write inside `place_order()`. Risk: clamping negative stock to `0` without physical warehouse verification assumes those `27` oversold units were cancelled/refunded or restocked physically.
- **Residual risk:** Without a physical warehouse stock count, we cannot confirm whether `products.stock_quantity` or `SUM(inventory_log.change_qty)` reflects actual shelf inventory for the `144` drifted SKUs.

### F-03: `orders.total_amount` mismatches and missing/zero `order_items.unit_price` — Severity: High

- **What it is:** `orders.total_amount` (application-written at checkout) is not constrained to match `SUM(order_items.quantity * order_items.unit_price)`, and `order_items.unit_price` lacks `NOT NULL` and `CHECK (unit_price > 0)`.
- **How I detected it:** `CHK-12`, `CHK-16`, and `Q4` in `01_setup_and_audit/integrity_checks.sql`.
- **Scale:** `2,426` orders differ from their line-item sum by `> 0.01` (`2,129` with positive line prices, `150` with `$0.00` line prices, `147` with `NULL` line prices). `300` `order_items` have `unit_price IS NULL` (`148` rows, `399,909.10` catalog value) or `unit_price = 0` (`152` rows, `132,384.40` catalog value).
- **Effect on the client's number:** Total header-vs-line discrepancy is **`5,291,591.64` absolute (`-3,400,693.90` net)** across `2,426` orders (`6,826,578.20` in active fulfilled order totals). Customer lifetime spend on Adwoa's Monday report will differ by up to `3.40M–5.29M` depending on whether she sums `orders.total_amount` or `order_items`.
- **What I did about it:** Enforce `NOT NULL` and `CHECK (unit_price > 0)` on new `order_items` (using `NOT VALID` or preserving legacy exceptions explicitly documented, or backfilling `NULL` prices only where verifiable), and document the canonical spend source (`orders.total_amount` vs `order_items`) in ADR-003. Risk: blindly overwriting `orders.total_amount` with line sums could erase unmodeled shipping, discounts, or promo `0.00` items.
- **Residual risk:** Because no `discount`, `tax`, or `shipping` columns exist in `orders`, we cannot determine from the schema alone which of the `2,129` positive-price mismatches were legitimate fees/discounts versus checkout calculation bugs.

### F-04: Cyclic category hierarchy and orphan category parent — Severity: High

- **What it is:** Missing self-referencing `FOREIGN KEY (parent_id) REFERENCES categories(category_id)` and missing cycle prevention on `categories`.
- **How I detected it:** `CHK-01`, `CHK-09`, and `Q7` in `01_setup_and_audit/integrity_checks.sql` using a recursive CTE with `ARRAY` path cycle detection.
- **Scale:** `2` cyclic categories (`9001` *Seasonal Promotions* `-> 9002`, and `9002` *Promotions* `-> 9001`) holding **`6` products (`440` stock units)**, plus `1` orphan category (`9003` *Clearance* pointing to non-existent `parent_id = 8999`, `0` direct products).
- **Effect on the client's number:** Any unguarded recursive CTE for Nana's low-stock category rollup enters an **infinite loop** on `9001 <-> 9002` (failing the report or blowing memory/timeout) and silently drops `9003` if anchored solely on `WHERE parent_id IS NULL`. Even if guarded, `6` products (`440` units) sit inside a rootless loop with no top-level parent.
- **What I did about it:** Break the cycle (`9002` set as root `parent_id = NULL`, keeping `9001 -> 9002`), set `9003.parent_id = NULL` (or archive empty orphan root), add `FOREIGN KEY (parent_id) REFERENCES categories(category_id)` and `CHECK (parent_id <> category_id)`, **and** still keep a cycle-termination guard (`CYCLE` / path check) in `04_reporting_and_rollups/category_rollup.sql` as defense-in-depth. Risk: promoting `9002` and `9003` to root categories assumes they were intended as top-level departments.
- **Residual risk:** A single-row `CHECK (parent_id <> category_id)` prevents 1-node self-loops, not future multi-node cycles (`A -> B -> A`), which is why the rollup view keeps a cycle guard and Phase 2/trigger validation is noted.

### F-05: Duplicate customer email accounts (`customers.email` not unique) — Severity: High

- **What it is:** Missing `UNIQUE` constraint (case/whitespace-insensitive) on `customers.email`.
- **How I detected it:** `CHK-07`, `CHK-08`, and `Q6` in `01_setup_and_audit/integrity_checks.sql` grouping by `lower(trim(email))`.
- **Scale:** `533` normalized email addresses appear on more than one customer row, spanning `1,068` rows (`535` extra accounts).
- **Effect on the client's number:** Overstates distinct customer count on the Monday report by up to **`535`** (`40,420` rows vs `39,885` unique emails), splits **`9,714,556.53`** of fulfilled customer spend across duplicate IDs, and **displaces `1` customer from Adwoa's Top-100 ranking** (that buyer's combined spend across duplicate accounts qualifies for Top 100, while each split account falls below the cutoff).
- **What I did about it:** Document and flag duplicate email groups without blindly auto-merging `customer_id`s in production without business verification; provide a deduplicated view option and unique normalized-email index decision in ADR-003. Risk: auto-merging rows on email alone could combine two real people (e.g., family members or corporate buyers) sharing one inbox.
- **Residual risk:** Until Kloud Kart decides whether one email strictly equals one buyer and completes a manual review of the `533` groups, a `UNIQUE` index on existing rows cannot be enforced without breaking/quarantining those `535` rows.

### F-06: Orphan `order_items` (`692` rows) and orphan `orders.customer_id` (`210` rows) — Severity: Medium-High

- **What it is:** Missing `FOREIGN KEY` constraints on `order_items(order_id)` and `orders(customer_id)` allowed child rows whose parent records do not exist.
- **How I detected it:** Anti-joins (`CHK-03`, `CHK-04`, and `Q5` in `01_setup_and_audit/integrity_checks.sql`).
- **Scale:** `692` `order_items` (`968` units, **`826,327.80`** line value) reference non-existent `order_id`s; `210` `orders` (**`665,180.61`** gross, **`427,668.87`** fulfilled) reference non-existent `customer_id`s.
- **Effect on the client's number:** An `INNER JOIN` between `orders` and `customers` in Adwoa's Monday report silently drops **`427,668.87`** of valid fulfilled revenue (`156` fulfilled orders; `210` total). Meanwhile, product-level revenue computed from `order_items` exceeds order-header revenue by **`826,327.80`** due to the `692` orphaned line items.
- **What I did about it:** Use `LEFT JOIN` (or explicit `"Unknown / Deleted Customer"` bucket) in reporting so `427,668.87` is never silently dropped, quarantine or validate historical orphans (`NOT VALID` FK constraints in Phase 2 so all *new* inserts enforce referential integrity without deleting financial history). Risk: `NOT VALID` FKs leave the historical `210` + `692` orphans in place until operations decides whether to purge or archive them.
- **Residual risk:** Orphan `order_items` cannot be attributed to a customer or order date without their missing `orders` header.

### F-07: Post-cutoff / future-dated `orders.order_date` and naive `timestamp` — Severity: Medium

- **What it is:** No `CHECK` bound on `orders.order_date`, and the column uses `timestamp` (without time zone) rather than `timestamptz`.
- **How I detected it:** Monthly distribution and `CHK-14` / `Q8` in `01_setup_and_audit/integrity_checks.sql`.
- **Scale:** Bulk operational history ends at `2026-08-31 23:58:07` (`159,360` orders); **`24` sparse orders (`68,040.02`)** carry dates from `2026-09-06` through `2027-08-20`, including **`15` strictly future orders** beyond the audit date (`2026-11-26`). (`40` `inventory_log` rows also fall after `2026-08-31`.)
- **Effect on the client's number:** If Adwoa's "trailing 12 months" window anchors on `max(order_date)` (`2027-08-20`), the window becomes `2026-08-21` to `2027-08-20`—silently discarding **~11.5 months of real orders** and showing almost empty monthly columns. Anchoring on `CURRENT_TIMESTAMP` still leaks `15` future-dated rows (`2026-12` to `2027-08`) into future buckets or skews "as-of" totals by `40,871.60` (`68,040.02` post-Aug).
- **What I did about it:** Anchor the Monday report's trailing 12-month cutoff cleanly (documented in ADR-003) and exclude/flag post-cutoff anomalies; constrain future `order_date`s via `CHECK` or `DEFAULT now()`. Risk: if Accra operates solely in `GMT`/`UTC+0`, `timestamp` matches UTC locally, but any timezone shift or multi-region client breaks instant comparisons.
- **Residual risk:** Without knowing whether the `9` orders in `2026-09`–`2026-11` were late test data or real trickle transactions, we cannot verify if the true business cutoff was `2026-08-31`.

### F-08: Orphan `inventory_log.product_id` — Severity: Low-Medium

- **What it is:** Missing `FOREIGN KEY (product_id) REFERENCES products(product_id)` on `inventory_log`.
- **How I detected it:** Anti-join (`CHK-06` and `Q5` in `01_setup_and_audit/integrity_checks.sql`).
- **Scale:** `120` `inventory_log` rows (`-120` net units, `120` absolute units moved) point to missing `product_id`s.
- **Effect on the client's number:** Does not change current `products.stock_quantity` or Monday customer spend, but breaks complete product-level audit-trail reconciliation (`120` historical movements have no SKU name or category).
- **What I did about it:** Add `FOREIGN KEY (product_id) REFERENCES products(product_id) NOT VALID` in Phase 2 so all new movements must match a valid SKU while preserving historical audit rows. Risk: existing `120` orphan movements remain unattributable to active SKUs.
- **Residual risk:** If those `120` rows came from deleted test or discontinued products, total historical warehouse volume audited strictly via `INNER JOIN products` will be short by `120` units.

## Looked wrong, is not wrong

| Apparent problem | Why it looks wrong | Why it is actually fine |
|---|---|---|
| Negative `inventory_log.change_qty` (`262,646` rows) | Negative numbers in a quantity column often signal corrupted inputs or underflows. | Intentional signed-ledger convention documented in `schema.sql` (`-- Negative for outward movement.`). All `262,088` `sale` and `268` `damage` rows are `< 0`, all `18,857` `restock` and `564` `return` rows are `> 0`, and `CHK-15` confirmed `0` sign inversions. |
| Zero `change_qty` in `inventory_log` (`90` `stock_take` rows) | A stock movement row changing stock by `0` looks like a no-op bug. | Every single `0`-qty row has `reason = 'stock_take'` (`90` of `90`), acting as an audit checkpoint confirming physical count matched system count. |
| `products.category_id IS NULL` (`37` products, `3,112` stock units, `12` low-stock) | Looks like missing foreign-key data that should be rejected or deleted. | Uncategorised SKUs (e.g., `Tecno Cooker XL`, `Oraimo Desktop Plus`) are valid active inventory. The rollup must include them via `LEFT JOIN` under an `"Uncategorised"` label rather than dropping `12` low-stock items. |
| `order_items.unit_price != products.price` (`3,964` positive-price rows) | Line price disagrees with the product's current catalog `price`. | Standard historical price capture: catalog prices change over time while completed order lines preserve the unit price paid at checkout. Only `NULL` and `0.00` prices (`300` rows) are faults. |
| Inconsistent casing/formats in `customers` (`full_name`, `city`, `phone`) | Values like `YAA MENSAH`, `ACCRA`, `031 862 6394`, and `+233...` look messy. | Purely cosmetic formatting differences; they do not inflate customer counts, distort spend totals, or break joins (`customer_id` is integer PK). Normalizing them adds effort with zero effect on Nana's or Adwoa's decisions. |
| Repeated `(order_id, product_id)` pairs in `order_items` (`616` pairs) | Looks like duplicate line items inside the same order. | Sample inspection shows distinct line additions (e.g., `{1,3}` or `{1,1}` units at valid prices) that sum normally per `order_id`; no `order_item_id` PK collision exists. |

## Could not verify

- **True physical stock for the `144` drifted SKUs and `14` negative-stock SKUs:** Without a physical warehouse count, we cannot verify whether `products.stock_quantity` or `SUM(inventory_log.change_qty)` represents true on-shelf inventory.
- **Root cause of the `2,129` positive-price `orders.total_amount` mismatches:** Because `orders` lacks `discount_amount`, `shipping_fee`, and `tax_amount` columns, we cannot verify from the database alone whether those `2,129` differences reflect legitimate checkout adjustments/fees or application calculation bugs.
- **Time zone of `orders.order_date`, `products.created_at`, `customers.registered_at`, and `inventory_log.created_at`:** All four columns are `timestamp` without time zone; we assume Accra local time (`UTC+0` / GMT) but cannot prove from the dump whether any application client wrote local offset timestamps (`UTC+1` e.g., Lagos).
- **Whether the `533` duplicate normalized emails are single individuals or genuinely shared addresses:** Without customer outreach or verification (e.g., matching phone/address records with operations sign-off), we cannot safely confirm that all `535` extra rows belong to duplicate accounts rather than shared family/business inboxes.
- **Whether the `9` orders dated `2026-09`–`2026-11` are valid trickle orders or rogue test rows:** The bulk extract ends sharply on `2026-08-31 23:58:07`; `15` orders in `2026-12`–`2027-08` are unambiguously invalid future dates, while the `9` orders in `2026-09`–`2026-11` cannot be definitively classified without checking the extract generation date.
