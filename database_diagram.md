# Kloud Kart — database diagram

How the six tables in `schema.sql` relate to each other. The lines show the
relationships the data is *meant* to follow. **None of them are enforced by
the database today**: there are no foreign keys, so broken links can and do
exist (see `data_findings.md`).

```mermaid
erDiagram
    categories ||--o{ categories    : "is parent of"
    categories |o--o{ products      : "contains"
    customers  ||--o{ orders        : "places"
    orders     ||--|{ order_items   : "is made up of"
    products   ||--o{ order_items   : "appears in"
    products   ||--o{ inventory_log : "has stock movements"

    categories {
        integer category_id   PK
        text    category_name
        integer parent_id     FK "points to categories, blank = top level"
    }

    products {
        integer   product_id     PK
        text      product_name
        integer   category_id    FK "may be blank"
        numeric   price             "numeric(12,2), current price"
        integer   stock_quantity    "units on the shelf now"
        timestamp created_at
    }

    customers {
        integer   customer_id   PK
        text      full_name
        text      email            "not unique"
        text      phone
        text      city
        timestamp registered_at
    }

    orders {
        integer   order_id      PK
        integer   customer_id   FK
        timestamp order_date       "no time zone"
        text      status           "free text"
        numeric   total_amount     "written by the website at checkout"
    }

    order_items {
        integer order_item_id PK
        integer order_id      FK
        integer product_id    FK
        integer quantity
        numeric unit_price       "price paid at the time of the order"
    }

    inventory_log {
        integer   log_id      PK
        integer   product_id  FK
        integer   change_qty     "negative = out, positive = in"
        text      reason         "sale, restock, return, damage, correction, stock_take"
        timestamp created_at
        text      note
    }
```

## Reading the lines

| Relationship | Meaning |
|---|---|
| categories → categories | One category can have many subcategories. Each category has at most one parent. A blank `parent_id` means a top-level category. This single table holds the whole tree, at any depth. |
| categories → products | One category holds many products. A product may have no category (`|o` = zero or one). |
| customers → orders | One customer places many orders. Every order should belong to exactly one customer. |
| orders → order_items | One order is made up of one or more lines (`|{` = at least one). |
| products → order_items | One product can appear in many order lines. |
| products → inventory_log | One product has many stock movements. Adding up a product's `change_qty` should equal its `stock_quantity`. |

## Symbol key

| Symbol | Meaning |
|---|---|
| `||` | exactly one |
| `|o` | zero or one |
| `|{` | one or more |
| `o{` | zero or more |
| PK | primary key: uniquely identifies each row |
| FK | foreign key: points to a row in another table (intended, not enforced) |