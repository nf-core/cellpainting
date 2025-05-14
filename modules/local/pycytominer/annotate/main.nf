
process PYCYTOMINER_ANNOTATE {
    tag "${profile_parquet_input}, ${platemap_metadata}"
    label 'process_low'
    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/pip_pycytominer:805fce2d9d298cea':
        'biocontainers/pip_pycytominer:805fce2d9d298cea' }"

    input:
        path(profile_parquet_input)
        path(platemap_metadata)
    output:
        path("${profile_parquet_input.baseName}_annotated.parquet"), emit: annotated_parquet
    when:
        task.ext.when == null || task.ext.when

    script:
    """
    python ${baseDir}/modules/local/pycytominer/annotate/pycytominer_annotate.py --profile ${profile_parquet_input} --platemap ${platemap_metadata} --mergeKeys "${params.mergeKeys}" --outputType "${params.outputType}"
    """

    stub:
    """
    touch ${profile_parquet_input.baseName}_annotated.parquet

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        stub: true
        note: "Stub executed in place of real pycytominer annotate"
    END_VERSIONS
    """
}


