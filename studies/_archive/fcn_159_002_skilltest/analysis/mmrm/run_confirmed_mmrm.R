options(encoding = "UTF-8")

suppressPackageStartupMessages({
  library(haven)
  library(dplyr)
  library(mmrm)
  library(emmeans)
  library(writexl)
})

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
if (length(script_arg) != 1) {
  stop("请使用 Rscript 运行本脚本。")
}

script_file <- normalizePath(sub("^--file=", "", script_arg), winslash = "/", mustWork = TRUE)
study_dir <- normalizePath(file.path(dirname(script_file), "..", ".."), winslash = "/", mustWork = TRUE)
project_dir <- normalizePath(file.path(study_dir, "..", ".."), winslash = "/", mustWork = TRUE)
source(file.path(study_dir, "analysis", "data-processing", "fcn_mmrm_data_processing.R"), encoding = "UTF-8")

paths <- list(
  adam = file.path(study_dir, "input", "adam"),
  review = file.path(study_dir, "statistician-review"),
  tables = file.path(study_dir, "output", "tables"),
  logs = file.path(study_dir, "output", "logs"),
  qc = file.path(study_dir, "output", "qc"),
  rds = file.path(study_dir, "output", "qc", "models"),
  manifest = file.path(study_dir, "output", "tfl-output-manifest.csv")
)

invisible(lapply(paths[c("tables", "logs", "qc", "rds")], dir.create, recursive = TRUE, showWarnings = FALSE))

write_utf8_bom_csv <- function(data, path) {
  con <- file(path, open = "wb")
  on.exit(try(close(con), silent = TRUE), add = TRUE)
  writeBin(as.raw(c(0xEF, 0xBB, 0xBF)), con)
  close(con)
  con <- file(path, open = "at", encoding = "UTF-8")
  on.exit(try(close(con), silent = TRUE), add = TRUE)
  write.csv(data, con, row.names = FALSE, na = "")
}

log_lines <- character()
add_log <- function(...) {
  log_lines <<- c(log_lines, paste0(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " | ", paste0(..., collapse = "")))
}

relative_path <- function(path) {
  normal_path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  prefix <- paste0(project_dir, "/")
  if (startsWith(normal_path, prefix)) {
    substr(normal_path, nchar(prefix) + 1L, nchar(normal_path))
  } else {
    normal_path
  }
}

assert_approval <- function() {
  approval <- readLines(file.path(paths$review, "approval.yaml"), encoding = "UTF-8", warn = FALSE)
  get_value <- function(key) trimws(sub(paste0("^", key, ":"), "", approval[startsWith(approval, paste0(key, ":"))]))
  if (!identical(get_value("tfl_inventory"), "approved") || !identical(get_value("mapping"), "approved")) {
    stop("approval.yaml 未通过两个门禁，不能运行正式 MMRM。")
  }
}

fmt_num <- function(x, digits = 2) {
  ifelse(is.na(x), "", formatC(x, digits = digits, format = "f"))
}

fmt_p <- function(x) {
  dplyr::case_when(
    is.na(x) ~ "",
    x < 0.001 ~ "<0.001",
    TRUE ~ formatC(x, digits = 3, format = "f")
  )
}

mean_sd <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0) return("")
  paste0(fmt_num(mean(x), 2), "（", fmt_num(stats::sd(x), 2), "）")
}

median_text <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0) return("")
  fmt_num(stats::median(x), 2)
}

min_max <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0) return("")
  paste0(fmt_num(min(x), 2), "，", fmt_num(max(x), 2))
}

one_subject_value <- function(data, value_col) {
  data |>
    dplyr::filter(!is.na(.data[[value_col]])) |>
    dplyr::arrange(USUBJID, AVISITN) |>
    dplyr::group_by(USUBJID) |>
    dplyr::summarise(value = dplyr::first(.data[[value_col]]), .groups = "drop")
}

