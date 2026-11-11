import marimo

__generated_with = "0.9.0"
app = marimo.App(width="medium")


@app.cell
def _():
    import argparse
    import json
    import sys
    from pathlib import Path

    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np
    import pandas as pd
    import seaborn as sns

    return Path, argparse, json, np, plt, pd, sns, sys


@app.cell
def _(Path, argparse, sys):
    # Command-line interface. All paths are required — there are no
    # developer-machine defaults (review feedback on #49).
    parser = argparse.ArgumentParser(description="CytoTable parquet reports")
    parser.add_argument(
        "--parquet-file",
        type=Path,
        required=True,
        help="Path to the CytoTable profiles parquet to report on",
    )
    parser.add_argument(
        "--output-prefix",
        type=str,
        required=True,
        help="Prefix for all output file names",
    )
    parser.add_argument(
        "--n-head-rows",
        type=int,
        default=10,
        help="Number of head rows to display",
    )

    if len(sys.argv) > 1:
        args = parser.parse_args()
    else:
        # interactive marimo sessions get required-argument errors instead of
        # silently falling back to developer defaults
        args = parser.parse_args(["--parquet-file", "", "--output-prefix", ""])

    parquet_file = args.parquet_file
    output_prefix = args.output_prefix
    n_head_rows = args.n_head_rows
    return args, n_head_rows, output_prefix, parquet_file, parser


@app.cell
def _(parquet_file, pd):
    print(f"Loading parquet file: {parquet_file}")
    df = pd.read_parquet(parquet_file)
    print(f"Loaded table with {df.shape[0]:,} rows and {df.shape[1]:,} columns")
    return (df,)


@app.cell
def _(df, n_head_rows):
    print("=" * 80)
    print(f"FIRST {n_head_rows} ROWS (showing first 20 columns)")
    print("=" * 80)
    df.head(n_head_rows).iloc[:, :20]
    return


@app.cell
def _(df, json, output_prefix, parquet_file):
    # ---- metadata report (from #49 parquet_metadata.py) ----
    metadata_cols = [c for c in df.columns if c.startswith("Metadata_")]

    column_prefixes = {}
    for _c in df.columns:
        prefix = _c.split("_", 1)[0]
        column_prefixes.setdefault(prefix, []).append(_c)

    dtype_counts = df.dtypes.astype(str).value_counts()

    metadata = {
        "file_info": {
            "filename": parquet_file.name,
        },
        "dataframe_overview": {
            "n_rows": int(df.shape[0]),
            "n_columns": int(df.shape[1]),
            "total_data_points": int(df.shape[0] * df.shape[1]),
        },
        "column_structure": {
            prefix: {
                "count": len(cols),
                "sample_columns": cols[:3],
            }
            for prefix, cols in sorted(column_prefixes.items())
        },
        "metadata_columns": {
            "count": len(metadata_cols),
            "columns": metadata_cols,
        },
        "data_types": {str(dtype): int(count) for dtype, count in dtype_counts.items()},
    }

    metadata_json_path = f"{output_prefix}_metadata.json"
    with open(metadata_json_path, "w") as f:
        json.dump(metadata, f, indent=2)
        f.write("\n")
    print(f"Saved metadata JSON to: {metadata_json_path}")
    return (metadata,)


@app.cell
def _(df, np, output_prefix):
    # ---- descriptive statistics report (from #49 parquet_stats.py) ----
    numeric_cols = df.select_dtypes(include=[np.number]).columns
    print(f"Number of numeric columns: {len(numeric_cols)}")

    descriptive_stats = df[numeric_cols].describe().T
    descriptive_stats = descriptive_stats.reset_index().rename(
        columns={"index": "feature"}
    )

    # Output name is derived from the requested output prefix, not from the
    # input parquet name (review feedback on #49).
    stats_path = f"{output_prefix}_descriptive_stats.parquet"
    descriptive_stats.to_parquet(stats_path, index=False)
    print(f"Saved descriptive statistics to: {stats_path}")

    missing_counts = df.isnull().sum()
    missing_cols = missing_counts[missing_counts > 0].sort_values(ascending=False)
    if len(missing_cols) > 0:
        print(f"Columns with missing values: {len(missing_cols)}")
        for _col, _count in missing_cols.head(20).items():
            print(f"  {_col}: {_count} ({(_count / len(df)) * 100:.1f}%)")
    else:
        print("No missing values found in dataset")
    return (descriptive_stats,)


