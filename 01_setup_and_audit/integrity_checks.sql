-- 01_setup_and_audit/integrity_checks.sql
-- Purpose: Read-only audit suite for the Kloud Kart operational database.
--          1) Single-pass UNION ALL summary of integrity & reconciliation checks.
--          2) Quantified business impact queries (revenue, stock drift, Top-100, hierarchy).
--          3) Verification of intentional / benign patterns ("Looked wrong, is not wrong").
-- Safety:  Strictly read-only SELECT queries. Re-runnable before and after Phase 2 remediation.

-- ============================================================================
-- SECTION 1: SINGLE-PASS INTEGRITY & RECONCILIATION SUMMARY
-- ============================================================================
WITH RECURSIVE
cat_walk AS (
    SELECT category_id,
           parent_id,
           ARRAY[category_id] AS path,
           false AS is_cycle
    FROM categories
    UNION ALL
    SELECT c.category_id,
           c.parent_id,
           w.path || c.category_id,
           c.category_id = ANY(w.path)
    FROM categories c
    JOIN cat_walk w ON c.parent_id = w.category_id AND NOT w.is_cycle
),
order_calc AS (
    SELECT order_id,
           sum(quantity * coalesce(unit_price, 0)) AS calc_total
    FROM order_items
    GROUP BY order_id
),
inv_calc AS (
    SELECT product_id,
           sum(change_qty) AS net_change
    FROM inventory_log
    GROUP BY product_id
)
SELECT check_id, integrity_type, check_name, violation_count
FROM (
    -- Referential integrity (missing FOREIGN KEYs)
    SELECT 1  AS sort_ord, 'CHK-01' AS check_id, 'Referential' AS integrity_type,
           'categories.parent_id points to non-existent category' AS check_name,
           (SELECT count(*) FROM categories c LEFT JOIN categories p ON p.category_id = c.parent_id
            WHERE c.parent_id IS NOT NULL AND p.category_id IS NULL) AS violation_count
    UNION ALL
    SELECT 2,  'CHK-02', 'Referential',
           'products.category_id points to non-existent category',
           (SELECT count(*) FROM products p LEFT JOIN categories c ON c.category_id = p.category_id
            WHERE p.category_id IS NOT NULL AND c.category_id IS NULL)
    UNION ALL
    SELECT 3,  'CHK-03', 'Referential',
           'orders.customer_id NULL or missing in customers',
           (SELECT count(*) FROM orders o LEFT JOIN customers c ON c.customer_id = o.customer_id
            WHERE o.customer_id IS NULL OR c.customer_id IS NULL)
    UNION ALL
    SELECT 4,  'CHK-04', 'Referential',
           'order_items.order_id NULL or missing in orders',
           (SELECT count(*) FROM order_items oi LEFT JOIN orders o ON o.order_id = oi.order_id
            WHERE oi.order_id IS NULL OR o.order_id IS NULL)
    UNION ALL
    SELECT 5,  'CHK-05', 'Referential',
           'order_items.product_id NULL or missing in products',
           (SELECT count(*) FROM order_items oi LEFT JOIN products p ON p.product_id = oi.product_id
            WHERE oi.product_id IS NULL OR p.product_id IS NULL)
    UNION ALL
    SELECT 6,  'CHK-06', 'Referential',
           'inventory_log.product_id NULL or missing in products',
           (SELECT count(*) FROM inventory_log il LEFT JOIN products p ON p.product_id = il.product_id
            WHERE il.product_id IS NULL OR p.product_id IS NULL)

    -- Entity & hierarchy integrity (missing UNIQUE / tree guards)
    UNION ALL
    SELECT 7,  'CHK-07', 'Entity',
           'customers duplicate normalized email groups (lower(trim(email)))',
           (SELECT count(*) FROM (
               SELECT lower(trim(email)) FROM customers
               WHERE email IS NOT NULL AND trim(email) <> ''
               GROUP BY 1 HAVING count(*) > 1
           ) t)
    UNION ALL
    SELECT 8,  'CHK-08', 'Entity',
           'customers extra duplicate rows beyond one per normalized email',
           (SELECT coalesce(sum(cnt - 1), 0) FROM (
               SELECT count(*) AS cnt FROM customers
               WHERE email IS NOT NULL AND trim(email) <> ''
               GROUP BY lower(trim(email)) HAVING count(*) > 1
           ) t)
    UNION ALL
    SELECT 9,  'CHK-09', 'Entity/Hierarchy',
           'categories participating in parent_id cycles',
           (SELECT count(DISTINCT category_id) FROM cat_walk WHERE is_cycle)

    -- Domain & range integrity (missing CHECK / NOT NULL / enum constraints)
    UNION ALL
    SELECT 10, 'CHK-10', 'Domain',
           'orders.status non-canonical (whitespace, mixed case, or US/UK spelling)',
           (SELECT count(*) FROM orders
            WHERE status IS DISTINCT FROM lower(trim(status))
               OR lower(trim(status)) IN ('complete', 'canceled'))
    UNION ALL
    SELECT 11, 'CHK-11', 'Domain',
           'products with negative stock_quantity (< 0)',
           (SELECT count(*) FROM products WHERE stock_quantity < 0)
    UNION ALL
    SELECT 12, 'CHK-12', 'Domain',
           'order_items with NULL or non-positive unit_price (<= 0)',
           (SELECT count(*) FROM order_items WHERE unit_price IS NULL OR unit_price <= 0)
    UNION ALL
    SELECT 13, 'CHK-13', 'Domain',
           'order_items with NULL or non-positive quantity (<= 0)',
           (SELECT count(*) FROM order_items WHERE quantity IS NULL OR quantity <= 0)
    UNION ALL
    SELECT 14, 'CHK-14', 'Domain',
           'orders with future order_date beyond extract cutoff (2026-08-31)',
           (SELECT count(*) FROM orders WHERE order_date >= timestamp '2026-09-01')
    UNION ALL
    SELECT 15, 'CHK-15', 'Domain',
           'inventory_log rows with wrong sign for reason (sale/damage > 0 or restock/return < 0)',
           (SELECT count(*) FROM inventory_log
            WHERE (reason IN ('sale', 'damage') AND change_qty >= 0)
               OR (reason IN ('restock', 'return') AND change_qty <= 0)
               OR change_qty IS NULL)

    -- Cross-table reconciliation
    UNION ALL
    SELECT 16, 'CHK-16', 'Reconciliation',
           'orders where total_amount differs from sum(order_items) by > 0.01',
           (SELECT count(*) FROM orders o
            JOIN order_calc oc ON oc.order_id = o.order_id
            WHERE abs(o.total_amount - oc.calc_total) > 0.01)
    UNION ALL
    SELECT 17, 'CHK-17', 'Reconciliation',
           'orders with zero matching order_items rows',
           (SELECT count(*) FROM orders o
            LEFT JOIN order_items oi ON oi.order_id = o.order_id
            WHERE oi.order_item_id IS NULL)
    UNION ALL
    SELECT 18, 'CHK-18', 'Reconciliation',
           'products where stock_quantity <> coalesce(sum(inventory_log.change_qty), 0)',
           (SELECT count(*) FROM products p
            LEFT JOIN inv_calc ic ON ic.product_id = p.product_id
            WHERE p.stock_quantity <> coalesce(ic.net_change, 0))
) checks
ORDER BY sort_ord;