summarise_baseline <- function(data) {
  data |>
    dplyr::group_by(analysis_group_id, analysis_group_label) |>
    dplyr::group_modify(~ {
      values <- one_subject_value(.x, "BASE")$value
      data.frame(
        visit_sort = -1,
        visit_label = "基线[1]",
        n_aval = length(values),
        aval_mean_sd = mean_sd(values),
        aval_median = median_text(values),
        aval_min_max = min_max(values),
        n_chg = NA_integer_,
        chg_mean_sd = "",
        chg_median = "",
        chg_min_max = "",
        stringsAsFactors = FALSE
      )
    }) |>
    dplyr::ungroup()
}

summarise_postbaseline <- function(data) {
  data |>
    dplyr::filter(AVISITN > 0) |>
    dplyr::group_by(analysis_group_id, analysis_group_label, AVISITN, AVISIT_LABEL) |>
    dplyr::summarise(
      visit_sort = unique(AVISITN)[1],
      visit_label = unique(AVISIT_LABEL)[1],
      n_aval = sum(!is.na(AVAL)),
      aval_mean_sd = mean_sd(AVAL),
      aval_median = median_text(AVAL),
      aval_min_max = min_max(AVAL),
      n_chg = sum(!is.na(CHG)),
      chg_mean_sd = mean_sd(CHG),
      chg_median = median_text(CHG),
      chg_min_max = min_max(CHG),
      .groups = "drop"
    ) |>
    dplyr::select(-AVISITN, -AVISIT_LABEL)
}

make_shell_like_rows <- function(prepared, lsmean) {
  desc <- dplyr::bind_rows(
    summarise_baseline(prepared),
    summarise_postbaseline(prepared)
  )

  source_paramcd_lookup <- prepared |>
    dplyr::group_by(analysis_group_id) |>
    dplyr::summarise(source_paramcd_from_data = paste(sort(unique(PARAMCD)), collapse = "; "), .groups = "drop")

  if (nrow(lsmean) == 0) {
    return(desc |>
      dplyr::left_join(source_paramcd_lookup, by = "analysis_group_id") |>
      dplyr::arrange(analysis_group_id, visit_sort) |>
      dplyr::transmute(
        分析参数 = analysis_group_label,
        源PARAMCD = source_paramcd_from_data,
        访视 = visit_label,
        观测值例数 = n_aval,
        观测值均值SD = aval_mean_sd,
        观测值中位数 = aval_median,
        观测值最小值最大值 = aval_min_max,
        变化例数 = n_chg,
        变化均值SD = chg_mean_sd,
        变化中位数 = chg_median,
        变化最小值最大值 = chg_min_max,
        MMRM_LSMean_SE = "",
        MMRM_95CI = "",
        MMRM_df = "",
        MMRM_t值 = "",
        MMRM_p值 = "",
        协方差结构 = "",
        模型状态 = "fit_failed"
      ))
  }

  visit_lookup <- prepared |>
    dplyr::distinct(AVISITN_F, AVISITN) |>
    dplyr::mutate(AVISITN_F = as.character(AVISITN_F))

  lsmean2 <- lsmean |>
    dplyr::mutate(AVISITN_F = as.character(AVISITN_F)) |>
    dplyr::left_join(visit_lookup, by = "AVISITN_F") |>
    dplyr::mutate(
      visit_sort = AVISITN,
      mmrm_lsmean_se = paste0(fmt_num(emmean, 2), "（", fmt_num(SE, 2), "）"),
      mmrm_ci = paste0(fmt_num(lower.CL, 2), "，", fmt_num(upper.CL, 2)),
      mmrm_df = fmt_num(df, 1),
      mmrm_t = fmt_num(t.ratio, 2),
      mmrm_p = fmt_p(p.value)
    ) |>
    dplyr::select(
      analysis_group_id = PARAMCD,
      covariance_used,
      source_paramcd,
      visit_sort,
      mmrm_lsmean_se,
      mmrm_ci,
      mmrm_df,
      mmrm_t,
      mmrm_p,
      model_status = status
    )

  desc |>
    dplyr::left_join(lsmean2, by = c("analysis_group_id", "visit_sort")) |>
    dplyr::left_join(source_paramcd_lookup, by = "analysis_group_id") |>
    dplyr::mutate(
      source_paramcd = dplyr::coalesce(source_paramcd, source_paramcd_from_data),
      covariance_used = dplyr::if_else(is.na(covariance_used), "", covariance_used),
      model_status = dplyr::if_else(
        visit_label == "基线[1]",
        "描述统计",
        dplyr::coalesce(model_status, "未生成MMRM结果")
      ),
      mmrm_lsmean_se = dplyr::coalesce(mmrm_lsmean_se, ""),
      mmrm_ci = dplyr::coalesce(mmrm_ci, ""),
      mmrm_df = dplyr::coalesce(mmrm_df, ""),
      mmrm_t = dplyr::coalesce(mmrm_t, ""),
      mmrm_p = dplyr::coalesce(mmrm_p, "")
    ) |>
    dplyr::arrange(analysis_group_id, visit_sort) |>
    dplyr::transmute(
      分析参数 = analysis_group_label,
      源PARAMCD = source_paramcd,
      访视 = visit_label,
      观测值例数 = n_aval,
      观测值均值SD = aval_mean_sd,
      观测值中位数 = aval_median,
      观测值最小值最大值 = aval_min_max,
      变化例数 = n_chg,
      变化均值SD = chg_mean_sd,
      变化中位数 = chg_median,
      变化最小值最大值 = chg_min_max,
      MMRM_LSMean_SE = mmrm_lsmean_se,
      MMRM_95CI = mmrm_ci,
      MMRM_df = mmrm_df,
      MMRM_t值 = mmrm_t,
      MMRM_p值 = mmrm_p,
      协方差结构 = covariance_used,
      模型状态 = model_status
    )
}

