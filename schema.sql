-- schema.sql
-- Kloud Kart: the FINAL schema, after the fixes. The original, as delivered, is in given/schema.sql.
--
-- Use it to build an empty, correct database (for example a new shop with no old data).
-- To build the database FROM THE CSV FILES, run load.sql instead: the old data breaks these
-- rules, so it must be loaded into the original schema and cleaned first (sql/02 and sql/03).
-- Behaviour (place_order, audit triggers, report, rollup, cancel_order) is in sql/04 to sql/09.

DROP TABLE IF EXISTS inventory_log_archive, inventory_log_quarantine, order_items_quarantine,
                     orders_quarantine, order_items, orders, inventory_log, products, customers,
                     categories CASCADE;
DROP SEQUENCE IF EXISTS orders_order_id_seq, order_items_order_item_id_seq, inventory_log_log_id_seq;

-- ===== Id generators =====

-- Orders start above the highest old order id (999,862), so old and new ids never clash.
CREATE SEQUENCE orders_order_id_seq           START 1000000;
CREATE SEQUENCE order_items_order_item_id_seq START 2000000;
CREATE SEQUENCE inventory_log_log_id_seq      START 2000000;

-- ===== categories =====

-- The whole tree in one table: each category points to its parent (NULL = top level).
CREATE TABLE categories (
    category_id   integer PRIMARY KEY,
    category_name text    NOT NULL,
    parent_id     integer CONSTRAINT categories_parent_fk REFERENCES categories (category_id)
);

-- ===== customers =====

-- Emails are stored trimmed and lowercase, so duplicates can't hide behind formatting.
-- Email is not unique: 533 groups share one and were deliberately not merged (ADR-005).
CREATE TABLE customers (
    customer_id   integer     PRIMARY KEY,
    full_name     text        NOT NULL,
    email         text        NOT NULL CONSTRAINT customers_email_clean_chk CHECK (email = lower(trim(email))),
    phone         text,
    city          text,
    registered_at timestamptz
);

-- ===== products =====

-- Category is optional (race_test.py adds products without one). Stock can never go below zero.
CREATE TABLE products (
    product_id     integer       PRIMARY KEY,
    product_name   text          NOT NULL,
    category_id    integer       CONSTRAINT products_category_fk REFERENCES categories (category_id),
    price          numeric(12,2) NOT NULL CONSTRAINT products_price_chk CHECK (price > 0),
    stock_quantity integer       NOT NULL CONSTRAINT products_stock_chk CHECK (stock_quantity >= 0),
    created_at     timestamptz
);

-- ===== orders =====

-- Every order has a real customer, a date with a time zone, one of 5 statuses, and a total >= 0.
CREATE TABLE orders (
    order_id     integer       PRIMARY KEY DEFAULT nextval('orders_order_id_seq'),
    customer_id  integer       NOT NULL CONSTRAINT orders_customer_fk REFERENCES customers (customer_id),
    order_date   timestamptz   NOT NULL,
    status       text          NOT NULL CONSTRAINT orders_status_chk
                               CHECK (status IN ('completed', 'pending', 'shipped', 'cancelled', 'refunded')),
    total_amount numeric(12,2) NOT NULL CONSTRAINT orders_total_chk CHECK (total_amount >= 0)
);

-- ===== order_items =====

-- One line per product per order (stops the double-insert bug). Quantity 1-100, price required.
CREATE TABLE order_items (
    order_item_id integer       PRIMARY KEY DEFAULT nextval('order_items_order_item_id_seq'),
    order_id      integer       NOT NULL CONSTRAINT order_items_order_fk   REFERENCES orders (order_id),
    product_id    integer       NOT NULL CONSTRAINT order_items_product_fk REFERENCES products (product_id),
    quantity      integer       NOT NULL CONSTRAINT order_items_quantity_chk CHECK (quantity BETWEEN 1 AND 100),
    unit_price    numeric(12,2) NOT NULL CONSTRAINT order_items_price_chk    CHECK (unit_price >= 0),
    CONSTRAINT order_items_order_product_uq UNIQUE (order_id, product_id)
);

-- ===== inventory_log =====

-- Every stock movement: which product, how much, why, when, which order, and who.
-- The sign must match the reason: sale/damage out, restock/return in, correction either, stock_take none.
-- order_id is checked at commit (place_order logs before it inserts the order) and cleared if the order is deleted.
CREATE TABLE inventory_log (
    log_id     integer     PRIMARY KEY DEFAULT nextval('inventory_log_log_id_seq'),
    product_id integer     NOT NULL CONSTRAINT inventory_log_product_fk REFERENCES products (product_id),
    change_qty integer     NOT NULL,
    reason     text        NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    note       text,
    order_id   integer     CONSTRAINT inventory_log_order_fk REFERENCES orders (order_id)
                           ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    changed_by text        DEFAULT current_user,
    CONSTRAINT inventory_log_reason_chk CHECK (
        (reason IN ('sale', 'damage')    AND change_qty < 0) OR
        (reason IN ('restock', 'return') AND change_qty > 0) OR
        (reason = 'correction'           AND change_qty <> 0) OR
        (reason = 'stock_take'           AND change_qty = 0))
);

-- ===== Quarantine tables (ADR-005) =====

-- Rows set aside by cleanup, kept exactly as they were found (original columns and types),
-- plus why and when. Keyed on the original id, so nothing is stored twice.
CREATE TABLE orders_quarantine (
    order_id          integer PRIMARY KEY,
    customer_id       integer,
    order_date        timestamp,
    status            text,
    total_amount      numeric(12,2),
    quarantine_reason text,
    quarantined_at    timestamptz DEFAULT now()
);

CREATE TABLE order_items_quarantine (
    order_item_id     integer PRIMARY KEY,
    order_id          integer,
    product_id        integer,
    quantity          integer,
    unit_price        numeric(12,2),
    quarantine_reason text,
    quarantined_at    timestamptz DEFAULT now()
);

CREATE TABLE inventory_log_quarantine (
    log_id            integer PRIMARY KEY,
    product_id        integer,
    change_qty        integer,
    reason            text,
    created_at        timestamp,
    note              text,
    quarantine_reason text,
    quarantined_at    timestamptz DEFAULT now()
);

-- ===== Archive of deleted log rows (ADR-002) =====

-- Log rows can be deleted (race_test.py removes its test rows), but a copy is always kept here.
CREATE TABLE inventory_log_archive (
    log_id      integer     NOT NULL,
    product_id  integer     NOT NULL,
    change_qty  integer     NOT NULL,
    reason      text        NOT NULL,
    created_at  timestamptz NOT NULL,
    note        text,
    order_id    integer,
    changed_by  text,
    archived_at timestamptz DEFAULT now(),
    archived_by text        DEFAULT current_user
);

-- ===== Indexes =====

-- The links between tables (sql/06_indexes.sql).
-- order_items.order_id is covered by the UNIQUE (order_id, product_id) rule.
CREATE INDEX orders_customer_idx       ON orders (customer_id);
CREATE INDEX order_items_product_idx   ON order_items (product_id);
CREATE INDEX inventory_log_product_idx ON inventory_log (product_id, created_at);
CREATE INDEX inventory_log_order_idx   ON inventory_log (order_id);
CREATE INDEX products_category_idx     ON products (category_id);
CREATE INDEX categories_parent_idx     ON categories (parent_id);
