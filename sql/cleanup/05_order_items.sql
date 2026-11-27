-- cleanup/05_order_items.sql
-- Order lines: quarantine lines with no order (F-04), absurd quantities (F-05),
-- missing prices (F-06) and repeated lines (F-03).

-- No order: either the order never existed (ids 900xxx) or it was just quarantined in 04_orders.
WITH moved AS (
    DELETE FROM order_items i
    WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.order_id = i.order_id)
    RETURNING i.*
)
INSERT INTO order_items_quarantine
SELECT moved.*,
       CASE WHEN EXISTS (SELECT 1 FROM orders_quarantine q WHERE q.order_id = moved.order_id)
            THEN 'its order was quarantined'
            ELSE 'order does not exist' END
FROM moved
ON CONFLICT DO NOTHING;

-- Absurd quantities: 999 and 9,999 (normal lines are 1-10; order totals show 1 unit was paid for).
WITH moved AS (
    DELETE FROM order_items WHERE quantity >= 100 RETURNING *
)
INSERT INTO order_items_quarantine
SELECT moved.*, 'absurd quantity' FROM moved
ON CONFLICT DO NOTHING;

-- Missing prices: a NULL price drops out of every sum without warning.
-- (Zero prices stay: the order total is correct and reports use the total.)
WITH moved AS (
    DELETE FROM order_items WHERE unit_price IS NULL RETURNING *
)
INSERT INTO order_items_quarantine
SELECT moved.*, 'missing price' FROM moved
ON CONFLICT DO NOTHING;

-- Repeated lines: same product twice in one order (double-insert bug).
-- Keep the first line (lowest id); quarantine the copies.
WITH ranked AS (
    SELECT order_item_id,
           row_number() OVER (PARTITION BY order_id, product_id ORDER BY order_item_id) AS copy_no
    FROM order_items
), moved AS (
    DELETE FROM order_items i
    USING ranked r
    WHERE r.order_item_id = i.order_item_id AND r.copy_no > 1
    RETURNING i.*
)
INSERT INTO order_items_quarantine
SELECT moved.*, 'repeated line (copy of an earlier line)' FROM moved
ON CONFLICT DO NOTHING;
