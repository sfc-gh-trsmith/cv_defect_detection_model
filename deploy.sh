#!/bin/bash

################################################################################
# PCB Defect Detection - Deployment Script
################################################################################
# This script deploys all necessary Snowflake resources for the PCB defect
# detection demo including database, warehouse, stages, and compute pool.
# It also downloads the PCBData dataset and uploads notebooks and Streamlit app.
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
SKIP_DATA_DOWNLOAD=false
SKIP_DATA_UPLOAD=false
SKIP_NOTEBOOK_UPLOAD=false
SKIP_STREAMLIT_UPLOAD=false

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy PCB Defect Detection demo to Snowflake.

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

Deployment Options:
  --skip-data-download         Skip downloading PCBData dataset
  --skip-data-upload           Skip uploading data to Snowflake
  --skip-notebook-upload       Skip uploading training notebook
  --skip-streamlit-upload      Skip uploading Streamlit app

Other Options:
  -h, --help                   Show this help message

Examples:
  $0                                    # Use 'demo' connection
  $0 -c prod                            # Use 'prod' connection
  $0 --account myaccount --user john   # Use specific credentials
  $0 --skip-data-download              # Skip dataset download if already exists

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
        --skip-data-download)
            SKIP_DATA_DOWNLOAD=true
            shift
            ;;
        --skip-data-upload)
            SKIP_DATA_UPLOAD=true
            shift
            ;;
        --skip-notebook-upload)
            SKIP_NOTEBOOK_UPLOAD=true
            shift
            ;;
        --skip-streamlit-upload)
            SKIP_STREAMLIT_UPLOAD=true
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
echo "  PCB Defect Detection - Deployment"
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

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo -e "${RED}✗ Error: git is not installed.${NC}"
    echo "  Install git to download the PCBData dataset"
    exit 1
fi

echo -e "${GREEN}✓${NC} Git found"
echo ""

# Check if setup.sql exists
if [ ! -f "scripts/setup.sql" ]; then
    echo -e "${RED}✗ Error: scripts/setup.sql not found${NC}"
    exit 1
fi

# =============================================================================
# Step 1: Download PCBData Dataset
# =============================================================================
if [ "$SKIP_DATA_DOWNLOAD" = false ]; then
    echo -e "${BLUE}Step 1: Downloading PCBData Dataset${NC}"
    echo "────────────────────────────────────────────────────────────────────────"
    echo "Performing sparse checkout of PCBData from GitHub..."
    echo "Repository: https://github.com/tangsanli5201/DeepPCB"
    echo ""

    # Create data directory if it doesn't exist
    mkdir -p data

    # Check if PCBData already exists
    if [ -d "data/PCBData" ]; then
        echo -e "${YELLOW}⚠️  PCBData directory already exists${NC}"
        read -p "Do you want to re-download? (yes/no): " redownload
        if [ "$redownload" != "yes" ]; then
            echo "Skipping dataset download"
        else
            echo "Removing existing PCBData..."
            rm -rf data/PCBData
            
            # Perform sparse checkout
            echo "Cloning repository with sparse checkout..."
            cd data
            git clone --depth 1 --filter=blob:none --sparse \
                https://github.com/tangsanli5201/DeepPCB.git temp_clone
            
            cd temp_clone
            git sparse-checkout set PCBData
            
            # Move PCBData to parent directory
            mv PCBData ../
            cd ..
            rm -rf temp_clone
            cd ..
            
            echo -e "${GREEN}✓ PCBData downloaded successfully${NC}"
        fi
    else
        # Perform sparse checkout
        echo "Cloning repository with sparse checkout..."
        cd data
        git clone --depth 1 --filter=blob:none --sparse \
            https://github.com/tangsanli5201/DeepPCB.git temp_clone
        
        cd temp_clone
        git sparse-checkout set PCBData
        
        # Move PCBData to parent directory
        mv PCBData ../
        cd ..
        rm -rf temp_clone
        cd ..
        
        echo -e "${GREEN}✓ PCBData downloaded successfully to data/PCBData${NC}"
    fi
    echo ""
else
    echo -e "${YELLOW}Skipping dataset download (--skip-data-download specified)${NC}"
    echo ""
fi

# =============================================================================
# Step 2: Create Snowflake Objects
# =============================================================================
echo -e "${BLUE}Step 2: Creating Snowflake Objects${NC}"
echo "────────────────────────────────────────────────────────────────────────"
echo "Creating:"
echo "  • Role: PCB_CV_ROLE"
echo "  • Database: PCB_CV"
echo "  • Warehouse: PCB_CV_WH"
echo "  • Stage: PCB_CV_DEEP_PCB_DATASET_STAGE"
echo "  • Compute Pool: PCB_CV_COMPUTEPOOL (GPU)"
echo "  • Tables: LABELS_TRAIN, train_images_labels, training_data, test_data"
echo ""

