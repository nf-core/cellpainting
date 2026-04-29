import marimo

__generated_with = "0.9.0"
app = marimo.App(width="medium")


@app.cell
def __():
    import pandas as pd
    import json
    from pathlib import Path
    import warnings
    import sys
    import argparse
    
    warnings.filterwarnings('ignore')
    return Path, argparse, json, pd, sys, warnings


@app.cell
def __(argparse, sys):
    # Parse command line arguments
    parser = argparse.ArgumentParser()
    parser.add_argument('--parquet-file', type=str, 
                       default="../nf-runs/test-profile-outdir/cytotable/2021_04_26_Batch1_BR00117035_A01_1.parquet")
    parser.add_argument('--output-json', type=str, default="metadata.json")
    
    # Handle both script execution and interactive mode
    if len(sys.argv) > 1:
        args = parser.parse_args()
    else:
        args = parser.parse_args([])
    
    parquet_file = args.parquet_file
    output_json = args.output_json
    return args, output_json, parser, parquet_file


@app.cell
def __(Path, parquet_file):
    # Basic file info
    file_path = Path(parquet_file)
    file_size_mb = file_path.stat().st_size / (1024 * 1024)
    
    print("=" * 80)
    print("FILE INFORMATION")
    print("=" * 80)
    print(f"File name: {file_path.name}")
    print(f"File size: {file_size_mb:.2f} MB")
    print(f"Full path: {file_path.absolute()}")
    print()
    return file_path, file_size_mb


@app.cell
def __(parquet_file, pd):
    # Load parquet file
    print(f"Loading parquet file: {parquet_file}")
    df = pd.read_parquet(parquet_file)
    print(f"✓ Successfully loaded parquet file")
    return df,


@app.cell
def __(df):
    print("=" * 80)
    print("DATAFRAME OVERVIEW")
    print("=" * 80)
    print(f"Number of rows (cells): {df.shape[0]:,}")
    print(f"Number of columns (features): {df.shape[1]:,}")
    print(f"Total data points: {df.shape[0] * df.shape[1]:,}")
    print()
    return


@app.cell
def __(df):
    # Analyze column structure by prefix
    column_prefixes = {}
    for _c in df.columns:
        if '_' in _c:
            prefix = _c.split('_')[0]
            if prefix not in column_prefixes:
                column_prefixes[prefix] = []
            column_prefixes[prefix].append(_c)
    
    print("=" * 80)
    print("COLUMN STRUCTURE BY COMPARTMENT/TYPE")
    print("=" * 80)
    for prefix in sorted(column_prefixes.keys()):
        _count = len(column_prefixes[prefix])
        print(f"{prefix:20s}: {_count:5d} columns")
    print()
    
    # Show sample columns for each prefix
    print("Sample columns for each compartment:")
    print("-" * 80)
    for prefix in sorted(column_prefixes.keys()):
        sample_cols = column_prefixes[prefix][:3]
        print(f"\n{prefix}:")
        for _col in sample_cols:
            print(f"  - {_col}")
    return column_prefixes,


@app.cell
def __(df):
    # Show all metadata columns
    metadata_cols = [_c for _c in df.columns if _c.startswith('Metadata_')]
    
    print("=" * 80)
    print(f"METADATA COLUMNS ({len(metadata_cols)} total)")
    print("=" * 80)
    for _col in metadata_cols:
        print(f"  - {_col}")
    print()
    return metadata_cols,


@app.cell
def __(df):
    # Data type summary
    dtype_counts = df.dtypes.value_counts()
    
    print("=" * 80)
    print("DATA TYPES SUMMARY")
    print("=" * 80)
    for dtype, _count in dtype_counts.items():
        print(f"{str(dtype):20s}: {_count:5d} columns")
    print()
    return dtype_counts,


@app.cell
def __(
    column_prefixes,
    df,
    dtype_counts,
    file_path,
    file_size_mb,
    json,
    metadata_cols,
    output_json,
):
    # Compile metadata dictionary
    metadata = {
        "file_info": {
            "filename": file_path.name,
        },
        "dataframe_overview": {
            "n_rows": int(df.shape[0]),
            "n_columns": int(df.shape[1]),
            "total_data_points": int(df.shape[0] * df.shape[1])
        },
        "column_structure": {
            prefix: {
                "count": len(cols),
                "sample_columns": cols[:3]
            }
            for prefix, cols in sorted(column_prefixes.items())
        },
        "metadata_columns": {
            "count": len(metadata_cols),
            "columns": metadata_cols
        },
        "data_types": {
            str(dtype): int(_count)
            for dtype, _count in dtype_counts.items()
        }
    }
    
    # Save to JSON file
    with open(output_json, 'w') as f:
        json.dump(metadata, f, indent=2)
    
    print("=" * 80)
    print("METADATA JSON SAVED")
    print("=" * 80)
    print(f"✓ Metadata saved to: {output_json}")
    print(f"✓ Total metadata entries: {len(metadata)}")
    print()
    return metadata,


@app.cell
def __(df):
    print("=" * 80)
    print(f"COMPLETE COLUMN LIST ({len(df.columns)} columns)")
    print("=" * 80)
    for i, _col in enumerate(df.columns, 1):
        print(f"{i:4d}. {_col}")
    return


if __name__ == "__main__":
    app.run()
