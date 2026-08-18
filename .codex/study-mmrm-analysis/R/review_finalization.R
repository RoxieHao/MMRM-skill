review_finalize_find_section <- function(lines, number) which(grepl(paste0("^##\\s+", number, "\\."), lines))

review_finalize_set_frontmatter <- function(lines, name, value) {
  if (length(lines) < 3L || trimws(lines[[1L]]) != "---") stop("Review is missing YAML front matter.")
  closing <- which(trimws(lines[-1L]) == "---")
  if (!length(closing)) stop("Review YAML front matter is not closed.")
  closing <- closing[[1L]] + 1L
  matches <- grep(paste0("^", name, "\\s*:"), lines[2:(closing - 1L)])
  replacement <- paste0(name, ": ", value)
  if (length(matches)) lines[[matches[[1L]] + 1L]] <- replacement else lines <- c(lines[seq_len(closing - 1L)], replacement, lines[closing:length(lines)])
  lines
}

review_finalize_issue <- function(scope, field, observed, requirement, resolution) {
  data.frame(issue_id = "", scope = scope, field = field, observed = observed, requirement = requirement, resolution = resolution, status = "unresolved", stringsAsFactors = FALSE, check.names = FALSE)
}

review_finalize_normalize_issues <- function(issues) {
  if (!length(issues)) return(data.frame(issue_id = character(), scope = character(), field = character(), observed = character(), requirement = character(), resolution = character(), status = character(), stringsAsFactors = FALSE, check.names = FALSE))
  out <- do.call(rbind, issues); out$issue_id <- paste0("REVIEW-", sprintf("%03d", seq_len(nrow(out)))); rownames(out) <- NULL; out
}

review_finalize_issue_table <- function(issues) {
  header <- c("| issue_id | scope | question_or_risk | resolution | status |", "|---|---|---|---|---|")
  if (!nrow(issues)) return(header)
  c(header, vapply(seq_len(nrow(issues)), function(i) {
    risk <- paste0("field=", issues$field[[i]], "; observed=", issues$observed[[i]], "; requirement=", issues$requirement[[i]])
    paste0("| ", issues$issue_id[[i]], " | ", endpoint_mapping_escape(issues$scope[[i]]), " | ", endpoint_mapping_escape(risk), " | ", endpoint_mapping_escape(issues$resolution[[i]]), " | unresolved |")
  }, character(1)))
}

review_finalize_replace_section7 <- function(lines, issues) {
  section7 <- review_finalize_find_section(lines, 7); section8 <- review_finalize_find_section(lines, 8)
  if (length(section7) != 1L || length(section8) != 1L || section8 <= section7) stop("Review must contain section 7 before section 8.")
  c(lines[seq_len(section7 - 1L)], lines[[section7]], review_finalize_issue_table(issues), "", lines[section8:length(lines)])
}

review_finalize_format_report <- function(issues) {
  if (!nrow(issues)) return("Finalization preflight passed: no unresolved issues.")
  rows <- vapply(seq_len(nrow(issues)), function(i) paste0("- ", issues$issue_id[[i]], " [", issues$scope[[i]], "] field=", issues$field[[i]], "; observed=", issues$observed[[i]], "; required=", issues$requirement[[i]], "; resolution=", issues$resolution[[i]]), character(1))
  paste(c("Finalization blocked: unresolved issues follow.", rows), collapse = "\n")
}

review_finalize_project_dir <- function(study_dir) {
  current <- normalizePath(study_dir, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "runtime_dataset_binding.R"))) return(current)
    parent <- dirname(current); if (identical(parent, current)) stop("Unable to locate project root."); current <- parent
  }
}

review_finalize_catalog_item <- function(catalog, binding) {
  hits <- Filter(function(item) runtime_dataset_binding_matches(binding, item), catalog)
  if (length(hits) == 1L) hits[[1L]] else NULL
}

