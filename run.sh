#!/bin/bash

################################################################################
# PCB Defect Detection - Run Streamlit App
################################################################################
# This script deploys and launches the Streamlit application for PCB defect
# detection inference in Snowflake.
################################################################################

set -e  # Exit on any error

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default connection name
CONNECTION_NAME="demo"
CONNECTION_PARAMS=""

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy and run the PCB Defect Detection Streamlit app in Snowflake.

Connection Options:
  -c, --connection NAME         Named connection from config.toml (default: demo)
  --account NAME               Snowflake account name
  --user NAME                  Username
  --password PASS              Password
  --authenticator TYPE         Authenticator type
  --private-key-file PATH      Path to private key file
  --database NAME              Database name
  --schema NAME                Schema name
  --role NAME                  Role name
  --warehouse NAME             Warehouse name
  -x, --temporary-connection   Use temporary connection with command line params

Other Options:
  -h, --help                   Show this help message

Examples:
  $0                                    # Use 'demo' connection
  $0 -c prod                            # Use 'prod' connection
  $0 --account myaccount --user john   # Use specific credentials

EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -c|--connection|--environment)
            CONNECTION_NAME="$2"
            shift 2
            ;;
        --account|--accountname)
            CONNECTION_PARAMS="$CONNECTION_PARAMS --account $2"
            shift 2
            ;;
        --user|--username)
            CONNECTION_PARAMS="$CONNECTION_PARAMS --user $2"
            shift 2
            ;;
        --password)
            CONNECTION_PARAMS="$CONNECTION_PARAMS --password $2"
            shift 2
            ;;
        --authenticator)
            CONNECTION_PARAMS="$CONNECTION_PARAMS --authenticator $2"
            shift 2
            ;;
        --private-key-file|--private-key-path)
            CONNECTION_PARAMS="$CONNECTION_PARAMS --private-key-file $2"
            shift 2
            ;;
        --database|--dbname)
            CONNECTION_PARAMS="$CONNECTION_PARAMS --database $2"
            shift 2
            ;;
        --schema|--schemaname)
            CONNECTION_PARAMS="$CONNECTION_PARAMS --schema $2"
            shift 2
            ;;
        --role|--rolename)
            CONNECTION_PARAMS="$CONNECTION_PARAMS --role $2"
            shift 2
            ;;
        --warehouse)
            CONNECTION_PARAMS="$CONNECTION_PARAMS --warehouse $2"
            shift 2
            ;;
        -x|--temporary-connection)
            CONNECTION_PARAMS="$CONNECTION_PARAMS -x"
            shift
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Build the connection string
if [ -n "$CONNECTION_PARAMS" ]; then
    SNOW_CONN="$CONNECTION_PARAMS"
else
    SNOW_CONN="-c $CONNECTION_NAME"
fi

echo "════════════════════════════════════════════════════════════════════════"
echo "  PCB Defect Detection - Streamlit App Deployment"
echo "════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "${BLUE}Connection:${NC} $CONNECTION_NAME"
echo ""

# Check if Snowflake CLI is installed
if ! command -v snow &> /dev/null; then
    echo -e "${RED}✗ Error: Snowflake CLI (snow) is not installed.${NC}"
    echo "  Install it using: pip install snowflake-cli-labs"
    exit 1
fi

echo -e "${GREEN}✓${NC} Snowflake CLI found"
echo ""

# Check if streamlit app directory exists
if [ ! -d "streamlitapp" ]; then
    echo -e "${RED}✗ Error: streamlitapp directory not found${NC}"
    exit 1
fi

# Check if required files exist
if [ ! -f "streamlitapp/streamlit_app.py" ]; then
    echo -e "${RED}✗ Error: streamlit_app.py not found in streamlitapp directory${NC}"
    exit 1
fi

if [ ! -f "streamlitapp/environment.yml" ]; then
    echo -e "${RED}✗ Error: environment.yml not found in streamlitapp directory${NC}"
    exit 1
fi

echo -e "${BLUE}Step 1: Preparing Streamlit App for Deployment${NC}"
echo "────────────────────────────────────────────────────────────────────────"
echo ""

# Change to streamlit app directory
cd streamlitapp

