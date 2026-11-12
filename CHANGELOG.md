# nf-core/cellpainting: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0.0dev - [unreleased<!-- TODO nf-core: replace with date on release -->]

Initial release of nf-core/cellpainting, created with the [nf-core](https://nf-co.re/) template.

#### Credits

- [Rachel Bozadjian](https://github.com/rboz1)

### `Added`

- [PR#50](https://github.com/nf-core/cellpainting/pull/50) - added test with larger plate
- [PR#47](https://github.com/nf-core/cellpainting/pull/47) - added `PYCYTOMINER_ANNO` module and optional `--metadata` plate-map annotation of CytoTable profiles
- [PR#48](https://github.com/nf-core/cellpainting/pull/48) - added `CYTOTABLE` structural QC stats JSON output (row/column counts, per-compartment column counts)
- [PR#49](https://github.com/nf-core/cellpainting/pull/49) - added `CYTOTABLE_REPORTS` module generating a marimo-based QC report (metadata summary, descriptive stats, size/DNA intensity plots) per plate

### `Fixed`

- [PR#47](https://github.com/nf-core/cellpainting/pull/47) - `CYTOTABLE` now keeps per-image metadata (well/plate/site, channel/position, file/path provenance) in the joined Parquet output by renaming `Image_Metadata_*` columns to the `Metadata_*` convention expected by Pycytominer

### `Dependencies`

- [PR#47](https://github.com/nf-core/cellpainting/pull/47) - upgraded `CYTOTABLE` container from CytoTable 0.0.15 to 1.2.6 (pinned `duckdb<2.0`, required by CytoTable 1.2.6)
- upgraded `CYTOTABLE` container to CytoTable 1.3.0 and switched to `joins="infer"` ([cytomining/CytoTable#523](https://github.com/cytomining/CytoTable/pull/523)) instead of hand-written join SQL; a post-join column filter keeps the same metadata/provenance columns as before and still drops unused per-image QC columns (`ImageQuality_*`, `Image_ExecutionTime_*`, etc.)

### `Deprecated`
