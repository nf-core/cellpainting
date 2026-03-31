# Analysis Step Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the CellProfiler analysis step and refactor all pipeline modules to use the data-staging + metadata JSON pattern from nf-pooled-cellpainting.

**Architecture:** Each CellProfiler process stages files into its working directory, receives a metadata JSON from Nextflow, runs a Python `bin/` script to generate `load_data.csv`, then runs CellProfiler headless. The main workflow handles all channel grouping/joining inline — no subworkflows for CSV generation. Analysis runs per-site with full feature extraction, feeding into CYTOTABLE for Parquet conversion.

**Tech Stack:** Nextflow DSL2, CellProfiler 4.2.8, Python 3 (stdlib only for bin/ scripts), nf-test, cytotable

---

## File Structure

### Files to create

- `bin/generate_illumination_calc_csv.py` — Reads metadata JSON, generates `load_data.csv` for illumination correction (single channel per group, one row per image)
- `bin/generate_illumination_apply_csv.py` — Reads metadata JSON + globs `.npy` files from images dir, generates `load_data.csv` with paired `FileName_Orig{ch}` / `FileName_Illum{ch}` columns. Used by both assay dev and analysis.

### Files to rewrite

- `workflows/cellpainting.nf` — Remove subworkflow imports, add inline channel grouping/joining, wire analysis + CYTOTABLE
- `modules/local/cellprofiler/illuminationcorrection/main.nf` — Accept `val(images_meta)` instead of `path(load_data_csv)`, generate CSV via bin/ script
- `modules/local/cellprofiler/assaydevelopment.nf` — Accept staged images + illum files + metadata, generate CSV via bin/ script, real CellProfiler command
- `modules/local/cellprofiler/analysis.nf` — Full rewrite from samtools stub to CellProfiler analysis module
- `modules/local/cytotable/main.nf` — Accept directory of CSVs instead of single CSV file

### Files to update

- `main.nf` — Pass `cellprofiler_assaydevelopment_site` param to workflow
- `nextflow.config` — Add `cellprofiler_assaydevelopment_site` param
- `conf/modules.config` — Add publish dirs for analysis and cytotable

### Files to delete

- `subworkflows/local/cellprofiler_load_data_csv/` (main.nf, meta.yml, tests/, tests/\*.snap)
- `subworkflows/local/cellprofiler_load_data_csv_with_illum/` (main.nf, meta.yml, tests/, tests/\*.snap)

### Files to update for tests

- `tests/default.nf.test` — Update assertions for new process structure
- `tests/.nftignore` (if exists) — Ensure analysis outputs are handled

---

## Task 1: Create `bin/generate_illumination_calc_csv.py`

**Files:**

- Create: `bin/generate_illumination_calc_csv.py`

- [ ] **Step 1: Create the script**

This script reads a metadata JSON and generates a `load_data.csv` for illumination correction. One channel per group, one row per image.

```python
#!/usr/bin/env python3
"""
Generate load_data.csv for CellProfiler illumination calculation.

Reads metadata JSON from Nextflow and generates a CSV with:
- FileName_Orig{channel} column
- Metadata columns (Batch, Plate, Well, Col, Row, Site)

Uses only Python standard library.
"""

import argparse
import csv
import json
import sys


def read_metadata_json(json_path):
    """Read and validate metadata JSON file."""
    with open(json_path, 'r') as f:
        data = json.load(f)

    if 'meta' not in data:
        raise ValueError("JSON must contain 'meta' key")
    if 'images' not in data:
        raise ValueError("JSON must contain 'images' key")
    if not data['images']:
        raise ValueError("images list is empty")

    return data


def generate_csv(data, output_file):
    """Generate load_data.csv from metadata."""
    meta = data['meta']
    images = data['images']
    channel = meta['channel']

    fieldnames = [
        f'FileName_Orig{channel}',
        'Metadata_Batch',
        'Metadata_Plate',
        'Metadata_Well',
        'Metadata_Col',
        'Metadata_Row',
        'Metadata_Site',
    ]

    with open(output_file, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()

        for img in images:
            writer.writerow({
                f'FileName_Orig{channel}': img['filename'],
                'Metadata_Batch': img['batch'],
                'Metadata_Plate': img['plate'],
                'Metadata_Well': img['well'],
                'Metadata_Col': img['col'],
                'Metadata_Row': img['row'],
                'Metadata_Site': img['site'],
            })

    print(f"Generated {output_file} with {len(images)} rows", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        description='Generate load_data.csv for CellProfiler illumination calculation'
    )
    parser.add_argument('--metadata', required=True, help='Path to metadata JSON file')
    parser.add_argument('--output', default='load_data.csv', help='Output CSV file path')

    args = parser.parse_args()

    data = read_metadata_json(args.metadata)
    generate_csv(data, args.output)


if __name__ == '__main__':
    main()
```

