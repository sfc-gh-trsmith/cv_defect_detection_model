#!/bin/bash

################################################################################
# PCB Defect Detection - Cleanup Script
################################################################################
# This script tears down all Snowflake resources created for the PCB defect
# detection demo. Use with caution as this will delete all data and objects.
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

Clean up all PCB Defect Detection demo resources from Snowflake.

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
echo "  PCB Defect Detection - Cleanup"
echo "════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "${BLUE}Connection:${NC} $CONNECTION_NAME"
echo ""
echo -e "${YELLOW}⚠️  WARNING: This will delete all demo resources including:${NC}"
echo "  • Database: PCB_CV (including ALL data and tables)"
echo "  • Warehouse: PCB_CV_WH"
echo "  • Compute Pool: PCB_CV_COMPUTEPOOL"
echo "  • Notebook: PCB_CV_TRAINING_NOTEBOOK"
echo "  • Role: PCB_CV_ROLE"
echo ""
echo -e "${RED}This action CANNOT be undone!${NC}"
echo ""

# Prompt for confirmation
read -p "Are you sure you want to proceed? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo ""
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo -e "${BLUE}Starting cleanup...${NC}"
echo ""

# Check if Snowflake CLI is installed
if ! command -v snow &> /dev/null; then
    echo -e "${RED}✗ Error: Snowflake CLI (snow) is not installed.${NC}"
    exit 1
fi

# Create a temporary SQL file for cleanup
CLEANUP_SQL=$(mktemp)
trap "rm -f $CLEANUP_SQL" EXIT

cat > "$CLEANUP_SQL" << 'EOF'
-- PCB Defect Detection Cleanup Script

USE ROLE SYSADMIN;

-- Drop compute pool first (must be done before role deletion)
DROP COMPUTE POOL IF EXISTS PCB_CV_COMPUTEPOOL;

-- Drop warehouse
DROP WAREHOUSE IF EXISTS PCB_CV_WH;

-- Drop notebook (must be done before dropping database)
DROP NOTEBOOK IF EXISTS PCB_CV.PUBLIC.PCB_CV_TRAINING_NOTEBOOK;

-- Drop database (this will drop all tables, stages, and associated objects)
DROP DATABASE IF EXISTS PCB_CV;

-- Switch to USERADMIN to drop role
USE ROLE USERADMIN;

-- Drop the demo role
DROP ROLE IF EXISTS PCB_CV_ROLE;

-- Display cleanup summary
SELECT 'Cleanup completed successfully!' AS status;
EOF

# Execute the cleanup script
echo -e "${BLUE}Dropping Snowflake objects...${NC}"
echo ""

if snow sql $SNOW_CONN -f "$CLEANUP_SQL" 2>&1; then
    echo ""
    echo -e "${GREEN}✓ Compute Pool removed${NC}"
    echo -e "${GREEN}✓ Warehouse removed${NC}"
    echo -e "${GREEN}✓ Notebook removed${NC}"
    echo -e "${GREEN}✓ Database removed${NC}"
    echo -e "${GREEN}✓ Role removed${NC}"
else
    echo ""
    echo -e "${YELLOW}⚠️  Warning: Some resources may not have been removed${NC}"
    echo "  This is normal if the resources didn't exist"
fi

echo ""
echo "════════════════════════════════════════════════════════════════════════"
echo -e "${GREEN}  Cleanup Complete!${NC}"
echo "════════════════════════════════════════════════════════════════════════"
echo ""
echo "All demo resources have been removed from your Snowflake account."
echo ""
echo "To redeploy the demo, run: ./deploy.sh $SNOW_CONN"
echo ""
