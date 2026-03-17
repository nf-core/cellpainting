# nf-core/cellpainting: Data Contracts

## Purpose

This document defines the workflow-facing data contracts that the pipeline should enforce. It is intentionally stricter than the broad brainstorming in the meeting notes.

The main rule is simple: accept a small number of explicit input shapes, normalize them early, and keep all internal process interfaces predictable.

## Contract summary

The pipeline should support two workflow entry contracts:

- `raw_images`
- `processed_cellprofiler`

Both contracts should ultimately produce the same internal collated representation for downstream processing.

## `raw_images` contract

### Expected shape

A tall samplesheet where each row describes one image and its metadata.

### Required fields

The exact schema may evolve, but the workflow design assumes at least:

| Field | Meaning |
|---|---|
| `path` | image path or URI |
| `channel` | imaging channel name |
| `batch` | batch identifier |
| `plate` | plate identifier |
| `well` | well identifier |
| `site` | site / field-of-view identifier |

Optional metadata can be included, but grouping logic should not depend on undocumented columns.

### Supported path types

- local filesystem paths
- cloud URIs such as `s3://...`

Nextflow is responsible for staging.

## `processed_cellprofiler` contract

### Purpose

Allows workflow entry after raw image preprocessing has already happened elsewhere.

### Supported shapes

The meetings discussed several possible shapes:

- per-image / per-site CellProfiler analysis outputs
- collated sqlite
- collated csv
- already standardized collated outputs

For v1, the contract should stay narrow and explicit. The workflow should either:

- accept only one or two clearly supported processed forms, or
- require conversion to the standardized collated format before continuing

### Recommendation

Treat this contract as a manifest plus paths to processed artifacts, not as an unstructured directory drop.

## Internal process contracts

### Illumination correction input

Grouped by:

- `batch`
- `plate`
- `channel`

Expected task inputs:

- metadata map
- staged image list
- generated `load_data.csv`
- illumination `cppipe`

Expected outputs:

- illumination correction artifacts
- versions metadata

### Assay development input

Grouped by:

- `batch`
- `plate`
- `well`

Expected task inputs:

- metadata map
- staged image list
- matching illumination files
- generated `load_data.csv`
- assay-development `cppipe`

Expected outputs:

- assay-development images for review
- optional per-group CSV outputs
- versions metadata

This stage should operate on a representative subset per group, not the entire full-analysis footprint.

### Analysis input

Grouped by:

- `batch`
- `plate`
- `well`
- `site`

Expected task inputs:

- metadata map
- staged image list
- matching illumination files
- generated `load_data.csv`
- analysis `cppipe`

Expected outputs:

- CellProfiler analysis outputs
- versions metadata

### Collation input

The `Cytotable` step should take normalized analysis outputs and emit one standardized collated artifact per analysis grouping or other explicitly defined merge unit.

Expected outputs:

- standardized collated profiles
- stable filenames that encode enough metadata to avoid collisions

## File naming rules

Output names should include relevant metadata, especially for grouped CellProfiler outputs.

At minimum, filenames should encode enough of:

- `batch`
- `plate`
- `well`
- `site`
- `channel` where applicable

This avoids collisions and makes published artifacts debuggable.

## `load_data.csv` rules

### Workflow ownership

The workflow generates `load_data.csv`. Users should not be expected to handcraft task-level CSVs for individual processing stages.

### Layering

At least two `load_data.csv` forms are needed in practice:

- one for pre-illumination / raw-image stages
- one that includes derived illumination artifacts for later CellProfiler stages

### Canonical source

The canonical source of truth should be structured metadata inside the workflow, not the generated CSV text itself.

Generated CSV files are derived artifacts.

## `cppipe` compatibility rules

The workflow assumes `cppipe` files are written to work with staged inputs.

Minimum expectations:

- use default input directory semantics compatible with Nextflow staging
- do not assume absolute original source paths
- do not rely on CellProfiler grouping to replace workflow grouping

Custom `cppipe` overrides are allowed, but only documented workflow-compatible behavior is supported.

## Validation recommendations

The workflow should validate early:

- required columns exist
- metadata keys needed for grouping are non-null
- channels map to expected names or documented aliases
- all referenced files exist or are fetchable
- processed entrypoint manifests describe one supported shape

## Open contract decisions

- Exact minimal required columns for the raw-image schema.
- Exact v1 processed-data schema.
- Whether standardized collated output is parquet-only in v1.
- Whether the workflow should emit a merged master metadata artifact spanning all groups.
