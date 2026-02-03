/*
================================================================================
SBA 7(a) LOAN PORTFOLIO ANALYTICS
Analysis: 05_segmentation.sql
================================================================================

Purpose: Geographic, industry, and lender performance segmentation analysis
Skills Demonstrated: Self-joins, correlated subqueries, ranking functions, pivots

Description:
    This script provides deep-dive segmentation analysis across geographic,
    industry, and lender dimensions to identify concentration risks and
    performance variations.

================================================================================
*/

-- ============================================================================
-- SECTION 1: STATE-LEVEL PERFORMANCE
-- Top/bottom performing regions
-- ============================================================================

-- 1.1 Comprehensive state performance ranking
WITH state_metrics AS (
    SELECT
        l.state,
        sr.state_name,
        sr.region,
        sr.division,
        COUNT(*) AS total_loans,
        SUM(gross_approved) AS total_volume,
        ROUND(AVG(gross_approved), 2) AS avg_loan_size,
        COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
        ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
        SUM(chargeoff_amount) AS total_loss,
        ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate,
        SUM(jobs_created + jobs_retained) AS total_jobs_impacted
    FROM vw_sba_loans_clean l
    LEFT JOIN state_regions sr ON l.state = sr.state_code
    WHERE loan_status IN ('PIF', 'CHGOFF')
    GROUP BY l.state, sr.state_name, sr.region, sr.division
    HAVING COUNT(*) >= 100  -- Minimum sample size
)
SELECT
    state,
    state_name,
    region,
    total_loans,
    total_volume,
    avg_loan_size,
    default_rate,
    loss_rate,
    -- Rankings
    RANK() OVER (ORDER BY total_volume DESC) AS volume_rank,
    RANK() OVER (ORDER BY default_rate) AS best_default_rank,  -- Lower is better
    RANK() OVER (ORDER BY default_rate DESC) AS worst_default_rank,
    -- Comparison to national average
    default_rate - (SELECT AVG(default_rate) FROM state_metrics) AS default_vs_national,
    -- Performance category
    CASE
        WHEN default_rate < (SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY default_rate) FROM state_metrics)
            THEN 'Top Quartile'
        WHEN default_rate < (SELECT PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY default_rate) FROM state_metrics)
            THEN 'Second Quartile'
        WHEN default_rate < (SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY default_rate) FROM state_metrics)
            THEN 'Third Quartile'
        ELSE 'Bottom Quartile'
    END AS performance_quartile
FROM state_metrics
ORDER BY total_volume DESC;

-- 1.2 Top 10 best and worst performing states
(
    SELECT
        'Top 10 Best' AS category,
        state,
        total_loans,
        default_rate,
        loss_rate,
        ROW_NUMBER() OVER (ORDER BY default_rate) AS rank
    FROM (
        SELECT
            state,
            COUNT(*) AS total_loans,
            ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
            ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate
        FROM vw_sba_loans_clean
        WHERE loan_status IN ('PIF', 'CHGOFF')
        GROUP BY state
        HAVING COUNT(*) >= 500
    ) sub
    ORDER BY default_rate
    LIMIT 10
)
UNION ALL
(
    SELECT
        'Top 10 Worst' AS category,
        state,
        total_loans,
        default_rate,
        loss_rate,
        ROW_NUMBER() OVER (ORDER BY default_rate DESC) AS rank
    FROM (
        SELECT
            state,
            COUNT(*) AS total_loans,
            ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
            ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate
        FROM vw_sba_loans_clean
        WHERE loan_status IN ('PIF', 'CHGOFF')
        GROUP BY state
        HAVING COUNT(*) >= 500
    ) sub
    ORDER BY default_rate DESC
    LIMIT 10
)
ORDER BY category, rank;

-- 1.3 Regional performance comparison
SELECT
    sr.region,
    COUNT(*) AS total_loans,
    SUM(gross_approved) AS total_volume,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_portfolio,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    SUM(chargeoff_amount) AS total_loss,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate,
    COUNT(DISTINCT l.state) AS states_in_region
FROM vw_sba_loans_clean l
JOIN state_regions sr ON l.state = sr.state_code
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY sr.region
ORDER BY total_volume DESC;

-- ============================================================================
-- SECTION 2: INDUSTRY RISK PROFILE
-- NAICS code analysis and sector performance
-- ============================================================================

