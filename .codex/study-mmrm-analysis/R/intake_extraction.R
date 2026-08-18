# Intake 多格式抽取与 input-manifest 审计同步。
# 该模块在 TFL 发现之前运行：先把 input/ 下当前文件同步登记到 backup-trace/input-manifest.csv，
# 再对文本型 PDF、DOCX、XLSX 生成标准化 UTF-8 文本与原始定位映射，供既有扫描逻辑复用。
# 依赖 io.R 中的 read_utf8_bom_csv / write_utf8_bom_csv / normalize_project_relative_path。

intake_manifest_base_columns <- function() {
  c("input_type", "file_name", "relative_path", "version", "file_size_bytes",
    "modified_at", "sha256", "status", "note")
}

intake_manifest_audit_columns <- function() {
  # 抽取文本与定位映射仅在运行期临时目录中存在，绝不写入 manifest。
  c("extraction_status", "extraction_format", "extractor_id", "extractor_version",
    "extracted_at_utc", "extraction_note")
}

intake_extraction_text_formats <- function() c("txt", "md")
intake_extraction_binary_formats <- function() c("pdf", "docx", "xlsx")

intake_utc_now <- function() format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

intake_utc_mtime <- function(path) {
  format(as.POSIXct(file.info(path)$mtime, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

intake_file_sha256 <- function(path) {
  stopifnot(requireNamespace("digest", quietly = TRUE))
  toupper(digest::digest(file = path, algo = "sha256"))
}

# 以 UTF-8（无 BOM）写出文本行，避免 Windows codepage 破坏中文。
intake_write_utf8_lines <- function(lines, path) {
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  payload <- paste0(paste(lines, collapse = "\n"), "\n")
  writeBin(charToRaw(enc2utf8(payload)), con)
}

# 防止派生 CSV 被 Excel 当作公式执行（CSV formula injection）。
intake_sanitize_cell <- function(value) {
  value <- as.character(value)
  if (length(value) != 1L || is.na(value)) return("")
  if (grepl("^[=+@-]", value)) paste0(" ", value) else value
}

# ---- 单文件抽取 ----------------------------------------------------------

intake_extract_pdf <- function(path) {
  if (!requireNamespace("pdftools", quietly = TRUE)) {
    return(list(status = "blocked_missing_package", note = "缺少 pdftools 包，无法抽取 PDF 文本。"))
  }
  pages <- tryCatch(pdftools::pdf_text(path), error = function(e) NULL)
  if (is.null(pages)) return(list(status = "failed", note = "PDF 读取失败，可能损坏或加密。"))
  text <- character()
  locators <- character()
  for (i in seq_along(pages)) {
    lines <- strsplit(pages[[i]], "\r?\n", perl = TRUE)[[1]]
    if (!length(lines)) lines <- ""
    text <- c(text, lines)
    locators <- c(locators, rep(paste0("p", i), length(lines)))
  }
  if (!any(nzchar(trimws(text)))) {
    return(list(status = "ocr_required", note = "PDF 无可提取文本层，疑似扫描件，需要 OCR 后再登记。"))
  }
  list(status = "succeeded", text = text, locators = locators,
       extractor_id = "pdftools", extractor_version = as.character(utils::packageVersion("pdftools")))
}

intake_extract_docx <- function(path) {
  if (!requireNamespace("officer", quietly = TRUE)) {
    return(list(status = "blocked_missing_package", note = "缺少 officer 包，无法抽取 DOCX 文本。"))
  }
  doc <- tryCatch(officer::read_docx(path), error = function(e) NULL)
  if (is.null(doc)) return(list(status = "failed", note = "DOCX 读取失败，可能损坏或加密。"))
  summ <- tryCatch(officer::docx_summary(doc), error = function(e) NULL)
  if (is.null(summ) || !nrow(summ)) return(list(status = "failed", note = "DOCX 无可解析内容。"))
  text <- character()
  locators <- character()
  for (i in seq_len(nrow(summ))) {
    row <- summ[i, , drop = FALSE]
    txt <- as.character(row$text)
    if (length(txt) != 1L || is.na(txt)) txt <- ""
    content_type <- as.character(row$content_type)
    if (identical(content_type, "table cell")) {
      locator <- sprintf("table=%s,row=%s,cell=%s", row$doc_index, row$row_id, row$cell_id)
    } else {
      locator <- sprintf("paragraph=%s", row$doc_index)
    }
    text <- c(text, txt)
    locators <- c(locators, locator)
  }
  if (!any(nzchar(trimws(text)))) return(list(status = "failed", note = "DOCX 提取内容为空。"))
  list(status = "succeeded", text = text, locators = locators,
       extractor_id = "officer", extractor_version = as.character(utils::packageVersion("officer")))
}

intake_extract_xlsx <- function(path) {
  if (!requireNamespace("readxl", quietly = TRUE)) {
    return(list(status = "blocked_missing_package", note = "缺少 readxl 包，无法抽取 XLSX 文本。"))
  }
  sheets <- tryCatch(readxl::excel_sheets(path), error = function(e) NULL)
  if (is.null(sheets)) return(list(status = "failed", note = "XLSX 读取失败，可能损坏或加密。"))
  text <- character()
  locators <- character()
  for (sheet in sheets) {
    df <- tryCatch(
      readxl::read_excel(path, sheet = sheet, col_names = FALSE, .name_repair = "minimal"),
      error = function(e) NULL
    )
    if (is.null(df) || !nrow(df)) next
    for (r in seq_len(nrow(df))) {
      cells <- vapply(seq_len(ncol(df)), function(cc) intake_sanitize_cell(df[[cc]][[r]]), character(1))
      line <- paste(cells, collapse = " | ")
      text <- c(text, line)
      locators <- c(locators, sprintf("sheet=%s,row=%s", sheet, r))
    }
  }
  if (!length(text) || !any(nzchar(trimws(text)))) {
    return(list(status = "failed", note = "XLSX 提取内容为空。"))
  }
  list(status = "succeeded", text = text, locators = locators,
       extractor_id = "readxl", extractor_version = as.character(utils::packageVersion("readxl")))
}

intake_extract_source <- function(absolute_path, extension) {
  switch(
    extension,
    pdf = intake_extract_pdf(absolute_path),
    docx = intake_extract_docx(absolute_path),
    xlsx = intake_extract_xlsx(absolute_path),
    list(status = "failed", note = paste0("不支持的抽取格式：", extension))
  )
}

# ---- input-manifest 同步（方案 A：自动追加新文件，变更/删除 fail closed）----

intake_sync_input_manifest <- function(study_dir, project_dir) {
  manifest_path <- file.path(study_dir, "backup-trace", "input-manifest.csv")
  input_dir <- file.path(study_dir, "input")
  if (!dir.exists(input_dir)) stop("创建 intake review 前必须存在 input/ 目录：", input_dir)
  dir.create(dirname(manifest_path), recursive = TRUE, showWarnings = FALSE)
  stopifnot(requireNamespace("digest", quietly = TRUE))

  existing <- if (file.exists(manifest_path)) read_utf8_bom_csv(manifest_path) else NULL
  if (!is.null(existing) && nrow(existing)) {
    for (col in setdiff(c(intake_manifest_base_columns(), intake_manifest_audit_columns()), names(existing))) {
      existing[[col]] <- rep("", nrow(existing))
    }
    existing$relative_path <- gsub("\\\\", "/", trimws(as.character(existing$relative_path)))
    existing$status <- trimws(as.character(existing$status))
  }

  input_root <- normalizePath(input_dir, winslash = "/", mustWork = TRUE)
  files <- list.files(input_dir, recursive = TRUE, full.names = TRUE, all.files = FALSE, no.. = TRUE)
  files <- files[file.exists(files) & !dir.exists(files)]
  files <- files[!grepl("^~\\$", basename(files))]  # 跳过 Office 临时锁文件
  current_rel <- vapply(files, function(path) {
    normalized <- normalizePath(path, winslash = "/", mustWork = TRUE)
    file.path("input", gsub("\\\\", "/", substr(normalized, nchar(input_root) + 2L, nchar(normalized))))
  }, character(1))
  names(files) <- current_rel

  # input/ 内已确认的 linked_source 仍是同一条审计记录，必须保留并持续校验；
  # 仅保留 input/ 外部记录，绝不为同一 relative_path 再追加 registered_input。
  preserved <- if (!is.null(existing) && nrow(existing)) {
    existing[!startsWith(existing$relative_path, "input/"), , drop = FALSE]
  } else {
    existing[0, , drop = FALSE]
  }
  existing_input <- if (!is.null(existing) && nrow(existing)) {
    existing[startsWith(existing$relative_path, "input/"), , drop = FALSE]
  } else NULL

  conflicts <- character()
  if (!is.null(existing_input) && nrow(existing_input) && anyDuplicated(tolower(existing_input$relative_path))) {
    duplicates <- unique(existing_input$relative_path[duplicated(tolower(existing_input$relative_path)) | duplicated(tolower(existing_input$relative_path), fromLast = TRUE)])
    conflicts <- c(conflicts, paste0("input-manifest.csv 存在重复 relative_path：", paste(duplicates, collapse = "; ")))
  }
  # 删除检测：已登记 input 文件在磁盘缺失。
  if (!is.null(existing_input) && nrow(existing_input)) {
    for (i in seq_len(nrow(existing_input))) {
      rel <- existing_input$relative_path[[i]]
      if (!(rel %in% current_rel)) {
        conflicts <- c(conflicts, paste0("已登记文件缺失：", rel))
      }
    }
  }

  rows_list <- list()
  for (rel in current_rel) {
    path <- files[[rel]]
    sha <- intake_file_sha256(path)
    size <- as.character(file.info(path)$size)
    prior <- if (!is.null(existing_input) && nrow(existing_input)) {
      existing_input[existing_input$relative_path == rel, , drop = FALSE]
    } else {
      existing_input[0, , drop = FALSE]
    }
    if (!is.null(prior) && nrow(prior) > 1L) {
      conflicts <- c(conflicts, paste0("input-manifest.csv 对同一 relative_path 有重复记录：", rel))
      next
    }
    if (!is.null(prior) && nrow(prior) == 1L) {
      prior_sha <- toupper(trimws(as.character(prior$sha256[[1]])))
      if (nzchar(prior_sha) && !identical(prior_sha, sha)) {
        conflicts <- c(conflicts, paste0("已登记文件内容改变：", rel, "（期望 ", prior_sha, "，实际 ", sha, "）"))
        next
      }
      row <- prior[1, , drop = FALSE]
      row$file_size_bytes <- size
      row$sha256 <- sha
      if (!nzchar(trimws(as.character(row$modified_at)))) row$modified_at <- intake_utc_mtime(path)
      if (!nzchar(trimws(as.character(row$version)))) row$version <- "current"
      if (!nzchar(trimws(as.character(row$input_type)))) {
        row$input_type <- if (basename(rel) == "statistician-analysis-input.md") "statistician_briefing" else "source_material"
      }
      if (!nzchar(trimws(as.character(row$status)))) row$status <- "registered_input"
      rows_list[[length(rows_list) + 1L]] <- row
    } else {
      rows_list[[length(rows_list) + 1L]] <- data.frame(
        input_type = if (basename(rel) == "statistician-analysis-input.md") "statistician_briefing" else "source_material",
        file_name = basename(rel),
        relative_path = rel,
        version = "current",
        file_size_bytes = size,
        modified_at = intake_utc_mtime(path),
        sha256 = sha,
        status = "registered_input",
        note = "auto_registered_by_generate_intake_review",
        extraction_status = "",
        extraction_format = "",
        extractor_id = "",
        extractor_version = "",
        extracted_text_path = "",
        extracted_text_sha256 = "",
        location_map_path = "",
        location_map_sha256 = "",
        extracted_at_utc = "",
        extraction_note = "",
        stringsAsFactors = FALSE,
        check.names = FALSE
      )
    }
  }

  if (length(conflicts)) {
    stop(
      "input-manifest.csv 与 input/ 不一致，已停止（需人工确认后重登记）：\n  - ",
      paste(conflicts, collapse = "\n  - "),
      "\n若确认这些变更有意，请手工更新或删除对应 manifest 行后重跑。"
    )
  }

  all_cols <- c(intake_manifest_base_columns(), intake_manifest_audit_columns())
  input_rows <- if (length(rows_list)) do.call(rbind, lapply(rows_list, function(r) r[, all_cols, drop = FALSE])) else NULL
  if (!is.null(preserved) && nrow(preserved)) preserved <- preserved[, all_cols, drop = FALSE]
  manifest <- rbind(preserved, input_rows)
  if (is.null(manifest) || !nrow(manifest)) stop("input/ 下未发现任何可登记文件。")
  rownames(manifest) <- NULL
  write_utf8_bom_csv(manifest, manifest_path)
  invisible(manifest_path)
}

# ---- 抽取并回写 manifest 审计列 -----------------------------------------

intake_prepare_extractions <- function(study_dir, project_dir) {
  intake_sync_input_manifest(study_dir, project_dir)
  manifest_path <- file.path(study_dir, "backup-trace", "input-manifest.csv")
  manifest <- read_utf8_bom_csv(manifest_path)
  for (col in setdiff(intake_manifest_audit_columns(), names(manifest))) manifest[[col]] <- rep("", nrow(manifest))
  manifest$relative_path <- gsub("\\\\", "/", trimws(as.character(manifest$relative_path)))
  manifest$status <- trimws(as.character(manifest$status))

  # 派生文本只在系统临时目录中存活；调用方在扫描/渲染结束后负责删除。
  extract_root <- tempfile("mmrm-intake-extractions-")
  dir.create(extract_root, recursive = TRUE, showWarnings = FALSE)
  temporary_sources <- list()
  extracted_count <- 0L

  for (i in seq_len(nrow(manifest))) {
    rel <- manifest$relative_path[[i]]
    if (!startsWith(rel, "input/") || !identical(manifest$status[[i]], "registered_input")) next
    ext <- tolower(tools::file_ext(rel))
    absolute <- normalizePath(file.path(study_dir, rel), winslash = "/", mustWork = FALSE)

    if (ext %in% intake_extraction_text_formats()) {
      manifest$extraction_status[[i]] <- "not_required"
      manifest$extraction_format[[i]] <- ext
      manifest$extractor_id[[i]] <- "native"
      manifest$extractor_version[[i]] <- ""
      manifest$extracted_at_utc[[i]] <- ""
      manifest$extraction_note[[i]] <- "文本文件，直接扫描无需二进制抽取。"
      next
    }
    if (!(ext %in% intake_extraction_binary_formats())) {
      manifest$extraction_status[[i]] <- "not_required"
      manifest$extraction_format[[i]] <- ext
      manifest$extractor_id[[i]] <- "native"
      manifest$extractor_version[[i]] <- ""
      manifest$extracted_at_utc[[i]] <- ""
      manifest$extraction_note[[i]] <- "非文本扫描格式；由其它流程处理或不参与 TFL 文本发现。"
      next
    }

    result <- if (file.exists(absolute)) intake_extract_source(absolute, ext) else list(status = "failed", note = "登记文件在抽取时缺失。")
    manifest$extraction_format[[i]] <- ext
    manifest$extraction_status[[i]] <- result$status
    manifest$extracted_at_utc[[i]] <- intake_utc_now()
    manifest$extractor_id[[i]] <- if (is.null(result$extractor_id)) "" else result$extractor_id
    manifest$extractor_version[[i]] <- if (is.null(result$extractor_version)) "" else result$extractor_version
    manifest$extraction_note[[i]] <- if (is.null(result$note)) "已在运行期临时目录抽取；扫描结束后删除。" else result$note

    if (identical(result$status, "succeeded")) {
      target_dir <- file.path(extract_root, as.character(i))
      dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
      text_path <- file.path(target_dir, "extracted-text.txt")
      map_path <- file.path(target_dir, "source-locations.csv")
      intake_write_utf8_lines(result$text, text_path)
      write_utf8_bom_csv(
        data.frame(extracted_line = seq_along(result$text), source_locator = result$locators,
                   stringsAsFactors = FALSE, check.names = FALSE), map_path
      )
      temporary_sources[[rel]] <- list(scan_path = text_path, location_map_path = map_path)
      extracted_count <- extracted_count + 1L
    }
  }

  all_cols <- c(intake_manifest_base_columns(), intake_manifest_audit_columns())
  manifest <- manifest[, all_cols, drop = FALSE]
  write_utf8_bom_csv(manifest, manifest_path)
  list(manifest_path = manifest_path, extract_root = extract_root,
       temporary_sources = temporary_sources, extracted_count = extracted_count)
}

# ---- 可扫描来源（原生文本 + 派生抽取文本）--------------------------------

intake_scannable_sources <- function(manifest, study_dir, temporary_sources = list()) {
  rows <- manifest$rows
  input_root <- paste0(normalizePath(file.path(study_dir, "input"), winslash = "/", mustWork = TRUE), "/")
  extension <- tolower(tools::file_ext(rows$absolute_path))
  inside_input <- startsWith(tolower(rows$absolute_path), tolower(input_root))
  status <- trimws(as.character(rows$status))
  extraction_status <- if ("extraction_status" %in% names(rows)) trimws(as.character(rows$extraction_status)) else rep("", nrow(rows))

  scan_path <- character()
  relative_path <- character()
  location_map_path <- character()

  text_idx <- which(inside_input & extension %in% intake_extraction_text_formats() & status == "registered_input")
  for (i in text_idx) {
    scan_path <- c(scan_path, rows$absolute_path[[i]])
    relative_path <- c(relative_path, rows$relative_path[[i]])
    location_map_path <- c(location_map_path, NA_character_)
  }

  extr_idx <- which(inside_input & extraction_status == "succeeded" & status == "registered_input")
  for (i in extr_idx) {
    rel <- rows$relative_path[[i]]
    temporary <- temporary_sources[[rel]]
    if (is.null(temporary) || !file.exists(temporary$scan_path) || !file.exists(temporary$location_map_path)) next
    scan_path <- c(scan_path, temporary$scan_path)
    relative_path <- c(relative_path, rel)
    location_map_path <- c(location_map_path, temporary$location_map_path)
  }

  data.frame(scan_path = scan_path, relative_path = relative_path, location_map_path = location_map_path,
             stringsAsFactors = FALSE, check.names = FALSE)
}

# 生成 scan trace 中的抽取审计段落。
intake_extraction_trace_lines <- function(rows) {
  if (is.null(rows) || !nrow(rows)) return("- 无已登记 input 文件。")
  rel <- gsub("\\\\", "/", trimws(as.character(rows$relative_path)))
  status_col <- if ("extraction_status" %in% names(rows)) trimws(as.character(rows$extraction_status)) else rep("", nrow(rows))
  note_col <- if ("extraction_note" %in% names(rows)) trimws(as.character(rows$extraction_note)) else rep("", nrow(rows))
  keep <- startsWith(rel, "input/")
  rel <- rel[keep]; status_col <- status_col[keep]; note_col <- note_col[keep]
  if (!length(rel)) return("- 无已登记 input 文件。")
  vapply(seq_along(rel), function(i) {
    status <- if (nzchar(status_col[[i]])) status_col[[i]] else "unknown"
    suffix <- if (nzchar(note_col[[i]])) paste0("：", note_col[[i]]) else ""
    paste0("- ", rel[[i]], " [", status, "]", suffix)
  }, character(1))
}

# 将同前缀的数值型定位压缩为区间，避免 source_ref 罗列大量连续段落/页码。
intake_compress_locators <- function(locators) {
  locators <- unique(locators[!is.na(locators) & nzchar(locators)])
  if (!length(locators)) return(character())
  parts <- regmatches(locators, regexec("^(.*?)([0-9]+)$", locators, perl = TRUE))
  ok <- vapply(parts, function(x) length(x) == 3L, logical(1))
  if (all(ok)) {
    prefixes <- vapply(parts, function(x) x[[2]], character(1))
    nums <- vapply(parts, function(x) as.integer(x[[3]]), integer(1))
    if (length(unique(prefixes)) == 1L) {
      lo <- min(nums); hi <- max(nums); pre <- prefixes[[1]]
      if (lo == hi) return(paste0(pre, lo))
      return(paste0(pre, lo, "..", hi))
    }
  }
  if (length(locators) > 12L) {
    locators <- c(locators[1:12], paste0("...(+", length(locators) - 12L, ")"))
  }
  locators
}
