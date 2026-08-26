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

  duplicate_records <- data |>
    dplyr::count(USUBJID, PARAMCD, AVISITN, name = "n_records") |>
    dplyr::filter(n_records > 1)
  if (nrow(duplicate_records) > 0) {
    stop(spec$tfl_id, " 发现 subject/PARAMCD/visit 重复分析记录，需先确认 ADaM 记录选择规则。")
  }

  attr(data, "expanded_paramcd") <- paramcd_expanded
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
    dplyr::group_by(PARAMCD, display_parameter) |>
    dplyr::summarise(
      n_subjects = dplyr::n_distinct(USUBJID),
      n_records = dplyr::n(),
      n_visits = dplyr::n_distinct(AVISITN),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      tfl_id = spec$tfl_id,
      parameter = display_parameter,
      status = dplyr::if_else(n_visits >= 2 & n_subjects >= 2, "ready", "blocked_data"),
      message_cn = dplyr::if_else(status == "ready", "数据满足最低建模检查。", "访视数或受试者数不足，不能稳定拟合 MMRM。")
    ) |>
    dplyr::select(tfl_id, PARAMCD, parameter, n_subjects, n_records, n_visits, status, message_cn)
}
