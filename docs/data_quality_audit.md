# Data Quality, Integrity & Anomaly Audit

**Scope:** `data/raw/policies_raw.csv` (38,592 rows, 12 columns), `data/raw/claims_raw.csv` (6,664 rows, 7 columns), `notebooks/01_eda_policies.ipynb`, `notebooks/02_eda_claims.ipynb`.
**Method:**
- Four parallel audits: policies, claims, cross-table integrity, and an actuarial best-practice review.
- Every count comes from code run on the raw files, read as untrimmed text.
- Percentages use the raw row count of the table concerned unless stated otherwise.
**Date:** 2026-10-12

---

## Executive summary

1. **The data is usable, but it needs about 25 explicit cleaning rules.**
   - 15.3% of policy rows (5,895) carry at least one issue.
   - Most issues can be fixed deterministically: label variants, date formats, currency text, unit errors and swapped dates.
   - Only a small number need to be excluded.
2. **Invalid policy periods move the BEV/ICE frequency ratio more than anything else.**
   - 25 policies have a `1900-01-01` placeholder start date. Each then counts as a ~125-year exposure: ~2,351 years added to ICE and ~859 to Hybrid.
   - Left in, they move the crude BEV/ICE frequency ratio from **1.057 to 1.148**.
   - All other cross-table defects combined move it by only ~1%.
3. **The notebook's 72 "orphan" claims are mostly a key-formatting error.**
   - 40 of the 72 have a lowercase and/or space-padded `Policy_ID` (`'p2032624 '`). They match once the key is normalised with `toupper(trimws())`.
   - Only **32 claims** are true orphans after de-duplication.
4. **The policy file has no renewals.**
   - 70 `Policy_ID`s have two records with the same end date and an overlapping later start. These are mid-term re-issues, not new periods.
   - Summing both records double-counts ~48 vehicle-years. Each pair must collapse to one record.
5. **The claims severity tail has entry errors.**
   - 10 own-damage amounts of ₪310k–1.56M are 6–45× the vehicle value, are not flagged as total losses, and are typed as whole numbers.
   - The total-loss flag is unreliable at the bottom of the distribution: 38 "total losses" are below 50% of vehicle value, and 21 of the 25 Malicious-Damage total losses are below 10%.
6. **About 82 BEVs are 15–25 years old.** That is infeasible, because mass-market BEVs only exist from about 2012 and these policies start in 2024. The notebook does not handle them.
7. **There was a catastrophe event on 2025-01-19:** 564 claims, 8.5% of all claims, mostly natural hazard. It is real, not an error, and needs a flag. The BEV/ICE ratio is robust to it (1.059 without it).
8. **The notebooks contain ~20 ad-hoc cleaning steps,** some inconsistent between the two notebooks and some with side-effects. All of them belong in `src/01_etl_merge_and_clean.R` (currently an empty template), and the notebooks should then read `data/processed/`.

---

## 1. Anomaly matrix

### 1A. Policies (`policies_raw.csv`, N = 38,592)