-- ============================================================================
-- SECTION 2: BUSINESS IMPACT QUANTIFICATION
-- ============================================================================

-- Q1: Baseline revenue & order counts across raw vs canonical order statuses
SELECT
    count(*) AS total_orders,
    round(sum(total_amount), 2) AS gross_order_total_all_statuses,
    round(sum(total_amount) FILTER (WHERE status = 'completed'), 2) AS naive_exact_completed_rev,
    count(*) FILTER (WHERE status = 'completed') AS naive_exact_completed_cnt,
    round(sum(total_amount) FILTER (WHERE lower(trim(status)) IN ('completed', 'complete', 'shipped')), 2) AS canonical_fulfilled_rev,
    count(*) FILTER (WHERE lower(trim(status)) IN ('completed', 'complete', 'shipped')) AS canonical_fulfilled_cnt
FROM orders;

-- Q2: Stock ledger drift vs products.stock_quantity
WITH inv_calc AS (
    SELECT product_id, sum(change_qty) AS net_log
    FROM inventory_log
    GROUP BY product_id
)
SELECT
    count(*) AS mismatched_products,
    sum(abs(p.stock_quantity - coalesce(ic.net_log, 0))) AS abs_unit_drift,
    sum(p.stock_quantity - coalesce(ic.net_log, 0)) AS net_unit_drift,
    round(sum(abs(p.stock_quantity - coalesce(ic.net_log, 0)) * p.price), 2) AS abs_inventory_value_drift
