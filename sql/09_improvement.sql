-- 09_improvement.sql
-- Purpose: cancel_order(), which puts stock back when an order is cancelled (improvement.md).
-- Usage:   SELECT * FROM cancel_order(1000123);

-- Why: place_order now takes stock the moment an order is placed. Without this, a cancelled
-- order would keep its stock forever and the shop would slowly "lose" stock it still has.
-- It returns exactly what the log says this order took, so old orders that never took stock
-- (all orders before the new place_order) get nothing back by mistake.
CREATE OR REPLACE FUNCTION cancel_order(p_order_id bigint)
RETURNS TABLE (success boolean, message text)
LANGUAGE plpgsql AS $$
DECLARE
    v_status text;
BEGIN
    -- 1. Lock the order so two cancellations can't both return the stock.
    SELECT o.status INTO v_status
    FROM orders o WHERE o.order_id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT false, 'Order not found'::text;
        RETURN;
    END IF;
    IF v_status NOT IN ('completed', 'pending') THEN
        RETURN QUERY SELECT false, ('Order cannot be cancelled: it is ' || v_status)::text;
        RETURN;
    END IF;

    -- 2. Tell the audit trigger this is a return for this order, then give the stock back.
    PERFORM set_config('kloudkart.reason',   'return',           true);
    PERFORM set_config('kloudkart.order_id', p_order_id::text,   true);

    UPDATE products p
    SET stock_quantity = p.stock_quantity + taken.units
    FROM (SELECT l.product_id, -sum(l.change_qty) AS units
          FROM inventory_log l
          WHERE l.order_id = p_order_id AND l.reason = 'sale'
          GROUP BY l.product_id) taken
    WHERE p.product_id = taken.product_id;

    -- 3. Mark the order cancelled. Same transaction: stock and status change together.
    UPDATE orders SET status = 'cancelled' WHERE order_id = p_order_id;

    RETURN QUERY SELECT true, 'Order cancelled; stock returned'::text;
END;
$$;
