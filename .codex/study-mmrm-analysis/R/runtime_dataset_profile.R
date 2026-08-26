# 全量 ADaM 结构化 profile：读取每个已登记 ADaM 的全部记录，产出变量元数据、真实取值水平、
# PARAMCD/PARAM 频数与数据集级事实，供 AI 生成 statistical review 候选。
# 只输出聚合事实（变量、类型、水平计数、PARAMCD/PARAM 计数），不输出 subject-level 原始记录或 subject ID 取值。
# 依赖 io.R 与 runtime_dataset_binding.R（catalog、路径与 SHA 校验）。

runtime_dataset_profile_level_cap <- function() 50L
runtime_dataset_profile_subject_columns <- function() c("USUBJID", "SUBJID")

runtime_dataset_read_all <- function(path, format) {
  switch(format,
    sas7bdat = { if (!requireNamespace("haven", quietly = TRUE)) stop("缺少 haven，无法读取 sas7bdat。"); as.data.frame(haven::read_sas(path)) },
    csv = read_utf8_bom_csv(path),
    stop("不支持的运行数据格式：", format))
}

runtime_dataset_profile_variable <- function(column, name, emit_levels = TRUE) {
  label <- attr(column, "label"); label <- if (is.null(label)) "" else as.character(label)[[1]]
  present <- column[!is.na(column)]
  distinct <- unique(present)
  levels_out <- list()
  if (emit_levels && length(distinct) > 0L && length(distinct) <= runtime_dataset_profile_level_cap()) {
    counts <- sort(table(as.character(present)), decreasing = TRUE)
    levels_out <- lapply(seq_along(counts), function(i) list(value = names(counts)[[i]], count = as.integer(counts[[i]])))
  }
  missing <- as.integer(sum(is.na(column)))
  list(name = name, label = label, class = class(column)[[1]], missing = missing, missing_rate = if (length(column)) round(missing / length(column), 6L) else 0, distinct_count = length(distinct), levels = levels_out)
}

runtime_dataset_profile_paramcd <- function(data) {
  if (!"PARAMCD" %in% names(data)) return(list())
  code <- trimws(as.character(data$PARAMCD))
  param <- if ("PARAM" %in% names(data)) trimws(as.character(data$PARAM)) else rep("", length(code))
  keep <- !is.na(code) & nzchar(code)
  if (!any(keep)) return(list())
  counts <- sort(table(paste(code[keep], param[keep], sep = "\r")), decreasing = TRUE)
  lapply(names(counts), function(k) { parts <- strsplit(k, "\r", fixed = TRUE)[[1]]; list(paramcd = parts[[1]], param = if (length(parts) > 1L) parts[[2]] else "", count = as.integer(counts[[k]])) })
}

# ---- MMRM 决策相关聚合事实（确定性；用标准 ADaM 命名约定定位关键列）--------
# 缺少所需列时该项事实返回 NULL（跳过，不报错、不臆造）；只输出聚合计数，不输出 subject ID 或整行。
runtime_dataset_profile_resolve_keys <- function(cols) {
  first_present <- function(cands) { hit <- cands[cands %in% cols]; if (length(hit)) hit[[1]] else NA_character_ }
  list(
    subject = first_present(c("USUBJID", "SUBJID")),
    endpoint = if ("PARAMCD" %in% cols) "PARAMCD" else NA_character_,
    visit = first_present(c("AVISITN", "AVISIT", "VISITNUM", "VISIT")),
    treatment = first_present(c("TRT01P", "TRTP", "TRT01A", "TRTA")),
    change = if ("CHG" %in% cols) "CHG" else NA_character_)
}

runtime_dataset_profile_crosstab <- function(data, keys, cap = 200L) {
  if (anyNA(c(keys$endpoint, keys$treatment, keys$visit, keys$subject))) return(NULL)
  ep <- as.character(data[[keys$endpoint]]); tr <- as.character(data[[keys$treatment]]); vs <- as.character(data[[keys$visit]]); sj <- as.character(data[[keys$subject]])
  keep <- !is.na(ep) & !is.na(tr) & !is.na(vs) & !is.na(sj)
  ep <- ep[keep]; tr <- tr[keep]; vs <- vs[keep]; sj <- sj[keep]
  if (!length(ep)) return(list(cell_count = 0L, truncated = FALSE, cells = list()))
  key <- paste(ep, tr, vs, sep = "\r")
  rows <- table(key); subj <- table(key[!duplicated(paste(key, sj, sep = "\r"))])
  names_sorted <- sort(names(rows), method = "radix"); truncated <- length(names_sorted) > cap
  cells <- lapply(head(names_sorted, cap), function(k) { p <- strsplit(k, "\r", fixed = TRUE)[[1]]; list(paramcd = p[[1]], treatment = p[[2]], visit = if (length(p) > 2L) p[[3]] else "", rows = as.integer(rows[[k]]), subjects = as.integer(subj[[k]])) })
  list(cell_count = length(names_sorted), truncated = truncated, cells = cells)
}

runtime_dataset_profile_postbaseline_coverage <- function(data, keys) {
  if (anyNA(c(keys$subject, keys$change))) return(NULL)
  sj <- as.character(data[[keys$subject]]); chg <- data[[keys$change]]
  list(subjects_with_postbaseline_change = as.integer(length(unique(sj[!is.na(chg)]))))
}

