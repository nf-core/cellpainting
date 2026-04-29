process CYTOTABLE {
    label 'process_low'
    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://community.wave.seqera.io/library/pip_cytotable:75a940a0fcae75db' :
        'community.wave.seqera.io/library/pip_cytotable_pandas:f9bd5512f71acd86'
    }

    // TODO: remove once https://github.com/cytomining/CytoTable/issues/440 is fixed (tracked in #42)
    stageInMode 'copy'

    input:
    // Rename each input dir to a unique number (no '/*' glob) so cytotable.convert sees
    // distinct immediate-parent names per source. Works around the upstream path-collision
    // bug at https://github.com/cytomining/CytoTable/issues/442.
    tuple val(meta), path(cellprofiler_output_dirs, stageAs: "analyses/?")

    output:
    tuple val(meta), path("${meta.batch}_${meta.plate}.parquet")

    script:
    """
#!/usr/bin/env python
from cytotable import convert
from parsl.config import Config
from parsl.executors import ThreadPoolExecutor
import pandas as pd
import os

os.environ["HOME"] = os.getcwd()

custom_join = '''
    SELECT
        image.*,
        cytoplasm.* EXCLUDE (Metadata_ImageNumber),
        cells.* EXCLUDE (Metadata_ImageNumber, Metadata_ObjectNumber),
        nuclei.* EXCLUDE (Metadata_ImageNumber, Metadata_ObjectNumber)
    FROM
        read_parquet('cytoplasm.parquet') AS cytoplasm
    LEFT JOIN read_parquet('cells.parquet') AS cells USING (Metadata_ImageNumber)
    LEFT JOIN read_parquet('nuclei.parquet') AS nuclei USING (Metadata_ImageNumber)
    LEFT JOIN read_parquet('image.parquet') AS image USING (Metadata_ImageNumber)
    WHERE
        cells.Metadata_ObjectNumber = cytoplasm.Metadata_Cytoplasm_Parent_Cells
        AND nuclei.Metadata_ObjectNumber = cytoplasm.Metadata_Cytoplasm_Parent_Nuclei
'''

convert(
    source_path="analyses",
    source_datatype="csv",
    dest_path="temp_output.parquet",
    dest_datatype="parquet",
    preset="cellprofiler_csv",
    joins=custom_join,
    identifying_columns=[
        "ImageNumber", "ObjectNumber",
        "Metadata_Well", "Metadata_Plate", "Metadata_Site",
        "Metadata_Col", "Metadata_Row",
        "Parent_Cells", "Parent_Nuclei"
    ],
    parsl_config=Config(
        executors=[ThreadPoolExecutor(max_threads=${task.cpus})],
    ),
)

# Fix any Image_ prefixed metadata columns
df = pd.read_parquet("temp_output.parquet")
rename_map = {}
for col in df.columns:
    if col.startswith("Image_Metadata_"):
        new_name = col.replace("Image_Metadata_", "Metadata_")
        rename_map[col] = new_name

if rename_map:
    df = df.rename(columns=rename_map)

df.to_parquet("${meta.batch}_${meta.plate}.parquet", index=False)
    """

    stub:
    """
    touch ${meta.batch}_${meta.plate}.parquet
    """
}
