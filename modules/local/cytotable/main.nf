process CYTOTABLE {

    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://community.wave.seqera.io/library/pip_cytotable:75a940a0fcae75db' :
        'community.wave.seqera.io/library/pip_cytotable:e5e76f6f7c7bea96'
    }

    input:
    tuple val(meta), path(cellprofiler_output_dir)

    output:
    tuple val(meta), path("*.parquet"),     emit: parquet
    tuple val(meta), path("*_stats.json"),  emit: stats

    script:
    def basename = "${meta.batch}_${meta.plate}_${meta.well}_${meta.site}"
    """
#!/usr/bin/env python

import json
import os
import re

from cytotable import convert
from parsl.config import Config
from parsl.executors import ThreadPoolExecutor
import pyarrow.parquet as pq

current_dir = os.getcwd()
os.environ["HOME"] = current_dir

dest_path  = "${basename}.parquet"
stats_path = "${basename}_stats.json"

convert(
    source_path="${cellprofiler_output_dir}",
    source_datatype="csv",
    dest_path=dest_path,
    dest_datatype="parquet",
    preset="cellprofiler_csv",
    parsl_config=Config(
        executors=[ThreadPoolExecutor(max_threads=${task.cpus})],
    ),
)

parquet_metadata = pq.read_metadata(dest_path)
column_names = parquet_metadata.schema.to_arrow_schema().names

# \$ is Nextflow's dollar-escape; Python re sees a bare $ (end-of-string anchor).
channel_pattern = re.compile(r"^Cells_Intensity_MeanIntensity_([A-Za-z0-9]+)\$")
channels = {m.group(1) for name in column_names for m in [channel_pattern.match(name)] if m}

stats = {
    "metadata": {
        "batch": "${meta.batch}",
        "plate": "${meta.plate}",
        "well":  "${meta.well}",
        "site":  "${meta.site}",
    },
    "num_cells":    parquet_metadata.num_rows,
    "num_channels": len(channels),
    "num_columns":  parquet_metadata.num_columns,
}

with open(stats_path, "w") as f:
    json.dump(stats, f, indent=2, sort_keys=True)
    """

    stub:
    def basename = "${meta.batch}_${meta.plate}_${meta.well}_${meta.site}"
    """
    touch ${basename}.parquet
    cat > ${basename}_stats.json <<'JSON'
    {
      "metadata": {
        "batch": "${meta.batch}",
        "plate": "${meta.plate}",
        "well":  "${meta.well}",
        "site":  "${meta.site}"
      },
      "num_cells": 0,
      "num_channels": 0,
      "num_columns": 0
    }
    JSON
    """
}