FROM products p
LEFT JOIN inv_calc ic ON ic.product_id = p.product_id
WHERE p.stock_quantity <> coalesce(ic.net_log, 0);

-- Q3: Negative stock exposure
SELECT
    count(*) AS negative_stock_products,
    sum(stock_quantity) AS total_negative_units,
    min(stock_quantity) AS min_stock_quantity,
    (SELECT count(DISTINCT oi.order_id)
     FROM order_items oi
     JOIN products p ON p.product_id = oi.product_id
     WHERE p.stock_quantity < 0) AS orders_touching_neg_products
FROM products
WHERE stock_quantity < 0;

-- Q4: Order total vs order_items discrepancy & NULL/zero unit_price impact
WITH oi_sum AS (
    SELECT order_id,
           sum(quantity * coalesce(unit_price, 0)) AS calc_total,
           bool_or(unit_price IS NULL) AS has_null_price,
           bool_or(unit_price = 0) AS has_zero_price
    FROM order_items
    GROUP BY order_id
)
SELECT
    has_null_price,
    has_zero_price,
    count(*) AS mismatched_orders,
    round(sum(o.total_amount - s.calc_total), 2) AS net_diff,
    round(sum(abs(o.total_amount - s.calc_total)), 2) AS abs_diff
FROM orders o
JOIN oi_sum s ON s.order_id = o.order_id
WHERE abs(o.total_amount - s.calc_total) > 0.01
GROUP BY has_null_price, has_zero_price
ORDER BY mismatched_orders DESC;

-- Q5: Orphan records financial & unit impact
SELECT 'orders_missing_customer' AS orphan_type,
       count(*) AS row_count,
       round(sum(o.total_amount), 2) AS gross_amount,
       round(sum(o.total_amount) FILTER (WHERE lower(trim(o.status)) IN ('completed', 'complete', 'shipped')), 2) AS fulfilled_amount
FROM orders o
LEFT JOIN customers c ON c.customer_id = o.customer_id
WHERE o.customer_id IS NULL OR c.customer_id IS NULL
UNION ALL
SELECT 'order_items_missing_order',
       count(*),
       round(coalesce(sum(oi.quantity * coalesce(oi.unit_price, 0)), 0), 2),
       NULL
FROM order_items oi
LEFT JOIN orders o ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL OR o.order_id IS NULL;

SELECT 'inventory_log_missing_product' AS orphan_type,
       count(*) AS row_count,
       sum(abs(il.change_qty)) AS abs_units,
       sum(il.change_qty) AS net_units
FROM inventory_log il
LEFT JOIN products p ON p.product_id = il.product_id
WHERE il.product_id IS NULL OR p.product_id IS NULL;

