/*
================================================================================
SBA 7(a) LOAN PORTFOLIO ANALYTICS
Analysis: 06_executive_dashboard.sql
================================================================================

Purpose: Executive summary views combining all key metrics for reporting
Skills Demonstrated: Complex CTEs, UNION, materialized views, comprehensive aggregation

Description:
    This script creates executive-level dashboard views that consolidate key
    metrics from all analysis areas, providing drill-down capability and
    period-over-period comparisons.

================================================================================
*/

-- ============================================================================
-- SECTION 1: EXECUTIVE SUMMARY VIEW
-- One-stop view for all key portfolio metrics
-- ============================================================================

DROP VIEW IF EXISTS vw_executive_summary;

CREATE VIEW vw_executive_summary AS
WITH portfolio_totals AS (
    SELECT
        COUNT(*) AS total_loans,
        SUM(gross_approved) AS total_volume,
        SUM(sba_approved) AS total_sba_exposure,
        ROUND(AVG(gross_approved), 2) AS avg_loan_size,
        ROUND(AVG(term_months), 1) AS avg_term_months,
        ROUND(AVG(sba_guarantee_pct), 2) AS avg_guarantee_pct,
        COUNT(DISTINCT bank_name) AS active_lenders,
        COUNT(DISTINCT state) AS states_with_loans,
        COUNT(DISTINCT industry_sector) AS industries_represented,
        SUM(jobs_created) AS total_jobs_created,
        SUM(jobs_retained) AS total_jobs_retained
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
),
risk_metrics AS (
    SELECT
        COUNT(*) FILTER (WHERE is_defaulted) AS total_defaults,
        SUM(chargeoff_amount) AS total_chargeoff,
        ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) /
            NULLIF(COUNT(*), 0), 2) AS default_rate,
        ROUND(100.0 * SUM(chargeoff_amount) /
            NULLIF(SUM(gross_approved), 0), 2) AS loss_rate,
        ROUND(100.0 * SUM(chargeoff_amount) /
            NULLIF(SUM(CASE WHEN is_defaulted THEN gross_approved END), 0), 2) AS lgd
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
),
ytd_metrics AS (
    SELECT
        COUNT(*) AS ytd_loans,
        SUM(gross_approved) AS ytd_volume,
        COUNT(*) FILTER (WHERE is_defaulted) AS ytd_defaults,
        ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) /
            NULLIF(COUNT(*), 0), 2) AS ytd_default_rate
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
      AND vintage_year = (SELECT MAX(vintage_year) FROM vw_sba_loans_clean)
),
prior_ytd AS (
    SELECT
        COUNT(*) AS prior_loans,
        SUM(gross_approved) AS prior_volume,
        ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) /
            NULLIF(COUNT(*), 0), 2) AS prior_default_rate
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
      AND vintage_year = (SELECT MAX(vintage_year) - 1 FROM vw_sba_loans_clean)
)
SELECT
    -- Portfolio Overview
    p.total_loans,
    p.total_volume,
    p.total_sba_exposure,
    p.avg_loan_size,
    p.avg_term_months,
    p.avg_guarantee_pct,
    p.active_lenders,
    p.states_with_loans,
    p.industries_represented,
    p.total_jobs_created,
    p.total_jobs_retained,
    p.total_jobs_created + p.total_jobs_retained AS total_jobs_impacted,

    -- Risk Metrics
    r.total_defaults,
    r.total_chargeoff,
    r.default_rate,
    r.loss_rate,
    r.lgd AS loss_given_default,

    -- YTD Performance
    y.ytd_loans,
    y.ytd_volume,
    y.ytd_defaults,
    y.ytd_default_rate,

    -- Prior Year Comparison
    py.prior_loans,
    py.prior_volume,
    py.prior_default_rate,
    ROUND(100.0 * (y.ytd_volume - py.prior_volume) / NULLIF(py.prior_volume, 0), 2) AS volume_growth_pct,
    ROUND(y.ytd_default_rate - py.prior_default_rate, 2) AS default_rate_change,

    -- Timestamp
    CURRENT_TIMESTAMP AS as_of_date