@app.cell
def _(df, output_prefix, plt, sns):
    # ---- cell size distribution plots (from #49 parquet_stats.py) ----
    # warnings are scoped to the plotting calls only (review feedback).
    import warnings as plot_warnings

    compartments = ["Cells", "Nuclei", "Cytoplasm"]
    areas = [f"{c}_AreaShape_Area" for c in compartments]
    present = [a for a in areas if a in df.columns]

    if present:
        with plot_warnings.catch_warnings():
            plot_warnings.simplefilter("ignore")
            size_fig, size_axes = plt.subplots(1, len(present), figsize=(5 * len(present), 4))
            if len(present) == 1:
                size_axes = [size_axes]
            for ax, area_col, color in zip(size_axes, present, ["steelblue", "seagreen", "darkorange"]):
                sns.histplot(df[area_col], bins=50, ax=ax, color=color)
                ax.set_xlabel("Area (pixels)")
                ax.set_title(f"{area_col.split('_')[0]} Area Distribution")
                ax.axvline(
                    df[area_col].median(),
                    color="red",
                    linestyle="--",
                    label=f"Median: {df[area_col].median():.0f}",
                )
                ax.legend()
            plt.tight_layout()
            size_plot_path = f"{output_prefix}_size_distributions.png"
            plt.savefig(size_plot_path, dpi=300, bbox_inches="tight")
            plt.close(size_fig)
            print(f"Saved size distributions to: {size_plot_path}")
    else:
        print("No AreaShape_Area columns found; skipping size distribution plots")
    return


@app.cell
def _(df, output_prefix, plt, sns):
    # ---- DNA intensity plot (from #49 parquet_stats.py) ----
    import warnings as dna_warnings

    dna_intensity_col = "Nuclei_Intensity_MeanIntensity_DNA"
    if dna_intensity_col in df.columns:
        with dna_warnings.catch_warnings():
            dna_warnings.simplefilter("ignore")
            dna_fig, dna_axes = plt.subplots(1, 2, figsize=(12, 4))
            sns.histplot(df[dna_intensity_col], bins=50, ax=dna_axes[0], color="steelblue")
            dna_axes[0].set_xlabel("Mean DNA Intensity")
            dna_axes[0].set_title("DNA Intensity Distribution")
            dna_axes[0].axvline(
                df[dna_intensity_col].median(),
                color="red",
                linestyle="--",
                label=f"Median: {df[dna_intensity_col].median():.3f}",
            )
            dna_axes[0].legend()
            sns.boxplot(y=df[dna_intensity_col].dropna(), ax=dna_axes[1], color="steelblue")
            dna_axes[1].set_ylabel("Mean DNA Intensity")
            dna_axes[1].set_title("DNA Intensity Box Plot")
            plt.tight_layout()
            dna_plot_path = f"{output_prefix}_dna_intensity.png"
            plt.savefig(dna_plot_path, dpi=300, bbox_inches="tight")
            plt.close(dna_fig)
            print(f"Saved DNA intensity distribution to: {dna_plot_path}")
    else:
        print(f"Column {dna_intensity_col} not found; skipping DNA intensity plot")
    return


@app.cell
def _(df, pd):
    # ---- summary metrics table (from #49 parquet_stats.py) ----
    summary_data = {"Metric": [], "Value": []}
    summary_data["Metric"].append("Total Cells")
    summary_data["Value"].append(f"{len(df):,}")
    for col, label in [
        ("Cells_AreaShape_Area", "Mean Cell Area"),
        ("Nuclei_AreaShape_Area", "Mean Nuclear Area"),
    ]:
        if col in df.columns:
            summary_data["Metric"].append(label)
            summary_data["Value"].append(f"{df[col].mean():.2f}")
    if "Nuclei_Intensity_MeanIntensity_DNA" in df.columns:
        summary_data["Metric"].append("Mean DNA Intensity")
        summary_data["Value"].append(
            f"{df['Nuclei_Intensity_MeanIntensity_DNA'].mean():.4f}"
        )
    summary_df = pd.DataFrame(summary_data)
    print("=" * 80)
    print("SUMMARY STATISTICS")
    print("=" * 80)
    print(summary_df.to_string(index=False))
    return (summary_df,)


if __name__ == "__main__":
    app.run()
