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

runtime_dataset_resolve_review_confirmation <- function(candidate_text, note, catalog) {
  candidates <- Filter(function(item) !is.null(runtime_dataset_parse_binding(candidate_text)) && runtime_dataset_binding_matches(runtime_dataset_parse_binding(candidate_text), item), catalog)
  is_confirmation <- function(value) grepl("^(确认|確認|confirm|confirmed)$", trimws(as.character(value)), ignore.case = TRUE)
  binding_occurrences <- lengths(regmatches(candidate_text, gregexpr("file=", candidate_text, fixed = TRUE)))
  if (length(candidates) == 1L && binding_occurrences == 1L && is_confirmation(note)) return(candidates[[1]])
  exact_file <- trimws(as.character(note))
  named <- Filter(function(item) identical(item$file_name, exact_file), catalog)
  if (length(named) != 1L) stop("分析数据集必须对唯一候选填写“确认”，或在候选歧义时填写完整 file_name；不接受逻辑数据集名、路径或猜测扩展名。")
  named[[1]]
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
