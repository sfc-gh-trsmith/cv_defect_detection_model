#!/usr/bin/env python3
"""
PCB Defect Detection - Data Upload Script

This script processes PCB dataset files locally and uploads them directly to Snowflake tables.
It reads images and labels from the PCBData directory, processes them in memory,
and writes them to Snowflake using bulk operations.
"""

import argparse
import os
import sys
import base64
import pandas as pd
from sklearn.model_selection import train_test_split

# Snowflake imports
try:
    from snowflake.snowpark.session import Session
except ImportError:
    print("✗ Error: snowflake-snowpark-python is not installed.")
    print("  Install it using: pip install snowflake-snowpark-python")
    sys.exit(1)

# Snowflake configuration
DATABASE = 'PCB_CV'
SCHEMA = 'PUBLIC'
ROLE = 'PCB_CV_ROLE'
WAREHOUSE = 'PCB_CV_WH'


def parse_arguments():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description='Upload PCB dataset to Snowflake',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s -c demo --data-dir data/PCBData
  %(prog)s --connection myconn --data-dir /path/to/PCBData
        """
    )
    
    parser.add_argument('-c', '--connection', default='demo',
                        help='Named connection from ~/.snowflake/connections.toml (default: demo)')
    parser.add_argument('--data-dir', default='data/PCBData',
                        help='Path to PCBData directory (default: data/PCBData)')
    
    return parser.parse_args()


def create_session(connection_name):
    """
    Create and return a Snowflake session using named connection.
    
    Args:
        connection_name: Name of the connection in ~/.snowflake/connections.toml
    
    Returns:
        Snowflake session configured with database, schema, and role
    """
    try:
        print(f"Connecting to Snowflake using connection: {connection_name}")
        session = Session.builder.config("connection_name", connection_name).create()
        
        # Set database, schema, and role
        session.use_database(DATABASE)
        session.use_schema(SCHEMA)
        session.use_role(ROLE)
        
        print(f"✓ Connected to Snowflake")
        print(f"  Database: {DATABASE}")
        print(f"  Schema: {SCHEMA}")
        print(f"  Role: {ROLE}")
        print(f"  Warehouse: {WAREHOUSE}")
        
        return session
    except Exception as e:
        print(f"✗ Error connecting to Snowflake: {e}")
        print("\nTroubleshooting:")
        print("  1. Ensure ~/.snowflake/connections.toml exists and has the connection configured")
        print(f"  2. Check that connection '{connection_name}' is defined in the config")
        print("  3. Verify account, user, and authentication settings are correct")
        print("  4. If using private key auth, ensure the key file path is correct")
        sys.exit(1)


def find_and_parse_labels(data_dir):
    """
    Walk through PCBData directory, find label files, and parse them into a DataFrame.
    
    Args:
        data_dir: Path to PCBData directory
    
    Returns:
        pandas DataFrame with columns: filename, xmin, ymin, xmax, ymax, class
    """
    print("\n" + "="*80)
    print("Step 1: Parsing Labels from PCBData")
    print("="*80)
    
    if not os.path.exists(data_dir):
        print(f"✗ Error: Data directory not found: {data_dir}")
        sys.exit(1)
    
    labels = []
    file_count = 0
    
    # Walk through the PCBData directory structure
    # Structure: PCBData/group44000/44000/*.jpg and group44000/44000_not/*.txt
    for group_folder in sorted(os.listdir(data_dir)):
        group_path = os.path.join(data_dir, group_folder)
        
        if not os.path.isdir(group_path):
            continue
        
        for sub_folder in sorted(os.listdir(group_path)):
            # Skip the "_not" folders in this pass
            if sub_folder.endswith("_not"):
                continue
            
            sub_folder_path = os.path.join(group_path, sub_folder)
            
            if not os.path.isdir(sub_folder_path):
                continue
            
            # Find corresponding *_not folder for labels
            folder_not = os.path.join(group_path, sub_folder + "_not")
            
            if not os.path.exists(folder_not):
                continue
            
            # Process files in the subfolder
            for file_name in sorted(os.listdir(sub_folder_path)):
                if file_name.endswith("_test.jpg"):
                    # Get the base filename without _test.jpg
                    filename_base = file_name.replace("_test.jpg", "")
                    
                    # Find corresponding .txt label file
                    txt_name = filename_base + ".txt"
                    txt_path = os.path.join(folder_not, txt_name)
                    
                    if os.path.exists(txt_path):
                        # Parse the label file
                        with open(txt_path, 'r') as f:
                            for line in f:
                                parts = line.strip().split()
                                if len(parts) == 5:
                                    xmin, ymin, xmax, ymax, class_id = parts
                                    labels.append({
                                        'filename': filename_base,
                                        'xmin': float(xmin),
                                        'ymin': float(ymin),
                                        'xmax': float(xmax),
                                        'ymax': float(ymax),
                                        'class': int(class_id)
                                    })
                        
                        file_count += 1
                        if file_count % 10 == 0:
                            print(f"  Processed {file_count} label files...", end='\r')
    
    print(f"\n✓ Parsed {file_count} label files with {len(labels)} bounding boxes")
    
    # Create DataFrame
    labels_df = pd.DataFrame(labels)
    return labels_df


def read_and_encode_images(data_dir, label_filenames):
    """
    Read image files and encode them as base64 strings.
    
    Args:
        data_dir: Path to PCBData directory
        label_filenames: Set of filenames (without extension) that have labels
    
    Returns:
        pandas DataFrame with columns: Filename, image_data
    """
    print("\n" + "="*80)
    print("Step 2: Reading and Encoding Images")
    print("="*80)
    
    images = []
    processed_count = 0
    
    # Walk through directory structure to find image files
    for group_folder in sorted(os.listdir(data_dir)):
        group_path = os.path.join(data_dir, group_folder)
        
        if not os.path.isdir(group_path):
            continue
        
        for sub_folder in sorted(os.listdir(group_path)):
            # Skip the "_not" folders
            if sub_folder.endswith("_not"):
                continue
            
            sub_folder_path = os.path.join(group_path, sub_folder)
            
            if not os.path.isdir(sub_folder_path):
                continue
            
            # Process image files
            for file_name in sorted(os.listdir(sub_folder_path)):
                if file_name.endswith("_test.jpg"):
                    filename_base = file_name.replace("_test.jpg", "")
                    
                    # Only process images that have corresponding labels
                    if filename_base in label_filenames:
                        jpg_path = os.path.join(sub_folder_path, file_name)
                        
                        try:
                            # Read and encode image
                            with open(jpg_path, 'rb') as f:
                                base64_string = base64.b64encode(f.read()).decode('utf-8')
                                images.append({
                                    'Filename': filename_base + "_test",
                                    'image_data': base64_string
                                })
                            
                            processed_count += 1
                            if processed_count % 10 == 0:
                                print(f"  Processed {processed_count} images...", end='\r')
                        except Exception as e:
                            print(f"\n✗ Error processing {file_name}: {e}")
    
    print(f"\n✓ Encoded {processed_count} images")
    
    # Create DataFrame
    images_df = pd.DataFrame(images)
    return images_df


def create_tables(session, labels_df, images_df):
    """
    Create Snowflake tables from the processed data.
    
    This function:
    1. Writes LABELS_TRAIN table
    2. Merges labels with images
    3. Writes train_images_labels table
    4. Splits data 90/10 and writes training_data and test_data tables
    
    Args:
        session: Snowflake session
        labels_df: DataFrame with label information
        images_df: DataFrame with image data
    """
    print("\n" + "="*80)
    print("Step 3: Creating Snowflake Tables")
    print("="*80)
    
    # 1. Write LABELS_TRAIN table
    print(f"  Writing LABELS_TRAIN table ({len(labels_df)} records)...")
    session.write_pandas(
        labels_df,
        "LABELS_TRAIN",
        auto_create_table=True,
        overwrite=True,
        quote_identifiers=False
    )
    print(f"✓ Created LABELS_TRAIN table")
    
    # 2. Merge labels with images
    print("  Merging labels with images...")
    # Prepare labels DataFrame for merging
    labels_for_merge = labels_df.copy()
    labels_for_merge['Filename'] = labels_for_merge['filename'] + "_test"
    labels_for_merge = labels_for_merge.drop(columns=['filename'])
    
    # Merge on Filename
    merged_df = pd.merge(labels_for_merge, images_df, how='inner', on='Filename')
    
    # Remove the "_test" suffix from Filename for consistency
    merged_df['Filename'] = merged_df['Filename'].str.replace('_test', '', regex=False)
    
    print(f"✓ Merged {len(merged_df)} records")
    
    # 3. Write train_images_labels table
    print(f"  Writing train_images_labels table ({len(merged_df)} records)...")
    session.write_pandas(
        merged_df,
        "train_images_labels",
        auto_create_table=True,
        overwrite=True,
        quote_identifiers=False
    )
    print(f"✓ Created train_images_labels table")
    
    # 4. Split dataset 90/10 and create training_data and test_data tables
    print("  Splitting dataset: 90% train, 10% test...")
    train_df, test_df = train_test_split(merged_df, test_size=0.1, random_state=42)
    
    print(f"  Writing training_data table ({len(train_df)} records)...")
    session.write_pandas(
        train_df,
        "training_data",
        auto_create_table=True,
        overwrite=True,
        quote_identifiers=False
    )
    print(f"✓ Created training_data table")
    
    print(f"  Writing test_data table ({len(test_df)} records)...")
    session.write_pandas(
        test_df,
        "test_data",
        auto_create_table=True,
        overwrite=True,
        quote_identifiers=False
    )
    print(f"✓ Created test_data table")


def main():
    """Main execution function."""
    args = parse_arguments()
    
    print("="*80)
    print("PCB Defect Detection - Data Upload")
    print("="*80)
    print(f"Data directory: {args.data_dir}")
    print(f"Connection: {args.connection}")
    print()
    
    # Create Snowflake session
    session = create_session(args.connection)
    
    try:
        # Step 1: Parse labels from PCBData
        labels_df = find_and_parse_labels(args.data_dir)
        
        # Step 2: Read and encode images
        label_filenames = set(labels_df['filename'].unique())
        images_df = read_and_encode_images(args.data_dir, label_filenames)
        
        # Step 3: Create Snowflake tables
        create_tables(session, labels_df, images_df)
        
        print("\n" + "="*80)
        print("✓ Data Upload Complete!")
        print("="*80)
        print("\nTables created:")
        print("  - LABELS_TRAIN: Raw label data")
        print("  - train_images_labels: Merged images and labels")
        print("  - training_data: 90% of data for training")
        print("  - test_data: 10% of data for testing")
        print()
        
    except Exception as e:
        print(f"\n✗ Error during data upload: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        session.close()


if __name__ == '__main__':
    main()
