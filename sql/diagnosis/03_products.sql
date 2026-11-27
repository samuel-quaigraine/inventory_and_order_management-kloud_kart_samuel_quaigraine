-- diagnosis/03_products.sql
-- Products: profile, negative stock, duplicate names, price outliers (read-only).

-- C1. Profile: id/price/stock/date ranges, missing values, impossible values.
--     NULL category is allowed (race_test.py inserts products without one).
SELECT count(*)                                              AS total_rows,
       min(product_id) AS min_id,  max(product_id) AS max_id,
       min(price)      AS min_price, max(price)    AS max_price,
       min(stock_quantity) AS min_stock, max(stock_quantity) AS max_stock,
       min(created_at) AS first_created, max(created_at) AS last_created,
       count(*) FILTER (WHERE coalesce(trim(product_name), '') = '') AS missing_names,
       count(*) - count(category_id)                         AS null_categories,
       count(*) FILTER (WHERE price IS NULL OR price <= 0)   AS bad_prices,
       count(*) FILTER (WHERE stock_quantity < 0)            AS negative_stock,
       count(*) FILTER (WHERE stock_quantity = 0)            AS out_of_stock
FROM products;

-- C2. Negative stock: products that were sold beyond what was on the shelf.
--     Evidence of overselling; compare with the inventory log in reconciliation.
SELECT product_id, product_name, stock_quantity
FROM products
WHERE stock_quantity < 0
ORDER BY stock_quantity, product_id;

-- C3. Duplicate names: same name once case/spaces are ignored.
--     Same category but different price = likely separate products sharing a generated name.
SELECT count(*)                                   AS duplicate_groups,
       sum(n)                                     AS rows_involved,
       count(*) FILTER (WHERE categories = 1)     AS same_category,
       count(*) FILTER (WHERE prices = 1)         AS same_price
FROM (SELECT count(*)                    AS n,
             count(DISTINCT category_id) AS categories,
             count(DISTINCT price)       AS prices
      FROM products
      GROUP BY lower(trim(product_name))
      HAVING count(*) > 1) g;

-- C4. Price bands: how prices are spread, to spot suspicious clusters.
--     Prices of 15k+ look odd, but orders sell them at that price (not typos).
SELECT CASE WHEN price < 100   THEN '1. under 100'
            WHEN price < 1000  THEN '2. 100 - 1k'
            WHEN price < 5000  THEN '3. 1k - 5k'
            WHEN price < 15000 THEN '4. 5k - 15k'
            ELSE                    '5. 15k and over' END AS price_band,
       count(*) AS products
FROM products
GROUP BY 1
ORDER BY 1;

-- C5. Stock levels: there is no reorder-level column, so "low stock" must be defined.
--     This spread informs the threshold chosen for the category rollup.
SELECT CASE WHEN stock_quantity < 0   THEN '1. negative'
            WHEN stock_quantity = 0   THEN '2. zero'
            WHEN stock_quantity <= 5  THEN '3. 1 - 5'
            WHEN stock_quantity <= 10 THEN '4. 6 - 10'
            WHEN stock_quantity <= 20 THEN '5. 11 - 20'
            ELSE                           '6. over 20' END AS stock_band,
       count(*) AS products
FROM products
GROUP BY 1
ORDER BY 1;
