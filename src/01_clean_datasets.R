# =============================================================================
# 01_clean_datasets.R
# -----------------------------------------------------------------------------
# Purpose : Clean the raw policy and claim extracts SEPARATELY (no join yet).
# Inputs  : data/raw/policies_raw.csv, data/raw/claims_raw.csv
# Outputs : data/processed/policies_cleaned.{rds,csv}
#           data/processed/claims_cleaned.{rds,csv}
#           data/processed/cleaning_log.csv   (rows in/out per step)
# Run     : Rscript src/01_clean_datasets.R      (from the repository root)
#
# Rules come from docs/data_quality_audit.md: fix what can be fixed, drop the
# few rows that can't, and log every step.
# The policy-claim join is left to src/01_etl_merge_and_clean.R.
# =============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
})

raw_dir  <- "data/raw"
out_dir  <- "data/processed"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ---- Helpers -------------------------------------------------------------------

# Read every column as raw text: no whitespace trimming, no NA conversion, so
# variants such as "Hybrid " or "N/A" stay visible to the cleaning rules.
read_raw <- function(file) {
  read_csv(file.path(raw_dir, file),
           col_types = cols(.default = col_character()),
           trim_ws = FALSE, na = character(), progress = FALSE) |>
    rename_with(~ sub("^﻿", "", .x))                     # strip UTF-8 BOM
}

# Text -> number: drops currency symbol, thousands separators and spaces.
# Blank strings become NA.
to_num <- function(x) {
  x <- str_remove_all(x, "[₪,\\s]")
  suppressWarnings(as.numeric(na_if(x, "")))
}

# Dates arrive as YYYY-MM-DD or DD/MM/YYYY.
parse_date_mixed <- function(x) {
  coalesce(ymd(x, quiet = TRUE), dmy(x, quiet = TRUE))
}

# Cleaning log: one row per step with rows before/after.
cleaning_log <- tibble(dataset = character(), step = character(), action = character(),
                       rows_before = integer(), rows_after = integer(), rows_affected = integer())

log_step <- function(dataset, step, action, before, after, affected = before - after) {
  cleaning_log <<- add_row(cleaning_log, dataset = dataset, step = step, action = action,
                           rows_before = as.integer(before), rows_after = as.integer(after),
                           rows_affected = as.integer(affected))
  message(sprintf("[%s] %-38s %-8s %6d -> %6d  (%d rows)",
                  dataset, step, action, before, after, affected))
}

# =============================================================================
# PART A: POLICIES
# =============================================================================
pol_raw <- read_raw("policies_raw.csv")

# ---- A1. Exact duplicate rows (P26) --------------------------------------------
pol <- distinct(pol_raw)                                               # -110
log_step("policies", "remove exact duplicates", "drop", nrow(pol_raw), nrow(pol))

# ---- A2. Key normalisation (X1) ------------------------------------------------
n_key <- sum(pol$Policy_ID != toupper(str_trim(pol$Policy_ID)))
pol <- mutate(pol, Policy_ID = toupper(str_trim(Policy_ID)))
log_step("policies", "normalise Policy_ID", "fix", nrow(pol), nrow(pol), n_key)

# ---- A3. Dates & exposure ------------------------------------------------------
# Mixed ISO / dd/mm formats (P21: 1,201 rows are dd/mm).
n_dmy <- sum(str_detect(pol$Start_Date, "/") | str_detect(pol$End_Date, "/"))
pol <- mutate(pol, Start_Date = parse_date_mixed(Start_Date),
                   End_Date   = parse_date_mixed(End_Date))
log_step("policies", "parse mixed date formats", "fix", nrow(pol), nrow(pol), n_dmy)

# Start > End on a second record of an already-present Policy_ID is an invalid
# re-issue (P2663026), not a period of its own -> drop before swapping.
n0  <- nrow(pol)
pol <- pol |>
  filter(!(Start_Date > End_Date & n() > 1), .by = Policy_ID)
log_step("policies", "drop invalid re-issue (Start > End)", "drop", n0, nrow(pol))