- [ ] **Step 2: Make script executable**

Run: `chmod +x bin/generate_illumination_calc_csv.py`

- [ ] **Step 3: Test script manually**

Run:

```bash
echo '{"meta":{"id":"b1_p1_DNA","batch":"b1","plate":"p1","channel":"DNA"},"images":[{"filename":"img1.tiff","batch":"b1","plate":"p1","well":"A01","col":1,"row":1,"site":1,"channel":"DNA"},{"filename":"img2.tiff","batch":"b1","plate":"p1","well":"A01","col":1,"row":1,"site":2,"channel":"DNA"}]}' > /tmp/test_illum_meta.json
python3 bin/generate_illumination_calc_csv.py --metadata /tmp/test_illum_meta.json --output /tmp/test_illum.csv
cat /tmp/test_illum.csv
```

Expected output:

```
FileName_OrigDNA,Metadata_Batch,Metadata_Plate,Metadata_Well,Metadata_Col,Metadata_Row,Metadata_Site
img1.tiff,b1,p1,A01,1,1,1
img2.tiff,b1,p1,A01,1,1,2
```

- [ ] **Step 4: Commit**

```bash
git add bin/generate_illumination_calc_csv.py
git commit -m "feat: add generate_illumination_calc_csv.py bin script"
```

---

## Task 2: Create `bin/generate_illumination_apply_csv.py`

**Files:**

- Create: `bin/generate_illumination_apply_csv.py`

- [ ] **Step 1: Create the script**

This script reads a metadata JSON for image info and globs `.npy` files from the images directory to generate a `load_data.csv` with paired original/illumination columns per channel. Used by both assay development and analysis.

