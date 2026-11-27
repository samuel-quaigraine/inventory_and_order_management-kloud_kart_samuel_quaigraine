# Monday report and category rollup performance report

## Target

- **Monday report:** "in seconds" (today: about 40 minutes, or it does not finish).
- **Low-stock rollup:** "a couple of seconds".
- **Flash sale:** about 400 orders in 10 seconds on one product, with no overselling.

## Method

- **Hardware / container spec:** Docker Desktop on a laptop, 8 CPUs, 16 GB RAM; PostgreSQL 18.7 in a fresh container from `docker-compose.yml`, default settings except `max_connections = 500`.
- **What was timed:** psql `\timing`, from the query being sent to the last row returned. The flash sale is the wall-clock time `race_test.py` reports for all 400 calls.
- **Runs:** "before" timed once each on 5, 10 and 20 customers, on the raw load (no cleanup, no indexes), then scaled up to all 40,420 customers. "After" run 5 times in a row (warm); the median is reported.
- **How to reproduce:**
  - Before: `schema.sql`, `load.sql`, then `psql -v sample=20 -f sql/benchmarks/report_before.sql`
  - After: `sql/00_run_all.sql`, then `psql -f sql/benchmarks/report_after.sql`
  - Flash sale: `python race_test.py` (output saved in `sql/benchmarks/results/`)

## Results

| Scenario | Runs | Median | p95 | Worst | Target met? |
|---|---|---|---|---|---|
| Monday report, all customers, top 100 × 12 months | 5 | 0.99 s | 1.19 s | 1.19 s | Yes |
| Low-stock rollup, whole tree | 5 | 21 ms | 23 ms | 23 ms | Yes |
| Flash sale, 400 buyers on 50 units | 1 | 5.2 s | — | — | Yes: exactly 50 sold, none oversold |

(With 5 runs, p95 is the slowest run.)

## Before / after

| Query / stage | Before | After | Change |
|---|---|---|---|
| Monday report | ~0.67 s per customer → ~7.5 hours for 40,420 (measured: 20 customers in 13.9 s) | 0.99 s for everyone | ~27,000× faster |
| Monday report: correctness | Exact `'completed'` filter misses 80% of completed orders; spend from order lines | All completed + shipped orders; spend from order totals | Right answer |
| Flash sale (400 buyers, 50 units) | 400 sold, stock ended at 48 | 50 sold, 350 told "out of stock", stock 0 | No overselling |
| Two buyers, last unit (25 rounds) | Both won in 25 of 25 rounds | One winner every round | Fixed |

## Caveats

- The "before" report is a reconstruction of a row-by-row design, not Adwoa's actual query, which I did not have. It was measured on a sample and scaled up; the full run was not attempted.
- Most of the speed-up comes from the redesign (one pass instead of thousands of small queries), not from indexes or hardware (ADR-003).
- Timings are on a laptop with the whole database in memory; a busy production server will be slower, but the work no longer grows with customers × months.
- The extract has about 1,170 orders a day at its busiest, not the brief's 4,000; at 4,000 a day the report would still read one year of orders once, an estimated few seconds.
