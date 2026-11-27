-- 01_diagnosis.sql
-- Purpose: Find and count every data problem (read-only).
-- Runs each table's checks in order; one file per table in diagnosis/.

\ir diagnosis/01_categories.sql
\ir diagnosis/02_customers.sql
\ir diagnosis/03_products.sql
\ir diagnosis/04_orders.sql
\ir diagnosis/05_order_items.sql
\ir diagnosis/06_inventory_log.sql
\ir diagnosis/07_relationships.sql
\ir diagnosis/08_reconciliation.sql
