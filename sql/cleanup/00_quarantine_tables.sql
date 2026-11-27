-- cleanup/00_quarantine_tables.sql
-- Quarantine tables: bad rows are moved here with a reason, never deleted (ADR-005).

-- One quarantine table per table that loses rows: same columns + primary key as the original,
-- plus quarantine_reason and quarantined_at. The key stops a re-run storing a row twice.
CREATE TABLE IF NOT EXISTS orders_quarantine (LIKE orders INCLUDING INDEXES);
ALTER TABLE orders_quarantine
    ADD COLUMN IF NOT EXISTS quarantine_reason text,
    ADD COLUMN IF NOT EXISTS quarantined_at    timestamptz DEFAULT now();

CREATE TABLE IF NOT EXISTS order_items_quarantine (LIKE order_items INCLUDING INDEXES);
ALTER TABLE order_items_quarantine
    ADD COLUMN IF NOT EXISTS quarantine_reason text,
    ADD COLUMN IF NOT EXISTS quarantined_at    timestamptz DEFAULT now();

CREATE TABLE IF NOT EXISTS inventory_log_quarantine (LIKE inventory_log INCLUDING INDEXES);
ALTER TABLE inventory_log_quarantine
    ADD COLUMN IF NOT EXISTS quarantine_reason text,
    ADD COLUMN IF NOT EXISTS quarantined_at    timestamptz DEFAULT now();
