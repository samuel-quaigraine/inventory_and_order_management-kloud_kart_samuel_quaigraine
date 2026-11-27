
<!-- kloudkart-scaffold -->
## How to run the solution

From the project root, with the database from docker-compose.yml running:

```bash
docker compose up -d
export DATABASE_URL=postgresql://<user>:<password>@localhost:<port>/<database>

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f schema.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f load.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/00_run_all.sql

pip install psycopg2-binary
python race_test.py
```

## Where the deliverables are

| Deliverable | File |
|---|---|
| Data diagnosis | `data_findings.md` |
| Working SQL solution | `sql/` (run in order by `sql/00_run_all.sql`) |
| Key decisions | `decisions/` |
| Performance proof | `performance_report.md` |
| Memo to Nana | `client_memo.md` |
| Improvement beyond the brief | `improvement.md`, `sql/09_improvement.sql` |

The given files (`schema.sql`, `load.sql`, `race_test.py`, `data/`) are unchanged. Note: `*.csv` datasets are excluded via `.gitignore`; place the Evalu8 Kloud Kart `data/*.csv` files in `data/` before running `load.sql`.
