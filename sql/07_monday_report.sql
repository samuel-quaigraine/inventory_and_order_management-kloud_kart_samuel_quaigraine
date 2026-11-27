-- 07_monday_report.sql
-- Purpose: Adwoa's Monday report, redesigned to run in seconds (ADR-003).
-- Usage:   SELECT * FROM monday_report();                     -- 12 months to 2026-08-31, top 100
--          SELECT * FROM monday_report(DATE '2026-08-31', 50); -- any end date, any top-N

-- Assumptions (data_findings.md, "Decisions the data cannot make"):
--   * Spend = completed + shipped orders, using the order total (what the customer paid).
--   * The 12 months are the 12 calendar months ending with the month of p_as_of.
--   * Total spent and order count cover the same 12 months.
-- Why it is fast: it reads the orders table once (no order lines), groups once, and ranks once.
-- The old design recalculated each customer and each month separately (benchmarks/report_before.sql).
CREATE OR REPLACE FUNCTION monday_report(p_as_of date DEFAULT DATE '2026-08-31', p_top integer DEFAULT 100)
RETURNS TABLE (spend_rank    bigint,
               customer_id   integer,
               full_name     text,
               total_spent   numeric,
               order_count   bigint,
               month         date,
               month_spend   numeric,
               running_total numeric)
LANGUAGE sql STABLE AS $$
    -- 1. Spending orders in the 12-month window, tagged with their month.
    WITH window_orders AS (
        SELECT o.customer_id,
               date_trunc('month', o.order_date)::date AS month,
               o.total_amount
        FROM orders o
        WHERE o.status IN ('completed', 'shipped')
          AND o.order_date >= date_trunc('month', p_as_of) - interval '11 months'
          AND o.order_date <  p_as_of + 1
    ),
    -- 2. One row per customer: total, order count, and rank (ties broken by customer id).
    totals AS (
        SELECT w.customer_id,
               sum(w.total_amount) AS total_spent,
               count(*)            AS order_count,
               row_number() OVER (ORDER BY sum(w.total_amount) DESC, w.customer_id) AS spend_rank
        FROM window_orders w
        GROUP BY w.customer_id
    ),
    top_customers AS (
        SELECT * FROM totals WHERE spend_rank <= p_top
    ),
    -- 3. The 12 months, so a month with no spending still shows as 0.
    months AS (
        SELECT generate_series(date_trunc('month', p_as_of) - interval '11 months',
                               date_trunc('month', p_as_of),
                               interval '1 month')::date AS month
    ),
    -- 4. Spend per top customer per month.
    monthly AS (
        SELECT w.customer_id, w.month, sum(w.total_amount) AS month_spend
        FROM window_orders w
        JOIN top_customers t ON t.customer_id = w.customer_id
        GROUP BY w.customer_id, w.month
    )
    -- 5. Every top customer x every month, with a running total that restarts per customer.
    SELECT t.spend_rank,
           t.customer_id,
           c.full_name,
           t.total_spent,
           t.order_count,
           m.month,
           coalesce(mo.month_spend, 0) AS month_spend,
           sum(coalesce(mo.month_spend, 0))
               OVER (PARTITION BY t.customer_id ORDER BY m.month) AS running_total
    FROM top_customers t
    JOIN customers c ON c.customer_id = t.customer_id
    CROSS JOIN months m
    LEFT JOIN monthly mo ON mo.customer_id = t.customer_id AND mo.month = m.month
    ORDER BY t.spend_rank, m.month;
$$;
