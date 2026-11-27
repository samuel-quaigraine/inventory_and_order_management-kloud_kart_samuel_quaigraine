-- 00_run_all.sql
-- Runs the whole solution, in order, against a fresh load.
--
-- Normally run by load.sql (project root), after given/schema.sql and given/load.sql.
-- To run it on its own after a fresh load:
--     psql -v ON_ERROR_STOP=1 -f sql/00_run_all.sql
--
-- \ir includes a file relative to this one, so it works from any directory.

\set ON_ERROR_STOP on
\timing on

\ir 01_diagnosis.sql
\ir 02_cleanup.sql
\ir 03_constraints.sql
\ir 04_place_order.sql
\ir 05_audit_trail.sql
\ir 06_indexes.sql
\ir 07_monday_report.sql
\ir 08_category_rollup.sql
\ir 09_improvement.sql
