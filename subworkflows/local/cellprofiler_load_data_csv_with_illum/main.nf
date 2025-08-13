// This subworkflow takes images from a samplesheet and creates
// CellProfiler-compatible load_data.csv files grouped by specified metadata keys
// with additional illumination correction file columns


workflow CELLPROFILER_LOAD_DATA_CSV_WITH_ILLUM {

    take:
    ch_samplesheet            // channel: [ val(meta), [ image ] ]
    grouping_keys             // value channel: list of keys to group by (e.g., ['batch','plate'])
    ch_illumination_correction // channel: [ val(meta), illumination_correction ]
    step_name                 // value channel: name of the pipeline step (determines working directory for load_data.csv files)

    main:

    // Group images by the specified metadata keys
    ch_samplesheet
        .map { meta, image ->
            def group_meta = meta.subMap(grouping_keys) + [id: grouping_keys.collect { meta[it] }.join('_')]
            [group_meta, meta, image]
        }
        .groupTuple()
        .set { ch_images_grouped}

    // Create load_data.csv files for each group
    ch_images_grouped
        .map { group_meta, meta_list, image_list ->
            // Derive channels dynamically from the metadata in this group
            def channels = meta_list.collect { it.channel }.unique().sort()

            // Group images by well and site within this group
            def wells_data = [:] // Map: well_site -> [meta, images_by_channel]
            [meta_list, image_list].transpose().each { meta, image ->
                def well_key = "${meta.well}_${meta.site ?: 1}"
                if (!wells_data[well_key]) {
                    wells_data[well_key] = [meta: meta, images_by_channel: [:]]
                }
                wells_data[well_key].images_by_channel[meta.channel] = image
            }

            // Header: for each channel add FileName_Orig{channel}, followed by metadata, then FileName_Illum{channel}
            def orig_headers = channels.collect { "FileName_Orig${it}" }
            def illum_headers = channels.collect { "FileName_Illum${it}" }
            def header = (orig_headers + ["Metadata_Batch", "Metadata_Plate", "Metadata_Well", "Metadata_Col", "Metadata_Row"] + illum_headers).join(',')

            // Content: one row per well+site
            def rows = wells_data.values().collect { well_data ->
                def meta = well_data.meta
                def images_by_channel = well_data.images_by_channel

                // Create image filename list in channel order
                def image_filenames = channels.collect { channel ->
                    images_by_channel[channel] ? images_by_channel[channel].name : ""
                }

                // Create illumination filename list based on the plate and channel
                def illum_filenames = channels.collect { channel ->
                    "${meta.batch}_${meta.plate}_Illum${channel}.npy"
                }

                // Combine: image files + metadata + illum files
                def row = image_filenames + [meta.batch, meta.plate, meta.well, meta.col, meta.row] + illum_filenames
                row.join(',')
            }

            def csv_content = ([header] + rows).join('\n')
            [group_meta, csv_content]
        }
        .collectFile(
            newLine: true,
            storeDir: "${workflow.workDir}/${workflow.sessionId}/cellprofiler/load_data_csvs_with_illum/${step_name}"
        ) { group_meta, csv_content ->
            ["${group_meta.id}.csv", csv_content]
        }
        .set { ch_load_data_csvs }

    // Join grouped images with their corresponding CSV files
    ch_images_grouped
        .map { group_meta, meta_list, image_list ->
            [group_meta.id, group_meta, meta_list, image_list]
        }
        .set { ch_images_with_key }

    ch_load_data_csvs
        .map { load_data_csv ->
            [load_data_csv.baseName, load_data_csv]
        }
        .set { ch_csvs_with_key }

    // Group illumination correction files by the same keys
    ch_illumination_correction
        .map { illum_meta, illum_file ->
            def group_meta = illum_meta.subMap(grouping_keys) + [id: grouping_keys.collect { illum_meta[it] }.join('_')]
            [group_meta, illum_meta, illum_file]
        }
        .groupTuple()
        .map { group_meta, illum_meta_list, illum_file_list ->
            [group_meta.id, group_meta, illum_file_list]
        }
        .set { ch_illum_with_key }

    // Combine grouped images with their load_data.csv files and illumination files
    ch_images_with_key
        .join(ch_csvs_with_key)
        .join(ch_illum_with_key)
        .map { _key, group_meta, _meta_list, image_list, load_data_csv, illum_group_meta, illum_file_list ->
            [group_meta, image_list, illum_file_list, load_data_csv]
        }
        .set { ch_images_with_illum_load_data_csv }

    emit:
    images_with_illum_load_data_csv = ch_images_with_illum_load_data_csv    // channel: [ val(meta), [ list_of_images ], [ list_of_illumination_correction_files ], load_data_csv ]

}
