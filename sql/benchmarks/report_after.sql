-- benchmarks/report_after.sql
-- Purpose: The 'after': the redesigned report (07_monday_report.sql) for ALL customers, timed 5 times.
-- Not part of 00_run_all.sql. Run after 00_run_all.sql. The median of the 5 runs is reported.

\timing on
SELECT count(*) AS report_rows FROM monday_report();
SELECT count(*) AS report_rows FROM monday_report();
SELECT count(*) AS report_rows FROM monday_report();
SELECT count(*) AS report_rows FROM monday_report();
SELECT count(*) AS report_rows FROM monday_report();

-- Category rollup, same method.
SELECT count(*) AS rollup_rows FROM low_stock_rollup();
SELECT count(*) AS rollup_rows FROM low_stock_rollup();
SELECT count(*) AS rollup_rows FROM low_stock_rollup();
SELECT count(*) AS rollup_rows FROM low_stock_rollup();
SELECT count(*) AS rollup_rows FROM low_stock_rollup();
