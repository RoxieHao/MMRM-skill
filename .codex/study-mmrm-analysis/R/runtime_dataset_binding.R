# 审批前受控运行数据集绑定：候选发现、确认解析和 manifest 提升。
# 依赖 io.R、intake_review.R（用于读取 manifest）和 intake_extraction.R（用于 SHA helper）。

runtime_dataset_supported_formats <- function() c("csv", "sas7bdat", "rds")

runtime_dataset_file_sha256 <- function(path) {
  if (!requireNamespace("digest", quietly = TRUE)) stop("digest package is required to validate runtime dataset binding.")
  toupper(digest::digest(file = path, algo = "sha256"))
}

runtime_dataset_format <- function(file_name) tolower(tools::file_ext(as.character(file_name)))

runtime_dataset_read_schema <- function(path, format) {
  tryCatch({
    data <- switch(
      format,
      sas7bdat = { if (!requireNamespace("haven", quietly = TRUE)) stop("缺少 haven，无法读取 sas7bdat。") ; haven::read_sas(path, n_max = 0) },
      csv = utils::read.csv(path, nrows = 0L, check.names = FALSE, fileEncoding = "UTF-8-BOM"),
      rds = readRDS(path),
      stop("不支持的运行数据格式：", format)
    )
    if (!is.data.frame(data)) stop("运行数据必须读取为 data.frame。")
    names(data)
  }, error = function(e) structure(character(), binding_error = conditionMessage(e)))
}

runtime_dataset_read_paramcd <- function(path, format, columns) {
  if (!"PARAMCD" %in% columns) return(character())
  tryCatch({
    data <- switch(
      format,
      sas7bdat = haven::read_sas(path, col_select = "PARAMCD"),
      csv = read_utf8_bom_csv(path),
      rds = readRDS(path),
      stop("unsupported format")
    )
    if (!is.data.frame(data) || !"PARAMCD" %in% names(data)) return(character())
    sort(unique(trimws(as.character(data$PARAMCD[!is.na(data$PARAMCD)]))))
  }, error = function(e) character())
}

runtime_dataset_catalog <- function(study_dir, project_dir) {
  manifest <- intake_manifest_for_review(study_dir, project_dir)$rows
  rel <- gsub("\\\\", "/", trimws(as.character(manifest$relative_path)))
  if (anyDuplicated(tolower(rel))) stop("input-manifest.csv 的 relative_path 必须唯一，发现重复运行来源记录。")
  selected <- manifest[startsWith(rel, "input/") & trimws(as.character(manifest$status)) %in% c("registered_input", "linked_source"), , drop = FALSE]
  if (!nrow(selected)) return(list())
  items <- lapply(seq_len(nrow(selected)), function(i) {
    row <- selected[i, , drop = FALSE]
    file_name <- trimws(as.character(row$file_name[[1]]))
    relative_path <- gsub("\\\\", "/", trimws(as.character(row$relative_path[[1]])))
    format <- runtime_dataset_format(file_name)
    if (!format %in% runtime_dataset_supported_formats()) return(NULL)
    path <- if (startsWith(relative_path, "input/")) normalizePath(file.path(study_dir, relative_path), winslash = "/", mustWork = FALSE) else normalize_project_relative_path(relative_path, project_dir, "manifest.relative_path")
    expected <- toupper(trimws(as.character(row$sha256[[1]])))
    if (!file.exists(path)) return(list(file_name = file_name, relative_path = relative_path, format = format, sha256 = expected, dataset = tolower(tools::file_path_sans_ext(file_name)), variables = character(), paramcd = character(), readable = FALSE, error = "登记的运行数据文件不存在。"))
    actual <- runtime_dataset_file_sha256(path)
    if (!identical(actual, expected)) return(list(file_name = file_name, relative_path = relative_path, format = format, sha256 = expected, dataset = tolower(tools::file_path_sans_ext(file_name)), variables = character(), paramcd = character(), readable = FALSE, error = "登记 SHA-256 与实体文件不一致。"))
    variables <- runtime_dataset_read_schema(path, format)
    schema_error <- attr(variables, "binding_error")
    list(file_name = file_name, relative_path = relative_path, format = format, sha256 = actual, dataset = tolower(tools::file_path_sans_ext(file_name)), variables = unname(variables), paramcd = if (length(variables)) runtime_dataset_read_paramcd(path, format, variables) else character(), readable = length(variables) > 0L, error = if (is.null(schema_error)) "" else schema_error)
  })
  Filter(Negate(is.null), items)
}

runtime_dataset_binding_text <- function(item, prefix = "Runtime dataset candidate") {
  paste0(prefix, ": file=", item$file_name, "; format=", item$format, "; relative_path=", item$relative_path, "; sha256=", item$sha256)
}

