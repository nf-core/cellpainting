process CYTOTABLE {

    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://community.wave.seqera.io/library/pip_cytotable:75a940a0fcae75db' :
        'community.wave.seqera.io/library/pip_cytotable:e5e76f6f7c7bea96'
    }

    input:
    tuple val(meta), path(cellprofiler_output)

    output:
    tuple val(meta), path("*.parquet")

    script:
    """
#!/usr/bin/env python

from cytotable import convert

import os
current_dir = os.getcwd()
os.environ["HOME"] = current_dir

# using a local path with cellprofiler csv presets
convert(
    source_path="$cellprofiler_output",
    source_datatype="csv",
    dest_path="${meta.batch}_${meta.plate}_${meta.well}.parquet",
    dest_datatype="parquet",
    preset="cellprofiler_csv",
)
    """
}
