/*
================================================================================
SBA 7(a) LOAN PORTFOLIO ANALYTICS
Schema Definition: 01_create_tables.sql
================================================================================

Purpose: Define database schema for SBA loan data analysis
Database: PostgreSQL 15+
Author: [Your Name]
Created: 2024

Description:
    This script creates the primary tables, indexes, and constraints for
    analyzing SBA 7(a) loan portfolio data. The schema is optimized for
    analytical queries including aggregations, window functions, and joins.

Usage:
    psql -d sba_loans -f schema/01_create_tables.sql

================================================================================
*/

-- ============================================================================
-- CLEANUP: Drop existing objects if they exist
-- ============================================================================

DROP TABLE IF EXISTS sba_loans CASCADE;
DROP TABLE IF EXISTS naics_codes CASCADE;
DROP TABLE IF EXISTS state_regions CASCADE;

-- ============================================================================
-- REFERENCE TABLE: NAICS Industry Codes
-- ============================================================================

CREATE TABLE naics_codes (
    naics_code      VARCHAR(6) PRIMARY KEY,
    sector_code     VARCHAR(2) NOT NULL,
    sector_name     VARCHAR(100) NOT NULL,
    subsector_name  VARCHAR(255),
    description     TEXT
);

COMMENT ON TABLE naics_codes IS 'North American Industry Classification System lookup table';

-- Populate common NAICS sector mappings
INSERT INTO naics_codes (naics_code, sector_code, sector_name, subsector_name) VALUES
('11', '11', 'Agriculture, Forestry, Fishing and Hunting', 'General'),
('21', '21', 'Mining, Quarrying, and Oil and Gas Extraction', 'General'),
('22', '22', 'Utilities', 'General'),
('23', '23', 'Construction', 'General'),
('31', '31', 'Manufacturing', 'Food, Beverage, Textile'),
('32', '32', 'Manufacturing', 'Wood, Paper, Chemical'),
('33', '33', 'Manufacturing', 'Metal, Machinery, Electronics'),
('42', '42', 'Wholesale Trade', 'General'),
('44', '44', 'Retail Trade', 'Motor Vehicle, Furniture, Electronics'),
('45', '45', 'Retail Trade', 'General Merchandise, Miscellaneous'),
('48', '48', 'Transportation and Warehousing', 'Transportation'),
('49', '49', 'Transportation and Warehousing', 'Warehousing, Postal'),
('51', '51', 'Information', 'General'),
('52', '52', 'Finance and Insurance', 'General'),
('53', '53', 'Real Estate and Rental and Leasing', 'General'),
('54', '54', 'Professional, Scientific, and Technical Services', 'General'),
('55', '55', 'Management of Companies and Enterprises', 'General'),
('56', '56', 'Administrative and Support Services', 'General'),
('61', '61', 'Educational Services', 'General'),
('62', '62', 'Health Care and Social Assistance', 'General'),
('71', '71', 'Arts, Entertainment, and Recreation', 'General'),
('72', '72', 'Accommodation and Food Services', 'General'),
('81', '81', 'Other Services (except Public Administration)', 'General'),
('92', '92', 'Public Administration', 'General');

-- ============================================================================
-- REFERENCE TABLE: State to Region Mapping
-- ============================================================================

CREATE TABLE state_regions (
    state_code      CHAR(2) PRIMARY KEY,
    state_name      VARCHAR(50) NOT NULL,
    region          VARCHAR(20) NOT NULL,
    division        VARCHAR(30) NOT NULL
);

COMMENT ON TABLE state_regions IS 'US Census Bureau regional classification of states';

