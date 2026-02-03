/*
================================================================================
SBA 7(a) LOAN PORTFOLIO ANALYTICS
Analysis: 04_cohort_analysis.sql
================================================================================

Purpose: Vintage analysis, seasoning curves, and time-based cohort performance
Skills Demonstrated: Window functions (LAG, LEAD, running totals), date manipulation

Description:
    This script performs cohort-based analysis on the SBA loan portfolio,
    tracking how different vintage groups perform over time and identifying
    patterns in loan seasoning and default timing.

================================================================================
*/

-- ============================================================================
-- SECTION 1: VINTAGE ANALYSIS
-- Performance by origination year cohort
-- ============================================================================

-- 1.1 Comprehensive vintage performance summary
SELECT
    vintage_year,
    COUNT(*) AS total_loans,
    SUM(gross_approved) AS total_volume,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    SUM(chargeoff_amount) AS total_loss,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate,
    -- Year-over-year comparison
    LAG(COUNT(*)) OVER (ORDER BY vintage_year) AS prev_year_loans,
    LAG(ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2))
        OVER (ORDER BY vintage_year) AS prev_year_default_rate
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY vintage_year
ORDER BY vintage_year DESC;

-- 1.2 Vintage cohort comparison (benchmark to overall average)
WITH vintage_stats AS (
    SELECT
        vintage_year,
        COUNT(*) AS loans,
        ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
        ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
    GROUP BY vintage_year
),
portfolio_avg AS (
    SELECT
        ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS avg_default_rate,
        ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS avg_loss_rate
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
)
SELECT
    v.vintage_year,
    v.loans,
    v.default_rate,
    v.loss_rate,
    p.avg_default_rate AS portfolio_avg_default,
    p.avg_loss_rate AS portfolio_avg_loss,
    ROUND(v.default_rate - p.avg_default_rate, 2) AS default_vs_avg,
    ROUND(v.loss_rate - p.avg_loss_rate, 2) AS loss_vs_avg,
    CASE
        WHEN v.default_rate < p.avg_default_rate * 0.8 THEN 'Outperformer'
        WHEN v.default_rate > p.avg_default_rate * 1.2 THEN 'Underperformer'
        ELSE 'Average'
    END AS vintage_performance
FROM vintage_stats v
CROSS JOIN portfolio_avg p
ORDER BY vintage_year DESC;

-- 1.3 Quarterly vintage granularity
SELECT
    vintage_year,
    vintage_quarter,
    CONCAT(vintage_year, '-Q', vintage_quarter) AS cohort,
    COUNT(*) AS total_loans,
    SUM(gross_approved) AS total_volume,
    COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    -- Quarterly trend within year
    LAG(ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2))
        OVER (PARTITION BY vintage_year ORDER BY vintage_quarter) AS prev_quarter_default_rate
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
  AND vintage_year >= 2015
GROUP BY vintage_year, vintage_quarter
ORDER BY vintage_year DESC, vintage_quarter DESC;

-- ============================================================================
-- SECTION 2: SEASONING CURVES
-- How default rates evolve over loan age
-- ============================================================================

-- 2.1 Calculate months to default for defaulted loans
WITH default_timing AS (
    SELECT
        loan_id,
        vintage_year,
        approval_date,
        chargeoff_date,
        -- Calculate months between disbursement and chargeoff
        EXTRACT(YEAR FROM AGE(chargeoff_date, COALESCE(disbursement_date, approval_date))) * 12 +
        EXTRACT(MONTH FROM AGE(chargeoff_date, COALESCE(disbursement_date, approval_date))) AS months_to_default,
        gross_approved,
        chargeoff_amount
    FROM vw_sba_loans_clean
    WHERE is_defaulted = TRUE
      AND chargeoff_date IS NOT NULL
      AND approval_date IS NOT NULL
)
SELECT
    CASE
        WHEN months_to_default < 0 THEN 'Data Error'
        WHEN months_to_default <= 12 THEN '0-12 months'
        WHEN months_to_default <= 24 THEN '13-24 months'
        WHEN months_to_default <= 36 THEN '25-36 months'
        WHEN months_to_default <= 48 THEN '37-48 months'
        WHEN months_to_default <= 60 THEN '49-60 months'
        WHEN months_to_default <= 84 THEN '61-84 months'
        ELSE '85+ months'
    END AS seasoning_bucket,
    COUNT(*) AS default_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_defaults,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    SUM(chargeoff_amount) AS total_loss,
    ROUND(AVG(months_to_default), 1) AS avg_months_to_default
