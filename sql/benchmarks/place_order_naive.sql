-- benchmarks/place_order_naive.sql
-- DEMONSTRATION ONLY, not part of the solution (not run by 00_run_all.sql).
-- Recreates how the app places an order today, so race_test.py can show the oversell.
-- 04_place_order.sql replaces this function with the correct version.

-- Id generators: none of these tables has one.
-- Orders start above 999,862, the highest orphan order id (finding F-04).
CREATE SEQUENCE IF NOT EXISTS orders_order_id_seq           START 1000000;
CREATE SEQUENCE IF NOT EXISTS order_items_order_item_id_seq START 2000000;
CREATE SEQUENCE IF NOT EXISTS inventory_log_log_id_seq      START 2000000;

-- Naive order placement: read stock, check it, then write back a value worked out from that read.
-- Bug: two buyers can read the same stock before either writes, so both succeed.
CREATE OR REPLACE FUNCTION place_order(p_customer_id bigint, p_product_id bigint, p_quantity integer)
RETURNS TABLE (success boolean, order_id bigint, message text)
LANGUAGE plpgsql AS $$
DECLARE
    v_stock    integer;
    v_price    numeric(12,2);
    v_order_id bigint;
BEGIN
    -- Step 1: read the current stock (no lock, like a plain app query).
    SELECT p.stock_quantity, p.price INTO v_stock, v_price
    FROM products p WHERE p.product_id = p_product_id;

    -- Step 2: check it.
    IF v_stock IS NULL OR v_stock < p_quantity THEN
        RETURN QUERY SELECT false, NULL::bigint, 'Out of stock'::text;
        RETURN;
    END IF;

    -- Step 3: write back the new stock, worked out from the value read in step 1.
    UPDATE products SET stock_quantity = v_stock - p_quantity
    WHERE product_id = p_product_id;

    -- Step 4: record the order, its line and the stock movement.
    v_order_id := nextval('orders_order_id_seq');
    INSERT INTO orders (order_id, customer_id, order_date, status, total_amount)
    VALUES (v_order_id, p_customer_id, now(), 'completed', v_price * p_quantity);

    INSERT INTO order_items (order_item_id, order_id, product_id, quantity, unit_price)
    VALUES (nextval('order_items_order_item_id_seq'), v_order_id, p_product_id, p_quantity, v_price);

    INSERT INTO inventory_log (log_id, product_id, change_qty, reason, created_at, note)
    VALUES (nextval('inventory_log_log_id_seq'), p_product_id, -p_quantity, 'sale', now(), NULL);

    RETURN QUERY SELECT true, v_order_id, 'Order placed'::text;
END;
$$;
