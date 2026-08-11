options(encoding = "UTF-8")

suppressPackageStartupMessages({
  library(haven)
  library(dplyr)
  library(tidyr)
  library(mmrm)
  library(emmeans)
  library(writexl)
})

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
if (length(script_arg) != 1) stop("Run this file with Rscript.")
reuse_model_output <- "--reuse-model-output" %in% commandArgs(FALSE)
script_file <- normalizePath(sub("^--file=", "", script_arg), winslash = "/")
skill_dir <- dirname(dirname(dirname(dirname(script_file))))
source(file.path(skill_dir, "R", "study_paths.R"))
paths <- study_paths(script_file)
script_dir <- paths$script_dir
base_dir <- paths$study_dir
source_dir <- paths$source_dir
output_dir <- paths$model_output_dir
table_dir <- paths$table_output_dir
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

source(file.path(skill_dir, "R", "io.R"))
source(file.path(skill_dir, "R", "shell_table.R"))

sap_visits <- c(
  "治疗后2周", "治疗后4周", "治疗后6周", "治疗后8周",
  "治疗后10周", "治疗后12周", "治疗后14周", "治疗后16周",
  "治疗后18周", "治疗后20周", "治疗后22周", "治疗后24周",
  "治疗后26周", "治疗后28周", "治疗后30周", "治疗后32周",
  "治疗后第36周"
)

