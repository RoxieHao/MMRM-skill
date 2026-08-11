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
script_dir <- paths$script_dir
adam_dir <- paths$adam_dir
output_dir <- paths$model_output_dir
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

source(file.path(skill_dir, "R", "io.R"))
source(file.path(skill_dir, "R", "model.R"))
source(file.path(script_dir, "00_fcn_tfl_specs.R"))

adqssum <- read_sas(file.path(adam_dir, "adqssum.sas7bdat"))
admk <- read_sas(file.path(adam_dir, "admk.sas7bdat"))

tfl_specs <- build_fcn_tfl_specs(adqssum, admk)

prepare_data <- function(data, paramcd) {
  data %>%
    filter(
      PARAMCD == paramcd,
      ANL01FL == "是",
      ABLFL != "是",
      !is.na(CHG),
      !is.na(BASE),
      !is.na(AVISIT),
      !is.na(USUBJID)
    ) %>%
    arrange(USUBJID, AVISITN) %>%
    mutate(
      AVISIT = factor(AVISIT, levels = unique(AVISIT[order(AVISITN)])),
      USUBJID = factor(USUBJID)
    )
}

fit_one <- function(tfl, paramcd) {
  dat <- prepare_data(tfl$data, paramcd)
  param_label <- tfl$data %>%
    filter(PARAMCD == paramcd) %>%
    distinct(PARAM) %>%
    pull(PARAM) %>%
    first()

  duplicate_n <- dat %>%
    count(USUBJID, AVISIT, name = "n") %>%
    filter(n > 1) %>%
    nrow()

  qc <- tibble(
    tfl_id = tfl$tfl_id,
    tfl_title = tfl$title,
    dataset = tfl$dataset,
    paramcd = paramcd,
    param = param_label %||% "",
    n_subjects = n_distinct(dat$USUBJID),
    n_rows = nrow(dat),
    n_visits = n_distinct(dat$AVISIT),
    duplicate_subject_visit = duplicate_n
  )

  if (nrow(dat) == 0 || n_distinct(dat$USUBJID) < 2 ||
      n_distinct(dat$AVISIT) < 2 || duplicate_n > 0) {
    return(list(
      result = mutate(
        qc,
        status = "not_run_qc",
        covariance = NA_character_,
        message = "Insufficient rows, subjects, visits, or duplicate subject-visit records."
      ),
      lsmeans = tibble()
    ))
  }

  formulas <- list(
    UN = CHG ~ BASE * AVISIT + us(AVISIT | USUBJID),
    AR1 = CHG ~ BASE * AVISIT + ar1(AVISIT | USUBJID)
  )

  messages <- character()
  for (cov_name in names(formulas)) {
    fit_control <- mmrm_control_for_covariance(cov_name)

    fit <- tryCatch(
      mmrm(
        formula = formulas[[cov_name]],
        data = dat,
        reml = TRUE,
        control = fit_control
      ),
      error = function(e) {
        messages <<- c(messages, paste0(cov_name, " failed: ", conditionMessage(e)))
        NULL
      }
    )

    if (!is.null(fit)) {
      emm <- tryCatch(
        as.data.frame(summary(emmeans(fit, ~ AVISIT), infer = c(TRUE, TRUE))),
        error = function(e) {
          messages <<- c(messages, paste0(cov_name, " emmeans failed: ", conditionMessage(e)))
          data.frame()
        }
      )
      output_complete <- inference_complete(emm)
      if (!output_complete) {
        messages <- c(
          messages,
          paste0(cov_name, " fit returned incomplete estimate/SE/df/CI/p-value output.")
        )
      }
      if (nrow(emm) > 0) {
        emm <- emm %>%
          mutate(
            tfl_id = tfl$tfl_id,
            tfl_title = tfl$title,
            dataset = tfl$dataset,
            paramcd = paramcd,
            param = param_label,
            covariance = cov_name,
            .before = 1
          )
      }
      return(list(
        result = mutate(
          qc,
          status = if_else(output_complete, "fit", "fit_incomplete"),
          covariance = cov_name,
          message = paste(messages, collapse = " | ")
        ),
        lsmeans = as_tibble(emm)
      ))
    }
  }

  list(
    result = mutate(
      qc,
      status = "fit_failed",
      covariance = NA_character_,
      message = paste(messages, collapse = " | ")
    ),
    lsmeans = tibble()
  )
}

`%||%` <- function(x, y) if (length(x) == 0 || is.na(x)) y else x

runs <- map(tfl_specs, function(tfl) {
  map(tfl$paramcd, function(paramcd) fit_one(tfl, paramcd))
}) %>% flatten()

results <- map_dfr(runs, "result")
lsmeans <- map_dfr(runs, "lsmeans")

tfl_summary <- results %>%
  count(tfl_id, tfl_title, dataset, status, covariance, name = "n_params") %>%
  arrange(tfl_id, status, covariance)

write_utf8_bom_csv(results, file.path(output_dir, "tfl_param_model_results.csv"))
write_utf8_bom_csv(lsmeans, file.path(output_dir, "tfl_param_lsmeans.csv"))
write_utf8_bom_csv(tfl_summary, file.path(output_dir, "tfl_model_summary.csv"))

summary_connection <- file(
  file.path(output_dir, "tfl_model_summary.txt"),
  open = "wt",
  encoding = "UTF-8"
)
sink(summary_connection)
on.exit({
  sink()
  close(summary_connection)
}, add = TRUE)
cat("FCN-159-002 MMRM by-TFL model-run test\n\n")
cat("Model source rule: CHG ~ AVISIT + region + BASE + BASE * AVISIT, repeated AVISIT within USUBJID.\n")
cat("Implementation: region omitted because current corrected data has one LOCATION level only.\n")
cat("Primary covariance: UN. Fallback attempted: AR(1).\n\n")
cat("TFL summary:\n")
print(tfl_summary)
cat("\nParameter-level results:\n")
print(results, n = nrow(results))

message("By-TFL MMRM test completed. Output directory: ", output_dir)