review_finalize_render_candidate_table <- function(candidate) {
  table <- candidate$table
  c(paste0("### 表 ", candidate$tfl_id, "：", candidate$tfl_title), "", paste0("| ", paste(statistical_review_candidate_table_columns(), collapse = " | "), " |"), "|---|---|---|---|---|---|", vapply(seq_len(nrow(table)), function(i) paste0("| ", paste(vapply(table[i, , drop = FALSE], endpoint_mapping_escape, character(1)), collapse = " | "), " |"), character(1)), "")
}

review_finalize_process_section3 <- function(lines, study_dir, project_dir) {
  review <- tryCatch(read_statistical_review_from_lines(lines), error = function(e) e)
  if (inherits(review, "error")) stop(conditionMessage(review))
  candidates <- parse_statistical_review_candidate_tables(review)
  catalog <- runtime_dataset_catalog(study_dir, project_dir)
  issues <- list(); bindings <- list()
  for (index in seq_along(candidates)) {
    candidate <- candidates[[index]]; table <- candidate$table; scope <- paste0("TFL ", candidate$tfl_id)
    decisions <- trimws(as.character(table[["统计师决定"]])); notes <- trimws(as.character(table[["统计师备注或修订值"]]))
    for (row_index in seq_len(nrow(table))) {
      rule <- as.character(table[["规则类别"]][[row_index]])
      if (!decisions[[row_index]] %in% c("采用", "修改")) issues[[length(issues) + 1L]] <- review_finalize_issue(scope, rule, decisions[[row_index]], "统计师必须选择采用或修改", "在 Section 3 明确处置该规则。")
      if (!nzchar(notes[[row_index]])) issues[[length(issues) + 1L]] <- review_finalize_issue(scope, rule, "empty statistician note", "每条已处置规则必须有明确备注或修订值", "填写明确、不可继承的规则。")
    }
    dataset_row <- match("分析数据集", table[["规则类别"]])
    if (is.na(dataset_row)) next
    binding <- tryCatch(runtime_dataset_resolve_review_confirmation(table[["AI 识别的候选规则"]][[dataset_row]], notes[[dataset_row]], catalog), error = function(e) e)
    if (inherits(binding, "error")) {
      issues[[length(issues) + 1L]] <- review_finalize_issue(scope, "分析数据集", notes[[dataset_row]], "完整且唯一的 runtime dataset binding", conditionMessage(binding))
    } else {
      table[["AI 识别的候选规则"]][[dataset_row]] <- runtime_dataset_binding_text(binding, "批准运行数据集")
      bindings[[length(bindings) + 1L]] <- list(file = binding$file_name, format = binding$format, relative_path = binding$relative_path, sha256 = binding$sha256)
      population_row <- match("分析人群", table[["规则类别"]])
      if (!is.na(population_row)) {
        population <- tryCatch(statistical_review_parse_population_rule(notes[[population_row]]), error = function(e) e)
        if (inherits(population, "error")) issues[[length(issues) + 1L]] <- review_finalize_issue(scope, "分析人群", notes[[population_row]], "valid population DSL", conditionMessage(population)) else table[["AI 识别的候选规则"]][[population_row]] <- paste0("批准人群：", statistical_review_population_rule_text(population))
      }
    }
    candidates[[index]]$table <- table
  }
  section3 <- review_finalize_find_section(lines, 3); section4 <- review_finalize_find_section(lines, 4)
  rendered <- unlist(lapply(candidates, review_finalize_render_candidate_table), use.names = FALSE)
  updated <- c(lines[seq_len(section3)], "以下规则均需显式确认；不得使用“同上”或跨 TFL 继承。", "", rendered, lines[section4:length(lines)])
  list(lines = updated, candidates = candidates, bindings = bindings, issues = review_finalize_normalize_issues(issues))
}

read_statistical_review_from_lines <- function(lines) {
  temporary <- tempfile("review-lines-", fileext = ".md"); on.exit(unlink(temporary, force = TRUE), add = TRUE); writeLines(lines, temporary, useBytes = TRUE); read_statistical_review(temporary)
}