make_mapping <- function() {
  mapping <- data.frame(
    tfl_id = c("14.2.10.1.2", "14.2.11.2", "14.2.12.1.2", "14.2.13.1.2", "14.2.14.1.2"),
    title = c(
      "PedsQL生活质量量表观测值及相对基线变化-MMRM-汇总（COA分析集）",
      "疼痛强度观测值及相对基线变化-MMRM-汇总（COA分析集）",
      "疼痛干扰观测值及相对基线变化-MMRM-汇总（COA分析集）",
      "肌力评估观测值及相对基线变化-MMRM-汇总（COA分析集）",
      "关节活动范围评估观测值及相对基线变化-MMRM-汇总（COA分析集）"
    ),
    dataset = c("adqssum", "adqssum", "adqssum", "admk", "admk"),
    covariance = c("UN; fallback AR(1)", "UN; fallback AR(1)", "UN; fallback AR(1)", "UN; fallback AR(1)", "UN; fallback AR(1)"),
    stringsAsFactors = FALSE
  )

  mapping$paramcd <- I(list(
    c("TS1", "TS2", "TS3", "TS4", "TS5", "TS6", "PF", "EF", "SOF", "SCF"),
    c("OVERPW", "OVERTPW"),
    c("PAINPR", "PAINTE"),
    c("KENDTEN"),
    c("SUMALL", "SUMNECK", "SUMHIP", "SUMSHOU", "SUMELBOW", "SUMWRIST", "SUMKNEE", "SUMANKLE")
  ))
  mapping
}

