/*
================================================================================
SBA 7(a) LOAN PORTFOLIO ANALYTICS
Analysis: 03_risk_analysis.sql
================================================================================

Purpose: Default rate analysis, charge-off metrics, and risk segmentation
Skills Demonstrated: Window functions, CTEs, complex JOINs, conditional aggregation

Description:
    This script performs comprehensive credit risk analysis on the SBA loan
    portfolio, calculating default rates, loss metrics, and risk segmentation
    across multiple dimensions.

================================================================================
*/

-- ============================================================================
-- SECTION 1: OVERALL DEFAULT RATE ANALYSIS
-- Portfolio-level default metrics
-- ============================================================================

-- 1.1 Overall portfolio default rate
SELECT
    'Portfolio Default Summary' AS metric,
    COUNT(*) AS total_loans,
    COUNT(*) FILTER (WHERE is_defaulted) AS defaulted_loans,
    COUNT(*) FILTER (WHERE is_paid_in_full) AS paid_in_full,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate_pct,
    SUM(gross_approved) AS total_approved_volume,
    SUM(CASE WHEN is_defaulted THEN gross_approved ELSE 0 END) AS defaulted_volume,
    ROUND(100.0 * SUM(CASE WHEN is_defaulted THEN gross_approved ELSE 0 END)
        / SUM(gross_approved), 2) AS default_rate_by_volume_pct
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF');

-- 1.2 Default rate by vintage year
SELECT
    vintage_year,
    COUNT(*) AS total_loans,
    COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate_pct,
    SUM(gross_approved) AS total_volume,
    SUM(chargeoff_amount) AS total_chargeoff,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate_pct
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY vintage_year
ORDER BY vintage_year DESC;