| # | Issue | Column(s) | Rows | % | Example records |
|---|---|---|---|---|---|
| P1 | Tel Aviv spelling variants (`TLV` 97, `Tel-Aviv` 88, `tel aviv` 78) | District | 263 | 0.68 | P2633396 `TLV`; P2859635 `Tel-Aviv`; P2065497 `tel aviv` |
| P2 | Blank district | District | 180 | 0.47 | P2307151 `""` |
| P3 | Gender code/case/whitespace variants (`M` 504, `F` 447, `␠male` 162, `female␠` 138) | Gender | 1,251 | 3.24 | P2886837 `M`; P2236579 `male` |
| P4 | Gender unknown (`""` 138, `N/A` 152, `U` 134) | Gender | 424 | 1.10 | P2631194 `N/A`; P2165687 `U` |
| P5 | Powertrain trailing whitespace (`Hybrid␠`) | Powertrain | 210 | 0.54 | `Hybrid␠` |
| P6 | Fuel label variants (`bev` 148, `Electric` 145, `EV` 139, `Diesal` 140) | Fuel_Detail | 572 | 1.48 | P2117149 BEV/`Electric`; P2976704 ICE/`Diesal` |
| P7 | **Powertrain = BEV but Fuel_Detail = PHEV**: the only logical conflict. There are no BEV+Petrol/Diesel and no ICE+electric rows. | Powertrain × Fuel_Detail | 76 | 0.20 | P2851303 BEV/PHEV/137,600; P2038640 BEV/PHEV/81,000 |
| P8 | Driver_Age blank | Driver_Age | 552 | 1.43 | P2582638 `""` / tenure 43 |
| P9 | Driver_Age = 999 placeholder. This is the only value above 95; there are no ages below 17. | Driver_Age | 65 | 0.17 | P2730603 999/47; P2747995 999/0 |
| P10 | License_Tenure blank (negative tenure: 0 rows) | License_Tenure | 280 | 0.73 | — |
| P11 | Infeasible tenure: Age − Tenure < 17. The count is the same at a threshold of 16. | Driver_Age, License_Tenure | 85 | 0.22 | P2636956 age 22 / tenure 24; P2016396 29/28 |
| P12 | Vehicle_Age = −1 (ICE 24, Hybrid 6, BEV 5) | Vehicle_Age | 35 | 0.09 | P2467793 Hybrid −1 |
| P13 | Vehicle_Age = 28 spike. Age 27 has 29 rows and age 28 has 104, all ICE, so this is likely a top-code. | Vehicle_Age | 104 | 0.27 | P2036487 ICE 28 / 11,800 |
| P14 | **BEV with Vehicle_Age > 12**, i.e. a model year before 2012. The BEV age distribution has a gap at 13–14 and a flat block at 15–25. | Vehicle_Age, Powertrain | 82 | 0.21 (1.88% of BEV) | P2886837 BEV age 22 / ₪187,000; P2246419 BEV 16 / ₪118,100 |
| P15 | Vehicle_Value blank | Vehicle_Value | 323 | 0.84 | P2876551 ICE `""` |
| P16 | Vehicle_Value = 0 placeholder. There are no −1 / 99999 / 999999 values. | Vehicle_Value | 45 | 0.12 | P2301654 ICE 0; P2579139 Hybrid 0 |
| P17 | Vehicle_Value recorded in ₪ thousands: decimals between 20.2 and 241.6, which are exactly all values below 5,000 | Vehicle_Value | 130 | 0.34 | P2256810 ICE 149.7; P2984342 BEV 37.4 |
| P18 | Premium as text (`₪9,999` 110 + `₪99,999` 4 = 114; `9,999` 85 + `99,999` 3 = 88) | Premium | 202 | 0.52 | P2699780 `₪12,212`; P2003175 `4,539` |
| P19 | Premium placeholder: 0 (21 rows) or −1 (19 rows) | Premium | 40 | 0.10 | P2875227 0; P2554982 −1 |
| P20 | Premium implausibly low (0 < Premium < 300) | Premium | 115 | 0.30 | P2505600 ICE 236 |
| P21 | Start_Date in `dd/mm/yyyy` (728 have day > 12; none has month > 12) | Start_Date | 1,201 | 3.11 | P2626328 `29/04/2024` |
| P22 | Start_Date placeholder `1900-01-01` (25 after removing exact duplicates) | Start_Date | 26 | 0.07 | P2303896 1900-01-01 → 2025-10-11 (45,940 days) |
| P23 | Start > End, i.e. negative exposure. In 54 of the 60 rows the difference is exactly −364 or −365 days, so the dates were swapped. | Start_Date, End_Date | 60 | 0.16 | P2451663 2025-06-17 → 2024-06-18 |
| P24 | Exposure > 1.0 but legitimate: 366-day policies spanning 29 Feb 2024 (exposure 1.0021). **A strict (0, 1] rule would drop these.** | derived | 5,579 | 14.46 | — |
| P25 | Very short period (< 30 days) | derived | 113 | 0.29 | P2863874 20 days |
| P26 | Exact full-row duplicates (110 pairs) | all | 110 | 0.29 | P2006296 ×2; P2459394 ×2 (also a 1900 row) |
| P27 | Same Policy_ID, different Start_Date only, overlapping, same End_Date (mid-term re-issue) | Policy_ID, Start_Date | 70 IDs (140 rows) | 0.36 | P2010004: 2024-11-27 and 2025-01-09, both ending 2025-11-26 |

*Rows with ≥1 issue: 5,895 (15.28%). Rows with ≥2 issues: 421. These counts exclude the legitimate leap-year rows (P24).*

### 1B. Claims (`claims_raw.csv`, N = 6,664)

