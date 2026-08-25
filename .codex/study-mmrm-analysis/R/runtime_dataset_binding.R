# 审批前受控运行数据集绑定：候选发现、确认解析和 manifest 提升。
# 依赖 io.R、intake_review.R（用于读取 manifest）和 intake_extraction.R（用于 SHA helper）。

runtime_dataset_supported_formats <- function() c("csv", "sas7bdat")

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
  pattern <- "file=([^;|[:space:]]+);\\s*format=(csv|sas7bdat);\\s*relative_path=([^;|[:space:]]+);\\s*sha256=([A-Fa-f0-9]{64})"
  match <- regmatches(value, regexec(pattern, value, ignore.case = TRUE, perl = TRUE))[[1]]
  if (length(match) != 5L) return(NULL)
  list(binding_mode = "linked", file = match[[2]], format = tolower(match[[3]]), relative_path = gsub("\\\\", "/", match[[4]]), sha256 = toupper(match[[5]]))
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
    if (!is.list(binding) || !identical(binding$binding_mode, "linked")) stop("PLAN-SCHEMA-DATASET-BINDING-RUNTIME: runtime_dataset_promote_binding only accepts linked bindings.")
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


# ---- ADaM specification 变量级 typed projection ---------------------------
# 基于当前 ADaM specification workbook 布局解析变量级定义、PARAM 定义与 codelist，
# 供 AI 生成 statistical review 候选并与 runtime profile 对齐。只解析已识别布局；
# required header 缺失或布局无法识别即报 parse error，不猜列义、不为未知 workbook 建兼容层。
# 不评分、不排序、不替 AI 选择 dataset/PARAMCD。

# 已登记 ADaM specification XLSX 的（relative_path, absolute_path）。无则空。
runtime_spec_workbook_paths <- function(study_dir, project_dir) {
  manifest <- intake_manifest_for_review(study_dir, project_dir)$rows
  if (!nrow(manifest)) return(data.frame(relative_path = character(), path = character(), stringsAsFactors = FALSE))
  rel <- gsub("\\\\", "/", trimws(as.character(manifest$relative_path)))
  status <- trimws(as.character(manifest$status))
  keep <- startsWith(rel, "input/") & tolower(tools::file_ext(rel)) == "xlsx" & status %in% c("registered_input", "linked_source")
  out <- data.frame(relative_path = character(), path = character(), stringsAsFactors = FALSE)
  for (relative_path in unique(rel[keep])) {
    abs <- normalizePath(file.path(study_dir, relative_path), winslash = "/", mustWork = FALSE)
    if (file.exists(abs)) out <- rbind(out, data.frame(relative_path = relative_path, path = abs, stringsAsFactors = FALSE))
  }
  out
}

# 读取 workbook 每个 sheet 为 trim 后的字符矩阵（保留行列位置，NA -> ""）。
runtime_spec_read_grids <- function(path) {
  if (!requireNamespace("readxl", quietly = TRUE)) stop("缺少 readxl，无法解析 ADaM specification。")
  sheets <- readxl::excel_sheets(path)
  grids <- lapply(sheets, function(s) {
    df <- suppressWarnings(suppressMessages(readxl::read_excel(path, sheet = s, col_names = FALSE, .name_repair = "minimal")))
    if (!nrow(df) || !ncol(df)) return(matrix(character(), 0L, 0L))
    m <- matrix("", nrow = nrow(df), ncol = ncol(df))
    for (j in seq_len(ncol(df))) { v <- as.character(df[[j]]); v[is.na(v)] <- ""; m[, j] <- trimws(v) }
    m
  })
  names(grids) <- sheets
  grids
}

# sheet 分类（与 evidence 层一致的确定性命名约定）。
runtime_spec_is_dataset_sheet <- function(sheet) { u <- toupper(sheet); grepl("^AD[A-Z0-9]+$", u) && !grepl("PARAM$", u) }
runtime_spec_is_param_sheet <- function(sheet) grepl("PARAM$", toupper(sheet))
runtime_spec_is_codelist_sheet <- function(sheet) toupper(trimws(sheet)) == "CODELIST"

# dataset 变量表的规范列标题（按当前 specification 布局）。
runtime_spec_dataset_columns <- function() c(
  variable = "Variable", label = "Label", type = "Type", length = "Length",
  format = "Display Format", codelist = "Controlled Term or Formats",
  core = "Core", derivation = "Source/Derivation/Comments")

