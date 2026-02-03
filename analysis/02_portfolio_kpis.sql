/*
================================================================================
SBA 7(a) LOAN PORTFOLIO ANALYTICS
Analysis: 02_portfolio_kpis.sql
================================================================================

Purpose: Calculate core lending performance metrics and portfolio KPIs
Skills Demonstrated: Aggregations, GROUP BY, HAVING, subqueries, CASE expressions

Description:
    This script calculates key performance indicators for the SBA loan portfolio
    including origination volumes, average loan sizes, approval trends, and
    portfolio composition analysis.

================================================================================
*/

-- ============================================================================
-- SECTION 1: ORIGINATION VOLUME ANALYSIS
-- Total loans approved by various time periods
-- ============================================================================

-- 1.1 Annual origination volume and growth
SELECT
    approval_fy AS fiscal_year,
    COUNT(*) AS loan_count,
    SUM(gross_approved) AS total_approved,
    SUM(sba_approved) AS total_sba_guaranteed,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    -- Year-over-year growth calculation using subquery
    ROUND(100.0 * (
        SUM(gross_approved) - (
            SELECT SUM(gross_approved)
            FROM vw_sba_loans_clean prev
            WHERE prev.approval_fy = vw_sba_loans_clean.approval_fy - 1
        )
    ) / NULLIF((
        SELECT SUM(gross_approved)
        FROM vw_sba_loans_clean prev
        WHERE prev.approval_fy = vw_sba_loans_clean.approval_fy - 1
    ), 0), 2) AS yoy_growth_pct
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
  AND approval_fy IS NOT NULL
GROUP BY approval_fy
ORDER BY approval_fy DESC;

-- 1.2 Monthly origination trends (last 5 years)
SELECT
    DATE_TRUNC('month', approval_date)::DATE AS month,
    COUNT(*) AS loan_count,
    SUM(gross_approved) AS monthly_volume,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    SUM(SUM(gross_approved)) OVER (
        ORDER BY DATE_TRUNC('month', approval_date)
        ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
    ) AS rolling_12mo_volume
FROM vw_sba_loans_clean
WHERE approval_date >= CURRENT_DATE - INTERVAL '5 years'
  AND loan_status IN ('PIF', 'CHGOFF')
GROUP BY DATE_TRUNC('month', approval_date)
ORDER BY month DESC;

-- 1.3 Quarterly origination summary
SELECT
    vintage_year,
    vintage_quarter,
    COUNT(*) AS loan_count,
    SUM(gross_approved) AS total_volume,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    ROUND(AVG(sba_guarantee_pct), 2) AS avg_guarantee_pct,
    SUM(jobs_created + jobs_retained) AS total_jobs_impacted
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY vintage_year, vintage_quarter
ORDER BY vintage_year DESC, vintage_quarter DESC;

-- ============================================================================
-- SECTION 2: AVERAGE LOAN SIZE ANALYSIS
-- By industry, state, year, and other dimensions
-- ============================================================================

-- 2.1 Average loan size by industry sector
SELECT
    industry_sector,
    COUNT(*) AS loan_count,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY gross_approved), 2) AS median_loan_size,
    MIN(gross_approved) AS min_loan,
    MAX(gross_approved) AS max_loan,
    SUM(gross_approved) AS total_volume,
    ROUND(100.0 * SUM(gross_approved) / SUM(SUM(gross_approved)) OVER (), 2) AS pct_of_portfolio
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
  AND industry_sector != 'Unknown'
GROUP BY industry_sector
HAVING COUNT(*) >= 100  -- Minimum sample size
ORDER BY avg_loan_size DESC;

-- 2.2 Average loan size by state (Top 20)
SELECT
    state,
    sr.state_name,
    sr.region,
    COUNT(*) AS loan_count,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    SUM(gross_approved) AS total_volume,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_loans
FROM vw_sba_loans_clean l
LEFT JOIN state_regions sr ON l.state = sr.state_code
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY state, sr.state_name, sr.region
ORDER BY total_volume DESC
LIMIT 20;

