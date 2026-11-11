process PYCYTOMINER_ANNO {
    tag "${meta.batch}_${meta.plate}"
    label 'process_single'

    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://community.wave.seqera.io/library/pip_pycytominer:0325c7e8bab7250e' :
        'community.wave.seqera.io/library/pip_pycytominer:411cd39ba25e6994'
    }

    input:
    tuple val(meta), path(cytotable_parquet), path(platemap_csv)

    output:
    tuple val(meta), path("*_anno.parquet"), emit: parquet
    tuple val("${task.process}"), val('pycytominer'), eval("python -c \"import importlib.metadata as im; print(im.version('pycytominer'))\""), topic: versions, emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    """
    pycytominer annotate \\
        --profiles ${cytotable_parquet} \\
        --platemap ${platemap_csv} \\
        --output_type parquet \\
        --output_file ${meta.batch}_${meta.plate}_anno.parquet \\
        --join_on "${params.pycytominer_annotation_join_on}" \\
        ${args}
    """

    stub:
    """
    touch ${meta.batch}_${meta.plate}_anno.parquet
    """
}
