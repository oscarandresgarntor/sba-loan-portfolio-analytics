# Data Sources & Dictionary

## Primary Data Source

### SBA 7(a) & 504 FOIA Dataset

**Source:** [U.S. Small Business Administration FOIA Data](https://data.sba.gov/en/dataset/7-a-504-foia)

**Description:** The SBA 7(a) loan program is the U.S. government's primary program for providing financial assistance to small businesses. This dataset contains loan-level information for all 7(a) loans approved since 1991.

**Download Instructions:**
1. Visit [data.sba.gov](https://data.sba.gov/en/dataset/7-a-504-foia)
2. Navigate to the 7(a) loan data section
3. Download the CSV file (approximately 200MB compressed)
4. Extract to this `data/` directory

**Alternative Source:** [Kaggle SBA 7A Loan Data](https://www.kaggle.com/datasets/williecosta/sba-7a-loan-data)

---

## Data Dictionary

### Core Loan Fields

| Column Name | Data Type | Description | Example |
|-------------|-----------|-------------|---------|
| `LoanNr_ChkDgt` | VARCHAR(12) | Unique loan identifier with check digit | 1234567890 |
| `Name` | VARCHAR(255) | Business name (borrower) | ABC Company LLC |
| `City` | VARCHAR(100) | Business city | San Francisco |
| `State` | CHAR(2) | Business state code | CA |
| `Zip` | VARCHAR(10) | Business ZIP code | 94102 |
| `Bank` | VARCHAR(255) | Lending institution name | Bank of America |
| `BankState` | CHAR(2) | Lender state code | NC |
| `NAICS` | VARCHAR(6) | North American Industry Classification | 541110 |
| `ApprovalDate` | DATE | Loan approval date | 2020-03-15 |
| `ApprovalFY` | INTEGER | Fiscal year of approval | 2020 |
| `Term` | INTEGER | Loan term in months | 84 |
| `NoEmp` | INTEGER | Number of employees | 25 |
| `NewExist` | INTEGER | New business (2) or Existing (1) | 1 |
| `CreateJob` | INTEGER | Jobs to be created | 5 |
| `RetainedJob` | INTEGER | Jobs to be retained | 20 |
| `FranchiseCode` | VARCHAR(10) | Franchise identifier (if applicable) | 00000 |
| `UrbanRural` | INTEGER | Urban (1), Rural (2), Undefined (0) | 1 |
| `RevLineCr` | CHAR(1) | Revolving line of credit (Y/N) | N |
| `LowDoc` | CHAR(1) | LowDoc program loan (Y/N) | N |
| `ChgOffDate` | DATE | Charge-off date (if defaulted) | NULL |
| `DisbursementDate` | DATE | Date funds disbursed | 2020-04-01 |
| `DisbursementGross` | DECIMAL | Gross disbursement amount | 500000.00 |
| `BalanceGross` | DECIMAL | Current gross balance | 0.00 |
| `MIS_Status` | VARCHAR(20) | Loan status: PIF or CHGOFF | PIF |
| `ChgOffPrinGr` | DECIMAL | Charged-off principal (gross) | 0.00 |
| `GrAppv` | DECIMAL | Gross amount approved | 500000.00 |
| `SBA_Appv` | DECIMAL | SBA guaranteed amount | 375000.00 |

### Derived/Calculated Fields (Created in Schema)

| Column Name | Data Type | Description | Calculation |
|-------------|-----------|-------------|-------------|
| `sba_guarantee_pct` | DECIMAL | SBA guarantee percentage | SBA_Appv / GrAppv |
| `is_defaulted` | BOOLEAN | Whether loan defaulted | MIS_Status = 'CHGOFF' |
| `vintage_year` | INTEGER | Year of origination | EXTRACT(YEAR FROM ApprovalDate) |
| `loan_size_bucket` | VARCHAR | Categorized loan size | Based on GrAppv ranges |

---

## NAICS Code Reference

The NAICS (North American Industry Classification System) codes categorize businesses by industry:

| NAICS Prefix | Industry Sector |
|--------------|-----------------|
| 11 | Agriculture, Forestry, Fishing |
| 21 | Mining, Quarrying, Oil/Gas |
| 22 | Utilities |
| 23 | Construction |
| 31-33 | Manufacturing |
| 42 | Wholesale Trade |
| 44-45 | Retail Trade |
| 48-49 | Transportation & Warehousing |
| 51 | Information |
| 52 | Finance & Insurance |
| 53 | Real Estate |
| 54 | Professional, Scientific, Technical |
| 55 | Management of Companies |
| 56 | Administrative & Support |
| 61 | Educational Services |
| 62 | Healthcare & Social Assistance |
| 71 | Arts, Entertainment, Recreation |
| 72 | Accommodation & Food Services |
| 81 | Other Services |
| 92 | Public Administration |

---

## Loan Status Codes

| Status Code | Description | Outcome |
|-------------|-------------|---------|
| PIF | Paid In Full | Successful repayment |
| CHGOFF | Charged Off | Defaulted / Written off |
| NULL | Active/Unknown | Still outstanding or status pending |

---

## Data Quality Notes

### Known Issues
1. **Missing NAICS codes:** Some older loans have incomplete industry classification
2. **Zip code formats:** Mix of 5-digit and 9-digit ZIP codes
3. **Date inconsistencies:** Some records have disbursement dates before approval dates
4. **Currency formatting:** Some amount fields may contain currency symbols in raw data

### Recommended Cleaning Steps
1. Standardize state codes to uppercase
2. Extract 5-digit ZIP from 9-digit codes
3. Handle NULL amounts as 0 for aggregations
4. Filter to completed loans (PIF or CHGOFF) for default analysis
5. Exclude test/administrative records

---

## Sample Data

For testing purposes, you can create a sample dataset:

```sql
-- Create 10K record sample for development
CREATE TABLE sba_loans_sample AS
SELECT * FROM sba_loans
ORDER BY RANDOM()
LIMIT 10000;
```

---

## Data Refresh

The SBA updates this dataset quarterly. To refresh:
1. Download the latest CSV from data.sba.gov
2. Truncate and reload the table, or
3. Use incremental loading based on ApprovalDate

```sql
-- Incremental load example
INSERT INTO sba_loans
SELECT * FROM staging_new_loans
WHERE approval_date > (SELECT MAX(approval_date) FROM sba_loans);
```
