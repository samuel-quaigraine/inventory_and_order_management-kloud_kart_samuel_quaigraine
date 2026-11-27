-- diagnosis/02_customers.sql
-- Customers: profile, untidy text, duplicate emails, city spellings, phone formats (read-only).

-- B1. Profile: row count, id range, registration date range, NULL/blank values.
--     Blank = only spaces; count() treats those as real values, so check separately.
SELECT count(*)                                           AS total_rows,
       min(customer_id)                                   AS min_id,
       max(customer_id)                                   AS max_id,
       min(registered_at)                                 AS first_registered,
       max(registered_at)                                 AS last_registered,
       count(*) FILTER (WHERE coalesce(trim(full_name), '') = '') AS missing_names,
       count(*) FILTER (WHERE coalesce(trim(email), '') = '')     AS missing_emails,
       count(*) FILTER (WHERE coalesce(trim(phone), '') = '')     AS missing_phones,
       count(*) FILTER (WHERE coalesce(trim(city), '') = '')      AS missing_cities
FROM customers;

-- B2. Untidy text: stray spaces, upper-case emails, invalid email shape.
--     Invalid = no "something@something.something" even after trimming.
SELECT count(*) FILTER (WHERE email <> trim(email))         AS emails_with_spaces,
       count(*) FILTER (WHERE full_name <> trim(full_name)) AS names_with_spaces,
       count(*) FILTER (WHERE email <> lower(email))        AS emails_not_lowercase,
       count(*) FILTER (WHERE trim(email) !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') AS invalid_emails
FROM customers;

-- B3. Duplicate emails: exact match vs after ignoring case and spaces.
--     The gap between the two shows how many duplicates hide behind formatting.
SELECT 'exact' AS match_type, count(*) AS duplicate_groups, sum(n) AS rows_involved
FROM (SELECT count(*) AS n FROM customers GROUP BY email HAVING count(*) > 1) d
UNION ALL
SELECT 'normalised', count(*), sum(n)
FROM (SELECT count(*) AS n FROM customers GROUP BY lower(trim(email)) HAVING count(*) > 1) d;

-- B4. Same person or not? Within each duplicate-email group, compare names, phones, cities.
--     Phones compared on last 9 digits only, so format differences are ignored.
SELECT count(*)                                                AS duplicate_groups,
       count(*) FILTER (WHERE names = 1)                       AS same_name,
       count(*) FILTER (WHERE phones = 1)                      AS same_phone,
       count(*) FILTER (WHERE cities = 1)                      AS same_city
FROM (SELECT count(DISTINCT lower(trim(full_name))) AS names,
             count(DISTINCT right(regexp_replace(phone, '\D', '', 'g'), 9)) AS phones,
             count(DISTINCT lower(trim(city)))      AS cities
      FROM customers
      GROUP BY lower(trim(email))
      HAVING count(*) > 1) g;

-- B5. City spellings: raw values that collapse into one city once cleaned.
--     Quotes show hidden spaces, e.g. "Accra " vs "Accra".
SELECT lower(trim(city))                      AS clean_city,
       count(DISTINCT city)                   AS spellings,
       string_agg(DISTINCT '"' || city || '"', ', ') AS raw_values,
       count(*)                               AS customers
FROM customers
GROUP BY lower(trim(city))
HAVING count(DISTINCT city) > 1
ORDER BY clean_city;

-- B6. Phone formats: replace every digit with 9 to see the patterns used.
--     Several formats for the same Ghana number = needs standardising before matching.
SELECT regexp_replace(phone, '[0-9]', '9', 'g') AS phone_pattern,
       count(*)                                 AS customers
FROM customers
GROUP BY 1
ORDER BY 2 DESC;

-- B7. Email domains: kloudkart.com could mean staff or test accounts.
--     Similar size to public domains suggests generated data, not internal users.
SELECT split_part(lower(trim(email)), '@', 2) AS domain, count(*) AS customers
FROM customers
GROUP BY 1
ORDER BY 2 DESC;
