params.cellprofiler_output = "/data/hps/assoc/private/rsc/user/ybae/RSC/nextflow/cellpainting/test/cytotable/test-datasets/minimal_dataset/cpg0016-jump/source_4/workspace/analysis/2021_04_26_Batch1/BR00117035/analysis/BR00117035-A01-1"
params.meta = [batch: 'test_batch', plate: 'P1', well: 'A01']

process CYTOTABLE {
    container "oras://community.wave.seqera.io/library/pip_cytotable:75a940a0fcae75db"

    input:
    tuple val(meta), path(cellprofiler_ouput)

    output: 
    tuple val(meta), path("*.parquet")

    script:
    """
#!/usr/bin/env python

from cytotable import convert

# using a local path with cellprofiler csv presets
convert(
    source_path="$cellprofiler_ouput",
    source_datatype="csv",
    dest_path="${meta.batch}_${meta.plate}_${meta.well}.parquet",
    dest_datatype="parquet",
    preset="cellprofiler_csv",
)
    """
}

workflow {
    channel.of(params.meta)
        .set{meta}

    channel.of(params.cellprofiler_output)
        .set{cellprofiler_output}

    meta
        .combine(cellprofiler_output)
        .set{meta_cellprofiler_output}

    CYTOTABLE(meta_cellprofiler_output)    
}