fit_one_param <- function(data, spec, analysis_group) {
  param_data <- data |> dplyr::filter(analysis_group_id == analysis_group)
  parameter_label <- unique(param_data$analysis_group_label)
  parameter_label <- if (length(parameter_label) == 0) NA_character_ else parameter_label[1]
  analysis_group_key <- unique(param_data$analysis_group_key)
  analysis_group_key <- if (length(analysis_group_key) == 0) gsub("[^A-Za-z0-9_]+", "_", analysis_group) else analysis_group_key[1]
  source_paramcd <- paste(sort(unique(param_data$PARAMCD)), collapse = "; ")

  if (nrow(param_data) == 0) {
    return(list(
      status = "blocked_data",
      table = data.frame(),
      qc = data.frame(tfl_id = spec$tfl_id, PARAMCD = analysis_group, source_paramcd = source_paramcd, parameter = parameter_label, status = "blocked_data", message_cn = "未找到该 analysis group 的分析记录。")
    ))
  }
  if (dplyr::n_distinct(param_data$USUBJID) < 2 || dplyr::n_distinct(param_data$AVISITN) < 2) {
    return(list(
      status = "blocked_data",
      table = data.frame(),
      qc = data.frame(
        tfl_id = spec$tfl_id,
        PARAMCD = analysis_group,
        source_paramcd = source_paramcd,
        parameter = parameter_label,
        status = "blocked_data",
        n_subjects = dplyr::n_distinct(param_data$USUBJID),
        n_records = nrow(param_data),
        n_visits = dplyr::n_distinct(param_data$AVISITN),
        message_cn = "受试者数或访视数不足，跳过模型拟合。",
        stringsAsFactors = FALSE
      )
    ))
  }

  include_region <- "REGION_F" %in% names(param_data) && nlevels(droplevels(param_data$REGION_F)) > 1
  rhs <- if (include_region) {
    "AVISITN_F + REGION_F + BASE + BASE:AVISITN_F"
  } else {
    add_log(spec$tfl_id, " / ", analysis_group, "：REGION 不可估计或只有一个水平，本次运行移除 REGION 项并保留日志。")
    "AVISITN_F + BASE + BASE:AVISITN_F"
  }

  covariance_used <- "UN"
  formula_un <- as.formula(paste("CHG ~", rhs, "+ us(AVISITN_F | USUBJID_F)"))
  formula_ar1 <- as.formula(paste("CHG ~", rhs, "+ ar1(AVISITN_F | USUBJID_F)"))

  fit <- tryCatch(
    withCallingHandlers(
      mmrm::mmrm(
        formula = formula_un,
        data = param_data,
        reml = TRUE,
        control = mmrm::mmrm_control(method = "Kenward-Roger", vcov = "Kenward-Roger-Linear")
      ),
      warning = function(w) {
        add_log(spec$tfl_id, " / ", analysis_group, "：UN 拟合 warning：", conditionMessage(w))
        invokeRestart("muffleWarning")
      },
      message = function(m) {
        add_log(spec$tfl_id, " / ", analysis_group, "：UN 拟合 message：", conditionMessage(m))
        invokeRestart("muffleMessage")
      }
    ),
    error = function(e) {
      add_log(spec$tfl_id, " / ", analysis_group, "：UN 拟合失败，尝试 AR(1)。原始错误：", conditionMessage(e))
      covariance_used <<- "AR(1)"
      tryCatch(
        withCallingHandlers(
          mmrm::mmrm(
            formula = formula_ar1,
            data = param_data,
            reml = TRUE,
            control = mmrm::mmrm_control(method = "Kenward-Roger")
          ),
          warning = function(w) {
            add_log(spec$tfl_id, " / ", analysis_group, "：AR(1) 拟合 warning：", conditionMessage(w))
            invokeRestart("muffleWarning")
          },
          message = function(m) {
            add_log(spec$tfl_id, " / ", analysis_group, "：AR(1) 拟合 message：", conditionMessage(m))
            invokeRestart("muffleMessage")
          }
        ),
        error = function(e2) e2
      )
    }
  )

  if (inherits(fit, "error")) {
    return(list(
      status = "fit_failed",
      table = data.frame(),
      qc = data.frame(
        tfl_id = spec$tfl_id,
        PARAMCD = analysis_group,
        source_paramcd = source_paramcd,
        parameter = parameter_label,
        status = "fit_failed",
        covariance_used = covariance_used,
        n_subjects = dplyr::n_distinct(param_data$USUBJID),
        n_records = nrow(param_data),
        n_visits = dplyr::n_distinct(param_data$AVISITN),
        message_cn = conditionMessage(fit),
        stringsAsFactors = FALSE
      )
    ))
  }

  safe_group <- gsub("[^A-Za-z0-9_]+", "_", analysis_group_key)
  rds_file <- file.path(paths$rds, paste0(gsub("\\.", "_", spec$tfl_id), "_", safe_group, "_mmrm.rds"))
  saveRDS(fit, rds_file)

  lsmean <- tryCatch(
    withCallingHandlers(
      as.data.frame(summary(emmeans::emmeans(fit, ~ AVISITN_F), infer = c(TRUE, TRUE))),
      warning = function(w) {
        add_log(spec$tfl_id, " / ", analysis_group, "：LSMean 提取 warning：", conditionMessage(w))
        invokeRestart("muffleWarning")
      },
      message = function(m) {
        add_log(spec$tfl_id, " / ", analysis_group, "：LSMean 提取 message：", conditionMessage(m))
        invokeRestart("muffleMessage")
      }
    ),
    error = function(e) e
  )
  if (inherits(lsmean, "error")) {
    return(list(
      status = "partial",
      table = data.frame(),
      qc = data.frame(
        tfl_id = spec$tfl_id,
        PARAMCD = analysis_group,
        source_paramcd = source_paramcd,
        parameter = parameter_label,
        status = "partial",
        covariance_used = covariance_used,
        model_rds = relative_path(rds_file),
        message_cn = paste("模型已拟合，但 LSMean/CI/p-value 提取失败：", conditionMessage(lsmean)),
        stringsAsFactors = FALSE
      )
    ))
  }

  required <- c("emmean", "SE", "df", "lower.CL", "upper.CL", "p.value")
  status <- if (all(required %in% names(lsmean)) && all(stats::complete.cases(lsmean[required]))) "partial" else "partial"
  lsmean <- lsmean |>
    dplyr::mutate(
      tfl_id = spec$tfl_id,
      title = spec$title,
      PARAMCD = analysis_group,
      source_paramcd = source_paramcd,
      parameter = parameter_label,
      covariance_used = covariance_used,
      model_rds = relative_path(rds_file),
      status = status,
      note_cn = "这是原始 MMRM LSMean 明细输出；同一次 R 运行会继续生成 shell-like final TFL CSV。",
      .before = 1
    )

  list(
    status = status,
    table = lsmean,
    qc = data.frame(
      tfl_id = spec$tfl_id,
      PARAMCD = analysis_group,
      source_paramcd = source_paramcd,
      parameter = parameter_label,
      status = status,
      covariance_used = covariance_used,
      n_subjects = dplyr::n_distinct(param_data$USUBJID),
      n_records = nrow(param_data),
      n_visits = dplyr::n_distinct(param_data$AVISITN),
      model_rds = relative_path(rds_file),
      message_cn = "模型拟合完成并输出 LSMean 明细；同一次 R 运行会继续生成 shell-like final TFL CSV。",
      stringsAsFactors = FALSE
    )
  )
}

