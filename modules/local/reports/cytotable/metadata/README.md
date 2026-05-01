# CytoTable Metadata Module

This module extracts metadata information from CytoTable-generated parquet files and exports it to JSON format for downstream processing.

## Description

The `CYTOTABLE_METADATA` process runs a Papermill notebook that analyzes parquet files containing Cell Painting data and extracts key metadata including:

- File information (name, size, path)
- DataFrame overview (number of rows, columns, memory usage)
- Column structure by compartment/type (Cells, Cytoplasm, Nuclei, Metadata, etc.)
- List of all metadata columns
- Data type summary

All metadata is exported to a JSON file for easy parsing and downstream use.

## Usage

```nextflow
include { CYTOTABLE_METADATA } from './modules/local/cytotable/metadata/main'

workflow {
    parquet_files = Channel.fromPath('*.parquet')
        .map { file -> 
            def meta = [batch: 'batch1', plate: 'plate1', well: 'A01', site: '1']
            [meta, file]
        }
    
    CYTOTABLE_METADATA(parquet_files)
}
```

## Inputs

- `meta`: Map containing sample metadata (batch, plate, well, site)
- `parquet_file`: Path to the parquet file to analyze

## Outputs

- `notebook`: Executed Jupyter notebook (*.ipynb)
- `json`: Metadata JSON file (*_metadata.json)
- `html`: HTML report (optional, controlled by `task.ext.convert_html`)
- `versions`: Software versions used (versions.yml)

## Parameters

The following parameters can be configured in `nextflow.config` using `task.ext`:

- `convert_html`: Convert notebook to HTML (default: false)
- `args`: Additional arguments passed to papermill

## Output JSON Structure

The metadata JSON file contains the following structure:

```json
{
  "file_info": {
    "filename": "sample.parquet",
    "file_size_mb": 12.34,
    "file_path": "/path/to/sample.parquet"
  },
  "dataframe_overview": {
    "n_rows": 1000,
    "n_columns": 500,
    "total_data_points": 500000,
    "memory_usage_mb": 10.5
  },
  "column_structure": {
    "Cells": {
      "count": 150,
      "sample_columns": ["Cells_AreaShape_Area", "Cells_AreaShape_Perimeter", ...]
    },
    ...
  },
  "metadata_columns": {
    "count": 10,
    "columns": ["Metadata_Plate", "Metadata_Well", ...]
  },
  "data_types": {
    "float64": 450,
    "int64": 40,
    "object": 10
  }
}
```

## Requirements

See `environment.yml` for conda dependencies.

## Authors

- @ybaeus