FROM default_timing
WHERE months_to_default >= 0
GROUP BY 1
ORDER BY
    CASE
        WHEN months_to_default <= 12 THEN 1
        WHEN months_to_default <= 24 THEN 2
        WHEN months_to_default <= 36 THEN 3
        WHEN months_to_default <= 48 THEN 4
        WHEN months_to_default <= 60 THEN 5
        WHEN months_to_default <= 84 THEN 6
        ELSE 7
    END;

-- 2.2 Seasoning curve by vintage year
WITH default_timing AS (
    SELECT
        loan_id,
        vintage_year,
        EXTRACT(YEAR FROM AGE(chargeoff_date, COALESCE(disbursement_date, approval_date))) * 12 +
        EXTRACT(MONTH FROM AGE(chargeoff_date, COALESCE(disbursement_date, approval_date))) AS months_to_default
    FROM vw_sba_loans_clean
    WHERE is_defaulted = TRUE
      AND chargeoff_date IS NOT NULL
),
seasoning_buckets AS (
    SELECT
        vintage_year,
        CASE
            WHEN months_to_default <= 12 THEN 'Year 1'
            WHEN months_to_default <= 24 THEN 'Year 2'
            WHEN months_to_default <= 36 THEN 'Year 3'
            WHEN months_to_default <= 48 THEN 'Year 4'
            WHEN months_to_default <= 60 THEN 'Year 5'
            ELSE 'Year 6+'
        END AS seasoning_year,
        COUNT(*) AS defaults
    FROM default_timing
    WHERE months_to_default >= 0
    GROUP BY vintage_year, 2
)
SELECT
    vintage_year,
    MAX(CASE WHEN seasoning_year = 'Year 1' THEN defaults ELSE 0 END) AS year_1_defaults,
    MAX(CASE WHEN seasoning_year = 'Year 2' THEN defaults ELSE 0 END) AS year_2_defaults,
    MAX(CASE WHEN seasoning_year = 'Year 3' THEN defaults ELSE 0 END) AS year_3_defaults,
    MAX(CASE WHEN seasoning_year = 'Year 4' THEN defaults ELSE 0 END) AS year_4_defaults,
    MAX(CASE WHEN seasoning_year = 'Year 5' THEN defaults ELSE 0 END) AS year_5_defaults,
    MAX(CASE WHEN seasoning_year = 'Year 6+' THEN defaults ELSE 0 END) AS year_6_plus_defaults,
    SUM(defaults) AS total_defaults
FROM seasoning_buckets
GROUP BY vintage_year
ORDER BY vintage_year DESC;

-- ============================================================================
-- SECTION 3: TIME-TO-DEFAULT ANALYSIS
-- Distribution of when defaults occur
-- ============================================================================

-- 3.1 Detailed time-to-default distribution
WITH default_timing AS (
    SELECT
        EXTRACT(YEAR FROM AGE(chargeoff_date, COALESCE(disbursement_date, approval_date))) * 12 +
        EXTRACT(MONTH FROM AGE(chargeoff_date, COALESCE(disbursement_date, approval_date))) AS months_to_default
    FROM vw_sba_loans_clean
    WHERE is_defaulted = TRUE
      AND chargeoff_date IS NOT NULL
      AND approval_date IS NOT NULL
)
SELECT
    'Time to Default Statistics' AS metric,
    COUNT(*) AS total_defaults,
    ROUND(AVG(months_to_default), 1) AS avg_months,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY months_to_default), 1) AS p25_months,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY months_to_default), 1) AS median_months,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY months_to_default), 1) AS p75_months,
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY months_to_default), 1) AS p90_months,
    MIN(months_to_default) AS min_months,
    MAX(months_to_default) AS max_months