# Run the setup SQL script using Snowflake CLI
if snow sql $SNOW_CONN -f scripts/setup.sql; then
    echo ""
    echo -e "${GREEN}✓ Snowflake objects created successfully${NC}"
else
    echo ""
    echo -e "${RED}✗ Error: Failed to execute setup.sql${NC}"
    echo "  Check your Snowflake CLI configuration and credentials"
    exit 1
fi
echo ""

# =============================================================================
# Step 3: Upload Training Data to Snowflake
# =============================================================================
if [ "$SKIP_DATA_UPLOAD" = false ]; then
    echo -e "${BLUE}Step 3: Uploading Training Data to Snowflake${NC}"
    echo "────────────────────────────────────────────────────────────────────────"
    echo ""

    if [ ! -d "data/PCBData" ]; then
        echo -e "${YELLOW}⚠️  Warning: data/PCBData directory not found${NC}"
        echo "  Please ensure the dataset was downloaded in Step 1"
        echo "  Or run with --skip-data-upload to skip this step"
        echo ""
    else
        echo "Uploading PCB dataset files and processing..."
        echo "This may take several minutes depending on dataset size..."
        echo ""

        # Check if Python is available
        if ! command -v python3 &> /dev/null; then
            echo -e "${RED}✗ Error: python3 is not installed.${NC}"
            exit 1
        fi

        # Check if required Python packages are installed
        if ! python3 -c "import snowflake.snowpark" 2>/dev/null; then
            echo -e "${YELLOW}⚠️  Warning: snowflake-snowpark-python not installed${NC}"
            echo "  Installing required packages..."
            pip3 install snowflake-snowpark-python pandas scikit-learn --quiet
        fi

        # Run the upload script with connection name
        # Note: upload_data.py uses the named connection from ~/.snowflake/connections.toml
        if python3 scripts/upload_data.py -c "$CONNECTION_NAME" --data-dir data/PCBData; then
            echo ""
            echo -e "${GREEN}✓ Data uploaded and processed successfully${NC}"
        else
            echo ""
            echo -e "${RED}✗ Error: Data upload failed${NC}"
            echo "  Check the error messages above for details"
            exit 1
        fi
    fi
    echo ""
else
    echo -e "${YELLOW}Skipping data upload (--skip-data-upload specified)${NC}"
    echo ""
fi

# =============================================================================
# Step 4: Deploy Training Notebook to Snowflake
# =============================================================================
if [ "$SKIP_NOTEBOOK_UPLOAD" = false ]; then
    echo -e "${BLUE}Step 4: Deploying Training Notebook to Snowflake${NC}"
    echo "────────────────────────────────────────────────────────────────────────"
    echo ""

    if [ -f "notebooks/1_Distributed_Model_Training_Snowflake_Notebooks.ipynb" ]; then
        if [ ! -f "notebooks/snowflake.yml" ]; then
            echo -e "${RED}✗ Error: notebooks/snowflake.yml not found${NC}"
            echo "  This file is required for notebook deployment"
            exit 1
        fi
        
        echo "Deploying notebook with environment configuration..."
        echo "This will upload the notebook and environment.yaml files..."
        echo ""
        
        # Change to notebooks directory since snowflake.yml is there
        cd notebooks
        
        if snow notebook deploy pcb_cv_training_notebook $SNOW_CONN \
            --database PCB_CV \
            --schema PUBLIC \
            --role PCB_CV_ROLE \
            --replace; then
            cd ..
            echo ""
            echo -e "${GREEN}✓ Notebook 'PCB_CV_TRAINING_NOTEBOOK' deployed successfully${NC}"
            
            # Configure notebook runtime and compute pool
            echo "Configuring notebook runtime and compute pool..."
            if snow sql $SNOW_CONN -q "ALTER NOTEBOOK PCB_CV.PUBLIC.PCB_CV_TRAINING_NOTEBOOK SET RUNTIME_NAME = 'SYSTEM\$GPU_RUNTIME', COMPUTE_POOL = PCB_CV_COMPUTEPOOL" --database PCB_CV --schema PUBLIC --role PCB_CV_ROLE; then
                echo -e "${GREEN}✓ Notebook configured with GPU runtime and compute pool${NC}"
            else
                echo -e "${YELLOW}⚠️  Warning: Could not configure notebook runtime automatically${NC}"
                echo "  You may need to set the compute pool manually in the notebook"
            fi
            
            echo ""
            echo -e "${YELLOW}Note:${NC} Access the notebook in Snowflake:"
            echo "  • Navigate to Projects → Notebooks"
            echo "  • Open 'PCB_CV_TRAINING_NOTEBOOK'"
            echo "  • The notebook is pre-configured with GPU runtime and PCB_CV_COMPUTEPOOL"
            echo "  • The notebook includes environment.yaml with dependencies"
            echo "  • Run the cells to train your model"
            echo ""
        else
            cd ..
            echo ""
            echo -e "${RED}✗ Error: Failed to deploy notebook${NC}"
            echo "  Check the error messages above for details"
            echo "  Ensure notebooks/snowflake.yml is configured correctly"
            exit 1
        fi
    else
        echo -e "${RED}✗ Error: Training notebook not found${NC}"
        echo "  Expected: notebooks/1_Distributed_Model_Training_Snowflake_Notebooks.ipynb"
        exit 1
    fi
