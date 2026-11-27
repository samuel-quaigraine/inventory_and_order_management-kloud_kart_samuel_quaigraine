# Kloud Kart: inventory and orders

Kloud Kart sells online in Accra. Two problems brought this project:

1. **Overselling.** When two customers buy the last unit at the same moment, both get it.
2. **A slow Monday report.** Adwoa's customer-spending report takes about 40 minutes, or never finishes.

This repository diagnoses the data, cleans it, and fixes both problems inside the existing PostgreSQL database, with no new servers.

## What was done, in one minute

| Problem | What fixed it | Proof |
|---|---|---|
| Overselling | `place_order()` checks and takes stock in one step, so the last unit can only be sold once | `race_test.py` passes: 400 buyers on 50 units → exactly 50 sold |
| Slow report | `monday_report()` reads the orders once instead of once per customer per month | About 1 second, from about 7.5 hours |
| Low-stock view | `low_stock_rollup()` walks the category tree at any depth, safe from loops | About 20 ms |
| No audit trail | Every stock change is logged automatically; log rows can't be edited | Stock matches the log for every product |
| Messy data | Bad rows moved to quarantine tables, text standardised, rules added | `data_findings.md` |
| (Extra) Cancelled orders kept their stock | `cancel_order()` puts back exactly what the order took | `improvement.md` |

## How to run it

You need **Docker** and **Python 3**. Everything else runs inside the container.

**1. Put the data in place.** Copy the six Kloud Kart CSV files into `data/` (they are not in the repository because they hold customer details):

```
data/categories.csv  data/products.csv  data/customers.csv
data/orders.csv      data/order_items.csv  data/inventory_log.csv
```

**2. Set a password and start the database.** The password lives in a local `.env` file that is never committed. Then start PostgreSQL 18, with the project folder visible inside it at `/lab`:

```bash
cp .env.example .env      # then edit .env and choose a password
docker compose up -d
```

**3. Build the database.** One command: `load.sql` creates the original tables, loads the CSVs, then runs the whole solution (steps 01 to 09). It stops at the first error:

```bash
docker compose exec -T db psql -U postgres -d kloudkart -v ON_ERROR_STOP=1 -f load.sql
```

**4. Run the concurrency test:**

```bash
pip install psycopg2-binary
source .env              # loads POSTGRES_PASSWORD from your .env
export DATABASE_URL="postgresql://postgres:${POSTGRES_PASSWORD}@localhost:5432/kloudkart"
python race_test.py
```

You should see `PASSED — exactly one buyer gets the last unit, every time.`

**5. Try it yourself** (inside `docker compose exec db psql -U postgres -d kloudkart`):

```sql
SELECT * FROM monday_report();                 -- top 100 customers, 12 months to 2026-08-31
SELECT * FROM low_stock_rollup();              -- low stock = 5 units or fewer
SELECT * FROM place_order(100001, 5001, 1);    -- buy 1 unit
SELECT * FROM cancel_order(<order_id>);        -- cancel it, stock comes back
```

Running step 3 a second time is safe: nothing is duplicated, and new orders are never touched by cleanup.

## What each step does

| File | What it does |
|---|---|
| `sql/01_diagnosis.sql` | Read-only checks that find and count every data problem (one file per table in `sql/diagnosis/`) |
| `sql/02_cleanup.sql` | Moves bad rows to `*_quarantine` tables with a reason; standardises text and statuses (`sql/cleanup/`) |
| `sql/03_constraints.sql` | Adds the rules: time zones on dates, id generators, required fields, allowed values, links between tables |
| `sql/04_place_order.sql` | The order function: one step to check and take stock, so nothing is oversold |
| `sql/05_audit_trail.sql` | Every stock change writes a log row automatically; log rows can't be edited; deleted ones are archived |
| `sql/06_indexes.sql` | Indexes for the lookups the solution makes |
| `sql/07_monday_report.sql` | Adwoa's report, redesigned |
| `sql/08_category_rollup.sql` | Low-stock counts rolled up through the category tree |
| `sql/09_improvement.sql` | `cancel_order()`: cancelling returns stock |
| `sql/benchmarks/` | Before/after timings and the old, broken order function used for comparison (not part of the run) |

**The two schema files:**

| File | What it is |
|---|---|
| `given/schema.sql`, `given/load.sql` | The originals, exactly as delivered: no rules, data loaded as found |
| `schema.sql` | The **final** design: every table, type, key, rule and index in one readable file. Run it on an empty database to get the corrected structure directly |
| `load.sql` | Builds the corrected database **from the CSVs**: original tables → load → clean → add rules |

Why not load the CSVs straight into the final `schema.sql`? The old data breaks its rules (orphans, 15 status spellings, negative stock), so the first bad row would stop the load. The data has to be cleaned (02) before the rules go on (03). Both routes produce the same structure: this was checked line by line (110 of 110 match).

## Where the deliverables are

| Deliverable | File |
|---|---|
| Data diagnosis | `data_findings.md` |
| Working SQL solution | `sql/` (run in order by `sql/00_run_all.sql`) |
| Key decisions | `decisions/ADR-001` … `ADR-005` |
| Performance proof | `performance_report.md` |
| Memo to Nana | `client_memo.md` |
| Improvement beyond the brief | `improvement.md`, `sql/09_improvement.sql` |
| Database diagram | `database_diagram.md` |

The given files are unchanged: `given/schema.sql`, `given/load.sql`, `race_test.py` and `data/`.
