-- benchmarks/report_before.sql
-- Purpose: The 'before': a row-by-row report design, as found. Run on the raw load (no indexes).
-- Not part of 00_run_all.sql. Usage: psql -v sample=20 -f sql/benchmarks/report_before.sql

-- Why it is slow: for EVERY customer and EVERY month it runs separate sub-queries, and each one
-- re-reads orders and order lines from scratch (no indexes). Work grows with customers x months.
-- Why it is also wrong: exact status = 'completed' misses 80% of completed orders (F-01),
-- and spend comes from order lines, which include absurd quantities and repeats (F-03, F-05).
-- It is timed on :sample customers and scaled up to all 40,420 (the full run would not finish).

\if :{?sample}
\else
    \set sample 20
\endif
\timing on

SELECT c.customer_id,
       c.full_name,
       m.month,
       (SELECT sum(i.quantity * i.unit_price)
        FROM orders o JOIN order_items i ON i.order_id = o.order_id
        WHERE o.customer_id = c.customer_id AND o.status = 'completed'
          AND o.order_date >= m.month AND o.order_date < m.month + interval '1 month') AS month_spend,
       (SELECT sum(i.quantity * i.unit_price)
        FROM orders o JOIN order_items i ON i.order_id = o.order_id
        WHERE o.customer_id = c.customer_id AND o.status = 'completed'
          AND o.order_date >= DATE '2025-09-01'
          AND o.order_date < m.month + interval '1 month')                            AS running_total,
       (SELECT sum(i.quantity * i.unit_price)
        FROM orders o JOIN order_items i ON i.order_id = o.order_id
        WHERE o.customer_id = c.customer_id AND o.status = 'completed'
          AND o.order_date >= DATE '2025-09-01' AND o.order_date < DATE '2026-09-01') AS total_spent,
       (SELECT count(*)
        FROM orders o
        WHERE o.customer_id = c.customer_id AND o.status = 'completed'
          AND o.order_date >= DATE '2025-09-01' AND o.order_date < DATE '2026-09-01') AS order_count
FROM (SELECT * FROM customers ORDER BY customer_id LIMIT :sample) c
CROSS JOIN generate_series(DATE '2025-09-01', DATE '2026-08-01', interval '1 month') AS m(month)
ORDER BY total_spent DESC NULLS LAST, c.customer_id, m.month;