collapse_tfl_status <- function(status) {
  if (length(status) == 0 || all(status == "blocked_data")) return("blocked_data")
  if (any(status == "partial")) return("partial")
  if (all(status == "fit_failed")) return("fit_failed")
  "partial"
}

assert_approval()
add_log("开始运行 FCN-159-002 已确认 MMRM TFL。")

mapping <- make_mapping()
raw_cache <- new.env(parent = emptyenv())
all_model_summary <- list()
all_parameter_status <- list()
all_lsmean <- list()
manifest <- data.frame()

for (i in seq_len(nrow(mapping))) {
  spec <- mapping[i, ]
  dataset_name <- spec$dataset
  if (!exists(dataset_name, envir = raw_cache, inherits = FALSE)) {
    add_log("读取 ADaM 数据集：", dataset_name)
    assign(dataset_name, haven::read_sas(file.path(paths$adam, paste0(dataset_name, ".sas7bdat"))), envir = raw_cache)
  }

  prepared <- prepare_fcn_mmrm_data(get(dataset_name, envir = raw_cache, inherits = FALSE), spec, add_log = add_log)
  data_qc <- describe_prepared_data(prepared, spec)
  paramcd_to_run <- attr(prepared, "expanded_paramcd")
  analysis_groups_to_run <- attr(prepared, "analysis_groups")

  table_rows <- list()
  qc_rows <- list(data_qc)
  model_status <- character()
  for (analysis_group in analysis_groups_to_run) {
    result <- fit_one_param(prepared, spec, analysis_group)
    model_status <- c(model_status, result$status)
    if (nrow(result$table) > 0) table_rows[[length(table_rows) + 1]] <- result$table
    qc_rows[[length(qc_rows) + 1]] <- result$qc
  }

  tfl_table <- if (length(table_rows) > 0) dplyr::bind_rows(table_rows) else data.frame()
  param_qc <- dplyr::bind_rows(qc_rows)
  tfl_status <- collapse_tfl_status(model_status)
  safe_tfl_id <- gsub("\\.", "_", spec$tfl_id)
  raw_output_file <- file.path(paths$tables, paste0(safe_tfl_id, "_mmrm_lsmean.csv"))
  final_tfl_file <- file.path(paths$tables, paste0(safe_tfl_id, "_shell_like.csv"))
  write_utf8_bom_csv(tfl_table, raw_output_file)
  shell_like_table <- make_shell_like_rows(prepared, tfl_table)
  write_utf8_bom_csv(shell_like_table, final_tfl_file)
  final_tfl_status <- if (tfl_status %in% c("fit_failed", "blocked_data")) tfl_status else if (any(shell_like_table$模型状态 == "未生成MMRM结果")) "partial" else "complete"

  all_model_summary[[length(all_model_summary) + 1]] <- data.frame(
    tfl_id = spec$tfl_id,
    title = spec$title,
    dataset = dataset_name,
    expanded_paramcd = paste(paramcd_to_run, collapse = "; "),
    analysis_groups = paste(analysis_groups_to_run, collapse = "; "),
    model_formula = "CHG ~ AVISITN + REGION + BASE + BASE*AVISITN + covariance(AVISITN | USUBJID)",
    covariance_strategy = spec$covariance,
    output_status = final_tfl_status,
    raw_output_file = relative_path(raw_output_file),
    final_tfl_file = relative_path(final_tfl_file),
    message_cn = "本表按确认 mapping 批量运行；同一次 R 运行先生成原始 MMRM LSMean CSV，再生成 shell-like final TFL CSV。",
    stringsAsFactors = FALSE
  )
  all_parameter_status[[length(all_parameter_status) + 1]] <- param_qc
  if (nrow(tfl_table) > 0) all_lsmean[[length(all_lsmean) + 1]] <- tfl_table

  manifest <- dplyr::bind_rows(manifest, data.frame(
    tfl_id = spec$tfl_id,
    tfl_type = "table",
    title = spec$title,
    scope_status = "approved",
    output_status = final_tfl_status,
    raw_output_file = relative_path(raw_output_file),
    final_tfl_file = relative_path(final_tfl_file),
    log_file = relative_path(file.path(paths$logs, "run_confirmed_mmrm.log")),
    qc_file = relative_path(file.path(paths$qc, "mmrm模型与QC汇总.xlsx")),
    note = "同一次正式 R 运行先生成原始 MMRM LSMean CSV，再生成 shell-like final TFL CSV；shell-like final TFL 只保留 CSV。",
    stringsAsFactors = FALSE
  ))
}

model_summary <- dplyr::bind_rows(all_model_summary)
parameter_status <- dplyr::bind_rows(all_parameter_status)
lsmean_contrast <- if (length(all_lsmean) > 0) dplyr::bind_rows(all_lsmean) else data.frame()

writexl::write_xlsx(
  list(
    "TFL模型汇总" = model_summary,
    "参数运行状态" = parameter_status,
    "LSMean与对比" = lsmean_contrast
  ),
  path = file.path(paths$qc, "mmrm模型与QC汇总.xlsx")
)

add_log("运行结束。")
write_utf8_bom_csv(manifest, paths$manifest)
writeLines(log_lines, file.path(paths$logs, "run_confirmed_mmrm.log"), useBytes = TRUE)
