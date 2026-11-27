-- diagnosis/05_order_items.sql
-- Order lines: profile, quantity spread, absurd quantities, missing/zero prices, repeated lines (read-only).

-- E1. Profile: ranges, missing values, impossible values.
SELECT count(*)                                          AS total_rows,
       min(quantity)   AS min_qty,   max(quantity)   AS max_qty,
       min(unit_price) AS min_price, max(unit_price) AS max_price,
       count(*) - count(order_id)                        AS null_orders,
       count(*) - count(product_id)                      AS null_products,
       count(*) - count(quantity)                        AS null_qty,
       count(*) - count(unit_price)                      AS null_prices,
       count(*) FILTER (WHERE quantity <= 0)             AS bad_qty,
       count(*) FILTER (WHERE unit_price < 0)            AS negative_prices,
       count(*) FILTER (WHERE unit_price = 0)            AS zero_prices
FROM order_items;

-- E2. Quantity spread: every quantity used and how often.
--     Shows normal values and the odd ones out.
SELECT quantity, count(*) AS lines
FROM order_items
GROUP BY quantity
ORDER BY quantity;

-- E3. Absurd quantities (100 or more), with the money they add to reports.
SELECT order_item_id, order_id, product_id, quantity, unit_price,
       quantity * unit_price AS line_value
FROM order_items
WHERE quantity >= 100
ORDER BY line_value DESC;

-- E4. Lines with a missing or zero price.
--     NULL price drops out of SUM silently; zero price may be a promotion.
SELECT CASE WHEN unit_price IS NULL THEN 'missing price' ELSE 'zero price' END AS problem,
       count(*)                   AS lines,
       count(DISTINCT order_id)   AS orders_affected
FROM order_items
WHERE unit_price IS NULL OR unit_price = 0
GROUP BY 1;

-- E5. Same product more than once in one order.
--     identical_copies = same quantity and price too (likely a double insert).
SELECT count(*)                                AS repeated_groups,
       sum(n) - count(*)                       AS extra_lines,
       count(*) FILTER (WHERE variants = 1)    AS identical_copies
FROM (SELECT count(*)                                     AS n,
             count(DISTINCT (quantity, unit_price))       AS variants
      FROM order_items
      GROUP BY order_id, product_id
      HAVING count(*) > 1) pair_groups;

-- E6. Price charged vs current list price (zero/NULL prices excluded).
--     Only ever lower or equal = line discounts, not price drift in both directions.
SELECT count(*)                                         AS lines,
       count(*) FILTER (WHERE i.unit_price = p.price)   AS same_as_list,
       count(*) FILTER (WHERE i.unit_price < p.price)   AS below_list,
       count(*) FILTER (WHERE i.unit_price > p.price)   AS above_list,
       round(min(i.unit_price / p.price), 2)            AS lowest_ratio
FROM order_items i
JOIN products p ON p.product_id = i.product_id
WHERE i.unit_price > 0;