-- 2.3 Average loan size by year and business type
SELECT
    vintage_year,
    business_type,
    COUNT(*) AS loan_count,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    ROUND(AVG(term_months), 1) AS avg_term_months,
    ROUND(AVG(sba_guarantee_pct), 2) AS avg_guarantee_pct
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
  AND vintage_year >= 2010
GROUP BY vintage_year, business_type
ORDER BY vintage_year DESC, business_type;

-- 2.4 Loan size trends over time
SELECT
    vintage_year,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    ROUND(AVG(CASE WHEN business_type = 'New' THEN gross_approved END), 2) AS avg_new_business,
    ROUND(AVG(CASE WHEN business_type = 'Existing' THEN gross_approved END), 2) AS avg_existing_business,
    ROUND(AVG(CASE WHEN location_type = 'Urban' THEN gross_approved END), 2) AS avg_urban,
    ROUND(AVG(CASE WHEN location_type = 'Rural' THEN gross_approved END), 2) AS avg_rural
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY vintage_year
ORDER BY vintage_year;

-- ============================================================================
-- SECTION 3: APPROVAL RATE TRENDS
-- Year-over-year changes in lending activity
-- ============================================================================

-- 3.1 Year-over-year growth analysis
WITH yearly_metrics AS (
    SELECT
        vintage_year,
        COUNT(*) AS loan_count,
        SUM(gross_approved) AS total_volume,
        ROUND(AVG(gross_approved), 2) AS avg_loan_size
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
    GROUP BY vintage_year
)
SELECT
    vintage_year,
    loan_count,
    total_volume,
    avg_loan_size,
    LAG(loan_count) OVER (ORDER BY vintage_year) AS prev_year_count,
    ROUND(100.0 * (loan_count - LAG(loan_count) OVER (ORDER BY vintage_year))
        / NULLIF(LAG(loan_count) OVER (ORDER BY vintage_year), 0), 2) AS count_growth_pct,
    LAG(total_volume) OVER (ORDER BY vintage_year) AS prev_year_volume,
    ROUND(100.0 * (total_volume - LAG(total_volume) OVER (ORDER BY vintage_year))
        / NULLIF(LAG(total_volume) OVER (ORDER BY vintage_year), 0), 2) AS volume_growth_pct
FROM yearly_metrics
ORDER BY vintage_year DESC;

-- 3.2 Compound annual growth rate (CAGR) by segment
WITH segment_growth AS (
    SELECT
        industry_sector,
        MIN(vintage_year) AS start_year,
        MAX(vintage_year) AS end_year,
        SUM(CASE WHEN vintage_year = (SELECT MIN(vintage_year) FROM vw_sba_loans_clean WHERE loan_status IN ('PIF', 'CHGOFF'))
            THEN gross_approved ELSE 0 END) AS start_volume,
        SUM(CASE WHEN vintage_year = (SELECT MAX(vintage_year) FROM vw_sba_loans_clean WHERE loan_status IN ('PIF', 'CHGOFF'))
            THEN gross_approved ELSE 0 END) AS end_volume,
        COUNT(DISTINCT vintage_year) AS num_years
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
      AND industry_sector != 'Unknown'
    GROUP BY industry_sector
    HAVING COUNT(DISTINCT vintage_year) > 5
)
SELECT
    industry_sector,
    start_year,
    end_year,
    start_volume,
    end_volume,
    num_years,
    CASE
        WHEN start_volume > 0 AND end_volume > 0
        THEN ROUND(100.0 * (POWER(end_volume / start_volume, 1.0 / num_years) - 1), 2)
        ELSE NULL
    END AS cagr_pct
FROM segment_growth
WHERE start_volume > 0
ORDER BY CASE
    WHEN start_volume > 0 AND end_volume > 0
    THEN POWER(end_volume / start_volume, 1.0 / num_years) - 1
    ELSE 0
END DESC;

-- ============================================================================
-- SECTION 4: PORTFOLIO COMPOSITION
-- Distribution by loan size buckets and other dimensions
-- ============================================================================

