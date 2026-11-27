# Data findings — Kloud Kart Ltd.

## Summary

The extract loaded in full and covers 2025-08-02 to 2026-08-31, plus 24 stray orders dated later. Four problems change the numbers Nana and Adwoa rely on: order status is spelled 15 ways, so an exact filter gets 85 of the top-100 customers wrong; 14 products were oversold; a double-insert bug added 617 order lines and 519 log rows; and orphan rows sit in id blocks that look like test or imported data. The stock log only appears to miss sales: cancelled, pending and refunded orders never took stock, by design. Volume is lower than the brief's ~4,000 orders a day (the busiest month averages ~1,170), so the extract may be a sample.

**What was done:** bad rows were moved to quarantine tables with a reason (234 orders, 1,979 order lines, 679 log rows), never deleted; text and statuses were standardised; and rules were added so none of these problems can be stored again (`sql/02_cleanup.sql`, `sql/03_constraints.sql`).

All checks are read-only: `sql/01_diagnosis.sql` runs `sql/diagnosis/01–08`. Check ids (A1, H7, …) refer to those files. Cleanup is in `sql/cleanup/01–06`, one file per table.

## Reconciliation

Three checks, one for each way the data can go wrong: rows going missing, money not adding up, and stock not matching sales.

### 1. Rows: did anything go missing?

Each table is counted at every stage. Rows removed by cleanup are in the matching `_quarantine` table, with a reason.

| Table | CSV file | Loaded | Delta | After cleanup | Delta | Reason |
|---|---|---|---|---|---|---|
| categories | 94 | 94 | 0 | 94 | 0 | 3 unreachable categories made top-level (F-07) |
| products | 4,023 | 4,023 | 0 | 4,023 | 0 | 14 negative stock levels set to 0 (F-02) |
| customers | 40,420 | 40,420 | 0 | 40,420 | 0 | Text tidied (F-13); duplicates kept (F-11) |
| orders | 159,384 | 159,384 | 0 | 159,150 | −234 | 210 with no customer (F-04), 24 after the extract (F-08) |
| order_items | 336,559 | 336,559 | 0 | 334,580 | −1,979 | 692 with no order, 519 whose order was quarantined, 614 repeats, 148 no price, 6 absurd |
| inventory_log | 282,352 | 282,352 | 0 | 282,236 | −116 | 679 quarantined (519 duplicates, 120 no product, 40 after the extract); 563 corrections added (see Units) |

Every row in every file was loaded (`check_setup.sql`). After cleanup, every row is either still in its table or in quarantine: none disappeared.

### 2. Money: do order totals agree with their lines? (H2)

The sum of all order lines (quantity × price) is **3,400,694 GHS higher** than the sum of all order totals (487,063,960 GHS). Every order falls into one group, and the groups add up to the whole gap:

| Cause | Orders | Lines minus totals (GHS) | Finding |
|---|---|---|---|
| Absurd quantity | 6 | +3,059,983 | F-05 |
| Repeated line | 610 | +882,398 | F-03 |
| Missing or zero price | 297 | −505,607 | F-06 |
| Discounts or fees not stored | 1,589 | −36,080 | F-12 |
| Totals and lines agree | 156,882 | 0 | |
| **Total** | **159,384** | **+3,400,694** | |

The order totals are the trustworthy figure: almost all of the gap comes from errors in the lines. This is why spend in the Monday report is taken from the order total.

**After cleanup** the lines are 610,666 GHS *lower* than the totals: 149 orders with zero-price lines (−123,112) and 1,793 orders in the discount group (−487,554). That group grew because about 200 orders lost a line to quarantine (no price, absurd quantity) while their total stayed. 30 orders now have no lines at all. The order total remains the figure to report from.

### 3. Units: does the stock log match the orders? (H4)

Only completed and shipped orders take stock off the shelf. The six absurd-quantity lines (23,994 units) are left out (F-05).

