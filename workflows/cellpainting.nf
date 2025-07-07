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
    cellprofiler_mode // value: assaydevelopment, analysis
    cellprofiler_illumination_cppipe // value: path to illumination cppipe
    cellprofiler_assaydevelopment_cppipe // value: path to assaydevelopment cppipe
    cellprofiler_analysis_cppipe // value: path to analysis cppipe


    main:

    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

    // Get the list of unique channels from the samplesheet
    channels_list = ch_samplesheet
        .map { meta, image -> meta.channel }
        .unique()
        .collect()

    // Illumination Correction
    // Group images by channel and plate
    ch_samplesheet.map { meta, image ->
        def group_key = meta.subMap('batch','plate','channel')
        def new_tuple = [group_key, meta, image]
        new_tuple
    }.groupTuple().set { images_grouped_by_plate_channel }

    // Create load_data.csv for each channel for illumination correction
    images_grouped_by_plate_channel.map{
        shared_meta, meta_list, image_list ->
        def header = "Orig${shared_meta.channel}_FileName,Orig${shared_meta.channel}_PathName,Metadata_Batch,Metadata_Plate,Metadata_Well,Metadata_Col,Metadata_Row"
        def zip_meta_image = [meta_list, image_list].transpose()
        def file_name = "${shared_meta.values().join('_')}.csv"
        def content = zip_meta_image.collect { meta, image ->
            def row = ["${image.name}","./images/", meta.batch, meta.plate, meta.well, meta.col, meta.row]
            row.join(',')
        }

        def file_content = [header] + content
        def file_content_str = file_content.join('\n')

        [shared_meta, file_name, file_content_str]
    }.collectFile(
        newLine: true,
        storeDir: "${workflow.workDir}/${workflow.sessionId}/illumination_correction/load_data_csvs"
    ) {
        shared_meta, file_path, file_content_str ->
        [file_path] + file_content_str
    }.set { ch_illumination_correction_load_data_csvs }

    // Create a key for each channel from the shared metadata
    images_grouped_by_plate_channel.map{
        shared_meta, meta_list, image_list ->
        ["${shared_meta.values().join('_')}", shared_meta, meta_list, image_list]
    }.set { ch_images_grouped_by_plate_channel_with_key }
    ch_illumination_correction_load_data_csvs.map{
        load_data_csv ->
        [load_data_csv.baseName, load_data_csv]
    }.set { ch_illumination_correction_load_data_csvs_with_key }

    // Join the two channels on the key, and return the shared metadata, image list and load_data_csv
    ch_images_grouped_by_plate_channel_with_key.join(ch_illumination_correction_load_data_csvs_with_key)
        .map{
            _key, shared_meta, meta_list, image_list, load_data_csv ->
            [shared_meta, image_list, load_data_csv]
        }
        .set{ch_illumination_correction_images_with_load_data_csv}


    CELLPROFILER_ILLUMINATIONCORRECTION(
        ch_illumination_correction_images_with_load_data_csv,
        cellprofiler_illumination_cppipe
    )


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

    // MULTIQC (
    //     ch_multiqc_files.collect(),
    //     ch_multiqc_config.toList(),
    //     ch_multiqc_custom_config.toList(),
    //     ch_multiqc_logo.toList(),
    //     [],
    //     []
    // )

    // emit:multiqc_report = MULTIQC.out.report.toList() // channel: /path/to/multiqc_report.html
    // versions       = ch_versions                 // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
