process PYCYTOMINER_ANNO {
    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/pip_pycytominer:805fce2d9d298cea' :
        'docker.io/cytomining/pycytominer:latest'
    }

    input:
    tuple val(meta), path(cytotable_parquet)
    path(meta_table_csv)

    output:
    tuple val(meta), path("*.parquet")

    script:
    """
    pycytominer annotate \\
        --profiles $cytotable_parquet \\
        --platemap $meta_table_csv \\
        --output_type parquet \\
        --output_file ${meta.batch}_${meta.plate}_${meta.well}_${meta.site}_anno.parquet \\
        --join_on Metadata_Well,Metadata_Well
    """

    stub:
    """
    touch ${meta.batch}_${meta.plate}_${meta.well}_${meta.site}_anno.parquet
    """
}
