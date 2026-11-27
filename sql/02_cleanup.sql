-- 02_cleanup.sql
-- Purpose: Get the data into a state where every rule in 03_constraints.sql can be added.
-- Bad rows are moved to *_quarantine tables with a reason, never deleted. One file per table in cleanup/.

-- One transaction: cleanup either completes fully or changes nothing.
BEGIN;

\ir cleanup/00_quarantine_tables.sql
\ir cleanup/01_categories.sql
\ir cleanup/02_customers.sql
\ir cleanup/03_products.sql
\ir cleanup/04_orders.sql
\ir cleanup/05_order_items.sql
\ir cleanup/06_inventory_log.sql

COMMIT;
