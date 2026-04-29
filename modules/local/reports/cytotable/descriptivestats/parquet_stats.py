import marimo

__generated_with = "0.9.0"
app = marimo.App(width="medium")


@app.cell
def __():
    import pandas as pd
    import numpy as np
    import matplotlib.pyplot as plt
    import seaborn as sns
    from pathlib import Path
    import warnings
    import sys
    import argparse
    
    warnings.filterwarnings('ignore')
    sns.set_style('whitegrid')
    plt.rcParams['figure.figsize'] = (12, 6)
    return Path, argparse, np, pd, plt, sns, sys, warnings


@app.cell
def __(argparse, sys):
    # Parse command line arguments
    parser = argparse.ArgumentParser()
    parser.add_argument('--parquet-file', type=str,
                       default="../nf-runs/test-profile-outdir/cytotable/2021_04_26_Batch1_BR00117035_A01_1.parquet")
    parser.add_argument('--n-head-rows', type=int, default=10)
    parser.add_argument('--output-prefix', type=str, default="sample")
    
    # Handle both script execution and interactive mode
    if len(sys.argv) > 1:
        args = parser.parse_args()
    else:
        args = parser.parse_args([])
    
    parquet_file = args.parquet_file
    n_head_rows = args.n_head_rows
    output_prefix = args.output_prefix
    return args, n_head_rows, output_prefix, parser, parquet_file


@app.cell
def __(parquet_file, pd):
    # Load parquet file
    print(f"Loading parquet file: {parquet_file}")
    df = pd.read_parquet(parquet_file)
    print(f"✓ Successfully loaded parquet file")
    return df,


@app.cell
def __(df, n_head_rows):
    print("=" * 80)
    print(f"FIRST {n_head_rows} ROWS (showing first 20 columns)")
    print("=" * 80)
    df.head(n_head_rows).iloc[:, :20]
    return


@app.cell
def __(df, np, parquet_file):
    # Get numeric columns only
    numeric_cols = df.select_dtypes(include=[np.number]).columns
    print(f"Number of numeric columns: {len(numeric_cols)}")
    print()
    
    # Calculate descriptive stats for ALL numeric columns
    descriptive_stats = df[numeric_cols].describe().T
    descriptive_stats.reset_index(inplace=True)
    descriptive_stats.rename(columns={'index': 'feature'}, inplace=True)
    
    # Save to parquet file
    stats_filename = parquet_file.replace('.parquet', '_descriptive_stats.parquet')
    descriptive_stats.to_parquet(stats_filename, index=False)
    print(f"✓ Saved descriptive statistics to: {stats_filename}")
    print()
    
    # Show descriptive stats for first 50 numeric columns
    print("=" * 80)
    print("DESCRIPTIVE STATISTICS (first 50 numeric columns)")
    print("=" * 80)
    descriptive_stats.head(50).set_index('feature')
    return descriptive_stats, numeric_cols, stats_filename


@app.cell
def __(df):
    # Check for missing values
    missing_counts = df.isnull().sum()
    missing_cols = missing_counts[missing_counts > 0].sort_values(ascending=False)
    
    print("=" * 80)
    print("MISSING VALUES ANALYSIS")
    print("=" * 80)
    if len(missing_cols) > 0:
        print(f"Columns with missing values: {len(missing_cols)}")
        print(f"\nTop 20 columns with most missing values:")
        print()
        for _col, _count in missing_cols.head(20).items():
            pct = (_count / len(df)) * 100
            print(f"{_col:60s}: {_count:5d} ({pct:5.1f}%)")
    else:
        print("✓ No missing values found in dataset")
    print()
    return missing_cols, missing_counts


@app.cell
def __(df):
    # Categorize features by measurement type
    feature_categories = {}
    compartments = ['Cells', 'Cytoplasm', 'Nuclei']
    measurement_types = ['AreaShape', 'Intensity', 'Texture', 'Granularity', 
                         'Correlation', 'Neighbors', 'RadialDistribution', 'Skeleton']
    
    for compartment in compartments:
        feature_categories[compartment] = {}
        for meas_type in measurement_types:
            pattern = f"{compartment}_{meas_type}"
            matching_cols = [_col for _col in df.columns if pattern in _col]
            if matching_cols:
                feature_categories[compartment][meas_type] = len(matching_cols)
    
    print("=" * 80)
    print("FEATURE CATEGORIES BY COMPARTMENT")
    print("=" * 80)
    for _compartment, measurements in feature_categories.items():
        if measurements:
            print(f"\n{_compartment}:")
            for _meas_type, _count in sorted(measurements.items(), key=lambda x: x[1], reverse=True):
                print(f"  {_meas_type:25s}: {_count:5d} features")
    return compartment, compartments, feature_categories, matching_cols, meas_type, measurement_types, measurements, pattern