log_file <- file.path(output_dir, "01_run_hgb_mmrm.log")
log_con <- tryCatch(
  file(log_file, open = "wt", encoding = "UTF-8"),
  error = function(e) {
    log_file <<- file.path(output_dir, paste0("01_run_hgb_mmrm_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".log"))
    file(log_file, open = "wt", encoding = "UTF-8")
  }
)
sink(log_con, split = TRUE)
sink(log_con, type = "message")
on.exit({
  sink(type = "message")
  sink()
  close(log_con)
}, add = TRUE)

cat("Run started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("R:", R.version.string, "\n")

adeff <- read_sas(file.path(source_dir, "adeff.sas7bdat"))
adsl <- read_sas(file.path(source_dir, "adsl.sas7bdat"))

model_data <- adeff %>%
  filter(
    PARAMCD == "HGB",
    FASFL == "Y",
    ANL03FL == "Y",
    AVISIT %in% sap_visits,
    !is.na(CHG),
    !is.na(BASE),
    !is.na(AVAL),
    TRT01P %in% c("Triferic组", "安慰剂组"),
    ESAGRA1 != ""
  ) %>%
  mutate(
    USUBJID = factor(USUBJID),
    TRT01P = factor(TRT01P, levels = c("安慰剂组", "Triferic组")),
    AVISIT = factor(AVISIT, levels = sap_visits),
    ESAGRA1 = factor(ESAGRA1)
  )

qc <- list(
  population = model_data %>%
    summarise(
      rows = n(),
      subjects = n_distinct(USUBJID),
      missing_chg = sum(is.na(CHG)),
      missing_base = sum(is.na(BASE)),
      missing_aval = sum(is.na(AVAL))
    ),
  by_visit_arm = model_data %>%
    count(AVISIT, TRT01P, name = "n_records") %>%
    arrange(AVISIT, TRT01P),
  duplicate_subject_visit = model_data %>%
    count(USUBJID, AVISIT, name = "n_records") %>%
    filter(n_records > 1),
  factor_levels = data.frame(
    variable = c("TRT01P", "ESAGRA1", "AVISIT"),
    n_levels = c(nlevels(model_data$TRT01P), nlevels(model_data$ESAGRA1), nlevels(model_data$AVISIT))
  )
)

cat("\nQC population:\n")
print(qc$population)
cat("\nQC factor levels:\n")
print(qc$factor_levels)
cat("\nDuplicate subject-visit rows:", nrow(qc$duplicate_subject_visit), "\n")

if (nrow(qc$duplicate_subject_visit) > 0) {
  stop("Duplicate subject-visit records found in model input.")
}

if (reuse_model_output) {
  cat("\nReusing existing visit-level MMRM outputs.\n")
  lsmeans_visit <- read_utf8_bom_csv(file.path(output_dir, "table_14_2_1_1_7_lsmeans_by_visit.csv"))
  contrasts_visit <- read_utf8_bom_csv(file.path(output_dir, "table_14_2_1_1_7_contrasts_by_visit.csv"))
} else {
  fit_chg <- mmrm(
    CHG ~ TRT01P + BASE + ESAGRA1 + AVISIT + TRT01P:AVISIT + us(AVISIT | USUBJID),
    data = model_data,
    control = mmrm_control(
      method = "Kenward-Roger",
      vcov = "Kenward-Roger-Linear"
    )
  )

  cat("\nModel summary:\n")
  print(summary(fit_chg))

  lsmeans_visit <- as.data.frame(
    summary(
      emmeans(fit_chg, ~ TRT01P | AVISIT),
      infer = c(TRUE, TRUE)
    )
  ) %>%
    mutate(
      tfl_id = "14.2.1.1.7",
      tfl_title = "补充分析6：治疗后36周Hgb较基线变化值-基于MMRM(FAS)",
      dataset = "ADEFF",
      PARAMCD = "HGB",
      PARAM = "血红蛋白（HGB）(g/L)",
      response = "CHG",
      covariance = "UN",
      model = "CHG ~ TRT01P + BASE + ESAGRA1 + AVISIT + TRT01P:AVISIT + us(AVISIT | USUBJID)"
    ) %>%
    select(tfl_id, tfl_title, dataset, PARAMCD, PARAM, response, covariance, model, everything())

  contrasts_visit <- as.data.frame(
    summary(
      contrast(emmeans(fit_chg, ~ TRT01P | AVISIT), method = "revpairwise"),
      infer = c(TRUE, TRUE)
    )
  ) %>%
    mutate(
      tfl_id = "14.2.1.1.7",
      tfl_title = "补充分析6：治疗后36周Hgb较基线变化值-基于MMRM(FAS)",
      dataset = "ADEFF",
      PARAMCD = "HGB",
      PARAM = "血红蛋白（HGB）(g/L)",
      response = "CHG",
      covariance = "UN"
    ) %>%
    select(tfl_id, tfl_title, dataset, PARAMCD, PARAM, response, covariance, everything())
}

week36_model_summary <- bind_rows(
  lsmeans_visit %>% filter(AVISIT == "治疗后第36周") %>% mutate(row_type = "lsmean"),
  contrasts_visit %>% filter(AVISIT == "治疗后第36周") %>% mutate(row_type = "contrast")
)

summarise_mean_se <- function(data, value_var) {
  data %>%
    group_by(TRT01P) %>%
    summarise(
      n = sum(!is.na(.data[[value_var]])),
      mean = mean(.data[[value_var]], na.rm = TRUE),
      se = sd(.data[[value_var]], na.rm = TRUE) / sqrt(n),
      .groups = "drop"
    ) %>%
    mutate(
      mean = ifelse(n == 0, NA_real_, mean),
      se = ifelse(n <= 1, NA_real_, se)
    )
}

shell_value <- function(data, arm, value_col) {
  if ("TRT01P" %in% names(data)) {
    data <- data %>% filter(TRT01P == arm)
  }
  value <- data %>% pull({{ value_col }})
  value <- unique(value[!is.na(value)])
  if (length(value) == 0) return("")
  if (length(value) > 1) stop("Expected one shell value, found ", length(value), ".")
  as.character(value[[1]])
}

tfl_title <- "补充分析6：治疗后36周Hgb较基线变化值-基于MMRM(FAS)"
triferic_arm <- "Triferic组"
placebo_arm <- "安慰剂组"

header_n <- adsl %>%
  filter(FASFL == "Y", TRT01P %in% c(triferic_arm, placebo_arm)) %>%
  distinct(USUBJID, TRT01P) %>%
  count(TRT01P, name = "header_n")

model_n <- model_data %>%
  distinct(USUBJID, TRT01P) %>%
  count(TRT01P, name = "n")

week36_data <- model_data %>% filter(AVISIT == "治疗后第36周")
baseline_subjects <- week36_data %>% distinct(USUBJID, TRT01P)
baseline_data <- adeff %>%
  filter(
    PARAMCD == "HGB",
    FASFL == "Y",
    AVISIT == "基线",
    !is.na(AVAL),
    TRT01P %in% c(triferic_arm, placebo_arm)
  ) %>%
  semi_join(baseline_subjects, by = c("USUBJID", "TRT01P"))

baseline_desc <- summarise_mean_se(baseline_data, "AVAL") %>%
  transmute(TRT01P, value = fmt_mean_se(mean, se))
week36_hgb_desc <- summarise_mean_se(week36_data, "AVAL") %>%
  transmute(TRT01P, value = fmt_mean_se(mean, se))
week36_chg_desc <- summarise_mean_se(week36_data, "CHG") %>%
  transmute(TRT01P, value = fmt_mean_se(mean, se))

lsmean_shell <- week36_model_summary %>%
  filter(row_type == "lsmean") %>%
  transmute(
    TRT01P,
    lsmean = fmt_mean_se(emmean, SE),
    ci = fmt_ci(lower.CL, upper.CL)
  )

contrast_shell <- week36_model_summary %>%
  filter(row_type == "contrast") %>%
  transmute(
    diff = fmt_mean_se(estimate, SE),
    ci = fmt_ci(lower.CL, upper.CL),
    p_value = fmt_p(p.value)
  )

week36_summary <- bind_rows(
  data.frame(
    tfl_id = "14.2.1.1.7",
    tfl_title = tfl_title,
    row_order = 1,
    row_label = "Header N",
    triferic_group = paste0("N=", shell_value(header_n, triferic_arm, header_n)),
    placebo_group = paste0("N=", shell_value(header_n, placebo_arm, header_n)),
    treatment_difference = "",
    p_value = "",
    source = "ADSL.FASFL"
  ),
  data.frame(
    tfl_id = "14.2.1.1.7",
    tfl_title = tfl_title,
    row_order = 2,
    row_label = "n",
    triferic_group = shell_value(model_n, triferic_arm, n),
    placebo_group = shell_value(model_n, placebo_arm, n),
    treatment_difference = "",
    p_value = "",
    source = "ADEFF model population"
  ),
  data.frame(
    tfl_id = "14.2.1.1.7",
    tfl_title = tfl_title,
    row_order = 3,
    row_label = "基线Hgb Mean (SE)",
    triferic_group = shell_value(baseline_desc, triferic_arm, value),
    placebo_group = shell_value(baseline_desc, placebo_arm, value),
    treatment_difference = "",
    p_value = "",
    source = "ADEFF baseline records for week-36 observed subjects"
  ),
  data.frame(
    tfl_id = "14.2.1.1.7",
    tfl_title = tfl_title,
    row_order = 4,
    row_label = "治疗后36周Hgb Mean (SE)",
    triferic_group = shell_value(week36_hgb_desc, triferic_arm, value),
    placebo_group = shell_value(week36_hgb_desc, placebo_arm, value),
    treatment_difference = "",
    p_value = "",
    source = "ADEFF week-36 observed records"
  ),
  data.frame(
    tfl_id = "14.2.1.1.7",
    tfl_title = tfl_title,
    row_order = 5,
    row_label = "治疗后36周Hgb较基线变化值 Mean (SE)",
    triferic_group = shell_value(week36_chg_desc, triferic_arm, value),
    placebo_group = shell_value(week36_chg_desc, placebo_arm, value),
    treatment_difference = "",
    p_value = "",
    source = "ADEFF week-36 observed records"
  ),
  data.frame(
    tfl_id = "14.2.1.1.7",
    tfl_title = tfl_title,
    row_order = 6,
    row_label = "LSMean (SE)",
    triferic_group = shell_value(lsmean_shell, triferic_arm, lsmean),
    placebo_group = shell_value(lsmean_shell, placebo_arm, lsmean),
    treatment_difference = shell_value(contrast_shell, "", diff),
    p_value = shell_value(contrast_shell, "", p_value),
    source = "MMRM"
  ),
  data.frame(
    tfl_id = "14.2.1.1.7",
    tfl_title = tfl_title,
    row_order = 7,
    row_label = "95% CI",
    triferic_group = shell_value(lsmean_shell, triferic_arm, ci),
    placebo_group = shell_value(lsmean_shell, placebo_arm, ci),
    treatment_difference = shell_value(contrast_shell, "", ci),
    p_value = "",
    source = "MMRM"
  )
)

write_utf8_bom_csv(lsmeans_visit, file.path(output_dir, "table_14_2_1_1_7_lsmeans_by_visit.csv"))
write_utf8_bom_csv(contrasts_visit, file.path(output_dir, "table_14_2_1_1_7_contrasts_by_visit.csv"))
write_utf8_bom_csv(week36_model_summary, file.path(output_dir, "table_14_2_1_1_7_mmrm_model_week36.csv"))
write_utf8_bom_csv(week36_summary, file.path(table_dir, "table_14_2_1_1_7_mmrm.csv"))

manifest <- data.frame(
  tfl_id = c("14.2.1.1.7", "14.2.1.1.8", "14.2.2.1.5", "14.2.2.1.6"),
  title = c(
    "补充分析6：治疗后36周Hgb较基线变化值-基于MMRM(FAS)",
    "补充分析7：治疗后36周Hgb较基线变化值协方差分析结果-基于MMRM(FAS)",
    "治疗后各访视Hgb(g/L)较基线变化值-基于MMRM(FAS)",
    "治疗后各访视Hgb(g/L)较基线变化值-基于MMRM(PPS)"
  ),
  status = c(
    "run",
    "planned: MMRM prediction/imputation then ANCOVA",
    "planned: MMRM imputation then descriptive visit summaries",
    "planned: MMRM imputation then descriptive visit summaries"
  ),
  output_file = c(
    "tables/table_14_2_1_1_7_mmrm.csv",
    "",
    "",
    ""
  )
)
write_utf8_bom_csv(manifest, file.path(table_dir, "table_output_manifest.csv"))

workbook_file <- file.path(table_dir, "triferic_phase3_mmrm_tables.xlsx")
tryCatch(
  write_xlsx(
    list(
      table_14_2_1_1_7 = week36_summary,
      lsmeans_by_visit = lsmeans_visit,
      contrasts_by_visit = contrasts_visit,
      manifest = manifest
    ),
    workbook_file
  ),
  error = function(e) {
    fallback_file <- file.path(
      table_dir,
      paste0("triferic_phase3_mmrm_tables_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".xlsx")
    )
    message("Primary workbook could not be written: ", conditionMessage(e))
    message("Writing fallback workbook: ", fallback_file)
    write_xlsx(
      list(
        table_14_2_1_1_7 = week36_summary,
        lsmeans_by_visit = lsmeans_visit,
        contrasts_by_visit = contrasts_visit,
        manifest = manifest
      ),
      fallback_file
    )
  }
)

cat("\nOutputs written under:", normalizePath(output_dir, winslash = "/"), "\n")
cat("Run completed:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
