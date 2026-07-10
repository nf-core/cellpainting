# nf-core/cellpainting: Implementation Design

## Purpose

This document turns the meeting-derived architecture into an implementation sequence. It is not a project-management document. It exists to answer one question:

What should be built first so the pipeline reaches a coherent, testable shape quickly?

## Recommended build order

### Phase 1: lock the workflow shape

Deliverables:

- choose the standardized collated convergence format
- decide the exact v1 processed-data entry scope
- document where v1 stops downstream

Why first:

- this unblocks branching and channel design
- without this, analysis and processed-entry work will drift

## Phase 2: stabilize the raw-image path

Deliverables:

- tall raw-image samplesheet schema
- reusable metadata validation
- task-level `load_data.csv` generation
- working illumination correction
- working assay-development branch
- working analysis branch

Why second:

- this is the canonical path
- the processed-data entrypoint should reuse the downstream half of this path rather than invent its own

## Phase 3: add QC gate + resume behavior

Deliverables:

- explicit stop after assay-development outputs
- parameterized resume/continue behavior
- documented QC expectations

Why now:

- the meetings repeatedly point to this as a high-value usability pattern
- it reduces wasted compute and fits real cell-painting workflows

## Phase 4: wire the collated convergence point

Deliverables:

- deterministic `Cytotable` handoff from analysis outputs
- stable collated output naming
- tests asserting the collated contract

Why now:

- this is the dependency boundary for both entrypoints
- it lets the repo reach a coherent MVP even if later downstream work is deferred

## Phase 5: implement processed-data entrypoint

Deliverables:

- manifest/schema for processed inputs
- format discrimination or explicit format parameter
- conversion path into the standardized collated representation
- shared downstream path after normalization

Why after raw path:

- the processed entrypoint should target an existing stable internal representation
- otherwise both entrypaths will evolve at once and become harder to test

## Phase 6: downstream profile processing

Deliverables:

- decide v1 endpoint: `Cytotable`, `Cytotable + QC`, or `pycytominer`
- if included, implement downstream profile-processing subworkflows against the collated contract

Why last:

- meetings indicate this is still moving
- the repo needs a clean data boundary before layering more downstream logic

## Repo-facing changes implied by this design

### Workflow wiring

- main workflow should branch only at the top-level entrypoint
- downstream of collation, both paths should share code

### Module shape

- modules should accept strongly typed metadata maps plus staged paths
- avoid large implicit directory inputs where a manifest-driven input is possible

### Testing

The repo should carry both:

- spec tests for the intended grouped interfaces and emitted artifacts
- regression tests for bugs found while wiring `load_data.csv`, staging, and grouping

Expected test focus:

- raw-image entrypoint
- processed-data entrypoint
- illumination grouping
- assay-development grouping
- analysis grouping
- collated convergence artifact
- resume/QC stop behavior where practical

### Documentation

The public docs should explain:

- what inputs are accepted
- which workflow stage each entrypoint skips
- what standardized format the workflow converges on
- what parts of the workflow are intentionally deferred

## Current risks

### 1. Too many entry formats too early

If v1 accepts every historical processed form directly, the normalization logic will dominate the implementation.

### 2. `load_data.csv` complexity leaks across modules

If each stage invents its own metadata-to-CSV logic, the pipeline will become hard to reason about and harder to test.

### 3. QC stop behavior added late

If the workflow is built as a straight-through pipeline first, retrofitting human QC gates later will be awkward.

### 4. Environment/test instability slows architecture work

Several meetings called out snapshot and dev-environment churn. The implementation order should keep tests passing while the interfaces settle.

## Suggested definition of MVP

An MVP is reached when all of the following are true:

- raw-image entrypoint works end-to-end
- assay-development outputs can be reviewed before continuation
- analysis outputs collate into the standardized format
- processed-data entrypoint can enter at one clearly documented supported point
- both entrypoints are covered by nf-test
- docs describe supported contracts without ambiguity

## Deferred items after MVP

- richer processed-data auto-detection
- additional segmentation backends
- broader custom-channel logic
- broader pooled-workflow reuse
- heavier downstream visualization/profile-analysis features