FROM default_timing
WHERE months_to_default >= 0 AND months_to_default < 360;

-- 3.2 Time-to-default by loan characteristics
WITH default_timing AS (
    SELECT
        loan_id,
        loan_size_bucket,
        term_category,
        business_type,
        EXTRACT(YEAR FROM AGE(chargeoff_date, COALESCE(disbursement_date, approval_date))) * 12 +
        EXTRACT(MONTH FROM AGE(chargeoff_date, COALESCE(disbursement_date, approval_date))) AS months_to_default
    FROM vw_sba_loans_clean
    WHERE is_defaulted = TRUE
      AND chargeoff_date IS NOT NULL
)
SELECT
    loan_size_bucket,
    COUNT(*) AS default_count,
    ROUND(AVG(months_to_default), 1) AS avg_months_to_default,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY months_to_default), 1) AS median_months
FROM default_timing
WHERE months_to_default >= 0 AND months_to_default < 360
GROUP BY loan_size_bucket
ORDER BY avg_months_to_default;

-- 3.3 Time-to-default by term length
WITH default_timing AS (
    SELECT
        term_category,
        EXTRACT(YEAR FROM AGE(chargeoff_date, COALESCE(disbursement_date, approval_date))) * 12 +
        EXTRACT(MONTH FROM AGE(chargeoff_date, COALESCE(disbursement_date, approval_date))) AS months_to_default
    FROM vw_sba_loans_clean
    WHERE is_defaulted = TRUE
      AND chargeoff_date IS NOT NULL
)
SELECT
    term_category,
    COUNT(*) AS default_count,
    ROUND(AVG(months_to_default), 1) AS avg_months_to_default,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY months_to_default), 1) AS median_months
FROM default_timing
WHERE months_to_default >= 0 AND months_to_default < 360
GROUP BY term_category
ORDER BY avg_months_to_default;

-- ============================================================================
-- SECTION 4: CUMULATIVE DEFAULT RATES
-- Running default rates by cohort
-- ============================================================================

-- 4.1 Cumulative default rate by vintage (as of each calendar year)
WITH vintage_yearly_defaults AS (
    SELECT
        vintage_year,
        EXTRACT(YEAR FROM chargeoff_date) AS default_year,
        COUNT(*) AS defaults_in_year,
        SUM(chargeoff_amount) AS loss_in_year
    FROM vw_sba_loans_clean
    WHERE is_defaulted = TRUE
      AND chargeoff_date IS NOT NULL
    GROUP BY vintage_year, EXTRACT(YEAR FROM chargeoff_date)
),
vintage_totals AS (
    SELECT
        vintage_year,
        COUNT(*) AS total_loans,
        SUM(gross_approved) AS total_volume
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
    GROUP BY vintage_year
)
SELECT
    v.vintage_year,
    d.default_year,
    d.default_year - v.vintage_year AS years_since_origination,
    v.total_loans,
    d.defaults_in_year,
    SUM(d.defaults_in_year) OVER (
        PARTITION BY v.vintage_year
        ORDER BY d.default_year
        ROWS UNBOUNDED PRECEDING
    ) AS cumulative_defaults,
    ROUND(100.0 * SUM(d.defaults_in_year) OVER (
        PARTITION BY v.vintage_year
        ORDER BY d.default_year
        ROWS UNBOUNDED PRECEDING
    ) / v.total_loans, 2) AS cumulative_default_rate,
    SUM(d.loss_in_year) OVER (
        PARTITION BY v.vintage_year
        ORDER BY d.default_year
        ROWS UNBOUNDED PRECEDING
    ) AS cumulative_loss
FROM vintage_totals v
JOIN vintage_yearly_defaults d ON v.vintage_year = d.vintage_year
WHERE v.vintage_year >= 2005
ORDER BY v.vintage_year, d.default_year;

