#!/bin/bash
# =============================================================================
# SBA 7(a) Loan Data Download Script
# =============================================================================
# This script downloads all SBA 7(a) FOIA loan data from data.sba.gov
# Data is split into decade-based files covering FY1991 to present
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Data directory
DATA_DIR="$(dirname "$0")/../data/raw"

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  SBA 7(a) Loan Data Download Script${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

# Create data directory if it doesn't exist
mkdir -p "$DATA_DIR"
cd "$DATA_DIR"

echo -e "${YELLOW}Downloading SBA 7(a) FOIA data files...${NC}"
echo "Data will be saved to: $DATA_DIR"
echo ""

# Download function with progress
download_file() {
    local url="$1"
    local filename="$2"
    local description="$3"

    echo -e "${YELLOW}Downloading: ${description}${NC}"
    if [ -f "$filename" ]; then
        echo -e "  File already exists. Skipping... (delete to re-download)"
    else
        curl -L --progress-bar -o "$filename" "$url"
        echo -e "${GREEN}  ✓ Downloaded: $filename${NC}"
    fi
    echo ""
}

# SBA 7(a) Data Files (as of 2025-12-31)
download_file \
    "https://data.sba.gov/en/dataset/0ff8e8e9-b967-4f4e-987c-6ac78c575087/resource/182e9421-ccee-4562-acb3-93b34fb695f2/download/foia-7a-fy1991-fy1999-as-of-251231.csv" \
    "sba_7a_1991_1999.csv" \
    "7(a) Loans FY1991-FY1999"

download_file \
    "https://data.sba.gov/en/dataset/0ff8e8e9-b967-4f4e-987c-6ac78c575087/resource/186eb176-b53e-4cbe-ab93-e5c4fb50197d/download/foia-7a-fy2000-fy2009-as-of-251231.csv" \
    "sba_7a_2000_2009.csv" \
    "7(a) Loans FY2000-FY2009"

download_file \
    "https://data.sba.gov/en/dataset/0ff8e8e9-b967-4f4e-987c-6ac78c575087/resource/3f838176-6060-44db-9c91-b4acafbcb28c/download/foia-7a-fy2010-fy2019-as-of-251231.csv" \
    "sba_7a_2010_2019.csv" \
    "7(a) Loans FY2010-FY2019"

download_file \
    "https://data.sba.gov/en/dataset/0ff8e8e9-b967-4f4e-987c-6ac78c575087/resource/d67d3ccb-2002-4134-a288-481b51cd3479/download/foia-7a-fy2020-present-as-of-251231.csv" \
    "sba_7a_2020_present.csv" \
    "7(a) Loans FY2020-Present"

# Download data dictionary
download_file \
    "https://data.sba.gov/en/dataset/0ff8e8e9-b967-4f4e-987c-6ac78c575087/resource/6898b986-a895-47b4-bb7e-c6b286b23a7b/download/7a_504_foia_data_dictionary.xlsx" \
    "data_dictionary.xlsx" \
    "Data Dictionary (Excel)"

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  Download Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

# Show file sizes
echo "Downloaded files:"
ls -lh "$DATA_DIR"/*.csv 2>/dev/null || echo "No CSV files found"
echo ""

# Count total rows (excluding headers)
echo "Counting records in each file..."
total_rows=0
for f in "$DATA_DIR"/*.csv; do
    if [ -f "$f" ]; then
        rows=$(($(wc -l < "$f") - 1))
        total_rows=$((total_rows + rows))
        echo "  $(basename "$f"): $(printf "%'d" $rows) records"
    fi
done
echo ""
echo -e "${GREEN}Total records across all files: $(printf "%'d" $total_rows)${NC}"
echo ""

echo "Next steps:"
echo "  1. Create PostgreSQL database: createdb sba_loans"
echo "  2. Run schema creation: psql -d sba_loans -f schema/01_create_tables.sql"
echo "  3. Run data import: psql -d sba_loans -f scripts/import_data.sql"
