# Actuarial Analysis & Pricing: BEV vs. ICE Motor Property Insurance

## Executive Overview

This seminar project investigates whether battery electric vehicles (BEVs) carry a
different motor property-damage risk profile than internal combustion engine (ICE)
vehicles, and what that means for pricing. Using policy-level exposure data and
claim-level loss data, the research aims to:

1. **Quantify claim frequency** (claims per policy-year) for BEV vs. ICE.
2. **Quantify claim severity** (own damage and third-party property damage) and
   **total-loss propensity**.
3. **Test statistically** whether observed differences are significant, after
   controlling for confounders such as vehicle age, vehicle value and driver profile.
4. **Estimate a pricing relativity** for Powertrain within an actuarial two-part
   frequency-severity GLM framework, and derive underwriting / tariff recommendations.

## Repository Structure

```
actuarial-seminar-ev-pricing/
├── data/
│   ├── raw/                          # Original source extracts (read-only)
│   │   ├── policies_raw.csv
│   │   └── claims_raw.csv
│   └── processed/                    # Cleaned & joined datasets produced by ETL
├── src/
│   └── 01_etl_merge_and_clean.R      # Load, join, clean, engineer features, export
├── notebooks/
│   ├── 01_eda_policies.ipynb         # Portfolio / exposure EDA
│   ├── 02_eda_claims.ipynb           # Frequency, severity, total-loss EDA
│   ├── 03_statistical_tests.ipynb    # BEV vs. ICE hypothesis testing
│   └── 04_pricing_glm_models.ipynb   # Frequency-severity GLMs & pricing
├── docs/                             # Proposal, status reports, guidelines, notes
├── r_requirements.txt                # R package list
├── setup_environment.R               # One-command R dependency installer
├── .gitignore
└── README.md
```

## Workflow

The analysis follows a linear pipeline; each stage consumes the outputs of the previous one.

```
Raw data ──► ETL ──► EDA ──► Statistical Testing ──► Actuarial GLM Pricing
```

| Step | File | What it does |
|------|------|--------------|
| 1. Raw data | `data/raw/` | Untouched policy and claim extracts. |
| 2. ETL | `src/01_etl_merge_and_clean.R` | Joins on `Policy_ID`, removes duplicates, handles missing values, parses dates and computes exposure, harmonises labels, isolates property claims, engineers rating factors, writes to `data/processed/`. |
| 3. EDA | `notebooks/01_eda_policies.ipynb`, `notebooks/02_eda_claims.ipynb` | Describes the portfolio and loss experience; identifies confounders and data issues. |
| 4. Statistical testing | `notebooks/03_statistical_tests.ipynb` | t-tests / Wilcoxon for severity, chi-square for frequency and total loss, stratified subgroup analysis. |
| 5. GLM pricing | `notebooks/04_pricing_glm_models.ipynb` | Poisson / Negative Binomial frequency model with exposure offset, Gamma / Inverse-Gaussian severity model, pure premium and BEV relativity, tariff implications. |

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
4. Run `src/01_etl_merge_and_clean.R` to generate `data/processed/`.
5. Run the notebooks in `notebooks/` in numerical order.