# Start > End: dates were swapped at entry (P23, 59 rows) -> swap back.
swapped <- pol$Start_Date > pol$End_Date
pol <- mutate(pol, s = pmin(Start_Date, End_Date), e = pmax(Start_Date, End_Date),
                   Start_Date = s, End_Date = e) |>
  select(-s, -e)
log_step("policies", "swap Start > End dates", "fix", nrow(pol), nrow(pol), sum(swapped))

# 1900-01-01 placeholder start (P22): exposure unknown -> drop.
n0  <- nrow(pol)
pol <- filter(pol, year(Start_Date) >= 2000)                           # -25
log_step("policies", "drop 1900 placeholder start", "drop", n0, nrow(pol))

# Overlapping mid-term re-issues (P27, 69 IDs x 2 rows): collapse each to one
# record over the union period. Other attributes are identical within the pair.
n0  <- nrow(pol)
pol <- pol |>
  group_by(Policy_ID) |>
  summarise(Start_Date = min(Start_Date), End_Date = max(End_Date),
            across(-c(Start_Date, End_Date), first), .groups = "drop")
log_step("policies", "collapse overlapping re-issues", "drop", n0, nrow(pol))

# Exposure in years, inclusive end. 0 < exposure <= 1.01 keeps 366-day
# leap-year policies (1.0021, P24).
n0  <- nrow(pol)
pol <- pol |>
  mutate(exposure = as.numeric(End_Date - Start_Date + 1) / 365.25) |>
  filter(exposure > 0, exposure <= 1.01)
log_step("policies", "keep 0 < exposure <= 1.01", "drop", n0, nrow(pol))

# ---- A4. Categoricals ----------------------------------------------------------
# District: Tel Aviv variants (P1), blank -> Unknown (P2).
n_dist <- with(pol, sum(str_trim(District) != "Tel Aviv" &
                          str_to_lower(str_trim(District)) %in% c("tlv", "tel-aviv", "tel aviv") |
                        str_trim(District) == ""))
pol <- mutate(pol, District = str_trim(District),
              District = case_when(str_to_lower(District) %in% c("tlv", "tel-aviv", "tel aviv") ~ "Tel Aviv",
                                   District == "" ~ "Unknown",
                                   .default = District))
log_step("policies", "standardise District", "fix", nrow(pol), nrow(pol), n_dist)

# Gender: code/case/space variants (P3); N/A, U, blank -> Unknown (P4).
g0  <- pol$Gender
pol <- mutate(pol, g = str_to_lower(str_trim(Gender)),
                   Gender = case_when(g %in% c("m", "male")   ~ "Male",
                                      g %in% c("f", "female") ~ "Female",
                                      .default = "Unknown")) |>
  select(-g)
log_step("policies", "standardise Gender", "fix", nrow(pol), nrow(pol), sum(g0 != pol$Gender))

# Fuel_Detail: electric synonyms -> BEV, typo Diesal -> Diesel (P6).
f0  <- pol$Fuel_Detail
pol <- mutate(pol, f = str_to_upper(str_trim(Fuel_Detail)),
                   Fuel_Detail = case_when(f %in% c("BEV", "EV", "ELECTRIC") ~ "BEV",
                                           f %in% c("DIESEL", "DIESAL")      ~ "Diesel",
                                           f == "PETROL" ~ "Petrol",
                                           f == "HEV"    ~ "HEV",
                                           f == "PHEV"   ~ "PHEV")) |>
  select(-f)
stopifnot(!anyNA(pol$Fuel_Detail))                                     # no unmapped label left
log_step("policies", "standardise Fuel_Detail", "fix", nrow(pol), nrow(pol), sum(f0 != pol$Fuel_Detail))

# Powertrain: trailing space "Hybrid " (P5).
p0  <- pol$Powertrain
pol <- mutate(pol, Powertrain = str_trim(Powertrain))
log_step("policies", "trim Powertrain", "fix", nrow(pol), nrow(pol), sum(p0 != pol$Powertrain))

# BEV with PHEV fuel (P7): a plug-in hybrid has an engine -> Hybrid. ICE = base level.
bev_phev <- pol$Powertrain == "BEV" & pol$Fuel_Detail == "PHEV"
pol <- mutate(pol, Powertrain = if_else(bev_phev, "Hybrid", Powertrain) |>
                                factor(levels = c("ICE", "Hybrid", "BEV")))
