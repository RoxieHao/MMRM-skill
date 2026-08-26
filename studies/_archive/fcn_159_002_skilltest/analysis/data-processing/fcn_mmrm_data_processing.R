options(encoding = "UTF-8")

fcn_yes_values <- c("Y", "YES", "Yes", "yes", "是", "1", "TRUE", "True", "true")

is_yes_value <- function(x) {
  trimws(as.character(x)) %in% fcn_yes_values
}

required_columns <- function(data, columns, context) {
  missing <- setdiff(columns, names(data))
  if (length(missing) > 0) {
    stop(context, " 缺少必要变量：", paste(missing, collapse = ", "))
  }
}

expand_paramcd_spec <- function(data, requested) {
  available <- unique(data$PARAMCD)
  expanded <- character()
  for (item in requested) {
    if (item %in% available) {
      expanded <- c(expanded, item)
    } else if (item %in% c("PF", "EF", "SOF", "SCF")) {
      expanded <- c(expanded, grep(paste0("^", item, "[0-9]+$"), available, value = TRUE))
    } else {
      expanded <- c(expanded, item)
    }
  }
  unique(expanded)
}

make_display_parameter <- function(data, tfl_id) {
  if (!"PARAM" %in% names(data)) {
    data$display_parameter <- data$PARAMCD
    return(data)
  }

  data$display_parameter <- data$PARAM
  if (identical(tfl_id, "14.2.10.1.2")) {
    data$display_parameter <- ifelse(
      grepl("^TS", data$PARAMCD) & grepl("家长|Parent|parent", data$PARAM),
      "家长总分",
      ifelse(grepl("^TS", data$PARAMCD), "受试者总分", data$PARAM)
    )
  }
  data
}

add_pedsql_analysis_groups <- function(data) {
  param_prefix <- sub("[0-9]+$", "", data$PARAMCD)
  param_version <- sub("^[A-Z]+", "", data$PARAMCD)
  reporter <- ifelse(param_version %in% c("1", "2"), "受试者报告", "家长报告")
  scale <- dplyr::case_when(
    param_prefix == "TS" ~ "总分",
    param_prefix == "PF" ~ "生理功能",
    param_prefix == "EF" ~ "情感功能",
    param_prefix == "SOF" ~ "社交功能",
    param_prefix == "SCF" ~ "学校表现",
    TRUE ~ data$display_parameter
  )
  data$reporter <- reporter
  data$scale <- scale
  data$analysis_group_id <- paste(reporter, scale, sep = "__")
  data$analysis_group_label <- paste(reporter, scale, sep = " - ")
  data$analysis_group_key <- dplyr::case_when(
    reporter == "受试者报告" & scale == "总分" ~ "subject_total",
    reporter == "受试者报告" & scale == "生理功能" ~ "subject_physical",
    reporter == "受试者报告" & scale == "情感功能" ~ "subject_emotional",
    reporter == "受试者报告" & scale == "社交功能" ~ "subject_social",
    reporter == "受试者报告" & scale == "学校表现" ~ "subject_school",
    reporter == "家长报告" & scale == "总分" ~ "parent_total",
    reporter == "家长报告" & scale == "生理功能" ~ "parent_physical",
    reporter == "家长报告" & scale == "情感功能" ~ "parent_emotional",
    reporter == "家长报告" & scale == "社交功能" ~ "parent_social",
    reporter == "家长报告" & scale == "学校表现" ~ "parent_school",
    TRUE ~ gsub("[^A-Za-z0-9_]+", "_", data$analysis_group_id)
  )
  data
}

add_default_analysis_groups <- function(data) {
  data$reporter <- NA_character_
  data$scale <- data$display_parameter
  data$analysis_group_id <- data$PARAMCD
  data$analysis_group_label <- data$display_parameter
  data$analysis_group_key <- data$PARAMCD
  data
}

