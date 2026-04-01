process CELLPROFILER_ASSAYDEVELOPMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/cellprofiler:4.2.8--pyhdfd78af_0'
        : 'community.wave.seqera.io/library/cellprofiler:4.2.8--aff0a99749304a7f'}"

    input:
    tuple val(meta), val(images_meta), path(images, stageAs: "images/*"), path(illum_files, stageAs: "images/*")
    path assay_development_cppipe

    output:
    tuple val(meta), path("assaydevelopment/*.png"), emit: png
    tuple val(meta), path("assaydevelopment/Image.csv"), emit: csv, optional: true
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def meta_plain = [id: meta.id, batch: meta.batch, plate: meta.plate, well: meta.well, site: meta.site]
    def images_plain = images_meta.collect { img -> [filename: img.filename, batch: img.batch, plate: img.plate, well: img.well, col: img.col, row: img.row, site: img.site, channel: img.channel] }
    def metadata_json = groovy.json.JsonOutput.toJson([meta: meta_plain, images: images_plain])
    """
    echo '${metadata_json}' > metadata.json
    generate_illumination_apply_csv.py --metadata metadata.json --images-dir ./images --output load_data.csv

    mkdir -p assaydevelopment

    cellprofiler -c -r \
    ${args} \
    -p ${assay_development_cppipe} \
    -o assaydevelopment \
    --data-file=load_data.csv \
    --image-directory ./images/ \
    -g Metadata_Plate=${meta.plate},Metadata_Well=${meta.well}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellprofiler: \$(cellprofiler --version)
    END_VERSIONS
    """

    stub:
    """
    mkdir -p assaydevelopment
    echo 'stub' > assaydevelopment/mock_segmentedimage.png
    echo 'ImageNumber,Metadata_Plate' > assaydevelopment/Image.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellprofiler: stub
    END_VERSIONS
    """
}