```python
#!/usr/bin/env python3
"""
Generate load_data.csv for CellProfiler steps that apply illumination correction.

Reads metadata JSON for image info. Globs *.npy from images directory to find
illumination correction files. Matches illum files to channels by parsing
{plate}_Illum{channel}.npy filename pattern.

Generates CSV with paired columns: FileName_Orig{ch} / FileName_Illum{ch}
plus metadata columns.

Used by both assay development and analysis steps.
Uses only Python standard library.
"""

import argparse
import csv
import glob
import json
import os
import re
import sys


def read_metadata_json(json_path):
    """Read and validate metadata JSON file."""
    with open(json_path, 'r') as f:
        data = json.load(f)

    if 'meta' not in data:
        raise ValueError("JSON must contain 'meta' key")
    if 'images' not in data:
        raise ValueError("JSON must contain 'images' key")
    if not data['images']:
        raise ValueError("images list is empty")

    return data


def find_illumination_files(images_dir):
    """
    Find illumination .npy files and extract channel from filename.

    Expected pattern: {plate}_Illum{channel}.npy
    Returns dict: channel -> filename
    """
    npy_files = glob.glob(os.path.join(images_dir, "*.npy"))
    illum_by_channel = {}

    for npy_path in npy_files:
        filename = os.path.basename(npy_path)
        match = re.match(r'.+?_Illum(.+?)\.npy', filename)
        if match:
            channel = match.group(1)
            illum_by_channel[channel] = filename

    if not illum_by_channel:
        raise ValueError(
            f"No illumination .npy files found in {images_dir}. "
            f"Expected pattern: {{plate}}_Illum{{channel}}.npy"
        )

    print(f"Found illumination files for channels: {sorted(illum_by_channel.keys())}", file=sys.stderr)
    return illum_by_channel


def generate_csv(data, illum_by_channel, output_file):
    """
    Generate load_data.csv from metadata and illumination files.

    Groups images by (well, site) to create one row per field of view
    with all channels represented.
    """
    meta = data['meta']
    images = data['images']

    # Get unique channels from image metadata
    channels = sorted(set(img['channel'] for img in images))

    # Group images by (well, site)
    grouped = {}
    for img in images:
        key = (img['well'], img['site'])
        if key not in grouped:
            grouped[key] = {'meta': img, 'by_channel': {}}
        grouped[key]['by_channel'][img['channel']] = img['filename']

    # Build fieldnames: FileName_Orig{ch}, FileName_Illum{ch} for each channel, then metadata
    fieldnames = []
    for ch in channels:
        fieldnames.append(f'FileName_Orig{ch}')
    fieldnames.extend([
        'Metadata_Batch',
        'Metadata_Plate',
        'Metadata_Well',
        'Metadata_Col',
        'Metadata_Row',
        'Metadata_Site',
    ])
    for ch in channels:
        fieldnames.append(f'FileName_Illum{ch}')

    with open(output_file, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()

        for (well, site), group in sorted(grouped.items()):
            row = {
                'Metadata_Batch': group['meta']['batch'],
                'Metadata_Plate': group['meta']['plate'],
                'Metadata_Well': well,
                'Metadata_Col': group['meta']['col'],
                'Metadata_Row': group['meta']['row'],
                'Metadata_Site': site,
            }

            for ch in channels:
                row[f'FileName_Orig{ch}'] = group['by_channel'].get(ch, '')
                row[f'FileName_Illum{ch}'] = illum_by_channel.get(ch, '')

            writer.writerow(row)

    print(f"Generated {output_file} with {len(grouped)} rows, {len(channels)} channels", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        description='Generate load_data.csv for CellProfiler illumination application'
    )
    parser.add_argument('--metadata', required=True, help='Path to metadata JSON file')
    parser.add_argument('--images-dir', default='./images', help='Directory containing images and .npy files')
    parser.add_argument('--output', default='load_data.csv', help='Output CSV file path')

    args = parser.parse_args()

    data = read_metadata_json(args.metadata)
    illum_by_channel = find_illumination_files(args.images_dir)
    generate_csv(data, illum_by_channel, args.output)


if __name__ == '__main__':
    main()
```

- [ ] **Step 2: Make script executable**

Run: `chmod +x bin/generate_illumination_apply_csv.py`

- [ ] **Step 3: Test script manually**

Run:

```bash
mkdir -p /tmp/test_apply_images
touch /tmp/test_apply_images/p1_IllumDNA.npy
touch /tmp/test_apply_images/p1_IllumRNA.npy
echo '{"meta":{"id":"b1_p1_A01_1","batch":"b1","plate":"p1","well":"A01","site":1},"images":[{"filename":"img1.tiff","batch":"b1","plate":"p1","well":"A01","col":1,"row":1,"site":1,"channel":"DNA"},{"filename":"img2.tiff","batch":"b1","plate":"p1","well":"A01","col":1,"row":1,"site":1,"channel":"RNA"}]}' > /tmp/test_apply_meta.json
python3 bin/generate_illumination_apply_csv.py --metadata /tmp/test_apply_meta.json --images-dir /tmp/test_apply_images --output /tmp/test_apply.csv
cat /tmp/test_apply.csv
```

Expected output:

```
FileName_OrigDNA,FileName_OrigRNA,Metadata_Batch,Metadata_Plate,Metadata_Well,Metadata_Col,Metadata_Row,Metadata_Site,FileName_IllumDNA,FileName_IllumRNA
img1.tiff,img2.tiff,b1,p1,A01,1,1,1,p1_IllumDNA.npy,p1_IllumRNA.npy
```

- [ ] **Step 4: Commit**

```bash
git add bin/generate_illumination_apply_csv.py
git commit -m "feat: add generate_illumination_apply_csv.py bin script"
```

---

## Task 3: Rewrite `modules/local/cellprofiler/illuminationcorrection/main.nf`

**Files:**

- Modify: `modules/local/cellprofiler/illuminationcorrection/main.nf`

- [ ] **Step 1: Rewrite the module**

Replace the entire file. Key changes: accept `val(images_meta)` instead of `path(load_data_csv)`, generate CSV via bin/ script inside the process.

