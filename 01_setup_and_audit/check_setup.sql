-- 01_setup_and_audit/check_setup.sql
-- Purpose: Verify PostgreSQL 18 runtime, connection headroom (>= 500 for race_test.py),
--          and expected row counts from a fresh Kloud Kart extract load.
-- Safety:  Read-only checks + assertions; does not modify schema or data.

SELECT version() AS server_version;

SHOW max_connections;

SELECT 'categories'    AS table_name, count(*) AS row_count FROM categories
UNION ALL
SELECT 'products'      AS table_name, count(*) AS row_count FROM products
UNION ALL
SELECT 'customers'     AS table_name, count(*) AS row_count FROM customers
UNION ALL
SELECT 'orders'        AS table_name, count(*) AS row_count FROM orders
UNION ALL
SELECT 'order_items'   AS table_name, count(*) AS row_count FROM order_items
UNION ALL
SELECT 'inventory_log' AS table_name, count(*) AS row_count FROM inventory_log
ORDER BY table_name;

-- Guard assertions before proceeding to audit or remediation
DO $$
DECLARE
    v_max_conn integer;
    v_ver_num  integer;
    v_empty    text;
BEGIN
    v_ver_num := current_setting('server_version_num')::integer;
    IF v_ver_num < 180000 THEN
        RAISE EXCEPTION 'Expected PostgreSQL 18+, found %', version();
    END IF;

    v_max_conn := current_setting('max_connections')::integer;
    IF v_max_conn < 500 THEN
        RAISE EXCEPTION 'max_connections is %, expected >= 500 for 400-buyer flash-sale test', v_max_conn;
    END IF;

    SELECT string_agg(tbl, ', ')
    INTO v_empty
    FROM (
        SELECT 'categories' AS tbl WHERE NOT EXISTS (SELECT 1 FROM categories)
        UNION ALL SELECT 'products'      WHERE NOT EXISTS (SELECT 1 FROM products)
        UNION ALL SELECT 'customers'     WHERE NOT EXISTS (SELECT 1 FROM customers)
        UNION ALL SELECT 'orders'        WHERE NOT EXISTS (SELECT 1 FROM orders)
        UNION ALL SELECT 'order_items'   WHERE NOT EXISTS (SELECT 1 FROM order_items)
        UNION ALL SELECT 'inventory_log' WHERE NOT EXISTS (SELECT 1 FROM inventory_log)
    ) t;

    IF v_empty IS NOT NULL THEN
        RAISE EXCEPTION 'Base data extract not loaded; empty table(s): %', v_empty;
    END IF;

    RAISE NOTICE 'Setup check passed: PostgreSQL %, max_connections = %, all 6 tables populated.',
        current_setting('server_version'), v_max_conn;
END $$;
