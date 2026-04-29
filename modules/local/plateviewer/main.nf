process PLATEVIEWER {
    label 'process_single'

    input:
    tuple val(plate_ids), path(montage_pngs)

    output:
    path "plate_montages_mqc.html", emit: html

    when:
    task.ext.when == null || task.ext.when

    script:
    def plate_ids_json = new groovy.json.JsonOutput().toJson(plate_ids)
    """
    #!/usr/bin/env python3
    import base64, json, os, sys

    plate_ids = json.loads('${plate_ids_json}')
    png_files = sorted(f for f in os.listdir('.') if f.endswith('.png'))

    if len(plate_ids) != len(png_files):
        print(f"Warning: {len(plate_ids)} plate IDs but {len(png_files)} PNGs", file=sys.stderr)

    # Base64-encode each plate montage
    plates = {}
    for pid, png in zip(sorted(plate_ids), png_files):
        with open(png, 'rb') as f:
            plates[pid] = base64.b64encode(f.read()).decode()

    sorted_ids = sorted(plates.keys())
    options = ''.join(f'<option value="{pid}">{pid}</option>' for pid in sorted_ids)
    first_img = plates[sorted_ids[0]]
    plate_data_json = json.dumps({pid: plates[pid] for pid in sorted_ids})

    html = f'''<!--
    id: "plate-montages"
    section_name: "Plate Montages"
    description: "Segmentation overlay montages arranged in plate grid layout. Select a plate from the dropdown to view."
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