review_finalize_publish <- function(study_dir, project_dir, target_review, review_lines, bindings) {
  manifest_path <- file.path(study_dir, "backup-trace", "input-manifest.csv")
  before_manifest <- if (file.exists(manifest_path)) readBin(manifest_path, "raw", n = file.info(manifest_path)$size) else raw()
  before_review <- if (file.exists(target_review)) readBin(target_review, "raw", n = file.info(target_review)$size) else NULL
  temporary_review <- tempfile(paste0(".", basename(target_review), "."), tmpdir = dirname(target_review))
  committed <- FALSE
  on.exit({
    unlink(temporary_review, force = TRUE)
    if (!committed) {
      if (length(before_manifest)) writeBin(before_manifest, manifest_path)
      if (is.null(before_review)) unlink(target_review, force = TRUE) else writeBin(before_review, target_review)
    }
  }, add = TRUE)
  runtime_dataset_promote_binding(study_dir, project_dir, bindings)
  review_lines <- review_finalize_set_frontmatter(review_lines, "source_input_sha256", toupper(specification_sha256(manifest_path)))
  writeLines(review_lines, temporary_review, useBytes = TRUE)
  if (!file.rename(temporary_review, target_review)) stop("Unable to atomically publish finalized review.")
  committed <- TRUE
  invisible(target_review)
}

finalize_statistical_review <- function(study_dir, source_review, target_review, allow_unresolved = TRUE) {
  project_dir <- review_finalize_project_dir(study_dir)
  source_lines <- readLines(source_review, encoding = "UTF-8", warn = FALSE)
  processed <- review_finalize_process_section3(source_lines, study_dir, project_dir)
  mapping_path <- endpoint_mapping_path(study_dir)
  mapping <- tryCatch(endpoint_mapping_read(mapping_path), error = function(e) e)
  mapping_issues <- if (inherits(mapping, "error")) review_finalize_normalize_issues(list(review_finalize_issue("ALL", "endpoint-mapping.yaml", conditionMessage(mapping), "valid study-local mapping YAML", "Create or correct endpoint-mapping.yaml."))) else endpoint_mapping_validate(mapping, vapply(processed$candidates, `[[`, character(1), "tfl_id"))
  issue_frames <- Filter(function(frame) nrow(frame) > 0L, list(processed$issues, mapping_issues))
  issues <- if (length(issue_frames)) do.call(rbind, issue_frames) else review_finalize_normalize_issues(list())
  if (nrow(issues)) issues$issue_id <- paste0("REVIEW-", sprintf("%03d", seq_len(nrow(issues))))
  if (nrow(issues)) {
    report <- review_finalize_format_report(issues)
    if (!allow_unresolved) stop(report)
    return(invisible(list(target_review = normalizePath(target_review, winslash = "/", mustWork = FALSE), mapping_count = if (inherits(mapping, "error")) 0L else nrow(mapping), issue_count = nrow(issues), ready_for_final_signature = FALSE, issues = issues, report = report, published = FALSE)))
  }
  mapping_sha <- toupper(specification_sha256(mapping_path))
  final_lines <- endpoint_mapping_render_review_section(processed$lines, mapping)
  final_lines <- review_finalize_replace_section7(final_lines, issues)
  final_lines <- review_finalize_set_frontmatter(final_lines, "endpoint_mapping_file", project_relative_path(mapping_path, project_dir))
  final_lines <- review_finalize_set_frontmatter(final_lines, "endpoint_mapping_sha256", mapping_sha)
  final_lines <- review_finalize_set_frontmatter(final_lines, "finalization_status", "ready_for_final_signature")
  dir.create(dirname(target_review), recursive = TRUE, showWarnings = FALSE)
  review_finalize_publish(study_dir, project_dir, target_review, final_lines, processed$bindings)
  invisible(list(target_review = normalizePath(target_review, winslash = "/", mustWork = TRUE), mapping_count = nrow(mapping), issue_count = 0L, ready_for_final_signature = TRUE, issues = issues, report = "Finalization published successfully.", published = TRUE))
}

review_finalization_self_check <- function() {
  stopifnot(grepl("unresolved issues", review_finalize_format_report(review_finalize_normalize_issues(list(review_finalize_issue("TFL X", "field", "observed", "required", "fix"))))))
  invisible(TRUE)
}
