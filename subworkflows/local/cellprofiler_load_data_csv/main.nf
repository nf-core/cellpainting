
// This subworkflow takes images from a samplesheet and creates
// CellProfiler-compatible load_data.csv files grouped by specified metadata keys


workflow CELLPROFILER_LOAD_DATA_CSV {

    take:
    ch_samplesheet // channel: [ val(meta), [ image ] ]
    grouping_keys  // value channel: list of keys to group by (e.g., ['batch','plate','channel'])

    main:

    // Group images by the specified metadata keys
    ch_samplesheet
        .map { meta, image ->
            def keys = grouping_keys
            def group_key = meta.subMap(keys)
            def group_id = keys.collect { meta[it] }.join('_')
            
            [group_key + [id: group_id], meta, image]
        }
        .groupTuple()
        .set { ch_images_grouped }

    // Create load_data.csv files for each group
    ch_images_grouped
        .map { group_meta, meta_list, image_list ->
            def keys = grouping_keys
            def has_channel = 'channel' in keys
            
            if (has_channel) {
                // Single channel format: FileName_Orig{channel},Metadata_Batch,etc.
                def header = "FileName_Orig${group_meta.channel},Metadata_Batch,Metadata_Plate,Metadata_Well,Metadata_Col,Metadata_Row"
                
                def content = [meta_list, image_list]
                    .transpose()
                    .collect { meta, image ->
                        [image.name, meta.batch, meta.plate, meta.well, meta.col, meta.row].join(',')
                    }
                
                def csv_content = ([header] + content).join('\n')
                [group_meta, csv_content]
            } else {
                // Multi-channel format: FileName_Orig{Channel1},FileName_Orig{Channel2},etc.
                def channels = meta_list.collect { it.channel }.unique().sort()
                def wells_data = [:] // Map of well_site -> [meta, images_by_channel]
                
                // Group by well+site within this group
                [meta_list, image_list].transpose().each { meta, image ->
                    def well_key = "${meta.well}_${meta.site ?: 1}"
                    if (!wells_data[well_key]) {
                        wells_data[well_key] = [meta: meta, images_by_channel: [:]]
                    }
                    wells_data[well_key].images_by_channel[meta.channel] = image
                }
                
                // Create header with FileName_Orig{Channel} columns
                def channel_headers = channels.collect { "FileName_Orig${it}" }
                def header = (channel_headers + ["Metadata_Batch", "Metadata_Plate", "Metadata_Well", "Metadata_Col", "Metadata_Row"]).join(',')
                
                // Create content rows - one per well+site
                def content = wells_data.values().collect { well_data ->
                    def meta = well_data.meta
                    def images_by_channel = well_data.images_by_channel
                    
                    // Create row with filename for each channel
                    def channel_values = channels.collect { channel ->
                        def image = images_by_channel[channel]
                        image ? image.name : ""
                    }
                    
                    // Add metadata columns
                    def row = channel_values + [meta.batch, meta.plate, meta.well, meta.col, meta.row]
                    row.join(',')
                }
                
                def csv_content = ([header] + content).join('\n')
                [group_meta, csv_content]
            }
        }
        .collectFile(
            newLine: true,
            storeDir: "${workflow.workDir}/${workflow.sessionId}/cellprofiler/load_data_csvs"
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

    // Combine grouped images with their load_data.csv files
    ch_images_with_key
        .join(ch_csvs_with_key)
        .map { _key, group_meta, _meta_list, image_list, load_data_csv ->
            [group_meta, image_list, load_data_csv]
        }
        .set { ch_images_with_load_data_csv }



    emit:
    images_with_load_data_csv      = ch_images_with_load_data_csv    // channel: [ val(meta), [ list_of_images ], load_data_csv ]

}
