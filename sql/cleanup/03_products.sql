-- cleanup/03_products.sql
-- Products: clear negative stock (F-02), recording the change in the stock log.

-- Log first: a correction that brings each negative product back up to 0.
-- New log ids continue after the highest id in the log or its quarantine.
INSERT INTO inventory_log (log_id, product_id, change_qty, reason, created_at, note)
SELECT (SELECT max(log_id) FROM (SELECT log_id FROM inventory_log
                                 UNION ALL SELECT log_id FROM inventory_log_quarantine) ids)
         + row_number() OVER (ORDER BY product_id),
       product_id,
       -stock_quantity,
       'correction',
       now(),
       'cleanup: negative stock reset to 0 (oversold)'
FROM products
WHERE stock_quantity < 0;

-- Then the stock itself.
UPDATE products
SET stock_quantity = 0
WHERE stock_quantity < 0;
