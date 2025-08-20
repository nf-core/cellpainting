/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { CYTOTABLE              } from '../modules/local/cytotable'
include { CELLPROFILER_ILLUMINATIONCORRECTION } from '../modules/local/cellprofiler/illuminationcorrection'
include { CELLPROFILER_ANALYSIS } from '../modules/local/cellprofiler/analysis.nf'
include { CELLPROFILER_ASSAYDEVELOPMENT } from '../modules/local/cellprofiler/assaydevelopment'
include { CELLPROFILER_LOAD_DATA_CSV as ILLUMINATION_LOAD_DATA_CSV } from '../subworkflows/local/cellprofiler_load_data_csv'
include { CELLPROFILER_LOAD_DATA_CSV_WITH_ILLUM } from '../subworkflows/local/cellprofiler_load_data_csv_with_illum'

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
    cellprofiler_analysis_cppipe // value: path to analysis cppipe


    main:

    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

    // Create load_data.csv files for illumination correction
    // Group by batch, plate, and channel for illumination correction
    ILLUMINATION_LOAD_DATA_CSV(
        ch_samplesheet,
        ['batch', 'plate', 'channel'],
        'illumination'
    )

    ch_illumination_correction_images_with_load_data_csv = ILLUMINATION_LOAD_DATA_CSV.out.images_with_load_data_csv


    CELLPROFILER_ILLUMINATIONCORRECTION(
        ch_illumination_correction_images_with_load_data_csv,
        cellprofiler_illumination_cppipe
    )

    if (cellprofiler_mode == 'assay_development') {

        // Create the LOAD_DATA.CSV files for assay development
        CELLPROFILER_LOAD_DATA_CSV_WITH_ILLUM(
            ch_samplesheet,
            ['batch', 'plate','well'],
            CELLPROFILER_ILLUMINATIONCORRECTION.out.illumination_corrections,
            'assay_development'
        )

        CELLPROFILER_ASSAYDEVELOPMENT(
            CELLPROFILER_LOAD_DATA_CSV_WITH_ILLUM.out.images_with_illum_load_data_csv,
            cellprofiler_assaydevelopment_cppipe
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
