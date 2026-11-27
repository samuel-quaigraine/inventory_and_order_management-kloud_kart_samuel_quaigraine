-- 04_place_order.sql
-- Purpose: place_order(), the function the shop (and race_test.py) calls to buy a product (ADR-001).
-- The stock movement is written to inventory_log by the audit trigger in 05_audit_trail.sql.

-- How it stops overselling: the stock check and the stock change are ONE statement:
--   UPDATE products SET stock = stock - qty WHERE product_id = ... AND stock >= qty
-- Postgres locks the row while it updates it. A second buyer waits, then re-checks
-- "stock >= qty" against the NEW stock, so the last unit can only be sold once.
CREATE OR REPLACE FUNCTION place_order(p_customer_id bigint, p_product_id bigint, p_quantity integer)
RETURNS TABLE (success boolean, order_id bigint, message text)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE
    v_price    numeric(12,2);
    v_order_id bigint;
BEGIN
    -- 1. Refuse bad requests up front, with a clear message instead of an error.
    IF p_quantity IS NULL OR p_quantity NOT BETWEEN 1 AND 100 THEN
        RETURN QUERY SELECT false, NULL::bigint, 'Quantity must be between 1 and 100'::text;
        RETURN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM customers c WHERE c.customer_id = p_customer_id) THEN
        RETURN QUERY SELECT false, NULL::bigint, 'Unknown customer'::text;
        RETURN;
    END IF;

    -- 2. Reserve the order number, and tell the audit trigger why stock is about to change.
    --    set_config(..., true) lasts only until this order's transaction ends.
    v_order_id := nextval('orders_order_id_seq');
    PERFORM set_config('kloudkart.reason',   'sale',              true);
    PERFORM set_config('kloudkart.order_id', v_order_id::text,    true);

    -- 3. Check and take the stock in one step (see the comment at the top).
    UPDATE products p
    SET stock_quantity = p.stock_quantity - p_quantity
    WHERE p.product_id = p_product_id
      AND p.stock_quantity >= p_quantity
    RETURNING p.price INTO v_price;

    -- 4. No row updated = not enough stock (or no such product): an instant, clear refusal.
    IF NOT FOUND THEN
        RETURN QUERY SELECT false, NULL::bigint, 'Out of stock'::text;
        RETURN;
    END IF;

    -- 5. Record the order and its line. Same transaction as step 3: all of it happens, or none of it.
    INSERT INTO orders (order_id, customer_id, order_date, status, total_amount)
    VALUES (v_order_id, p_customer_id, now(), 'completed', v_price * p_quantity);

    INSERT INTO order_items (order_id, product_id, quantity, unit_price)
    VALUES (v_order_id, p_product_id, p_quantity, v_price);

    RETURN QUERY SELECT true, v_order_id, 'Order placed'::text;
END;
$$;
