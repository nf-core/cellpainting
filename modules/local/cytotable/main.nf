process CYTOTABLE {
    tag "${meta.batch}_${meta.plate}"
    label 'process_medium'

    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://community.wave.seqera.io/library/python_pip_cytotable_duckdb:f302838336b9161f' :
        'community.wave.seqera.io/library/python_pip_cytotable_duckdb:45640327546360eb'
    }

    input:
    // Rename each input dir to a unique number (no '/*' glob) so each staged
    // source keeps its CSV filenames distinct from its siblings. The
    // intermediate-parquet path collision this also worked around
    // (https://github.com/cytomining/CytoTable/issues/442) was fixed upstream
    // in CytoTable 1.2.2, but unique per-source staging names remain required
    // so same-named CSVs from different sites never overwrite each other.
    tuple val(meta), path(cellprofiler_output_dirs, stageAs: "analyses/?")

    output:
    tuple val(meta), path("*.parquet"),    emit: parquet
    tuple val(meta), path("*_stats.json"), emit: stats
    path "versions.yml",                   emit: versions

    script:
    """
#!/usr/bin/env python

import os

from cytotable import convert
from parsl.config import Config
from parsl.executors import ThreadPoolExecutor

import pyarrow.parquet as pq

os.environ["HOME"] = os.getcwd()

# Let CytoTable infer the join SQL from the source table data (joins="infer",
# CytoTable >= 1.3.0, https://github.com/cytomining/CytoTable/pull/523) instead
# of hand-writing a join. Inference detects the shared image keys, compartment
# object numbers, and Parent_* references, validates them against the actual
# data, and raises a clear error if no defensible join exists. identifying_columns
# is still passed explicitly so the well/plate/site metadata keys we rely on
# downstream keep their plain Metadata_* names (CytoTable would otherwise
# prefix them Image_Metadata_* as it does for any non-identifying Image column).
convert(
    source_path="analyses",
    source_datatype="csv",
    dest_path="temp_output.parquet",
    dest_datatype="parquet",
    preset="cellprofiler_csv",
    joins="infer",
    identifying_columns=[
        "ImageNumber",
        "ObjectNumber",
        "Metadata_Well",
        "Metadata_Plate",
        "Metadata_Site",
        "Metadata_Col",
        "Metadata_Row",
        "Parent_Cells",
        "Parent_Nuclei",
    ],
    parsl_config=Config(
        executors=[ThreadPoolExecutor(max_threads=${task.cpus})],
    ),
)

# Inferred joins select every column from each source table (unlike a
# hand-written join, inference has no way to know which Image-table columns
# matter downstream), which pulls in ~1,900 per-image QC columns
# (ImageQuality_*, Image_ExecutionTime_*, Image_Count_*, etc.) that are
# diagnostic measurements, not metadata. Drop them here, keeping only the
# Image-table columns that are genuine metadata or file/path provenance.
table = pq.read_table("temp_output.parquet")
keep_image_prefixes = ("Image_Metadata_", "Image_FileName_", "Image_PathName_")
drop_columns = [
    col
    for col in table.column_names
    if (col.startswith("Image_") or col.startswith("ImageQuality_"))
    and not col.startswith(keep_image_prefixes)
]
if drop_columns:
    table = table.drop_columns(drop_columns)

pq.write_table(table, "${meta.batch}_${meta.plate}.parquet", compression="snappy")

# QC stats: structural summary of the joined profile, grouped by measurement
# source so downstream users can sanity-check that every compartment/metadata
# group is present and non-empty without opening the (potentially large)
# Parquet file itself.
import json
import re
from collections import Counter

prefix_counts = Counter()
for col in table.column_names:
    match = re.match(r"^([A-Za-z]+)_", col)
    prefix_counts[match.group(1) if match else col] += 1

stats = {
    "num_rows": table.num_rows,
    "num_columns": table.num_columns,
    "num_cells": table.num_rows,
    "compartment_columns": dict(prefix_counts),
}
with open("${meta.batch}_${meta.plate}_stats.json", "w") as f:
    json.dump(stats, f, indent=2, sort_keys=True)

import importlib.metadata as im

with open("versions.yml", "w") as f:
    f.write("${task.process}:\\n")
    f.write("    cytotable: " + im.version("cytotable") + "\\n")
    """

    stub:
    """
    touch ${meta.batch}_${meta.plate}.parquet
    cat <<-END_STATS > ${meta.batch}_${meta.plate}_stats.json
    {
        "num_rows": 0,
        "num_columns": 0,
        "num_cells": 0,
        "compartment_columns": {}
    }
    END_STATS
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cytotable: 1.3.0
    END_VERSIONS
    """
}
