# Analysis Step Design — Full Pipeline Refactor

## Summary

Implement the CellProfiler analysis step for the nf-core/cellpainting pipeline while refactoring the entire pipeline to adopt the data-staging pattern from nf-pooled-cellpainting. This replaces the current subworkflow-based CSV generation approach with a pattern where each CellProfiler process generates its own `load_data.csv` at runtime from staged files and a metadata JSON.

## Context

- **Issue**: nf-core/cellpainting#6
- **Reference implementation**: [broadinstitute/nf-pooled-cellpainting](https://github.com/broadinstitute/nf-pooled-cellpainting)
- **Prior work**: `001-mergecsv-migration` branch (WIP migration to inline CSV generation)
- **Current branch**: `ken-brewer/feat-analysis`

### What is the analysis step?

The analysis step runs CellProfiler on illumination-corrected images to perform cell segmentation and full feature extraction (morphology, intensity, texture, etc.). It processes every site in every well — unlike assay development which subsamples a single site per well for QC.

### Key differences from assay development

|                        | Assay Development               | Analysis                                               |
| ---------------------- | ------------------------------- | ------------------------------------------------------ |
| Purpose                | QC segmentation on subsample    | Full measurement run                                   |
| Sites                  | Single site per well (filtered) | All sites                                              |
| Grouping               | `[batch, plate, well]`          | `[batch, plate, well, site]`                           |
| CellProfiler `-g` flag | `Metadata_Plate,Metadata_Well`  | `Metadata_Plate,Metadata_Well,Metadata_Site`           |
| Outputs                | Overlay PNGs + Image.csv        | Multiple CSVs (Image, Nuclei, Cells, Cytoplasm) + PNGs |
| Downstream             | Visual QC inspection            | CYTOTABLE Parquet conversion                           |

## Architecture

### Pipeline Flow

```
Samplesheet
  -> enrich with filename metadata
  -> group by [batch, plate, channel]
  -> CELLPROFILER_ILLUMINATIONCORRECTION (generates own CSV from metadata JSON, outputs .npy files)
  -> flatten illum corrections to plate level
  -> if mode == 'assay_development':
       group by [batch, plate, well], filter to single site, join with illum .npy files
       -> CELLPROFILER_ASSAYDEVELOPMENT (generates own CSV from metadata JSON, outputs PNGs + Image.csv)
  -> if mode == 'analysis':
       group by [batch, plate, well, site], join with illum .npy files
       -> CELLPROFILER_ANALYSIS (generates own CSV from metadata JSON, outputs CSVs + PNGs)
       -> CYTOTABLE (converts CSV directory to Parquet)
```

### Core Pattern: Data Staging + Metadata JSON

Every CellProfiler process follows the same pattern:

1. Nextflow stages images (and illumination files where needed) into the process working directory via `path(..., stageAs: "images/*")`
2. Nextflow writes a metadata JSON containing per-image metadata from the samplesheet
3. A Python `bin/` script reads the metadata JSON and generates `load_data.csv`
4. CellProfiler runs headless with `--data-file=load_data.csv` and `-g` metadata grouping

This replaces the current subworkflow-based approach where CSVs are generated in separate subworkflows and passed to processes.

## Workflow Channel Operations

### Samplesheet Enrichment

```groovy
ch_samplesheet
    .map { meta, image ->
        def image_meta = meta.clone()
        image_meta.filename = image.name
        [image_meta, image]
    }
    .set { ch_enriched }
```

### Illumination Correction Grouping

Group by `[batch, plate, channel]`, carry per-image metadata:

```groovy
ch_enriched
    .map { meta, image ->
        def group_key = meta.subMap(['batch', 'plate', 'channel'])
        def group_id = [meta.batch, meta.plate, meta.channel].join('_')
        [group_key + [id: group_id], meta, image]
    }
    .groupTuple()  // -> [group_meta, [images_meta_list], [images_list]]
    .set { ch_illumination_images }
```

### Illumination Corrections Flattened to Plate Level

```groovy
CELLPROFILER_ILLUMINATIONCORRECTION.out.illumination_corrections
    .map { meta, npy_files ->
        def plate_key = [meta.batch, meta.plate].join('_')
        [plate_key, npy_files]
    }
    .groupTuple()
    .map { key, npy_lists -> [key, npy_lists.flatten()] }
    .set { ch_illum_by_plate }
```

### Assay Development Channel (per-well, single site)

```groovy
ch_enriched
    .map { meta, image ->
        def group_id = [meta.batch, meta.plate, meta.well].join('_')
        def group_key = meta.subMap(['batch', 'plate', 'well']) + [id: group_id, site: meta.site]
        [group_key, meta, image]
    }
    .groupTuple()
    .filter { meta, _images_meta, _images ->
        meta.site == cellprofiler_assaydevelopment_site
    }
    .map { meta, images_meta, images ->
        def plate_key = [meta.batch, meta.plate].join('_')
        [plate_key, meta, images_meta, images]
    }
    .combine(ch_illum_by_plate, by: 0)
    .map { _key, meta, images_meta, images, illum_files ->
        [meta, images_meta, images, illum_files]
    }
    .set { ch_assay_dev_with_illum }
```

### Analysis Channel (per-site)

```groovy
ch_enriched
    .map { meta, image ->
        def group_id = [meta.batch, meta.plate, meta.well, meta.site].join('_')
        def group_key = meta.subMap(['batch', 'plate', 'well', 'site']) + [id: group_id]
        [group_key, meta, image]
    }
    .groupTuple()
    .map { meta, images_meta, images ->
        def plate_key = [meta.batch, meta.plate].join('_')
        [plate_key, meta, images_meta, images]
    }
    .combine(ch_illum_by_plate, by: 0)
    .map { _key, meta, images_meta, images, illum_files ->
        [meta, images_meta, images, illum_files]
    }
    .set { ch_analysis_with_illum }
```

## Module Definitions

### CELLPROFILER_ILLUMINATIONCORRECTION

```groovy
input:
tuple val(meta), val(images_meta), path(images, stageAs: "images/*")
path illumination_cppipe

output:
tuple val(meta), path("illumination_corrections/*.npy"), emit: illumination_corrections
path "versions.yml", emit: versions

script:
def metadata = groovy.json.JsonOutput.toJson([meta: meta, images: images_meta])
"""
echo '${metadata}' > metadata.json
generate_illumination_calc_csv.py --metadata metadata.json --output load_data.csv
sed 's/{{channel}}/${meta.channel}/g' ${illumination_cppipe} > illumination.cppipe
mkdir -p illumination_corrections
cellprofiler -c -r -p illumination.cppipe -o illumination_corrections \
    --data-file=load_data.csv --image-directory ./images/ \
    -g Metadata_Plate=${meta.plate}
"""
```

### CELLPROFILER_ASSAYDEVELOPMENT

```groovy
input:
tuple val(meta), val(images_meta), path(images, stageAs: "images/*"), path(illum_files, stageAs: "images/*")
path assay_development_cppipe

output:
tuple val(meta), path("assaydevelopment/*.png"), emit: png
tuple val(meta), path("assaydevelopment/Image.csv"), emit: csv, optional: true
path "versions.yml", emit: versions

script:
def metadata = groovy.json.JsonOutput.toJson([meta: meta, images: images_meta])
"""
echo '${metadata}' > metadata.json
generate_illumination_apply_csv.py --metadata metadata.json --images-dir ./images --output load_data.csv
mkdir -p assaydevelopment
cellprofiler -c -r -p ${assay_development_cppipe} -o assaydevelopment \
    --data-file=load_data.csv --image-directory ./images/ \
    -g Metadata_Plate=${meta.plate},Metadata_Well=${meta.well}
"""
```

### CELLPROFILER_ANALYSIS

```groovy
input:
tuple val(meta), val(images_meta), path(images, stageAs: "images/*"), path(illum_files, stageAs: "images/*")
path analysis_cppipe

output:
tuple val(meta), path("analysis"), emit: output_dir
tuple val(meta), path("analysis/*.png"), emit: pngs, optional: true
path "versions.yml", emit: versions

script:
def metadata = groovy.json.JsonOutput.toJson([meta: meta, images: images_meta])
"""
echo '${metadata}' > metadata.json
generate_illumination_apply_csv.py --metadata metadata.json --images-dir ./images --output load_data.csv
mkdir -p analysis
cellprofiler -c -r -p ${analysis_cppipe} -o analysis \
    --data-file=load_data.csv --image-directory ./images/ \
    -g Metadata_Plate=${meta.plate},Metadata_Well=${meta.well},Metadata_Site=${meta.site}
"""
```

Note: Both assay dev and analysis use `generate_illumination_apply_csv.py` — the CSV format is identical (original images paired with illumination corrections). The per-site vs per-well distinction is handled by Nextflow's channel grouping and CellProfiler's `-g` flag.

### Workflow `take:` Parameters

The workflow needs `cellprofiler_assaydevelopment_site` added to its `take:` block (already present on `001-mergecsv-migration`, not yet on this branch). This controls which site is used for the assay development subsample.

### CYTOTABLE

Adjusted to accept a directory of CellProfiler CSVs:

```groovy
input:
tuple val(meta), path(cellprofiler_output_dir)

output:
tuple val(meta), path("*.parquet")

script:
"""
#!/usr/bin/env python
from cytotable import convert
from parsl.config import Config
from parsl.executors import ThreadPoolExecutor
import os
os.environ["HOME"] = os.getcwd()

convert(
    source_path="${cellprofiler_output_dir}",
    source_datatype="csv",
    dest_path="${meta.batch}_${meta.plate}_${meta.well}_${meta.site}.parquet",
    dest_datatype="parquet",
    preset="cellprofiler_csv",
    parsl_config=Config(
        executors=[ThreadPoolExecutor(max_threads=${task.cpus})],
    )
)
"""
```

## Python bin/ Scripts

### Metadata JSON Structure

Written by Nextflow in the process script block:

```json
{
  "meta": {"id": "batch1_plate1_DNA", "batch": "batch1", "plate": "plate1", ...},
  "images": [
    {
      "filename": "WellA1_Point..._Seq0000.ome.tiff",
      "channel": "DNA",
      "well": "A1",
      "site": 1,
      "batch": "batch1",
      "plate": "plate1",
      "row": "A",
      "col": "1"
    }
  ]
}
```

### bin/generate_illumination_calc_csv.py

- Reads metadata JSON
- Single channel per group
- Generates CSV with `FileName_Orig{channel}` + metadata columns (`Metadata_Batch`, `Metadata_Plate`, `Metadata_Well`, `Metadata_Site`, etc.)
- Rows grouped by (well, site)

### bin/generate_illumination_apply_csv.py

- Reads metadata JSON for image info
- Globs `images/*.npy` to find illumination correction files, matches to channels by parsing `{plate}_Illum{channel}.npy` filename pattern
- Generates CSV with paired columns per channel: `FileName_Orig{channel}` / `FileName_Illum{channel}`
- Plus metadata columns
- Rows grouped by (well, site)
- Used by both assay development and analysis steps

## Files Changed

### Deleted

- `subworkflows/local/cellprofiler_load_data_csv/` (main.nf, meta.yml, tests/)
- `subworkflows/local/cellprofiler_load_data_csv_with_illum/` (main.nf, meta.yml, tests/)

### Rewritten

- `workflows/cellpainting.nf` — inline channel ops, analysis mode wiring, CYTOTABLE wiring
- `modules/local/cellprofiler/illuminationcorrection/main.nf` — metadata JSON input, generates own CSV
- `modules/local/cellprofiler/assaydevelopment.nf` — staged files, generates own CSV, real CellProfiler command
- `modules/local/cellprofiler/analysis.nf` — full rewrite from stub to working module
- `modules/local/cytotable/main.nf` — accept directory input instead of single CSV

### Created

- `bin/generate_illumination_calc_csv.py`
- `bin/generate_illumination_apply_csv.py`

### Updated

- `conf/modules.config` — publish dirs for analysis and cytotable
- `tests/default.nf.test` — updated for new process structure, regenerated snapshots

### Unchanged

- `nextflow.config` — params already support analysis mode
- `main.nf` — entry point unchanged
- `assets/cellprofiler/*.cppipe` — pipeline files unchanged
- All nf-core subworkflows/modules — untouched

## Testing

### Stub Strategy

Each module's `stub:` block produces the expected output structure with mock files:

- **Illumination correction**: `touch illumination_corrections/${meta.plate}_Illum${meta.channel}.npy`
- **Assay development**: mock PNG + CSV header for Image.csv
- **Analysis**: mock CSVs (Image.csv, Nuclei.csv, Cells.csv, Cytoplasm.csv) + mock PNG, in `analysis/` directory

### nf-test Updates

- Existing `tests/default.nf.test` updated for new process names and task counts
- Snapshots regenerated
- Test profile defaults to `assay_development` mode; add test case for `analysis` mode
