include { toJson; mergeCsv } from 'plugin/nf-boost'

/*
 * CELLPROFILER_ILLUMINATIONCORRECTION
 *
 * Calculate illumination correction functions using CellProfiler.
 *
 * Input:
 *   tuple val(meta), val(images_meta), path(images, stageAs: "images/*")
 *     - meta: Map with shared metadata (id, batch, plate, channel)
 *     - images_meta: List of maps with per-image metadata (filename, batch, plate, well, col, row, site, channel)
 *     - images: List of image files staged in images/ directory
 *   path illumination_cppipe: CellProfiler pipeline file for illumination calculation
 *
 * Output:
 *   tuple val(meta), val(images_meta), path("illumination_corrections/*.npy"): Illumination correction functions
 *   path "versions.yml": Software versions
 */
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
    tuple val(meta), val(images_meta), path("illumination_corrections/*.npy"), emit: illumination_corrections
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def images_path = task.workDir.resolve("load_data.csv")
    mergeCsv(images_meta, images_path, header: true, sep: ',')
    """

    mkdir -p illumination_corrections
    # Replace the channel name in the cppipe file
    sed 's/{{channel}}/${meta.channel}/g' ${illumination_cppipe} > illumination.cppipe

    cellprofiler -c -r \\
    ${args} \\
    -p illumination.cppipe \\
    -o illumination_corrections \\
    --data-file=load_data.csv \\
    --image-directory ./images/ \\
    -g Metadata_Plate=${meta.plate}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellprofiler: \$(cellprofiler --version)
    END_VERSIONS
    """.stripIndent()

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    mkdir -p illumination_corrections
    echo 'this is not an illumination correction' > illumination_corrections/${meta.plate}_Illum${meta.channel}.npy

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellprofiler: \$(cellprofiler --version )
    END_VERSIONS
    """.stripIndent()
}
