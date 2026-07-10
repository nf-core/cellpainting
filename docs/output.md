# nf-core/cellpainting: Output

## Introduction

This document describes the output produced by the pipeline. The directories listed below will be created in the results directory after the pipeline has finished. All paths are relative to the top-level results directory.

## Pipeline overview

The pipeline is built using [Nextflow](https://www.nextflow.io/) and processes data using the following steps:

- [Illumination Correction](#illumination-correction) - Per-channel, per-plate illumination correction functions
- [Assay Development](#assay-development) - Single-site segmentation QC per well
- [Analysis](#analysis) - Full morphological feature extraction per site
- [CytoTable](#cytotable) - CSV-to-Parquet conversion
- [Pipeline information](#pipeline-information) - Report metrics generated during the workflow execution

### Illumination Correction

<details markdown="1">
<summary>Output files</summary>

- `cellprofiler/illumination_correction/`
  - `<batch>_<plate>_<channel>/`: One subdirectory per channel and plate combination
    - `<plate>_Illum<channel>.npy`: NumPy array containing the illumination correction function

</details>

[CellProfiler](https://cellprofiler.org/) computes per-channel, per-plate illumination correction functions using the CorrectIlluminationCalculate module. These `.npy` files are used as inputs to both the assay development and analysis steps to normalize uneven illumination across the field of view.

### Assay Development

<details markdown="1">
<summary>Output files</summary>

- `cellprofiler/assay_development/`
  - `<batch>_<plate>_<well>/`: One subdirectory per well
    - `*.png`: Segmentation overlay images for visual QC
    - `Image.csv`: Image-level measurements

</details>

[CellProfiler](https://cellprofiler.org/) segments a single site per well (controlled by `--cellprofiler_assaydevelopment_site`, default: `1`) and produces overlay images for visual inspection. This step serves as a QC gate — review the segmentation overlays before committing to full analysis. Assay development always runs in both `assay_development` and `analysis` modes.

### Analysis

<details markdown="1">
<summary>Output files</summary>

- `cellprofiler/analysis/`
  - `<batch>_<plate>_<well>_<site>/`: One subdirectory per site
    - `Image.csv`: Image-level measurements and metadata
    - `Nuclei.csv`: Nuclei object morphological measurements
    - `Cells.csv`: Cell object morphological measurements
    - `Cytoplasm.csv`: Cytoplasm object morphological measurements
    - `*.png`: Segmentation overlay images

</details>

[CellProfiler](https://cellprofiler.org/) performs full morphological feature extraction on every site. Images are grouped by batch, plate, well, and site, with illumination correction functions applied from the illumination correction step. This step only runs in `analysis` mode.

### CytoTable

<details markdown="1">
<summary>Output files</summary>

- `cytotable/`
  - `<batch>_<plate>.parquet`: Collated CellProfiler measurements for the entire plate (all wells and sites) in Parquet format.

</details>

[CytoTable](https://github.com/cytomining/CytoTable) consolidates the per-site CellProfiler CSV outputs of a plate into a single Parquet file using the `cellprofiler_csv` preset. Per-site `CELLPROFILER_ANALYSIS` runs are joined in one `cytotable.convert` call, producing one row per CellProfiler image set per plate. Parquet files are columnar, compressed, and ready for downstream analysis with tools like [Pycytominer](https://github.com/cytomining/pycytominer). This step only runs in `analysis` mode.

### Pipeline information

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/`
  - `execution_timeline_*.html`: Nextflow execution timeline
  - `execution_report_*.html`: Nextflow execution report with resource usage
  - `execution_trace_*.txt`: Nextflow execution trace with per-task metrics
  - `pipeline_dag_*.html`: Pipeline DAG visualization
  - `nf_core_cellpainting_software_mqc_versions.yml`: Software versions used in the run

</details>

[Nextflow](https://www.nextflow.io/docs/latest/tracing.html) provides excellent functionality for generating various reports relevant to the running and execution of the pipeline. This will allow you to troubleshoot errors with the running of the pipeline, and also provide you with other information such as launch commands, run times and resource usage.
