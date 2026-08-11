suppressPackageStartupMessages({
  library(haven)
  library(dplyr)
  library(purrr)
})

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
if (length(script_arg) != 1) stop("Run this file with Rscript.")
script_file <- normalizePath(sub("^--file=", "", script_arg), winslash = "/")
skill_dir <- dirname(dirname(dirname(dirname(script_file))))
source(file.path(skill_dir, "R", "study_paths.R"))
paths <- study_paths(script_file)
script_dir <- paths$script_dir
adam_dir <- paths$adam_dir
model_output_dir <- paths$model_output_dir
table_output_dir <- paths$table_output_dir
dir.create(table_output_dir, recursive = TRUE, showWarnings = FALSE)

source(file.path(skill_dir, "R", "io.R"))
source(file.path(skill_dir, "R", "shell_table.R"))
source(file.path(script_dir, "00_fcn_tfl_specs.R"))

adqssum <- read_sas(file.path(adam_dir, "adqssum.sas7bdat"))
admk <- read_sas(file.path(adam_dir, "admk.sas7bdat"))
model_results <- read_utf8_bom_csv(file.path(model_output_dir, "tfl_param_model_results.csv"))
lsmeans <- read_utf8_bom_csv(file.path(model_output_dir, "tfl_param_lsmeans.csv"))
tfl_specs <- build_fcn_tfl_specs(adqssum, admk)

build_observed_rows <- function(tfl) {
  base_rows <- tfl$data %>%
    filter(PARAMCD %in% tfl$paramcd, ABLFL == "是", !is.na(AVAL)) %>%
    group_by(PARAMCD, PARAM, AVISIT, AVISITN) %>%
    summarise(summarise_value(AVAL), .groups = "drop") %>%
    mutate(
      row_type = "Observed AVAL",
      chg_n = NA_integer_,
      chg_mean = NA_real_,
      chg_sd = NA_real_,
      chg_median = NA_real_,
      chg_min = NA_real_,
      chg_max = NA_real_
    )

  post_rows <- tfl$data %>%
    filter(
      PARAMCD %in% tfl$paramcd,
      ANL01FL == "是",
      ABLFL != "是",
      !is.na(AVISIT)
    ) %>%
    group_by(PARAMCD, PARAM, AVISIT, AVISITN) %>%
    summarise(
      aval = list(summarise_value(AVAL)),
      chg = list(summarise_value(CHG)),
      .groups = "drop"
    ) %>%
    mutate(
      n = map_int(aval, "n"),
      mean = map_dbl(aval, "mean"),
      sd = map_dbl(aval, "sd"),
      median = map_dbl(aval, "median"),
      min = map_dbl(aval, "min"),
      max = map_dbl(aval, "max"),
      chg_n = map_int(chg, "n"),
      chg_mean = map_dbl(chg, "mean"),
      chg_sd = map_dbl(chg, "sd"),
      chg_median = map_dbl(chg, "median"),
      chg_min = map_dbl(chg, "min"),
      chg_max = map_dbl(chg, "max"),
      row_type = "Observed AVAL and CHG"
    ) %>%
    select(-aval, -chg)

  bind_rows(base_rows, post_rows)
}

make_tfl_table <- function(tfl) {
  observed <- build_observed_rows(tfl)
  param_order <- tibble(PARAMCD = tfl$paramcd, param_order = seq_along(tfl$paramcd))

  model_slice <- model_results %>%
    filter(tfl_id == tfl$tfl_id) %>%
    select(paramcd, model_status = status, covariance, model_message = message)

  lsm_slice <- lsmeans %>%
    filter(tfl_id == tfl$tfl_id) %>%
    mutate(
      adjusted_mean_95ci = ifelse(
        is.na(lower.CL) | is.na(upper.CL),
        fmt_num(emmean),
        paste0(fmt_num(emmean), " (", fmt_num(lower.CL), ", ", fmt_num(upper.CL), ")")
      ),
      p_value_formatted = ifelse(
        is.na(p.value),
        "",
        fmt_p(p.value)
      )
    ) %>%
    select(
      paramcd, AVISIT,
      mmrm_adjusted_mean = emmean,
      mmrm_se = SE,
      mmrm_df = df,
      mmrm_lower_cl = lower.CL,
      mmrm_upper_cl = upper.CL,
      mmrm_adjusted_mean_95ci = adjusted_mean_95ci,
      mmrm_p_value = p.value,
      mmrm_p_value_formatted = p_value_formatted
    )

  observed %>%
    left_join(param_order, by = "PARAMCD") %>%
    left_join(model_slice, by = c("PARAMCD" = "paramcd")) %>%
    left_join(lsm_slice, by = c("PARAMCD" = "paramcd", "AVISIT")) %>%
    mutate(
      tfl_id = tfl$tfl_id,
      tfl_title = tfl$title,
      dataset = tfl$dataset,
      observed_mean_sd = fmt_mean_sd(mean, sd, n),
      observed_median = fmt_num(median),
      observed_min_max = fmt_min_max(min, max, n),
      chg_mean_sd = fmt_mean_sd(chg_mean, chg_sd, chg_n),
      chg_median_fmt = fmt_num(chg_median),
      chg_min_max = fmt_min_max(chg_min, chg_max, chg_n)
    ) %>%
    arrange(param_order, AVISITN) %>%
    select(
      tfl_id, tfl_title, dataset,
      PARAMCD, PARAM, AVISIT, AVISITN, row_type,
      n, observed_mean_sd, observed_median, observed_min_max,
      chg_n, chg_mean_sd, chg_median_fmt, chg_min_max,
      model_status, covariance,
      mmrm_adjusted_mean_95ci, mmrm_p_value_formatted,
      model_message
    )
}

manifest <- map_dfr(tfl_specs, function(tfl) {
  table <- make_tfl_table(tfl)
  file_stub <- paste0("table_", gsub("[^0-9]+", "_", tfl$tfl_id), "_mmrm.csv")
  out_path <- file.path(table_output_dir, file_stub)
  write_utf8_bom_csv(table, out_path)
  tibble(
    tfl_id = tfl$tfl_id,
    tfl_title = tfl$title,
    dataset = tfl$dataset,
    output_file = file.path("model-run", "output", "tables", file_stub),
    n_rows = nrow(table),
    n_params = n_distinct(table$PARAMCD),
    n_fit_params = n_distinct(table$PARAMCD[table$model_status == "fit"]),
    n_failed_or_not_run_params = n_distinct(table$PARAMCD[table$model_status != "fit"])
  )
})

write_utf8_bom_csv(manifest, file.path(table_output_dir, "table_output_manifest.csv"))

message("Shell-style table CSVs created. Output directory: ", table_output_dir)
