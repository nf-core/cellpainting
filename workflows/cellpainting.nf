/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
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
    ch_samplesheet // channel: samplesheet read in from --input
    main:

    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

    // Assay Development
    // Group images by plate and well
    ch_samplesheet.map { meta, image ->
        def group_key = meta.subMap('batch','plate','well')
        def new_tuple = [group_key + [id: "${meta.batch}_${meta.plate}_${meta.well}"], meta, image]
        new_tuple
    }.groupTuple().set { images_grouped_by_plate_well }

    // Create load_data.csv for each well for assay development
    images_grouped_by_plate_well.map{
        shared_meta, meta_list, image_list ->
        // Create the header for the load_data.csv file
        # TODO: Need a FileName_OrigCHANNEL for each channel in experiment
        # TODO: Need an FileName_IllumCHANNEL for each channel in experiment
        def header = "FileName_Orig${shared_meta.channel},Metadata_Batch,Metadata_Plate,Metadata_Well,Metadata_Col,Metadata_Row"
        // Zip the metadata and image list together so that each row corresponds to an image together with its metadata
        def zip_meta_image = [meta_list, image_list].transpose()
        // Create the content for the load_data.csv file
        // Each row will contain the image filename, batch, plate, well, column and row
        def content = zip_meta_image.collect { meta, image ->
            def row = ["${image.name}",meta.batch, meta.plate, meta.well, meta.col, meta.row]
            row.join(',')
        }
        // Combine the header and content into a text string
        def file_content = [header] + content
        def file_content_str = file_content.join('\n')
        // Return a tuple with the shared metadata and the file content string
        [shared_meta, file_content_str]
    }.collectFile(
        newLine: true,
        storeDir: "${workflow.workDir}/cellpainting/${workflow.sessionId}/load_data_csvs/assay_development/"
    ) {
        shared_meta, file_content_str ->
        // Create a file name for the load_data.csv file
        def file_name = "${shared_meta.id}.csv"
        [file_name] + file_content_str
    }.set { well_assay_development_load_data_csvs }

    // Create a join key for each channel from the shared metadata
    images_grouped_by_plate_well.map{
        shared_meta, meta_list, image_list ->
        [shared_meta.id, shared_meta, meta_list, image_list]
    }.set { images_grouped_by_plate_well_with_key }
    well_assay_development_load_data_csvs.map{
        load_data_csv ->
        [load_data_csv.baseName, load_data_csv]
    }.set { well_assay_development_load_data_csvs_with_key }

    // Join the two channels on the key, and return the shared metadata, image list and load_data_csv
    images_grouped_by_plate_well_with_key.join(well_assay_development_load_data_csvs_with_key)
        .map{
            _key, shared_meta, _meta_list, image_list, load_data_csv ->
            [shared_meta, image_list, load_data_csv]
        }
        .set{assay_dev_images_with_load_data_csv}


    CELLPROFILER_ASSAYDEVELOPMENT(
        assay_dev_images_with_load_data_csv,
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
