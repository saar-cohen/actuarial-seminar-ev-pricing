# =============================================================================
# 02_verify_join.R
# -----------------------------------------------------------------------------
# Purpose : Verify the policy-claim join on the CLEANED data (read-only check):
#           key, cardinality, orphans, accident-date window, reconciliation.
# Inputs  : data/processed/policies_cleaned.rds, data/processed/claims_cleaned.rds
#           data/raw/policies_raw.csv            (only to trace orphan causes)
# Outputs : data/processed/join_reconciliation.csv   (claims in -> CAT, by powertrain)
# Run     : Rscript src/02_verify_join.R      (from the repository root)
#
# Join rules checked (as used in the notebooks):
#   claims |> inner_join(policies, by = "Policy_ID", relationship = "many-to-one")
#          |> filter(between(Accident_Date, Start_Date, End_Date))   # inclusive
# Hard rules fail with stopifnot(); everything else is printed.
# =============================================================================

suppressPackageStartupMessages(suppressWarnings({
  library(tidyverse)
  library(lubridate)
}))

pol <- read_rds("data/processed/policies_cleaned.rds")
clm <- read_rds("data/processed/claims_cleaned.rds")
pol_raw <- read_csv("data/raw/policies_raw.csv", col_types = cols(.default = col_character()),
                    progress = FALSE) |>
  rename_with(~ sub("^﻿", "", .x))                      # strip UTF-8 BOM

options(width = 120)                                       # wide console tables
norm_id <- function(x) toupper(trimws(x))
say <- function(...) cat(sprintf(...), "\n", sep = "")

# ---- 1. Keys -------------------------------------------------------------------
say("== 1. Keys")
stopifnot(all(pol$Policy_ID == norm_id(pol$Policy_ID)),     # policies key normalised
          all(clm$Policy_ID == norm_id(clm$Policy_ID)),     # claims FK normalised
          !anyDuplicated(pol$Policy_ID),                    # one row per policy
          !anyDuplicated(clm$Claim_ID),                     # one row per claim
          !anyNA(pol$Policy_ID), !anyNA(clm$Policy_ID))
say("policies: %d rows, %d unique Policy_ID | claims: %d rows, %d unique Claim_ID  -> OK",
    nrow(pol), n_distinct(pol$Policy_ID), nrow(clm), n_distinct(clm$Claim_ID))

# ---- 2. Cardinality ------------------------------------------------------------
say("\n== 2. Cardinality")
joined <- inner_join(clm, pol, by = "Policy_ID", relationship = "many-to-one")  # errors if not
stopifnot(!anyDuplicated(joined$Claim_ID))                  # each claim -> at most 1 policy
say("inner_join(relationship = 'many-to-one') OK: %d claims matched, none duplicated", nrow(joined))

per_pol <- pol |>
  left_join(count(clm, Policy_ID, name = "n_claims"), by = "Policy_ID") |>
  mutate(n_claims = coalesce(n_claims, 0L),
         bucket   = if_else(n_claims >= 3, "3+", as.character(n_claims)))
say("claims per policy (all claim rows, before date filter):")
print(count(per_pol, bucket, name = "policies"))

# ---- 3. Orphans ----------------------------------------------------------------
say("\n== 3. Orphans (claim Policy_ID not in cleaned policies)")
# Trace each orphan key back to the raw policy file.
raw_trace <- pol_raw |>
  mutate(Policy_ID = norm_id(Policy_ID),
         start = coalesce(ymd(Start_Date, quiet = TRUE), dmy(Start_Date, quiet = TRUE)),
         end   = coalesce(ymd(End_Date,   quiet = TRUE), dmy(End_Date,   quiet = TRUE)),
         is1900  = year(pmin(start, end)) < 2000,
         old_bev = trimws(Powertrain) == "BEV" & trimws(Fuel_Detail) != "PHEV" &
                   year(pmin(start, end)) - as.numeric(Vehicle_Age) < 2012) |>
  summarise(is1900 = any(is1900), old_bev = any(old_bev, na.rm = TRUE), .by = Policy_ID)

orphans <- anti_join(clm, pol, by = "Policy_ID") |>
  left_join(raw_trace, by = "Policy_ID") |>
  mutate(cause = case_when(is.na(is1900) ~ "true orphan (not in raw policies)",
                           is1900        ~ "policy dropped: 1900 start",
                           old_bev       ~ "policy dropped: BEV model year < 2012",
                           .default      = "policy dropped: other"))
