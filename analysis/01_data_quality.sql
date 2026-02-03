/*
================================================================================
SBA 7(a) LOAN PORTFOLIO ANALYTICS
Analysis: 01_data_quality.sql
================================================================================

Purpose: Data validation, quality assessment, and cleaning queries
Skills Demonstrated: CASE statements, COALESCE, NULL handling, data validation

Description:
    This script performs comprehensive data quality analysis on the SBA loan
    dataset, identifying issues and creating cleaned views for downstream analysis.

================================================================================
*/

-- ============================================================================
-- SECTION 1: NULL VALUE ANALYSIS
-- Identify completeness issues across all columns
-- ============================================================================

-- 1.1 Comprehensive NULL analysis for all columns
SELECT
    'loan_id' AS column_name,
    COUNT(*) AS total_rows,
    SUM(CASE WHEN loan_id IS NULL THEN 1 ELSE 0 END) AS null_count,
    ROUND(100.0 * SUM(CASE WHEN loan_id IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS null_pct
FROM sba_loans

UNION ALL

SELECT
    'business_name',
    COUNT(*),
    SUM(CASE WHEN business_name IS NULL THEN 1 ELSE 0 END),
    ROUND(100.0 * SUM(CASE WHEN business_name IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM sba_loans

UNION ALL

SELECT
    'state',
    COUNT(*),
    SUM(CASE WHEN state IS NULL THEN 1 ELSE 0 END),
    ROUND(100.0 * SUM(CASE WHEN state IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM sba_loans

UNION ALL

SELECT
    'naics',
    COUNT(*),
    SUM(CASE WHEN naics IS NULL THEN 1 ELSE 0 END),
    ROUND(100.0 * SUM(CASE WHEN naics IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM sba_loans

UNION ALL

SELECT
    'approval_date',
    COUNT(*),
    SUM(CASE WHEN approval_date IS NULL THEN 1 ELSE 0 END),
    ROUND(100.0 * SUM(CASE WHEN approval_date IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM sba_loans

UNION ALL

SELECT
    'gross_approved',
    COUNT(*),
    SUM(CASE WHEN gross_approved IS NULL THEN 1 ELSE 0 END),
    ROUND(100.0 * SUM(CASE WHEN gross_approved IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM sba_loans

UNION ALL

SELECT
    'loan_status',
    COUNT(*),
    SUM(CASE WHEN loan_status IS NULL THEN 1 ELSE 0 END),
    ROUND(100.0 * SUM(CASE WHEN loan_status IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM sba_loans

ORDER BY null_pct DESC;

-- 1.2 Dynamic NULL analysis using information_schema
-- More elegant approach for all columns
WITH column_nulls AS (
    SELECT
        COUNT(*) AS total_rows,
        SUM(CASE WHEN loan_id IS NULL THEN 1 ELSE 0 END) AS loan_id_nulls,
        SUM(CASE WHEN business_name IS NULL THEN 1 ELSE 0 END) AS business_name_nulls,
        SUM(CASE WHEN city IS NULL THEN 1 ELSE 0 END) AS city_nulls,
        SUM(CASE WHEN state IS NULL THEN 1 ELSE 0 END) AS state_nulls,
        SUM(CASE WHEN zip IS NULL THEN 1 ELSE 0 END) AS zip_nulls,
        SUM(CASE WHEN bank_name IS NULL THEN 1 ELSE 0 END) AS bank_name_nulls,
        SUM(CASE WHEN naics IS NULL THEN 1 ELSE 0 END) AS naics_nulls,
        SUM(CASE WHEN approval_date IS NULL THEN 1 ELSE 0 END) AS approval_date_nulls,
        SUM(CASE WHEN term_months IS NULL THEN 1 ELSE 0 END) AS term_months_nulls,
        SUM(CASE WHEN num_employees IS NULL THEN 1 ELSE 0 END) AS num_employees_nulls,
        SUM(CASE WHEN gross_approved IS NULL THEN 1 ELSE 0 END) AS gross_approved_nulls,
        SUM(CASE WHEN sba_approved IS NULL THEN 1 ELSE 0 END) AS sba_approved_nulls,
        SUM(CASE WHEN loan_status IS NULL THEN 1 ELSE 0 END) AS loan_status_nulls
    FROM sba_loans
)
SELECT
    total_rows,
    loan_id_nulls,
    ROUND(100.0 * loan_id_nulls / total_rows, 2) AS loan_id_null_pct,
    naics_nulls,
    ROUND(100.0 * naics_nulls / total_rows, 2) AS naics_null_pct,
    loan_status_nulls,
    ROUND(100.0 * loan_status_nulls / total_rows, 2) AS loan_status_null_pct
FROM column_nulls;

-- ============================================================================
-- SECTION 2: OUTLIER DETECTION
-- Identify anomalous values in key numeric fields
-- ============================================================================

-- 2.1 Loan amount distribution and outlier detection
SELECT
    'Gross Approved Amount' AS metric,
    COUNT(*) AS total_records,
    MIN(gross_approved) AS min_value,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY gross_approved) AS p25,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY gross_approved) AS median,
    ROUND(AVG(gross_approved), 2) AS mean,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY gross_approved) AS p75,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY gross_approved) AS p95,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY gross_approved) AS p99,
    MAX(gross_approved) AS max_value,
    ROUND(STDDEV(gross_approved), 2) AS std_dev
FROM sba_loans
WHERE gross_approved IS NOT NULL;

-- 2.2 Identify outliers using IQR method
WITH quartiles AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY gross_approved) AS q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY gross_approved) AS q3
    FROM sba_loans
    WHERE gross_approved IS NOT NULL
),
bounds AS (
    SELECT
        q1,
        q3,
        q3 - q1 AS iqr,
        q1 - 1.5 * (q3 - q1) AS lower_bound,
        q3 + 1.5 * (q3 - q1) AS upper_bound
    FROM quartiles
)
SELECT
    'Loan Amount Outliers' AS analysis,
    COUNT(*) FILTER (WHERE gross_approved < lower_bound) AS below_lower_bound,
    COUNT(*) FILTER (WHERE gross_approved > upper_bound) AS above_upper_bound,
    COUNT(*) FILTER (WHERE gross_approved BETWEEN lower_bound AND upper_bound) AS within_bounds,
    ROUND(100.0 * COUNT(*) FILTER (WHERE gross_approved > upper_bound) / COUNT(*), 2) AS pct_high_outliers
FROM sba_loans, bounds
WHERE gross_approved IS NOT NULL;

-- 2.3 Term length outlier analysis
SELECT
    'Loan Term (Months)' AS metric,
    COUNT(*) AS total_records,
    MIN(term_months) AS min_term,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY term_months) AS median_term,
    ROUND(AVG(term_months), 1) AS avg_term,
    MAX(term_months) AS max_term,
    COUNT(*) FILTER (WHERE term_months > 300) AS extreme_terms,
    COUNT(*) FILTER (WHERE term_months <= 0) AS invalid_terms
FROM sba_loans
WHERE term_months IS NOT NULL;

-- 2.4 Employee count reasonableness check
SELECT
    CASE
        WHEN num_employees IS NULL THEN 'NULL'
        WHEN num_employees = 0 THEN '0 employees'
        WHEN num_employees BETWEEN 1 AND 10 THEN '1-10'
        WHEN num_employees BETWEEN 11 AND 50 THEN '11-50'
        WHEN num_employees BETWEEN 51 AND 100 THEN '51-100'
        WHEN num_employees BETWEEN 101 AND 500 THEN '101-500'
        WHEN num_employees > 500 THEN '>500 (potential issue)'
        ELSE 'Negative (invalid)'
    END AS employee_bucket,
    COUNT(*) AS loan_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM sba_loans
GROUP BY 1
ORDER BY loan_count DESC;

-- ============================================================================
-- SECTION 3: DATA TYPE AND FORMAT VALIDATION
-- Ensure data conforms to expected formats
-- ============================================================================

-- 3.1 State code validation
SELECT
    state,
    COUNT(*) AS occurrences,
    CASE
        WHEN state IS NULL THEN 'NULL'
        WHEN LENGTH(state) != 2 THEN 'Invalid length'
        WHEN state !~ '^[A-Z]{2}$' THEN 'Invalid format'
        WHEN state NOT IN (SELECT state_code FROM state_regions) THEN 'Unknown state'
        ELSE 'Valid'
    END AS validation_status
FROM sba_loans
GROUP BY state
HAVING
    state IS NULL
    OR LENGTH(state) != 2
    OR state !~ '^[A-Z]{2}$'
    OR state NOT IN (SELECT state_code FROM state_regions)
ORDER BY occurrences DESC
LIMIT 20;

-- 3.2 NAICS code validation
SELECT
    CASE
        WHEN naics IS NULL THEN 'NULL'
        WHEN naics !~ '^\d+$' THEN 'Non-numeric'
        WHEN LENGTH(naics) < 2 THEN 'Too short'
        WHEN LENGTH(naics) > 6 THEN 'Too long'
        WHEN LEFT(naics, 2) NOT IN ('11','21','22','23','31','32','33','42','44','45',
                                     '48','49','51','52','53','54','55','56','61','62',
                                     '71','72','81','92') THEN 'Invalid sector'
        ELSE 'Valid'
    END AS naics_status,
    COUNT(*) AS record_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM sba_loans
GROUP BY 1
ORDER BY record_count DESC;

-- 3.3 Date consistency checks
SELECT
    'Date Validation' AS check_type,
    COUNT(*) AS total_loans,
    COUNT(*) FILTER (WHERE approval_date > CURRENT_DATE) AS future_approval_dates,
    COUNT(*) FILTER (WHERE approval_date < '1990-01-01') AS ancient_approval_dates,
    COUNT(*) FILTER (WHERE disbursement_date < approval_date) AS disbursement_before_approval,
    COUNT(*) FILTER (WHERE chargeoff_date IS NOT NULL AND chargeoff_date < disbursement_date) AS chargeoff_before_disbursement,
    COUNT(*) FILTER (WHERE approval_date IS NULL) AS missing_approval_date,
    COUNT(*) FILTER (WHERE approval_fy != EXTRACT(YEAR FROM approval_date)
                     AND approval_fy != EXTRACT(YEAR FROM approval_date) + 1) AS fy_mismatch
FROM sba_loans;

-- 3.4 Loan status distribution and validation
SELECT
    COALESCE(loan_status, 'NULL/Unknown') AS status,
    COUNT(*) AS loan_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total,
    ROUND(AVG(gross_approved), 2) AS avg_loan_amount,
    SUM(gross_approved) AS total_volume
FROM sba_loans
GROUP BY loan_status
ORDER BY loan_count DESC;

-- ============================================================================
-- SECTION 4: DUPLICATE DETECTION
-- Identify potential duplicate records
-- ============================================================================

-- 4.1 Exact duplicate loan IDs (should be 0)
SELECT
    loan_id,
    COUNT(*) AS duplicate_count
FROM sba_loans
GROUP BY loan_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC
LIMIT 10;

-- 4.2 Potential duplicates based on business attributes
SELECT
    business_name,
    city,
    state,
    approval_date,
    gross_approved,
    COUNT(*) AS potential_duplicates
FROM sba_loans
WHERE business_name IS NOT NULL
GROUP BY business_name, city, state, approval_date, gross_approved
HAVING COUNT(*) > 1
ORDER BY potential_duplicates DESC
LIMIT 20;

-- ============================================================================
-- SECTION 5: REFERENTIAL INTEGRITY CHECKS
-- Verify relationships between related fields
-- ============================================================================

-- 5.1 SBA guarantee percentage validation
SELECT
    CASE
        WHEN gross_approved IS NULL OR gross_approved = 0 THEN 'Cannot calculate'
        WHEN sba_approved IS NULL THEN 'Missing SBA amount'
        WHEN sba_approved > gross_approved THEN 'SBA > Gross (invalid)'
        WHEN (sba_approved / gross_approved) > 0.90 THEN 'High guarantee (>90%)'
        WHEN (sba_approved / gross_approved) BETWEEN 0.70 AND 0.90 THEN 'Standard (70-90%)'
        WHEN (sba_approved / gross_approved) < 0.50 THEN 'Low guarantee (<50%)'
        ELSE 'Normal (50-70%)'
    END AS guarantee_category,
    COUNT(*) AS loan_count,
    ROUND(AVG(CASE WHEN gross_approved > 0 THEN sba_approved / gross_approved * 100 END), 2) AS avg_guarantee_pct
FROM sba_loans
GROUP BY 1
ORDER BY loan_count DESC;

-- 5.2 Chargeoff consistency check
SELECT
    'Chargeoff Validation' AS check_type,
    COUNT(*) FILTER (WHERE loan_status = 'CHGOFF' AND chargeoff_date IS NULL) AS chgoff_missing_date,
    COUNT(*) FILTER (WHERE loan_status = 'CHGOFF' AND chargeoff_amount IS NULL) AS chgoff_missing_amount,
    COUNT(*) FILTER (WHERE loan_status = 'CHGOFF' AND chargeoff_amount = 0) AS chgoff_zero_amount,
    COUNT(*) FILTER (WHERE loan_status = 'PIF' AND chargeoff_date IS NOT NULL) AS pif_with_chgoff_date,
    COUNT(*) FILTER (WHERE loan_status = 'PIF' AND chargeoff_amount > 0) AS pif_with_chgoff_amount
FROM sba_loans;

-- ============================================================================
-- SECTION 6: CREATE CLEANED VIEW
-- Standardized view with cleaned and derived fields
-- ============================================================================

-- Drop existing view if it exists
DROP VIEW IF EXISTS vw_sba_loans_clean;

-- Create cleaned view with standardized fields and derived columns
CREATE VIEW vw_sba_loans_clean AS
SELECT
    -- Primary key
    loan_id,

    -- Borrower information (cleaned)
    COALESCE(NULLIF(TRIM(business_name), ''), 'Unknown') AS business_name,
    COALESCE(NULLIF(TRIM(city), ''), 'Unknown') AS city,
    UPPER(COALESCE(state, 'XX')) AS state,
    LEFT(COALESCE(zip, '00000'), 5) AS zip_5,

    -- Lender information (cleaned)
    COALESCE(NULLIF(TRIM(bank_name), ''), 'Unknown Lender') AS bank_name,
    UPPER(COALESCE(bank_state, 'XX')) AS bank_state,

    -- Industry (cleaned and derived)
    COALESCE(naics, '000000') AS naics,
    LEFT(COALESCE(naics, '00'), 2) AS naics_sector,
    COALESCE(n.sector_name, 'Unknown') AS industry_sector,

    -- Dates (validated)
    approval_date,
    COALESCE(approval_fy, EXTRACT(YEAR FROM approval_date)::INTEGER) AS approval_fy,
    disbursement_date,
    chargeoff_date,

    -- Loan terms (cleaned)
    COALESCE(term_months, 0) AS term_months,
    CASE
        WHEN term_months <= 12 THEN 'Short (<=1yr)'
        WHEN term_months <= 60 THEN 'Medium (1-5yr)'
        WHEN term_months <= 120 THEN 'Long (5-10yr)'
        WHEN term_months > 120 THEN 'Extended (>10yr)'
        ELSE 'Unknown'
    END AS term_category,

    -- Business characteristics (cleaned)
    COALESCE(num_employees, 0) AS num_employees,
    CASE
        WHEN num_employees IS NULL OR num_employees = 0 THEN 'Unknown'
        WHEN num_employees <= 10 THEN 'Micro (1-10)'
        WHEN num_employees <= 50 THEN 'Small (11-50)'
        WHEN num_employees <= 250 THEN 'Medium (51-250)'
        ELSE 'Large (250+)'
    END AS business_size,
    CASE new_business
        WHEN 1 THEN 'Existing'
        WHEN 2 THEN 'New'
        ELSE 'Unknown'
    END AS business_type,
    COALESCE(jobs_created, 0) AS jobs_created,
    COALESCE(jobs_retained, 0) AS jobs_retained,
    CASE urban_rural
        WHEN 1 THEN 'Urban'
        WHEN 2 THEN 'Rural'
        ELSE 'Unknown'
    END AS location_type,

    -- Program flags (cleaned)
    COALESCE(rev_line_of_credit, 'N') = 'Y' AS is_revolving_line,
    COALESCE(low_doc, 'N') = 'Y' AS is_low_doc,

    -- Financial amounts (cleaned, NULLs to 0)
    COALESCE(gross_approved, 0) AS gross_approved,
    COALESCE(sba_approved, 0) AS sba_approved,
    COALESCE(disbursement_gross, 0) AS disbursement_gross,
    COALESCE(balance_gross, 0) AS balance_gross,
    COALESCE(chargeoff_amount, 0) AS chargeoff_amount,

    -- Derived financial metrics
    CASE
        WHEN COALESCE(gross_approved, 0) < 50000 THEN 'Micro (<$50K)'
        WHEN gross_approved < 150000 THEN 'Small ($50K-$150K)'
        WHEN gross_approved < 350000 THEN 'Medium ($150K-$350K)'
        WHEN gross_approved < 1000000 THEN 'Large ($350K-$1M)'
        ELSE 'Jumbo (>$1M)'
    END AS loan_size_bucket,
    CASE
        WHEN COALESCE(gross_approved, 0) > 0
        THEN ROUND((COALESCE(sba_approved, 0) / gross_approved) * 100, 2)
        ELSE 0
    END AS sba_guarantee_pct,

    -- Loan outcome (cleaned)
    COALESCE(loan_status, 'UNKNOWN') AS loan_status,
    loan_status = 'CHGOFF' AS is_defaulted,
    loan_status = 'PIF' AS is_paid_in_full,

    -- Calculated fields for analysis
    CASE
        WHEN loan_status = 'CHGOFF' AND COALESCE(gross_approved, 0) > 0
        THEN ROUND((COALESCE(chargeoff_amount, 0) / gross_approved) * 100, 2)
        ELSE 0
    END AS loss_severity_pct,

    -- Time-based derived fields
    EXTRACT(YEAR FROM approval_date) AS vintage_year,
    EXTRACT(QUARTER FROM approval_date) AS vintage_quarter,
    EXTRACT(MONTH FROM approval_date) AS vintage_month,

    -- Metadata
    CURRENT_TIMESTAMP AS processed_at

FROM sba_loans s
LEFT JOIN naics_codes n ON LEFT(s.naics, 2) = n.naics_code;

COMMENT ON VIEW vw_sba_loans_clean IS 'Cleaned and standardized SBA loan data for analysis';

-- ============================================================================
-- SECTION 7: DATA QUALITY SUMMARY REPORT
-- Executive summary of data quality issues
-- ============================================================================

-- Final quality score card
WITH quality_metrics AS (
    SELECT
        COUNT(*) AS total_records,
        COUNT(*) FILTER (WHERE loan_id IS NOT NULL) AS has_loan_id,
        COUNT(*) FILTER (WHERE state IS NOT NULL AND LENGTH(state) = 2) AS has_valid_state,
        COUNT(*) FILTER (WHERE naics IS NOT NULL AND LENGTH(naics) >= 2) AS has_valid_naics,
        COUNT(*) FILTER (WHERE approval_date IS NOT NULL AND approval_date <= CURRENT_DATE) AS has_valid_date,
        COUNT(*) FILTER (WHERE gross_approved IS NOT NULL AND gross_approved > 0) AS has_valid_amount,
        COUNT(*) FILTER (WHERE loan_status IN ('PIF', 'CHGOFF')) AS has_known_outcome,
        COUNT(*) FILTER (WHERE term_months IS NOT NULL AND term_months > 0 AND term_months <= 360) AS has_valid_term
    FROM sba_loans
)
SELECT
    'Data Quality Summary' AS report,
    total_records,
    ROUND(100.0 * has_loan_id / total_records, 2) AS pct_with_loan_id,
    ROUND(100.0 * has_valid_state / total_records, 2) AS pct_valid_state,
    ROUND(100.0 * has_valid_naics / total_records, 2) AS pct_valid_naics,
    ROUND(100.0 * has_valid_date / total_records, 2) AS pct_valid_date,
    ROUND(100.0 * has_valid_amount / total_records, 2) AS pct_valid_amount,
    ROUND(100.0 * has_known_outcome / total_records, 2) AS pct_known_outcome,
    ROUND(100.0 * has_valid_term / total_records, 2) AS pct_valid_term,
    -- Overall quality score (average of all metrics)
    ROUND((
        100.0 * has_loan_id / total_records +
        100.0 * has_valid_state / total_records +
        100.0 * has_valid_naics / total_records +
        100.0 * has_valid_date / total_records +
        100.0 * has_valid_amount / total_records +
        100.0 * has_known_outcome / total_records +
        100.0 * has_valid_term / total_records
    ) / 7, 2) AS overall_quality_score
FROM quality_metrics;

-- ============================================================================
-- SECTION 8: RECOMMENDED EXCLUSIONS
-- Identify records to exclude from analysis
-- ============================================================================

-- Create exclusion flags for problematic records
DROP VIEW IF EXISTS vw_analysis_exclusions;

CREATE VIEW vw_analysis_exclusions AS
SELECT
    loan_id,
    CASE WHEN gross_approved IS NULL OR gross_approved <= 0 THEN 1 ELSE 0 END AS exclude_invalid_amount,
    CASE WHEN loan_status NOT IN ('PIF', 'CHGOFF') THEN 1 ELSE 0 END AS exclude_unknown_outcome,
    CASE WHEN approval_date IS NULL OR approval_date > CURRENT_DATE THEN 1 ELSE 0 END AS exclude_invalid_date,
    CASE WHEN state IS NULL OR LENGTH(state) != 2 THEN 1 ELSE 0 END AS exclude_invalid_state,
    CASE
        WHEN gross_approved IS NULL OR gross_approved <= 0
          OR loan_status NOT IN ('PIF', 'CHGOFF')
          OR approval_date IS NULL
          OR approval_date > CURRENT_DATE
        THEN 1
        ELSE 0
    END AS exclude_from_analysis
FROM sba_loans;

-- Summary of exclusions
SELECT
    'Exclusion Summary' AS report,
    COUNT(*) AS total_records,
    SUM(exclude_invalid_amount) AS excluded_invalid_amount,
    SUM(exclude_unknown_outcome) AS excluded_unknown_outcome,
    SUM(exclude_invalid_date) AS excluded_invalid_date,
    SUM(exclude_invalid_state) AS excluded_invalid_state,
    SUM(exclude_from_analysis) AS total_excluded,
    COUNT(*) - SUM(exclude_from_analysis) AS records_for_analysis,
    ROUND(100.0 * (COUNT(*) - SUM(exclude_from_analysis)) / COUNT(*), 2) AS pct_usable
FROM vw_analysis_exclusions;
