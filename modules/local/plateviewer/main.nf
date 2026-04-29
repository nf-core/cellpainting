process PLATEVIEWER {
    label 'process_single'

    input:
    tuple val(plate_ids), path(montage_pngs)

    output:
    path "plate_montages_mqc.html", emit: html

    when:
    task.ext.when == null || task.ext.when

    script:
    // plate_ids and montage_pngs are parallel lists — build explicit mapping
    def png_list = montage_pngs instanceof List ? montage_pngs : [montage_pngs]
    def plate_map = [:]
    plate_ids.eachWithIndex { id, idx ->
        if (idx < png_list.size()) {
            plate_map[id] = png_list[idx].name
        }
    }
    def plate_map_json = new groovy.json.JsonOutput().toJson(plate_map)
    """
    #!/usr/bin/env python3
    import base64, json

    plate_map = json.loads('${plate_map_json}')

    # Base64-encode each plate montage using the metadata-driven mapping
    plates = {}
    for plate_id, filename in plate_map.items():
        with open(filename, 'rb') as f:
            plates[plate_id] = base64.b64encode(f.read()).decode()

    sorted_ids = sorted(plates.keys())
    options = ''.join(f'<option value="{pid}">{pid}</option>' for pid in sorted_ids)
    first_img = plates[sorted_ids[0]]
    plate_data_json = json.dumps({pid: plates[pid] for pid in sorted_ids})

    html = f'''<!--
    id: "plate-montages"
    section_name: "Plate Montages"
    description: "Segmentation overlay montages arranged in plate grid layout. Each well shows a single representative site (controlled by <code>cellprofiler_assaydevelopment_site</code>, default site 1) with all channels composited into one overlay image. Select a plate from the dropdown to view."
    -->
    <div style="margin: 10px 0;">
        <label for="plate-select" style="font-weight: bold; margin-right: 8px;">Plate:</label>
        <select id="plate-select" onchange="switchPlate(this.value)" style="padding: 4px 8px; font-size: 14px;">
            {options}
        </select>
        <span style="margin-left: 12px; color: #999;">{len(sorted_ids)} plate(s)</span>
    </div>
    <details style="margin: 6px 0; font-size: 12px; color: #999;">
        <summary>Output file locations</summary>
        <ul style="margin: 4px 0;">
            <li>Thumbnail montages: <code>imagemagick/montage/thumbnail/</code></li>
            <li>Full-resolution montages (if enabled via <code>ext.full_res = true</code>): <code>imagemagick/montage/full/</code></li>
            <li>Individual per-well overlays: <code>cellprofiler/assay_development/</code></li>
        </ul>
    </details>
    <div>
        <img id="plate-image" src="data:image/png;base64,{first_img}" style="max-width: 100%; border: 1px solid #333;" />
    </div>
    <script>
        var plateData = {plate_data_json};
        function switchPlate(plateId) {{
            document.getElementById("plate-image").src = "data:image/png;base64," + plateData[plateId];
        }}
    </script>
    '''

    with open('plate_montages_mqc.html', 'w') as f:
        f.write(html)
    """

    stub:
    """
    echo '<!-- stub -->' > plate_montages_mqc.html
    """
}