FROM portfolio_totals p
CROSS JOIN risk_metrics r
CROSS JOIN ytd_metrics y
CROSS JOIN prior_ytd py;

-- ============================================================================
-- SECTION 2: MONTH-OVER-MONTH TREND CALCULATIONS
-- Rolling trend analysis
-- ============================================================================

DROP VIEW IF EXISTS vw_monthly_trends;

CREATE VIEW vw_monthly_trends AS
WITH monthly_data AS (
    SELECT
        DATE_TRUNC('month', approval_date)::DATE AS month,
        COUNT(*) AS loans,
        SUM(gross_approved) AS volume,
        ROUND(AVG(gross_approved), 2) AS avg_loan_size,
        COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
        SUM(chargeoff_amount) AS chargeoff
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
      AND approval_date >= CURRENT_DATE - INTERVAL '5 years'
    GROUP BY DATE_TRUNC('month', approval_date)
)
SELECT
    month,
    loans,
    volume,
    avg_loan_size,
    defaults,
    chargeoff,

    -- Month-over-month changes
    LAG(loans) OVER (ORDER BY month) AS prev_month_loans,
    ROUND(100.0 * (loans - LAG(loans) OVER (ORDER BY month)) /
        NULLIF(LAG(loans) OVER (ORDER BY month), 0), 2) AS mom_loan_growth,

    LAG(volume) OVER (ORDER BY month) AS prev_month_volume,
    ROUND(100.0 * (volume - LAG(volume) OVER (ORDER BY month)) /
        NULLIF(LAG(volume) OVER (ORDER BY month), 0), 2) AS mom_volume_growth,

    -- Rolling 3-month averages
    ROUND(AVG(loans) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS rolling_3mo_avg_loans,
    ROUND(AVG(volume) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS rolling_3mo_avg_volume,

    -- Rolling 12-month totals
    SUM(loans) OVER (ORDER BY month ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS rolling_12mo_loans,
    SUM(volume) OVER (ORDER BY month ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS rolling_12mo_volume,
    SUM(defaults) OVER (ORDER BY month ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS rolling_12mo_defaults,

    -- Rolling default rate
    ROUND(100.0 * SUM(defaults) OVER (ORDER BY month ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) /
        NULLIF(SUM(loans) OVER (ORDER BY month ROWS BETWEEN 11 PRECEDING AND CURRENT ROW), 0), 2)
        AS rolling_12mo_default_rate,

    -- Year-over-year comparison
    LAG(loans, 12) OVER (ORDER BY month) AS same_month_prior_year_loans,
    LAG(volume, 12) OVER (ORDER BY month) AS same_month_prior_year_volume,
    ROUND(100.0 * (loans - LAG(loans, 12) OVER (ORDER BY month)) /
        NULLIF(LAG(loans, 12) OVER (ORDER BY month), 0), 2) AS yoy_loan_growth,
    ROUND(100.0 * (volume - LAG(volume, 12) OVER (ORDER BY month)) /
        NULLIF(LAG(volume, 12) OVER (ORDER BY month), 0), 2) AS yoy_volume_growth

FROM monthly_data
ORDER BY month DESC;

-- ============================================================================
-- SECTION 3: YTD VS PRIOR YEAR COMPARISONS
-- Comprehensive year-over-year analysis
-- ============================================================================

DROP VIEW IF EXISTS vw_ytd_comparison;

CREATE VIEW vw_ytd_comparison AS
WITH current_year AS (
    SELECT MAX(vintage_year) AS cy FROM vw_sba_loans_clean
),
ytd_data AS (
    SELECT
        vintage_year,
        vintage_month,
        COUNT(*) AS monthly_loans,
        SUM(gross_approved) AS monthly_volume,
        COUNT(*) FILTER (WHERE is_defaulted) AS monthly_defaults,
        SUM(chargeoff_amount) AS monthly_chargeoff
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
      AND vintage_year >= (SELECT cy - 2 FROM current_year)
    GROUP BY vintage_year, vintage_month
)
SELECT
    y.vintage_month AS month,
    -- Current Year
    MAX(CASE WHEN y.vintage_year = (SELECT cy FROM current_year)
        THEN y.monthly_loans END) AS cy_loans,
    MAX(CASE WHEN y.vintage_year = (SELECT cy FROM current_year)
        THEN y.monthly_volume END) AS cy_volume,
    -- Prior Year
    MAX(CASE WHEN y.vintage_year = (SELECT cy - 1 FROM current_year)
        THEN y.monthly_loans END) AS py_loans,
    MAX(CASE WHEN y.vintage_year = (SELECT cy - 1 FROM current_year)
        THEN y.monthly_volume END) AS py_volume,
    -- Two Years Ago
    MAX(CASE WHEN y.vintage_year = (SELECT cy - 2 FROM current_year)
        THEN y.monthly_loans END) AS py2_loans,
    MAX(CASE WHEN y.vintage_year = (SELECT cy - 2 FROM current_year)
        THEN y.monthly_volume END) AS py2_volume,
    -- YoY Change
    ROUND(100.0 * (
        MAX(CASE WHEN y.vintage_year = (SELECT cy FROM current_year) THEN y.monthly_loans END) -
        MAX(CASE WHEN y.vintage_year = (SELECT cy - 1 FROM current_year) THEN y.monthly_loans END)
    ) / NULLIF(MAX(CASE WHEN y.vintage_year = (SELECT cy - 1 FROM current_year)
        THEN y.monthly_loans END), 0), 2) AS yoy_loan_change_pct,
    ROUND(100.0 * (
        MAX(CASE WHEN y.vintage_year = (SELECT cy FROM current_year) THEN y.monthly_volume END) -
        MAX(CASE WHEN y.vintage_year = (SELECT cy - 1 FROM current_year) THEN y.monthly_volume END)
    ) / NULLIF(MAX(CASE WHEN y.vintage_year = (SELECT cy - 1 FROM current_year)
        THEN y.monthly_volume END), 0), 2) AS yoy_volume_change_pct
FROM ytd_data y
GROUP BY y.vintage_month
ORDER BY y.vintage_month;

-- ============================================================================
-- SECTION 4: DRILL-DOWN CAPABILITY BY DIMENSION
-- Parameterized views for interactive exploration
-- ============================================================================

-- 4.1 Dimension summary with all key metrics
DROP VIEW IF EXISTS vw_dimension_drilldown;

CREATE VIEW vw_dimension_drilldown AS
-- By State
SELECT
    'State' AS dimension,
    state AS dimension_value,
    COUNT(*) AS loans,
    SUM(gross_approved) AS volume,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY state

UNION ALL

-- By Industry
SELECT
    'Industry' AS dimension,
    industry_sector AS dimension_value,
    COUNT(*) AS loans,
    SUM(gross_approved) AS volume,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY industry_sector

UNION ALL

-- By Loan Size Bucket
SELECT
    'Loan Size' AS dimension,
    loan_size_bucket AS dimension_value,
    COUNT(*) AS loans,
    SUM(gross_approved) AS volume,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY loan_size_bucket

UNION ALL

-- By Business Type
SELECT
    'Business Type' AS dimension,
    business_type AS dimension_value,
    COUNT(*) AS loans,
    SUM(gross_approved) AS volume,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY business_type

UNION ALL

-- By Term Category
SELECT
    'Term Category' AS dimension,
    term_category AS dimension_value,
    COUNT(*) AS loans,
    SUM(gross_approved) AS volume,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY term_category

UNION ALL

-- By Location Type
SELECT
    'Location Type' AS dimension,
    location_type AS dimension_value,
    COUNT(*) AS loans,
    SUM(gross_approved) AS volume,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY location_type

UNION ALL

-- By Vintage Year
SELECT
    'Vintage Year' AS dimension,
    vintage_year::TEXT AS dimension_value,
    COUNT(*) AS loans,
    SUM(gross_approved) AS volume,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY vintage_year;

-- ============================================================================
-- SECTION 5: TOP N RANKINGS
-- Quick access to top performers and underperformers
-- ============================================================================

DROP VIEW IF EXISTS vw_top_rankings;

CREATE VIEW vw_top_rankings AS
-- Top 10 States by Volume
SELECT
    'Top States by Volume' AS ranking_category,
    state AS entity,
    SUM(gross_approved) AS metric_value,
    'volume' AS metric_type,
    RANK() OVER (ORDER BY SUM(gross_approved) DESC) AS rank
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY state
ORDER BY metric_value DESC
LIMIT 10;

-- Additional rankings combined with UNION ALL
DROP VIEW IF EXISTS vw_comprehensive_rankings;

CREATE VIEW vw_comprehensive_rankings AS
-- Top 10 States by Volume
(SELECT 'Top 10 States by Volume' AS category, state AS entity,
    ROUND(SUM(gross_approved)/1000000, 2) AS value_millions,
    RANK() OVER (ORDER BY SUM(gross_approved) DESC) AS rank
FROM vw_sba_loans_clean WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY state ORDER BY value_millions DESC LIMIT 10)

UNION ALL

-- Top 10 Industries by Volume
(SELECT 'Top 10 Industries by Volume', industry_sector,
    ROUND(SUM(gross_approved)/1000000, 2),
    RANK() OVER (ORDER BY SUM(gross_approved) DESC)
FROM vw_sba_loans_clean WHERE loan_status IN ('PIF', 'CHGOFF') AND industry_sector != 'Unknown'
GROUP BY industry_sector ORDER BY 3 DESC LIMIT 10)

UNION ALL

-- Highest Default Rate States (min 500 loans)
(SELECT 'Highest Default Rate States', state,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2),
    RANK() OVER (ORDER BY 100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*) DESC)
FROM vw_sba_loans_clean WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY state HAVING COUNT(*) >= 500 ORDER BY 3 DESC LIMIT 10)

UNION ALL

-- Lowest Default Rate States (min 500 loans)
(SELECT 'Lowest Default Rate States', state,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2),
    RANK() OVER (ORDER BY 100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*))
FROM vw_sba_loans_clean WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY state HAVING COUNT(*) >= 500 ORDER BY 3 LIMIT 10)

UNION ALL

-- Highest Default Rate Industries (min 500 loans)
(SELECT 'Highest Default Rate Industries', industry_sector,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2),
    RANK() OVER (ORDER BY 100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*) DESC)
