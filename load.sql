-- load.sql
-- Kloud Kart: builds the CORRECT database from the CSV files, in one command.
-- Run from the project root (so data/ resolves):
--     psql -v ON_ERROR_STOP=1 -f load.sql
--
-- Why it doesn't load straight into the final schema.sql: the CSVs contain rows that break its
-- rules (orphans, 15 status spellings, negative stock...), so the very first bad row would stop
-- the load. Instead the data goes in the way it was found, is cleaned, and THEN the rules go on.
-- The result has exactly the structure described in schema.sql.

\set ON_ERROR_STOP on

-- 1. The original tables, exactly as delivered (no rules yet).
\ir given/schema.sql

-- 2. The CSV files, exactly as delivered.
\ir given/load.sql

-- 3. Diagnose, clean, add the rules, then build place_order, the audit trail, indexes,
--    the report, the rollup and cancel_order.
\ir sql/00_run_all.sql
