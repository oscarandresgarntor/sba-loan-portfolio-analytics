# SBA 7(a) Loan Portfolio Analytics

A SQL analytics project demonstrating Senior Data Analyst skills using **SBA 7(a) Loan Program data** - the U.S. government's primary small business lending program with 900,000+ loan records spanning 1991-2025.

## Project Overview

This project showcases proficiency with real-world fintech data and commercial lending metrics through comprehensive SQL analysis including:

- **Data Quality Assessment** - Validation, cleaning, and standardization
- **Portfolio KPIs** - Core lending performance metrics
- **Risk Analysis** - Default rates, charge-offs, and loss analysis
- **Cohort Analysis** - Vintage performance and seasoning curves
- **Segmentation** - Geographic and industry insights
- **Executive Dashboards** - Summary views for reporting

## Key Findings

### Portfolio Performance
- **Total Origination Volume:** $580.6 billion across 1.9M+ loans (1991-2025)
- **Average Loan Size:** $303,558 with significant variation by industry
- **Default Rate:** 13.05% overall with notable vintage variation
- **Total Chargeoffs:** $23.25 billion in losses

### Risk Insights
- Default rates vary significantly by **industry sector** - from 5% (Management) to 16.5% (Retail/Information)
- **Geographic concentration** in CA, TX, FL, and NY represents 37% of portfolio volume
- **2008 Financial Crisis** impact clearly visible: 2007 vintage has 37% default rate vs. 7% for post-2010 vintages
- **Economic cycles** dramatically affect loan performance - crisis-era vintages show 3-4x higher default rates

### Top Performing Segments
| Segment | Default Rate | Avg Loan Size |
|---------|-------------|---------------|
| Management of Companies | 5.05% | $590,521 |
| Healthcare | 7.20% | $381,896 |
| Agriculture | 7.32% | $470,252 |

### Highest Risk Segments
| Segment | Default Rate | Avg Loan Size |
|---------|-------------|---------------|
| Information | 16.52% | $230,846 |
| Retail Trade | 16.46% | $294,693 |
| Wholesale Trade | 15.14% | $358,249 |

## Repository Structure

```
sba-loan-portfolio-analytics/
├── README.md                    # Project overview, setup, findings summary
├── data/
│   ├── README.md                # Data dictionary & download instructions
│   └── raw/                     # Downloaded CSV files (677 MB)
├── schema/
│   └── 01_create_tables.sql     # Table definitions with constraints
├── scripts/
│   ├── download_data.sh         # Automated data download script
│   └── import_data.sql          # Data import and transformation
├── analysis/
│   ├── 01_data_quality.sql      # Data validation & cleaning
│   ├── 02_portfolio_kpis.sql    # Core lending metrics
│   ├── 03_risk_analysis.sql     # Default/delinquency analysis
│   ├── 04_cohort_analysis.sql   # Time-based cohort performance
│   ├── 05_segmentation.sql      # Customer/industry insights
│   └── 06_executive_dashboard.sql  # Summary views for reporting
└── docs/
    └── findings.md              # Key insights & visualizations
```

## Technical Setup

### Prerequisites
- **PostgreSQL 15+** (supports all advanced SQL features used)
- **psql** or **pgAdmin** for query execution
- ~2GB disk space for full dataset

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/sba-loan-portfolio-analytics.git
   cd sba-loan-portfolio-analytics
   ```

2. **Create PostgreSQL database**
   ```bash
   createdb sba_loans
   ```

3. **Run schema creation**
   ```bash
   psql -d sba_loans -f schema/01_create_tables.sql
   ```

4. **Download SBA data** (~677 MB)
   ```bash
   ./scripts/download_data.sh
   ```

5. **Import data into PostgreSQL**
   ```bash
   psql -d sba_loans -f scripts/import_data.sql
   ```

6. **Run analysis scripts**
   ```bash
   # Run all analyses sequentially
   for f in analysis/*.sql; do psql -d sba_loans -f "$f"; done

   # Or run individually
   psql -d sba_loans -f analysis/01_data_quality.sql
   psql -d sba_loans -f analysis/02_portfolio_kpis.sql
   # ... continue with remaining scripts
   ```

7. **Query the dashboard views**
   ```sql
   -- Executive summary
   SELECT * FROM vw_executive_summary;

   -- Portfolio snapshot
   SELECT * FROM vw_portfolio_snapshot;

   -- Risk watchlist
   SELECT * FROM vw_risk_watchlist;
   ```

## SQL Skills Demonstrated

| Skill | Analysis File | Example |
|-------|---------------|---------|
| CASE statements | 01_data_quality.sql | Data categorization |
| NULL handling | 01_data_quality.sql | COALESCE, NULLIF |
| Aggregations | 02_portfolio_kpis.sql | SUM, AVG, COUNT |
| GROUP BY / HAVING | 02_portfolio_kpis.sql | Segmented metrics |
| Window Functions | 03_risk_analysis.sql | Running totals, rankings |
| CTEs | 03_risk_analysis.sql | Complex multi-step queries |
| Self-joins | 05_segmentation.sql | Comparative analysis |
| Correlated Subqueries | 05_segmentation.sql | Dynamic filtering |
| Date Functions | 04_cohort_analysis.sql | Vintage analysis |
| Views | 06_executive_dashboard.sql | Reusable metrics |

## Key Financial Metrics

| Metric | Description | Business Relevance |
|--------|-------------|-------------------|
| Default Rate | % loans charged off | Core credit risk indicator |
| Charge-Off Rate | Losses / Portfolio | P&L impact measurement |
| Loss Given Default | Avg loss when default occurs | Recovery analysis |
| Average Loan Size | Mean principal amount | Product sizing insight |
| SBA Guarantee % | Government risk share | Risk transfer analysis |
| Geographic Concentration | Portfolio distribution | Diversification metric |

## Data Source

**Primary Dataset:** [SBA 7(a) & 504 FOIA Data](https://data.sba.gov/en/dataset/7-a-504-foia)
- **1,912,539 loan records** (FY1991-FY2025)
- **677 MB** of raw CSV data across 4 files
- Public domain (U.S. government data)
- Includes loan outcomes (Paid in Full vs. Charged Off)
- Rich fields: amounts, terms, industries (NAICS), geography, lender info
- Updated quarterly by SBA

**Data Files Used:**
| File | Records | Period |
|------|---------|--------|
| sba_7a_1991_1999.csv | 318,589 | FY1991-FY1999 |
| sba_7a_2000_2009.csv | 690,333 | FY2000-FY2009 |
| sba_7a_2010_2019.csv | 545,751 | FY2010-FY2019 |
| sba_7a_2020_present.csv | 357,866 | FY2020-Present |

## License

This project uses public domain data from the U.S. Small Business Administration. Code is available under the MIT License.

## Author

[Your Name]

---

*This project was created to demonstrate SQL proficiency for Senior Data Analyst positions in fintech and commercial lending.*
