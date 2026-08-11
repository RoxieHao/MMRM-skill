suppressPackageStartupMessages({
  library(haven)
  library(dplyr)
  library(purrr)
  library(mmrm)
  library(emmeans)
})

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
if (length(script_arg) != 1) stop("Run this file with Rscript.")
script_file <- normalizePath(sub("^--file=", "", script_arg), winslash = "/")
skill_dir <- dirname(dirname(dirname(dirname(script_file))))
source(file.path(skill_dir, "R", "study_paths.R"))
paths <- study_paths(script_file)
adam_dir <- paths$adam_dir
review_dir <- paths$review_dir
dir.create(review_dir, recursive = TRUE, showWarnings = FALSE)

source(file.path(skill_dir, "R", "io.R"))

adsl <- read_sas(file.path(adam_dir, "adsl.sas7bdat")) %>%
  select(USUBJID, PAINFL, COAFL, COA01FL, COA02FL)
adqssum <- read_sas(file.path(adam_dir, "adqssum.sas7bdat")) %>%
  left_join(adsl, by = "USUBJID", suffix = c("", "_ADSL"))

prepare_data <- function(paramcd, candidate) {
  data <- adqssum %>%
    filter(
      PARAMCD == paramcd,
      ANL01FL == "是",
      ABLFL != "是",
      !is.na(CHG),
      !is.na(BASE),
      !is.na(AVISIT),
      !is.na(USUBJID)
    )

  data <- switch(
    candidate,
    current_anl01 = data,
    coa01fl_yes = filter(data, COA01FL == "是"),
    coa02fl_yes = filter(data, COA02FL == "是"),
    painfl_yes = filter(data, PAINFL == "是"),
    baseline_gt0 = filter(data, BASE > 0),
    stop("Unknown candidate: ", candidate)
  )

  data %>%
    arrange(USUBJID, AVISITN) %>%
    mutate(
      AVISIT = factor(AVISIT, levels = unique(AVISIT[order(AVISITN)])),
      USUBJID = factor(USUBJID)
    )
}

fit_candidate <- function(paramcd, candidate) {
  dat <- prepare_data(paramcd, candidate)
  param_label <- adqssum %>%
    filter(PARAMCD == paramcd) %>%
    distinct(PARAM) %>%
    pull(PARAM) %>%
    first()

  fit <- tryCatch(
    mmrm(
      CHG ~ BASE * AVISIT + us(AVISIT | USUBJID),
      data = dat,
      reml = TRUE,
      control = mmrm_control(
        method = "Kenward-Roger",
        vcov = "Kenward-Roger-Linear"
      )
    ),
    error = function(e) e
  )

  if (inherits(fit, "error")) {
    return(tibble(
      candidate = candidate,
      PARAMCD = paramcd,
      PARAM = param_label,
      n_subjects = n_distinct(dat[["USUBJID"]]),
      n_rows = nrow(dat),
      AVISIT = NA_character_,
      emmean = NA_real_,
      SE = NA_real_,
      df = NA_real_,
      lower.CL = NA_real_,
      upper.CL = NA_real_,
      p.value = NA_real_,
      message = conditionMessage(fit)
    ))
  }

  as_tibble(as.data.frame(summary(emmeans(fit, ~ AVISIT), infer = c(TRUE, TRUE)))) %>%
    mutate(
      candidate = candidate,
      PARAMCD = paramcd,
      PARAM = param_label,
      n_subjects = n_distinct(dat[["USUBJID"]]),
      n_rows = nrow(dat),
      message = "",
      .before = 1
    )
}

results <- expand.grid(
  PARAMCD = c("OVERPW", "OVERTPW", "PTOTW"),
  candidate = c("current_anl01", "coa01fl_yes", "coa02fl_yes", "painfl_yes", "baseline_gt0"),
  stringsAsFactors = FALSE
) %>%
  pmap_dfr(function(PARAMCD, candidate) fit_candidate(PARAMCD, candidate))

write_utf8_bom_csv(
  results,
  file.path(review_dir, "table_14_2_11_2_population_candidates.csv")
)

message("Diagnostic candidates written to: ", review_dir)
