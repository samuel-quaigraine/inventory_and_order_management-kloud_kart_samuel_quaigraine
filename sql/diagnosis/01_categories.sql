-- diagnosis/01_categories.sql
-- Categories: profile, duplicate names, broken parent links, tree walk (read-only).
-- A1. Profile: total rows, NULL names, distinct names, NULL parents.
--     NULL parent = top-level category (expected, not an error).
SELECT count(*)                        AS total_rows,
       count(*) - count(category_name) AS null_names,
       count(DISTINCT category_name)   AS distinct_names,
       count(*) - count(parent_id)     AS null_parents
FROM categories;

-- A2. Near-duplicate names, ignoring case and surrounding spaces.
--     Returns only names that appear more than once.
SELECT lower(trim(category_name)) AS normalised_name,
       count(*)                   AS how_many,
       array_agg(category_id)     AS category_ids
FROM categories
GROUP BY lower(trim(category_name))
HAVING count(*) > 1;

-- A3. Broken parent links: parent id does not exist, or points to itself.
--     Self-join: c = child, p = parent.
SELECT c.category_id, c.category_name, c.parent_id,
       CASE WHEN c.parent_id = c.category_id THEN 'own parent'
            ELSE 'parent missing' END AS problem
FROM categories c
LEFT JOIN categories p ON p.category_id = c.parent_id
WHERE c.parent_id IS NOT NULL
  AND (p.category_id IS NULL OR c.parent_id = c.category_id);

-- A4. Walk the tree from top-level categories; count per depth + unreachable.
--     Unreachable = in a loop or under a missing parent (a FK can't catch loops).
WITH RECURSIVE tree AS (
    SELECT category_id, 1 AS depth, ARRAY[category_id] AS path
    FROM categories
    WHERE parent_id IS NULL
  UNION ALL
    SELECT c.category_id, t.depth + 1, t.path || c.category_id
    FROM categories c
    JOIN tree t ON c.parent_id = t.category_id
    WHERE c.category_id <> ALL (t.path)          -- loop guard
)
SELECT 'depth ' || depth AS level, count(*) AS categories
FROM tree GROUP BY depth
UNION ALL
SELECT 'unreachable', count(*)
FROM categories WHERE category_id NOT IN (SELECT category_id FROM tree)
ORDER BY level;

-- A5. List the unreachable categories (same walk as A4).
WITH RECURSIVE tree AS (
    SELECT category_id, ARRAY[category_id] AS path
    FROM categories WHERE parent_id IS NULL
  UNION ALL
    SELECT c.category_id, t.path || c.category_id
    FROM categories c JOIN tree t ON c.parent_id = t.category_id
    WHERE c.category_id <> ALL (t.path)          -- loop guard
)
SELECT category_id, category_name, parent_id
FROM categories
WHERE category_id NOT IN (SELECT category_id FROM tree)
ORDER BY category_id;
