process IMAGEMAGICK_MONTAGE {
    tag "$meta.id"
    label 'process_single' // montage is single-threaded (OpenMP disabled in conda-forge build)

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://community.wave.seqera.io/library/imagemagick:imagemagick-7.1.2--d0b725a537542464' :
        'community.wave.seqera.io/library/imagemagick:imagemagick-7.1.2--d0b725a537542464' }"

    input:
    tuple val(meta), val(wells_meta), path(pngs, stageAs: "images/*"), val(plate_rows), val(plate_cols)

    output:
    tuple val(meta), path("*_montage_mqc.png"),  emit: montage
    tuple val(meta), path("*_montage_full.tiff"), emit: montage_full, optional: true

    tuple val("${task.process}"), val('imagemagick'), eval("montage -version | sed -n 's/^Version: ImageMagick //p' | cut -d' ' -f1"), topic: versions, emit: versions_imagemagick

    when:
    task.ext.when == null || task.ext.when

    script:
    def args      = task.ext.args ?: ''
    def prefix    = task.ext.prefix ?: "${meta.id}"
    def full_res  = task.ext.full_res ?: false

    // wells_meta and pngs are parallel lists — write a well->file TSV for bash
    def png_list = pngs instanceof List ? pngs : [pngs]
    def mapping_lines = []
    wells_meta.eachWithIndex { w, idx ->
        if (idx < png_list.size()) {
            mapping_lines << w.well + '\t' + png_list[idx].name
        }
    }
    def mapping_tsv = mapping_lines.join('\n')

    // Plate grid well names (A01, A02, ..., P24) and header labels
    def plate_grid = []
    (1..plate_rows).each { int r ->
        (1..plate_cols).each { int c ->
            plate_grid << "" + (char)((int)('A' as char) + r - 1) + String.format('%02d', c)
        }
    }

    def row_letters = (0..<plate_rows).collect { int i -> "" + (char)((int)('A' as char) + i) }
    def col_numbers = (1..plate_cols).collect { int i -> i.toString() }

    """
    FONT=\$(fc-list : file | head -1 | cut -d: -f1)

    # Build well -> staged file lookup from channel metadata
    declare -A WELL_FILE
    while IFS=\$'\\t' read -r WELL FILENAME; do
        WELL_FILE[\$WELL]="\$FILENAME"
    done <<< "${mapping_tsv}"

    # Emit file list in plate-grid order (null: for missing wells)
    > montage_args.txt
    for WELL in ${plate_grid.join(' ')}; do
        if [ -n "\${WELL_FILE[\$WELL]+x}" ]; then
            echo "\${WELL_FILE[\$WELL]}" >> montage_args.txt
        else
            echo "null:"     >> montage_args.txt
        fi
    done

    # Annotate montage with plate-style row/column headers
    export FONT
    add_plate_headers() {
        local INPUT="\$1" OUTPUT="\$2" TILE_SZ="\$3"
        local POINTSIZE=\$((TILE_SZ / 2))
        local CELL_SZ=\$((TILE_SZ + 2 * 2))
        local MARGIN_LEFT=\$((POINTSIZE + 8))
        local MARGIN_TOP=\$((POINTSIZE + 4))

        # Center labels over each cell using approximate glyph metrics
        local HALF_GLYPH_W=\$((POINTSIZE / 3))
        local HALF_GLYPH_H=\$((POINTSIZE / 3))

        local COL_ANNOT="" ROW_ANNOT=""
        local IDX=0
        for COL_NUM in ${col_numbers.join(' ')}; do
            local NUM_DIGITS=\${#COL_NUM}
            local TEXT_W=\$((HALF_GLYPH_W * NUM_DIGITS))
            local X=\$((MARGIN_LEFT + IDX * CELL_SZ + CELL_SZ / 2 - TEXT_W))
            COL_ANNOT="\$COL_ANNOT -annotate +\${X}+2 '\$COL_NUM'"
            IDX=\$((IDX + 1))
        done
        IDX=0
        for ROW_LTR in ${row_letters.join(' ')}; do
            local Y=\$((MARGIN_TOP + IDX * CELL_SZ + CELL_SZ / 2 - HALF_GLYPH_H))
            ROW_ANNOT="\$ROW_ANNOT -annotate +4+\${Y} '\$ROW_LTR'"
            IDX=\$((IDX + 1))
        done

        eval magick "\$INPUT" \\
            -gravity northwest \\
            -splice \${MARGIN_LEFT}x\${MARGIN_TOP} \\
            -fill white -font "\$FONT" -pointsize "\$POINTSIZE" \\
            \$COL_ANNOT \$ROW_ANNOT \\
            "\$OUTPUT"
    }

    # Thumbnail montage — tiles resized during assembly to keep memory low
    montage \\
        \$(cat montage_args.txt | tr '\\n' ' ') \\
        -tile ${plate_cols}x${plate_rows} \\
        -geometry 200x200+2+2 \\
        -font "\$FONT" \\
        -background black \\
        +label \\
        ${args} \\
        montage_raw.png

    add_plate_headers montage_raw.png ${prefix}_montage_mqc.png 200
    rm montage_raw.png

    # Optional full-res montage (off by default — expensive for large plates)
    if [ "${full_res}" = "true" ]; then
        montage \\
            \$(cat montage_args.txt | tr '\\n' ' ') \\
            -tile ${plate_cols}x${plate_rows} \\
            -geometry +2+2 \\
            -font "\$FONT" \\
            -background black \\
            +label \\
            ${args} \\
            montage_full_raw.tiff

        FULL_TILE_SZ=\$(magick identify -format '%w' \$(grep -v null montage_args.txt | head -1) 2>/dev/null || echo 200)
        add_plate_headers montage_full_raw.tiff ${prefix}_montage_full.tiff \$FULL_TILE_SZ
        rm montage_full_raw.tiff
    fi
    """

    stub:
    def prefix   = task.ext.prefix ?: "${meta.id}"
    def full_res = task.ext.full_res ?: false
    """
    touch ${prefix}_montage_mqc.png
    if [ "${full_res}" = "true" ]; then
        touch ${prefix}_montage_full.tiff
    fi
    """
}
