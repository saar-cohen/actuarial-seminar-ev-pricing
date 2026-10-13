# Data Quality Audit

**Files:** `data/raw/policies_raw.csv` (38,592 rows, 12 columns) and `data/raw/claims_raw.csv` (6,664 rows, 7 columns).
**Cleaning script:** `src/01_clean_datasets.R` → `data/processed/policies_cleaned` (38,309 rows), `claims_cleaned` (6,569 rows), `cleaning_log.csv`.
**Updated:** 2026-10-13. Every row count below is the count the script logs (after exact duplicates are removed), unless marked "raw".

Sources cited for rules: **GLM-M** = Goldburd et al., *GLMs for Insurance Rating* (CAS Monograph 5); **W&M** = Werner & Modlin, *Basic Ratemaking*; **NSW18** = Noll, Salzmann & Wüthrich (2018); **O&J** = Ohlsson & Johansson (2010); **IR** = the `insurancerating` R package. **[J]** = our own judgment.

---

## 1. Summary

- The data is usable. Most problems are fixable label variants, date formats, currency text and unit errors. Only 283 policies (0.7%) and 95 claims (1.4%) are removed; 110 and 60 of them are exact duplicates.
- **Invalid policy periods matter most.** 25 policies start on `1900-01-01`. Left in, each counts as ~125 years of exposure and the crude BEV/ICE frequency ratio goes from 1.057 to 1.148. They are dropped.
- **The policy file has no renewals.** 70 Policy_IDs have two records, which are mid-term re-issues of the same contract. They are collapsed to one record each, so exposure is not counted twice.
- **78 BEVs have a model year before 2012**, which is not plausible for a mass-market BEV. They are dropped. 75 "BEV" rows with PHEV fuel are moved to Hybrid.
- **40 claims have a lowercase or padded Policy_ID.** `toupper(trim())` fixes all of them. 32 claims remain true orphans; they and 19 claims on dropped policies are excluded at the join (section 4).
- **The severity tail has entry errors** (12 own-damage amounts above 2× vehicle value) and the total-loss flag is unreliable at low damage ratios. Both need the vehicle value, so they are handled at the join.
- **A storm on 2025-01-19** produced 532 natural-hazard claims. It is real loss, so it is kept and flagged (`is_cat_event`). It barely changes the BEV/ICE ratio.

---

## 2. Policies

