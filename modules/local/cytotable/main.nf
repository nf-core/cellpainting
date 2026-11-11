process CYTOTABLE {
    tag "${meta.batch}_${meta.plate}"
    label 'process_medium'

    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://community.wave.seqera.io/library/pip_cytotable:9ab5556a2d37fe91' :
        'community.wave.seqera.io/library/pip_cytotable:b10ffccc482ad53a'
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

# Custom join which keeps genuine Image-table metadata (well/plate/site,
# channel/position metadata, and file/path provenance) without also pulling
# in the ~1,900 per-image QC columns (ImageQuality_*, ExecutionTime_*, etc.)
# that cellprofiler_csv's default preset also drops — those are diagnostic
# measurements, not metadata, and keeping them duplicated onto every cell row
# bloats the join's memory footprint substantially for no benefit.
custom_join = '''
    SELECT
        image.Metadata_ImageNumber,
        image.Metadata_Well,
        image.Metadata_Plate,
        image.Metadata_Site,
        image.Metadata_Col,
        image.Metadata_Row,
        COLUMNS('Image_(Metadata|FileName|PathName)_.*'),
        cytoplasm.* EXCLUDE (Metadata_ImageNumber),
        cells.* EXCLUDE (Metadata_ImageNumber, Metadata_ObjectNumber),
        nuclei.* EXCLUDE (Metadata_ImageNumber, Metadata_ObjectNumber)
    FROM
        read_parquet('cytoplasm.parquet') AS cytoplasm
    LEFT JOIN read_parquet('cells.parquet') AS cells USING (Metadata_ImageNumber)
    LEFT JOIN read_parquet('nuclei.parquet') AS nuclei USING (Metadata_ImageNumber)
    LEFT JOIN read_parquet('image.parquet') AS image USING (Metadata_ImageNumber)
    WHERE
        cells.Metadata_ObjectNumber = cytoplasm.Metadata_Cytoplasm_Parent_Cells
        AND nuclei.Metadata_ObjectNumber = cytoplasm.Metadata_Cytoplasm_Parent_Nuclei
'''

convert(
    source_path="analyses",
    source_datatype="csv",
    dest_path="temp_output.parquet",
    dest_datatype="parquet",
    preset="cellprofiler_csv",
    joins=custom_join,
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

# Rewrite the joined table with Image_-prefixed metadata columns renamed to
# plain Metadata_ columns (Image_Metadata_Well -> Metadata_Well) so the output
# follows the Pycytominer single-table metadata convention. pyarrow (already a
# cytotable dependency) is used so no extra container packages are needed.
table = pq.read_table("temp_output.parquet")
renames = {
    col: col.replace("Image_Metadata_", "Metadata_")
    for col in table.column_names
    if col.startswith("Image_Metadata_")
}
if renames:
    table = table.rename_columns([renames.get(col, col) for col in table.column_names])

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
        cytotable: 1.2.6
    END_VERSIONS
    """
}