prepare_fcn_mmrm_data <- function(raw, spec, add_log = function(...) invisible(NULL)) {
  required_columns(
    raw,
    c("USUBJID", "PARAMCD", "CHG", "BASE", "AVISITN", "AVISIT", "COAFL"),
    paste0(spec$tfl_id, " / ", spec$dataset)
  )

  if (!"ANL01FL" %in% names(raw)) {
    add_log(spec$tfl_id, "：数据集中没有 ANL01FL，本轮只按 COAFL 和 PARAMCD 过滤。")
    raw$ANL01FL <- "是"
  }

  paramcd_expanded <- expand_paramcd_spec(raw, spec$paramcd[[1]])
  missing_requested <- setdiff(spec$paramcd[[1]], unique(c(raw$PARAMCD, gsub("[0-9]+$", "", raw$PARAMCD))))
  if (length(missing_requested) > 0) {
    add_log(spec$tfl_id, "：以下确认 PARAMCD 或前缀在数据中未找到：", paste(missing_requested, collapse = ", "))
  }

  data <- raw |>
    dplyr::filter(is_yes_value(COAFL)) |>
    dplyr::filter(is_yes_value(ANL01FL)) |>
    dplyr::filter(PARAMCD %in% paramcd_expanded) |>
    dplyr::filter(!is.na(CHG), !is.na(BASE), !is.na(AVISITN), AVISITN > 0, !is.na(USUBJID)) |>
    dplyr::mutate(
      USUBJID_F = factor(USUBJID),
      AVISITN_F = factor(AVISITN, levels = sort(unique(AVISITN))),
      AVISIT_LABEL = as.character(AVISIT)
    )

  if ("REGION" %in% names(data)) {
    data$REGION_F <- factor(data$REGION)
  } else if ("COUNTRY" %in% names(data)) {
    data$REGION_F <- factor(data$COUNTRY)
    add_log(spec$tfl_id, "：未找到 REGION，使用 COUNTRY 作为可估计性检查候选；若正式规则不同需统计师确认。")
  } else {
    data$REGION_F <- factor("未提供")
    add_log(spec$tfl_id, "：未找到 REGION 或 COUNTRY，模型运行时将移除 REGION 项。")
  }

  data <- make_display_parameter(data, spec$tfl_id)
  if (identical(spec$tfl_id, "14.2.10.1.2")) {
    data <- add_pedsql_analysis_groups(data)
    add_log(spec$tfl_id, "：PedsQL 按报告者和分量表合并年龄版本后建模；不再按 TS1/TS2/PF1/PF2 等单个 PARAMCD 分别建模。")
  } else {
    data <- add_default_analysis_groups(data)
  }

  duplicate_records <- data |>
    dplyr::count(USUBJID, analysis_group_id, AVISITN, name = "n_records") |>
    dplyr::filter(n_records > 1)
  if (nrow(duplicate_records) > 0) {
    stop(spec$tfl_id, " 发现 subject/analysis_group/visit 重复分析记录，需先确认 ADaM 记录选择规则。")
  }

  attr(data, "expanded_paramcd") <- paramcd_expanded
  attr(data, "analysis_groups") <- unique(data$analysis_group_id)
  data
}

describe_prepared_data <- function(data, spec) {
  if (nrow(data) == 0) {
    return(data.frame(
      tfl_id = spec$tfl_id,
      PARAMCD = NA_character_,
      parameter = NA_character_,
      n_subjects = 0L,
      n_records = 0L,
      n_visits = 0L,
      status = "blocked_data",
      message_cn = "按已确认规则过滤后没有可建模记录。",
      stringsAsFactors = FALSE
    ))
  }

  data |>
    dplyr::group_by(analysis_group_id, analysis_group_label) |>
    dplyr::summarise(
      n_subjects = dplyr::n_distinct(USUBJID),
      n_records = dplyr::n(),
      n_visits = dplyr::n_distinct(AVISITN),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      tfl_id = spec$tfl_id,
      PARAMCD = analysis_group_id,
      parameter = analysis_group_label,
      status = dplyr::if_else(n_visits >= 2 & n_subjects >= 2, "ready", "blocked_data"),
      message_cn = dplyr::if_else(status == "ready", "数据满足最低建模检查。", "访视数或受试者数不足，不能稳定拟合 MMRM。")
    ) |>
    dplyr::select(tfl_id, PARAMCD, parameter, n_subjects, n_records, n_visits, status, message_cn)
}
