# ADR-003: Fix the Monday report by redesigning the query, not buying a bigger server

- **Status:** Accepted
- **Date:** 2026-11-27
- **Decision owner:** Samuel Quaigraine

## Context

Adwoa's Monday report (per customer: total spent, order count, monthly spend for 12 months, running total, top 100) takes about 40 minutes or does not finish. Nana was quoted a bigger server; he has no budget for one. A row-by-row version of the report, run on the data as found, costs about 0.67 seconds per customer, about 7.5 hours for all 40,420 (`sql/benchmarks/report_before.sql`). It is also wrong: it filters on the exact word `'completed'`, which misses 80% of completed orders (F-01), and builds spend from order lines, which include absurd quantities and repeats (F-03, F-05).

## Decision

Rewrite the report as one function, `monday_report()`, that reads the orders table once, groups once and ranks once, using order totals (what the customer paid) for completed and shipped orders. Add indexes on the columns it and the rest of the solution look up.

## Alternatives considered

### Alternative A: A bigger server

- **How it would work:** Same report, faster hardware.
- **Why it is attractive:** No code change.
- **Why rejected:** The work grows with customers × months; faster hardware divides 7.5 hours by a small factor, costs money Nana does not have, and the report would still give the wrong answer.

### Alternative B: Pre-compute the report overnight into a summary table

- **How it would work:** A nightly job fills a table; Monday reads it.
- **Why it is attractive:** Instant to read.
- **Why rejected:** Not needed once the query runs in about a second, and it adds a job that can fail and data that can go stale.

### Alternative C: Indexes only, keep the row-by-row design

- **How it would work:** Add indexes so each small query is faster.
- **Why it is attractive:** Smallest change.
- **Why rejected:** Still thousands of separate queries per run, and still the wrong numbers.

## Consequences

- **What this buys:** The full report (100 customers × 12 months) runs in about **1 second** (median of 5 runs), from about 7.5 hours. The numbers now include all completed orders.
- **What this costs:** Adwoa runs a function instead of her old query; the rules it uses (what counts as spend, which 12 months) are written in the file and need Nana's confirmation.
- **What it costs the client if I am wrong:** Decisions made on a ranking that misses 80% of completed orders.
- **What would make me revisit this:** Order volume growing 10–20×, at which point a summary table (Alternative B) becomes worth it.

## What this survives

- **A different week or a different top-N:** `monday_report(DATE '…', 50)`.
- **Status spelling drift:** impossible now; a CHECK rule allows only 5 statuses.
- **Bad order lines:** the report never reads them; it uses order totals.
- **Growth:** the work grows with the number of orders, not orders × customers × months.
