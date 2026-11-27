-- diagnosis/07_relationships.sql
-- Links between tables: orphans, orphan id ranges, empty orders, products cut off from the tree (read-only).

-- G1. Broken links: child rows whose parent id does not exist.
--     LEFT JOIN keeps every child; parent NULL = parent missing. NULL child keys are "not set", not broken.
SELECT 'orders -> customers' AS link, count(*) AS orphan_rows
FROM orders o LEFT JOIN customers c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL AND o.customer_id IS NOT NULL
UNION ALL
SELECT 'order_items -> orders', count(*)
FROM order_items i LEFT JOIN orders o ON o.order_id = i.order_id
WHERE o.order_id IS NULL AND i.order_id IS NOT NULL
UNION ALL
SELECT 'order_items -> products', count(*)
FROM order_items i LEFT JOIN products p ON p.product_id = i.product_id
WHERE p.product_id IS NULL AND i.product_id IS NOT NULL
UNION ALL
SELECT 'inventory_log -> products', count(*)
FROM inventory_log l LEFT JOIN products p ON p.product_id = l.product_id
WHERE p.product_id IS NULL AND l.product_id IS NOT NULL
UNION ALL
SELECT 'products -> categories', count(*)
FROM products p LEFT JOIN categories c ON c.category_id = p.category_id
WHERE c.category_id IS NULL AND p.category_id IS NOT NULL
UNION ALL
SELECT 'categories -> parent', count(*)
FROM categories k LEFT JOIN categories p ON p.category_id = k.parent_id
WHERE p.category_id IS NULL AND k.parent_id IS NOT NULL
ORDER BY orphan_rows DESC;

-- G2. Orphan id ranges vs real id ranges: are the missing parents random or a separate block?
SELECT 'customer ids in orders' AS ids,
       (SELECT min(customer_id) || ' - ' || max(customer_id) FROM customers) AS real_range,
       min(o.customer_id) || ' - ' || max(o.customer_id)                   AS orphan_range,
       count(DISTINCT o.customer_id)                                       AS distinct_orphans
FROM orders o LEFT JOIN customers c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL
UNION ALL
SELECT 'order ids in order_items',
       (SELECT min(order_id) || ' - ' || max(order_id) FROM orders),
       min(i.order_id) || ' - ' || max(i.order_id),
       count(DISTINCT i.order_id)
FROM order_items i LEFT JOIN orders o ON o.order_id = i.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'product ids in inventory_log',
       (SELECT min(product_id) || ' - ' || max(product_id) FROM products),
       min(l.product_id) || ' - ' || max(l.product_id),
       count(DISTINCT l.product_id)
FROM inventory_log l LEFT JOIN products p ON p.product_id = l.product_id
WHERE p.product_id IS NULL;

-- G3. Orders with no lines at all (the reverse direction: parent with no children).
SELECT count(*) AS orders_without_lines
FROM orders o
WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.order_id = o.order_id);

-- G4. Products sitting in categories the tree walk cannot reach (see A4/A5).
--     A recursive low-stock rollup would silently skip these.
WITH RECURSIVE tree AS (
    SELECT category_id, ARRAY[category_id] AS path
    FROM categories WHERE parent_id IS NULL
  UNION ALL
    SELECT c.category_id, t.path || c.category_id
    FROM categories c JOIN tree t ON c.parent_id = t.category_id
    WHERE c.category_id <> ALL (t.path)          -- loop guard
)
SELECT p.category_id, c.category_name, count(*) AS products
FROM products p
JOIN categories c ON c.category_id = p.category_id
WHERE p.category_id NOT IN (SELECT category_id FROM tree)
GROUP BY p.category_id, c.category_name;

-- G5. Time order across tables: nothing should happen before its parent existed.
SELECT (SELECT count(*) FROM orders o JOIN customers c ON c.customer_id = o.customer_id
        WHERE o.order_date < c.registered_at)                           AS orders_before_registration,
       (SELECT count(*) FROM order_items i
        JOIN orders o   ON o.order_id = i.order_id
        JOIN products p ON p.product_id = i.product_id
        WHERE o.order_date < p.created_at)                              AS sold_before_product_created,
       (SELECT count(*) FROM inventory_log l JOIN products p ON p.product_id = l.product_id
        WHERE l.created_at < p.created_at)                              AS logged_before_product_created,
       (SELECT count(*) FROM customers c
        WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id)) AS customers_without_orders;

-- G6. Sale log -> order line: the log has no order_id, but a sale's timestamp equals its order_date.
--     Matching on product + time links each sale back to the order that caused it.
WITH lines AS (
    SELECT DISTINCT i.product_id, o.order_date
    FROM orders o JOIN order_items i ON i.order_id = o.order_id
)
SELECT count(*)            AS sale_entries,
       count(ln.product_id) AS linked_to_order_line,
       count(*) - count(ln.product_id) AS unlinked
FROM inventory_log l
LEFT JOIN lines ln ON ln.product_id = l.product_id AND ln.order_date = l.created_at
WHERE l.reason = 'sale';

-- G7. Highest ids referenced anywhere, including orphans.
--     A new order_id sequence must start above max_order_referenced, or old orphan lines attach to new orders.
SELECT (SELECT max(order_id)      FROM orders)        AS max_order_id,
       (SELECT max(order_id)      FROM order_items)   AS max_order_referenced,
       (SELECT max(order_item_id) FROM order_items)   AS max_order_item_id,
       (SELECT max(log_id)        FROM inventory_log) AS max_log_id,
       (SELECT max(product_id)    FROM products)      AS max_product_id;