```groovy
process CELLPROFILER_ILLUMINATIONCORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/cellprofiler:4.2.8--pyhdfd78af_0'
        : 'community.wave.seqera.io/library/cellprofiler:4.2.8--aff0a99749304a7f'}"

    input:
    tuple val(meta), val(images_meta), path(images, stageAs: "images/*")
    path illumination_cppipe

    output:
    tuple val(meta), path("illumination_corrections/*.npy"), emit: illumination_corrections
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def metadata_json = groovy.json.JsonOutput.toJson([meta: meta, images: images_meta])
    """
    echo '${metadata_json}' > metadata.json
    generate_illumination_calc_csv.py --metadata metadata.json --output load_data.csv

    sed 's/{{channel}}/${meta.channel}/g' ${illumination_cppipe} > illumination.cppipe

    mkdir -p illumination_corrections

    cellprofiler -c -r \
    ${args} \
    -p illumination.cppipe \
    -o illumination_corrections \
    --data-file=load_data.csv \
    --image-directory ./images/ \
    -g Metadata_Plate=${meta.plate}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellprofiler: \$(cellprofiler --version)
    END_VERSIONS
    """

    stub:
    """
    mkdir -p illumination_corrections
    touch illumination_corrections/${meta.plate}_Illum${meta.channel}.npy

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellprofiler: stub
    END_VERSIONS
    """
}
```

- [ ] **Step 2: Commit**

```bash
git add modules/local/cellprofiler/illuminationcorrection/main.nf
git commit -m "refactor: illumination correction to use metadata JSON + bin script"
```

---

## Task 4: Rewrite `modules/local/cellprofiler/assaydevelopment.nf`

**Files:**

- Modify: `modules/local/cellprofiler/assaydevelopment.nf`

- [ ] **Step 1: Rewrite the module**

Replace the entire file. Key changes: accept staged images + illum files + images_meta, generate CSV via bin/ script, run real CellProfiler command.

```groovy
process CELLPROFILER_ASSAYDEVELOPMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/cellprofiler:4.2.8--pyhdfd78af_0'
        : 'community.wave.seqera.io/library/cellprofiler:4.2.8--aff0a99749304a7f'}"

    input:
    tuple val(meta), val(images_meta), path(images, stageAs: "images/*"), path(illum_files, stageAs: "images/*")
    path assay_development_cppipe

    output:
    tuple val(meta), path("assaydevelopment/*.png"), emit: png
    tuple val(meta), path("assaydevelopment/Image.csv"), emit: csv, optional: true
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def metadata_json = groovy.json.JsonOutput.toJson([meta: meta, images: images_meta])
    """
    echo '${metadata_json}' > metadata.json
    generate_illumination_apply_csv.py --metadata metadata.json --images-dir ./images --output load_data.csv

    mkdir -p assaydevelopment

    cellprofiler -c -r \
    ${args} \
    -p ${assay_development_cppipe} \
    -o assaydevelopment \
    --data-file=load_data.csv \
    --image-directory ./images/ \
    -g Metadata_Plate=${meta.plate},Metadata_Well=${meta.well}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellprofiler: \$(cellprofiler --version)
    END_VERSIONS
    """

    stub:
    """
    mkdir -p assaydevelopment
    echo 'stub' > assaydevelopment/mock_segmentedimage.png
    echo 'ImageNumber,Metadata_Plate' > assaydevelopment/Image.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellprofiler: stub
    END_VERSIONS
    """
}
```

- [ ] **Step 2: Commit**

```bash
git add modules/local/cellprofiler/assaydevelopment.nf
git commit -m "refactor: assay development to use metadata JSON + bin script"
```

---

## Task 5: Rewrite `modules/local/cellprofiler/analysis.nf`

**Files:**

- Modify: `modules/local/cellprofiler/analysis.nf`

- [ ] **Step 1: Rewrite the module**

Replace the entire samtools stub with a real CellProfiler analysis module. Per-site execution, outputs multiple CSVs + PNGs.