echo -e "${BLUE}Step 2: Deploying Streamlit App to Snowflake${NC}"
echo "────────────────────────────────────────────────────────────────────────"
echo ""
echo "Creating Streamlit app in Snowflake..."
echo "  • Database: PCB_CV"
echo "  • Schema: PUBLIC"
echo "  • App Name: PCB_CV_DEFECT_DETECTION_APP"
echo ""

# Create a temporary SQL file for Streamlit app creation
STREAMLIT_SQL=$(mktemp)
trap "rm -f $STREAMLIT_SQL" EXIT

cat > "$STREAMLIT_SQL" << 'EOF'
USE ROLE PCB_CV_ROLE;
USE DATABASE PCB_CV;
USE SCHEMA PUBLIC;
USE WAREHOUSE PCB_CV_WH;

-- Create Streamlit app
CREATE OR REPLACE STREAMLIT PCB_CV_DEFECT_DETECTION_APP
    ROOT_LOCATION = '@PCB_CV.PUBLIC.PCB_CV_DEEP_PCB_DATASET_STAGE/streamlit'
    MAIN_FILE = 'streamlit_app.py'
    QUERY_WAREHOUSE = PCB_CV_WH
    COMMENT = 'PCB Defect Detection Inference Application';

SELECT 'Streamlit app created successfully!' AS status;
EOF

# Upload Streamlit app files to stage
echo "Uploading Streamlit app files to Snowflake stage..."
echo ""

if snow stage copy $SNOW_CONN streamlit_app.py @PCB_CV.PUBLIC.PCB_CV_DEEP_PCB_DATASET_STAGE/streamlit/ --overwrite; then
    echo -e "${GREEN}✓ Uploaded streamlit_app.py${NC}"
else
    echo -e "${RED}✗ Failed to upload streamlit_app.py${NC}"
    cd ..
    exit 1
fi

# Upload additional required files
for file in environment.yml page_helper.py utils.py pcb.png; do
    if [ -f "$file" ]; then
        if snow stage copy $SNOW_CONN "$file" @PCB_CV.PUBLIC.PCB_CV_DEEP_PCB_DATASET_STAGE/streamlit/ --overwrite; then
            echo -e "${GREEN}✓ Uploaded $file${NC}"
        else
            echo -e "${YELLOW}⚠️  Warning: Could not upload $file${NC}"
        fi
    fi
done

# Upload snowflakelogo directory if it exists
if [ -d "snowflakelogo" ]; then
    if snow stage copy $SNOW_CONN snowflakelogo/ @PCB_CV.PUBLIC.PCB_CV_DEEP_PCB_DATASET_STAGE/streamlit/snowflakelogo/ --overwrite --recursive; then
        echo -e "${GREEN}✓ Uploaded snowflakelogo directory${NC}"
    else
        echo -e "${YELLOW}⚠️  Warning: Could not upload snowflakelogo directory${NC}"
    fi
fi

echo ""
echo -e "${BLUE}Step 3: Creating Streamlit App in Snowflake${NC}"
echo "────────────────────────────────────────────────────────────────────────"
echo ""

# Create the Streamlit app using SQL
cd ..
if snow sql $SNOW_CONN -f "$STREAMLIT_SQL"; then
    echo ""
    echo -e "${GREEN}✓ Streamlit app created successfully${NC}"
else
    echo ""
    echo -e "${RED}✗ Error: Failed to create Streamlit app${NC}"
    exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════════════════════"
echo -e "${GREEN}  Streamlit App Deployment Complete!${NC}"
echo "════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "${YELLOW}Access Your Application:${NC}"
echo ""
echo "1. Log in to your Snowflake account"
echo "2. Navigate to: ${BLUE}Projects → Streamlit${NC}"
echo "3. Find and open: ${BLUE}PCB_CV_DEFECT_DETECTION_APP${NC}"
echo ""
echo "OR"
echo ""
echo "Run this SQL command in a Snowflake worksheet:"
echo "${BLUE}  USE DATABASE PCB_CV;${NC}"
echo "${BLUE}  SHOW STREAMLIT APPS;${NC}"
echo ""
echo -e "${YELLOW}Note:${NC}"
echo "• Ensure the model has been trained and registered in Snowpark Model Registry"
echo "• The app uses the PCB_CV_WH warehouse for queries"
echo "• Upload PCB images through the app interface for defect detection"
echo ""
