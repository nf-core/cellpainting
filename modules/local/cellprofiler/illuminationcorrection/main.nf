process CELLPROFILER_ILLUMINATIONCORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/cellprofiler:4.2.8--pyhdfd78af_0'
        : 'community.wave.seqera.io/library/cellprofiler:4.2.8--aff0a99749304a7f'}"

    input:
    tuple val(meta), val(images_meta), path(images, stageAs: "images/*")
    path illumination_cppipe

    output:
    tuple val(meta), path("illumination_corrections/*.npy"), emit: illumination_corrections
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def meta_plain = [id: meta.id, batch: meta.batch, plate: meta.plate, channel: meta.channel]
    def images_plain = images_meta.collect { img -> [filename: img.filename, batch: img.batch, plate: img.plate, well: img.well, col: img.col, row: img.row, site: img.site, channel: img.channel] }
    def metadata_json = groovy.json.JsonOutput.toJson([meta: meta_plain, images: images_plain])
    """
    echo '${metadata_json}' > metadata.json
    generate_illumination_calc_csv.py --metadata metadata.json --output load_data.csv

    sed 's/{{channel}}/${meta.channel}/g' ${illumination_cppipe} > illumination.cppipe

    mkdir -p illumination_corrections

    cellprofiler -c -r \
    ${args} \
    -p illumination.cppipe \
    -o illumination_corrections \
    --data-file=load_data.csv \
    --image-directory ./images/ \
    -g Metadata_Plate=${meta.plate}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellprofiler: \$(cellprofiler --version)
    END_VERSIONS
    """

    stub:
    """
    mkdir -p illumination_corrections
    touch illumination_corrections/${meta.plate}_Illum${meta.channel}.npy

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellprofiler: stub
    END_VERSIONS
    """
}