| # | Issue | Rule in the script | Rows |
|---|---|---|---|
| P26 | Exact duplicate rows | Drop | −110 |
| X1 | Policy_ID case / spaces | `toupper(str_trim())` (needed on the claims side only) | 0 |
| P21 | Start_Date as `dd/mm/yyyy` (End_Date is always ISO) | Parse with `ymd()`, then `dmy()`. 473 have day ≤ 12, but read as dd/mm they give 364/365-day periods and read as mm/dd they do not, so dd/mm is right. | 1,200 |
| P27 | P2663026: a second record with Start > End | Drop that record before the swap, so it does not stretch the period | −1 |
| P23 | Start > End (dates entered in the wrong order; most differ by exactly 364/365 days) | Swap back | 59 |
| P22 | Start_Date `1900-01-01` placeholder | Drop: exposure unknown | −25 |
| P27 | Same Policy_ID twice, overlapping, same end date (mid-term re-issue). All other columns are identical within each pair. | Collapse to one record over the union period [S: IR `merge_date_ranges`] | −69 |
| P24 | Exposure = (End − Start + 1) / 365.25 | Keep 0 < exposure ≤ 1.01. A strict ≤ 1 would drop the 5,565 leap-year policies of 366 days (1.0021). [S: NSW18 caps at 1] | 0 dropped |
| P1, P2 | District: `TLV`, `Tel-Aviv`, `tel aviv`; blanks | → `Tel Aviv`; blank → `Unknown` (180) [S: GLM-M, explicit Unknown level] | 440 |
| P3, P4 | Gender: `M`, `F`, `␠male`, `female␠`; `N/A`, `U`, blank | → `Male` / `Female`; the rest → `Unknown` (419) | 1,667 |
| P6 | Fuel_Detail: `bev`, `EV`, `Electric`, `Diesal` | → `BEV`, `Diesel` | 570 |
| P5 | Powertrain `Hybrid␠` | Trim | 209 |
| P7 | Powertrain BEV but Fuel_Detail PHEV | → Hybrid (a plug-in hybrid has an engine). Factor levels ICE (base), Hybrid, BEV. [J] | 75 |
| P8, P9 | Driver_Age 999 placeholder (blank is already NA) | → NA. 612 NA in total. [S: GLM-M, placeholder as a number distorts the curve] | 65 |
| P11 | License_Tenure < 0 or Age − Tenure < 17 | → NA, only where age is known. 364 NA in total. Minimum licence age in Israel is 17. | 85 |
| P12 | Vehicle_Age −1 (next model year) | → 0 | 35 |
| — | Vehicle_Age missing or outside 0–30 | Drop | 0 |
| P14 | BEV with model year (start year − Vehicle_Age) < 2012. 82 BEVs had age > 12; 4 of them were BEV+PHEV and became Hybrid first. | Drop [J: no mass-market BEVs before ~2012] | −78 |
| P17 | Vehicle_Value in ₪ thousands (all between 20.2 and 241.6) | × 1000 when 0 < value < 5,000. After the fix the smallest value is 7,000, so the threshold is clean. | 129 |
| P15, P16 | Vehicle_Value 0 placeholder (blank is already NA) | → NA. 363 NA in total. Rows kept. | 44 |
| P18 | Premium as text (`₪12,212`, `4,539`) | Strip `₪`, `,` and spaces | 200 |
| P19 | Premium 0 or −1 | → NA. Premium is never a rating factor (it is the old tariff's output) [S: GLM-M] | 40 |

**Checked and left as is:**
- **P20, Premium < 300 (115 rows):** these are short policies priced pro rata. Premium / exposure is at least 300 for every row.
- **P25, periods shorter than 30 days (112 rows, shortest 20 days):** real short contracts. Exposure already accounts for them.
- **P13, Vehicle_Age 28 (104 rows, all ICE, vs 29 at age 27):** probably a top-code. A `20+` age band absorbs it.

---

## 3. Claims

| # | Issue | Rule in the script | Rows |
|---|---|---|---|
| C15 | Exact duplicate rows. No Claim_ID has conflicting content. | Drop; Claim_ID is then unique | −60 |
| X1 | Policy_ID lowercase `p…`, 22 also with a trailing space | `toupper(str_trim())` | 40 |
| — | Accident_Date | All ISO; the script stops if any fails to parse | 0 |
| C4 | Amounts as text (`₪7,815`, `22,563.05`) and float artefacts (`1018120.0000000001`) | Parse, round to 2 dp | 336 |
| C7 | Own damage < 0. All Collision_No_TP, no parent claim to net against. | Drop | −35 |
| C13 | "No TP" stored as blank or as `0.0` (150 rows) | Blank → 0 | 4,227 |
| C1–C3 | Claim_Type variants (`Self Accident`, `Weather`, `Flood`, `NATURAL_HAZARD␠`…), blanks, vague `Accident` | Map to canonical labels. Blank with TP > 0 → `Collision_With_TP` (41). Other blanks (79) and `Accident` (85) → `Unspecified` (164), kept as its own level. | 511 |
| C17 | Storm on 2025-01-19 (558 claims that day, next-busiest day 27) | Flag `is_cat_event` = that date **and** Natural_Hazard. Kept as real loss; run a sensitivity without it. | 532 |
| C10 | Total-loss flag with own damage = 0 (13 raw; 4 were negatives, already dropped) | `is_total_loss_clean` = flag 1 **and** OD > 0. The raw flag is kept too. Never a predictor. | 9 |

**Checked and left as is:**
- **C5, C6: own damage = 0 (350 rows: 260 TP-only, 90 closed without payment).** These are kept. The own-damage claim definition (OD > 0) is applied at the modelling stage, for frequency and severity alike [S: GLM-M, O&J ch. 2].
- **C9: own damage exactly 250 (12 rows).** Probably a placeholder or deductible artefact. It is too small to matter.
- **C14: Theft with TP > 0 (20 rows).** Odd, but TP does not enter the own-damage study.
- **C16: same policy and date, different Claim_ID (3 pairs).** Different perils and amounts, so these are separate events.

---

## 4. Joining policies and claims

The cleaning script treats the two files separately. The join is checked by `src/02_verify_join.R`, which uses the same rules as notebooks 02–03 and writes `data/processed/join_reconciliation.csv`.

**How the join works**
1. **Key:** `Policy_ID`, normalised with `toupper(str_trim())` in both tables. After cleaning it is unique in policies (38,309) and `Claim_ID` is unique in claims (6,569). 40 claims match only because of this normalisation.
2. **Cardinality:** `inner_join(..., relationship = "many-to-one")`. Each claim matches at most one policy, while a policy can have 0, 1 or more claims (before the date filter: 32,593 policies with 0 claims, 5,035 with 1, 578 with 2, 103 with 3+). The join is checked to produce no duplicates.
3. **Orphans:** claims with no policy are dropped by the inner join.
4. **Accident date window:** a claim counts only if `Start_Date <= Accident_Date <= End_Date`. Both ends are inclusive, which matches exposure = End − Start + 1 (41 accidents fall exactly on a boundary date).
5. **Claim definition:** own-damage claim = `Own_Damage_Amount > 0`, for frequency and severity alike.
6. **Frequency base:** all policies, `left_join` with their claim counts, missing counts set to 0. Total exposure is unchanged by the join (36,331 vehicle-years).

**What the join removes**

| # | Issue | Rule | Claims |
|---|---|---|---|
| X2 | No policy: 32 true orphans (OD ₪287,617) + 14 on dropped old BEVs (₪524,362) + 5 on 1900-start policies (₪37,977) | Exclude; no covariates. The orphan rate is 0.8%. | −51 |
| X4 | Accident before Start_Date | All 13 raw cases were on swapped-date policies and now fall inside | 0 |
| X5 | Accident after End_Date by 6–119 days (median 57.5); probably renewals missing from the file | Exclude: their exposure is not in the file [S: IR `active_rows_by_date`] | −70 |
| — | Own damage = 0 (TP-only or no payment) | Not an own-damage claim | −341 |

Reconciliation: 6,569 claims → 6,518 matched → 6,448 in period → **6,107 own-damage claims** (ICE 4,051, Hybrid 1,361, BEV 695), of which 521 are storm claims.

**Still to apply in the modelling stage** (`src/01_etl_merge_and_clean.R` is a template; notebooks 02–03 apply the first rule inline)

| # | Issue | Rule | Rows |
|---|---|---|---|
| C8 | Own damage > 2× vehicle value and not a total loss (10 of 12 are whole numbers of ₪310k–1.56M) | Keep in frequency, exclude from severity | 12 |
| C11, C12 | Total loss with OD < 50% of value (38); not total loss with OD ≥ 70% of value (15) | `tl_clean` also needs ratio ≥ 0.5; flag the second group | 38 / 15 |
| — | Large losses | Cap OD at P99.5 of the clean severity sample (≈ ₪142k), spread the excess as a loading; test P99 and no cap [S: W&M ch. 6] | — |
| X7 | Late-2025 reporting lag (~27 claims, ~0.4%) | No action, not material | — |

---

## 5. Decisions taken

| Question | Decision |
|---|---|
| 1900 start dates | Dropped (25). Imputing `End − 364` would only be a sensitivity run. |
| Hybrid | Separate level, not merged into ICE or BEV. ICE is the base level (largest exposure). |
| Old BEVs (model year < 2012) | Dropped (78). The first draft suggested setting Vehicle_Age to NA; the team chose to drop them because both age and powertrain are suspect. |
| Missing categoricals | Explicit `Unknown` level, no imputation. |
| Numeric placeholders (age 999, value 0, premium ≤ 0) | Set to NA, rows kept. |
| Negative own damage | Dropped (35). |
| CAT event | Kept and flagged; sensitivity without it. |
| No flag columns | Apart from `is_cat_event` and `is_total_loss_clean`, no `dq_*` columns are exported. The cleaning log records what each step changed. |
| Orphans, claims after End_Date | Excluded at the join (section 4). |
| Severity cap, total-loss ratio rule | Modelling stage (section 4). |

---

## 6. Effect on the BEV/ICE frequency ratio

Crude claim frequency = claims / exposure-years, computed on the raw files during the audit.

| Scenario | Freq BEV | Freq ICE | BEV/ICE |
|---|---|---|---|
| A. Naive raw join, all rows (including 1900 and swapped periods) | .1870 | .1628 | **1.148** |
| A2. Naive raw join, valid periods only | .1867 | .1784 | 1.047 |
| B. Fully cleaned (keys normalised, duplicates removed, orphans and out-of-period claims dropped) | .1856 | .1757 | **1.057** |
| B2. B, with swapped dates repaired | .1859 | .1757 | 1.058 |
| B3. B, without the CAT day | .1701 | .1606 | 1.059 |

- The 25 policies with a 1900 start alone push the apparent BEV disadvantage from ~6% to ~15%.
- Every other fix moves the ratio by about one point.
- The CAT event changes the level of frequency, not the BEV/ICE ratio.