# dataset sheet 顶部 "key:" -> value 元数据块（value 取该行最后一个非空单元格）。
runtime_spec_dataset_metadata <- function(grid, header_row) {
  meta <- list()
  for (r in seq_len(header_row - 1L)) {
    key <- grid[r, 1]
    if (!nzchar(key) || !endsWith(key, ":")) next
    values <- grid[r, ][nzchar(grid[r, ])]
    if (length(values) < 2L) next
    meta[[sub(":$", "", key)]] <- values[[length(values)]]
  }
  meta
}

runtime_spec_parse_dataset_sheet <- function(sheet, grid, relative_path) {
  header_row <- NA_integer_
  if (ncol(grid) >= 2L) for (r in seq_len(nrow(grid))) if (grid[r, 1] == "Variable" && grid[r, 2] == "Label") { header_row <- r; break }
  if (is.na(header_row)) stop("specification parse error: sheet ", sheet, " 缺少变量表头（Variable | Label）。")
  header <- grid[header_row, ]
  cols <- runtime_spec_dataset_columns()
  idx <- vapply(cols, function(name) { m <- which(header == name); if (length(m)) m[[1]] else NA_integer_ }, integer(1))
  missing_required <- c("variable", "label", "type")[is.na(idx[c("variable", "label", "type")])]
  if (length(missing_required)) stop("specification parse error: sheet ", sheet, " 缺少必需列：", paste(cols[missing_required], collapse = "、"), "。")
  cell <- function(r, key) { j <- idx[[key]]; if (is.na(j) || j > ncol(grid)) "" else grid[r, j] }
  variables <- list()
  if (header_row < nrow(grid)) for (r in seq.int(header_row + 1L, nrow(grid))) {
    name <- cell(r, "variable")
    if (!nzchar(name)) next
    variables[[length(variables) + 1L]] <- list(
      variable = name, label = cell(r, "label"), type = cell(r, "type"), length = cell(r, "length"),
      format = cell(r, "format"), codelist = cell(r, "codelist"), core = cell(r, "core"),
      derivation = cell(r, "derivation"), source = paste0("sheet=", sheet, "; row=", r))
  }
  list(dataset = sheet, relative_path = relative_path, header_row = header_row,
       metadata = runtime_spec_dataset_metadata(grid, header_row), variables = variables)
}

runtime_spec_parse_param_sheet <- function(sheet, grid, relative_path) {
  if (!nrow(grid)) stop("specification parse error: PARAM sheet ", sheet, " 为空。")
  header <- grid[1, ]
  find <- function(name) { m <- which(toupper(header) == toupper(name)); if (length(m)) m[[1]] else NA_integer_ }
  i_cd <- find("PARAMCD"); i_pm <- find("PARAM"); i_pn <- find("PARAMN")
  if (is.na(i_cd) || is.na(i_pm)) stop("specification parse error: PARAM sheet ", sheet, " 缺少 PARAMCD/PARAM 列。")
  ctx_cols <- setdiff(which(nzchar(header)), c(i_cd, i_pm, i_pn))
  parameters <- list()
  if (nrow(grid) > 1L) for (r in seq.int(2L, nrow(grid))) {
    code <- grid[r, i_cd]
    if (!nzchar(code)) next
    context <- list()
    for (j in ctx_cols) { val <- grid[r, j]; if (nzchar(val)) context[[header[[j]]]] <- val }
    parameters[[length(parameters) + 1L]] <- list(
      paramcd = code, param = grid[r, i_pm], paramn = if (is.na(i_pn)) "" else grid[r, i_pn],
      context = context, source = paste0("sheet=", sheet, "; row=", r))
  }
  list(sheet = sheet, relative_path = relative_path, parameters = parameters)
}

# CODELIST sheet：以「名称行(仅首列)+表头行(值|解码)+若干值行」为一个 block，空行分隔。
runtime_spec_parse_codelists <- function(grid, relative_path) {
  if (!nrow(grid)) return(list())
  out <- list(); r <- 1L; n <- nrow(grid)
  while (r <= n) {
    name <- grid[r, 1]
    if (!nzchar(name) || (ncol(grid) >= 2L && nzchar(grid[r, 2]))) { r <- r + 1L; next }
    header_row <- r + 1L
    if (header_row > n || !nzchar(grid[header_row, 1])) { r <- r + 1L; next }
    decode_label <- if (ncol(grid) >= 2L) grid[header_row, 2] else ""
    # 值行两列均非空；空行或下一个名称行（首列非空、次列空）结束本 block。
    values <- list(); vr <- header_row + 1L
    while (vr <= n && nzchar(grid[vr, 1]) && ncol(grid) >= 2L && nzchar(grid[vr, 2])) {
      values[[length(values) + 1L]] <- list(value = grid[vr, 1], code = grid[vr, 2], source = paste0("sheet=CODELIST; row=", vr))
      vr <- vr + 1L
    }
    out[[length(out) + 1L]] <- list(name = name, decode_label = decode_label, values = values, source = paste0("sheet=CODELIST; row=", header_row))
    r <- vr
  }
  out
}

