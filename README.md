[![Snowflake - Certified](https://img.shields.io/badge/Snowflake-Certified-2ea44f?style=for-the-badge&logo=snowflake)](https://developers.snowflake.com/solutions/)

# Defect Detection using Distributed PyTorch with Snowflake Notebooks

## Overview

In this guide, we will perform multiclass defect detection on PCB images using distributed PyTorch training across multiple nodes and workers within a Snowflake Notebook. This guide utilizes a pre-trained Faster R-CNN model with ResNet50 as the backbone from PyTorch, fine-tuned for the task. The trained model is logged in the Snowpark Model Registry for future use. Additionally, a Streamlit app is developed to enable real-time defect detection on new images, making inference accessible and user-friendly.

## Prerequisites

### 1. Snowflake Account Requirements
- Snowflake account with the following capabilities:
  - **GPU Compute Pools**: Access to GPU_NV_S instance family for distributed training
  - **Snowflake Notebooks**: Container runtime support
  - **USERADMIN** privilege for role creation
  - **SYSADMIN** role for database and warehouse management

### 2. Dataset
- The deployment script automatically downloads the PCB dataset from the [DeepPCB repository](https://github.com/tangsanli5201/DeepPCB/tree/master/PCBData) using sparse checkout
- **Important**: Review and comply with the licensing terms and usage guidelines of the repository owner before using the dataset
- The dataset will be downloaded to `data/PCBData` during deployment
- If you already have the dataset, use `--skip-data-download` flag

### 3. Local Environment Setup
- **Python 3.11+** (for data upload and preparation scripts)
- **Git**: Required for downloading the dataset
- **Snowflake CLI** (`snow`): Install via `pip install snowflake-cli-labs`
- **Snowflake account credentials**: Configured with keypair authentication
- Required Python packages (auto-installed by deploy.sh if missing):
  ```bash
  pip install snowflake-snowpark-python pandas scikit-learn
  ```

### 4. Snowflake CLI Configuration
Ensure your Snowflake CLI is configured with your connection details. The scripts use the `snow sql` command which requires a properly configured connection profile.

**Option 1: Named Connection (Recommended)**

Create a connection named "demo" in your `~/.snowflake/connections.toml`:

```toml
[demo]
account = "your-account"
user = "your-username"
authenticator = "SNOWFLAKE"  # or "externalbrowser", "oauth", etc.
# password = "your-password"  # Optional if using key-pair
private_key_file = "~/.ssh/snowflake_key.p8"  # Optional for key-pair authentication
role = "SYSADMIN"
warehouse = "COMPUTE_WH"
database = "DEMO_DB"
```

**Option 2: Command Line Parameters**

You can also provide connection details directly when running the scripts:

```bash
./deploy.sh --account myaccount --user myuser --private-key-file ~/.ssh/snowflake_key.p8 -x
```

## Project Structure

```
cv_defect_detection_model/
├── README.md                    # This file
├── LICENSE                      # License information
├── deploy.sh                    # Deployment script (downloads data, creates objects, uploads files)
├── run.sh                       # Streamlit app creation script
├── clean.sh                     # Teardown script
├── data/                        # Downloaded datasets (created by deploy.sh)
│   └── PCBData/                 # DeepPCB dataset (auto-downloaded)
├── notebooks/
│   ├── 0_data_preparation_run_in_local_IDE.ipynb    # Data prep notebook (run locally)
│   ├── 1_Distributed_Model_Training_Snowflake_Notebooks.ipynb  # Training notebook
│   ├── environment.yaml         # Notebook environment dependencies
│   └── snowflake.yml            # Notebook deployment configuration (definition_version: 2)
├── scripts/
│   ├── setup.sql                # Snowflake object creation SQL
│   └── upload_data.py           # Data upload and processing script
└── streamlitapp/
    ├── streamlit_app.py         # Main Streamlit application
    ├── environment.yml          # Streamlit environment
    └── ...                      # Supporting files
```

## Setup Instructions

### Step 1: Deploy All Resources

Run the deployment script to download the dataset and create all Snowflake objects:

```bash
./deploy.sh
```

This script will:
1. **Download PCBData Dataset** (using sparse checkout from GitHub)
   - Downloads to `data/PCBData`
   - Use `--skip-data-download` if you already have the data
2. **Create Snowflake Objects**
   - Create the `PCB_CV_ROLE` custom role and grant it to current user
   - Create the `PCB_CV` database and schema
   - Create the `PCB_CV_WH` warehouse
   - Create the `PCB_CV_DEEP_PCB_DATASET_STAGE` internal stage
   - Create the `PCB_CV_COMPUTEPOOL` GPU compute pool
   - Create all required tables
   - Grant ownership of all objects to `PCB_CV_ROLE`
3. **Upload Training Data** (automatically processes and uploads dataset)
   - Processes images and labels from `data/PCBData` locally
   - Creates `LABELS_TRAIN` table from parsed label files
   - Converts images to base64 and merges with labels
   - Writes data directly to Snowflake tables using bulk operations
   - Creates `train_images_labels`, `training_data`, and `test_data` tables
   - Use `--skip-data-upload` to skip this step
   - **Note**: This step may take 10-15 minutes depending on dataset size
4. **Deploy Training Notebook**
   - Uses `snow notebook deploy` with `snowflake.yml` configuration (definition_version: 2)
   - Uploads `1_Distributed_Model_Training_Snowflake_Notebooks.ipynb` to Snowflake stage
   - Uploads `environment.yaml` with Python dependencies alongside notebook
   - Automatically creates the notebook `PCB_CV_TRAINING_NOTEBOOK` in Snowflake
   - Configures notebook with `SYSTEM$GPU_RUNTIME` and `PCB_CV_COMPUTEPOOL`
   - Use `--skip-notebook-upload` to skip this step
5. **Upload Streamlit App Files**
   - Uploads all Streamlit app files to stage
   - Use `--skip-streamlit-upload` to skip this step

**Deployment Options:**
```bash
# Full deployment (download dataset, create objects, upload data, upload files)
./deploy.sh

# Use different connection
./deploy.sh -c production

# Skip data download if already exists
./deploy.sh --skip-data-download

# Skip data upload (if you want to upload manually via notebook)
./deploy.sh --skip-data-upload

# Skip notebook and Streamlit uploads
./deploy.sh --skip-notebook-upload --skip-streamlit-upload

# Only create Snowflake objects, skip everything else
./deploy.sh --skip-data-download --skip-data-upload --skip-notebook-upload --skip-streamlit-upload
```

### Step 2: Data Preparation (Optional)

**Note**: If you ran `./deploy.sh` without the `--skip-data-upload` flag, your data is already uploaded and processed. You can skip this step and proceed directly to Step 3.

For manual data preparation or custom scenarios:

1. Open `notebooks/0_data_preparation_run_in_local_IDE.ipynb` in Jupyter
2. Update the notebook to use:
   - Database: `PCB_CV`
   - Warehouse: `PCB_CV_WH`
   - Stage: `PCB_CV_DEEP_PCB_DATASET_STAGE`
   - Dataset path: `./data/PCBData` (or wherever you downloaded it)
3. Run all cells to:
   - Upload images and labels to Snowflake stages
   - Parse label files and create `LABELS_TRAIN` table
   - Convert images to base64 and merge with labels
   - Create `train_images_labels`, `training_data`, and `test_data` tables

**Alternative**: Run the upload script manually:
```bash
python3 scripts/upload_data.py -c demo --data-dir data/PCBData
```

### Step 3: Model Training

**Note**: If you ran `./deploy.sh` without the `--skip-notebook-upload` flag, the notebook is already created and ready to use.

1. Log in to Snowflake and navigate to **Projects** → **Notebooks**
2. Open the notebook: **`PCB_CV_TRAINING_NOTEBOOK`**
3. Ensure the compute pool is set to: **`PCB_CV_COMPUTEPOOL`**
4. Run the notebook cells to:
   - Load training data from Snowflake tables
   - Perform distributed PyTorch training with Faster R-CNN (4 workers, 1 GPU each)
   - Log the trained model to Snowpark Model Registry

**Alternative (Manual Creation)**: If you skipped notebook deployment, you can create it manually:
   - Click **Create** → **From Stage**
   - Select database: `PCB_CV`
   - Select stage: `PCB_CV_DEEP_PCB_DATASET_STAGE`
   - Path: `notebooks/1_Distributed_Model_Training_Snowflake_Notebooks.ipynb`
   - Select compute pool: `PCB_CV_COMPUTEPOOL`

### Step 4: Create Streamlit Application

Create the Streamlit application in Snowflake for inference:

```bash
./run.sh
```

**Note**: The app files were already uploaded to the stage during deployment (Step 1). This command creates the Streamlit app object in Snowflake.

The Streamlit app allows you to:
- Upload new PCB images
- Run defect detection using the trained model
- Visualize detected defects with bounding boxes

## Usage

### Quick Start Commands

```bash
# Full deployment: download dataset, create objects, upload data (10-15 min)
./deploy.sh

# Use different connection
./deploy.sh -c production

# Use specific credentials
./deploy.sh --account myaccount --user myuser --private-key-file ~/.ssh/snowflake.p8 -x

# Skip data upload if you want to do it manually
./deploy.sh --skip-data-upload

# Run the Streamlit application
./run.sh

# Tear down all resources (cleanup)
./clean.sh
```

### Connection Options

All scripts (`deploy.sh`, `run.sh`, `clean.sh`) support the same connection parameters as the `snow sql` command:

- `-c, --connection NAME` - Use a named connection from your connections.toml (default: "demo")
- `--account NAME` - Snowflake account name
- `--user NAME` - Username
- `--password PASS` - Password
- `--authenticator TYPE` - Authenticator type
- `--private-key-file PATH` - Path to private key file
- `--role NAME` - Role to use
- `-x, --temporary-connection` - Use command line parameters instead of config file

**Examples:**
```bash
# Use the default 'demo' connection
./deploy.sh

# Use a named 'production' connection
./deploy.sh -c production

# Use specific account and credentials
./deploy.sh --account xy12345 --user john_doe --role SYSADMIN
```

### Manual Data Upload

If you need to manually upload data to Snowflake stages:

```sql
-- Upload images
PUT file:///path/to/PCBData/*_test.jpg @PCB_CV_DEEP_PCB_DATASET_STAGE/images/train AUTO_COMPRESS=FALSE;

-- Upload labels
PUT file:///path/to/PCBData/*.txt @PCB_CV_DEEP_PCB_DATASET_STAGE/labels/train AUTO_COMPRESS=FALSE;
```

## Key Components

### Snowflake Objects
- **Role**: `PCB_CV_ROLE` (custom role with ownership of all demo objects)
- **Database**: `PCB_CV`
- **Schema**: `PUBLIC`
- **Warehouse**: `PCB_CV_WH` (SMALL, auto-suspend after 5 minutes)
- **Compute Pool**: `PCB_CV_COMPUTEPOOL` (GPU_NV_S, 1-2 nodes, auto-suspend after 2 hours)
- **Stage**: `PCB_CV_DEEP_PCB_DATASET_STAGE` (internal stage for images and labels)
- **Streamlit App**: `PCB_CV_DEFECT_DETECTION_APP`

### Tables
1. **LABELS_TRAIN**: Parsed label data with bounding box coordinates
2. **train_images_labels**: Combined images (base64) and labels
3. **training_data**: 90% training split
4. **test_data**: 10% test split

### Naming Convention
This demo follows a consistent naming pattern:
- Prefix: `PCB_CV_` (Project identifier)
- Objects: `{PREFIX}{OBJECT_TYPE}` (e.g., `PCB_CV_WH`, `PCB_CV_ROLE`)
- Stage: `{PREFIX}DEEP_PCB_DATASET_STAGE` (descriptive of data source)
- Streamlit: `{PREFIX}DEFECT_DETECTION_APP` (descriptive of function)

## Dataset Details

The PCB (Printed Circuit Board) dataset contains:
- **Images**: PCB images with various defect types
- **Labels**: Bounding box coordinates (xmin, ymin, xmax, ymax) and defect class
- **Format**: JPG images with corresponding TXT label files
- **Split**: 90% training, 10% testing

### Defect Classes
The dataset includes multiple defect classes commonly found in PCB manufacturing (refer to the original dataset documentation for specific class definitions).

## Troubleshooting

### GPU Compute Pool Not Available
- Ensure your Snowflake account has GPU compute pool capabilities enabled
- Contact Snowflake support to enable GPU access

### Data Download Issues
- If git sparse checkout fails, manually clone the repository
- Ensure you have network access to GitHub
- Check that the `data/` directory is writable

### Data Upload Issues
- **Automatic Upload Fails**: Check Python and required packages are installed
- **Connection Errors**: Verify Snowflake credentials and connection parameters
- **Timeout Issues**: For large datasets, the upload may take 10-15 minutes - be patient
- **Manual Upload**: Use `python3 scripts/upload_data.py -c demo --data-dir data/PCBData`
- **Check Progress**: The script shows progress for file uploads and table creation
- **Verify Tables**: After upload, check that these tables exist:
  - `LABELS_TRAIN`
  - `train_images_labels`
  - `training_data`
  - `test_data`

### Role and Permission Issues
- Ensure you have USERADMIN privileges to create roles
- Verify `PCB_CV_ROLE` was created and granted to your user
- Check ownership grants on all objects

### Authentication Issues
- Ensure Snowflake CLI is properly configured
- Verify keypair authentication is set up correctly
- Check the passphrase in `~/.snowsql/config` if using snowsql

## Cleanup

To completely remove all demo resources from your Snowflake account:

```bash
./clean.sh
```

This will:
- Drop the `PCB_CV_COMPUTEPOOL` compute pool
- Drop the `PCB_CV_WH` warehouse
- Drop the `PCB_CV` database (including all tables and stages)
- Drop the `PCB_CV_ROLE` role

**Warning**: This action cannot be undone and will delete all data.

## Additional Resources

- [Snowflake Notebooks Documentation](https://docs.snowflake.com/en/user-guide/ui-snowsight-notebooks)
- [Snowflake Compute Pools](https://docs.snowflake.com/en/user-guide/compute-pools)
- [PyTorch Faster R-CNN](https://pytorch.org/vision/stable/models.html#object-detection)
- [Original Dataset Repository](https://github.com/Charmve/Surface-Defect-Detection/tree/master/DeepPCB/PCBData)

## Step-By-Step Guide

For a detailed walkthrough with screenshots and explanations, please refer to the [QuickStart Guide](https://quickstarts.snowflake.com/guide/defect_detection_using_distributed_pyTorch_with_snowflake_notebooks/index.html?index=..%2F..index#0).

## License

See [LICENSE](LICENSE) file for details.

## Support

For issues and questions:
- Review the troubleshooting section above
- Check the Snowflake documentation
- Refer to the QuickStart guide for detailed instructions
