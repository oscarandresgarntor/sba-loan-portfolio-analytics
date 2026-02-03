/*
================================================================================
SBA 7(a) LOAN DATA IMPORT SCRIPT
================================================================================

Purpose: Import SBA FOIA CSV data into PostgreSQL
Usage: psql -d sba_loans -f scripts/import_data.sql

Note: Run download_data.sh first to download the CSV files.
      Run schema/01_create_tables.sql first to create the target tables.

================================================================================
*/

-- ============================================================================
-- STEP 1: CREATE STAGING TABLE
-- Staging table matches actual CSV column headers (as of Jan 2026)
-- ============================================================================

\echo ''
\echo '================================================'
\echo '  SBA 7(a) Data Import Script'
\echo '================================================'
\echo ''

DROP TABLE IF EXISTS sba_loans_staging CASCADE;

CREATE TABLE sba_loans_staging (
    asofdate TEXT,
    program TEXT,
    l2locid TEXT,
    borrname TEXT,
    borrstreet TEXT,
    borrcity TEXT,
    borrstate TEXT,
    borrzip TEXT,
    bankname TEXT,
    bankfdicnumber TEXT,
    bankncuanumber TEXT,
    bankstreet TEXT,
    bankcity TEXT,
    bankstate TEXT,
    bankzip TEXT,
    grossapproval TEXT,
    sbaguaranteedapproval TEXT,
    approvaldate TEXT,
    approvalfiscalyear TEXT,
    firstdisbursementdate TEXT,
    processingmethod TEXT,
    subprogram TEXT,
    initialinterestrate TEXT,
    fixedorvariableinterestind TEXT,
    terminmonths TEXT,
    naicscode TEXT,
    naicsdescription TEXT,
    franchisecode TEXT,
    franchisename TEXT,
    projectcounty TEXT,
    projectstate TEXT,
    sbadistrictoffice TEXT,
    congressionaldistrict TEXT,
    businesstype TEXT,
    businessage TEXT,
    loanstatus TEXT,
    paidinfulldate TEXT,
    chargeoffdate TEXT,
    grosschargeoffamount TEXT,
    revolverstatus TEXT,
    jobssupported TEXT,
    collateralind TEXT,
    soldsecmrktind TEXT
);

\echo 'Created staging table.'

-- ============================================================================
-- STEP 2: IMPORT CSV FILES INTO STAGING TABLE
-- ============================================================================

\echo ''
\echo 'Importing SBA 7(a) data files into staging table...'
\echo 'This may take several minutes for ~2 million records.'
\echo ''

-- FY1991-FY1999
\echo 'Importing FY1991-FY1999 data (~319K records)...'
\copy sba_loans_staging FROM 'data/raw/sba_7a_1991_1999.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');

-- FY2000-FY2009
\echo 'Importing FY2000-FY2009 data (~690K records)...'
\copy sba_loans_staging FROM 'data/raw/sba_7a_2000_2009.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');

-- FY2010-FY2019
\echo 'Importing FY2010-FY2019 data (~546K records)...'
\copy sba_loans_staging FROM 'data/raw/sba_7a_2010_2019.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');

-- FY2020-Present
\echo 'Importing FY2020-Present data (~358K records)...'
\copy sba_loans_staging FROM 'data/raw/sba_7a_2020_present.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8');

\echo ''
\echo 'Staging import complete.'

SELECT 'Staging table record count: ' || TO_CHAR(COUNT(*), 'FM999,999,999') FROM sba_loans_staging;

-- ============================================================================
-- STEP 3: TRANSFORM AND LOAD INTO FINAL TABLE
-- Map staging columns to schema columns with proper data types
-- ============================================================================

\echo ''
\echo 'Transforming and loading data into final sba_loans table...'
\echo 'This may take a few minutes...'

-- Clear existing data
TRUNCATE TABLE sba_loans;

