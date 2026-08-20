# Intake ADaM 证据关联（确定性，仅用 ADaM specification）：在 statistical review 生成阶段，
# 只读取 ADaM specification / SAP / shell，不读取任何 ADaM SAS7BDAT 数据集。对每个 TFL，
# 基于 ADaM specification 的 sheet/row 证据确定性地给出候选“分析数据集”的逻辑名与证据，
# pending 阶段只写候选本身（数据集名），不写 sha256、format、relative_path。真实文件与 SHA
# 的绑定在统计师 approve 后的 finalize/代码生成阶段才产生。
# 所有匹配与排序由 R 端确定性规则完成；相同输入必然产生相同输出。

intake_enrichment_split_row <- function(line) markdown_table_split_row(line, "intake candidate table")

intake_enrichment_join_row <- function(cells) paste0("| ", paste(vapply(cells, markdown_table_escape, character(1)), collapse = " | "), " |")

intake_enrichment_guardrail <- function() {
  "候选为 ADaM specification 中全部分析数据集，仅供统计师确认；未评分、未排序、未自动选择数据集或 PARAMCD，真实文件与 SHA 在批准后绑定。"
}

# 分析数据集候选单元格：稳定列出全部候选数据集逻辑名（按名称升序），不评分、不排序、不含 sha/format。
intake_enrichment_dataset_candidate_text <- function(candidates, has_datasets) {
  if (!has_datasets) return("未在 ADaM specification 中识别数据集 sheet；请统计师依据 spec 补充分析数据集。")
  names <- vapply(candidates, function(x) x$name, character(1))
  paste0("候选分析数据集（ADaM specification 全部数据集，按名称排序，统计师确认后在批准阶段绑定真实文件与 SHA）：", paste(names, collapse = "、"))
}

# 分析数据集证据单元格：给出每个候选的 spec sheet/row（含派生 PARAM sheet）。
intake_enrichment_dataset_evidence_text <- function(candidates, has_datasets) {
  if (!has_datasets) return(intake_enrichment_guardrail())
  details <- vapply(candidates, function(x) {
    param <- if (nzchar(x$param_ref)) paste0("; ", x$param_ref) else ""
    paste0(x$name, " ← ADaM specification ", x$sheet_ref, param)
  }, character(1))
  paste0("ADaM specification 数据集证据（按名称排序，未评分、未排序打分）：", paste(details, collapse = " || "), "。", intake_enrichment_guardrail())
}

intake_enrichment_apply_block <- function(lines, block_start, block_end, title, spec_evidence) {
  table_indices <- which(grepl("^\\s*\\|", lines[block_start:block_end])) + block_start - 1L
  if (length(table_indices) < 3L) return(lines)
  data_indices <- table_indices[-c(1L, 2L)]

  listing <- tryCatch(
    runtime_dataset_spec_list_datasets(spec_evidence),
    error = function(e) list(candidates = list(), has_datasets = FALSE)
  )

  for (index in data_indices) {
    cells <- tryCatch(intake_enrichment_split_row(lines[[index]]), error = function(e) NULL)
    if (is.null(cells) || length(cells) < 3L) next
    category <- trimws(cells[[1]])
    if (identical(category, "分析数据集")) {
      cells[[2]] <- intake_enrichment_dataset_candidate_text(listing$candidates, listing$has_datasets)
      cells[[3]] <- intake_enrichment_dataset_evidence_text(listing$candidates, listing$has_datasets)
      lines[[index]] <- intake_enrichment_join_row(cells)
    }
  }
  lines
}

intake_enrichment_heading_title <- function(line) {
  title <- sub("^###\\s+", "", line)
  title <- sub("^表[^：:]*[：:]", "", title)
  trimws(title)
}

intake_enrich_review_with_adam <- function(study_dir, project_dir, review_path) {
  spec_evidence <- tryCatch(runtime_dataset_spec_evidence(study_dir, project_dir), error = function(e) NULL)
  if (is.null(spec_evidence) || !nrow(spec_evidence)) return(invisible(list(enriched = FALSE, dataset_count = 0L)))
  dataset_sheets <- runtime_dataset_spec_dataset_sheets(spec_evidence)
  if (!length(dataset_sheets)) return(invisible(list(enriched = FALSE, dataset_count = 0L)))
  lines <- readLines(review_path, encoding = "UTF-8", warn = FALSE)
  headings <- which(grepl("^###\\s+", lines))
  for (i in seq_along(headings)) {
    start <- headings[[i]]
    end <- if (i == length(headings)) length(lines) else headings[[i + 1L]] - 1L
    title <- intake_enrichment_heading_title(lines[[start]])
    lines <- intake_enrichment_apply_block(lines, start, end, title, spec_evidence)
  }
  writeLines(lines, review_path, useBytes = TRUE)
  invisible(list(enriched = TRUE, dataset_count = length(dataset_sheets), spec_rows = nrow(spec_evidence)))
}