```groovy
process CELLPROFILER_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/cellprofiler:4.2.8--pyhdfd78af_0'
        : 'community.wave.seqera.io/library/cellprofiler:4.2.8--aff0a99749304a7f'}"

    input:
    tuple val(meta), val(images_meta), path(images, stageAs: "images/*"), path(illum_files, stageAs: "images/*")
    path analysis_cppipe

    output:
    tuple val(meta), path("analysis"), emit: output_dir
    tuple val(meta), path("analysis/*.png"), emit: pngs, optional: true
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def metadata_json = groovy.json.JsonOutput.toJson([meta: meta, images: images_meta])
    """
    echo '${metadata_json}' > metadata.json
    generate_illumination_apply_csv.py --metadata metadata.json --images-dir ./images --output load_data.csv

    mkdir -p analysis

    cellprofiler -c -r \
    ${args} \
    -p ${analysis_cppipe} \
    -o analysis \
    --data-file=load_data.csv \
    --image-directory ./images/ \
    -g Metadata_Plate=${meta.plate},Metadata_Well=${meta.well},Metadata_Site=${meta.site}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellprofiler: \$(cellprofiler --version)
    END_VERSIONS
    """

    stub:
    """
    mkdir -p analysis
    echo 'ImageNumber,Metadata_Plate' > analysis/Image.csv
    echo 'ImageNumber,ObjectNumber' > analysis/Nuclei.csv
    echo 'ImageNumber,ObjectNumber' > analysis/Cells.csv
    echo 'ImageNumber,ObjectNumber' > analysis/Cytoplasm.csv
    touch analysis/mock_overlay.png

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellprofiler: stub
    END_VERSIONS
    """
}
```

- [ ] **Step 2: Commit**

```bash
git add modules/local/cellprofiler/analysis.nf
git commit -m "feat: implement CellProfiler analysis module with per-site execution"
```

---

## Task 6: Rewrite `modules/local/cytotable/main.nf`

**Files:**

- Modify: `modules/local/cytotable/main.nf`

- [ ] **Step 1: Update CYTOTABLE to accept a directory**

Change the input from a single CSV file to a directory of CellProfiler CSVs.

```groovy
process CYTOTABLE {

    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://community.wave.seqera.io/library/pip_cytotable:75a940a0fcae75db' :
        'community.wave.seqera.io/library/pip_cytotable:e5e76f6f7c7bea96'
    }

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
current_dir = os.getcwd()
os.environ["HOME"] = current_dir

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
}
```

- [ ] **Step 2: Commit**

```bash
git add modules/local/cytotable/main.nf
git commit -m "refactor: cytotable to accept directory of CellProfiler CSVs"
```

---

## Task 7: Delete old CSV generation subworkflows

**Files:**

- Delete: `subworkflows/local/cellprofiler_load_data_csv/main.nf`
- Delete: `subworkflows/local/cellprofiler_load_data_csv/meta.yml`
- Delete: `subworkflows/local/cellprofiler_load_data_csv/tests/` (all files)
- Delete: `subworkflows/local/cellprofiler_load_data_csv_with_illum/main.nf`
- Delete: `subworkflows/local/cellprofiler_load_data_csv_with_illum/meta.yml`
- Delete: `subworkflows/local/cellprofiler_load_data_csv_with_illum/tests/` (all files)

- [ ] **Step 1: Remove both subworkflow directories**

Run:

```bash
rm -rf subworkflows/local/cellprofiler_load_data_csv
rm -rf subworkflows/local/cellprofiler_load_data_csv_with_illum
```

- [ ] **Step 2: Commit**

```bash
git add -u subworkflows/local/cellprofiler_load_data_csv subworkflows/local/cellprofiler_load_data_csv_with_illum
git commit -m "refactor: remove CSV generation subworkflows (replaced by bin scripts)"
```

---

## Task 8: Add `cellprofiler_assaydevelopment_site` parameter

**Files:**

- Modify: `nextflow.config`
- Modify: `main.nf`

- [ ] **Step 1: Add param to `nextflow.config`**

Add after the `cellprofiler_analysis_cppipe` line:

```groovy
    cellprofiler_assaydevelopment_site = 1
```

- [ ] **Step 2: Update `main.nf` to pass the param**

In the `NFCORE_CELLPAINTING` workflow, update the `CELLPAINTING` call to pass the new param:

```groovy
    CELLPAINTING (
        samplesheet,
        params.cellprofiler_mode,
        params.cellprofiler_illumination_cppipe,
        params.cellprofiler_assaydevelopment_cppipe,
        params.cellprofiler_assaydevelopment_site,
        params.cellprofiler_analysis_cppipe
    )
```

- [ ] **Step 3: Commit**

