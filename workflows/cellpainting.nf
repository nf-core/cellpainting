/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { CYTOTABLE              } from '../modules/local/cytotable'
include { CELLPROFILER_ILLUMINATIONCORRECTION } from '../modules/local/cellprofiler/illuminationcorrection'
include { CELLPROFILER_ANALYSIS } from '../modules/local/cellprofiler/analysis.nf'
include { CELLPROFILER_ASSAYDEVELOPMENT } from '../modules/local/cellprofiler/assaydevelopment.nf'

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

    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

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
        // CYTOTABLE - convert analysis CSVs to Parquet
        //
        CYTOTABLE(
            CELLPROFILER_ANALYSIS.out.output_dir
        )

    }

    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_'  +  'cellpainting_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }

    //
    // MODULE: MultiQC
    //
    ch_multiqc_config        = Channel.fromPath(
        "$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_custom_config = params.multiqc_config ?
        Channel.fromPath(params.multiqc_config, checkIfExists: true) :
        Channel.empty()
    ch_multiqc_logo          = params.multiqc_logo ?
        Channel.fromPath(params.multiqc_logo, checkIfExists: true) :
        Channel.empty()

    summary_params      = paramsSummaryMap(
        workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary = Channel.value(paramsSummaryMultiqc(summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_custom_methods_description = params.multiqc_methods_description ?
        file(params.multiqc_methods_description, checkIfExists: true) :
        file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = Channel.value(
        methodsDescriptionText(ch_multiqc_custom_methods_description))

    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_methods_description.collectFile(
            name: 'methods_description_mqc.yaml',
            sort: true
        )
    )

    ch_multiqc_config_combined = ch_multiqc_config
        .mix(ch_multiqc_custom_config)
        .toList()

    ch_multiqc_input = ch_multiqc_files
        .collect()
        .map { files -> [ [id: 'multiqc'], files ] }
        .combine(ch_multiqc_config_combined.map { [it] })
        .combine(ch_multiqc_logo.ifEmpty([]).toList().map { [it.flatten()] })
        .map { meta, files, config, logo ->
            [ meta, files, config.flatten(), logo.flatten() ?: [], [], [] ]
        }

    MULTIQC ( ch_multiqc_input )

    emit:
    multiqc_report = MULTIQC.out.report.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
