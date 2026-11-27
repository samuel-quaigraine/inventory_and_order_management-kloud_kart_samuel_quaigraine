-- cleanup/06_inventory_log.sql
-- Stock log: quarantine orphan (F-04), post-extract (F-08) and duplicate (F-03) rows,
-- then add corrections so every product's stock equals the sum of its log (F-09).

-- Column lists are written out because 05_audit_trail.sql later adds columns to the log;
-- this keeps the file safe to re-run.

-- Orphans: log rows for products that do not exist (ids 99xxx).
WITH moved AS (
    DELETE FROM inventory_log l
    WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.product_id = l.product_id)
    RETURNING l.log_id, l.product_id, l.change_qty, l.reason, l.created_at, l.note
)
INSERT INTO inventory_log_quarantine (log_id, product_id, change_qty, reason, created_at, note, quarantine_reason)
SELECT moved.*, 'product does not exist' FROM moved
ON CONFLICT DO NOTHING;

-- Post-extract: rows from the extract (log_id below 982,488) dated after 2026-08-31,
-- the sales of the quarantined late orders. New rows made after go-live are never touched.
WITH moved AS (
    DELETE FROM inventory_log
    WHERE created_at >= DATE '2026-09-01'
      AND log_id <= 982487
    RETURNING log_id, product_id, change_qty, reason, created_at, note
)
INSERT INTO inventory_log_quarantine (log_id, product_id, change_qty, reason, created_at, note, quarantine_reason)
SELECT moved.*, 'dated after the extract ends (2026-08-31)' FROM moved
ON CONFLICT DO NOTHING;

-- Duplicates in the extract: same product, change, reason and time written twice.
-- Keep the first (lowest id), quarantine the copies.
WITH ranked AS (
    SELECT log_id,
           row_number() OVER (PARTITION BY product_id, change_qty, reason, created_at
                              ORDER BY log_id) AS copy_no
    FROM inventory_log
    WHERE log_id <= 982487
), moved AS (
    DELETE FROM inventory_log l
    USING ranked r
    WHERE r.log_id = l.log_id AND r.copy_no > 1
    RETURNING l.log_id, l.product_id, l.change_qty, l.reason, l.created_at, l.note
)
INSERT INTO inventory_log_quarantine (log_id, product_id, change_qty, reason, created_at, note, quarantine_reason)
SELECT moved.*, 'duplicate log row' FROM moved
ON CONFLICT DO NOTHING;

-- Reconcile: stock_quantity is treated as the truth. Where the log does not add up to it
-- (no opening stock, removed rows), add one correction row for the difference.
WITH gap AS (
    SELECT p.product_id,
           p.stock_quantity - coalesce(sum(l.change_qty), 0) AS difference
    FROM products p
    LEFT JOIN inventory_log l ON l.product_id = p.product_id
    GROUP BY p.product_id, p.stock_quantity
    HAVING p.stock_quantity <> coalesce(sum(l.change_qty), 0)
), next_log_id AS (
    SELECT max(log_id) AS last_id
    FROM (SELECT log_id FROM inventory_log
          UNION ALL
          SELECT log_id FROM inventory_log_quarantine) all_log_ids
)
INSERT INTO inventory_log (log_id, product_id, change_qty, reason, created_at, note)
SELECT n.last_id + row_number() OVER (ORDER BY g.product_id),
       g.product_id,
       g.difference,
       'correction',
       now(),
       'cleanup: align log with stock (opening balance / removed rows)'
FROM gap g
CROSS JOIN next_log_id n;