-- 4.2 Cumulative default curve comparison (normalized by months since origination)
WITH cohort_defaults AS (
    SELECT
        vintage_year,
        CEIL((EXTRACT(YEAR FROM AGE(chargeoff_date, approval_date)) * 12 +
              EXTRACT(MONTH FROM AGE(chargeoff_date, approval_date))) / 12.0) AS years_seasoned,
        COUNT(*) AS defaults
    FROM vw_sba_loans_clean
    WHERE is_defaulted = TRUE
      AND chargeoff_date IS NOT NULL
      AND approval_date IS NOT NULL
    GROUP BY vintage_year, 2
),
cohort_totals AS (
    SELECT vintage_year, COUNT(*) AS total_loans
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
    GROUP BY vintage_year
)
SELECT
    c.vintage_year,
    cd.years_seasoned,
    cd.defaults,
    SUM(cd.defaults) OVER (
        PARTITION BY c.vintage_year
        ORDER BY cd.years_seasoned
        ROWS UNBOUNDED PRECEDING
    ) AS cumulative_defaults,
    ROUND(100.0 * SUM(cd.defaults) OVER (
        PARTITION BY c.vintage_year
        ORDER BY cd.years_seasoned
        ROWS UNBOUNDED PRECEDING
    ) / c.total_loans, 2) AS cumulative_default_rate_pct
FROM cohort_totals c
JOIN cohort_defaults cd ON c.vintage_year = cd.vintage_year
WHERE c.vintage_year BETWEEN 2010 AND 2020
  AND cd.years_seasoned BETWEEN 1 AND 10
ORDER BY c.vintage_year, cd.years_seasoned;

-- ============================================================================
-- SECTION 5: VINTAGE PERFORMANCE HEAT MAP DATA
-- Matrix format for visualization
-- ============================================================================

-- 5.1 Vintage x Seasoning Year matrix (default rates)
WITH seasoning_data AS (
    SELECT
        vintage_year,
        CEIL((EXTRACT(YEAR FROM AGE(chargeoff_date, approval_date)) * 12 +
              EXTRACT(MONTH FROM AGE(chargeoff_date, approval_date))) / 12.0) AS seasoning_year,
        COUNT(*) AS defaults
    FROM vw_sba_loans_clean
    WHERE is_defaulted = TRUE
      AND chargeoff_date IS NOT NULL
    GROUP BY vintage_year, 2
),
vintage_counts AS (
    SELECT vintage_year, COUNT(*) AS total_loans
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
    GROUP BY vintage_year
)
SELECT
    v.vintage_year,
    ROUND(100.0 * COALESCE(MAX(CASE WHEN s.seasoning_year = 1 THEN s.defaults END), 0) / v.total_loans, 2) AS yr1_default_rate,
    ROUND(100.0 * COALESCE(MAX(CASE WHEN s.seasoning_year = 2 THEN s.defaults END), 0) / v.total_loans, 2) AS yr2_default_rate,
    ROUND(100.0 * COALESCE(MAX(CASE WHEN s.seasoning_year = 3 THEN s.defaults END), 0) / v.total_loans, 2) AS yr3_default_rate,
    ROUND(100.0 * COALESCE(MAX(CASE WHEN s.seasoning_year = 4 THEN s.defaults END), 0) / v.total_loans, 2) AS yr4_default_rate,
    ROUND(100.0 * COALESCE(MAX(CASE WHEN s.seasoning_year = 5 THEN s.defaults END), 0) / v.total_loans, 2) AS yr5_default_rate,
    v.total_loans
FROM vintage_counts v
LEFT JOIN seasoning_data s ON v.vintage_year = s.vintage_year
WHERE v.vintage_year >= 2005
GROUP BY v.vintage_year, v.total_loans
ORDER BY v.vintage_year DESC;

-- ============================================================================
-- SECTION 6: COHORT RETENTION ANALYSIS
-- Track loan outcomes over time
-- ============================================================================