# 完整 typed projection：跨所有已登记 workbook 汇总 dataset / PARAM / codelist。
runtime_spec_projection <- function(study_dir, project_dir) {
  workbooks <- runtime_spec_workbook_paths(study_dir, project_dir)
  empty <- list(has_specification = FALSE, source_files = character(), datasets = list(), parameters = list(), codelists = list())
  if (!nrow(workbooks)) return(empty)
  datasets <- list(); parameters <- list(); codelists <- list()
  for (i in seq_len(nrow(workbooks))) {
    relative_path <- workbooks$relative_path[[i]]
    grids <- runtime_spec_read_grids(workbooks$path[[i]])
    for (sheet in names(grids)) {
      grid <- grids[[sheet]]
      if (runtime_spec_is_dataset_sheet(sheet)) datasets[[length(datasets) + 1L]] <- runtime_spec_parse_dataset_sheet(sheet, grid, relative_path)
      else if (runtime_spec_is_param_sheet(sheet)) parameters[[length(parameters) + 1L]] <- runtime_spec_parse_param_sheet(sheet, grid, relative_path)
      else if (runtime_spec_is_codelist_sheet(sheet)) codelists <- c(codelists, runtime_spec_parse_codelists(grid, relative_path))
    }
  }
  datasets <- datasets[order(vapply(datasets, function(x) toupper(x$dataset), character(1)), method = "radix")]
  list(has_specification = TRUE, source_files = workbooks$relative_path, datasets = datasets, parameters = parameters, codelists = codelists)
}

# ---- spec 与 runtime profile 变量级对齐 -----------------------------------
runtime_spec_type_class <- function(spec_type) { u <- toupper(trimws(spec_type)); if (u %in% c("CHAR", "CHARACTER", "TEXT", "STRING")) "character" else if (u %in% c("NUM", "NUMERIC", "INTEGER", "FLOAT", "DOUBLE")) "numeric" else NA_character_ }
runtime_spec_runtime_class <- function(cls) { if (cls %in% c("character", "factor")) "character" else if (cls %in% c("numeric", "integer", "double")) "numeric" else NA_character_ }

# 对每个 spec/runtime 都有的 dataset，按变量名给出 matched/runtime-only/spec-only/type-mismatch。
runtime_spec_runtime_alignment <- function(profile_datasets, spec) {
  if (!isTRUE(spec$has_specification)) return(list(datasets = list(), datasets_runtime_only = character(), datasets_spec_only = character()))
  runtime_by_name <- setNames(profile_datasets, vapply(profile_datasets, function(x) toupper(as.character(x$dataset)), character(1)))
  spec_by_name <- setNames(spec$datasets, vapply(spec$datasets, function(x) toupper(x$dataset), character(1)))
  common <- intersect(names(runtime_by_name), names(spec_by_name))
  aligned <- lapply(sort(common), function(key) {
    rt <- runtime_by_name[[key]]; sp <- spec_by_name[[key]]
    rt_vars <- vapply(rt$variables, function(v) toupper(as.character(v$name)), character(1))
    rt_class <- setNames(vapply(rt$variables, function(v) as.character(v$class), character(1)), rt_vars)
    sp_vars <- vapply(sp$variables, function(v) toupper(v$variable), character(1))
    sp_type <- setNames(vapply(sp$variables, function(v) as.character(v$type), character(1)), sp_vars)
    matched <- intersect(rt_vars, sp_vars)
    type_mismatch <- list()
    for (v in matched) {
      sc <- runtime_spec_type_class(sp_type[[v]]); rc <- runtime_spec_runtime_class(rt_class[[v]])
      if (!is.na(sc) && !is.na(rc) && sc != rc) type_mismatch[[length(type_mismatch) + 1L]] <- list(variable = v, spec_type = sp_type[[v]], runtime_class = rt_class[[v]])
    }
    list(dataset = sp$dataset, matched = sort(matched), runtime_only = sort(setdiff(rt_vars, sp_vars)), spec_only = sort(setdiff(sp_vars, rt_vars)), type_mismatch = type_mismatch)
  })
  list(datasets = aligned,
       datasets_runtime_only = sort(setdiff(names(runtime_by_name), names(spec_by_name))),
       datasets_spec_only = sort(setdiff(names(spec_by_name), names(runtime_by_name))))
}