| Order status | Units ordered | Takes stock off the shelf? |
|---|---|---|
| Completed | 369,973 | Yes |
| Shipped | 42,742 | Yes |
| Pending | 53,414 | No, not yet fulfilled |
| Cancelled | 41,829 | No |
| Refunded | 21,531 | No |
| **Completed + shipped** | **412,715** | |
| **Logged as sales** | **412,645** | 70 units apart (0.02%) |

The log matches the orders that shipped. The "missing" 22% are orders that never took stock. One caution: 70 is a *net* figure. Some shipped units were never logged, while 120 logged sales belong to products that do not exist (F-04), so the two errors partly cancel out. The duplicate lines and duplicate log rows (F-03) also cancel each other. The match is close, but not as close as 70 suggests.

**After cleanup** stock equals the sum of its log for all 4,023 products (H1). 14 correction rows record the negative stock being reset, and 549 record gaps that had no log entry (missing opening stock, removed duplicates). Each is marked `cleanup:` in its note.

## Findings, ranked by risk

Severity: **Critical** = loses money or customers, or makes a decision number wrong · **High** = silently distorts reports or breaks the solution · **Medium** = real but contained · **Low** = untidy, no number affected.

### F-01: Order status spelled 15 ways — Severity: Critical

- **What it is:** 5 statuses written 15 ways (`COMPLETED`, `" completed"`, `complete`, `canceled`, …).
- **How I detected it:** D2 (spellings), H7 (top 100 both ways).
- **Scale:** Only 22,091 of 111,351 completed orders match `'completed'` exactly.
- **Effect on the client's number:** The naive top 100 shares only **15 customers** with the correct one.
- **What I did about it:** Rewrote all statuses to 5 values (`cleanup/04_orders.sql`); a CHECK rule now refuses any other spelling.
- **Residual risk:** Which statuses count as "spent" is a business decision; my default is completed + shipped.

### F-02: Overselling — Severity: Critical

- **What it is:** Products sold beyond what was on the shelf.
- **How I detected it:** C2 (negative stock), H1 (stock vs log).
- **Scale:** 14 products, as low as −4; 13 match their log, so the oversell was recorded but not blocked.
- **Effect on the client's number:** Customers sold items that did not exist.
- **What I did about it:** Reset the 14 to 0 with a logged correction. `place_order` checks and takes stock in one step (ADR-001), with a `stock >= 0` rule as the safety net. `race_test.py`: 400 buyers on 50 units now sells exactly 50 (the old way sold 400).
- **Residual risk:** Earlier oversells cannot be counted (no opening stock, F-09).

### F-03: Double-insert bug — Severity: High

- **What it is:** The same product written twice in one order, with its log sale written twice.
- **How I detected it:** E5 (repeated lines), F5 (duplicate log rows), H2 (totals).
- **Scale:** 617 extra order lines (577 identical copies); 519 duplicate log rows.
- **Effect on the client's number:** Line revenue overstated by 882,398 GHS; units and stock movements double-counted. Order totals are correct.
- **What I did about it:** Quarantined 614 repeated lines and 519 duplicate log rows, keeping the first of each. A UNIQUE rule allows one line per product per order.
- **Residual risk:** 39 pairs differ and may be genuine second lines.

### F-04: Orphan rows in separate id blocks — Severity: High

- **What it is:** Rows pointing at a parent that does not exist.
- **How I detected it:** G1 (counts), G2 (id ranges), G7 (highest ids).
- **Scale:** 210 orders (customer ids 999007–999997), 692 order lines (order ids 900101–999862), 120 log rows (product ids 99011–99999), 1 category. None overlap the real ranges.
- **Effect on the client's number:** Blocks foreign keys; a new order-id sequence must start above 999,862 or old orphan lines attach to new orders.
- **What I did about it:** Quarantined them (ADR-005), then added foreign keys on every link. New order ids start at 1,000,000.
- **Residual risk:** Source unconfirmed.

