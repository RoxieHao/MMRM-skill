# Study MMRM template.
# Copy this file into a study `model-run/` directory, then fill the study-specific
# mapping section from confirmed SAP/shell/ADaM rules.

options(encoding = "UTF-8")

suppressPackageStartupMessages({
  library(haven)
  library(dplyr)
  library(mmrm)
  library(emmeans)
})

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
if (length(script_arg) != 1) stop("Run this file with Rscript.")
script_file <- normalizePath(sub("^--file=", "", script_arg), winslash = "/")
skill_dir <- dirname(dirname(dirname(dirname(script_file))))

source(file.path(skill_dir, "R", "study_paths.R"))
source(file.path(skill_dir, "R", "io.R"))
source(file.path(skill_dir, "R", "model.R"))
source(file.path(skill_dir, "R", "shell_table.R"))

paths <- study_paths(script_file)
dir.create(paths$model_output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(paths$table_output_dir, recursive = TRUE, showWarnings = FALSE)

# ---- Study-specific mapping -------------------------------------------------

study_id <- "STUDY_ID"
tfl_id <- "TFL_ID"
tfl_title <- "TFL_TITLE"
source_dataset_file <- "adam_dataset.sas7bdat"
parameter_filter <- function(data) data
analysis_filter <- function(data) data
visit_levels <- character()
response_var <- "CHG"
baseline_var <- "BASE"
subject_var <- "USUBJID"
visit_var <- "AVISIT"
covariance_formula <- CHG ~ BASE * AVISIT + us(AVISIT | USUBJID)
emmeans_spec <- ~ AVISIT

stop("Fill the study-specific mapping section before running this template.")

# ---- Data preparation -------------------------------------------------------

analysis_source <- read_sas(file.path(paths$adam_dir, source_dataset_file))
analysis_data <- analysis_source %>%
  parameter_filter() %>%
  analysis_filter() %>%
  filter(
    !is.na(.data[[response_var]]),
    !is.na(.data[[baseline_var]]),
    !is.na(.data[[subject_var]]),
    !is.na(.data[[visit_var]])
  ) %>%
  mutate(
    "{subject_var}" := factor(.data[[subject_var]]),
    "{visit_var}" := if (length(visit_levels) > 0) {
      factor(.data[[visit_var]], levels = visit_levels)
    } else {
      factor(.data[[visit_var]])
    }
  )

duplicates <- analysis_data %>%
  count(.data[[subject_var]], .data[[visit_var]], name = "n_records") %>%
  filter(n_records > 1)

if (nrow(duplicates) > 0) stop("Duplicate subject-visit records found.")

# ---- Model run --------------------------------------------------------------

fit <- mmrm(
  formula = covariance_formula,
  data = analysis_data,
  reml = TRUE,
  control = mmrm_control_for_covariance("UN")
)

lsmeans <- as.data.frame(summary(emmeans(fit, emmeans_spec), infer = c(TRUE, TRUE)))
status <- if (inference_complete(lsmeans)) "fit" else "fit_incomplete"

lsmeans <- lsmeans %>%
  mutate(
    study_id = study_id,
    tfl_id = tfl_id,
    tfl_title = tfl_title,
    status = status,
    .before = 1
  )

write_utf8_bom_csv(lsmeans, file.path(paths$model_output_dir, "model_lsmeans.csv"))

# ---- Shell-ready output -----------------------------------------------------

# Build the final TFL table here from the shell-required rows/columns. Keep raw
# model output in `model-run/output/`; write shell-ready outputs to
# `model-run/output/tables/`.