-- Insert with transformations
INSERT INTO sba_loans (
    loan_id,
    business_name,
    city,
    state,
    zip,
    bank_name,
    bank_state,
    naics,
    approval_date,
    approval_fy,
    disbursement_date,
    term_months,
    num_employees,
    new_business,
    jobs_created,
    jobs_retained,
    franchise_code,
    urban_rural,
    rev_line_of_credit,
    low_doc,
    gross_approved,
    sba_approved,
    disbursement_gross,
    balance_gross,
    loan_status,
    chargeoff_date,
    chargeoff_amount
)
SELECT
    -- Generate unique loan ID using row number (l2locid is not unique - it's a lender location ID)
    'SBA-' || LPAD(ROW_NUMBER() OVER (ORDER BY approvalfiscalyear, approvaldate, borrname)::TEXT, 8, '0'),

    -- Borrower information
    LEFT(TRIM(borrname), 255),
    LEFT(TRIM(borrcity), 100),
    UPPER(LEFT(TRIM(COALESCE(borrstate, projectstate)), 2)),
    LEFT(TRIM(borrzip), 10),

    -- Bank information
    LEFT(TRIM(bankname), 255),
    UPPER(LEFT(TRIM(bankstate), 2)),

    -- Industry (NAICS code)
    LEFT(TRIM(naicscode), 6),

    -- Approval date
    CASE
        WHEN approvaldate ~ '^\d{1,2}/\d{1,2}/\d{2,4}$'
        THEN TO_DATE(approvaldate, 'MM/DD/YYYY')
        WHEN approvaldate ~ '^\d{4}-\d{2}-\d{2}'
        THEN TO_DATE(LEFT(approvaldate, 10), 'YYYY-MM-DD')
        ELSE NULL
    END,

    -- Fiscal year
    CASE
        WHEN approvalfiscalyear ~ '^\d{4}$'
        THEN approvalfiscalyear::INTEGER
        ELSE NULL
    END,

    -- Disbursement date
    CASE
        WHEN firstdisbursementdate ~ '^\d{1,2}/\d{1,2}/\d{2,4}$'
        THEN TO_DATE(firstdisbursementdate, 'MM/DD/YYYY')
        WHEN firstdisbursementdate ~ '^\d{4}-\d{2}-\d{2}'
        THEN TO_DATE(LEFT(firstdisbursementdate, 10), 'YYYY-MM-DD')
        ELSE NULL
    END,

    -- Term in months (must be > 0 or NULL per constraint chk_term_positive)
    NULLIF(CASE
        WHEN terminmonths ~ '^\d+$'
        THEN terminmonths::INTEGER
        WHEN terminmonths ~ '^\d+\.'
        THEN ROUND(terminmonths::NUMERIC)::INTEGER
        ELSE NULL
    END, 0),

    -- Employees (from jobs supported - estimate)
    CASE
        WHEN jobssupported ~ '^\d+$'
        THEN LEAST(jobssupported::INTEGER, 9999)
        WHEN jobssupported ~ '^\d+\.'
        THEN LEAST(ROUND(jobssupported::NUMERIC)::INTEGER, 9999)
        ELSE NULL
    END,

    -- New/Existing business (from businessage field)
    CASE
        WHEN UPPER(TRIM(businessage)) IN ('NEW BUSINESS', 'STARTUP', 'NEW', '2') THEN 2
        WHEN UPPER(TRIM(businessage)) IN ('EXISTING BUSINESS', 'EXISTING', '1') THEN 1
        WHEN UPPER(TRIM(businessage)) LIKE '%NEW%' THEN 2
        WHEN UPPER(TRIM(businessage)) LIKE '%EXIST%' THEN 1
        WHEN businessage ~ '^\d+' AND TRIM(businessage)::NUMERIC < 2 THEN 2  -- Less than 2 years
        WHEN businessage ~ '^\d+' THEN 1  -- 2+ years
        ELSE NULL
    END,

    -- Jobs created (estimate as half of jobs supported)
    CASE
        WHEN jobssupported ~ '^\d+$'
        THEN GREATEST(jobssupported::INTEGER / 2, 0)
        WHEN jobssupported ~ '^\d+\.'
        THEN GREATEST(ROUND(jobssupported::NUMERIC / 2)::INTEGER, 0)
        ELSE 0
    END,

    -- Jobs retained (estimate as half of jobs supported)
    CASE
        WHEN jobssupported ~ '^\d+$'
        THEN GREATEST(jobssupported::INTEGER / 2, 0)
        WHEN jobssupported ~ '^\d+\.'
        THEN GREATEST(ROUND(jobssupported::NUMERIC / 2)::INTEGER, 0)
        ELSE 0
    END,

    -- Franchise code
    NULLIF(LEFT(TRIM(franchisecode), 10), ''),

    -- Urban/Rural (default to 0/unknown)
    0,

    -- Revolving line
    CASE
        WHEN UPPER(TRIM(revolverstatus)) IN ('Y', 'YES', '1', 'TRUE', 'REVOLVING') THEN 'Y'
        ELSE 'N'
    END,

    -- Low Doc (from processing method)
    CASE
        WHEN UPPER(TRIM(processingmethod)) LIKE '%LOWDOC%' THEN 'Y'
        WHEN UPPER(TRIM(processingmethod)) LIKE '%LOW DOC%' THEN 'Y'
        ELSE 'N'
    END,

    -- Gross approval amount
    CASE
        WHEN grossapproval ~ '^[\d.]+$'
        THEN grossapproval::DECIMAL(15,2)
        WHEN grossapproval ~ '^[\$,\d.]+$'
        THEN REGEXP_REPLACE(grossapproval, '[^\d.]', '', 'g')::DECIMAL(15,2)
        ELSE NULL
    END,

    -- SBA guaranteed amount
    CASE
        WHEN sbaguaranteedapproval ~ '^[\d.]+$'
        THEN sbaguaranteedapproval::DECIMAL(15,2)
        WHEN sbaguaranteedapproval ~ '^[\$,\d.]+$'
        THEN REGEXP_REPLACE(sbaguaranteedapproval, '[^\d.]', '', 'g')::DECIMAL(15,2)
        ELSE NULL
    END,

    -- Disbursement gross (same as gross approval)
    CASE
        WHEN grossapproval ~ '^[\d.]+$'
        THEN grossapproval::DECIMAL(15,2)
        WHEN grossapproval ~ '^[\$,\d.]+$'
        THEN REGEXP_REPLACE(grossapproval, '[^\d.]', '', 'g')::DECIMAL(15,2)
        ELSE NULL
    END,

    -- Balance (not available in source)
    NULL,

    -- Loan status
    CASE
        WHEN UPPER(TRIM(loanstatus)) LIKE '%PIF%' THEN 'PIF'
        WHEN UPPER(TRIM(loanstatus)) LIKE '%PAID%FULL%' THEN 'PIF'
        WHEN UPPER(TRIM(loanstatus)) LIKE '%CHGOFF%' THEN 'CHGOFF'
        WHEN UPPER(TRIM(loanstatus)) LIKE '%CHARGE%OFF%' THEN 'CHGOFF'
        WHEN UPPER(TRIM(loanstatus)) = 'COMMIT' THEN NULL  -- Active/pending
        WHEN UPPER(TRIM(loanstatus)) = 'CANCLD' THEN NULL  -- Cancelled
        WHEN UPPER(TRIM(loanstatus)) = 'EXEMPT' THEN 'PIF' -- Treat as paid
        ELSE NULL
    END,

    -- Chargeoff date
    CASE
        WHEN chargeoffdate ~ '^\d{1,2}/\d{1,2}/\d{2,4}$'
        THEN TO_DATE(chargeoffdate, 'MM/DD/YYYY')
        WHEN chargeoffdate ~ '^\d{4}-\d{2}-\d{2}'
        THEN TO_DATE(LEFT(chargeoffdate, 10), 'YYYY-MM-DD')
        ELSE NULL
    END,

    -- Chargeoff amount
    CASE
        WHEN grosschargeoffamount ~ '^[\d.]+$' AND grosschargeoffamount::DECIMAL > 0
        THEN grosschargeoffamount::DECIMAL(15,2)
        WHEN grosschargeoffamount ~ '^[\$,\d.]+$'
        THEN NULLIF(REGEXP_REPLACE(grosschargeoffamount, '[^\d.]', '', 'g'), '')::DECIMAL(15,2)
        ELSE NULL
    END

FROM sba_loans_staging
WHERE l2locid IS NOT NULL
  AND TRIM(l2locid) != '';

\echo ''
\echo 'Data transformation complete.'

-- ============================================================================
-- STEP 4: VERIFY IMPORT
-- ============================================================================

\echo ''
\echo '================================================'
\echo '  Import Verification'
\echo '================================================'
\echo ''

-- Record counts
SELECT 'Total loans imported: ' || TO_CHAR(COUNT(*), 'FM999,999,999') AS metric FROM sba_loans;

-- Status distribution
\echo ''
\echo 'Loan Status Distribution:'
SELECT
    COALESCE(loan_status, 'ACTIVE/PENDING') AS status,
    TO_CHAR(COUNT(*), 'FM999,999,999') AS count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)::TEXT || '%' AS pct