-- Q6: Duplicate customer email distortion on distinct count and Top-100 ranking
WITH dup_emails AS (
    SELECT lower(trim(email)) AS norm_email, count(*) AS acct_cnt
    FROM customers
    WHERE email IS NOT NULL AND trim(email) <> ''
    GROUP BY 1
    HAVING count(*) > 1
),
merged_top100 AS (
    SELECT lower(trim(c.email)) AS norm_email,
           coalesce(sum(o.total_amount) FILTER (WHERE lower(trim(o.status)) IN ('completed', 'complete', 'shipped')), 0) AS spend
    FROM customers c
    LEFT JOIN orders o ON o.customer_id = c.customer_id
    GROUP BY 1
    ORDER BY 2 DESC
    LIMIT 100
),
unmerged_top100 AS (
    SELECT c.customer_id,
           lower(trim(c.email)) AS norm_email,
           coalesce(sum(o.total_amount) FILTER (WHERE lower(trim(o.status)) IN ('completed', 'complete', 'shipped')), 0) AS spend
    FROM customers c
    LEFT JOIN orders o ON o.customer_id = c.customer_id
    GROUP BY 1, 2
    ORDER BY 3 DESC
    LIMIT 100
)
SELECT
    (SELECT count(*) FROM dup_emails) AS duplicate_email_groups,
    (SELECT sum(acct_cnt) FROM dup_emails) AS total_rows_in_dup_groups,
    (SELECT sum(acct_cnt - 1) FROM dup_emails) AS overstated_customer_count,
    (SELECT count(*) FROM merged_top100 m WHERE m.norm_email NOT IN (SELECT norm_email FROM unmerged_top100)) AS top100_displaced_customers,
    (SELECT round(sum(o.total_amount) FILTER (WHERE lower(trim(o.status)) IN ('completed', 'complete', 'shipped')), 2)
     FROM orders o
     JOIN customers c ON c.customer_id = o.customer_id
     WHERE lower(trim(c.email)) IN (SELECT norm_email FROM dup_emails)) AS fulfilled_spend_across_dup_accounts;

-- Q7: Category cycle & orphan parent impact on product counts & stock
WITH RECURSIVE cat_walk AS (
    SELECT category_id, category_name, parent_id, ARRAY[category_id] AS path, false AS is_cycle
    FROM categories
    UNION ALL
    SELECT c.category_id, c.category_name, c.parent_id, w.path || c.category_id, c.category_id = ANY(w.path)
    FROM categories c
    JOIN cat_walk w ON c.parent_id = w.category_id AND NOT w.is_cycle
),
bad_cats AS (
    SELECT DISTINCT category_id, 'cycle' AS issue FROM cat_walk WHERE is_cycle
    UNION ALL
    SELECT c.category_id, 'orphan_parent' FROM categories c
    LEFT JOIN categories p ON p.category_id = c.parent_id
    WHERE c.parent_id IS NOT NULL AND p.category_id IS NULL
)
SELECT bc.category_id, c.category_name, c.parent_id, bc.issue,
       count(p.product_id) AS direct_products,
       coalesce(sum(p.stock_quantity), 0) AS direct_stock_units
FROM bad_cats bc
JOIN categories c ON c.category_id = bc.category_id
LEFT JOIN products p ON p.category_id = bc.category_id
GROUP BY bc.category_id, c.category_name, c.parent_id, bc.issue
ORDER BY bc.category_id;

-- Q8: Post-cutoff / future order dates beyond 2026-08-31
SELECT
    count(*) FILTER (WHERE order_date >= timestamp '2026-09-01') AS post_aug2026_orders,
    count(*) FILTER (WHERE order_date > now()) AS strictly_future_orders,
    round(coalesce(sum(total_amount) FILTER (WHERE order_date >= timestamp '2026-09-01'), 0), 2) AS post_aug2026_amount,
    min(order_date) FILTER (WHERE order_date >= timestamp '2026-09-01') AS first_post_aug2026,
    max(order_date) AS max_order_date
FROM orders;

-- ============================================================================
-- SECTION 3: LOOKED WRONG, IS NOT WRONG (VERIFICATION)
-- ============================================================================

-- V1: inventory_log sign conventions and stock_take checkpoints
SELECT reason,
       count(*) AS total_rows,
       count(*) FILTER (WHERE change_qty > 0) AS positive_rows,
       count(*) FILTER (WHERE change_qty = 0) AS zero_rows,
       count(*) FILTER (WHERE change_qty < 0) AS negative_rows
FROM inventory_log
GROUP BY reason
ORDER BY total_rows DESC;

-- V2: Uncategorised products (products.category_id IS NULL)
SELECT count(*) AS uncategorised_products,
       coalesce(sum(stock_quantity), 0) AS total_stock,
       count(*) FILTER (WHERE stock_quantity <= 5) AS low_stock_count
FROM products
WHERE category_id IS NULL;

-- V3: Customer timestamp ties (zero ties confirmed -> deterministic running totals)
SELECT count(*) AS customer_timestamp_tie_groups
FROM (
    SELECT customer_id, order_date
    FROM orders
    WHERE customer_id IS NOT NULL
    GROUP BY customer_id, order_date
    HAVING count(*) > 1
) t;
