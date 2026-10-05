# =============================================================================
# 01_etl_merge_and_clean.R
# -----------------------------------------------------------------------------
# Purpose : Build clean, analysis-ready datasets for the BEV vs. ICE motor
#           property insurance study from the raw policy and claim extracts.
# Inputs  : data/raw/policies_raw.csv  (one row per policy-period)
#           data/raw/claims_raw.csv    (one row per claim)
# Outputs : data/processed/  (cleaned policies, cleaned claims, merged
#           frequency/severity modelling base)
# Status  : TEMPLATE - implementation pending.
# =============================================================================
#
# PLANNED WORKFLOW
# ----------------
# 1. Load raw data
#    - Read both CSVs (note: files carry a UTF-8 BOM - strip it from the first
#      column name).
#    - Enforce explicit column types; inspect row counts and structure.
#
# 2. Duplicates & keys
#    - Check Policy_ID uniqueness in policies and Claim_ID uniqueness in claims.
#    - Remove exact duplicates; investigate and resolve conflicting duplicates.
#
# 3. Date parsing & exposure
#    - Parse Start_Date, End_Date, Accident_Date.
#    - Exposure (years) = (End_Date - Start_Date + 1) / 365.25.
#    - Flag invalid periods (End < Start, zero/negative/excess exposure).
#
# 4. Rigorous join on Policy_ID
#    - Anti-join both ways: orphan claims (no matching policy) and policies
#      without claims (expected - zero-claim exposure).
#    - Validate that Accident_Date falls within the policy period.
#    - Aggregate claims to policy level (claim count, total severity) and
#      left-join onto policies so zero-claim policies are retained.
#
# 5. Missing values & label harmonisation
#    - Profile NAs per column; decide drop / impute / flag.
#    - TP_Damage_Amount NA -> 0 where no third party is involved.
#    - Harmonise Claim_Type labels (e.g. "natural hazard", "NATURAL_HAZARD ",
#      "Weather" -> Natural_Hazard; "Self Accident", "single vehicle" ->
#      Single_Vehicle_Accident; blank / "Accident" -> review).
#    - Harmonise Powertrain / Fuel_Detail (trim whitespace, case; fix typos
#      such as "Diesal"; resolve conflicts like Powertrain = BEV with
#      Fuel_Detail = PHEV).
#
# 6. Isolate property claims
#    - Study scope is property damage: use Own_Damage_Amount (and TP property
#      damage where relevant); neutralise / exclude any bodily-injury component.
#    - Drop or zero non-positive / implausible amounts; document outliers.
#
# 7. Feature engineering
#    - Driver age bands, license tenure bands.
#    - Vehicle value tiers, vehicle age bands.
#    - Powertrain factor for the study: BEV vs. ICE (decide treatment of
#      Hybrid/PHEV - separate level or excluded from the main contrast).
#    - Set reference levels for GLM factors (ICE as base for Powertrain).
#
# 8. Export
#    - Write cleaned datasets to data/processed/ (CSV and/or RDS).
#    - Log a short summary: rows in/out at each step, exclusions and reasons.
#
# CHECKLIST
# ---------
# [ ] No duplicate Policy_ID / Claim_ID in outputs
# [ ] All claims matched to a policy; accidents inside the exposure window
# [ ] Exposure strictly positive and <= ~1 year per record
# [ ] Claim_Type and Powertrain labels fully harmonised
# [ ] Bodily-injury elements excluded from property severity
# [ ] Row-count reconciliation documented at every filtering step
# [ ] Script reruns end-to-end from raw data with no manual steps
# =============================================================================

# ---- Setup -------------------------------------------------------------------
# library(tidyverse)
# library(lubridate)
# library(janitor)

# ---- 1. Load -----------------------------------------------------------------

# ---- 2. Duplicates -----------------------------------------------------------

# ---- 3. Dates & exposure -----------------------------------------------------

# ---- 4. Join -----------------------------------------------------------------

# ---- 5. Missing values & labels ----------------------------------------------

# ---- 6. Property claims ------------------------------------------------------

# ---- 7. Feature engineering --------------------------------------------------

# ---- 8. Export ---------------------------------------------------------------