```bash
git add nextflow.config main.nf
git commit -m "feat: add cellprofiler_assaydevelopment_site parameter"
```

---

## Task 9: Rewrite `workflows/cellpainting.nf`

**Files:**

- Modify: `workflows/cellpainting.nf`

This is the largest task. The workflow removes all subworkflow imports for CSV generation and replaces them with inline channel operations.

- [ ] **Step 1: Rewrite the workflow**

Replace the entire file:

```groovy
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { CYTOTABLE              } from '../modules/local/cytotable'
include { CELLPROFILER_ILLUMINATIONCORRECTION } from '../modules/local/cellprofiler/illuminationcorrection'
include { CELLPROFILER_ANALYSIS } from '../modules/local/cellprofiler/analysis.nf'
include { CELLPROFILER_ASSAYDEVELOPMENT } from '../modules/local/cellprofiler/assaydevelopment.nf'

include { paramsSummaryMap       } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_cellpainting_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow CELLPAINTING {

    take:
    ch_samplesheet // channel: images read in from --input samplesheet
    cellprofiler_mode // value: assay_development, analysis
    cellprofiler_illumination_cppipe // value: path to illumination cppipe
    cellprofiler_assaydevelopment_cppipe // value: path to assaydevelopment cppipe
    cellprofiler_assaydevelopment_site // value: site number for assay development
    cellprofiler_analysis_cppipe // value: path to analysis cppipe

    main:

    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

    //
    // Enrich samplesheet with filename metadata
    //
    ch_samplesheet
        .map { meta, image ->
            def image_meta = meta.clone()
            image_meta.filename = image.name
            [image_meta, image]
        }
        .set { ch_enriched }

    //
    // ILLUMINATION CORRECTION
    // Group by [batch, plate, channel], carry per-image metadata
    //
    ch_enriched
        .map { meta, image ->
            def group_key = meta.subMap(['batch', 'plate', 'channel'])
            def group_id = [meta.batch, meta.plate, meta.channel].join('_')
            [group_key + [id: group_id], meta, image]
        }
        .groupTuple()
        .set { ch_illumination_images }

    CELLPROFILER_ILLUMINATIONCORRECTION(
        ch_illumination_images,
        cellprofiler_illumination_cppipe
    )

    ch_versions = ch_versions.mix(CELLPROFILER_ILLUMINATIONCORRECTION.out.versions)

    //
    // Flatten illumination corrections to plate level
    //
    CELLPROFILER_ILLUMINATIONCORRECTION.out.illumination_corrections
        .map { meta, npy_files ->
            def plate_key = [meta.batch, meta.plate].join('_')
            [plate_key, npy_files]
        }
        .groupTuple()
        .map { key, npy_lists -> [key, npy_lists.flatten()] }
        .set { ch_illum_by_plate }

    if (cellprofiler_mode == 'assay_development') {

        //
        // ASSAY DEVELOPMENT
        // Group by [batch, plate, well], filter to single site, join with illum
        //
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

        CELLPROFILER_ASSAYDEVELOPMENT(
            ch_assay_dev_with_illum,
            cellprofiler_assaydevelopment_cppipe
        )

        ch_versions = ch_versions.mix(CELLPROFILER_ASSAYDEVELOPMENT.out.versions)

    }

    if (cellprofiler_mode == 'analysis') {

        //
        // ANALYSIS
        // Group by [batch, plate, well, site], join with illum
        //
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

        CELLPROFILER_ANALYSIS(
            ch_analysis_with_illum,
            cellprofiler_analysis_cppipe
        )

        ch_versions = ch_versions.mix(CELLPROFILER_ANALYSIS.out.versions)

        //
        // CYTOTABLE - convert analysis CSVs to Parquet
        //
        CYTOTABLE(
            CELLPROFILER_ANALYSIS.out.output_dir
        )

    }

    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_'  +  'cellpainting_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }

    //
    // MODULE: MultiQC
    //
    ch_multiqc_config        = Channel.fromPath(
        "$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_custom_config = params.multiqc_config ?
        Channel.fromPath(params.multiqc_config, checkIfExists: true) :
        Channel.empty()
    ch_multiqc_logo          = params.multiqc_logo ?
        Channel.fromPath(params.multiqc_logo, checkIfExists: true) :
        Channel.empty()

    summary_params      = paramsSummaryMap(
        workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary = Channel.value(paramsSummaryMultiqc(summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_custom_methods_description = params.multiqc_methods_description ?
        file(params.multiqc_methods_description, checkIfExists: true) :
        file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = Channel.value(
        methodsDescriptionText(ch_multiqc_custom_methods_description))

    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_methods_description.collectFile(
            name: 'methods_description_mqc.yaml',
            sort: true
        )
    )

    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList(),
        [],
        []
    )

    emit:
    multiqc_report = MULTIQC.out.report.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
```

