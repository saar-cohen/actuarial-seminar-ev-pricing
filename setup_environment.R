# =============================================================================
# setup_environment.R
# -----------------------------------------------------------------------------
# Installs every R package the seminar pipeline needs, in one command:
#
#   Rscript setup_environment.R        (run from the repository root)
#
# The package list lives in r_requirements.txt. Only missing packages are
# installed (from CRAN); the script then checks that every package loads and
# exits with an error if any do not.
# =============================================================================

options(repos = c(CRAN = "https://cloud.r-project.org"))

# ---- Read package list ----
req_file <- "r_requirements.txt"
if (!file.exists(req_file)) {
  stop("r_requirements.txt not found - run from the repository root.")
}
lines    <- trimws(readLines(req_file, warn = FALSE))
packages <- lines[lines != "" & !startsWith(lines, "#")]

# ---- Install missing packages ----
missing <- setdiff(packages, rownames(installed.packages()))

if (length(missing) > 0) {
  message("Installing ", length(missing), " missing package(s): ",
          paste(missing, collapse = ", "))
  install.packages(missing)
} else {
  message("All required packages are already installed.")
}

# ---- Verify every package loads ----
loads  <- vapply(packages, function(p) {
  suppressPackageStartupMessages(requireNamespace(p, quietly = TRUE))
}, logical(1))

for (p in packages) {
  message(sprintf("  [%s] %-12s %s", if (loads[[p]]) "OK" else "FAIL", p,
                  if (loads[[p]]) as.character(packageVersion(p)) else ""))
}

if (!all(loads)) {
  stop("Failed to load: ", paste(packages[!loads], collapse = ", "))
}
message("Environment ready: ", length(packages), " packages verified.")