log_step("policies", "BEV + PHEV -> Hybrid", "fix", nrow(pol), nrow(pol), sum(bev_phev))

# ---- A5. Driver & vehicle ------------------------------------------------------
# Driver_Age: blank -> NA; 999 placeholder or outside 17-100 -> NA (P8, P9).
pol <- mutate(pol, Driver_Age = to_num(Driver_Age))
bad_age <- !is.na(pol$Driver_Age) & (pol$Driver_Age == 999 | pol$Driver_Age < 17 | pol$Driver_Age > 100)
pol <- mutate(pol, Driver_Age = if_else(bad_age, NA_real_, Driver_Age))
log_step("policies", "Driver_Age 999 / out of range -> NA", "fix", nrow(pol), nrow(pol), sum(bad_age))

# License_Tenure: infeasible when negative or licensed before 17 (P11).
# Only judged where Driver_Age is known, so unknown ages do not wipe tenures.
pol <- mutate(pol, License_Tenure = to_num(License_Tenure))
bad_ten <- with(pol, !is.na(Driver_Age) & !is.na(License_Tenure) &
                     (License_Tenure < 0 | Driver_Age - License_Tenure < 17))
pol <- mutate(pol, License_Tenure = if_else(bad_ten, NA_real_, License_Tenure))
log_step("policies", "infeasible License_Tenure -> NA", "fix", nrow(pol), nrow(pol), sum(bad_ten))

# Vehicle_Age: -1 (next model year) -> 0 (P12).
pol <- mutate(pol, Vehicle_Age = to_num(Vehicle_Age))
neg_va <- pol$Vehicle_Age %in% -1
pol <- mutate(pol, Vehicle_Age = if_else(neg_va, 0, Vehicle_Age))
log_step("policies", "Vehicle_Age -1 -> 0", "fix", nrow(pol), nrow(pol), sum(neg_va))

# Vehicle_Age missing or impossible (outside 0-30 years) -> drop the row.
n0  <- nrow(pol)
pol <- filter(pol, !is.na(Vehicle_Age), between(Vehicle_Age, 0, 30))
log_step("policies", "drop missing / impossible Vehicle_Age", "drop", n0, nrow(pol))

# BEV with model year before 2012 (P14): mass-market BEVs did not exist yet,
# so the age (or the powertrain) is wrong -> drop the row.
n0  <- nrow(pol)
pol <- filter(pol, !(Powertrain == "BEV" & year(Start_Date) - Vehicle_Age < 2012))
log_step("policies", "drop BEV with model year < 2012", "drop", n0, nrow(pol))

# Vehicle_Value: values in NIS thousands (P17) -> x1000; 0 placeholder (P16) -> NA.
# Blanks (P15) are already NA via to_num(). Rows are kept.
pol <- mutate(pol, Vehicle_Value = to_num(Vehicle_Value))
thous <- pol$Vehicle_Value > 0 & pol$Vehicle_Value < 5000 & !is.na(pol$Vehicle_Value)
pol <- mutate(pol, Vehicle_Value = if_else(thous, Vehicle_Value * 1000, Vehicle_Value))
log_step("policies", "Vehicle_Value in thousands x1000", "fix", nrow(pol), nrow(pol), sum(thous))
zero_v <- pol$Vehicle_Value <= 0 & !is.na(pol$Vehicle_Value)
pol <- mutate(pol, Vehicle_Value = if_else(zero_v, NA_real_, Vehicle_Value))
log_step("policies", "Vehicle_Value <= 0 -> NA", "fix", nrow(pol), nrow(pol), sum(zero_v))