runtime_dataset_parse_binding <- function(value) {
  value <- trimws(as.character(value))
  pattern <- "file=([^;|[:space:]]+);\\s*format=(csv|sas7bdat|rds);\\s*relative_path=([^;|[:space:]]+);\\s*sha256=([A-Fa-f0-9]{64})"
  match <- regmatches(value, regexec(pattern, value, ignore.case = TRUE, perl = TRUE))[[1]]
  if (length(match) != 5L) return(NULL)
  list(file = match[[2]], format = tolower(match[[3]]), relative_path = gsub("\\\\", "/", match[[4]]), sha256 = toupper(match[[5]]))
}

runtime_dataset_binding_matches <- function(binding, item) {
  !is.null(binding) && identical(binding$file, item$file_name) && identical(binding$format, item$format) && identical(binding$relative_path, item$relative_path) && identical(binding$sha256, item$sha256)
}

# Typed selectors come from an AI agent's structured disposition. No free-text opinion parsing is allowed here.
# Resolves only the AI agent's typed dataset selector. It never consumes free-text review opinions or candidate text.
runtime_dataset_resolve_typed_selector <- function(selector, catalog) {
  selector <- trimws(as.character(selector))
  if (!nzchar(selector)) stop("结构化处置缺少 dataset selector。")
  dedup <- function(items) items[!duplicated(vapply(items, function(x) x$file_name, character(1)))]
  stem_of <- function(item) toupper(tools::file_path_sans_ext(item$file_name))
  matched <- dedup(Filter(function(item) {
    identical(item$file_name, selector) || identical(toupper(item$dataset), toupper(selector)) || identical(stem_of(item), toupper(selector))
  }, catalog))
  if (length(matched) != 1L) stop("结构化 dataset selector 必须唯一、精确匹配已登记数据集或 file_name：", selector)
  matched[[1L]]
}
runtime_dataset_promote_binding <- function(study_dir, project_dir, bindings) {
  if (!length(bindings)) stop("没有可提升的已确认运行数据集 binding。")
  manifest_path <- file.path(study_dir, "backup-trace", "input-manifest.csv")
  manifest <- read_utf8_bom_csv(manifest_path)
  required <- c("file_name", "relative_path", "sha256", "status")
  if (length(setdiff(required, names(manifest)))) stop("input-manifest.csv 缺少运行绑定所需列。")
  manifest$relative_path <- gsub("\\\\", "/", trimws(as.character(manifest$relative_path)))
  if (anyDuplicated(tolower(manifest$relative_path))) stop("input-manifest.csv 的 relative_path 必须唯一，不能提升重复记录。")
  for (binding in bindings) {
    index <- which(manifest$relative_path == binding$relative_path & as.character(manifest$file_name) == binding$file)
    if (length(index) != 1L) stop("无法唯一定位待提升的 manifest 记录：", binding$relative_path)
    if (runtime_dataset_format(binding$file) != binding$format) stop("确认 binding 的 file/format 不一致：", binding$file)
    if (!identical(toupper(trimws(as.character(manifest$sha256[[index]]))), binding$sha256)) stop("确认 binding 与 manifest SHA-256 不一致：", binding$file)
    source_path <- if (startsWith(binding$relative_path, "input/")) normalizePath(file.path(study_dir, binding$relative_path), winslash = "/", mustWork = FALSE) else normalize_project_relative_path(binding$relative_path, project_dir, "manifest.relative_path")
    if (!file.exists(source_path)) stop("确认的运行数据文件缺失：", binding$relative_path)
    actual <- runtime_dataset_file_sha256(source_path)
    if (!identical(actual, binding$sha256)) stop("确认后运行数据 SHA-256 已变化：", binding$file)
    manifest$status[[index]] <- "linked_source"
  }
  write_utf8_bom_csv(manifest, manifest_path)
  invisible(runtime_dataset_file_sha256(manifest_path))
}


# ---- ADaM specification 证据关联（仅列出候选，不评分、不排序）-------------
# 目标：在 statistical review 生成阶段仅读取 ADaM specification XLSX，
# 为每个 TFL 稳定列出所有候选分析数据集（dataset sheet），按数据集名升序，
# 并附 sheet/row 与派生 PARAM sheet 证据。不做文本规范化、不做匹配打分、不做排序打分，
# 不读取任何 SAS7BDAT，不写 SHA/format/path，不自动确认数据集或 PARAMCD。
# 真实文件与 SHA 的绑定在统计师 approve 后的 finalize/代码生成阶段才产生。

