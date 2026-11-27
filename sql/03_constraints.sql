-- 03_constraints.sql
-- Purpose: Lock the cleaned data in. Data types, id generators, NOT NULL, CHECK, UNIQUE, foreign keys.
-- Each rule is dropped first if it exists, so the file can be re-run.
-- One transaction: all rules are added, or none.

BEGIN;

-- ===== Data types =====

-- Dates get a time zone (customers in Ghana and Nigeria). Existing values are Ghana time (UTC+0).
ALTER TABLE products      ALTER COLUMN created_at    TYPE timestamptz USING created_at::timestamp    AT TIME ZONE 'Africa/Accra';
ALTER TABLE customers     ALTER COLUMN registered_at TYPE timestamptz USING registered_at::timestamp AT TIME ZONE 'Africa/Accra';
ALTER TABLE orders        ALTER COLUMN order_date    TYPE timestamptz USING order_date::timestamp    AT TIME ZONE 'Africa/Accra';
ALTER TABLE inventory_log ALTER COLUMN created_at    TYPE timestamptz USING created_at::timestamp    AT TIME ZONE 'Africa/Accra';

-- Kept as they are: integer ids (room for 2 billion), numeric(12,2) for money (exact, no rounding),
-- text + CHECK for status (easier to extend than an enum).

-- ===== Id generators =====

-- None of these tables could create its own ids. Orders start above 999,862, the highest
-- quarantined orphan order id, so a quarantined row can never clash with a new one (F-04).
CREATE SEQUENCE IF NOT EXISTS orders_order_id_seq           START 1000000;
CREATE SEQUENCE IF NOT EXISTS order_items_order_item_id_seq START 2000000;
CREATE SEQUENCE IF NOT EXISTS inventory_log_log_id_seq      START 2000000;

ALTER TABLE orders        ALTER COLUMN order_id      SET DEFAULT nextval('orders_order_id_seq');
ALTER TABLE order_items   ALTER COLUMN order_item_id SET DEFAULT nextval('order_items_order_item_id_seq');
ALTER TABLE inventory_log ALTER COLUMN log_id        SET DEFAULT nextval('inventory_log_log_id_seq');
ALTER TABLE inventory_log ALTER COLUMN created_at    SET DEFAULT now();

-- ===== categories =====

-- Every category needs a name; a parent must be a real category (NULL = top level).
-- A foreign key cannot stop loops; the rollup's loop guard handles that (ADR-004).
ALTER TABLE categories ALTER COLUMN category_name SET NOT NULL;
ALTER TABLE categories
    DROP CONSTRAINT IF EXISTS categories_parent_fk,
    ADD  CONSTRAINT categories_parent_fk FOREIGN KEY (parent_id) REFERENCES categories (category_id);

-- ===== customers =====

-- Name and email required; emails stored trimmed and lowercase so duplicates can't hide (F-13).
ALTER TABLE customers ALTER COLUMN full_name SET NOT NULL;
ALTER TABLE customers ALTER COLUMN email     SET NOT NULL;
ALTER TABLE customers
    DROP CONSTRAINT IF EXISTS customers_email_clean_chk,
    ADD  CONSTRAINT customers_email_clean_chk CHECK (email = lower(trim(email)));

-- ===== products =====

-- Name, price and stock required; category stays optional (race_test.py inserts products without one).
-- Stock can never go below zero: the safety net under place_order (F-02).
ALTER TABLE products ALTER COLUMN product_name   SET NOT NULL;
ALTER TABLE products ALTER COLUMN price          SET NOT NULL;
ALTER TABLE products ALTER COLUMN stock_quantity SET NOT NULL;
ALTER TABLE products
    DROP CONSTRAINT IF EXISTS products_price_chk,
    ADD  CONSTRAINT products_price_chk CHECK (price > 0),
    DROP CONSTRAINT IF EXISTS products_stock_chk,
    ADD  CONSTRAINT products_stock_chk CHECK (stock_quantity >= 0),
    DROP CONSTRAINT IF EXISTS products_category_fk,
    ADD  CONSTRAINT products_category_fk FOREIGN KEY (category_id) REFERENCES categories (category_id);