| # | Issue | Column(s) | Rows | % | Example records |
|---|---|---|---|---|---|
| C1 | Claim_Type case/space/synonym variants (`Self Accident` 82, `single vehicle` 77, `Weather` 48, `NATURAL_HAZARD␠` 41, `natural hazard` 32, `Flood` 29) | Claim_Type | 309 | 4.64 | C779637 `NATURAL_HAZARD␠` |
| C2 | Claim_Type blank. 43 of the 122 carry a TP amount, so they are most likely Collision_With_TP. | Claim_Type | 122 | 1.83 | C945398 `""` OD 0 / TP 26,014 |
| C3 | Ambiguous label `Accident`. None has a TP amount. | Claim_Type | 86 | 1.29 | C743429 `Accident` 32,254 |
| C4 | Amounts as text (`₪7,815`, `22,563.05`); 0 rows fail to parse once these are cleaned | Own_Damage_Amount, TP_Damage_Amount | 343 (OD 282, TP 61) | 5.15 | C853097 `1018120.0000000001` |
| C5 | Own damage = 0 **with** TP > 0: a TP-only claim, which is not an own-damage event | Own_Damage_Amount | 264 | 3.96 | C849378 CwTP OD 0 / TP 3,967 |
| C6 | Own damage = 0, no TP: closed without payment | Own_Damage_Amount | 81 | 1.22 | C761206 Natural_Hazard OD 0 |
| C7 | Own damage < 0. All 36 are Collision_No_TP, none offsets a positive claim, and 4 are flagged total loss. | Own_Damage_Amount | 36 | 0.54 | C936030 −3,450.51 |
| C8 | **Own damage > 2× vehicle value, not total loss.** 10 of the 12 are whole-number ₪310k–1.56M amounts, i.e. entry errors. | OD vs Vehicle_Value | 12 | 0.18 | C704210 ₪1,557,232 vs value 34,600 (45×); C854225 ₪312,009 vs 15,700 |
| C9 | Own damage = 250.0, repeated: a placeholder or deductible artefact | Own_Damage_Amount | 12 | 0.18 | C943803; C738173 |
| C10 | Total loss with own damage ≤ 0 | Is_Total_Loss | 13 | 0.20 | C761920 SVA OD 0; C860251 −3,403 |
| C11 | **Total loss with own damage < 50% of vehicle value.** 34 of them are below 10%; 21 of the 25 Malicious-Damage total losses are below 10%. | Is_Total_Loss vs ratio | 38 | 0.57 | C796534 Malicious ₪1,642 vs ₪140,200 (1.2%) |
| C12 | Not total loss but own damage ≥ 70% of vehicle value (13 of these are ≥ 100%) | Is_Total_Loss vs ratio | 15 | 0.23 | C757336 Natural_Hazard 0.90×; C707844 Fire 1.62× |
| C13 | "No TP" stored two ways: blank (structural) vs explicit `0.0` | TP_Damage_Amount | 151 | 2.27 | C930383 SVA TP `0.0` |
| C14 | TP > 0 on Theft | TP_Damage_Amount | 20 | 0.30 | C715914 Theft TP 7,869.76 |
| C15 | Exact duplicate rows. There are 0 conflicting duplicate Claim_IDs. | all | 60 | 0.90 | C706361 ×2; C914733 ×2 (₪175,118) |
| C16 | Same policy and date, different Claim_IDs. All 3 groups have different types and amounts, so they look genuine. | Policy_ID, Accident_Date | 6 (3 groups) | 0.09 | P2571199 2025-04-04: Malicious + Self Accident |
| C17 | CAT event: 564 claims on 2025-01-19. The next-busiest day has 27. | Accident_Date | 564 | 8.46 | mostly Natural_Hazard, Center/Tel Aviv |

Severity reference: own damage > 0 has p50 ₪5,455, p95 ₪57,848, p99 ₪127,321, p99.5 ₪153,063, p99.9 ₪506,322 and max ₪1,557,232.

### 1C. Cross-table integrity

| # | Issue | Rows | % | Example records |
|---|---|---|---|---|
| X1 | **Claim Policy_ID lowercase `p…`, 22 of them also with a trailing space.** Trimming alone recovers none; `toupper(trimws())` recovers all 40. | 40 | 0.60 of claims | C767861 `'p2032624 '`; C919759 `'p2371074'` |
| X2 | True orphan claims, with no policy after normalisation. They carry ₪309,690 of own damage (0.34%). | 33 raw / 32 after removing duplicates | 0.50 | C928394 → P2465223; C812597 → P2650229 (Theft, ₪22,073) |
| X3 | Join fan-out on the raw keys. After de-duplication and normalisation, 9 claims still match 2 records: 2 resolve by date, and 7 fall inside both records with the same attributes. | 24 claims doubled | 0.36 | C997641 / P2033161 |
| X4 | Accident before Start_Date. **All 13 are on swapped-date policies (P23)** and fall inside the corrected period. | 13 | 0.20 | C848676 / P2154649 |
| X5 | **Accident after End_Date** by 6–119 days (median 57.5). None is off by one day. These are probably claims on renewals that are missing from the policy file. | 70 | 1.05 | C859871 / P2029721 +6 days; C852157 / P2500960 +119 days |
| X6 | Claims on policies with a 1900 placeholder start, which fall "inside" the period only because of the placeholder | 5 | 0.08 | C733175 / P2716070 |
| X7 | Late-2025 reporting lag: ~27 fewer claims than expected in Sep–Dec 2025 (~0.4%). Not material. | — | — | — |

*Policies without claims: 85.0%. That is expected, since they are the zero-claim exposure.*

### 1D. What the anomalies do to the study's key number

