-- diagnosis/04_orders.sql
-- Orders: profile, status spellings, dates beyond the extract, monthly volume (read-only).

-- D1. Profile: id/date/total ranges, missing values, impossible totals.
SELECT count(*)                                         AS total_rows,
       min(order_id)   AS min_id,     max(order_id)     AS max_id,
       min(order_date) AS first_order, max(order_date)  AS last_order,
       min(total_amount) AS min_total, max(total_amount) AS max_total,
       count(*) - count(customer_id)                    AS null_customers,
       count(*) - count(order_date)                     AS null_dates,
       count(*) FILTER (WHERE coalesce(trim(status), '') = '') AS missing_status,
       count(*) FILTER (WHERE total_amount IS NULL OR total_amount <= 0) AS bad_totals
FROM orders;

-- D2. Status spellings: raw values grouped under their cleaned meaning.
--     exact_match = rows a filter like status = 'completed' would actually catch.
SELECT clean_status,
       count(DISTINCT status)                           AS spellings,
       string_agg(DISTINCT '"' || status || '"', ', ')  AS raw_values,
       count(*)                                         AS orders,
       count(*) FILTER (WHERE status = clean_status)    AS exact_match
FROM (SELECT status,
             CASE lower(trim(status))
                  WHEN 'complete' THEN 'completed'
                  WHEN 'canceled' THEN 'cancelled'
                  ELSE lower(trim(status)) END AS clean_status
      FROM orders) cleaned
GROUP BY clean_status
ORDER BY orders DESC;

-- D3. Dates beyond the extract: after 2026-08-31 (where the log stops) and after today.
--     "After today" depends on when this runs; "after extract" is fixed.
SELECT count(*) FILTER (WHERE order_date >= DATE '2026-09-01') AS after_extract_end,
       count(*) FILTER (WHERE order_date > now())             AS in_the_future
FROM orders;

-- D4. Orders per month: shows growth and the trickle after the extract ends.
SELECT date_trunc('month', order_date)::date AS month,
       count(*)                              AS orders
FROM orders
GROUP BY 1
ORDER BY 1;

-- D5. Busiest order hours, Ghana vs Nigeria customers (no time zone is stored).
--     The same peak hour in both suggests one clock was used for everyone.
SELECT CASE WHEN lower(trim(c.city)) IN ('lagos', 'abuja') THEN 'Nigeria' ELSE 'Ghana' END AS country,
       mode() WITHIN GROUP (ORDER BY extract(hour FROM o.order_date))                       AS busiest_hour,
       count(*)                                                                             AS orders
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
GROUP BY 1
ORDER BY 1;