FROM sba_loans
GROUP BY loan_status
ORDER BY COUNT(*) DESC;

-- Fiscal year range
\echo ''
SELECT
    'Fiscal year range: ' || MIN(approval_fy)::TEXT || ' - ' || MAX(approval_fy)::TEXT AS metric
FROM sba_loans
WHERE approval_fy IS NOT NULL;

-- State coverage
SELECT
    'States/territories with loans: ' || COUNT(DISTINCT state)::TEXT AS metric
FROM sba_loans
WHERE state IS NOT NULL;

-- Volume totals
\echo ''
\echo 'Financial Summary:'
SELECT
    'Total approved volume: $' || TO_CHAR(SUM(gross_approved) / 1000000000, 'FM999,999.99') || ' billion' AS metric
FROM sba_loans;

SELECT
    'Total SBA guaranteed: $' || TO_CHAR(SUM(sba_approved) / 1000000000, 'FM999,999.99') || ' billion' AS metric
FROM sba_loans;

SELECT
    'Total chargeoffs: $' || TO_CHAR(SUM(chargeoff_amount) / 1000000000, 'FM999.99') || ' billion' AS metric
FROM sba_loans
WHERE chargeoff_amount > 0;

-- Average loan metrics
\echo ''
\echo 'Average Loan Metrics:'
SELECT
    'Average loan size: $' || TO_CHAR(ROUND(AVG(gross_approved)), 'FM999,999') AS metric