Crude claim frequency is claims divided by exposure-years. Powertrain was trimmed in every scenario.

| Scenario | Freq BEV | Freq ICE | **BEV/ICE** |
|---|---|---|---|
| A. Naive raw join, all rows (including 1900 and swapped periods) | .1870 | .1628 | **1.148** |
| A2. Naive raw join, valid periods only | .1867 | .1784 | 1.047 |
| B. Fully cleaned (keys normalised, duplicates removed, orphans and out-of-period claims dropped) | .1856 | .1757 | **1.057** |
| B2. B, with swapped dates repaired | .1859 | .1757 | 1.058 |
| B3. B, without the CAT day | .1701 | .1606 | 1.059 |

**Conclusion:**
- The 25 policies with a 1900 start date alone inflate the apparent BEV disadvantage from ~6% to ~15%.
- Every other fix moves it by about 1 point.
- The CAT event changes the level of frequency but not the BEV/ICE ratio.

---

## 2. Recommended actuarial treatment

Each rule below is labelled **[S]** if a source supports it and **[J]** if it is actuarial judgment. Sources:
- **GLM-M:** Goldburd et al., *GLMs for Insurance Rating* (CAS Monograph 5)
- **W&M:** Werner & Modlin, *Basic Ratemaking*
- **NSW18:** Noll, Salzmann & Wüthrich (2018), French MTPL case study
- **O&J:** Ohlsson & Johansson (2010)
- **IR:** the `insurancerating` R package

**General principles**
- Flag every rule in a `dq_*` column rather than dropping rows silently.
- Write corrected values to new columns.
- Keep a row, exposure and claim reconciliation table at every step, split by Powertrain.

