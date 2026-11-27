-- 06_indexes.sql
-- Purpose: Indexes for the lookups the solution actually makes. The schema had none beyond primary keys.

-- Foreign keys: finding a customer's orders, an order's lines, a product's log rows.
-- Without these, every lookup by these columns reads the whole table.
-- (order_items.order_id is already covered by the UNIQUE (order_id, product_id) rule.)
CREATE INDEX IF NOT EXISTS orders_customer_idx       ON orders (customer_id);
CREATE INDEX IF NOT EXISTS order_items_product_idx   ON order_items (product_id);
CREATE INDEX IF NOT EXISTS inventory_log_product_idx ON inventory_log (product_id, created_at);
CREATE INDEX IF NOT EXISTS inventory_log_order_idx   ON inventory_log (order_id);
CREATE INDEX IF NOT EXISTS products_category_idx     ON products (category_id);
CREATE INDEX IF NOT EXISTS categories_parent_idx     ON categories (parent_id);

-- No index for the Monday report: its 12-month window covers most of the orders table, so
-- reading the table once is fastest (EXPLAIN shows a full scan). Its speed comes from the
-- redesign, not an index (ADR-003). An earlier version created one; it is removed here.
DROP INDEX IF EXISTS orders_report_idx;

-- Refresh the planner's statistics after cleanup changed so many rows.
ANALYZE;