else
    echo -e "${YELLOW}Skipping notebook deployment (--skip-notebook-upload specified)${NC}"
    echo ""
fi

# =============================================================================
# Step 5: Upload Streamlit App
# =============================================================================
if [ "$SKIP_STREAMLIT_UPLOAD" = false ]; then
    echo -e "${BLUE}Step 5: Uploading Streamlit Application${NC}"
    echo "────────────────────────────────────────────────────────────────────────"
    echo ""

    if [ -d "streamlitapp" ]; then
        # Change to streamlit app directory
        cd streamlitapp

        echo "Uploading Streamlit files to stage..."
        echo ""

        # Upload main files
        for file in streamlit_app.py environment.yml page_helper.py utils.py pcb.png; do
            if [ -f "$file" ]; then
                if snow stage copy $SNOW_CONN "$file" \
                    @PCB_CV.PUBLIC.PCB_CV_DEEP_PCB_DATASET_STAGE/streamlit/ \
                    --overwrite 2>/dev/null; then
                    echo -e "${GREEN}✓ Uploaded $file${NC}"
                else
                    echo -e "${YELLOW}⚠️  Warning: Could not upload $file${NC}"
                fi
            fi
        done

        # Upload snowflakelogo directory if it exists
        if [ -d "snowflakelogo" ]; then
            for logo_file in snowflakelogo/*; do
                if [ -f "$logo_file" ]; then
                    if snow stage copy $SNOW_CONN "$logo_file" \
                        @PCB_CV.PUBLIC.PCB_CV_DEEP_PCB_DATASET_STAGE/streamlit/snowflakelogo/ \
                        --overwrite 2>/dev/null; then
                        echo -e "${GREEN}✓ Uploaded $(basename $logo_file)${NC}"
                    fi
                fi
            done
        fi

        cd ..

        echo ""
        echo -e "${GREEN}✓ Streamlit app files uploaded${NC}"
        echo ""
        echo -e "${YELLOW}Note:${NC} To create the Streamlit app, run: ${BLUE}./run.sh $SNOW_CONN${NC}"
        echo ""
    else
        echo -e "${YELLOW}⚠️  Warning: streamlitapp directory not found${NC}"
        echo ""
    fi
else
    echo -e "${YELLOW}Skipping Streamlit upload (--skip-streamlit-upload specified)${NC}"
    echo ""
fi

# =============================================================================
# Deployment Summary
# =============================================================================
echo "════════════════════════════════════════════════════════════════════════"
echo -e "${GREEN}  Deployment Complete!${NC}"
echo "════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. ${BLUE}Model Training${NC}"
echo "   • Log in to Snowflake web interface"
echo "   • Navigate to Projects → Notebooks"
echo "   • Open the notebook: ${BLUE}PCB_CV_TRAINING_NOTEBOOK${NC}"
echo "   • Ensure compute pool is set to: ${BLUE}PCB_CV_COMPUTEPOOL${NC}"
echo "   • Run the training cells to train your model"
echo ""
echo "2. ${BLUE}Create Streamlit App${NC}"
echo "   • Run: ${BLUE}./run.sh${NC} (or ${BLUE}./run.sh $SNOW_CONN${NC})"
echo ""
echo "3. ${BLUE}Clean Up${NC}"
echo "   • When done, run: ${BLUE}./clean.sh${NC} to remove all resources"
echo ""
echo "For detailed instructions, see README.md"
echo ""
