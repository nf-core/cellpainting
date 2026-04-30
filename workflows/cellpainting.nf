/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { CYTOTABLE              } from '../modules/local/cytotable'
include { CELLPROFILER_ILLUMINATIONCORRECTION } from '../modules/local/cellprofiler/illuminationcorrection'
include { CELLPROFILER_ANALYSIS } from '../modules/local/cellprofiler/analysis'
include { CELLPROFILER_ASSAYDEVELOPMENT } from '../modules/local/cellprofiler/assaydevelopment'
include { IMAGEMAGICK_MONTAGE } from '../modules/local/imagemagick/montage'
include { PLATEVIEWER } from '../modules/local/plateviewer'

include { paramsSummaryMap       } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_cellpainting_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow CELLPAINTING {

    take:
    ch_samplesheet // channel: images read in from --input samplesheet
    cellprofiler_mode // value: assay_development, analysis
    cellprofiler_illumination_cppipe // value: path to illumination cppipe
    cellprofiler_assaydevelopment_cppipe // value: path to assaydevelopment cppipe
    cellprofiler_assaydevelopment_site // value: site number for assay development
    cellprofiler_analysis_cppipe // value: path to analysis cppipe

    main:

    ch_versions = channel.empty()
    ch_multiqc_files = channel.empty()

    // Sort grouped image pairs by filename for deterministic resume caching
    def sortGroupedImages = { meta, images_meta, images ->
        def sorted = [images_meta, images].transpose().sort { a, b -> a[0].filename <=> b[0].filename }
        [meta, sorted.collect { it[0] }, sorted.collect { it[1] }]
    }

    //
    // Enrich samplesheet with filename metadata
    //
    ch_samplesheet
        .map { meta, image ->
            def image_meta = meta.clone()
            image_meta.filename = image.name
            [image_meta, image]
        }
        .set { ch_enriched }

    //
    // ILLUMINATION CORRECTION
    // Group by [batch, plate, channel], carry per-image metadata
    //
    ch_enriched
        .map { meta, image ->
            def group_key = meta.subMap(['batch', 'plate', 'channel'])
            def group_id = [meta.batch, meta.plate, meta.channel].join('_')
            [group_key + [id: group_id], meta, image]
        }
        .groupTuple()
        .map(sortGroupedImages)
        .set { ch_illumination_images }

    CELLPROFILER_ILLUMINATIONCORRECTION(
        ch_illumination_images,
        cellprofiler_illumination_cppipe
    )

    ch_versions = ch_versions.mix(CELLPROFILER_ILLUMINATIONCORRECTION.out.versions)

    //
    // Flatten illumination corrections to plate level
    //
    CELLPROFILER_ILLUMINATIONCORRECTION.out.illumination_corrections
        .map { meta, npy_files ->
            def plate_key = [meta.batch, meta.plate].join('_')
            [plate_key, npy_files]
        }
        .groupTuple()
        .map { key, npy_lists -> [key, npy_lists.flatten()] }
        .set { ch_illum_by_plate }

    //
    // ASSAY DEVELOPMENT
    // Runs in both assay_development and analysis modes
    // Group by [batch, plate, well], filter to single site, join with illum
    //
    ch_enriched
        .filter { meta, _image -> meta.site == cellprofiler_assaydevelopment_site }
        .map { meta, image ->
            def group_id = [meta.batch, meta.plate, meta.well].join('_')
            def group_key = meta.subMap(['batch', 'plate', 'well']) + [id: group_id]
            [group_key, meta, image]
        }
        .groupTuple()
        .map { meta, images_meta, images ->
            def (m, im, imgs) = sortGroupedImages(meta, images_meta, images)
            def plate_key = [m.batch, m.plate].join('_')
            [plate_key, m, im, imgs]
        }
        .combine(ch_illum_by_plate, by: 0)
        .map { _key, meta, images_meta, images, illum_files ->
            [meta, images_meta, images, illum_files]
        }
        .set { ch_assay_dev_with_illum }

    CELLPROFILER_ASSAYDEVELOPMENT(
        ch_assay_dev_with_illum,
        cellprofiler_assaydevelopment_cppipe
    )

    ch_versions = ch_versions.mix(CELLPROFILER_ASSAYDEVELOPMENT.out.versions)

    //
    // PLATE MONTAGE
    // Collect assay dev overlay PNGs by [batch, plate], montage into plate grid for MultiQC.
    // Each well shows one representative site (cellprofiler_assaydevelopment_site) with all
    // channels composited into a single segmentation overlay image.
    //

    // Derive plate dimensions from samplesheet (max row/col per batch+plate)
    ch_enriched
        .map { meta, _image ->
            def plate_key = [meta.batch, meta.plate].join('_')
            [plate_key, meta.row as int, meta.col as int]
        }
        .groupTuple()
        .map { key, rows, cols -> [key, rows.max(), cols.max()] }
        .set { ch_plate_dims }

    // Collect overlay PNGs by [batch, plate], derive well row/col from well name.
    // Each assay dev emission is one well — flatMap to one entry per PNG, then
    // groupTuple keeps well_info (pos 3) and png (pos 4) as parallel lists.
    CELLPROFILER_ASSAYDEVELOPMENT.out.png
        .flatMap { meta, pngs ->
            def plate_key = [meta.batch, meta.plate].join('_')
            def well_row = (meta.well[0] as char) - ('A' as char) + 1
            def well_col = (meta.well.substring(1)) as int
            def well_info = [well: meta.well, row: well_row, col: well_col]
            def png_list = pngs instanceof List ? pngs.flatten() : [pngs]
            png_list.collect { png -> [plate_key, meta.batch, meta.plate, well_info, png] }
        }
        .groupTuple(by: [0, 1, 2])
        .map { plate_key, batch, plate, wells_meta, pngs ->
            // Sort wells_meta and pngs together by well name for deterministic -resume caching
            def sorted = [wells_meta, pngs].transpose().sort { a, b -> a[0].well <=> b[0].well }
            def plate_meta = [id: plate_key, batch: batch, plate: plate]
            [plate_key, plate_meta, sorted.collect { it[0] }, sorted.collect { it[1] }]
        }
        .combine(ch_plate_dims, by: 0)
        .map { _key, meta, wells_meta, pngs, plate_rows, plate_cols ->
            [meta, wells_meta, pngs, plate_rows, plate_cols]
        }
        .set { ch_montage_input }

    IMAGEMAGICK_MONTAGE(ch_montage_input)

    //
    // PLATE VIEWER
    // Aggregate all plate montages into an interactive HTML viewer for MultiQC
    //
    IMAGEMAGICK_MONTAGE.out.montage
        .map { meta, png -> [meta.id, png] }
        .collect()
        .map { items ->
            // items is a flat list: [id1, png1, id2, png2, ...]
            def pairs = items.collate(2)
            def ids = pairs.collect { List pair -> pair[0] }
            def pngs = pairs.collect { List pair -> pair[1] }
            [ids, pngs]
        }
        .set { ch_all_montages }

    PLATEVIEWER(ch_all_montages)

    ch_multiqc_files = ch_multiqc_files.mix(PLATEVIEWER.out.html)

    if (cellprofiler_mode == 'analysis') {

        //
        // ANALYSIS
        // Group by [batch, plate, well, site], join with illum
        //
        ch_enriched
            .map { meta, image ->
                def group_id = [meta.batch, meta.plate, meta.well, meta.site].join('_')
                def group_key = meta.subMap(['batch', 'plate', 'well', 'site']) + [id: group_id]
                [group_key, meta, image]
            }
            .groupTuple()
            .map { meta, images_meta, images ->
                def (m, im, imgs) = sortGroupedImages(meta, images_meta, images)
                def plate_key = [m.batch, m.plate].join('_')
                [plate_key, m, im, imgs]
            }
            .combine(ch_illum_by_plate, by: 0)
            .map { _key, meta, images_meta, images, illum_files ->
                [meta, images_meta, images, illum_files]
            }
            .set { ch_analysis_with_illum }

        CELLPROFILER_ANALYSIS(
            ch_analysis_with_illum,
            cellprofiler_analysis_cppipe
        )

        ch_versions = ch_versions.mix(CELLPROFILER_ANALYSIS.out.versions)

        //
        // CYTOTABLE - convert analysis CSVs to Parquet (one file per plate)
        //
        CELLPROFILER_ANALYSIS.out.output_dir
            .map { meta, output_dir ->
                def group_id = [meta.batch, meta.plate].join('_')
                def group_key = meta.subMap(['batch', 'plate']) + [id: group_id]
                [group_key, meta, output_dir]
            }
            .groupTuple()
            .map { plate_meta, site_metas, output_dirs ->
                def sorted_dirs = [site_metas, output_dirs]
                    .transpose()
                    .sort { a, b -> a[0].id <=> b[0].id }
                    .collect { it[1] }
                [plate_meta, sorted_dirs]
            }
            .set { ch_cytotable_input }

        CYTOTABLE(ch_cytotable_input)

    }

    //
    // Collate and save software versions
    //
    def topic_versions = Channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [ process[process.lastIndexOf(':')+1..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by:0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_'  +  'cellpainting_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }

    //
    // MODULE: MultiQC
    //
    ch_multiqc_config        = channel.fromPath(
        "$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_custom_config = params.multiqc_config ?
        channel.fromPath(params.multiqc_config, checkIfExists: true) :
        channel.empty()
    ch_multiqc_logo          = params.multiqc_logo ?
        channel.fromPath(params.multiqc_logo, checkIfExists: true) :
        channel.empty()

    summary_params      = paramsSummaryMap(
        workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary = channel.value(paramsSummaryMultiqc(summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_custom_methods_description = params.multiqc_methods_description ?
        file(params.multiqc_methods_description, checkIfExists: true) :
        file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = channel.value(
        methodsDescriptionText(ch_multiqc_custom_methods_description))

    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_methods_description.collectFile(
            name: 'methods_description_mqc.yaml',
            sort: true
        )
    )

    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList(),
        [],
        []
    )

    emit:
    multiqc_report = MULTIQC.out.report.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