-- Populate state-region mappings
INSERT INTO state_regions (state_code, state_name, region, division) VALUES
('AL', 'Alabama', 'South', 'East South Central'),
('AK', 'Alaska', 'West', 'Pacific'),
('AZ', 'Arizona', 'West', 'Mountain'),
('AR', 'Arkansas', 'South', 'West South Central'),
('CA', 'California', 'West', 'Pacific'),
('CO', 'Colorado', 'West', 'Mountain'),
('CT', 'Connecticut', 'Northeast', 'New England'),
('DE', 'Delaware', 'South', 'South Atlantic'),
('FL', 'Florida', 'South', 'South Atlantic'),
('GA', 'Georgia', 'South', 'South Atlantic'),
('HI', 'Hawaii', 'West', 'Pacific'),
('ID', 'Idaho', 'West', 'Mountain'),
('IL', 'Illinois', 'Midwest', 'East North Central'),
('IN', 'Indiana', 'Midwest', 'East North Central'),
('IA', 'Iowa', 'Midwest', 'West North Central'),
('KS', 'Kansas', 'Midwest', 'West North Central'),
('KY', 'Kentucky', 'South', 'East South Central'),
('LA', 'Louisiana', 'South', 'West South Central'),
('ME', 'Maine', 'Northeast', 'New England'),
('MD', 'Maryland', 'South', 'South Atlantic'),
('MA', 'Massachusetts', 'Northeast', 'New England'),
('MI', 'Michigan', 'Midwest', 'East North Central'),
('MN', 'Minnesota', 'Midwest', 'West North Central'),
('MS', 'Mississippi', 'South', 'East South Central'),
('MO', 'Missouri', 'Midwest', 'West North Central'),
('MT', 'Montana', 'West', 'Mountain'),
('NE', 'Nebraska', 'Midwest', 'West North Central'),
('NV', 'Nevada', 'West', 'Mountain'),
('NH', 'New Hampshire', 'Northeast', 'New England'),
('NJ', 'New Jersey', 'Northeast', 'Middle Atlantic'),
('NM', 'New Mexico', 'West', 'Mountain'),
('NY', 'New York', 'Northeast', 'Middle Atlantic'),
('NC', 'North Carolina', 'South', 'South Atlantic'),
('ND', 'North Dakota', 'Midwest', 'West North Central'),
('OH', 'Ohio', 'Midwest', 'East North Central'),
('OK', 'Oklahoma', 'South', 'West South Central'),
('OR', 'Oregon', 'West', 'Pacific'),
('PA', 'Pennsylvania', 'Northeast', 'Middle Atlantic'),
('RI', 'Rhode Island', 'Northeast', 'New England'),
('SC', 'South Carolina', 'South', 'South Atlantic'),
('SD', 'South Dakota', 'Midwest', 'West North Central'),
('TN', 'Tennessee', 'South', 'East South Central'),
('TX', 'Texas', 'South', 'West South Central'),
('UT', 'Utah', 'West', 'Mountain'),
('VT', 'Vermont', 'Northeast', 'New England'),
('VA', 'Virginia', 'South', 'South Atlantic'),
('WA', 'Washington', 'West', 'Pacific'),
('WV', 'West Virginia', 'South', 'South Atlantic'),
('WI', 'Wisconsin', 'Midwest', 'East North Central'),
('WY', 'Wyoming', 'West', 'Mountain'),
('DC', 'District of Columbia', 'South', 'South Atlantic'),
('PR', 'Puerto Rico', 'South', 'Caribbean'),
('GU', 'Guam', 'West', 'Pacific'),
('VI', 'Virgin Islands', 'South', 'Caribbean');

-- ============================================================================
-- PRIMARY TABLE: SBA Loans
-- ============================================================================