| Issue(s) | Treatment | Rationale |
|---|---|---|
| P1–P6, C1, C13 Label / whitespace / case variants | **Deterministic correction** with an explicit dictionary. Use the CBS district list. Blank and unknown values become an `"Unknown"` level, not imputed values (P2, P4). | Split levels give sparse, unstable relativities. An explicit Unknown level is the GLM-M recommendation for categorical missingness, and with ≤1.1% of rows it costs almost nothing [S: GLM-M ch. 2]. |
| P7 BEV + PHEV | **Correct `Powertrain` to `Hybrid`.** Fuel_Detail is the more granular field. Flag the rows and run a sensitivity check that excludes them. | A plug-in hybrid has an engine. Misclassifying it as BEV directly biases the parameter of interest [J]. |
| Hybrid level generally | **Keep it as a separate level.** Do not merge it into ICE or BEV. Base level is ICE, the largest exposure. | Keeps the BEV vs. ICE contrast clean. The PHEV battery affects repair cost [S: GLM-M base-level guidance; J]. |
| P8, P9 Age blank or 999 | **Set to NA** (617 rows) and use an `"Unknown"` age band. Imputation can be a sensitivity run. | A placeholder used as a number creates extreme leverage under a log link [S: GLM-M]. |
| P11 Age − Tenure < 17 | **Set tenure to NA** and flag the row. Apply the rule **only where age is known**. | The minimum licence age in Israel is 17 for category B [S: AACI]. The notebook's rule wiped 610 valid tenures as a side-effect (§4). |
| P12 Vehicle_Age −1 | **Correct to 0.** A model year one later than the start year is normal for new-car registrations. | Deterministic, with no information loss [J]. |
| P13 Vehicle_Age 28 | **Keep it,** inside a top band such as `20+`. | It is consistent with a top-code, and banding neutralises it [J]. |
| P14 BEV older than 12 | **Set Vehicle_Age to NA** and flag the row (`dq_bev_age`). Exclude these rows from the main BEV model and check sensitivity. | BEVs before 2011–12 did not exist in volume. Israel's only earlier stock was the Better Place Fluence (2012, fewer than 1,000 cars). Age drives value and repair cost and confounds the BEV effect [S: Nissan, ToI; J for the cutoff]. |
| P15, P16 Value blank or 0 | **Set to NA** (368 rows), use an `"Unknown"` value band, and flag the row. Impute within Powertrain × Vehicle_Age only as a sensitivity run. | A placeholder value distorts the value slope, and value is strongly correlated with BEV status [S: GLM-M]. |
| P17 Value in ₪ thousands | **Multiply by 1,000** when the value is between 0 and 5,000. | All 130 cases fall in 20.2–241.6, which is plausible as thousands. Fully deterministic [J]. |
| P18–P20 Premium | **Parse** by removing `₪` and `,`. Set values ≤ 0 to NA. **Never use Premium as a predictor.** Use it only for loss-ratio comparisons. | Premium is the output of the old tariff on the same factors, so using it causes leakage and collinearity [S: GLM-M on offsets; J]. |
| P21 Mixed date formats | **Parse both formats** (`ymd`, then `dmy`). | All 1,201 are unambiguously dd/mm. |
| P23 Start > End | **Swap the dates** and flag the row. This recovers 12 claims and 57 exposure-years. | 54 of the 60 are exact one-year swaps, and all 13 "before-start" claims (X4) fall inside the corrected period [J]. |
| P22 1900 start | **Exclude** (25 policies, 5 claims) and log them. Imputing `End − 364` is a sensitivity run only. | Exposure is unknown. Left in, these rows move BEV/ICE by about 9 points (§1D) [J]. |
| P24, P25 Exposure | `exposure = (End − Start + 1) / 365.25`. Keep rows with 0 < exposure ≤ 1.01. Keep short periods but flag them. | Inclusive-end is confirmed: boundary accidents fall on Start and End, but none on End+1. NSW18 caps exposure at 1 [S]. |
| P26 Exact duplicate policies | **Remove** (110 rows). | They double-count exposure, which pushes frequency down [S: IR]. |
| P27 Overlapping re-issues | **Collapse to one record per Policy_ID covering the union period** (earliest valid start, common end). Drop the invalid second record of P2663026. | These are not renewals. Summing both records double-counts ~48 years. Attributes match across the pair, so collapsing is safe [S: IR `merge_date_ranges`]. |
| X1 Key formatting | **Normalise both keys** with `toupper(trimws())` before any join. | Recovers 40 claims that would otherwise be lost (6 BEV, 9 Hybrid, 25 ICE). |
| X2 Orphans | **Exclude** them and log the count and amount. | They have no covariates. The orphan rate of 0.5% is below the 1–2% investigation threshold [J]. |
| X3 Fan-out | **Assert many-to-one** after de-duplication: `relationship = "many-to-one"`. | Guards against silently double-counting claims. |
| X5 Accident after End | **Exclude** them (70 claims) and log them. | Their exposure is not in the file. Keeping them inflates frequency, though only slightly: rates are BEV 0.78%, ICE 1.03%, Hybrid 1.30% [S: IR `active_rows_by_date`]. |
| C15 Duplicate claims | **Remove exact duplicates** (60) **before** aggregating. | Duplicates inflate both frequency and severity. |
| C16 Same policy, same date | **Keep them as separate claims.** | Different perils and amounts mean they are not split lines of one event [J]. |
| C2, C3 Blank or `Accident` type | Blank with TP > 0 becomes **Collision_With_TP** (flagged, 43 rows). Other blanks and `Accident` become **`Unspecified`**, kept as their own level. | Do not guess. The notebook currently merges the two groups without saying so. |
| C5–C7 Own damage ≤ 0 | **Own-damage claim = `own_damage > 0`, used for both frequency and severity.** Exclude TP-only rows (264), closed-without-payment rows (81) and negatives (36) from the own-damage models. Counting zero-payment claims is a sensitivity run. | Frequency and severity must use the same claim definition so that freq × sev = pure premium. Gamma severity requires values > 0. The negatives have no parent claim to net against [S: GLM-M, O&J ch. 2]. |
| C8 Own damage > 2× value | Keep the claim in the **frequency count**. Exclude it **from severity** as an entry error and flag it. | The event happened but its amount is wrong [J]. |
| C9 Own damage = 250 | Flag the row and keep it. | It is too small to matter, so a sensitivity check is enough. |
| Large losses | **Cap own damage at P99.5** of the clean severity sample (≈ ₪142k once the 12 entry errors are removed; ₪153k on the raw positive amounts). Redistribute the excess as a uniform loading. Test P99, P99.5 and no cap. | A Gamma GLM is sensitive to extreme values. Capping keeps the rate level, while dropping large losses would understate it [S: W&M ch. 6; IR `redistribute_excess_loss`]. |
| C10–C12 Total-loss flag | **Rebuild it:** `tl_clean = Is_Total_Loss == 1 & own_damage > 0 & ratio >= 0.5`. Flag rows where TL = 0 and ratio ≥ 0.7. **Never use the flag as a predictor.** | The market threshold for constructive total loss is about 60% [J]. Above the 10th percentile of total losses the ratio distribution is tight (median 0.906), so the bottom tail is mis-flagged. |
| C14 Theft with TP > 0 | Flag it for review. | It does not affect the own-damage study. |
| C17 CAT event | **Keep it,** with `cat_event = Accident_Date == "2025-01-19" & type == "Natural_Hazard"`. Run a sensitivity check without it. | It is real loss, but it is non-recurring. BEV/ICE is robust to it (1.059). |
| Bodily injury | **No action needed.** The extract has no BI field. TP_Damage_Amount is TP property. | In Israel, BI sits in the separate compulsory policy under the Road Accident Victims Compensation Law (1975) [S]. |

---

## 3. ETL action items: `src/01_etl_merge_and_clean.R`