-- 2.1 Industry sector performance summary
SELECT
    industry_sector,
    COUNT(*) AS total_loans,
    SUM(gross_approved) AS total_volume,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_portfolio,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    SUM(chargeoff_amount) AS total_loss,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate,
    -- Risk ranking
    RANK() OVER (ORDER BY 100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*)) AS risk_rank_best,
    RANK() OVER (ORDER BY 100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*) DESC) AS risk_rank_worst
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
  AND industry_sector != 'Unknown'
GROUP BY industry_sector
ORDER BY total_volume DESC;

-- 2.2 Detailed NAICS subsector analysis (top 25 by volume)
SELECT
    naics_sector,
    industry_sector,
    COUNT(*) AS total_loans,
    SUM(gross_approved) AS total_volume,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    ROUND(AVG(term_months), 1) AS avg_term_months,
    COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate,
    -- Compare to sector average using correlated subquery
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*) -
        (SELECT 100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*)
         FROM vw_sba_loans_clean sub
         WHERE sub.industry_sector = vw_sba_loans_clean.industry_sector
           AND sub.loan_status IN ('PIF', 'CHGOFF')), 2) AS vs_sector_avg
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY naics_sector, industry_sector
HAVING COUNT(*) >= 100
ORDER BY total_volume DESC
LIMIT 25;

-- 2.3 Industry concentration risk analysis
WITH industry_concentration AS (
    SELECT
        industry_sector,
        SUM(gross_approved) AS sector_volume,
        SUM(SUM(gross_approved)) OVER () AS total_portfolio
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
    GROUP BY industry_sector
)
SELECT
    industry_sector,
    sector_volume,
    ROUND(100.0 * sector_volume / total_portfolio, 2) AS pct_of_portfolio,
    SUM(ROUND(100.0 * sector_volume / total_portfolio, 2))
        OVER (ORDER BY sector_volume DESC) AS cumulative_concentration
FROM industry_concentration
ORDER BY sector_volume DESC;

-- 2.4 Industry performance trend over time
SELECT
    industry_sector,
    vintage_year,
    COUNT(*) AS loans,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    -- Year-over-year change
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*) -
        LAG(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*))
            OVER (PARTITION BY industry_sector ORDER BY vintage_year), 2) AS yoy_change
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
  AND industry_sector != 'Unknown'
  AND vintage_year >= 2010
GROUP BY industry_sector, vintage_year
HAVING COUNT(*) >= 50
ORDER BY industry_sector, vintage_year DESC;

-- ============================================================================
-- SECTION 3: LENDER PERFORMANCE ANALYSIS
-- Bank-level default rate comparison
-- ============================================================================

-- 3.1 Lender performance ranking (minimum 100 loans)
WITH lender_metrics AS (
    SELECT
        bank_name,
        bank_state,
        COUNT(*) AS total_loans,
        SUM(gross_approved) AS total_volume,
        ROUND(AVG(gross_approved), 2) AS avg_loan_size,
        COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
        ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
        SUM(chargeoff_amount) AS total_loss,
        ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate,
        COUNT(DISTINCT state) AS states_served,
        COUNT(DISTINCT industry_sector) AS industries_served
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
      AND bank_name != 'Unknown Lender'
    GROUP BY bank_name, bank_state
    HAVING COUNT(*) >= 100
)
SELECT
    bank_name,
    bank_state,
    total_loans,
    total_volume,
    avg_loan_size,
    default_rate,
    loss_rate,
    states_served,
    industries_served,
    -- Rankings
    RANK() OVER (ORDER BY total_volume DESC) AS volume_rank,
    RANK() OVER (ORDER BY default_rate) AS performance_rank,  -- Lower default = better
    NTILE(4) OVER (ORDER BY default_rate) AS performance_quartile,
    -- Comparison to portfolio average
    default_rate - (SELECT AVG(default_rate) FROM lender_metrics) AS vs_avg_default_rate
FROM lender_metrics
ORDER BY total_volume DESC
LIMIT 50;

