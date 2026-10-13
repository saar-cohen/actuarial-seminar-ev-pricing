# Actuarial Analysis & Pricing: BEV vs. ICE Motor Property Insurance

## Overview

This seminar project asks whether battery electric vehicles (BEVs) have a different
motor property-damage risk than internal combustion engine (ICE) vehicles, and what
that means for pricing. Using policy-level exposure data and claim-level loss data, we:

1. **Measure claim frequency** (claims per vehicle-year) for BEV vs. ICE.
2. **Measure claim severity** (own-damage cost per claim) and the **total-loss rate**.
3. **Test** whether the differences are statistically significant, before and after
   controlling for vehicle value, vehicle age and driver age.
4. **Estimate a BEV pricing relativity** with a frequency-severity GLM and turn it
   into tariff recommendations.

## Repository Structure

```
actuarial-seminar-ev-pricing/
├── data/
│   ├── raw/                          # Original source extracts (read-only)
│   │   ├── policies_raw.csv
│   │   └── claims_raw.csv
│   └── processed/                    # Cleaned files written by src/ (not in git)
├── src/
│   ├── 01_clean_datasets.R           # Cleans policies and claims, writes data/processed/
│   ├── 01_etl_merge_and_clean.R      # Planned: policy-claim join
│   └── 02_verify_join.R              # Checks keys, many-to-one join, orphans, dates
├── notebooks/
│   ├── 01_eda_policies.ipynb         # Portfolio / exposure EDA
│   ├── 02_eda_claims.ipynb           # Frequency, severity, total-loss EDA
│   ├── 03_statistical_tests.ipynb    # BEV vs. ICE hypothesis testing
│   └── 04_pricing_glm_models.ipynb   # Frequency-severity GLMs & pricing
├── docs/
│   ├── data_quality_audit.md         # Every data issue found and how we handle it
│   └── summary_report.md             # Interim summary: cleaning, join, test results
├── r_requirements.txt                # R package list
├── setup_environment.R               # One-command R dependency installer
├── .gitignore
└── README.md
```

## Workflow

Each step uses the output of the one before it.

```
Raw data ──► ETL ──► EDA ──► Statistical Testing ──► Actuarial GLM Pricing
```

| Step | File | What it does |
|------|------|--------------|
| 1. Raw data | `data/raw/` | Untouched policy and claim extracts. |
| 2. Cleaning | `src/01_clean_datasets.R` | Removes duplicates, parses dates and amounts, computes exposure, fixes labels and placeholders, and writes `policies_cleaned` and `claims_cleaned` to `data/processed/`. The rules are in `docs/data_quality_audit.md`. |
| 3. EDA | `notebooks/01_eda_policies.ipynb`, `notebooks/02_eda_claims.ipynb` | Describes the portfolio and the claims, and finds the confounders (vehicle value and age). |
| 4. Statistical testing | `notebooks/03_statistical_tests.ipynb` | Four formal H0/H1 tests, BEV vs. ICE: Poisson rate test (frequency), Two-Sample t-test on log cost, after an F-test finds no evidence of unequal variances (own-damage and third-party severity), two-proportion test (total loss). Each is repeated on all ages, on cars aged ≤ 5, and within value tiers. |
| 5. GLM pricing | `notebooks/04_pricing_glm_models.ipynb` | Poisson frequency GLM with exposure offset, Gamma severity GLM and logistic total-loss GLM, all with ICE as reference. Combines frequency × severity into the BEV pure-premium relativity (≈ 1.26) and the tariff recommendations. |

## Prerequisites / Getting Started

1. **Install R** (4.5 or later) and Python with Jupyter.
2. **Install all R dependencies in one command** (run from the repository root):
   ```bash
   Rscript setup_environment.R
   ```
   This reads `r_requirements.txt`, installs any missing packages from CRAN, and checks that each one loads.
   On Windows, if `Rscript` is not on your PATH, use the full path:
   `& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" setup_environment.R`
3. **Register the R kernel for Jupyter / VS Code** (once per machine):
   ```bash
   Rscript -e "IRkernel::installspec()"
   ```
   Then in VS Code: *Select Kernel → Select Another Kernel... → Jupyter Kernel... → R*.
   Note: if you write `kernel.json` by hand, save it as UTF-8 **without BOM**. VS Code cannot read the file if it starts with a BOM.
4. Run `Rscript src/01_clean_datasets.R` from the repository root to create `data/processed/`, then `Rscript src/02_verify_join.R` to check the join.
5. Run the notebooks in `notebooks/` in numerical order.