CREATE TABLE sba_loans (
    -- Primary identifier
    loan_id             VARCHAR(12) PRIMARY KEY,

    -- Borrower information
    business_name       VARCHAR(255),
    city                VARCHAR(100),
    state               CHAR(2),
    zip                 VARCHAR(10),

    -- Lender information
    bank_name           VARCHAR(255),
    bank_state          CHAR(2),

    -- Industry classification
    naics               VARCHAR(6),

    -- Loan dates
    approval_date       DATE,
    approval_fy         INTEGER,
    disbursement_date   DATE,

    -- Loan terms
    term_months         INTEGER,

    -- Business characteristics
    num_employees       INTEGER,
    new_business        INTEGER,  -- 1=Existing, 2=New
    jobs_created        INTEGER,
    jobs_retained       INTEGER,
    franchise_code      VARCHAR(10),
    urban_rural         INTEGER,  -- 0=Undefined, 1=Urban, 2=Rural

    -- Program flags
    rev_line_of_credit  CHAR(1),  -- Y/N
    low_doc             CHAR(1),  -- Y/N

    -- Financial amounts
    gross_approved      DECIMAL(15,2),
    sba_approved        DECIMAL(15,2),
    disbursement_gross  DECIMAL(15,2),
    balance_gross       DECIMAL(15,2),

    -- Loan outcome
    loan_status         VARCHAR(20),  -- PIF (Paid in Full) or CHGOFF (Charged Off)
    chargeoff_date      DATE,
    chargeoff_amount    DECIMAL(15,2),

    -- Metadata
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE sba_loans IS 'SBA 7(a) loan program data from FOIA requests';
COMMENT ON COLUMN sba_loans.loan_id IS 'Unique loan identifier with check digit';
COMMENT ON COLUMN sba_loans.loan_status IS 'PIF=Paid In Full, CHGOFF=Charged Off/Defaulted';
COMMENT ON COLUMN sba_loans.new_business IS '1=Existing Business, 2=New Business';
COMMENT ON COLUMN sba_loans.urban_rural IS '0=Undefined, 1=Urban, 2=Rural';

-- ============================================================================
-- INDEXES: Optimize common query patterns
-- ============================================================================

-- Date-based queries (vintage analysis, trends)
CREATE INDEX idx_sba_loans_approval_date ON sba_loans(approval_date);
CREATE INDEX idx_sba_loans_approval_fy ON sba_loans(approval_fy);
CREATE INDEX idx_sba_loans_disbursement_date ON sba_loans(disbursement_date);

-- Geographic analysis
CREATE INDEX idx_sba_loans_state ON sba_loans(state);
CREATE INDEX idx_sba_loans_bank_state ON sba_loans(bank_state);

-- Industry analysis
CREATE INDEX idx_sba_loans_naics ON sba_loans(naics);

-- Risk/default analysis
CREATE INDEX idx_sba_loans_status ON sba_loans(loan_status);
CREATE INDEX idx_sba_loans_chargeoff_date ON sba_loans(chargeoff_date);

-- Composite indexes for common query patterns
CREATE INDEX idx_sba_loans_state_status ON sba_loans(state, loan_status);
CREATE INDEX idx_sba_loans_fy_status ON sba_loans(approval_fy, loan_status);
CREATE INDEX idx_sba_loans_naics_status ON sba_loans(naics, loan_status);

-- ============================================================================
-- CONSTRAINTS: Data integrity rules
-- ============================================================================

-- Add check constraints for data validation
ALTER TABLE sba_loans
    ADD CONSTRAINT chk_loan_status
    CHECK (loan_status IN ('PIF', 'CHGOFF') OR loan_status IS NULL);

ALTER TABLE sba_loans
    ADD CONSTRAINT chk_new_business
    CHECK (new_business IN (1, 2) OR new_business IS NULL);

ALTER TABLE sba_loans
    ADD CONSTRAINT chk_urban_rural
    CHECK (urban_rural IN (0, 1, 2) OR urban_rural IS NULL);

ALTER TABLE sba_loans
    ADD CONSTRAINT chk_rev_line
    CHECK (rev_line_of_credit IN ('Y', 'N') OR rev_line_of_credit IS NULL);

ALTER TABLE sba_loans
    ADD CONSTRAINT chk_low_doc
    CHECK (low_doc IN ('Y', 'N') OR low_doc IS NULL);

ALTER TABLE sba_loans
    ADD CONSTRAINT chk_gross_approved_positive
    CHECK (gross_approved >= 0 OR gross_approved IS NULL);

ALTER TABLE sba_loans
    ADD CONSTRAINT chk_sba_approved_positive
    CHECK (sba_approved >= 0 OR sba_approved IS NULL);

ALTER TABLE sba_loans
    ADD CONSTRAINT chk_term_positive
    CHECK (term_months > 0 OR term_months IS NULL);

-- Foreign key constraints (optional - depends on data completeness)
-- ALTER TABLE sba_loans
--     ADD CONSTRAINT fk_state
--     FOREIGN KEY (state) REFERENCES state_regions(state_code);

-- ============================================================================
-- HELPER FUNCTION: Calculate SBA guarantee percentage
-- ============================================================================

CREATE OR REPLACE FUNCTION calculate_guarantee_pct(sba_amt DECIMAL, gross_amt DECIMAL)
RETURNS DECIMAL AS $$
BEGIN
    IF gross_amt IS NULL OR gross_amt = 0 THEN
        RETURN NULL;
    END IF;
    RETURN ROUND((sba_amt / gross_amt) * 100, 2);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION calculate_guarantee_pct IS 'Calculate SBA guarantee percentage for a loan';

-- ============================================================================
-- HELPER FUNCTION: Categorize loan size
-- ============================================================================

CREATE OR REPLACE FUNCTION categorize_loan_size(amount DECIMAL)
RETURNS VARCHAR AS $$
BEGIN
    CASE
        WHEN amount IS NULL THEN RETURN 'Unknown';
        WHEN amount < 50000 THEN RETURN 'Micro (<$50K)';
        WHEN amount < 150000 THEN RETURN 'Small ($50K-$150K)';
        WHEN amount < 350000 THEN RETURN 'Medium ($150K-$350K)';
        WHEN amount < 1000000 THEN RETURN 'Large ($350K-$1M)';
        ELSE RETURN 'Jumbo (>$1M)';
    END CASE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION categorize_loan_size IS 'Categorize loans into size buckets for analysis';

-- ============================================================================
-- HELPER FUNCTION: Extract industry sector from NAICS
-- ============================================================================

CREATE OR REPLACE FUNCTION get_naics_sector(naics_code VARCHAR)
RETURNS VARCHAR AS $$
BEGIN
    IF naics_code IS NULL OR LENGTH(naics_code) < 2 THEN
        RETURN 'Unknown';
    END IF;
    RETURN LEFT(naics_code, 2);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION get_naics_sector IS 'Extract 2-digit sector code from NAICS';

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Verify table creation
SELECT
    table_name,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_name = 'sba_loans'
ORDER BY ordinal_position;

-- Verify indexes
SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'sba_loans';

-- Verify constraints
SELECT
    conname AS constraint_name,
    contype AS constraint_type,
    pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'sba_loans'::regclass;

-- ============================================================================
-- DATA IMPORT TEMPLATE
-- ============================================================================

/*
After downloading the SBA FOIA data CSV, use the following command to import:

\copy sba_loans(
    loan_id, business_name, city, state, zip, bank_name, bank_state,
    naics, approval_date, approval_fy, term_months, num_employees,
    new_business, jobs_created, jobs_retained, franchise_code, urban_rural,
    rev_line_of_credit, low_doc, disbursement_date, disbursement_gross,
    balance_gross, loan_status, chargeoff_date, chargeoff_amount,
    gross_approved, sba_approved
) FROM '/path/to/sba_data.csv' WITH (FORMAT csv, HEADER true, NULL '');

Note: Column order in CSV may differ. Adjust the column list to match your CSV structure.
You may need to create a staging table first and then transform into this schema.
*/

-- Print completion message
DO $$
BEGIN
    RAISE NOTICE 'Schema creation completed successfully!';
    RAISE NOTICE 'Tables created: sba_loans, naics_codes, state_regions';
    RAISE NOTICE 'Next step: Import SBA FOIA data using \copy command';
END $$;