-- 4.1 Loan size distribution
SELECT
    loan_size_bucket,
    COUNT(*) AS loan_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_count,
    SUM(gross_approved) AS total_volume,
    ROUND(100.0 * SUM(gross_approved) / SUM(SUM(gross_approved)) OVER (), 2) AS pct_of_volume,
    ROUND(AVG(gross_approved), 2) AS avg_in_bucket,
    ROUND(AVG(term_months), 1) AS avg_term_months
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY loan_size_bucket
ORDER BY
    CASE loan_size_bucket
        WHEN 'Micro (<$50K)' THEN 1
        WHEN 'Small ($50K-$150K)' THEN 2
        WHEN 'Medium ($150K-$350K)' THEN 3
        WHEN 'Large ($350K-$1M)' THEN 4
        WHEN 'Jumbo (>$1M)' THEN 5
    END;

-- 4.2 Portfolio composition by term category
SELECT
    term_category,
    COUNT(*) AS loan_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_count,
    SUM(gross_approved) AS total_volume,
    ROUND(100.0 * SUM(gross_approved) / SUM(SUM(gross_approved)) OVER (), 2) AS pct_of_volume,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    ROUND(AVG(sba_guarantee_pct), 2) AS avg_guarantee_pct
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY term_category
ORDER BY
    CASE term_category
        WHEN 'Short (<=1yr)' THEN 1
        WHEN 'Medium (1-5yr)' THEN 2
        WHEN 'Long (5-10yr)' THEN 3
        WHEN 'Extended (>10yr)' THEN 4
        ELSE 5
    END;

-- 4.3 Business size segmentation
SELECT
    business_size,
    business_type,
    COUNT(*) AS loan_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total,
    SUM(gross_approved) AS total_volume,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    SUM(jobs_created) AS total_jobs_created,
    SUM(jobs_retained) AS total_jobs_retained
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY business_size, business_type
ORDER BY business_size, business_type;

-- 4.4 Urban vs Rural portfolio mix
SELECT
    location_type,
    vintage_year,
    COUNT(*) AS loan_count,
    SUM(gross_approved) AS total_volume,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY vintage_year), 2) AS pct_of_year
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
  AND vintage_year >= 2010
GROUP BY location_type, vintage_year
ORDER BY vintage_year DESC, location_type;

-- ============================================================================
-- SECTION 5: SBA GUARANTEE ANALYSIS
-- Understanding government risk exposure
-- ============================================================================

-- 5.1 Guarantee percentage distribution
SELECT
    CASE
        WHEN sba_guarantee_pct >= 90 THEN '90-100%'
        WHEN sba_guarantee_pct >= 80 THEN '80-89%'
        WHEN sba_guarantee_pct >= 75 THEN '75-79%'
        WHEN sba_guarantee_pct >= 50 THEN '50-74%'
        ELSE '<50%'
    END AS guarantee_bucket,
    COUNT(*) AS loan_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_loans,
    SUM(gross_approved) AS total_gross,
    SUM(sba_approved) AS total_sba_exposure,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
  AND gross_approved > 0
GROUP BY 1
ORDER BY
    CASE
        WHEN sba_guarantee_pct >= 90 THEN 1
        WHEN sba_guarantee_pct >= 80 THEN 2
        WHEN sba_guarantee_pct >= 75 THEN 3
        WHEN sba_guarantee_pct >= 50 THEN 4
        ELSE 5
    END;

-- 5.2 SBA exposure by year
SELECT
    vintage_year,
    COUNT(*) AS loan_count,
    SUM(gross_approved) AS total_gross_approved,
    SUM(sba_approved) AS total_sba_guaranteed,
    ROUND(100.0 * SUM(sba_approved) / NULLIF(SUM(gross_approved), 0), 2) AS portfolio_guarantee_pct,
    ROUND(AVG(sba_guarantee_pct), 2) AS avg_loan_guarantee_pct
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY vintage_year
ORDER BY vintage_year DESC;

-- ============================================================================
-- SECTION 6: LENDER PERFORMANCE OVERVIEW
-- Bank-level lending activity
-- ============================================================================

-- 6.1 Top 25 lenders by volume
SELECT
    bank_name,
    bank_state,
    COUNT(*) AS loan_count,
    SUM(gross_approved) AS total_volume,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 4) AS market_share_count,
    ROUND(100.0 * SUM(gross_approved) / SUM(SUM(gross_approved)) OVER (), 4) AS market_share_volume,
    COUNT(DISTINCT state) AS states_served
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
  AND bank_name != 'Unknown Lender'