# Premium: "NIS 9,999" text parsed by to_num() (P18); 0 / -1 placeholders -> NA (P19).
# Reference only: never a rating factor.
n_txt <- sum(str_detect(pol$Premium, "[₪,]"))
pol <- mutate(pol, Premium = to_num(Premium))
log_step("policies", "parse Premium text", "fix", nrow(pol), nrow(pol), n_txt)
bad_prem <- pol$Premium <= 0 & !is.na(pol$Premium)
pol <- mutate(pol, Premium = if_else(bad_prem, NA_real_, Premium))
log_step("policies", "Premium <= 0 -> NA", "fix", nrow(pol), nrow(pol), sum(bad_prem))
# Premium < 300 (P20) is left as is: those rows are short periods priced pro rata.
# Vehicle_Age 28 (P13, a likely top-code) is left for banding (20+).

# ---- A6. Final layout ----------------------------------------------------------
policies_cleaned <- pol |>
  select(Policy_ID, Start_Date, End_Date, exposure, District, Gender, Driver_Age,
         License_Tenure, Powertrain, Fuel_Detail, Vehicle_Age, Vehicle_Value, Premium)
stopifnot(!anyDuplicated(policies_cleaned$Policy_ID),
          !anyNA(policies_cleaned$Powertrain),
          all(policies_cleaned$exposure > 0 & policies_cleaned$exposure <= 1.01))

# =============================================================================
# PART B: CLAIMS
# =============================================================================
clm_raw <- read_raw("claims_raw.csv")
n0 <- nrow(clm_raw)

# ---- B1. Exact duplicate rows (C15) ---------------------------------------------
# 60 rows are byte-identical copies; no Claim_ID has conflicting content.
clm <- clm_raw |> distinct()
log_step("claims", "B1 remove exact duplicates", "drop", n0, nrow(clm))
stopifnot(!anyDuplicated(clm$Claim_ID))                     # Claim_ID is now a key

# ---- B2. Policy_ID key normalisation (X1) ---------------------------------------
# 40 keys are lowercase "p..." and/or padded; toupper(trim) recovers all of them.
n_fix <- sum(clm$Policy_ID != toupper(str_trim(clm$Policy_ID)))
clm <- clm |> mutate(Policy_ID = toupper(str_trim(Policy_ID)))
log_step("claims", "B2 normalise Policy_ID", "fix", nrow(clm), nrow(clm), n_fix)

# ---- B3. Accident_Date -> Date ----------------------------------------------------
# All dates are ISO YYYY-MM-DD; any parse failure stops the pipeline.
clm <- clm |> mutate(Accident_Date = ymd(Accident_Date, quiet = TRUE))
stopifnot(!anyNA(clm$Accident_Date))
log_step("claims", "B3 parse Accident_Date", "fix", nrow(clm), nrow(clm), 0)

# ---- B4a. Amounts: text -> numeric (C4) -------------------------------------------
# "₪7,815" / "22,563.05" text and float artefacts (1018120.0000000001) -> 2 dp.
n_fix <- sum(str_detect(clm$Own_Damage_Amount, "[₪,\\s]") |
             str_detect(clm$TP_Damage_Amount,  "[₪,\\s]"))           # rows, not cells
clm <- clm |>
  mutate(across(c(Own_Damage_Amount, TP_Damage_Amount), ~ round(to_num(.x), 2)))
stopifnot(!anyNA(clm$Own_Damage_Amount))                    # OD is never blank
log_step("claims", "B4a parse amounts (text -> num)", "fix", nrow(clm), nrow(clm), n_fix)

# ---- B4b. Negative own damage (C7) ------------------------------------------------
# All Collision_No_TP with no parent claim to net against -> unrecoverable, drop.
n_before <- nrow(clm)
clm <- clm |> filter(Own_Damage_Amount >= 0)
log_step("claims", "B4b drop Own_Damage_Amount < 0", "drop", n_before, nrow(clm))

# ---- B4c. Blank TP amount -> 0 (C13) -----------------------------------------------
# "No TP" is stored as blank or 0.0; unify on 0.
n_fix <- sum(is.na(clm$TP_Damage_Amount))
clm <- clm |> mutate(TP_Damage_Amount = coalesce(TP_Damage_Amount, 0))
log_step("claims", "B4c blank TP_Damage_Amount -> 0", "fix", nrow(clm), nrow(clm), n_fix)
# Own damage = 0 rows (TP-only / closed without payment) are KEPT: the own-damage
# claim definition (OD > 0) is applied later, at the frequency/severity stage.

