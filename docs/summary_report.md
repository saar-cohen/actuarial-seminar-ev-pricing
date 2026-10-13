# BEV vs. ICE Motor Property Insurance: Interim Summary

**Status:** data cleaning, join checks and statistical tests done. GLM pricing (notebook 04) is next.
**Details:** `docs/data_quality_audit.md` (cleaning and join rules), `notebooks/03_statistical_tests.ipynb` (all test output).

---

## 1. What we cleaned and why

`src/01_clean_datasets.R` cleans the two raw files separately. Every step is logged in `data/processed/cleaning_log.csv`.

| | Raw rows | Clean rows | Main fixes |
|---|---|---|---|
| Policies | 38,592 | 38,309 | 110 exact duplicates dropped. 1,200 `dd/mm/yyyy` dates parsed. 59 swapped Start/End dates fixed. 69 mid-term re-issues collapsed to one record per policy. |
| Claims | 6,664 | 6,569 | 60 exact duplicates dropped. 336 amounts stored as text (`₪7,815`) parsed. 35 negative own-damage amounts dropped. 14 claim-type labels mapped to 8. |

The fixes that matter most for the BEV/ICE comparison:
- **25 policies start on `1900-01-01`.** Each would count as about 125 years of exposure, which pushes the crude BEV/ICE frequency ratio from 1.06 to 1.15. We dropped them.
- **78 "BEVs" have a model year before 2012**, when mass-market BEVs did not exist yet. We dropped them.
- **75 "BEVs" have PHEV fuel.** A plug-in hybrid has an engine, so we moved them to Hybrid.
- **Placeholders** (driver age 999, vehicle value 0, premium −1/0) are set to NA rather than used as numbers. **129 vehicle values recorded in ₪ thousands** are multiplied by 1,000.
- **A storm on 2025-01-19** caused 532 natural-hazard claims. It is real loss, so we keep it, but we flag it (`is_cat_event`) and leave it out of the main tests. A one-off catastrophe is priced separately.

We did not impute anything. Missing categories get an explicit `Unknown` level.

## 2. How policies and claims are joined

The join is checked by `src/02_verify_join.R`, and the notebooks use the same rules.

1. **Key:** `Policy_ID`, normalised with `toupper(trimws())` on both sides. This recovers 40 claims whose key was lowercase or padded (`'p2032624 '`).
2. **Cardinality:** `inner_join(..., relationship = "many-to-one")`. Each claim belongs to exactly one policy; a policy can have 0, 1 or more claims. The check confirms that no claim is duplicated.
3. **Orphans:** 51 claims have no policy and are dropped by the inner join. Of these, 32 are true orphans, 14 belong to the dropped pre-2012 BEVs and 5 to the dropped 1900-start policies.
4. **Accident dates:** a claim counts only if `Start_Date <= Accident_Date <= End_Date`, inclusive at both ends, like exposure = End − Start + 1.
   - 70 accidents fall 6–119 days after the policy ended (probably renewals missing from the file). They are excluded.
   - None falls before the start: all 13 such raw cases were on policies whose dates had been swapped.
5. **Claim definition:** an own-damage claim has `Own_Damage_Amount > 0`. We use the same definition for frequency and severity.

Reconciliation: 6,569 claims → 6,518 matched → 6,448 in period → **6,107 own-damage claims**. Total exposure (36,331 vehicle-years) is unchanged by the join.

## 3. Test results: BEV vs. ICE

All tests compare BEV with ICE only; Hybrid is left out. The storm is excluded, and 12 own-damage amounts above 2× vehicle value are excluded from severity as entry errors. α = 0.05, two-sided.

Comparing all BEVs with all ICE cars mixes powertrain with car age. ICE cars go up to 20+ years old, while 91% of BEV exposure is at most 5 years old. So we also test inside an **age-matched cohort**: cars aged 0–5 years, where both groups have enough exposure. BEV exposure drops below 200 vehicle-years per age after age 5. This keeps 91% of BEV exposure and 41% of ICE exposure. Within the cohort we also stratify by vehicle value tier (<₪75k, ₪75–150k, ₪150k+).

| | All ages, crude | Age ≤ 5 cohort, crude | Age ≤ 5 cohort, same value tier |
|---|---|---|---|
| **H1 Severity** (BEV/ICE cost ratio) | **1.98** (1.79–2.20), p < 0.001 | **1.62** (1.44–1.83), p < 0.001 | **1.29** (1.13–1.48), p < 0.001 |
| **H2 Frequency** (rate ratio) | 1.05 (0.96–1.14), p = 0.29 | 1.06 (0.96–1.17), p = 0.25 | 1.07, p = 0.21 |
| **H3 Total loss**, excluding theft | 8.6% vs 8.2%, p = 0.79 | 7.7% vs 5.7%, p = 0.11 | **OR 1.80** (1.18–2.74), p = 0.006 |
| **Third-party damage** (BEV/ICE cost ratio) | 0.95 (0.84–1.08), p = 0.42 | 0.93 (0.81–1.08), p = 0.36 | – |

Tests used:
- **Frequency:** exact Poisson rate test.
- **Severity (own damage and third party):** first an F-test for equal variances of log cost, which never rejects (p = 0.37–0.86). We then use the Two-Sample t-test on log cost, giving a ratio of geometric means. With value tiers pooled, we use a log-cost regression with value tier.
- **Total loss:** two-proportion test; with value tiers pooled, a Cochran-Mantel-Haenszel test. The tiers are too small to test one by one.

Theft is left out of total loss, because a stolen car is written off whatever its powertrain.

**What this means**
- **H1 (severity) holds, but most of the gap is vehicle value.** A BEV claim costs about 2× an ICE claim overall. At the same age and similar value the gap is about 1.3×, and a regression on `log(Vehicle_Value)` gives 1.25×. The premium is largest for cheaper BEVs (≈ 1.95× in the low tier) and not significant in the top tier (1.10×).
- **H2 (frequency) holds.** BEVs do not claim more often, overall, at equal age, or within any value tier (rate ratios 0.90–1.13). The confidence intervals rule out a BEV excess much above 15%.
- **H3 (total loss) is not supported in the main tests.**
  - Including theft, BEVs are even written off less often (9.0% vs 10.7%), because ICE cars are stolen more often.
  - Without theft, but holding age and value fixed, BEV odds of a write-off are about 1.8×. That fits the battery-damage argument, and it stays significant after a Holm correction over the 8 main tests (p_holm = 0.03). It rests on few cases, though: the low value tier has only 7 BEV total losses out of 37 claims.
- **Third-party damage shows no difference.** In collisions with another vehicle, the damage a BEV causes to the other car is about the same as for an ICE car (ratio 0.95, p = 0.42). The extra battery weight does not show up in third-party payouts.
- **H4 (confounding) holds.**
  - Vehicle value and age change the severity and total-loss estimates a lot.
  - Driver age changes nothing: driver profiles are almost the same for BEV and ICE.

## 4. Next step

Notebook 04 fits the GLMs with all rating factors at once:
- **Frequency:** Poisson or Negative Binomial with `offset(log(exposure))`.
- **Severity:** Gamma with a log link and `log(Vehicle_Value)`.
- **Total loss:** logistic GLM with theft handled separately.

From the tests we expect:
- a BEV frequency relativity close to 1.0;
- a severity relativity of about 1.25–1.3 on top of value;
- a non-theft total-loss effect that may be above 1 but needs the full model to confirm.
