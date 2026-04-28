# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Test commands

```bash
# 1. Fast: stub variants of every test (pipeline + modules), filtered by `stub` tag (~3min)
nf-test test tests/default.nf.test modules/local --profile test,docker --tag stub

# 2. Full: every test including real CellProfiler runs (~13min, needs Docker with >= 16GB memory)
nf-test test tests/default.nf.test modules/local --profile test,docker
```

### Linting

```bash
nf-core pipelines lint --dir .
pre-commit run --all-files
```

### Running a single module test

```bash
nf-test test modules/local/cellprofiler/illuminationcorrection/tests/main.nf.test --profile test,docker
```

### Regenerating snapshots after process output changes

```bash
nf-test test tests/default.nf.test modules/local --profile test,docker --update-snapshot
```

### Resume a failed pipeline run

```bash
nextflow run . -profile test,docker --outdir results -resume
```

### Staging a local Cell Painting Gallery mirror for minimal test data

The non-stub `cellprofiler/*` tests fetch source TIFFs and illumination `.npy`
files from `s3://cellpainting-gallery/cpg0016-jump/source_4/...` via the
`params.cellpainting_gallery_testdata_base_path` parameter (defined in
`tests/nextflow.config`, default `s3://cellpainting-gallery/`). To run the real
tests without going to S3 every time, mirror the relevant subtree once and
point the env var at the local copy:

```bash
# 1. Stage the illumination .npy files (~37MB)
aws s3 sync \
  s3://cellpainting-gallery/cpg0016-jump/source_4/images/2021_04_26_Batch1/illum/BR00117035/ \
  .nf-test/testdata/cpg0016-jump/source_4/images/2021_04_26_Batch1/illum/BR00117035/ \
  --no-sign-request

# 2. Stage the source TIFFs for wells A01, A02, B01 (sites 1+2, ~150MB)
aws s3 sync \
  s3://cellpainting-gallery/cpg0016-jump/source_4/images/2021_04_26_Batch1/images/BR00117035__2021-05-02T16_02_51-Measurement1/Images/ \
  .nf-test/testdata/cpg0016-jump/source_4/images/2021_04_26_Batch1/images/BR00117035__2021-05-02T16_02_51-Measurement1/Images/ \
  --exclude '*' \
  --include 'r01c01f0[12]*' --include 'r01c02f0[12]*' --include 'r02c01f0[12]*' \
  --no-sign-request

# 3. Run nf-test against the local mirror
export CELLPAINTING_GALLERY_TESTDATA_BASE_PATH=$PWD/.nf-test/testdata/
nf-test test tests/default.nf.test modules/local --profile test,docker
```

`.nf-test/` is gitignored, so the mirror stays out of version control.

## Architecture

### Pipeline flow

```
Samplesheet → ILLUMINATION_CORRECTION → ASSAY_DEVELOPMENT → ANALYSIS → CYTOTABLE → MULTIQC
                (per channel/plate)       (per well, 1 site)  (per site)  (per site)
```

`cellprofiler_mode` controls branching:

- `assay_development`: runs illumination + assay dev only
- `analysis`: runs illumination + assay dev + analysis + cytotable

Assay development always runs (it's a QC gate before full analysis).

### Data-staging pattern

Every CellProfiler module follows the same pattern:

1. Nextflow stages images (and .npy illumination files) into `images/` via `stageAs`
2. Groovy serializes per-image metadata into a JSON file (sanitized to plain maps to avoid StackOverflow)
3. A Python `bin/` script reads the JSON and generates `load_data.csv`
4. CellProfiler runs headless with `--data-file=load_data.csv` and `-g` metadata grouping

### Channel operations

All grouping/joining happens inline in `workflows/cellpainting.nf`, not in subworkflows:

- Images grouped by `[batch, plate, channel]` for illumination correction
- Illumination .npy files flattened to plate level, then joined to downstream steps via `.combine(ch_illum_by_plate, by: 0)`
- Assay dev filters to a single site before `groupTuple()` (not after) for efficiency
- `sortGroupedImages` closure sorts image pairs by filename after every `groupTuple()` for deterministic `-resume` caching

### Illumination cppipe templating

`illumination.cppipe.jinja` uses `{{channel}}` placeholders. The illumination correction process substitutes the channel name via `sed` at runtime. This is why `assets/cellprofiler/illumination.cppipe.jinja` and `modules/local/cellprofiler/illuminationcorrection/main.nf` are in the `template_strings` lint ignore list.

## Key conventions

- Python `bin/` scripts use only stdlib (no external dependencies)
- All CellProfiler modules must call `cellprofiler --version` in both `script:` and `stub:` blocks
- Metadata maps must be sanitized to plain key-value maps before `groovy.json.JsonOutput.toJson()` — Nextflow meta maps contain internal objects that cause `StackOverflowError`
- nf-core module tests that reference S3 data work because `cellpainting-gallery` is a public bucket with anonymous access
- Test profile resource limits: 4 CPUs, 15GB RAM, 1h — matching CI runner specs

## nf-core template sync

Pipeline tracks nf-core template via `TEMPLATE` branch. To sync:

```bash
nf-core pipelines sync
git merge origin/TEMPLATE
```

Keep our samplesheet parsing in `subworkflows/local/utils_nfcore_cellpainting_pipeline/main.nf` (don't take the generic fastq handling from template).
