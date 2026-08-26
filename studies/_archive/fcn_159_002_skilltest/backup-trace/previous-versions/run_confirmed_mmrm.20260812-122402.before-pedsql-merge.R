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

fit_one_param <- function(data, spec, paramcd) {
  param_data <- data |> dplyr::filter(PARAMCD == paramcd)
  parameter_label <- unique(param_data$display_parameter)
  parameter_label <- if (length(parameter_label) == 0) NA_character_ else parameter_label[1]

  if (nrow(param_data) == 0) {
    return(list(
      status = "blocked_data",
      table = data.frame(),
      qc = data.frame(tfl_id = spec$tfl_id, PARAMCD = paramcd, parameter = parameter_label, status = "blocked_data", message_cn = "未找到该 PARAMCD 的分析记录。")
    ))
  }
  if (dplyr::n_distinct(param_data$USUBJID) < 2 || dplyr::n_distinct(param_data$AVISITN) < 2) {
    return(list(
      status = "blocked_data",
      table = data.frame(),
      qc = data.frame(
        tfl_id = spec$tfl_id,
        PARAMCD = paramcd,
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
    add_log(spec$tfl_id, " / ", paramcd, "：REGION 不可估计或只有一个水平，本次运行移除 REGION 项并保留日志。")
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
        add_log(spec$tfl_id, " / ", paramcd, "：UN 拟合 warning：", conditionMessage(w))
        invokeRestart("muffleWarning")
      },
      message = function(m) {
        add_log(spec$tfl_id, " / ", paramcd, "：UN 拟合 message：", conditionMessage(m))
        invokeRestart("muffleMessage")
      }
    ),
    error = function(e) {
      add_log(spec$tfl_id, " / ", paramcd, "：UN 拟合失败，尝试 AR(1)。原始错误：", conditionMessage(e))
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
            add_log(spec$tfl_id, " / ", paramcd, "：AR(1) 拟合 warning：", conditionMessage(w))
            invokeRestart("muffleWarning")
          },
          message = function(m) {
            add_log(spec$tfl_id, " / ", paramcd, "：AR(1) 拟合 message：", conditionMessage(m))
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
        PARAMCD = paramcd,
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

  rds_file <- file.path(paths$rds, paste0(gsub("\\.", "_", spec$tfl_id), "_", paramcd, "_mmrm.rds"))
  saveRDS(fit, rds_file)

  lsmean <- tryCatch(
    withCallingHandlers(
      as.data.frame(summary(emmeans::emmeans(fit, ~ AVISITN_F), infer = c(TRUE, TRUE))),
      warning = function(w) {
        add_log(spec$tfl_id, " / ", paramcd, "：LSMean 提取 warning：", conditionMessage(w))
        invokeRestart("muffleWarning")
      },
      message = function(m) {
        add_log(spec$tfl_id, " / ", paramcd, "：LSMean 提取 message：", conditionMessage(m))
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
        PARAMCD = paramcd,
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
      PARAMCD = paramcd,
      parameter = parameter_label,
      covariance_used = covariance_used,
      model_rds = relative_path(rds_file),
      status = status,
      note_cn = "这是 MMRM LSMean 明细输出；最终 shell-ready TFL 仍需按 shell 版式拼表核查。",
      .before = 1
    )

  list(
    status = status,
    table = lsmean,
    qc = data.frame(
      tfl_id = spec$tfl_id,
      PARAMCD = paramcd,
      parameter = parameter_label,
      status = status,
      covariance_used = covariance_used,
      n_subjects = dplyr::n_distinct(param_data$USUBJID),
      n_records = nrow(param_data),
      n_visits = dplyr::n_distinct(param_data$AVISITN),
      model_rds = relative_path(rds_file),
      message_cn = "模型拟合完成并输出 LSMean 明细；因尚未拼成 shell-ready 表，TFL 状态保守标记为 partial。",
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

  table_rows <- list()
  qc_rows <- list(data_qc)
  model_status <- character()
  for (paramcd in paramcd_to_run) {
    result <- fit_one_param(prepared, spec, paramcd)
    model_status <- c(model_status, result$status)
    if (nrow(result$table) > 0) table_rows[[length(table_rows) + 1]] <- result$table
    qc_rows[[length(qc_rows) + 1]] <- result$qc
  }

  tfl_table <- if (length(table_rows) > 0) dplyr::bind_rows(table_rows) else data.frame()
  param_qc <- dplyr::bind_rows(qc_rows)
  tfl_status <- collapse_tfl_status(model_status)
  output_file <- file.path(paths$tables, paste0(gsub("\\.", "_", spec$tfl_id), "_mmrm_lsmean.csv"))
  write_utf8_bom_csv(tfl_table, output_file)

  all_model_summary[[length(all_model_summary) + 1]] <- data.frame(
    tfl_id = spec$tfl_id,
    title = spec$title,
    dataset = dataset_name,
    expanded_paramcd = paste(paramcd_to_run, collapse = "; "),
    model_formula = "CHG ~ AVISITN + REGION + BASE + BASE*AVISITN + covariance(AVISITN | USUBJID)",
    covariance_strategy = spec$covariance,
    output_status = tfl_status,
    output_file = relative_path(output_file),
    message_cn = "本表按确认 mapping 批量运行；REGION 不可估计时在日志中记录并临时移除。当前输出为 LSMean 明细，不直接等同 shell-ready TFL。",
    stringsAsFactors = FALSE
  )
  all_parameter_status[[length(all_parameter_status) + 1]] <- param_qc
  if (nrow(tfl_table) > 0) all_lsmean[[length(all_lsmean) + 1]] <- tfl_table

  manifest <- dplyr::bind_rows(manifest, data.frame(
    tfl_id = spec$tfl_id,
    tfl_type = "table",
    title = spec$title,
    scope_status = "approved",
    output_status = tfl_status,
    output_file = relative_path(output_file),
    log_file = relative_path(file.path(paths$logs, "run_confirmed_mmrm.log")),
    qc_file = relative_path(file.path(paths$qc, "mmrm模型与QC汇总.xlsx")),
    note = "已运行 mmrm 并生成 LSMean 明细；尚未按 shell 版式完成最终 TFL 拼表，因此不标记 complete。",
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