The steps follow the existing template. Each step writes a row to a reconciliation `log` (policies, exposure, claims and own-damage sum, split by Powertrain).

```r
library(tidyverse); library(lubridate)

# ---- 1. Load: raw text, BOM stripped, NO auto-trim (so variants stay visible) ----
read_raw <- function(f) read_csv(f, col_types = cols(.default = col_character()),
                                 trim_ws = FALSE, na = character()) |>
  rename_with(~ sub("^﻿", "", .x))
pol_raw <- read_raw("data/raw/policies_raw.csv")
clm_raw <- read_raw("data/raw/claims_raw.csv")

num   <- function(x) as.numeric(str_remove_all(x, "[₪,\\s]"))   # "₪12,212" -> 12212
blank <- function(x) if_else(str_trim(x) %in% c("", "N/A", "NA", "U"), NA_character_, str_trim(x))
parse_dt <- function(x) coalesce(ymd(x, quiet = TRUE), dmy(x, quiet = TRUE))

# ---- 2a. Policies: exact duplicates, then key normalisation ------------------
pol <- pol_raw |>
  distinct() |>                                                    # -110
  mutate(Policy_ID = toupper(str_trim(Policy_ID)))

# ---- 3. Dates & exposure --------------------------------------------------------
pol <- pol |>
  mutate(start = parse_dt(Start_Date), end = parse_dt(End_Date),
         dq_date_swapped = start > end,                           # 60 -> repair
         s = pmin(start, end), e = pmax(start, end), start = s, end = e,
         dq_start_placeholder = year(start) < 2000) |>             # 25 -> exclude
  select(-s, -e) |>
  filter(!dq_start_placeholder)

# Overlapping re-issues (70 IDs): one record per Policy_ID over the union period
pol <- pol |>
  group_by(Policy_ID) |>
  mutate(dq_reissue = n() > 1) |>
  summarise(start = min(start), end = max(end),
            across(-c(start, end), first), .groups = "drop") |>
  mutate(exposure = as.numeric(end - start + 1) / 365.25,
         dq_short_period = exposure < 30 / 365.25) |>
  filter(exposure > 0, exposure <= 1.01)                          # keeps 366-day leap-year policies
stopifnot(!anyDuplicated(pol$Policy_ID))

# ---- 5a. Policy attributes ------------------------------------------------------
pol <- pol |>
  mutate(
    District = case_when(str_to_lower(str_trim(District)) %in% c("tlv", "tel-aviv", "tel aviv") ~ "Tel Aviv",
                         is.na(blank(District)) ~ "Unknown", .default = str_trim(District)),
    Gender   = case_match(str_to_lower(blank(Gender)), c("m", "male") ~ "Male",
                          c("f", "female") ~ "Female", .default = "Unknown"),
    Fuel_Detail = case_match(str_to_upper(str_trim(Fuel_Detail)),
                             c("BEV", "EV", "ELECTRIC") ~ "BEV", c("DIESEL", "DIESAL") ~ "Diesel",
                             "PETROL" ~ "Petrol", "HEV" ~ "HEV", "PHEV" ~ "PHEV"),
    Powertrain = str_trim(Powertrain),
    dq_bev_phev = Powertrain == "BEV" & Fuel_Detail == "PHEV",     # 76 -> Hybrid
    Powertrain = if_else(dq_bev_phev, "Hybrid", Powertrain) |>
                 factor(levels = c("ICE", "Hybrid", "BEV")),       # ICE = base level

    Driver_Age     = num(Driver_Age),
    dq_age_invalid = is.na(Driver_Age) | Driver_Age < 17 | Driver_Age > 95,
    Driver_Age     = if_else(dq_age_invalid, NA_real_, Driver_Age),
    License_Tenure = num(License_Tenure),
    dq_tenure_infeasible = !is.na(Driver_Age) & !is.na(License_Tenure) &
                           (License_Tenure < 0 | Driver_Age - License_Tenure < 17),   # 85
    License_Tenure = if_else(dq_tenure_infeasible, NA_real_, License_Tenure),

    Vehicle_Age = num(Vehicle_Age),
    Vehicle_Age = if_else(Vehicle_Age == -1, 0, Vehicle_Age),                         # 35
    dq_bev_age  = Powertrain == "BEV" & year(start) - Vehicle_Age < 2012,            # 82
    Vehicle_Age = if_else(dq_bev_age, NA_real_, Vehicle_Age),

    Vehicle_Value = num(Vehicle_Value),
    dq_value_thousands = !is.na(Vehicle_Value) & Vehicle_Value > 0 & Vehicle_Value < 5000,   # 130
    Vehicle_Value = case_when(Vehicle_Value <= 0 ~ NA_real_,                          # 45 (+323 blank)
                              dq_value_thousands ~ Vehicle_Value * 1000,
                              .default = Vehicle_Value),

    Premium = num(Premium),
    Premium = if_else(Premium > 0, Premium, NA_real_)               # 40; analysis only, NOT a rating factor
  )

# ---- 2b. Claims: exact duplicates, keys, amounts, labels -------------------------
clm <- clm_raw |>
  distinct() |>                                                    # -60
  mutate(
    Policy_ID     = toupper(str_trim(Policy_ID)),                  # recovers 40
    accident_date = ymd(Accident_Date),
    own_damage    = round(num(Own_Damage_Amount), 2),
    tp_damage     = coalesce(round(num(TP_Damage_Amount), 2), 0),  # blank == 0.0 == no TP
    type_key      = str_replace_all(str_to_lower(str_trim(Claim_Type)), "[ _]+", "_"),
    claim_type = case_when(
      type_key %in% c("natural_hazard", "weather", "flood") ~ "Natural_Hazard",
      type_key %in% c("single_vehicle_accident", "self_accident", "single_vehicle") ~ "Single_Vehicle_Accident",
      type_key == "" & tp_damage > 0 ~ "Collision_With_TP",        # 43, flagged below
      type_key %in% c("", "accident") ~ "Unspecified",
      .default = str_trim(Claim_Type)),
    dq_type_inferred = type_key == "" & tp_damage > 0,
    dq_theft_tp      = claim_type == "Theft" & tp_damage > 0,
    dq_od_250        = own_damage == 250,
    cat_event        = accident_date == ymd("2025-01-19") & claim_type == "Natural_Hazard"
  )

# ---- 4. Join: orphans, fan-out guard, period check ------------------------------
orphans <- anti_join(clm, pol, by = "Policy_ID")                  # 37 = 32 true orphans + 5 on excluded 1900 policies; log count + OD sum
clm <- clm |>
  inner_join(pol |> select(Policy_ID, start, end, Vehicle_Value, Powertrain),
             by = "Policy_ID", relationship = "many-to-one") |>
  mutate(in_period = accident_date >= start & accident_date <= end) |>
  filter(in_period)                                               # drops ~70 after-end, log it

# ---- 6. Own-damage claim definition, severity screens, total-loss flag -----------
clm <- clm |>
  mutate(
    damage_ratio   = own_damage / Vehicle_Value,
    is_od_claim    = own_damage > 0,                              # excludes 264 TP-only, 81 closed without payment, 36 negative
    dq_od_entry_error = is_od_claim & !is.na(damage_ratio) & damage_ratio > 2 & Is_Total_Loss == "0",  # 12
    in_severity    = is_od_claim & !dq_od_entry_error,
    tl_clean       = Is_Total_Loss == "1" & is_od_claim & coalesce(damage_ratio >= 0.5, TRUE),
    dq_tl_mismatch = (Is_Total_Loss == "1" & !tl_clean) |
                     (Is_Total_Loss == "0" & coalesce(damage_ratio >= 0.7, FALSE))
  )
cap <- quantile(clm$own_damage[clm$in_severity], 0.995)           # ~142k; also test p99 / no cap
clm <- clm |> mutate(own_damage_capped = pmin(own_damage, cap))

# ---- Policy-level frequency base -------------------------------------------------
freq_base <- pol |>
  left_join(clm |> filter(is_od_claim) |>
              summarise(n_claims = n(), od_total = sum(own_damage), .by = Policy_ID),
            by = "Policy_ID") |>
  mutate(n_claims = coalesce(n_claims, 0L), od_total = coalesce(od_total, 0))

# ---- 8. Export + reconciliation ---------------------------------------------------
# write_rds(pol, ...); write_rds(clm, ...); write_rds(freq_base, ...); write_csv(log, ...)
```

