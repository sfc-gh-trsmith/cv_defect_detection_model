-- ============================================================================
-- PCB Defect Detection - Setup Script
-- ============================================================================
-- This script creates all necessary Snowflake objects for the PCB defect
-- detection demo including database, warehouse, stages, compute pool, and tables
-- ============================================================================

-- Use SYSADMIN role for standard object creation
USE ROLE SYSADMIN;

-- ============================================================================
-- 1. Create Custom Role for Demo
-- ============================================================================
USE ROLE USERADMIN;

CREATE ROLE IF NOT EXISTS PCB_CV_ROLE
    COMMENT = 'Role for PCB Computer Vision defect detection demo';

-- Get current user and grant role
SET MY_USER = (SELECT CURRENT_USER());
GRANT ROLE PCB_CV_ROLE TO USER IDENTIFIER($MY_USER);

-- Grant role to SYSADMIN (for role hierarchy)
GRANT ROLE PCB_CV_ROLE TO ROLE SYSADMIN;

-- Switch to SYSADMIN to create objects
USE ROLE ACCOUNTADMIN;
CREATE OR REPLACE NETWORK RULE allow_all_rule MODE= 'EGRESS' TYPE = 'HOST_PORT' VALUE_LIST = ('0.0.0.0:443','0.0.0.0:80');
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION allow_all_integration 
ALLOWED_NETWORK_RULES = (allow_all_rule) 
ENABLED = true;

GRANT USAGE ON INTEGRATION allow_all_integration TO ROLE PCB_CV_ROLE;
USE ROLE SYSADMIN;

-- ============================================================================
-- 2. Create Database and Schema
-- ============================================================================
CREATE DATABASE IF NOT EXISTS PCB_CV
    COMMENT = 'Database for PCB Computer Vision defect detection demo';

USE DATABASE PCB_CV;
USE SCHEMA PUBLIC;

-- Grant ownership to demo role
GRANT OWNERSHIP ON DATABASE PCB_CV TO ROLE PCB_CV_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA PCB_CV.PUBLIC TO ROLE PCB_CV_ROLE COPY CURRENT GRANTS;

-- ============================================================================
-- 3. Create Warehouse for Data Processing
-- ============================================================================
CREATE WAREHOUSE IF NOT EXISTS PCB_CV_WH
    WAREHOUSE_SIZE = SMALL
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Warehouse for PCB CV dataset processing and queries';

-- Grant ownership to demo role
GRANT OWNERSHIP ON WAREHOUSE PCB_CV_WH TO ROLE PCB_CV_ROLE COPY CURRENT GRANTS;

USE WAREHOUSE PCB_CV_WH;

-- ============================================================================
-- 4. Create Internal Stage for Data Storage
-- ============================================================================
CREATE STAGE IF NOT EXISTS PCB_CV_DEEP_PCB_DATASET_STAGE
    COMMENT = 'Stage for storing PCB images and labels from DeepPCB dataset';

-- Grant ownership to demo role
GRANT OWNERSHIP ON STAGE PCB_CV_DEEP_PCB_DATASET_STAGE TO ROLE PCB_CV_ROLE COPY CURRENT GRANTS;

-- ============================================================================
-- 5. Create Compute Pool for GPU-based Model Training
-- ============================================================================
-- Note: GPU compute pools require specific Snowflake account configurations
-- 1 + 4 GPUs:Optimized for intensive GPU usage scenarios like Computer Vision or LLMs/VLMs.
-- https://docs.snowflake.com/en/sql-reference/sql/create-compute-pool#:~:text=GPU_NV_M
CREATE COMPUTE POOL IF NOT EXISTS PCB_CV_COMPUTEPOOL
    MIN_NODES = 1
    MAX_NODES = 4
    INSTANCE_FAMILY = GPU_NV_M
    AUTO_SUSPEND_SECS = 600 -- 10 minutes
    COMMENT = 'GPU compute pool for distributed PyTorch training';

-- Grant ownership to demo role
GRANT OWNERSHIP ON COMPUTE POOL PCB_CV_COMPUTEPOOL TO ROLE PCB_CV_ROLE COPY CURRENT GRANTS;

