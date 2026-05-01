process CYTOTABLE_METADATA {

    tag "${meta.batch}_${meta.plate}_${meta.well}_${meta.site}"
    label 'process_single'

    // conda "${moduleDir}/environment.yml"
    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://community.wave.seqera.io/library/pip_marimo_nbconvert_pyarrow_seaborn:470760039a5aa5d9' :
        'community.wave.seqera.io/library/pip_marimo_nbconvert_pyarrow_seaborn:470760039a5aa5d9'
    }

    input:
    tuple val(meta), path(parquet_file)

    output:
    tuple val(meta), path("*_metadata.py")         , emit: app
    tuple val(meta), path("*_metadata.json")       , emit: json
    tuple val(meta), path("*_metadata.ipynb")      , emit: notebook, optional: true
    tuple val(meta), path("*_metadata.html")       , emit: html, optional: true
    tuple val(meta), path("*_metadata.md")         , emit: markdown, optional: true
    path "versions.yml"                            , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = "${meta.batch}_${meta.plate}_${meta.well}_${meta.site}"
    def convert_html = task.ext.convert_html ?: false
    def export_ipynb = task.ext.export_ipynb ?: false
    def export_markdown = task.ext.export_markdown ?: false
    """
    # Copy the marimo app with proper prefix
    cp ${moduleDir}/parquet_metadata.py ${prefix}_metadata.py
    
    # Export to HTML (this also executes the code)
    marimo export html ${prefix}_metadata.py \\
        -o ${prefix}_metadata.html \\
        -- \\
        --parquet-file ${parquet_file} \\
        --output-json ${prefix}_metadata.json \\
        ${args}

    # Optionally also export to ipynb
    if [ "${export_ipynb}" = "true" ]; then
        marimo export ipynb ${prefix}_metadata.py -o ${prefix}_metadata.ipynb || echo "Warning: ipynb export failed (nbformat may not be installed)"
    fi

    # Optionally also export to markdown
    if [ "${export_markdown}" = "true" ]; then
        marimo export md ${prefix}_metadata.py -o ${prefix}_metadata.md || echo "Warning: markdown export failed"
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        marimo: \$(marimo --version 2>&1 | awk '{print \$2}' || echo "unknown")
        python: \$(python --version 2>&1 | awk '{print \$2}')
        pandas: \$(python -c "import pandas; print(pandas.__version__)")
    END_VERSIONS
    """

    stub:
    def prefix = "${meta.batch}_${meta.plate}_${meta.well}_${meta.site}"
    """
    touch ${prefix}_metadata.py
    touch ${prefix}_metadata.ipynb
    touch ${prefix}_metadata.html
    touch ${prefix}_metadata.md
    touch ${prefix}_metadata.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        marimo: stub
        python: stub
        pandas: stub
    END_VERSIONS
    """
}