-- 3.2 Lender performance comparison using self-join
-- Compare each lender to lenders in the same state
WITH lender_stats AS (
    SELECT
        bank_name,
        bank_state,
        COUNT(*) AS total_loans,
        ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
      AND bank_name != 'Unknown Lender'
    GROUP BY bank_name, bank_state
    HAVING COUNT(*) >= 100
),
state_averages AS (
    SELECT
        bank_state,
        ROUND(AVG(default_rate), 2) AS state_avg_default_rate,
        COUNT(*) AS lenders_in_state
    FROM lender_stats
    GROUP BY bank_state
)
SELECT
    l.bank_name,
    l.bank_state,
    l.total_loans,
    l.default_rate,
    s.state_avg_default_rate,
    ROUND(l.default_rate - s.state_avg_default_rate, 2) AS vs_state_avg,
    CASE
        WHEN l.default_rate < s.state_avg_default_rate * 0.8 THEN 'Outperforms State'
        WHEN l.default_rate > s.state_avg_default_rate * 1.2 THEN 'Underperforms State'
        ELSE 'Average for State'
    END AS state_performance
FROM lender_stats l
JOIN state_averages s ON l.bank_state = s.bank_state
WHERE s.lenders_in_state >= 3  -- States with multiple lenders for comparison
ORDER BY l.total_loans DESC
LIMIT 30;

-- 3.3 Lender specialization analysis
-- Which industries do top lenders focus on?
WITH lender_industry AS (
    SELECT
        bank_name,
        industry_sector,
        COUNT(*) AS loans_in_industry,
        SUM(COUNT(*)) OVER (PARTITION BY bank_name) AS total_lender_loans,
        ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS industry_default_rate
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
      AND bank_name != 'Unknown Lender'
      AND industry_sector != 'Unknown'
    GROUP BY bank_name, industry_sector
),
top_lenders AS (
    SELECT bank_name
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
      AND bank_name != 'Unknown Lender'
    GROUP BY bank_name
    ORDER BY SUM(gross_approved) DESC
    LIMIT 20
)
SELECT
    li.bank_name,
    li.industry_sector,
    li.loans_in_industry,
    ROUND(100.0 * li.loans_in_industry / li.total_lender_loans, 2) AS pct_of_lender_portfolio,
    li.industry_default_rate,
    RANK() OVER (PARTITION BY li.bank_name ORDER BY li.loans_in_industry DESC) AS industry_rank
FROM lender_industry li
JOIN top_lenders tl ON li.bank_name = tl.bank_name
WHERE li.loans_in_industry >= 20
ORDER BY li.bank_name, li.loans_in_industry DESC;

-- ============================================================================
-- SECTION 4: GEOGRAPHIC CONCENTRATION
-- Portfolio distribution heatmap data
-- ============================================================================

-- 4.1 State-level concentration metrics
WITH state_totals AS (
    SELECT
        state,
        COUNT(*) AS state_loans,
        SUM(gross_approved) AS state_volume,
        SUM(COUNT(*)) OVER () AS total_loans,
        SUM(SUM(gross_approved)) OVER () AS total_volume
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
    GROUP BY state
)
SELECT
    state,
    state_loans,
    state_volume,
    ROUND(100.0 * state_loans / total_loans, 2) AS pct_of_loans,
    ROUND(100.0 * state_volume / total_volume, 2) AS pct_of_volume,
    -- Cumulative concentration
    SUM(ROUND(100.0 * state_volume / total_volume, 2))
        OVER (ORDER BY state_volume DESC) AS cumulative_volume_pct,
    -- Herfindahl-Hirschman contribution
    POWER(100.0 * state_volume / total_volume, 2) AS hhi_contribution
FROM state_totals
ORDER BY state_volume DESC;

-- 4.2 Geographic Herfindahl-Hirschman Index (HHI)
-- HHI < 1500: Unconcentrated, 1500-2500: Moderate, > 2500: Highly concentrated
WITH state_shares AS (
    SELECT
        state,
        100.0 * SUM(gross_approved) / SUM(SUM(gross_approved)) OVER () AS market_share
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
    GROUP BY state
)
SELECT
    'Geographic Concentration (HHI)' AS metric,
    ROUND(SUM(POWER(market_share, 2)), 2) AS hhi_score,
    CASE
        WHEN SUM(POWER(market_share, 2)) < 1500 THEN 'Unconcentrated'
        WHEN SUM(POWER(market_share, 2)) < 2500 THEN 'Moderately Concentrated'
        ELSE 'Highly Concentrated'
    END AS concentration_level,
    COUNT(*) AS num_states