runtime_dataset_profile_treatment_visit_cells <- function(data, keys, sparse_below = 2L, cap = 200L) {
  if (anyNA(c(keys$treatment, keys$visit, keys$subject))) return(NULL)
  tr <- as.character(data[[keys$treatment]]); vs <- as.character(data[[keys$visit]]); sj <- as.character(data[[keys$subject]])
  keep <- !is.na(tr) & !is.na(vs); tr <- tr[keep]; vs <- vs[keep]; sj <- sj[keep]
  trs <- sort(unique(tr)); vss <- sort(unique(vs))
  key <- paste(tr, vs, sep = "\r"); subj <- table(key[!duplicated(paste(key, sj, sep = "\r"))])
  full <- as.vector(outer(trs, vss, function(a, b) paste(a, b, sep = "\r")))
  empty <- setdiff(full, names(subj)); sparse <- names(subj)[as.integer(subj[names(subj)]) < sparse_below]
  cells <- lapply(head(sort(sparse), cap), function(k) { p <- strsplit(k, "\r", fixed = TRUE)[[1]]; list(treatment = p[[1]], visit = if (length(p) > 1L) p[[2]] else "", subjects = as.integer(subj[[k]])) })
  list(treatment_levels = length(trs), visit_levels = length(vss), total_cells = length(trs) * length(vss), empty_cell_count = length(empty), sparse_cell_count = length(sparse), sparse_cells = cells)
}

runtime_dataset_profile_dimensions <- function(data, cap = 100L) {
  dcols <- intersect(c("PARCAT1", "PARCAT2"), names(data))
  if (!length(dcols)) return(NULL)
  key <- do.call(paste, c(lapply(dcols, function(cc) as.character(data[[cc]])), sep = "\r"))
  counts <- sort(table(key), decreasing = TRUE)
  limited <- head(counts, cap)
  combos <- lapply(seq_along(limited), function(i) {
    p <- strsplit(paste0(names(limited)[[i]], "\r"), "\r", fixed = TRUE)[[1]]
    c(setNames(as.list(p), dcols), list(count = as.integer(limited[[i]])))
  })
  list(columns = dcols, combination_count = length(counts), combinations = combos)
}

runtime_dataset_profile_mmrm <- function(data) {
  keys <- runtime_dataset_profile_resolve_keys(names(data))
  list(
    keys = keys,
    endpoint_treatment_visit = runtime_dataset_profile_crosstab(data, keys),
    postbaseline = runtime_dataset_profile_postbaseline_coverage(data, keys),
    treatment_visit_cells = runtime_dataset_profile_treatment_visit_cells(data, keys),
    dimensions = runtime_dataset_profile_dimensions(data))
}

runtime_dataset_profile_subject_count <- function(data) {
  col <- intersect(runtime_dataset_profile_subject_columns(), names(data))
  if (!length(col)) return(NA_integer_)
  length(unique(data[[col[[1]]]][!is.na(data[[col[[1]]]])]))
}

runtime_dataset_profile_one <- function(item, study_dir, project_dir) {
  base <- list(file = item$file_name, format = item$format, relative_path = item$relative_path, sha256 = item$sha256, dataset = item$dataset)
  unreadable <- function(message) c(base, list(readable = FALSE, error = message, row_count = NA_integer_, subject_count = NA_integer_, variables = list(), paramcd = list()))
  if (!isTRUE(item$readable)) return(unreadable(if (nzchar(item$error)) item$error else "运行数据不可读。"))
  path <- if (startsWith(item$relative_path, "input/")) normalizePath(file.path(study_dir, item$relative_path), winslash = "/", mustWork = FALSE) else normalize_project_relative_path(item$relative_path, project_dir, "manifest.relative_path")
  data <- tryCatch(runtime_dataset_read_all(path, item$format), error = function(e) e)
  if (inherits(data, "error")) return(unreadable(conditionMessage(data)))
  subject_cols <- intersect(runtime_dataset_profile_subject_columns(), names(data))
  variables <- lapply(names(data), function(n) runtime_dataset_profile_variable(data[[n]], n, emit_levels = !(n %in% subject_cols)))
  c(base, list(readable = TRUE, error = "", row_count = nrow(data), subject_count = runtime_dataset_profile_subject_count(data), variables = variables, paramcd = runtime_dataset_profile_paramcd(data), mmrm = runtime_dataset_profile_mmrm(data)))
}

runtime_dataset_profile <- function(study_dir, project_dir) {
  catalog <- runtime_dataset_catalog(study_dir, project_dir)
  datasets <- lapply(catalog, runtime_dataset_profile_one, study_dir = study_dir, project_dir = project_dir)
  datasets <- datasets[order(vapply(datasets, function(x) x$file, character(1)), method = "radix")]
  specification <- runtime_spec_projection(study_dir, project_dir)
  alignment <- runtime_spec_runtime_alignment(datasets, specification)
  list(profile_schema_version = "1.1", study_id = basename(normalizePath(study_dir, winslash = "/", mustWork = TRUE)), dataset_count = length(datasets), datasets = datasets, specification = specification, alignment = alignment)
}

runtime_dataset_profile_path <- function(study_dir) file.path(study_dir, "backup-trace", "intake-mmrm-profile.yaml")
runtime_dataset_write_profile <- function(study_dir, project_dir) {
  profile <- runtime_dataset_profile(study_dir, project_dir)
  path <- runtime_dataset_profile_path(study_dir)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  yaml::write_yaml(profile, path)
  invisible(list(path = normalizePath(path, winslash = "/", mustWork = TRUE), dataset_count = profile$dataset_count))
}
