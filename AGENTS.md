# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Pre-push verification (required before every push)

```bash
# 1. Fast: stub variants of every test (pipeline + modules), filtered by `stub` tag (~3min)
nf-test test tests/default.nf.test modules/local --profile test,docker --tag stub

# 2. Full: every test including real CellProfiler runs (~13min, needs Docker with >= 16GB memory)
nf-test test tests/default.nf.test modules/local --profile test,docker
```

Do not push if either fails. Both stub and real variants live in the same `*.nf.test` file (per nf-core convention); the `stub` tag on the stub variants lets the fast pre-push command skip the slow real runs.

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
