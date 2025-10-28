process CELLPROFILER_ASSAYDEVELOPMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/cellprofiler:4.2.8--pyhdfd78af_0'
        : 'community.wave.seqera.io/library/cellprofiler:4.2.8--aff0a99749304a7f'}"

    input:
    tuple val(meta), path(images, stageAs: "images/*"), path(illumination_correction_files, stageAs: "images/*") // channel: [ val(meta), [ list_of_images ], [ list_of_illumination_correction_files ] ]
    path(assay_development_cppipe)

    output:
    tuple val(meta), path("assaydevelopment/*.png"), emit: png
    tuple val(meta), path("assaydevelopment/Image.csv"), emit: csv, optional: true
    path "versions.yml", emit: versions
    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Generate load_data.csv dynamically with illumination files
    generate_illumination_apply_csv.py \\
        --images-dir ./images \\
        --illum-dir ./images \\
        --output load_data.csv

    mkdir -p assaydevelopment

    cellprofiler -c -r \\
    ${args} \\
    -p ${assay_development_cppipe} \\
    -o assaydevelopment \\
    --data-file=load_data.csv \\
    --image-directory ./images/

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellprofiler: \$(cellprofiler --version)
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    mkdir -p assaydevelopment
    echo 'this is not assay development' > assaydevelopment/mock_segmentedimage.png
    echo 'this is not assay development' > assaydevelopment/mock_Image.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellprofiler: \$(cellprofiler --version )
    END_VERSIONS
    """
}