-- ===== orders =====

-- Every order belongs to a real customer, has a date, one of 5 statuses, and a total of 0 or more.
ALTER TABLE orders ALTER COLUMN customer_id  SET NOT NULL;
ALTER TABLE orders ALTER COLUMN order_date   SET NOT NULL;
ALTER TABLE orders ALTER COLUMN status       SET NOT NULL;
ALTER TABLE orders ALTER COLUMN total_amount SET NOT NULL;
ALTER TABLE orders
    DROP CONSTRAINT IF EXISTS orders_status_chk,
    ADD  CONSTRAINT orders_status_chk
         CHECK (status IN ('completed', 'pending', 'shipped', 'cancelled', 'refunded')),
    DROP CONSTRAINT IF EXISTS orders_total_chk,
    ADD  CONSTRAINT orders_total_chk CHECK (total_amount >= 0),
    DROP CONSTRAINT IF EXISTS orders_customer_fk,
    ADD  CONSTRAINT orders_customer_fk FOREIGN KEY (customer_id) REFERENCES customers (customer_id);

-- ===== order_items =====

-- Every line belongs to a real order and product, with a sane quantity and a price.
-- One line per product per order stops the double-insert bug (F-03).
ALTER TABLE order_items ALTER COLUMN order_id   SET NOT NULL;
ALTER TABLE order_items ALTER COLUMN product_id SET NOT NULL;
ALTER TABLE order_items ALTER COLUMN quantity   SET NOT NULL;
ALTER TABLE order_items ALTER COLUMN unit_price SET NOT NULL;
ALTER TABLE order_items
    DROP CONSTRAINT IF EXISTS order_items_quantity_chk,
    ADD  CONSTRAINT order_items_quantity_chk CHECK (quantity BETWEEN 1 AND 100),
    DROP CONSTRAINT IF EXISTS order_items_price_chk,
    ADD  CONSTRAINT order_items_price_chk CHECK (unit_price >= 0),
    DROP CONSTRAINT IF EXISTS order_items_order_product_uq,
    ADD  CONSTRAINT order_items_order_product_uq UNIQUE (order_id, product_id),
    DROP CONSTRAINT IF EXISTS order_items_order_fk,
    ADD  CONSTRAINT order_items_order_fk   FOREIGN KEY (order_id)   REFERENCES orders (order_id),
    DROP CONSTRAINT IF EXISTS order_items_product_fk,
    ADD  CONSTRAINT order_items_product_fk FOREIGN KEY (product_id) REFERENCES products (product_id);

-- ===== inventory_log =====

-- Every movement belongs to a real product, has one of 6 reasons, and moves stock the right way:
-- sale/damage out, restock/return in, correction either way, stock_take none.
ALTER TABLE inventory_log ALTER COLUMN product_id SET NOT NULL;
ALTER TABLE inventory_log ALTER COLUMN change_qty SET NOT NULL;
ALTER TABLE inventory_log ALTER COLUMN reason     SET NOT NULL;
ALTER TABLE inventory_log ALTER COLUMN created_at SET NOT NULL;
ALTER TABLE inventory_log
    DROP CONSTRAINT IF EXISTS inventory_log_reason_chk,
    ADD  CONSTRAINT inventory_log_reason_chk CHECK (
         (reason IN ('sale', 'damage')     AND change_qty < 0) OR
         (reason IN ('restock', 'return')  AND change_qty > 0) OR
         (reason = 'correction'            AND change_qty <> 0) OR
         (reason = 'stock_take'            AND change_qty = 0)),
    DROP CONSTRAINT IF EXISTS inventory_log_product_fk,
    ADD  CONSTRAINT inventory_log_product_fk FOREIGN KEY (product_id) REFERENCES products (product_id);

COMMIT;
