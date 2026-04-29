process CYTOTABLE_DESCRIPTIVESTATS {

    tag "${meta.batch}_${meta.plate}_${meta.well}_${meta.site}"
    label 'process_single'

    // conda "${moduleDir}/environment.yml"
    container "docker.io/dabbleofdevops/papermill-notebook:latest"

    input:
    tuple val(meta), path(parquet_file)

    output:
    tuple val(meta), path("*.ipynb")                      , emit: notebook
    tuple val(meta), path("*_descriptive_stats.parquet")  , emit: stats
    tuple val(meta), path("*_size_distributions.png")     , emit: size_plot, optional: true
    tuple val(meta), path("*_dna_intensity.png")          , emit: dna_plot, optional: true
    tuple val(meta), path("*.html")                       , emit: html, optional: true
    path "versions.yml"                                   , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = "${meta.batch}_${meta.plate}_${meta.well}_${meta.site}"
    def n_head_rows = task.ext.n_head_rows ?: 10
    def convert_html = task.ext.convert_html ?: false
    """
    # Run papermill to execute the notebook with parameters
    papermill ${moduleDir}/parquet_stats.ipynb \\
        ${prefix}_stats.ipynb \\
        -p parquet_file ${parquet_file} \\
        -p n_head_rows ${n_head_rows} \\
        -p output_prefix ${prefix} \\
        ${args}

    # Optionally convert to HTML
    if [ "${convert_html}" = "true" ]; then
        jupyter nbconvert --to html ${prefix}_stats.ipynb
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        papermill: \$(papermill --version 2>&1 | head -1 || echo "unknown")
        python: \$(python --version 2>&1 | awk '{print \$2}')
        pandas: \$(python -c "import pandas; print(pandas.__version__)")
        matplotlib: \$(python -c "import matplotlib; print(matplotlib.__version__)")
        seaborn: \$(python -c "import seaborn; print(seaborn.__version__)")
    END_VERSIONS
    """

    stub:
    def prefix = "${meta.batch}_${meta.plate}_${meta.well}_${meta.site}"
    """
    touch ${prefix}_stats.ipynb
    touch ${prefix}_stats.html
    touch ${prefix}_descriptive_stats.parquet
    touch ${prefix}_size_distributions.png
    touch ${prefix}_dna_intensity.png

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        papermill: stub
        python: stub
        pandas: stub
        matplotlib: stub
        seaborn: stub
    END_VERSIONS
    """
}