### F-05: Absurd quantities — Severity: High

- **What it is:** Quantities of 999 and 9,999; every other line is 1, 2, 3, 5 or 10.
- **How I detected it:** E2, E3, H6.
- **Scale:** 6 lines, 3.06M GHS of line value. The order totals are normal (order 583621: 9,999 × 87.35, total 87.35), so the quantity is wrong.
- **Effect on the client's number:** Line-based units and revenue inflated; `total_amount` unaffected.
- **What I did about it:** Quarantined the 6 lines; a CHECK now allows quantities from 1 to 100.
- **Residual risk:** Those orders keep their (correct) total but show fewer units.

### F-06: Missing and zero line prices — Severity: High

- **What it is:** Lines with no price, or a price of 0.
- **How I detected it:** E4 (counts), H2b (was the customer charged?).
- **Scale:** 148 NULL, 152 zero. 142 of the 152 zero-price lines were charged at full list price, so the price was lost, not discounted.
- **Effect on the client's number:** `SUM` skips NULLs silently; line revenue understated.
- **What I did about it:** Quarantined the 148 lines with no price; a price is now required. Zero-price lines were kept: the order total is right and reports use it.
- **Residual risk:** 150 zero-price lines remain and understate line revenue; 30 orders now have no lines.

### F-07: Category loop and missing parent — Severity: High

- **What it is:** 9001 and 9002 are each other's parent; 9003 points at 8999, which does not exist.
- **How I detected it:** A3, A4, A5 (tree walk), G4.
- **Scale:** 3 categories unreachable; 6 products inside them. A foreign key cannot catch the loop.
- **Effect on the client's number:** The low-stock rollup skips them, or loops forever without a guard.
- **What I did about it:** Any category the tree walk cannot reach is now top-level (one rule fixes both); a foreign key checks parents, and the rollup has a loop guard (ADR-004).
- **Residual risk:** The right parents are a business decision.

### F-08: Records after the extract ends — Severity: High

- **What it is:** Orders grow to 36,357 in August 2026, then drop to 1–5 a month until 2027-08.
- **How I detected it:** D3, D4, F4.
- **Scale:** 24 orders and 40 log sales after 2026-08-31; 15 orders in the future.
- **Effect on the client's number:** "Trailing 12 months" anchored on the latest date would report on almost nothing.
- **What I did about it:** Quarantined the 24 orders, their lines and their 40 log rows; the report counts back from a stated date (2026-08-31 by default).
- **Residual risk:** They may be clock or time-zone errors.

### F-09: Stock vs log mismatch; no opening stock — Severity: High

- **What it is:** Stock differs from the sum of its log, and the log has no opening balance.
- **How I detected it:** H1, F6.
- **Scale:** 144 products mismatch (net −2,375 units). For 2,911 products the first log entry is a sale.
- **Effect on the client's number:** The log cannot prove current stock.
- **What I did about it:** Added 549 `cleanup:` corrections so stock equals the log for every product. New products now get an opening-balance row automatically (ADR-002).
- **Residual risk:** The corrections explain the gap but not its cause; stock was treated as the truth.

### F-10: Weak audit trail — Severity: High

- **What it is:** Manual changes with no usable reason; sales not linked to orders.
- **How I detected it:** F3 (notes), F7 (stock-takes), G6 (log-to-order link).
- **Scale:** 216 of 485 corrections say "??", "see WhatsApp msg" or nothing. All 90 stock-takes record 0 and none was followed by a correction (F7), so the counts were never applied. A sale's timestamp equals its order's, so 261,968 of 262,088 sales can be linked back.
- **Effect on the client's number:** Nana cannot answer "who changed this, and why?"
- **What I did about it:** Every stock change now writes a log row automatically, with reason, order and user; log rows can't be edited and deleted ones are archived (ADR-002). Past sales were linked to their orders (261,005 linked).
- **Residual risk:** Past corrections stay unexplained.