print(summarise(orphans, claims = n(), od_claims = sum(Own_Damage_Amount > 0),
                od_sum = sum(Own_Damage_Amount), .by = cause) |> arrange(desc(claims)))
stopifnot(!any(orphans$Claim_ID %in% joined$Claim_ID),     # excluded by inner join
          nrow(orphans) + nrow(joined) == nrow(clm))
say("total orphans: %d, all excluded by the inner join", nrow(orphans))
# Matches recovered only by key normalisation (raw claim key differs).
clm_raw_keys <- read_csv("data/raw/claims_raw.csv", col_types = cols(.default = col_character()),
                         progress = FALSE) |>
  rename_with(~ sub("^﻿", "", .x)) |> distinct(Claim_ID, Policy_ID)
n_norm <- joined |> semi_join(filter(clm_raw_keys, Policy_ID != norm_id(Policy_ID)), by = "Claim_ID") |> nrow()
say("matched claims whose raw Policy_ID needed normalisation: %d", n_norm)

# ---- 4. Accident date window ---------------------------------------------------
say("\n== 4. Accident date window (inclusive: Start <= Accident <= End; exposure = End - Start + 1)")
joined <- joined |>
  mutate(window = case_when(Accident_Date < Start_Date ~ "before start",
                            Accident_Date > End_Date   ~ "after end",
                            .default = "inside"),
         days_out = case_when(window == "before start" ~ as.numeric(Start_Date - Accident_Date),
                              window == "after end"    ~ as.numeric(Accident_Date - End_Date)))
print(summarise(joined, claims = n(), min_days = min(days_out), median_days = median(days_out),
                max_days = max(days_out), .by = window))
say("boundary hits (inside): accident = Start_Date %d, accident = End_Date %d",
    sum(joined$Accident_Date == joined$Start_Date), sum(joined$Accident_Date == joined$End_Date))
stopifnot(sum(joined$window == "before start") == 0)       # date swap repaired all X4 cases
in_period <- filter(joined, between(Accident_Date, Start_Date, End_Date))
stopifnot(nrow(in_period) == sum(joined$window == "inside"))

# ---- 5. Reconciliation ---------------------------------------------------------
say("\n== 5. Reconciliation by powertrain")
recon <- joined |>
  mutate(Powertrain = as.character(Powertrain)) |>
  bind_rows(transmute(orphans, Claim_ID, Powertrain = "(no policy)", window = "orphan")) |>
  mutate(od_in = window == "inside" & Own_Damage_Amount > 0) |>
  summarise(claims_in     = n(),
            orphans       = sum(window == "orphan"),
            out_of_period = sum(window %in% c("before start", "after end")),
            in_period     = sum(window == "inside"),
            od_claims     = sum(od_in),
            od_amount     = round(sum(Own_Damage_Amount[od_in])),
            cat_flagged   = sum(od_in & is_cat_event),
            .by = Powertrain) |>
  arrange(match(Powertrain, c("ICE", "Hybrid", "BEV")))
recon <- bind_rows(recon, summarise(recon, Powertrain = "TOTAL", across(where(is.numeric), sum)))
print(as.data.frame(recon), row.names = FALSE)
tot <- filter(recon, Powertrain == "TOTAL")
stopifnot(tot$claims_in == nrow(clm),
          tot$orphans == nrow(orphans),
          tot$claims_in - tot$orphans - tot$out_of_period == tot$in_period)

# Notebook inline rule gives the same OD claim count.
nb <- clm |> filter(Own_Damage_Amount > 0) |>
  inner_join(pol, by = "Policy_ID", relationship = "many-to-one") |>
  filter(between(Accident_Date, Start_Date, End_Date))
stopifnot(nrow(nb) == tot$od_claims)
say("notebook inline join -> %d OD claims in period (matches)", nrow(nb))

# Exposure is untouched: zero-claim policies stay in the frequency base.
freq_base <- pol |> left_join(count(nb, Policy_ID, name = "n_od"), by = "Policy_ID") |>
  mutate(n_od = coalesce(n_od, 0L))
stopifnot(nrow(freq_base) == nrow(pol),
          isTRUE(all.equal(sum(freq_base$exposure), sum(pol$exposure))),
          sum(freq_base$n_od) == nrow(nb))
say("frequency base: %d policies, exposure %.2f years (unchanged), %d with 0 OD claims",
    nrow(freq_base), sum(freq_base$exposure), sum(freq_base$n_od == 0))

write_csv(recon, "data/processed/join_reconciliation.csv")
say("\nAll join checks passed -> data/processed/join_reconciliation.csv")