FROM vw_sba_loans_clean WHERE loan_status IN ('PIF', 'CHGOFF') AND industry_sector != 'Unknown'
GROUP BY industry_sector HAVING COUNT(*) >= 500 ORDER BY 3 DESC LIMIT 10);

-- ============================================================================
-- SECTION 6: PORTFOLIO SNAPSHOT
-- Single-row summary for quick reference
-- ============================================================================

DROP VIEW IF EXISTS vw_portfolio_snapshot;

CREATE VIEW vw_portfolio_snapshot AS
SELECT
    -- Identification
    'SBA 7(a) Loan Portfolio' AS portfolio_name,
    CURRENT_DATE AS snapshot_date,

    -- Volume Metrics
    COUNT(*) AS total_loans,
    ROUND(SUM(gross_approved) / 1000000000, 2) AS total_volume_billions,
    ROUND(SUM(sba_approved) / 1000000000, 2) AS sba_exposure_billions,
    ROUND(AVG(gross_approved), 0) AS avg_loan_size,

    -- Portfolio Characteristics
    ROUND(AVG(term_months), 0) AS avg_term_months,
    ROUND(AVG(sba_guarantee_pct), 1) AS avg_guarantee_pct,
    MODE() WITHIN GROUP (ORDER BY loan_size_bucket) AS most_common_size_bucket,
    MODE() WITHIN GROUP (ORDER BY industry_sector) AS largest_industry,
    MODE() WITHIN GROUP (ORDER BY state) AS largest_state,

    -- Risk Metrics
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate_pct,
    ROUND(SUM(chargeoff_amount) / 1000000, 2) AS total_chargeoff_millions,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 3) AS loss_rate_pct,

    -- Diversity Metrics
    COUNT(DISTINCT bank_name) AS num_lenders,
    COUNT(DISTINCT state) AS num_states,
    COUNT(DISTINCT industry_sector) AS num_industries,

    -- Economic Impact
    SUM(jobs_created) AS total_jobs_created,
    SUM(jobs_retained) AS total_jobs_retained,

    -- Time Range
    MIN(approval_date) AS earliest_loan,
    MAX(approval_date) AS latest_loan,
    MIN(vintage_year) AS first_vintage,
    MAX(vintage_year) AS latest_vintage

FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF');

-- ============================================================================
-- SECTION 7: ALERT/WATCHLIST VIEW
-- Identify segments requiring attention
-- ============================================================================

DROP VIEW IF EXISTS vw_risk_watchlist;

CREATE VIEW vw_risk_watchlist AS
WITH portfolio_avg AS (
    SELECT
        ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS avg_default_rate
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
),
segment_risk AS (
    -- State-level risk
    SELECT
        'State' AS segment_type,
        state AS segment_value,
        COUNT(*) AS loans,
        SUM(gross_approved) AS volume,
        ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
    GROUP BY state
    HAVING COUNT(*) >= 100

    UNION ALL

    -- Industry-level risk
    SELECT
        'Industry',
        industry_sector,
        COUNT(*),
        SUM(gross_approved),
        ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2)
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF') AND industry_sector != 'Unknown'
    GROUP BY industry_sector
    HAVING COUNT(*) >= 100

    UNION ALL

    -- Vintage-level risk
    SELECT
        'Vintage Year',
        vintage_year::TEXT,
        COUNT(*),
        SUM(gross_approved),
        ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2)
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
    GROUP BY vintage_year
)
SELECT
    s.segment_type,
    s.segment_value,
    s.loans,
    s.volume,
    s.default_rate,
    p.avg_default_rate AS portfolio_avg,
    ROUND(s.default_rate - p.avg_default_rate, 2) AS vs_portfolio_avg,
    CASE
        WHEN s.default_rate > p.avg_default_rate * 1.5 THEN 'HIGH RISK'
        WHEN s.default_rate > p.avg_default_rate * 1.2 THEN 'ELEVATED'
        WHEN s.default_rate < p.avg_default_rate * 0.8 THEN 'LOW RISK'
        ELSE 'NORMAL'
    END AS risk_classification
