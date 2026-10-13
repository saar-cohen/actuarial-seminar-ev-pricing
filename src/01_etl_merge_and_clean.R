# =============================================================================
# 01_etl_merge_and_clean.R
# -----------------------------------------------------------------------------
# Purpose : Join the cleaned policies and claims into one modelling base.
# Inputs  : data/processed/policies_cleaned.rds, claims_cleaned.rds
#           (written by src/01_clean_datasets.R, which does the table-level cleaning)
# Outputs : data/processed/  merged frequency/severity base
# Status  : TEMPLATE - not implemented yet. Notebooks 02-03 apply these rules inline.
# =============================================================================
#
# STEPS STILL TO DO (rules in docs/data_quality_audit.md)
# 1. Inner join on Policy_ID, many-to-one; log the 51 orphan claims.
# 2. Keep only claims inside the policy period (about 70 fall after End_Date).
# 3. Own-damage claim = Own_Damage_Amount > 0, for both frequency and severity.
# 4. Keep claims with own damage > 2x vehicle value in frequency, drop them from severity (12).
# 5. Rebuild the total-loss flag to need a damage ratio >= 50%.
# 6. Cap large losses at P99.5 of severity; test P99 and no cap.
# 7. Add rating bands: driver age, tenure, vehicle value tier, vehicle age.
# 8. Build the policy-level frequency base (claim count per policy, zero-claim policies kept).
# 9. Export and write a reconciliation log (rows, exposure, claims, cost by Powertrain).
# =============================================================================

# ---- Setup -------------------------------------------------------------------
# library(tidyverse)

# ---- 1-2. Join and in-period filter --------------------------------------------

# ---- 3-5. Claim definition, severity screen, total-loss flag -------------------

# ---- 6. Large-loss cap ---------------------------------------------------------

# ---- 7. Rating bands -----------------------------------------------------------

# ---- 8. Frequency base ---------------------------------------------------------

# ---- 9. Export and reconciliation ----------------------------------------------
