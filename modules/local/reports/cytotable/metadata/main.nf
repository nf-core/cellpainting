process CYTOTABLE_METADATA {

    tag "${meta.batch}_${meta.plate}_${meta.well}_${meta.site}"
    label 'process_single'

    // conda "${moduleDir}/environment.yml"
    container "docker.io/dabbleofdevops/papermill-notebook:latest"

    input:
    tuple val(meta), path(parquet_file)

    output:
    tuple val(meta), path("*.ipynb")               , emit: notebook
    tuple val(meta), path("*_metadata.json")       , emit: json
    tuple val(meta), path("*.html")                , emit: html, optional: true
    path "versions.yml"                            , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = "${meta.batch}_${meta.plate}_${meta.well}_${meta.site}"
    def convert_html = task.ext.convert_html ?: false
    """
    # Run papermill to execute the notebook with parameters
    papermill ${moduleDir}/parquet_metadata.ipynb \\
        ${prefix}_metadata.ipynb \\
        -p parquet_file ${parquet_file} \\
        -p output_json ${prefix}_metadata.json \\
        ${args}

    # Optionally convert to HTML
    if [ "${convert_html}" = "true" ]; then
        jupyter nbconvert --to html ${prefix}_metadata.ipynb
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        papermill: \$(papermill --version 2>&1 | head -1 || echo "unknown")
        python: \$(python --version 2>&1 | awk '{print \$2}')
        pandas: \$(python -c "import pandas; print(pandas.__version__)")
    END_VERSIONS
    """

    stub:
    def prefix = "${meta.batch}_${meta.plate}_${meta.well}_${meta.site}"
    """
    touch ${prefix}_metadata.ipynb
    touch ${prefix}_metadata.html
    touch ${prefix}_metadata.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        papermill: stub
        python: stub
        pandas: stub
    END_VERSIONS
    """
}