FROM segment_risk s
CROSS JOIN portfolio_avg p
WHERE s.default_rate > p.avg_default_rate * 1.2  -- Only show elevated+ risk
ORDER BY s.default_rate DESC;

-- ============================================================================
-- SECTION 8: DISPLAY ALL DASHBOARD VIEWS
-- Quick verification of all created views
-- ============================================================================

-- List all dashboard views and their record counts
SELECT 'Executive Summary' AS view_name, 1 AS record_count
UNION ALL SELECT 'Monthly Trends', (SELECT COUNT(*) FROM vw_monthly_trends)
UNION ALL SELECT 'YTD Comparison', (SELECT COUNT(*) FROM vw_ytd_comparison)
UNION ALL SELECT 'Dimension Drilldown', (SELECT COUNT(*) FROM vw_dimension_drilldown)
UNION ALL SELECT 'Top Rankings', (SELECT COUNT(*) FROM vw_top_rankings)
UNION ALL SELECT 'Comprehensive Rankings', (SELECT COUNT(*) FROM vw_comprehensive_rankings)
UNION ALL SELECT 'Portfolio Snapshot', 1
UNION ALL SELECT 'Risk Watchlist', (SELECT COUNT(*) FROM vw_risk_watchlist);

-- Display executive summary
SELECT * FROM vw_executive_summary;

-- Display portfolio snapshot
SELECT * FROM vw_portfolio_snapshot;

-- Display risk watchlist (top 10 highest risk segments)
SELECT * FROM vw_risk_watchlist LIMIT 10;