**Verified:** this code was run end-to-end on the raw files (R 4.4.3). It produced:
- 38,387 clean policies and 36,406 exposure-years
- 6,497 in-period claims, of which 6,119 are own-damage claims (OD > 0) and 6,107 enter severity
- 532 CAT-event claims
- no NA in any `dq_*` column

Crude own-damage frequency on the result: ICE 0.165, Hybrid 0.174, BEV 0.174, a **BEV/ICE ratio of 1.054**.

**Checks to add at the end of the script:**
- `stopifnot()` that Policy_ID and Claim_ID are unique.
- Every modelled claim has `in_period`.
- `all(exposure > 0 & exposure <= 1.01)`.
- No `dq_*` column contains NA.
- The exposure total before and after the join is identical.

---

## 4. Notebook findings to centralise

**Ad-hoc workarounds that move into the ETL:**
- Both notebooks re-implement `distinct()`.
- 01 keeps the longest-exposure record with `slice_max(exposure, by = Policy_ID)`. Replace this with the union-period collapse.
- Dual-format date parsing.
- Exposure filter at 1.01.
- `parse_number()` on Premium and on the amounts.
- Gender, District, Fuel and Claim_Type recodes.
- `Vehicle_Value < 1000 → × 1000`.
- Placeholders set to NA.
- In 02, the hard-coded `cat_date <- as_date("2025-01-19")`.
- In 02, `valid_amount = own_damage > 0 & damage_ratio <= 2`.