FROM state_shares;

-- 4.3 Cross-state lending patterns (where do lenders operate?)
SELECT
    bank_state AS lender_home_state,
    state AS borrower_state,
    CASE WHEN bank_state = state THEN 'In-State' ELSE 'Out-of-State' END AS lending_type,
    COUNT(*) AS loan_count,
    SUM(gross_approved) AS total_volume,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
  AND bank_state IS NOT NULL
  AND state IS NOT NULL
GROUP BY bank_state, state
HAVING COUNT(*) >= 50
ORDER BY loan_count DESC
LIMIT 30;

-- 4.4 In-state vs out-of-state lending performance
SELECT
    CASE WHEN bank_state = state THEN 'In-State Lending' ELSE 'Out-of-State Lending' END AS lending_type,
    COUNT(*) AS total_loans,
    SUM(gross_approved) AS total_volume,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_portfolio,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
  AND bank_state IS NOT NULL
  AND state IS NOT NULL
GROUP BY 1
ORDER BY total_loans DESC;

-- ============================================================================
-- SECTION 5: MULTI-DIMENSIONAL SEGMENTATION
-- Cross-segment analysis
-- ============================================================================

-- 5.1 State x Industry matrix (top combinations)
SELECT
    state,
    industry_sector,
    COUNT(*) AS loans,
    SUM(gross_approved) AS volume,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    RANK() OVER (PARTITION BY state ORDER BY COUNT(*) DESC) AS industry_rank_in_state,
    RANK() OVER (PARTITION BY industry_sector ORDER BY COUNT(*) DESC) AS state_rank_in_industry
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
  AND industry_sector != 'Unknown'
GROUP BY state, industry_sector
HAVING COUNT(*) >= 50
ORDER BY loans DESC
LIMIT 50;

-- 5.2 Business type x Location type segmentation
SELECT
    business_type,
    location_type,
    loan_size_bucket,
    COUNT(*) AS total_loans,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY business_type, location_type, loan_size_bucket
HAVING COUNT(*) >= 100
ORDER BY business_type, location_type, loan_size_bucket;

-- ============================================================================
-- SECTION 6: SEGMENTATION SUMMARY VIEWS
-- Pre-built views for dashboarding
-- ============================================================================

-- 6.1 Geographic summary view
DROP VIEW IF EXISTS vw_geographic_summary;

CREATE VIEW vw_geographic_summary AS
SELECT
    l.state,
    sr.state_name,
    sr.region,
    sr.division,
    COUNT(*) AS total_loans,
    SUM(gross_approved) AS total_volume,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate,
    SUM(jobs_created + jobs_retained) AS total_jobs_impacted
FROM vw_sba_loans_clean l
LEFT JOIN state_regions sr ON l.state = sr.state_code
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY l.state, sr.state_name, sr.region, sr.division;

-- 6.2 Industry summary view
DROP VIEW IF EXISTS vw_industry_summary;

CREATE VIEW vw_industry_summary AS
SELECT
    naics_sector,
    industry_sector,
    COUNT(*) AS total_loans,
    SUM(gross_approved) AS total_volume,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate,
    ROUND(AVG(term_months), 1) AS avg_term_months
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY naics_sector, industry_sector;

-- 6.3 Lender summary view
DROP VIEW IF EXISTS vw_lender_summary;

CREATE VIEW vw_lender_summary AS
SELECT
    bank_name,
    bank_state,
    COUNT(*) AS total_loans,
    SUM(gross_approved) AS total_volume,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate,
    COUNT(DISTINCT state) AS states_served,
    COUNT(DISTINCT industry_sector) AS industries_served,
    MIN(approval_date) AS first_loan_date,
    MAX(approval_date) AS last_loan_date
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
  AND bank_name != 'Unknown Lender'
GROUP BY bank_name, bank_state;

-- Display sample outputs
SELECT 'Geographic Summary' AS view_name, COUNT(*) AS record_count FROM vw_geographic_summary
UNION ALL
SELECT 'Industry Summary', COUNT(*) FROM vw_industry_summary
UNION ALL
SELECT 'Lender Summary', COUNT(*) FROM vw_lender_summary;
