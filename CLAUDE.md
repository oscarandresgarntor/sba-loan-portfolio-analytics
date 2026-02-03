# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Summary

SQL-based financial analytics project analyzing the SBA 7(a) Loan Portfolio — 1.9M+ loan records (FY1991–FY2025), $580B+ in volume. The primary codebase is PostgreSQL SQL with an optional Jupyter notebook visualization layer.

## Setup & Common Commands

### Database Setup (PostgreSQL 15+ required)

```bash
createdb sba_loans
psql -d sba_loans -f schema/01_create_tables.sql
./scripts/download_data.sh                          # downloads ~677 MB of CSVs
psql -d sba_loans -f scripts/import_data.sql
```

### Running Analysis

```bash
# All analyses sequentially
for f in analysis/*.sql; do psql -d sba_loans -f "$f"; done

# Individual analysis file
psql -d sba_loans -f analysis/01_data_quality.sql
```

### Jupyter Notebook Environment

```bash
cd notebooks
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
jupyter lab
```

### Querying Dashboard Views (after running all analysis scripts)

```sql
SELECT * FROM vw_executive_summary;
SELECT * FROM vw_portfolio_snapshot;
SELECT * FROM vw_risk_watchlist;
```

## Architecture

The project follows a layered data pipeline pattern where each layer depends on the previous:

```
Raw CSVs → Staging Table → Cleaned Main Table + Reference Tables → Clean View → Analysis Queries → Dashboard Views
```

### Schema Layer (`schema/`)
- `sba_loans` — primary loan data table
- `naics_codes` — industry classification lookup (20 NAICS sectors)
- `state_regions` — US Census Bureau regional classification

### Data Import Layer (`scripts/`)
- `download_data.sh` — downloads 4 CSV files from data.sba.gov
- `import_data.sql` — loads CSVs into `sba_loans_staging` (text columns), then transforms and inserts into `sba_loans` with proper types

### Analysis Layer (`analysis/`, numbered 01–06)
Scripts are **ordered by dependency** and build progressively:

1. `01_data_quality.sql` — validation, NULL analysis, creates `vw_sba_loans_clean` view (used by subsequent scripts)
2. `02_portfolio_kpis.sql` — origination volume, loan size distribution, YoY growth
3. `03_risk_analysis.sql` — default rates, charge-offs, LGD, rolling 12-month trends
4. `04_cohort_analysis.sql` — vintage performance, seasoning curves, economic period comparison
5. `05_segmentation.sql` — geographic, industry (NAICS), lender, and loan-size segmentation
6. `06_executive_dashboard.sql` — creates materialized views combining metrics for reporting

### Notebook Layer (`notebooks/`)
- `sba_portfolio_analysis.ipynb` — connects to PostgreSQL via SQLAlchemy, runs analysis queries, and produces visualizations with matplotlib/seaborn/plotly

## Key Domain Concepts

- **Default Rate** = % of loans with CHGOFF (charged-off) status
- **Loss Rate** = total chargeoff amount / total approved amount
- **Loss Given Default (LGD)** = total chargeoff / total defaulted amount
- **SBA Guarantee %** = SBA guaranteed amount / gross approved amount
- **Vintage** = loans grouped by origination (approval) year for cohort tracking

## SQL Conventions

- `snake_case` for all table/column names; `UPPERCASE` for SQL keywords
- CTEs preferred for multi-step logic; FILTER clauses for conditional aggregation
- Analyses segment consistently across dimensions: vintage year, state, NAICS industry, lender, loan size bucket
