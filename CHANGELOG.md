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

### `Fixed`

- [PR#47](https://github.com/nf-core/cellpainting/pull/47) - `CYTOTABLE` now keeps per-image metadata (well/plate/site, channel/position, file/path provenance) in the joined Parquet output by renaming `Image_Metadata_*` columns to the `Metadata_*` convention expected by Pycytominer

### `Dependencies`

- [PR#47](https://github.com/nf-core/cellpainting/pull/47) - upgraded `CYTOTABLE` container from CytoTable 0.0.15 to 1.2.6 (pinned `duckdb<2.0`, required by CytoTable 1.2.6)

### `Deprecated`
