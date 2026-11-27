-- cleanup/02_customers.sql
-- Customers: tidy text and standardise phone numbers (F-13). Duplicate emails are kept (F-11).

-- Names: remove stray spaces. Emails: remove spaces and lowercase.
-- Cities: remove spaces and use one capitalisation, so 4 spellings of Accra become "Accra".
UPDATE customers
SET full_name = trim(full_name),
    email     = lower(trim(email)),
    city      = initcap(trim(city))
WHERE full_name <> trim(full_name)
   OR email     <> lower(trim(email))
   OR city      <> initcap(trim(city));

-- Phones: one format, +233 followed by 9 digits.
-- Handles 233XXXXXXXXX, 0XXXXXXXXX and XXXXXXXXX (spaces and + removed first).
UPDATE customers
SET phone = '+233' || right(regexp_replace(phone, '\D', '', 'g'), 9)
WHERE phone !~ '^\+233[0-9]{9}$';

-- Duplicate emails (533 groups) are NOT merged: same name but never the same phone,
-- so whether they are one person is a business decision. They stay as separate customers.
