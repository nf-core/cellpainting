process CYTOTABLE_DESCRIPTIVESTATS {

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
    tuple val(meta), path("*_stats.py")                   , emit: app
    tuple val(meta), path("*_descriptive_stats.parquet")  , emit: stats
    tuple val(meta), path("*_stats.ipynb")                , emit: notebook, optional: true
    tuple val(meta), path("*_size_distributions.png")     , emit: size_plot, optional: true
    tuple val(meta), path("*_dna_intensity.png")          , emit: dna_plot, optional: true
    tuple val(meta), path("*_stats.html")                 , emit: html, optional: true
    tuple val(meta), path("*_stats.md")                   , emit: markdown, optional: true
    path "versions.yml"                                   , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = "${meta.batch}_${meta.plate}_${meta.well}_${meta.site}"
    def n_head_rows = task.ext.n_head_rows ?: 10
    def convert_html = task.ext.convert_html ?: false
    def export_ipynb = task.ext.export_ipynb ?: false
    def export_markdown = task.ext.export_markdown ?: false
    """
    # Copy the marimo app with proper prefix
    cp ${moduleDir}/parquet_stats.py ${prefix}_stats.py
    
    # Export to HTML (this also executes the code)
    marimo export html ${prefix}_stats.py \\
        -o ${prefix}_stats.html \\
        -- \\
        --parquet-file ${parquet_file} \\
        --n-head-rows ${n_head_rows} \\
        --output-prefix ${prefix} \\
        ${args}

    # Optionally also export to ipynb
    if [ "${export_ipynb}" = "true" ]; then
        marimo export ipynb ${prefix}_stats.py -o ${prefix}_stats.ipynb || echo "Warning: ipynb export failed (nbformat may not be installed)"
    fi

    # Optionally also export to markdown
    if [ "${export_markdown}" = "true" ]; then
        marimo export md ${prefix}_stats.py -o ${prefix}_stats.md || echo "Warning: markdown export failed"
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        marimo: \$(marimo --version 2>&1 | awk '{print \$2}' || echo "unknown")
        python: \$(python --version 2>&1 | awk '{print \$2}')
        pandas: \$(python -c "import pandas; print(pandas.__version__)")
        matplotlib: \$(python -c "import matplotlib; print(matplotlib.__version__)")
        seaborn: \$(python -c "import seaborn; print(seaborn.__version__)")
    END_VERSIONS
    """

    stub:
    def prefix = "${meta.batch}_${meta.plate}_${meta.well}_${meta.site}"
    """
    touch ${prefix}_stats.py
    touch ${prefix}_stats.ipynb
    touch ${prefix}_stats.html
    touch ${prefix}_stats.md
    touch ${prefix}_descriptive_stats.parquet
    touch ${prefix}_size_distributions.png
    touch ${prefix}_dna_intensity.png

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        marimo: stub
        python: stub
        pandas: stub
        matplotlib: stub
        seaborn: stub
    END_VERSIONS
    """
}
