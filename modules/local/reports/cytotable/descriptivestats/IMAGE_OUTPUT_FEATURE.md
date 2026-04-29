# Image Output Feature Summary

## Overview

Added support for saving visualization plots as standalone PNG files in the `CYTOTABLE_DESCRIPTIVESTATS` module.

## Changes Made

### 1. Notebook Updates (`parquet_stats.ipynb`)

#### Added Parameter
- `output_prefix`: Parameter to control the naming of output image files (passed from module)

#### Modified Cell Size Distribution Plot (Cell 16)
- Added conditional check to verify required columns exist
- Added `plt.savefig()` to save plot as PNG file: `{output_prefix}_size_distributions.png`
- Resolution: 300 DPI with tight bounding box
- Print confirmation message when file is saved

#### Modified DNA Intensity Distribution Plot (Cell 18)
- Added `plt.savefig()` to save plot as PNG file: `{output_prefix}_dna_intensity.png`
- Resolution: 300 DPI with tight bounding box
- Print confirmation message when file is saved

### 2. Module Updates (`main.nf`)

#### Outputs
Added two new optional outputs:
```groovy
tuple val(meta), path("*_size_distributions.png")     , emit: size_plot, optional: true
tuple val(meta), path("*_dna_intensity.png")          , emit: dna_plot, optional: true
```

These are marked as `optional: true` because:
- Size distribution plot requires specific area shape columns
- DNA intensity plot requires DNA intensity column
- Not all datasets will have these columns

#### Script Section
Added `output_prefix` parameter to papermill command:
```bash
-p output_prefix ${prefix}
```

#### Stub Section
Added touch commands for the PNG files to support dry-run testing.

### 3. Documentation Updates

#### meta.yml
Added entries for the two new optional outputs with descriptions explaining their conditional nature.

#### README.md
- Updated **Outputs** section to list the new PNG files
- Updated **Visualizations** section to explain that plots are now saved as high-resolution PNG files
- Noted that outputs are optional based on column availability

## Output Files

The module now produces the following image files (when applicable):

1. **`{prefix}_size_distributions.png`**
   - 3-panel plot showing cell, nuclear, and cytoplasm size distributions
   - Created only if area shape columns are present
   - 15x4 inch figure at 300 DPI

2. **`{prefix}_dna_intensity.png`**
   - 2-panel plot showing DNA intensity histogram and box plot
   - Created only if `Nuclei_Intensity_MeanIntensity_DNA` column is present
   - 12x4 inch figure at 300 DPI

## Benefits

1. **Reusable Plots**: Visualization plots can be used in presentations, reports, or publications without extracting from notebooks
2. **High Quality**: 300 DPI resolution suitable for publications
3. **Automated**: No manual intervention needed - plots are automatically saved when generated
4. **Optional**: Module gracefully handles cases where columns are missing
5. **Named Consistently**: Files follow the same naming pattern as other outputs using the meta information

## Usage Example

When running the workflow, if the parquet file contains the required columns, you'll get:
```
2021_04_26_Batch1_BR00117035_A01_1_stats.ipynb
2021_04_26_Batch1_BR00117035_A01_1_descriptive_stats.parquet
2021_04_26_Batch1_BR00117035_A01_1_size_distributions.png
2021_04_26_Batch1_BR00117035_A01_1_dna_intensity.png
```

If certain columns are missing, only the applicable PNG files will be created.