-- 6.1 Loan status progression by vintage
WITH vintage_outcomes AS (
    SELECT
        vintage_year,
        COUNT(*) AS total_originated,
        COUNT(*) FILTER (WHERE loan_status = 'PIF') AS paid_in_full,
        COUNT(*) FILTER (WHERE loan_status = 'CHGOFF') AS charged_off,
        COUNT(*) FILTER (WHERE loan_status NOT IN ('PIF', 'CHGOFF') OR loan_status IS NULL) AS other_unknown
    FROM vw_sba_loans_clean
    GROUP BY vintage_year
)
SELECT
    vintage_year,
    total_originated,
    paid_in_full,
    charged_off,
    other_unknown,
    ROUND(100.0 * paid_in_full / total_originated, 2) AS pif_rate,
    ROUND(100.0 * charged_off / total_originated, 2) AS chargeoff_rate,
    -- Running totals across vintages
    SUM(total_originated) OVER (ORDER BY vintage_year) AS cumulative_originated,
    SUM(charged_off) OVER (ORDER BY vintage_year) AS cumulative_chargeoffs
FROM vintage_outcomes
ORDER BY vintage_year DESC;

-- 6.2 Survival analysis proxy (loans remaining active by seasoning)
-- This simulates how many loans "survive" (don't default) at each time point
WITH loan_events AS (
    SELECT
        vintage_year,
        loan_id,
        CASE
            WHEN is_defaulted THEN
                CEIL((EXTRACT(YEAR FROM AGE(chargeoff_date, approval_date)) * 12 +
                      EXTRACT(MONTH FROM AGE(chargeoff_date, approval_date))) / 12.0)
            ELSE 99  -- Still active/PIF, assign high value
        END AS event_year
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
),
survival AS (
    SELECT
        vintage_year,
        year_n,
        COUNT(*) FILTER (WHERE event_year > year_n) AS surviving,
        COUNT(*) AS total
    FROM loan_events
    CROSS JOIN generate_series(0, 10) AS year_n
    GROUP BY vintage_year, year_n
)
SELECT
    vintage_year,
    year_n AS years_since_origination,
    surviving,
    total,
    ROUND(100.0 * surviving / NULLIF(total, 0), 2) AS survival_rate_pct
FROM survival
WHERE vintage_year BETWEEN 2010 AND 2018
ORDER BY vintage_year, year_n;

-- ============================================================================
-- SECTION 7: ECONOMIC CYCLE CORRELATION
-- Compare vintage performance to economic conditions
-- ============================================================================

-- 7.1 Pre/Post recession vintage comparison
-- (2007-2009 Financial Crisis, 2020 COVID)
SELECT
    CASE
        WHEN vintage_year BETWEEN 2005 AND 2006 THEN 'Pre-2008 Crisis'
        WHEN vintage_year BETWEEN 2007 AND 2009 THEN 'During 2008 Crisis'
        WHEN vintage_year BETWEEN 2010 AND 2019 THEN 'Post-2008 Recovery'
        WHEN vintage_year = 2020 THEN 'COVID Year'
        WHEN vintage_year >= 2021 THEN 'Post-COVID'
        ELSE 'Earlier Vintages'
    END AS economic_period,
    COUNT(*) AS total_loans,
    SUM(gross_approved) AS total_volume,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    SUM(chargeoff_amount) AS total_loss,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY 1
ORDER BY MIN(vintage_year);

-- ============================================================================
-- SECTION 8: COHORT ANALYSIS SUMMARY VIEW
-- ============================================================================

DROP VIEW IF EXISTS vw_cohort_summary;

CREATE VIEW vw_cohort_summary AS
SELECT
    vintage_year,
    COUNT(*) AS cohort_size,
    SUM(gross_approved) AS cohort_volume,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    COUNT(*) FILTER (WHERE is_defaulted) AS total_defaults,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS lifetime_default_rate,
    SUM(chargeoff_amount) AS total_chargeoff,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS lifetime_loss_rate,
    -- Cohort age (years since origination)
    EXTRACT(YEAR FROM CURRENT_DATE) - vintage_year AS cohort_age_years
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY vintage_year
ORDER BY vintage_year DESC;

-- Display cohort summary
SELECT * FROM vw_cohort_summary;