@app.cell
def __(df, output_prefix, plt):
    # Check if we have the required columns for size distribution
    has_size_cols = (
        'Cells_AreaShape_Area' in df.columns or 
        'Nuclei_AreaShape_Area' in df.columns or 
        'Cytoplasm_AreaShape_Area' in df.columns
    )
    
    if has_size_cols:
        _fig, _axes = plt.subplots(1, 3, figsize=(15, 4))
    
        # Cell area
        if 'Cells_AreaShape_Area' in df.columns:
            _axes[0].hist(df['Cells_AreaShape_Area'], bins=50, edgecolor='black', alpha=0.7)
            _axes[0].set_xlabel('Cell Area (pixels)')
            _axes[0].set_ylabel('Frequency')
            _axes[0].set_title('Cell Size Distribution')
            _axes[0].axvline(df['Cells_AreaShape_Area'].median(), color='red', 
                           linestyle='--', label=f'Median: {df["Cells_AreaShape_Area"].median():.0f}')
            _axes[0].legend()
    
        # Nuclear area
        if 'Nuclei_AreaShape_Area' in df.columns:
            _axes[1].hist(df['Nuclei_AreaShape_Area'], bins=50, edgecolor='black', alpha=0.7, color='green')
            _axes[1].set_xlabel('Nuclear Area (pixels)')
            _axes[1].set_ylabel('Frequency')
            _axes[1].set_title('Nuclear Size Distribution')
            _axes[1].axvline(df['Nuclei_AreaShape_Area'].median(), color='red', 
                           linestyle='--', label=f'Median: {df["Nuclei_AreaShape_Area"].median():.0f}')
            _axes[1].legend()
    
        # Cytoplasm area
        if 'Cytoplasm_AreaShape_Area' in df.columns:
            _axes[2].hist(df['Cytoplasm_AreaShape_Area'], bins=50, edgecolor='black', alpha=0.7, color='orange')
            _axes[2].set_xlabel('Cytoplasm Area (pixels)')
            _axes[2].set_ylabel('Frequency')
            _axes[2].set_title('Cytoplasm Size Distribution')
            _axes[2].axvline(df['Cytoplasm_AreaShape_Area'].median(), color='red', 
                           linestyle='--', label=f'Median: {df["Cytoplasm_AreaShape_Area"].median():.0f}')
            _axes[2].legend()
    
        plt.tight_layout()
        
        # Save figure to file
        size_dist_filename = f"{output_prefix}_size_distributions.png"
        plt.savefig(size_dist_filename, dpi=300, bbox_inches='tight')
        print(f"✓ Saved cell size distributions to: {size_dist_filename}")
        
        plt.show()
    else:
        print("Note: No area shape columns found for size distribution plots")
    return has_size_cols, size_dist_filename


@app.cell
def __(df, output_prefix, plt):
    dna_intensity_col = 'Nuclei_Intensity_MeanIntensity_DNA'
    if dna_intensity_col in df.columns:
        _fig, _axes = plt.subplots(1, 2, figsize=(12, 4))
        
        # Histogram
        _axes[0].hist(df[dna_intensity_col], bins=50, edgecolor='black', alpha=0.7, color='blue')
        _axes[0].set_xlabel('Mean DNA Intensity')
        _axes[0].set_ylabel('Frequency')
        _axes[0].set_title('DNA Intensity Distribution')
        _axes[0].axvline(df[dna_intensity_col].median(), color='red', 
                       linestyle='--', label=f'Median: {df[dna_intensity_col].median():.3f}')
        _axes[0].legend()
        
        # Box plot
        _axes[1].boxplot(df[dna_intensity_col].dropna())
        _axes[1].set_ylabel('Mean DNA Intensity')
        _axes[1].set_title('DNA Intensity Box Plot')
        _axes[1].set_xticklabels(['DNA'])
        
        plt.tight_layout()
        
        # Save figure to file
        dna_dist_filename = f"{output_prefix}_dna_intensity.png"
        plt.savefig(dna_dist_filename, dpi=300, bbox_inches='tight')
        print(f"✓ Saved DNA intensity distribution to: {dna_dist_filename}")
        
        plt.show()
    else:
        print(f"Note: Column {dna_intensity_col} not found")
    return dna_dist_filename, dna_intensity_col


@app.cell
def __(df, dna_intensity_col, pd):
    # Create summary table of key metrics
    summary_data = {
        'Metric': [],
        'Value': []
    }
    
    summary_data['Metric'].append('Total Cells')
    summary_data['Value'].append(f"{len(df):,}")
    
    if 'Cells_AreaShape_Area' in df.columns:
        summary_data['Metric'].append('Mean Cell Area')
        summary_data['Value'].append(f"{df['Cells_AreaShape_Area'].mean():.2f}")
        summary_data['Metric'].append('Median Cell Area')
        summary_data['Value'].append(f"{df['Cells_AreaShape_Area'].median():.2f}")
    
    if 'Nuclei_AreaShape_Area' in df.columns:
        summary_data['Metric'].append('Mean Nuclear Area')
        summary_data['Value'].append(f"{df['Nuclei_AreaShape_Area'].mean():.2f}")
    
    if dna_intensity_col in df.columns:
        summary_data['Metric'].append('Mean DNA Intensity')
        summary_data['Value'].append(f"{df[dna_intensity_col].mean():.4f}")
    
    summary_df = pd.DataFrame(summary_data)
    
    print("=" * 80)
    print("SUMMARY STATISTICS")
    print("=" * 80)
    summary_df
    return summary_data, summary_df


if __name__ == "__main__":
    app.run()