FROM sba_loans
WHERE gross_approved > 0;

SELECT
    'Average term: ' || ROUND(AVG(term_months), 0)::TEXT || ' months' AS metric
FROM sba_loans
WHERE term_months > 0;

-- ============================================================================
-- STEP 5: CREATE INDEXES (if not already created)
-- ============================================================================

\echo ''
\echo 'Ensuring indexes are in place...'

-- These are defined in schema but let's make sure they exist
CREATE INDEX IF NOT EXISTS idx_sba_loans_approval_date ON sba_loans(approval_date);
CREATE INDEX IF NOT EXISTS idx_sba_loans_approval_fy ON sba_loans(approval_fy);
CREATE INDEX IF NOT EXISTS idx_sba_loans_state ON sba_loans(state);
CREATE INDEX IF NOT EXISTS idx_sba_loans_naics ON sba_loans(naics);
CREATE INDEX IF NOT EXISTS idx_sba_loans_status ON sba_loans(loan_status);

\echo 'Indexes verified.'

-- ============================================================================
-- STEP 6: REFRESH STATISTICS
-- ============================================================================

\echo ''
\echo 'Refreshing table statistics for query optimization...'
ANALYZE sba_loans;

-- ============================================================================
-- STEP 7: CLEANUP (Optional - keep staging for debugging)
-- ============================================================================

-- Uncomment to drop staging table after successful import
-- DROP TABLE IF EXISTS sba_loans_staging;

\echo ''
\echo '================================================'
\echo '  SBA Data Import Complete!'
\echo '================================================'
\echo ''
\echo 'Next steps:'
\echo '  1. Run data quality analysis:'
\echo '     psql -d sba_loans -f analysis/01_data_quality.sql'
\echo ''
\echo '  2. Or run all analyses:'
\echo '     for f in analysis/*.sql; do psql -d sba_loans -f "$f"; done'
\echo ''