### F-11: Duplicate customer emails — Severity: Medium

- **What it is:** Customers sharing an email once case and spaces are ignored.
- **How I detected it:** B3, B4.
- **Scale:** 533 groups (1,068 rows); 234 hidden by formatting. Same name, never the same phone.
- **Effect on the client's number:** One person's spend could split across ids; none are in the top 100.
- **What I did about it:** Kept as separate customers, not merged (ADR-005); emails are now stored trimmed and lowercase so duplicates can't hide.
- **Residual risk:** Same person or not is unproven.

### F-12: Totals off by clean percentages — Severity: Medium

- **What it is:** Order totals that differ from their lines with no data error to explain it.
- **How I detected it:** H2, H3, E6.
- **Scale:** 1,589 orders; ratios at 0.50, 0.75, 0.90, 1.10, 1.25. Line prices are only ever at or below list.
- **Effect on the client's number:** Spend must come from `total_amount`, what the customer paid.
- **What I did about it:** The Monday report uses `total_amount`.
- **Residual risk:** The discount and fee rules are not stored.

### F-13: Untidy text — Severity: Low

- **What it is:** Stray spaces, capitals, Accra spelled 4 ways, 5 phone formats.
- **How I detected it:** B2, B5, B6.
- **Scale:** About 1,300 emails and 1,150 names with spaces; no invalid or missing values.
- **Effect on the client's number:** None in the brief's reports.
- **What I did about it:** Trimmed names, lowercased emails, one spelling per city, phones as `+233` and 9 digits (`cleanup/02_customers.sql`).
- **Residual risk:** None.

## Looked wrong, is not wrong

| Apparent problem | Why it looks wrong | Why it is actually fine |
|---|---|---|
| Log covers only ~78% of units ordered | Sales missing from the log | Only completed and shipped orders take stock; those match within 70 units (H4) |
| Negative `change_qty` | Negative quantities | Sign is direction: sale/damage out, restock/return in (F2) |
| 7 categories with no parent | Missing data | They are the top-level categories (A1) |
| 37 products with no category | Missing data | The test suite inserts products without one |
| 406 duplicate product names | Duplicate products | Different ids and prices: generated names that collide (C3) |
| 55 products at 15,000 GHS+ | Typos | Orders sell them at that price (C4) |
| Line prices below list | Wrong prices | Never above list: discounts (E6) |
| kloudkart.com emails | Staff or test accounts | Same size as gmail or yahoo (B7) |
| Lagos and Abuja customers | Wrong country | Plausibly a Nigeria pilot |
| 768 customers with no orders | Orphans | Registering without buying is normal (G5) |

## Could not verify

- **Where the orphan rows came from.** Their ids sit far outside the normal ranges, which suggests test data or an import from another system. Only Kloud Kart can confirm this.
- **Whether the 24 orders dated after August 2026 are real.** They belong to real customers and their sales were recorded in the stock log. A wrong clock on the server would look exactly the same, so the data cannot tell the two apart.
- **How the discounts and fees on orders were worked out.** Many order totals are 10%, 25% or 50% off the sum of their lines, but no column records why.
- **Whether customers who share an email are the same person.** Their names match, but their phone numbers are always different.
- **Which time zone the dates are in.** The database does not store one. Orders from Ghana and Nigeria are busiest at the same hours, so one clock was probably used for both.

**Decisions the data cannot make.** These are business rules. I have chosen a sensible default for each, and Nana should confirm them.

- **What counts as money spent:** completed and shipped orders only. Pending, cancelled and refunded orders are left out, because no stock or money changed hands for good.
- **Where "the last 12 months" starts:** counted back from 31 August 2026, the last day of the data, not from today. Counting from today would include three months with almost no orders and drop three months of real ones (F-08).
- **What counts as low stock:** 5 units or fewer. The data has no reorder level for any product, so a threshold has to be chosen (C5).