- [ ] **Step 2: Commit**

```bash
git add workflows/cellpainting.nf
git commit -m "refactor: rewrite workflow with inline channel ops and analysis step"
```

---

## Task 10: Update `conf/modules.config`

**Files:**

- Modify: `conf/modules.config`

- [ ] **Step 1: Add publish dir configs for analysis and cytotable**

Add process-specific publish dirs:

```groovy
process {

    publishDir = [
        path: { "${params.outdir}/${task.process.tokenize(':')[-1].tokenize('_')[0].toLowerCase()}" },
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename.equals('versions.yml') ? null : filename }
    ]

    withName: 'CELLPROFILER_ANALYSIS' {
        publishDir = [
            path: { "${params.outdir}/cellprofiler/analysis" },
            mode: params.publish_dir_mode,
            saveAs: { filename -> filename.equals('versions.yml') ? null : filename }
        ]
    }

    withName: 'CYTOTABLE' {
        publishDir = [
            path: { "${params.outdir}/cytotable" },
            mode: params.publish_dir_mode,
            saveAs: { filename -> filename.equals('versions.yml') ? null : filename }
        ]
    }

    withName: 'MULTIQC' {
        ext.args   = { params.multiqc_title ? "--title \"$params.multiqc_title\"" : '' }
        publishDir = [
            path: { "${params.outdir}/multiqc" },
            mode: params.publish_dir_mode,
            saveAs: { filename -> filename.equals('versions.yml') ? null : filename }
        ]
    }

}
```

- [ ] **Step 2: Commit**

```bash
git add conf/modules.config
git commit -m "feat: add publish dir config for analysis and cytotable"
```

---

## Task 11: Update tests

**Files:**

- Modify: `tests/default.nf.test`

- [ ] **Step 1: Update the nf-test**

The test currently runs with `cellprofiler_mode = "analysis"` and uses `-stub`. The workflow structure has changed (no subworkflows, new processes), so the snapshot needs regenerating. The test itself stays similar — it validates workflow success and snapshots output structure.

No code changes needed to `default.nf.test` — the test structure is already correct. It runs with `cellprofiler_mode = "analysis"` which will exercise the new analysis path.

- [ ] **Step 2: Delete old snapshot**

Run:

```bash
rm -f tests/default.nf.test.snap
```

- [ ] **Step 3: Regenerate snapshot**

Run:

```bash
nf-test test tests/default.nf.test --profile test,docker --update-snapshot
```

Expected: Test passes with `-stub`, new snapshot is generated reflecting the updated process structure.

- [ ] **Step 4: Commit**

```bash
git add tests/default.nf.test.snap
git commit -m "test: regenerate snapshots for refactored pipeline"
```

---

## Task 12: Verify full pipeline in stub mode

**Files:** None (verification only)

- [ ] **Step 1: Run pipeline in stub mode with analysis**

Run:

```bash
nextflow run main.nf -profile test,docker -stub --outdir results_analysis --cellprofiler_mode analysis
```

Expected: Pipeline completes successfully. All processes run as stubs. Output directory has:

- `cellprofiler/analysis/` — stub CSVs and PNG
- `cytotable/` — stub parquet (may not produce output in stub mode, which is acceptable)
- `multiqc/` — MultiQC report
- `pipeline_info/` — execution reports

- [ ] **Step 2: Run pipeline in stub mode with assay_development**

Run:

```bash
nextflow run main.nf -profile test,docker -stub --outdir results_assaydev --cellprofiler_mode assay_development
```

Expected: Pipeline completes successfully with assay development path.

- [ ] **Step 3: Run nf-test**

Run:

```bash
nf-test test tests/default.nf.test --profile test,docker
```

Expected: All tests pass against the new snapshots.