GROUP BY bank_name, bank_state
HAVING COUNT(*) >= 50  -- Minimum activity threshold
ORDER BY total_volume DESC
LIMIT 25;

-- 6.2 Lender concentration analysis
WITH lender_ranked AS (
    SELECT
        bank_name,
        SUM(gross_approved) AS total_volume,
        ROW_NUMBER() OVER (ORDER BY SUM(gross_approved) DESC) AS volume_rank
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
      AND bank_name != 'Unknown Lender'
    GROUP BY bank_name
),
portfolio_total AS (
    SELECT SUM(gross_approved) AS total FROM vw_sba_loans_clean WHERE loan_status IN ('PIF', 'CHGOFF')
)
SELECT
    'Top 10 Lenders' AS segment,
    SUM(total_volume) AS segment_volume,
    ROUND(100.0 * SUM(total_volume) / (SELECT total FROM portfolio_total), 2) AS pct_of_portfolio
FROM lender_ranked
WHERE volume_rank <= 10

UNION ALL

SELECT
    'Top 25 Lenders',
    SUM(total_volume),
    ROUND(100.0 * SUM(total_volume) / (SELECT total FROM portfolio_total), 2)
FROM lender_ranked
WHERE volume_rank <= 25

UNION ALL

SELECT
    'Top 50 Lenders',
    SUM(total_volume),
    ROUND(100.0 * SUM(total_volume) / (SELECT total FROM portfolio_total), 2)
FROM lender_ranked
WHERE volume_rank <= 50

UNION ALL

SELECT
    'All Other Lenders',
    SUM(total_volume),
    ROUND(100.0 * SUM(total_volume) / (SELECT total FROM portfolio_total), 2)
FROM lender_ranked
WHERE volume_rank > 50;

-- ============================================================================
-- SECTION 7: PORTFOLIO KPI DASHBOARD SUMMARY
-- Executive-level metrics in one view
-- ============================================================================

-- Create summary view for dashboarding
DROP VIEW IF EXISTS vw_portfolio_kpi_summary;

CREATE VIEW vw_portfolio_kpi_summary AS
WITH current_metrics AS (
    SELECT
        MAX(vintage_year) AS current_year,
        COUNT(*) AS total_loans,
        SUM(gross_approved) AS total_volume,
        SUM(sba_approved) AS total_sba_exposure,
        ROUND(AVG(gross_approved), 2) AS avg_loan_size,
        ROUND(AVG(term_months), 1) AS avg_term_months,
        ROUND(AVG(sba_guarantee_pct), 2) AS avg_guarantee_pct,
        COUNT(DISTINCT bank_name) AS active_lenders,
        COUNT(DISTINCT state) AS states_with_loans,
        SUM(jobs_created + jobs_retained) AS total_jobs_impacted
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
),
ytd_metrics AS (
    SELECT
        COUNT(*) AS ytd_loan_count,
        SUM(gross_approved) AS ytd_volume
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
      AND vintage_year = (SELECT MAX(vintage_year) FROM vw_sba_loans_clean)
),
prior_ytd AS (
    SELECT
        COUNT(*) AS prior_ytd_count,
        SUM(gross_approved) AS prior_ytd_volume
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
      AND vintage_year = (SELECT MAX(vintage_year) - 1 FROM vw_sba_loans_clean)
)
SELECT
    c.current_year,
    c.total_loans,
    c.total_volume,
    c.total_sba_exposure,
    c.avg_loan_size,
    c.avg_term_months,
    c.avg_guarantee_pct,
    c.active_lenders,
    c.states_with_loans,
    c.total_jobs_impacted,
    y.ytd_loan_count,
    y.ytd_volume,
    p.prior_ytd_count,
    p.prior_ytd_volume,
    ROUND(100.0 * (y.ytd_volume - p.prior_ytd_volume) / NULLIF(p.prior_ytd_volume, 0), 2) AS ytd_vs_prior_pct
FROM current_metrics c
CROSS JOIN ytd_metrics y
CROSS JOIN prior_ytd p;

-- Display KPI summary
SELECT * FROM vw_portfolio_kpi_summary;
