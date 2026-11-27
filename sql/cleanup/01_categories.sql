-- cleanup/01_categories.sql
-- Categories: make every category reachable from the top of the tree (F-07).

-- Any category the tree walk cannot reach (in a loop, or under a missing parent) becomes top-level.
-- Fixes Seasonal Promotions <-> Promotions (loop) and Clearance -> 8999 (missing parent) with one rule.
WITH RECURSIVE tree AS (
    SELECT category_id, ARRAY[category_id] AS path
    FROM categories WHERE parent_id IS NULL
  UNION ALL
    SELECT c.category_id, t.path || c.category_id
    FROM categories c JOIN tree t ON c.parent_id = t.category_id
    WHERE c.category_id <> ALL (t.path)          -- loop guard
)
UPDATE categories
SET parent_id = NULL
WHERE category_id NOT IN (SELECT category_id FROM tree);
