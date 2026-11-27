-- diagnosis/08_reconciliation.sql
-- Totals that should agree: stock vs log, order total vs lines, logged sales vs units sold (read-only).

-- H1. Stock vs log: stock_quantity should equal the sum of all its log movements.
--     neg_stock_matching_log = oversold products whose log agrees (oversell recorded, not drift).
WITH s AS (
    SELECT p.product_id, p.stock_quantity AS stock, coalesce(sum(l.change_qty), 0) AS log_sum
    FROM products p
    LEFT JOIN inventory_log l ON l.product_id = p.product_id
    GROUP BY p.product_id, p.stock_quantity
)
SELECT count(*) FILTER (WHERE stock = log_sum)                AS matching,
       count(*) FILTER (WHERE stock < log_sum)                AS stock_lower,
       count(*) FILTER (WHERE stock > log_sum)                AS stock_higher,
       sum(stock - log_sum)                                   AS net_unit_gap,
       count(*) FILTER (WHERE stock < 0)                      AS negative_stock,
       count(*) FILTER (WHERE stock < 0 AND stock = log_sum)  AS neg_stock_matching_log
FROM s;

-- H2. Money KPI: sum of lines minus sum of order totals, split by cause (TOTAL row = whole gap).
--     Causes checked in order; NULL prices count as 0 so every order is included.
WITH repeated AS (
    SELECT DISTINCT order_id FROM order_items
    GROUP BY order_id, product_id HAVING count(*) > 1
), t AS (
    SELECT o.order_id, o.total_amount,
           coalesce(sum(i.quantity * i.unit_price), 0)          AS lines_sum,
           bool_or(i.unit_price IS NULL OR i.unit_price = 0)    AS bad_price,
           bool_or(i.quantity >= 100)                           AS absurd_qty
    FROM orders o
    JOIN order_items i ON i.order_id = o.order_id
    GROUP BY o.order_id, o.total_amount
)
, c AS (
    SELECT lines_sum - total_amount AS gap,
           CASE WHEN absurd_qty THEN '1. absurd quantity'
                WHEN bad_price  THEN '2. missing/zero price'
                WHEN order_id IN (SELECT order_id FROM repeated) THEN '3. repeated line'
                WHEN abs(total_amount - lines_sum) > 0.01 THEN '4. discounts/fees'
                ELSE '5. agree' END AS cause
    FROM t
)
SELECT coalesce(cause, 'TOTAL')         AS cause,
       count(*)                         AS orders,
       round(sum(gap), 2)               AS lines_minus_totals
FROM c
GROUP BY ROLLUP (cause)
ORDER BY cause;

-- H2b. Zero-price lines: was the customer charged anyway?
--      If total minus the other lines equals list price x qty, the price was lost, not discounted.
WITH z AS (
    SELECT i.order_id, i.quantity, p.price
    FROM order_items i JOIN products p ON p.product_id = i.product_id
    WHERE i.unit_price = 0
), gap AS (
    SELECT o.order_id,
           o.total_amount - sum(i.quantity * coalesce(i.unit_price, 0)) AS unpaid_gap
    FROM orders o JOIN order_items i ON i.order_id = o.order_id
    WHERE o.order_id IN (SELECT order_id FROM z)
    GROUP BY o.order_id, o.total_amount
)
SELECT count(*)                                                              AS zero_price_lines,
       count(*) FILTER (WHERE abs(g.unpaid_gap - z.quantity * z.price) < 0.05) AS charged_at_list_price
FROM z JOIN gap g ON g.order_id = z.order_id;

-- H3. Unexplained mismatches: ratio of total to lines.
--     Clean ratios (0.5, 0.75, 0.9, 1.1, 1.25) suggest discounts/fees applied but never stored.
WITH t AS (
    SELECT o.order_id, o.total_amount, sum(i.quantity * i.unit_price) AS lines_sum
    FROM orders o JOIN order_items i ON i.order_id = o.order_id
    GROUP BY o.order_id, o.total_amount
    HAVING sum(i.quantity * i.unit_price) > 0
)
SELECT round(total_amount / lines_sum, 2) AS total_to_lines_ratio,
       count(*)                           AS orders
FROM t
WHERE abs(total_amount - lines_sum) > 0.01
GROUP BY 1
ORDER BY 2 DESC
LIMIT 8;

-- H4. Units sold by status vs units logged as sales.
--     Shows which statuses actually take stock off the shelf.
SELECT CASE lower(trim(o.status))
            WHEN 'complete' THEN 'completed'
            WHEN 'canceled' THEN 'cancelled'
            ELSE lower(trim(o.status)) END    AS clean_status,
       sum(i.quantity)                        AS units_ordered
FROM orders o
JOIN order_items i ON i.order_id = o.order_id
WHERE i.quantity < 100
GROUP BY 1
UNION ALL
SELECT 'LOGGED AS SALE', -sum(change_qty)
FROM inventory_log
WHERE reason = 'sale'
ORDER BY 1;

-- H5. Per product: logged sales vs units from completed + shipped orders.
--     FULL JOIN keeps products found on only one side (e.g. orphan log products).
WITH shipped AS (
    SELECT i.product_id, sum(i.quantity) AS units
    FROM orders o JOIN order_items i ON i.order_id = o.order_id
    WHERE lower(trim(o.status)) IN ('completed', 'complete', 'shipped')
      AND i.quantity < 100
    GROUP BY i.product_id
), logged AS (
    SELECT product_id, -sum(change_qty) AS units
    FROM inventory_log WHERE reason = 'sale'
    GROUP BY product_id
)
SELECT count(*)                                         AS products,
       count(*) FILTER (WHERE s.units = l.units)        AS exact_match,
       count(*) FILTER (WHERE s.units IS NULL)          AS logged_only,
       count(*) FILTER (WHERE l.units IS NULL)          AS shipped_only,
       count(*) FILTER (WHERE s.units <> l.units)       AS both_but_differ
FROM shipped s
FULL JOIN logged l ON l.product_id = s.product_id;

-- H6. Absurd-quantity orders: which number is wrong, the quantity or the total?
--     Total far below lines = customer paid for a normal quantity; the quantity field is wrong.
SELECT o.order_id, o.total_amount, sum(i.quantity * i.unit_price) AS lines_sum
FROM orders o
JOIN order_items i ON i.order_id = o.order_id
WHERE o.order_id IN (SELECT order_id FROM order_items WHERE quantity >= 100)
GROUP BY o.order_id, o.total_amount
ORDER BY o.order_id;

-- H7. Monday report impact: top 100 by spend with clean statuses vs an exact 'completed' filter.
--     in_both = customers who appear in both lists.
WITH clean AS (
    SELECT customer_id FROM orders
    WHERE lower(trim(status)) IN ('completed', 'complete', 'shipped')
    GROUP BY customer_id ORDER BY sum(total_amount) DESC LIMIT 100
), naive AS (
    SELECT customer_id FROM orders
    WHERE status = 'completed'
    GROUP BY customer_id ORDER BY sum(total_amount) DESC LIMIT 100
)
SELECT count(*) AS top_100_clean,
       count(*) FILTER (WHERE customer_id IN (SELECT customer_id FROM naive)) AS in_both
FROM clean;