Notebook 02 also copies notebook 01's policy-side fixes. Once the ETL exists, both notebooks should read from `data/processed/`.

**Bugs and contradictions in the notebooks:**

| Finding | Notebook | Problem | Fix |
|---|---|---|---|
| "Drop the 72 orphan claims" | 02 | 40 of the 72 are lowercase or padded keys; only 32 are true orphans | Normalise keys before the join |
| Exposure rule stated as "(0, 1]" | 01 (markdown and action item) | The code uses ≤ 1.01. Applying a strict (0, 1] rule would wrongly drop 5,649 rows, almost all leap-year policies. | Write the rule down as ≤ 1.01 |
| Gender missing = 138 | 01 cell 8 | Counts blanks only. The true unknown count is 424 (+ `N/A` 152, + `U` 134). | Use `blank()` before counting |
| `License_Tenure > Driver_Age − 16 → NA` | 01 cell 14 | Runs after Driver_Age is set to NA, so 610 valid tenures are wiped | Apply the rule only where age is known |
| Start > End and 1900 rows set to NA exposure | 01 | Swapped dates are recoverable. The 84 NA-exposure rows still appear in the portfolio counts and shares (cell 16). | Repair or exclude them in the ETL |
| BEV + PHEV (75) and BEVs aged 15–25 (82) | 01 | Both are counted as BEV in every BEV statistic | Apply `dq_bev_phev` and `dq_bev_age` |
| `Unspecified` level | 02 | Mixes 120 blanks (43 of which carry TP) with 86 `Accident` rows | Use the mapping in §3 |
| Total-loss rates | 02 | Computed on the raw flag, which includes the 13 total losses with OD ≤ 0 and 34–38 low-ratio flags | Use `tl_clean` |
| Out-of-period counts: 12 before / 82 after | 02 | This audit finds 13 before (all fixed by the date swap) and 70 after. The difference comes from the notebook's dedup rule and its NA exposure on swapped rows; it was not reconciled row by row. | Recount after the ETL |
| Claim-label variant count of 362 | 02 | Treats `Flood` as canonical although the code maps it to Natural hazard | Count it as a variant |

---

## 5. Open decisions for the team

1. **1900 start dates:** exclude them (recommended) or impute `start = End − 364` as a sensitivity run.
2. **Hybrid:** keep it as a separate level (recommended) or exclude it from the main BEV vs. ICE contrast.
3. **Severity cap:** P99.5 (recommended), with P99 and no cap as sensitivity runs.
4. **Old BEVs (82):** set Vehicle_Age to NA (recommended) or exclude the rows entirely.
5. **Claims after End_Date (70):** exclude them (recommended). Recovering them would need the renewal policy records from the data provider.

---

## 6. Implementation status (2026-10-12)

The table-level rules are implemented in `src/01_clean_datasets.R`. It writes `data/processed/policies_cleaned.{rds,csv}` (38,309 rows), `claims_cleaned.{rds,csv}` (6,569 rows) and `cleaning_log.csv`. The join-level rules are still pending in `src/01_etl_merge_and_clean.R`.

**Decisions taken** (these resolve §5):

| # | Decision | Implemented as |
|---|---|---|
| 1 | 1900 start dates | **Excluded** (25 policies) |
| 2 | Hybrid | **Separate level.** BEV + PHEV rows (75) are moved to Hybrid. Factor levels: ICE (base), Hybrid, BEV. |
| 4 | Old BEVs | **Excluded, not set to NA.** The audit recommended NA, but the team chose strict filtering: BEVs with model year < 2012 are dropped (78), and so are rows with a missing or out-of-range (0–30) Vehicle_Age (0 in this extract). No flag columns are exported. |
| — | P2663026 | Its reversed-date second record is **dropped** (1 row) before the date swap, so the record is not stretched to a false union period. |
| — | Negative own damage | **Dropped** (35 after de-duplication). |
| — | CAT flag | `is_cat_event` = 2025-01-19 **and** Natural_Hazard (532 claims). Every claim on that date would be 558. |
| 3, 5 | Severity cap; claims after End_Date | Not yet implemented. Belongs to the merge / modelling stage. |

**Still pending in the merge script** (they need the join):
- orphan claims: 51 = 32 true + 5 on 1900-start policies + 14 on dropped old-BEV policies;
- the in-period filter (about 70 claims after End_Date);
- the own-damage > 2× vehicle-value severity screen (12);
- the total-loss ratio rule (`tl_clean` with ratio ≥ 0.5);
- the large-loss cap.
