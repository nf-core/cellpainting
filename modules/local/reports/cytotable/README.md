# cytotable reports

Consolidated reports for CytoTable parquet outputs: a JSON metadata report, a
descriptive-statistics parquet, distribution plots, and a rendered HTML report
(optionally also ipynb / markdown exports). Everything is produced by one
marimo app (`parquet_reports.py`) executed via `marimo export html`.

The two report flavours (metadata + descriptive statistics) started life as two
separate processes in #49 and were consolidated into a single process so the
profiles parquet is staged once per plate instead of twice.

## Inputs

| Type   | Description                                |
| ------ | ------------------------------------------ |
| `file` | CytoTable profiles parquet (one per plate) |

## Outputs

| Emit       | File                                                            | Description                                |
| ---------- | --------------------------------------------------------------- | ------------------------------------------ |
| `app`      | `<prefix>_reports.py`                                           | The marimo app copy                        |
| `metadata` | `<prefix>_metadata.json`                                        | JSON metadata report                       |
| `stats`    | `<prefix>_descriptive_stats.parquet`                            | Per-feature descriptive statistics         |
| `plots`    | `<prefix>_size_distributions.png`, `<prefix>_dna_intensity.png` | Distribution plots                         |
| `html`     | `<prefix>_reports.html`                                         | Rendered HTML report                       |
| `notebook` | `<prefix>_reports.ipynb`                                        | Optional (task.ext.export_ipynb = true)    |
| `markdown` | `<prefix>_reports.md`                                           | Optional (task.ext.export_markdown = true) |

## Example usage

```groovy
include { CYTOTABLE_REPORTS } from '../modules/local/reports/cytotable'

CYTOTABLE_REPORTS(
    ch_cytotable_parquet // [ [batch: ..., plate: ...], parquet ]
)
```

## Parameters

- `task.ext.prefix` — output file prefix (defaults to `${batch}_${plate}`)
- `task.ext.n_head_rows` — head-rows shown in the report (default 10)
- `task.ext.export_ipynb` — also export a Jupyter notebook (default false)
- `task.ext.export_markdown` — also export markdown (default false)
- `task.ext.args` — extra CLI args appended to the marimo invocation
