# data/processed

Output folder for the ETL steps. Do not edit these files by hand. Regenerate them by re-running the scripts from the repository root.

| File | Written by | Contents |
|---|---|---|
| `policies_cleaned.{rds,csv}` | `src/01_clean_datasets.R` | One row per policy: cleaned attributes and `exposure` in years |
| `claims_cleaned.{rds,csv}` | `src/01_clean_datasets.R` | One row per claim: harmonised `Claim_Type`, numeric amounts, plus the flags `is_total_loss_clean` and `is_cat_event` |
| `cleaning_log.csv` | `src/01_clean_datasets.R` | Rows in and out, and rows affected, for every cleaning step |
| merged frequency/severity base | `src/01_etl_merge_and_clean.R` | Planned: join, orphans, in-period checks |

Prefer the `.rds` files in R. They keep the column types: `Date` columns and the `Powertrain` factor, whose base level is ICE.