-- 1.3 Monthly default rate trend (rolling 12-month)
WITH monthly_defaults AS (
    SELECT
        DATE_TRUNC('month', approval_date)::DATE AS month,
        COUNT(*) AS total_loans,
        COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
        SUM(gross_approved) AS total_volume,
        SUM(chargeoff_amount) AS chargeoff_volume
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
      AND approval_date >= '2010-01-01'
    GROUP BY DATE_TRUNC('month', approval_date)
)
SELECT
    month,
    total_loans,
    defaults,
    ROUND(100.0 * defaults / NULLIF(total_loans, 0), 2) AS monthly_default_rate,
    SUM(total_loans) OVER (ORDER BY month ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS rolling_12mo_loans,
    SUM(defaults) OVER (ORDER BY month ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS rolling_12mo_defaults,
    ROUND(100.0 * SUM(defaults) OVER (ORDER BY month ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)
        / NULLIF(SUM(total_loans) OVER (ORDER BY month ROWS BETWEEN 11 PRECEDING AND CURRENT ROW), 0), 2)
        AS rolling_12mo_default_rate
FROM monthly_defaults
ORDER BY month DESC;

-- ============================================================================
-- SECTION 2: CHARGE-OFF AMOUNT ANALYSIS
-- Total losses by segment
-- ============================================================================

-- 2.1 Charge-off summary by year
SELECT
    vintage_year,
    COUNT(*) FILTER (WHERE is_defaulted) AS defaulted_loans,
    SUM(chargeoff_amount) AS gross_chargeoff,
    ROUND(AVG(CASE WHEN is_defaulted THEN chargeoff_amount END), 2) AS avg_chargeoff_per_default,
    SUM(CASE WHEN is_defaulted THEN sba_approved ELSE 0 END) AS sba_exposure_on_defaults,
    SUM(CASE WHEN is_defaulted THEN gross_approved ELSE 0 END) AS gross_exposure_on_defaults
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY vintage_year
ORDER BY vintage_year DESC;

-- 2.2 Charge-off by industry sector
SELECT
    industry_sector,
    COUNT(*) AS total_loans,
    COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    SUM(chargeoff_amount) AS total_chargeoff,
    ROUND(AVG(CASE WHEN is_defaulted THEN chargeoff_amount END), 2) AS avg_chargeoff,
    SUM(gross_approved) AS total_exposure,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate_pct
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
  AND industry_sector != 'Unknown'
GROUP BY industry_sector
HAVING COUNT(*) >= 100
ORDER BY default_rate DESC;

-- 2.3 Charge-off by loan size bucket
SELECT
    loan_size_bucket,
    COUNT(*) AS total_loans,
    COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    SUM(chargeoff_amount) AS total_chargeoff,
    ROUND(AVG(CASE WHEN is_defaulted THEN chargeoff_amount END), 2) AS avg_chargeoff,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate_pct
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

-- ============================================================================
-- SECTION 3: LOSS GIVEN DEFAULT (LGD) ANALYSIS
-- Average loss when defaults occur
-- ============================================================================

-- 3.1 Overall LGD calculation
SELECT
    'Loss Given Default Analysis' AS metric,
    COUNT(*) FILTER (WHERE is_defaulted) AS defaulted_loans,
    SUM(CASE WHEN is_defaulted THEN gross_approved ELSE 0 END) AS defaulted_exposure,
    SUM(chargeoff_amount) AS total_loss,
    ROUND(100.0 * SUM(chargeoff_amount)
        / NULLIF(SUM(CASE WHEN is_defaulted THEN gross_approved ELSE 0 END), 0), 2) AS lgd_pct,
    ROUND(AVG(CASE WHEN is_defaulted THEN loss_severity_pct END), 2) AS avg_loss_severity_pct
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF');

-- 3.2 LGD by vintage year (recovery trends)
SELECT
    vintage_year,
    COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
    SUM(CASE WHEN is_defaulted THEN gross_approved ELSE 0 END) AS exposure_at_default,
    SUM(chargeoff_amount) AS actual_loss,
    ROUND(100.0 * SUM(chargeoff_amount)
        / NULLIF(SUM(CASE WHEN is_defaulted THEN gross_approved ELSE 0 END), 0), 2) AS lgd_pct,
    -- Implied recovery rate
    ROUND(100.0 - (100.0 * SUM(chargeoff_amount)
        / NULLIF(SUM(CASE WHEN is_defaulted THEN gross_approved ELSE 0 END), 0)), 2) AS recovery_rate_pct
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY vintage_year
ORDER BY vintage_year DESC;

-- 3.3 LGD distribution analysis
SELECT
    CASE
        WHEN loss_severity_pct = 0 THEN 'No Loss (0%)'
        WHEN loss_severity_pct < 25 THEN 'Low (1-24%)'
        WHEN loss_severity_pct < 50 THEN 'Medium (25-49%)'
        WHEN loss_severity_pct < 75 THEN 'High (50-74%)'
        WHEN loss_severity_pct < 100 THEN 'Severe (75-99%)'
        ELSE 'Total Loss (100%)'
    END AS loss_severity_bucket,
    COUNT(*) AS default_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_defaults,
    SUM(chargeoff_amount) AS total_loss,
    ROUND(AVG(loss_severity_pct), 2) AS avg_severity_in_bucket
FROM vw_sba_loans_clean
WHERE is_defaulted = TRUE
GROUP BY 1
ORDER BY
    CASE
        WHEN loss_severity_pct = 0 THEN 1
        WHEN loss_severity_pct < 25 THEN 2
        WHEN loss_severity_pct < 50 THEN 3
        WHEN loss_severity_pct < 75 THEN 4
        WHEN loss_severity_pct < 100 THEN 5
        ELSE 6
    END;

-- ============================================================================
-- SECTION 4: RISK SEGMENTATION
-- Default rates by multiple dimensions using CTEs
-- ============================================================================

-- 4.1 Multi-dimensional risk matrix: Industry x Loan Size
WITH risk_matrix AS (
    SELECT
        industry_sector,
        loan_size_bucket,
        COUNT(*) AS total_loans,
        COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
        SUM(gross_approved) AS total_volume,
        SUM(chargeoff_amount) AS total_loss
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
      AND industry_sector != 'Unknown'
    GROUP BY industry_sector, loan_size_bucket
    HAVING COUNT(*) >= 50  -- Minimum sample for statistical relevance
)
SELECT
    industry_sector,
    loan_size_bucket,
    total_loans,
    defaults,
    ROUND(100.0 * defaults / total_loans, 2) AS default_rate,
    ROUND(100.0 * total_loss / NULLIF(total_volume, 0), 2) AS loss_rate,
    -- Risk ranking within industry
    RANK() OVER (PARTITION BY industry_sector ORDER BY 100.0 * defaults / total_loans DESC) AS risk_rank_in_industry
FROM risk_matrix
ORDER BY industry_sector, default_rate DESC;

-- 4.2 Geographic risk analysis
WITH state_risk AS (
    SELECT
        state,
        sr.region,
        COUNT(*) AS total_loans,
        COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
        SUM(gross_approved) AS total_volume,
        SUM(chargeoff_amount) AS total_loss,
        ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate
    FROM vw_sba_loans_clean l
    LEFT JOIN state_regions sr ON l.state = sr.state_code
    WHERE loan_status IN ('PIF', 'CHGOFF')
    GROUP BY state, sr.region
    HAVING COUNT(*) >= 100
)
SELECT
    state,
    region,
    total_loans,
    defaults,
    default_rate,
    ROUND(100.0 * total_loss / NULLIF(total_volume, 0), 2) AS loss_rate,
    -- Compare to portfolio average
    default_rate - (SELECT AVG(default_rate) FROM state_risk) AS vs_portfolio_avg,
    -- Rank within region
    RANK() OVER (PARTITION BY region ORDER BY default_rate DESC) AS rank_in_region,
    -- National rank
    RANK() OVER (ORDER BY default_rate DESC) AS national_rank
FROM state_risk
ORDER BY default_rate DESC;

-- 4.3 New vs Existing Business risk comparison
SELECT
    business_type,
    vintage_year,
    COUNT(*) AS total_loans,
    COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    ROUND(AVG(gross_approved), 2) AS avg_loan_size,
    ROUND(AVG(CASE WHEN is_defaulted THEN loss_severity_pct END), 2) AS avg_lgd
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
  AND vintage_year >= 2010
GROUP BY business_type, vintage_year
ORDER BY vintage_year DESC, business_type;

-- 4.4 Term length risk analysis
SELECT
    term_category,
    COUNT(*) AS total_loans,
    COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    SUM(gross_approved) AS total_volume,
    SUM(chargeoff_amount) AS total_loss,
    ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS loss_rate,
    ROUND(AVG(CASE WHEN is_defaulted THEN term_months END), 1) AS avg_term_of_defaults
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY term_category
ORDER BY default_rate DESC;

-- ============================================================================
-- SECTION 5: SBA GUARANTEE RISK EXPOSURE
-- Government loss analysis
-- ============================================================================

-- 5.1 SBA loss exposure by vintage
SELECT
    vintage_year,
    COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
    SUM(CASE WHEN is_defaulted THEN sba_approved ELSE 0 END) AS sba_guaranteed_on_defaults,
    SUM(chargeoff_amount) AS total_chargeoff,
    -- Estimated SBA loss (assuming pro-rata with guarantee percentage)
    ROUND(SUM(CASE WHEN is_defaulted THEN chargeoff_amount * (sba_guarantee_pct / 100.0) ELSE 0 END), 2) AS estimated_sba_loss,
    -- Lender loss (remainder)
    ROUND(SUM(CASE WHEN is_defaulted THEN chargeoff_amount * (1 - sba_guarantee_pct / 100.0) ELSE 0 END), 2) AS estimated_lender_loss
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
GROUP BY vintage_year
ORDER BY vintage_year DESC;

-- 5.2 Default rate by guarantee percentage bucket
SELECT
    CASE
        WHEN sba_guarantee_pct >= 90 THEN '90-100%'
        WHEN sba_guarantee_pct >= 80 THEN '80-89%'
        WHEN sba_guarantee_pct >= 75 THEN '75-79%'
        WHEN sba_guarantee_pct >= 50 THEN '50-74%'
        ELSE '<50%'
    END AS guarantee_bucket,
    COUNT(*) AS total_loans,
    COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS default_rate,
    SUM(gross_approved) AS total_exposure,
    SUM(sba_approved) AS sba_exposure,
    SUM(chargeoff_amount) AS total_loss
FROM vw_sba_loans_clean
WHERE loan_status IN ('PIF', 'CHGOFF')
  AND gross_approved > 0
GROUP BY 1
ORDER BY default_rate DESC;

-- ============================================================================
-- SECTION 6: RISK CONCENTRATION ANALYSIS
-- Identify concentration risks in portfolio
-- ============================================================================

-- 6.1 Top 10 riskiest NAICS codes (with minimum volume)
WITH naics_risk AS (
    SELECT
        naics_sector,
        industry_sector,
        COUNT(*) AS total_loans,
        COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
        SUM(gross_approved) AS total_volume,
        SUM(chargeoff_amount) AS total_loss
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
    GROUP BY naics_sector, industry_sector
    HAVING COUNT(*) >= 500
)
SELECT
    naics_sector,
    industry_sector,
    total_loans,
    defaults,
    ROUND(100.0 * defaults / total_loans, 2) AS default_rate,
    total_volume,
    total_loss,
    ROUND(100.0 * total_loss / NULLIF(total_volume, 0), 2) AS loss_rate
FROM naics_risk
ORDER BY default_rate DESC
LIMIT 10;

-- 6.2 Lender risk profile (banks with highest default rates)
WITH lender_risk AS (
    SELECT
        bank_name,
        bank_state,
        COUNT(*) AS total_loans,
        COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
        SUM(gross_approved) AS total_volume,
        SUM(chargeoff_amount) AS total_loss
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
      AND bank_name != 'Unknown Lender'
    GROUP BY bank_name, bank_state
    HAVING COUNT(*) >= 100  -- Minimum loan count for reliability
)
SELECT
    bank_name,
    bank_state,
    total_loans,
    defaults,
    ROUND(100.0 * defaults / total_loans, 2) AS default_rate,
    total_volume,
    total_loss,
    ROUND(100.0 * total_loss / NULLIF(total_volume, 0), 2) AS loss_rate,
    RANK() OVER (ORDER BY 100.0 * defaults / total_loans DESC) AS risk_rank
FROM lender_risk
ORDER BY default_rate DESC
LIMIT 25;

-- ============================================================================
-- SECTION 7: EXPECTED LOSS CALCULATION
-- Probability of Default x Exposure x LGD
-- ============================================================================

-- 7.1 Expected loss by segment
WITH segment_metrics AS (
    SELECT
        industry_sector,
        loan_size_bucket,
        COUNT(*) AS total_loans,
        COUNT(*) FILTER (WHERE is_defaulted) AS defaults,
        SUM(gross_approved) AS total_exposure,
        SUM(chargeoff_amount) AS actual_loss,
        -- Calculate PD (Probability of Default)
        ROUND(1.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 4) AS pd,
        -- Calculate LGD
        ROUND(COALESCE(
            SUM(chargeoff_amount) / NULLIF(SUM(CASE WHEN is_defaulted THEN gross_approved END), 0),
            0), 4) AS lgd
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
      AND industry_sector != 'Unknown'
    GROUP BY industry_sector, loan_size_bucket
    HAVING COUNT(*) >= 50
)
SELECT
    industry_sector,
    loan_size_bucket,
    total_loans,
    defaults,
    ROUND(pd * 100, 2) AS pd_pct,
    ROUND(lgd * 100, 2) AS lgd_pct,
    total_exposure,
    -- Expected Loss = PD x LGD x Exposure
    ROUND(pd * lgd * total_exposure, 2) AS expected_loss,
    actual_loss,
    -- Compare expected to actual
    ROUND(actual_loss - (pd * lgd * total_exposure), 2) AS variance
FROM segment_metrics
ORDER BY expected_loss DESC
LIMIT 20;

-- ============================================================================
-- SECTION 8: RISK SUMMARY VIEW
-- Consolidated risk metrics for dashboarding
-- ============================================================================

DROP VIEW IF EXISTS vw_risk_summary;

CREATE VIEW vw_risk_summary AS
WITH portfolio_risk AS (
    SELECT
        COUNT(*) AS total_loans,
        COUNT(*) FILTER (WHERE is_defaulted) AS total_defaults,
        SUM(gross_approved) AS total_exposure,
        SUM(sba_approved) AS total_sba_exposure,
        SUM(chargeoff_amount) AS total_loss,
        ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / COUNT(*), 2) AS portfolio_default_rate,
        ROUND(100.0 * SUM(chargeoff_amount) / NULLIF(SUM(gross_approved), 0), 2) AS portfolio_loss_rate,
        ROUND(100.0 * SUM(chargeoff_amount)
            / NULLIF(SUM(CASE WHEN is_defaulted THEN gross_approved END), 0), 2) AS portfolio_lgd
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
),
ytd_risk AS (
    SELECT
        COUNT(*) FILTER (WHERE is_defaulted) AS ytd_defaults,
        ROUND(100.0 * COUNT(*) FILTER (WHERE is_defaulted) / NULLIF(COUNT(*), 0), 2) AS ytd_default_rate
    FROM vw_sba_loans_clean
    WHERE loan_status IN ('PIF', 'CHGOFF')
      AND vintage_year = (SELECT MAX(vintage_year) FROM vw_sba_loans_clean)
)
SELECT
    p.*,
    y.ytd_defaults,
    y.ytd_default_rate
FROM portfolio_risk p
CROSS JOIN ytd_risk y;

-- Display risk summary
SELECT * FROM vw_risk_summary;
