-- 08_category_rollup.sql
-- Purpose: Low-stock rollup through the category tree, any depth, safe from loops (ADR-004).
-- Usage:   SELECT * FROM low_stock_rollup();      -- low stock = 5 units or fewer
--          SELECT * FROM low_stock_rollup(10);    -- any threshold

-- Each category counts its own products plus those of every category below it.
-- Depth is never hard-coded: the recursive walk goes as deep as the tree goes.
CREATE OR REPLACE FUNCTION low_stock_rollup(p_threshold integer DEFAULT 5)
RETURNS TABLE (category_id        integer,
               category_name      text,
               depth              integer,
               low_stock_products bigint,
               total_products     bigint)
LANGUAGE sql STABLE AS $$
    -- 1. Every (category, category below it) pair, including itself.
    --    path remembers the route; the loop guard stops a cycle repeating forever.
    WITH RECURSIVE below AS (
        SELECT c.category_id AS top_id, c.category_id AS sub_id, ARRAY[c.category_id] AS path
        FROM categories c
      UNION ALL
        SELECT b.top_id, c.category_id, b.path || c.category_id
        FROM below b
        JOIN categories c ON c.parent_id = b.sub_id
        WHERE c.category_id <> ALL (b.path)            -- loop guard
    ),
    -- 2. Depth = how many categories sit above it, plus itself (top level = 1).
    depths AS (
        SELECT sub_id AS category_id, count(*)::integer AS depth
        FROM below
        GROUP BY sub_id
    )
    -- 3. Count products in each category's whole branch.
    SELECT c.category_id,
           c.category_name,
           d.depth,
           count(p.product_id) FILTER (WHERE p.stock_quantity <= p_threshold) AS low_stock_products,
           count(p.product_id)                                                AS total_products
    FROM categories c
    JOIN depths d   ON d.category_id = c.category_id
    JOIN below b    ON b.top_id = c.category_id
    LEFT JOIN products p ON p.category_id = b.sub_id
    GROUP BY c.category_id, c.category_name, d.depth
  UNION ALL
    -- 4. Products with no category would otherwise be invisible.
    SELECT NULL::integer, '(no category)'::text, NULL::integer,
           count(*) FILTER (WHERE stock_quantity <= p_threshold),
           count(*)
    FROM products
    WHERE category_id IS NULL
    ORDER BY low_stock_products DESC, category_id;
$$;