# 抽取当前 study 已登记 XLSX（ADaM specification）为 sheet/row 证据。
# 返回 data.frame(relative_path, sheet, row, text)；无可读 XLSX 时返回空表。
runtime_dataset_spec_evidence <- function(study_dir, project_dir) {
  empty <- data.frame(relative_path = character(), sheet = character(), row = integer(), text = character(), stringsAsFactors = FALSE)
  manifest <- tryCatch(intake_manifest_for_review(study_dir, project_dir)$rows, error = function(e) NULL)
  if (is.null(manifest) || !nrow(manifest)) return(empty)
  rel <- gsub("\\\\", "/", trimws(as.character(manifest$relative_path)))
  status <- trimws(as.character(manifest$status))
  is_xlsx <- tolower(tools::file_ext(rel)) == "xlsx"
  keep <- startsWith(rel, "input/") & is_xlsx & status %in% c("registered_input", "linked_source")
  if (!any(keep)) return(empty)
  pieces <- list()
  for (relative_path in unique(rel[keep])) {
    path <- normalizePath(file.path(study_dir, relative_path), winslash = "/", mustWork = FALSE)
    if (!file.exists(path)) next
    extracted <- tryCatch(intake_extract_xlsx(path), error = function(e) list(status = "failed"))
    if (!identical(extracted$status, "succeeded")) next
    text <- as.character(extracted$text)
    locators <- as.character(extracted$locators)
    if (!length(text) || length(text) != length(locators)) next
    sheet <- sub("^sheet=([^,]*),.*$", "\\1", locators)
    row <- suppressWarnings(as.integer(sub("^.*,row=([0-9]+)$", "\\1", locators)))
    pieces[[length(pieces) + 1L]] <- data.frame(
      relative_path = relative_path, sheet = trimws(sheet), row = row, text = text,
      stringsAsFactors = FALSE
    )
  }
  if (!length(pieces)) return(empty)
  do.call(rbind, pieces)
}

# 将 spec sheet 关联到某个运行数据集（确定性、精确）：
#   1) sheet 名与逻辑数据集名完全一致（如 ADQSSUM）；
#   2) 该数据集派生的 PARAM sheet（如 ADQSSUM -> QSSUMPARAM，ADLB -> LBPARAM）。
# 不使用宽泛的“文本提及”关联，避免 CONTENT/CODELIST 等结构性 sheet 把噪声引入每个数据集。
runtime_dataset_spec_sheets_for <- function(spec_evidence, logical_name) {
  if (!nrow(spec_evidence)) return(character())
  logical_upper <- toupper(logical_name)
  param_sheet <- paste0(sub("^AD", "", logical_upper), "PARAM")  # 确定性派生 PARAM sheet 名
  targets <- c(logical_upper, param_sheet)
  sheet_upper <- toupper(trimws(spec_evidence$sheet))
  unique(spec_evidence$sheet[sheet_upper %in% targets])
}

# 压缩同 sheet 的 row 为区间字符串，供证据引用。
runtime_dataset_compress_rows <- function(rows) {
  rows <- sort(unique(rows[!is.na(rows)]))
  if (!length(rows)) return("")
  if (length(rows) == 1L) return(as.character(rows))
  paste0(min(rows), "..", max(rows))
}

# 从 spec 证据中确定性识别“数据集 sheet”：以 AD 开头且不是以 PARAM 结尾的 sheet
# （如 ADSL、ADQS、ADQSSUM、ADEXSUM）。派生 PARAM sheet（如 QSSUMPARAM）单独关联。
runtime_dataset_spec_dataset_sheets <- function(spec_evidence) {
  if (!nrow(spec_evidence)) return(character())
  sheets <- unique(trimws(spec_evidence$sheet))
  upper <- toupper(sheets)
  keep <- grepl("^AD[A-Z0-9]+$", upper) & !grepl("PARAM$", upper)
  sheets[keep]
}

# 仅基于 ADaM specification 稳定列出候选数据集（dataset sheet），不评分、不排序打分、不做文本匹配。
# 候选按数据集名（大写）升序稳定排列；每个候选附 sheet/row 与派生 PARAM sheet 证据。
# 相同输入必然产生相同、可复现的候选列表；不读取任何 SAS7BDAT。
runtime_dataset_spec_list_datasets <- function(spec_evidence) {
  dataset_sheets <- runtime_dataset_spec_dataset_sheets(spec_evidence)
  if (!length(dataset_sheets)) return(list(candidates = list(), has_datasets = FALSE))
  ordered <- dataset_sheets[order(toupper(dataset_sheets), method = "radix")]
  candidates <- lapply(ordered, function(sheet) {
    logical_upper <- toupper(sheet)
    param_sheet_name <- paste0(sub("^AD", "", logical_upper), "PARAM")
    sheet_upper <- toupper(trimws(spec_evidence$sheet))
    own <- sheet_upper == logical_upper
    param <- sheet_upper == param_sheet_name
    own_rows <- runtime_dataset_compress_rows(spec_evidence$row[own])
    param_rows <- runtime_dataset_compress_rows(spec_evidence$row[param])
    sheet_ref <- if (nzchar(own_rows)) paste0("sheet=", sheet, "; row=", own_rows) else paste0("sheet=", sheet)
    param_ref <- if (any(param)) paste0("PARAM sheet=", spec_evidence$sheet[param][[1]], if (nzchar(param_rows)) paste0("; row=", param_rows) else "") else ""
    list(name = sheet, sheet_ref = sheet_ref, param_ref = param_ref)
  })
  list(candidates = candidates, has_datasets = TRUE)
}