-- ============================================================================
-- 6. Create Tables for Labels and Training Data
-- ============================================================================

-- Table to store parsed label information
CREATE TABLE IF NOT EXISTS LABELS_TRAIN (
    filename VARCHAR(255),
    xmin FLOAT,
    ymin FLOAT,
    xmax FLOAT,
    ymax FLOAT,
    class INT
) COMMENT = 'Training labels with bounding box coordinates and defect class';

-- Table to store images with labels (merged data)
CREATE TABLE IF NOT EXISTS TRAIN_IMAGES_LABELS (
    Filename VARCHAR(255),
    image_data VARCHAR(16777216),  -- Max VARCHAR size for base64 encoded images
    class INT,
    xmin FLOAT,
    ymin FLOAT,
    xmax FLOAT,
    ymax FLOAT
) COMMENT = 'Combined training data with base64 encoded images and label information';

-- Table for training dataset (90% split)
CREATE TABLE IF NOT EXISTS TRAINING_DATA (
    Filename VARCHAR(255),
    image_data VARCHAR(16777216),
    class INT,
    xmin FLOAT,
    ymin FLOAT,
    xmax FLOAT,
    ymax FLOAT
) COMMENT = 'Training dataset (90% of total data)';

-- Table for test dataset (10% split)
CREATE TABLE IF NOT EXISTS TEST_DATA (
    Filename VARCHAR(255),
    image_data VARCHAR(16777216),
    class INT,
    xmin FLOAT,
    ymin FLOAT,
    xmax FLOAT,
    ymax FLOAT
) COMMENT = 'Test dataset (10% of total data)';

-- Grant ownership of all tables to demo role
GRANT OWNERSHIP ON ALL TABLES IN SCHEMA PCB_CV.PUBLIC TO ROLE PCB_CV_ROLE COPY CURRENT GRANTS;

-- ============================================================================
-- 7. Grant Additional Privileges
-- ============================================================================
-- Grant usage on warehouse to demo role for future operations
GRANT USAGE ON WAREHOUSE PCB_CV_WH TO ROLE PCB_CV_ROLE;
GRANT OPERATE ON WAREHOUSE PCB_CV_WH TO ROLE PCB_CV_ROLE;
GRANT MODIFY ON WAREHOUSE PCB_CV_WH TO ROLE PCB_CV_ROLE;

-- Grant usage on compute pool to demo role
GRANT USAGE ON COMPUTE POOL PCB_CV_COMPUTEPOOL TO ROLE PCB_CV_ROLE;
GRANT MONITOR ON COMPUTE POOL PCB_CV_COMPUTEPOOL TO ROLE PCB_CV_ROLE;

-- Grant database and schema privileges
GRANT USAGE ON DATABASE PCB_CV TO ROLE PCB_CV_ROLE;
GRANT USAGE ON SCHEMA PCB_CV.PUBLIC TO ROLE PCB_CV_ROLE;
GRANT CREATE TABLE ON SCHEMA PCB_CV.PUBLIC TO ROLE PCB_CV_ROLE;
GRANT CREATE STAGE ON SCHEMA PCB_CV.PUBLIC TO ROLE PCB_CV_ROLE;
GRANT CREATE STREAMLIT ON SCHEMA PCB_CV.PUBLIC TO ROLE PCB_CV_ROLE;

-- ============================================================================
-- 8. Display Setup Summary
-- ============================================================================
SELECT 'Setup completed successfully!' AS status;
SELECT 'Role: PCB_CV_ROLE' AS info
UNION ALL
SELECT 'Database: PCB_CV' AS info
UNION ALL
SELECT 'Warehouse: PCB_CV_WH' AS info
UNION ALL
SELECT 'Compute Pool: PCB_CV_COMPUTEPOOL' AS info
UNION ALL
SELECT 'Stage: PCB_CV_DEEP_PCB_DATASET_STAGE' AS info
UNION ALL
SELECT 'Tables: LABELS_TRAIN, train_images_labels, training_data, test_data' AS info;
