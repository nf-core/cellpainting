process CYTOTABLE {

    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://community.wave.seqera.io/library/pip_cytotable:75a940a0fcae75db' :
        'community.wave.seqera.io/library/pip_cytotable:e5e76f6f7c7bea96'
    }

    // TODO: remove once https://github.com/cytomining/CytoTable/issues/440 is fixed (tracked in #42)
    stageInMode 'copy'

    input:
    tuple val(meta), path(cellprofiler_output_dirs, stageAs: "analyses/?/*")

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
    source_path="analyses",
    source_datatype="csv",
    dest_path="${meta.batch}_${meta.plate}.parquet",
    dest_datatype="parquet",
    preset="cellprofiler_csv",
    parsl_config=Config(
        executors=[ThreadPoolExecutor(max_threads=${task.cpus})],
    )
)
    """

    stub:
    """
    touch ${meta.batch}_${meta.plate}.parquet
    """
}