# ---- B5. Claim_Type recode (C1-C3) -------------------------------------------------
# Case/space/synonym variants -> canonical labels. Blank with TP > 0 is almost
# surely Collision_With_TP; other blanks and the vague "Accident" -> Unspecified.
clm <- clm |>
  mutate(
    type_raw = Claim_Type,
    type_key = str_replace_all(str_to_lower(str_trim(Claim_Type)), "[ _]+", "_"),
    Claim_Type = case_when(
      type_key %in% c("single_vehicle_accident", "self_accident", "single_vehicle") ~ "Single_Vehicle_Accident",
      type_key %in% c("natural_hazard", "weather", "flood")                          ~ "Natural_Hazard",
      type_key == "" & TP_Damage_Amount > 0                                          ~ "Collision_With_TP",
      type_key %in% c("", "accident")                                                ~ "Unspecified",
      type_key == "collision_with_tp"                                                ~ "Collision_With_TP",
      type_key == "collision_no_tp"                                                  ~ "Collision_No_TP",
      type_key == "malicious_damage"                                                 ~ "Malicious_Damage",
      type_key == "theft"                                                            ~ "Theft",
      type_key == "fire"                                                             ~ "Fire"
    ))
stopifnot(!anyNA(clm$Claim_Type))                           # no unmapped label left
n_fix <- sum(clm$Claim_Type != clm$type_raw)
log_step("claims", "B5 recode Claim_Type", "fix", nrow(clm), nrow(clm), n_fix)
clm <- clm |> select(-type_raw, -type_key)

# ---- B6a. CAT event flag (C17) ------------------------------------------------------
# Storm of 2025-01-19: kept as real loss, flagged for the without-CAT sensitivity.
clm <- clm |>
  mutate(is_cat_event = Accident_Date == as.Date("2025-01-19") & Claim_Type == "Natural_Hazard")
log_step("claims", "B6a flag CAT event 2025-01-19", "flag", nrow(clm), nrow(clm), sum(clm$is_cat_event))

# ---- B6b. Total-loss flag (C10) -----------------------------------------------------
# Keep the original 0/1 flag; the clean flag needs a positive own-damage amount.
# (The ratio-to-value screen, C11-C12, needs Vehicle_Value -> merge script.)
clm <- clm |>
  mutate(Is_Total_Loss       = as.integer(Is_Total_Loss),
         is_total_loss_clean = Is_Total_Loss == 1 & Own_Damage_Amount > 0)
stopifnot(!anyNA(clm$Is_Total_Loss))
log_step("claims", "B6b total-loss flag reset (OD = 0)", "flag", nrow(clm), nrow(clm),
         sum(clm$Is_Total_Loss == 1 & !clm$is_total_loss_clean))

# ---- B7. Final column order ---------------------------------------------------------
claims_cleaned <- clm |>
  select(Claim_ID, Policy_ID, Accident_Date, Claim_Type, Own_Damage_Amount,
         TP_Damage_Amount, Is_Total_Loss, is_total_loss_clean, is_cat_event)
stopifnot(!anyNA(claims_cleaned), all(claims_cleaned$TP_Damage_Amount >= 0))
# Left as is: OD = 250 (C9, 12 rows) and Theft with TP > 0 (C14, 20 rows) do not
# change the own-damage study; same-day claims on one policy (C16) look genuine.

# =============================================================================
# EXPORT
# =============================================================================
write_rds(policies_cleaned, file.path(out_dir, "policies_cleaned.rds"))
write_csv(policies_cleaned, file.path(out_dir, "policies_cleaned.csv"), na = "")
write_rds(claims_cleaned,   file.path(out_dir, "claims_cleaned.rds"))
write_csv(claims_cleaned,   file.path(out_dir, "claims_cleaned.csv"),   na = "")
write_csv(cleaning_log,     file.path(out_dir, "cleaning_log.csv"))

message(sprintf("\nDone. policies: %d rows, claims: %d rows -> %s/",
                nrow(policies_cleaned), nrow(claims_cleaned), out_dir))
