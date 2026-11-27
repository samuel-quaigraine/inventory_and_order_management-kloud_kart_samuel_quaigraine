-- cleanup/04_orders.sql
-- Orders: standardise status (F-01), quarantine orphan (F-04) and post-extract (F-08) orders.

-- Status: 15 spellings become 5 values (completed, pending, shipped, cancelled, refunded).
-- The clean value is worked out once, then only rows that change are updated.
WITH normalised AS (
    SELECT order_id,
           CASE lower(trim(status))
                WHEN 'complete' THEN 'completed'
                WHEN 'canceled' THEN 'cancelled'
                ELSE lower(trim(status)) END AS clean_status
    FROM orders
)
UPDATE orders o
SET status = n.clean_status
FROM normalised n
WHERE n.order_id = o.order_id
  AND o.status <> n.clean_status;

-- Orphans: orders whose customer does not exist (ids 999xxx).
-- DELETE ... RETURNING hands the removed rows straight to the quarantine insert.
WITH moved AS (
    DELETE FROM orders o
    WHERE NOT EXISTS (SELECT 1 FROM customers c WHERE c.customer_id = o.customer_id)
    RETURNING o.*
)
INSERT INTO orders_quarantine
SELECT moved.*, 'customer does not exist' FROM moved
ON CONFLICT DO NOTHING;

-- Post-extract: orders from the extract (ids below 1,000,000) dated after 2026-08-31.
-- New orders from place_order start at 1,000,000, so a re-run never touches real new sales.
WITH moved AS (
    DELETE FROM orders
    WHERE order_date >= DATE '2026-09-01'
      AND order_id < 1000000
    RETURNING *
)
INSERT INTO orders_quarantine
SELECT moved.*, 'dated after the extract ends (2026-08-31)' FROM moved
ON CONFLICT DO NOTHING;
