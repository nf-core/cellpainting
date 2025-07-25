process CELLPROFILER_ILLUMINATIONCORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/cellprofiler:4.2.8--pyhdfd78af_0'
        : 'community.wave.seqera.io/library/cellprofiler:4.2.8--aff0a99749304a7f'}"

    input:
    tuple val(meta), path(images, stageAs: "images/*"), path(load_data_csv)
    tuple val(meta), path(illum, stageAs: "illumination_corrections/*"), path(load_data_csv)

    path assaydevelopment_cppipe

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
    mkdir -p assaydevelopment
    # TODO Do we need to move illumination corrections to the images directory?

    cellprofiler -c -r \
    ${args} \
    -p assaydevelopment.cppipe \
    -o assaydevelopment \
    --data-file=${load_data_csv} \
    --image-directory ./images/ \
    -g Metadata_Plate=${meta.plate},Metadata_Well=${meta.well} \

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellprofiler: \$(cellprofiler --version |& sed '1!d ; s/cellprofiler //')
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
        cellprofiler: \$(cellprofiler --version |& sed '1!d ; s/cellprofiler //')
    END_VERSIONS
    """
}
