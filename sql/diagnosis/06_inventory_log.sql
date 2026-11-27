-- diagnosis/06_inventory_log.sql
-- Inventory log: profile, sign of change by reason, notes, dates beyond the extract (read-only).

-- F1. Profile: ranges, missing values, zero-quantity movements.
--     Negative change_qty = stock going out (by design, not an error).
SELECT count(*)                                       AS total_rows,
       min(created_at) AS first_entry, max(created_at) AS last_entry,
       min(change_qty) AS min_change,  max(change_qty) AS max_change,
       count(*) - count(product_id)                   AS null_products,
       count(*) - count(change_qty)                   AS null_changes,
       count(*) FILTER (WHERE coalesce(trim(reason), '') = '') AS missing_reasons,
       count(*) FILTER (WHERE change_qty = 0)         AS zero_changes
FROM inventory_log;

-- F2. Sign of change by reason: each reason should only move stock one way.
--     sale/damage out, restock/return in, correction either, stock_take none.
SELECT reason,
       count(*)                                  AS entries,
       count(*) FILTER (WHERE change_qty < 0)    AS outward,
       count(*) FILTER (WHERE change_qty > 0)    AS inward,
       count(*) FILTER (WHERE change_qty = 0)    AS no_change,
       min(change_qty) AS min_change, max(change_qty) AS max_change,
       max(created_at)                           AS last_entry
FROM inventory_log
GROUP BY reason
ORDER BY entries DESC;

-- F3. Notes: which reasons carry notes, and what they say.
--     Vague notes on manual corrections = weak audit trail.
SELECT reason,
       coalesce(note, '(no note)') AS note,
       count(*)                    AS entries
FROM inventory_log
WHERE reason IN ('correction', 'stock_take')
GROUP BY reason, note
ORDER BY reason, entries DESC;

-- F4. Entries beyond the extract (from 2026-09-01) and in the future, by reason.
SELECT reason,
       count(*) FILTER (WHERE created_at >= DATE '2026-09-01') AS after_extract_end,
       count(*) FILTER (WHERE created_at > now())             AS in_the_future
FROM inventory_log
GROUP BY reason
HAVING count(*) FILTER (WHERE created_at >= DATE '2026-09-01') > 0;

-- F5. Duplicate log entries: same product, change, reason and timestamp.
--     consecutive_ids = written back-to-back by log_id.
SELECT reason,
       count(*)                                     AS duplicate_groups,
       sum(n) - count(*)                            AS extra_rows,
       count(*) FILTER (WHERE max_id - min_id = n - 1) AS consecutive_ids
FROM (SELECT reason, count(*) AS n, min(log_id) AS min_id, max(log_id) AS max_id
      FROM inventory_log
      GROUP BY product_id, change_qty, reason, created_at
      HAVING count(*) > 1) dupes
GROUP BY reason;

-- F6. Opening stock: is each product's first log entry a restock?
--     A first entry of 'sale' means the starting balance was never logged.
SELECT reason AS first_entry_reason, count(*) AS products
FROM (SELECT DISTINCT ON (product_id) product_id, reason
      FROM inventory_log
      ORDER BY product_id, created_at, log_id) first_entry
GROUP BY reason
ORDER BY products DESC;

-- F7. Were stock-takes applied? Look for a correction on the same product within 7 days.
SELECT count(*) AS stock_takes,
       count(*) FILTER (WHERE EXISTS (
           SELECT 1 FROM inventory_log c
           WHERE c.product_id = s.product_id
             AND c.reason = 'correction'
             AND c.created_at >  s.created_at
             AND c.created_at <= s.created_at + interval '7 days')) AS followed_by_correction
FROM inventory_log s
WHERE s.reason = 'stock_take';
