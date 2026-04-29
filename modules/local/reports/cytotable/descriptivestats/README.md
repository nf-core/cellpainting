# CytoTable Descriptive Statistics Module

This module generates comprehensive descriptive statistics and visualizations for CytoTable-generated parquet files.

## Description

The `CYTOTABLE_DESCRIPTIVESTATS` process runs a Papermill notebook that analyzes parquet files containing Cell Painting data and generates:

- Descriptive statistics for all numeric columns (count, mean, std, min, quartiles, max)
- Missing values analysis
- Feature categorization by compartment and measurement type
- Visualizations:
  - Cell, nuclear, and cytoplasm size distributions
  - DNA intensity distribution
  - Summary statistics table

The descriptive statistics are saved as a parquet file for efficient storage and downstream analysis.

## Usage

```nextflow
include { CYTOTABLE_DESCRIPTIVESTATS } from './modules/local/cytotable/descriptivestats/main'

workflow {
    parquet_files = Channel.fromPath('*.parquet')
        .map { file -> 
            def meta = [batch: 'batch1', plate: 'plate1', well: 'A01', site: '1']
            [meta, file]
        }
    
    CYTOTABLE_DESCRIPTIVESTATS(parquet_files)
}
```

## Inputs

- `meta`: Map containing sample metadata (batch, plate, well, site)
- `parquet_file`: Path to the parquet file to analyze

## Outputs

- `notebook`: Executed Jupyter notebook with visualizations (*.ipynb)
- `stats`: Descriptive statistics parquet file (*_descriptive_stats.parquet)
- `size_plot`: Cell size distribution plot PNG (*_size_distributions.png) - **optional**, only created if area shape columns are present
- `dna_plot`: DNA intensity distribution plot PNG (*_dna_intensity.png) - **optional**, only created if DNA intensity column is present
- `html`: HTML report (optional, controlled by `task.ext.convert_html`)
- `versions`: Software versions used (versions.yml)

## Parameters

The following parameters can be configured in `nextflow.config` using `task.ext`:

- `n_head_rows`: Number of rows to display in the head preview (default: 10)
- `convert_html`: Convert notebook to HTML (default: false)
- `args`: Additional arguments passed to papermill

## Output Statistics File

The descriptive statistics parquet file contains one row per numeric feature with columns:

- `feature`: Feature name
- `count`: Number of non-null values
- `mean`: Mean value
- `std`: Standard deviation
- `min`: Minimum value
- `25%`: First quartile
- `50%`: Median
- `75%`: Third quartile
- `max`: Maximum value

This can be loaded and analyzed with:

```python
import pandas as pd
stats_df = pd.read_parquet('sample_descriptive_stats.parquet')
```

## Visualizations

The notebook generates the following visualizations (also saved as high-resolution PNG files):

1. **Cell Size Distribution** (`*_size_distributions.png`): Histograms of cell, nuclear, and cytoplasm areas
2. **DNA Intensity Distribution** (`*_dna_intensity.png`): Histogram and box plot of DNA intensity

These image files are automatically generated and saved alongside the notebook when the required columns are present in the data. They are marked as optional outputs since their creation depends on the availability of specific columns in the parquet file.

## Requirements

See `environment.yml` for conda dependencies, including matplotlib and seaborn for visualizations.

## Authors

- @ybaeus
