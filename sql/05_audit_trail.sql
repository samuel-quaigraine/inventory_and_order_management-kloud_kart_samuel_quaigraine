-- 05_audit_trail.sql
-- Purpose: Every stock change leaves an inventory_log row, automatically, whoever makes it (ADR-002).
-- Log rows can't be edited; deleted rows are kept in an archive.

-- Triggers are removed first and recreated at the end, so this file can be re-run.
DROP TRIGGER IF EXISTS products_stock_audit        ON products;
DROP TRIGGER IF EXISTS inventory_log_no_edit       ON inventory_log;
DROP TRIGGER IF EXISTS inventory_log_keep_deleted  ON inventory_log;

-- ===== New columns: which order, and who =====

-- order_id links a sale to the order that caused it (F-10). changed_by records the database user.
-- The default is set after adding, so existing rows stay NULL ("unknown") instead of a made-up user.
ALTER TABLE inventory_log ADD COLUMN IF NOT EXISTS order_id   integer;
ALTER TABLE inventory_log ADD COLUMN IF NOT EXISTS changed_by text;
ALTER TABLE inventory_log ALTER COLUMN changed_by SET DEFAULT current_user;

-- The link may point only at a real order. ON DELETE SET NULL: deleting an order keeps its stock history.
-- DEFERRABLE: checked when the transaction commits, because place_order logs the sale before
-- it inserts the order row.
ALTER TABLE inventory_log
    DROP CONSTRAINT IF EXISTS inventory_log_order_fk,
    ADD  CONSTRAINT inventory_log_order_fk FOREIGN KEY (order_id) REFERENCES orders (order_id)
         ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- ===== Backfill the link for past sales =====

-- A sale's timestamp equals its order's order_date, so product + time finds the order (G6).
-- DISTINCT ON keeps one order if two ever share a product and a timestamp.
UPDATE inventory_log l
SET order_id = m.order_id
FROM (SELECT DISTINCT ON (i.product_id, o.order_date) i.product_id, o.order_date, o.order_id
      FROM orders o JOIN order_items i ON i.order_id = o.order_id
      ORDER BY i.product_id, o.order_date, o.order_id) m
WHERE l.reason = 'sale'
  AND l.order_id IS NULL
  AND m.product_id = l.product_id
  AND m.order_date = l.created_at;

-- ===== Archive for deleted log rows =====

-- Same columns as the log, plus when and by whom it was deleted.
CREATE TABLE IF NOT EXISTS inventory_log_archive (LIKE inventory_log);
ALTER TABLE inventory_log_archive
    ADD COLUMN IF NOT EXISTS archived_at timestamptz DEFAULT now(),
    ADD COLUMN IF NOT EXISTS archived_by text        DEFAULT current_user;

-- ===== Trigger 1: any stock change writes a log row =====

-- Fires when a product is added (opening stock) or its stock changes, from any source.
-- Reason and order come from place_order (or any caller) via set_config; otherwise:
-- a new product = 'restock' (opening balance), a direct edit = 'correction'.
CREATE OR REPLACE FUNCTION log_stock_change() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_change integer := NEW.stock_quantity - CASE WHEN TG_OP = 'INSERT' THEN 0 ELSE OLD.stock_quantity END;
    v_reason text    := nullif(current_setting('kloudkart.reason', true), '');
BEGIN
    IF v_change = 0 THEN
        RETURN NULL;                                     -- nothing moved, nothing to log
    END IF;
    INSERT INTO inventory_log (product_id, change_qty, reason, created_at, note, order_id)
    VALUES (NEW.product_id,
            v_change,
            coalesce(v_reason, CASE WHEN TG_OP = 'INSERT' THEN 'restock' ELSE 'correction' END),
            now(),
            CASE WHEN v_reason IS NOT NULL THEN NULL
                 WHEN TG_OP = 'INSERT'     THEN 'opening balance'
                 ELSE 'direct stock change, no reason given' END,
            nullif(current_setting('kloudkart.order_id', true), '')::integer);
    RETURN NULL;
END;
$$;

CREATE TRIGGER products_stock_audit
AFTER INSERT OR UPDATE OF stock_quantity ON products
FOR EACH ROW EXECUTE FUNCTION log_stock_change();

-- ===== Trigger 2: log rows can't be edited =====

-- A mistake is fixed by adding a correction, not by rewriting history.
-- Only exception: order_id may be cleared when its order is deleted (the SET NULL above).
CREATE OR REPLACE FUNCTION block_log_edit() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.order_id IS NULL
       AND (NEW.log_id, NEW.product_id, NEW.change_qty, NEW.reason, NEW.created_at, NEW.note, NEW.changed_by)
           IS NOT DISTINCT FROM
           (OLD.log_id, OLD.product_id, OLD.change_qty, OLD.reason, OLD.created_at, OLD.note, OLD.changed_by)
    THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'inventory_log rows cannot be changed; add a correction row instead';
END;
$$;

CREATE TRIGGER inventory_log_no_edit
BEFORE UPDATE ON inventory_log
FOR EACH ROW EXECUTE FUNCTION block_log_edit();

-- ===== Trigger 3: deleted log rows are kept =====

-- Deleting is still possible (race_test.py removes its test rows), but a copy goes to the archive.
CREATE OR REPLACE FUNCTION keep_deleted_log() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO inventory_log_archive SELECT OLD.*;
    RETURN OLD;
END;
$$;

CREATE TRIGGER inventory_log_keep_deleted
BEFORE DELETE ON inventory_log
FOR EACH ROW EXECUTE FUNCTION keep_deleted_log();
