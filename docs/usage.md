# nf-core/cellpainting: Usage

## ⚠️ Please read this documentation on the nf-core website: [https://nf-co.re/cellpainting/usage](https://nf-co.re/cellpainting/usage)

> _Documentation of pipeline parameters is generated automatically from the pipeline schema and can no longer be found in markdown files._

## Introduction

This pipeline processes [Cell Painting](https://doi.org/10.1038/nprot.2016.105) assay images through illumination correction, segmentation QC, morphological feature extraction, and format conversion. For technical architecture details, see the [architecture documentation](architecture.md).

## Samplesheet input

You will need to create a samplesheet with information about the images you would like to analyse before running the pipeline. Use the `--input` parameter to specify its location.

```bash
--input '[path to samplesheet file]'
```

The samplesheet is in **tall format** — one row per image. Each row associates a single `.tif`/`.tiff` image file with its channel and plate/well/site metadata.

```csv
channel,path,source,batch,plate,well,site,row,col
Mito,s3://cellpainting-gallery/cpg0016-jump/source_4/images/2021_04_26_Batch1/images/BR00117035__2021-05-02T16_02_51-Measurement1/Images/r01c01f01p01-ch1sk1fk1fl1.tiff,source_4,2021_04_26_Batch1,BR00117035,A01,1,1,1
DNA,s3://cellpainting-gallery/cpg0016-jump/source_4/images/2021_04_26_Batch1/images/BR00117035__2021-05-02T16_02_51-Measurement1/Images/r01c01f01p01-ch5sk1fk1fl1.tiff,source_4,2021_04_26_Batch1,BR00117035,A01,1,1,1
ER,s3://cellpainting-gallery/cpg0016-jump/source_4/images/2021_04_26_Batch1/images/BR00117035__2021-05-02T16_02_51-Measurement1/Images/r01c01f01p01-ch4sk1fk1fl1.tiff,source_4,2021_04_26_Batch1,BR00117035,A01,1,1,1
RNA,s3://cellpainting-gallery/cpg0016-jump/source_4/images/2021_04_26_Batch1/images/BR00117035__2021-05-02T16_02_51-Measurement1/Images/r01c01f01p01-ch3sk1fk1fl1.tiff,source_4,2021_04_26_Batch1,BR00117035,A01,1,1,1
AGP,s3://cellpainting-gallery/cpg0016-jump/source_4/images/2021_04_26_Batch1/images/BR00117035__2021-05-02T16_02_51-Measurement1/Images/r01c01f01p01-ch2sk1fk1fl1.tiff,source_4,2021_04_26_Batch1,BR00117035,A01,1,1,1
```

A standard Cell Painting experiment images 5-8 channels (e.g., `DNA`, `Mito`, `ER`, `RNA`, `AGP`) across multiple plates, wells, and sites. Each unique combination of `batch`, `plate`, `well`, `site`, and `channel` should have exactly one row in the samplesheet.

### Full samplesheet

The samplesheet requires the following columns:

| Column     | Required | Type   | Description                                                                                                |
| ---------- | -------- | ------ | ---------------------------------------------------------------------------------------------------------- |
| `channel`  | Yes      | string | Channel identifier (e.g.,`DNA`, `Mito`, `ER`, `RNA`, `AGP`). Alphanumeric characters and underscores only. |
| `path`     | Yes      | string | Path to a `.tif` or `.tiff` image file. Supports local filesystem paths and S3 URIs.                       |
| `source`   | Yes      | string | Data source identifier (e.g.,`source_4`).                                                                  |
| `batch`    | Yes      | string | Batch identifier (e.g.,`2021_04_26_Batch1`).                                                               |
| `plate`    | Yes      | string | Plate identifier (e.g.,`BR00117035`).                                                                      |
| `well`     | Yes      | string | Well identifier (e.g.,`A01`).                                                                              |
| `site`     | Yes      | number | Site/field number within the well.                                                                         |
| `row`      | Yes      | number | Plate row number.                                                                                          |
| `col`      | Yes      | number | Plate column number.                                                                                       |
| `field_id` | No       | number | Field identifier (optional additional metadata).                                                           |
| `plane_id` | No       | number | Z-plane identifier (optional additional metadata).                                                         |

An [example minimal samplesheet](../assets/samplesheet.csv) has been provided with the pipeline.

## Pipeline modes

The `--cellprofiler_mode` parameter controls which pipeline steps are executed:

- **`assay_development`** — Runs illumination correction and assay development QC only. Use this mode to validate segmentation quality before committing to a full analysis run.
- **`analysis`** (default) — Runs the full pipeline: illumination correction, assay development QC, feature extraction, and CytoTable conversion.

Assay development always runs as a QC gate, even in `analysis` mode.

## CellProfiler pipeline files

The pipeline uses CellProfiler `.cppipe` pipeline files for each processing step. Default pipelines are included in the `assets/cellprofiler/` directory. You can provide your own pipelines using the following parameters:

| Parameter                                | Default                                         | Description                                                                                                                     |
| ---------------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `--cellprofiler_illumination_cppipe`     | `assets/cellprofiler/illumination.cppipe.jinja` | CellProfiler pipeline for illumination correction. Uses `{{channel}}` Jinja-style placeholders that are substituted at runtime. |
| `--cellprofiler_assaydevelopment_cppipe` | `assets/cellprofiler/assaydevelopment.cppipe`   | CellProfiler pipeline for assay development QC.                                                                                 |
| `--cellprofiler_analysis_cppipe`         | `assets/cellprofiler/analysis.cppipe`           | CellProfiler pipeline for full feature extraction.                                                                              |
| `--cellprofiler_assaydevelopment_site`   | `1`                                             | Site number to use for assay development (single site per well).                                                                |

## Running the pipeline

The typical command for running the pipeline is as follows:

```bash
nextflow run nf-core/cellpainting \
   --input ./samplesheet.csv \
   --outdir ./results \
   -profile docker
```

This will launch the pipeline with the `docker` configuration profile in the default `analysis` mode. See below for more information about profiles.

To run in assay development mode (QC only):

```bash
nextflow run nf-core/cellpainting \
   --input ./samplesheet.csv \
   --cellprofiler_mode assay_development \
   --outdir ./results \
   -profile docker
```

Note that the pipeline will create the following files in your working directory:

```bash
work                # Directory containing the nextflow working files
<OUTDIR>            # Finished results in specified location (defined with --outdir)
.nextflow_log       # Log file from Nextflow
# Other nextflow hidden files, eg. history of pipeline runs and old logs.
```

If you wish to repeatedly use the same parameters for multiple runs, rather than specifying each flag in the command, you can specify these in a params file.

Pipeline settings can be provided in a `yaml` or `json` file via `-params-file <file>`.

> [!WARNING]
> Do not use `-c <file>` to specify parameters as this will result in errors. Custom config files specified with `-c` must only be used for [tuning process resource specifications](https://nf-co.re/docs/usage/configuration#tuning-workflow-resources), other infrastructural tweaks (such as output directories), or module arguments (args).

The above pipeline run specified with a params file in yaml format:

```bash
nextflow run nf-core/cellpainting -profile docker -params-file params.yaml
```

with:

```yaml
input: "./samplesheet.csv"
outdir: "./results/"
cellprofiler_mode: "analysis"
```

You can also generate such `YAML`/`JSON` files via [nf-core/launch](https://nf-co.re/launch).

### Updating the pipeline

When you run the above command, Nextflow automatically pulls the pipeline code from GitHub and stores it as a cached version. When running the pipeline after this, it will always use the cached version if available - even if the pipeline has been updated since. To make sure that you're running the latest version of the pipeline, make sure that you regularly update the cached version of the pipeline:

```bash
nextflow pull nf-core/cellpainting
```

### Reproducibility

It is a good idea to specify the pipeline version when running the pipeline on your data. This ensures that a specific version of the pipeline code and software are used when you run your pipeline. If you keep using the same tag, you'll be running the same version of the pipeline, even if there have been changes to the code since.

First, go to the [nf-core/cellpainting releases page](https://github.com/nf-core/cellpainting/releases) and find the latest pipeline version - numeric only (eg. `1.3.1`). Then specify this when running the pipeline with `-r` (one hyphen) - eg. `-r 1.3.1`. Of course, you can switch to another version by changing the number after the `-r` flag.

This version number will be logged in reports when you run the pipeline, so that you'll know what you used when you look back in the future. For example, at the bottom of the MultiQC reports.

To further assist in reproducibility, you can use share and reuse [parameter files](#running-the-pipeline) to repeat pipeline runs with the same settings without having to write out a command with every single parameter.

> [!TIP]
> If you wish to share such profile (such as upload as supplementary material for academic publications), make sure to NOT include cluster specific paths to files, nor institutional specific profiles.

## Core Nextflow arguments

> [!NOTE]
> These options are part of Nextflow and use a _single_ hyphen (pipeline parameters use a double-hyphen)

### `-profile`

Use this parameter to choose a configuration profile. Profiles can give configuration presets for different compute environments.

Several generic profiles are bundled with the pipeline which instruct the pipeline to use software packaged using different methods (Docker, Singularity, Podman, Shifter, Charliecloud, Apptainer, Conda) - see below.

> [!IMPORTANT]
> We highly recommend the use of Docker or Singularity containers for full pipeline reproducibility, however when this is not possible, Conda is also supported.

The pipeline also dynamically loads configurations from [https://github.com/nf-core/configs](https://github.com/nf-core/configs) when it runs, making multiple config profiles for various institutional clusters available at run time. For more information and to check if your system is supported, please see the [nf-core/configs documentation](https://github.com/nf-core/configs#documentation).

Note that multiple profiles can be loaded, for example: `-profile test,docker` - the order of arguments is important!
They are loaded in sequence, so later profiles can overwrite earlier profiles.

If `-profile` is not specified, the pipeline will run locally and expect all software to be installed and available on the `PATH`. This is _not_ recommended, since it can lead to different results on different machines dependent on the computer environment.

- `test`
  - A profile with a complete configuration for automated testing with a **minimal** samplesheet (3 wells with 2 sites per well and 8 channels per site)
  - Includes links to test data so needs no other parameters
- `test_full`
  - A profile with a complete configuration for automated testing with a **larger** samplesheet (4 wells with 9 sites per well and 8 channels per site; negative control well included)
  - Includes links to test_full data so needs no other parameters
- `docker`
  - A generic configuration profile to be used with [Docker](https://docker.com/)
- `singularity`
  - A generic configuration profile to be used with [Singularity](https://sylabs.io/docs/)
- `podman`
  - A generic configuration profile to be used with [Podman](https://podman.io/)
- `shifter`
  - A generic configuration profile to be used with [Shifter](https://nersc.gitlab.io/development/shifter/how-to-use/)
- `charliecloud`
  - A generic configuration profile to be used with [Charliecloud](https://charliecloud.io/)
- `apptainer`
  - A generic configuration profile to be used with [Apptainer](https://apptainer.org/)
- `wave`
  - A generic configuration profile to enable [Wave](https://seqera.io/wave/) containers. Use together with one of the above (requires Nextflow ` 24.03.0-edge` or later).
- `conda`
  - A generic configuration profile to be used with [Conda](https://conda.io/docs/). Please only use Conda as a last resort i.e. when it's not possible to run the pipeline with Docker, Singularity, Podman, Shifter, Charliecloud, or Apptainer.

### `-resume`

Specify this when restarting a pipeline. Nextflow will use cached results from any pipeline steps where the inputs are the same, continuing from where it got to previously. For input to be considered the same, not only the names must be identical but the files' contents as well. For more info about this parameter, see [this blog post](https://www.nextflow.io/blog/2019/demystifying-nextflow-resume.html).

You can also supply a run name to resume a specific run: `-resume [run-name]`. Use the `nextflow log` command to show previous run names.

### `-c`

Specify the path to a specific config file (this is a core Nextflow command). See the [nf-core website documentation](https://nf-co.re/usage/configuration) for more information.

## Custom configuration

### Resource requests

Whilst the default requirements set within the pipeline will hopefully work for most people and with most input data, you may find that you want to customise the compute resources that the pipeline requests. Each step in the pipeline has a default set of requirements for number of CPUs, memory and time. For most of the pipeline steps, if the job exits with any of the error codes specified [here](https://github.com/nf-core/rnaseq/blob/4c27ef5610c87db00c3c5a3eed10b1d161abf575/conf/base.config#L18) it will automatically be resubmitted with higher resources request (2 x original, then 3 x original). If it still fails after the third attempt then the pipeline execution is stopped.

To change the resource requests, please see the [max resources](https://nf-co.re/docs/usage/configuration#max-resources) and [tuning workflow resources](https://nf-co.re/docs/usage/configuration#tuning-workflow-resources) section of the nf-core website.

### Custom Containers

In some cases, you may wish to change the container or conda environment used by a pipeline steps for a particular tool. By default, nf-core pipelines use containers and software from the [biocontainers](https://biocontainers.pro/) or [bioconda](https://bioconda.github.io/) projects. However, in some cases the pipeline specified version maybe out of date.

To use a different container from the default container or conda environment specified in a pipeline, please see the [updating tool versions](https://nf-co.re/docs/usage/configuration#updating-tool-versions) section of the nf-core website.

### Custom Tool Arguments

A pipeline might not always support every possible argument or option of a particular tool used in pipeline. Fortunately, nf-core pipelines provide some freedom to users to insert additional parameters that the pipeline does not include by default.

To learn how to provide additional arguments to a particular tool of the pipeline, please see the [customising tool arguments](https://nf-co.re/docs/usage/configuration#customising-tool-arguments) section of the nf-core website.

### nf-core/configs

In most cases, you will only need to create a custom config as a one-off but if you and others within your organisation are likely to be running nf-core pipelines regularly and need to use the same settings regularly it may be a good idea to request that your custom config file is uploaded to the `nf-core/configs` git repository. Before you do this please can you test that the config file works with your pipeline of choice using the `-c` parameter. You can then create a pull request to the `nf-core/configs` repository with the addition of your config file, associated documentation file (see examples in [`nf-core/configs/docs`](https://github.com/nf-core/configs/tree/master/docs)), and amending [`nfcore_custom.config`](https://github.com/nf-core/configs/blob/master/nfcore_custom.config) to include your custom profile.

See the main [Nextflow documentation](https://www.nextflow.io/docs/latest/config.html) for more information about creating your own configuration files.

If you have any questions or issues please send us a message on [Slack](https://nf-co.re/join/slack) on the [`#configs` channel](https://nfcore.slack.com/channels/configs).

## Running in the background

Nextflow handles job submissions and supervises the running jobs. The Nextflow process must run until the pipeline is finished.

The Nextflow `-bg` flag launches Nextflow in the background, detached from your terminal so that the workflow does not stop if you log out of your session. The logs are saved to a file.

Alternatively, you can use `screen` / `tmux` or similar tool to create a detached session which you can log back into at a later time.
Some HPC setups also allow you to run nextflow within a cluster job submitted your job scheduler (from where it submits more jobs).

## Nextflow memory requirements

In some cases, the Nextflow Java virtual machines can start to request a large amount of memory.
We recommend adding the following line to your environment to limit this (typically in `~/.bashrc` or `~./bash_profile`):

```bash
NXF_OPTS='-Xms1g -Xmx4g'
```
