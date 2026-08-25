review_finalize_find_section <- function(lines, number) which(grepl(paste0("^##\\s+", number, "\\."), lines))
review_finalize_issue_frame <- function(id, scope, field, observed, requirement, resolution) data.frame(issue_id = id, scope = scope, field = field, observed = observed, requirement = requirement, resolution = resolution, status = "unresolved", stringsAsFactors = FALSE, check.names = FALSE)
review_finalize_empty_issues <- function() data.frame(issue_id = character(), scope = character(), field = character(), observed = character(), requirement = character(), resolution = character(), status = character(), stringsAsFactors = FALSE, check.names = FALSE)
review_finalize_issue_table <- function(issues) { header <- c("| issue_id | scope | question_or_risk | resolution | status |", "|---|---|---|---|---|"); if (!nrow(issues)) return(header); c(header, vapply(seq_len(nrow(issues)), function(i) paste0("| ", markdown_table_escape(issues$issue_id[[i]]), " | ", markdown_table_escape(issues$scope[[i]]), " | field=", markdown_table_escape(issues$field[[i]]), "; observed=", markdown_table_escape(issues$observed[[i]]), "; requirement=", markdown_table_escape(issues$requirement[[i]]), " | ", markdown_table_escape(issues$resolution[[i]]), " | unresolved |"), character(1))) }
review_finalize_replace_section <- function(lines, number, content) { start <- review_finalize_find_section(lines, number); next_start <- review_finalize_find_section(lines, number + 1L); if (length(start) != 1L || (number < 8L && length(next_start) != 1L)) stop("Review section structure invalid."); end <- if (number == 8L) length(lines) else next_start - 1L; c(if (start > 1L) lines[seq_len(start - 1L)] else character(), lines[[start]], content, if (end < length(lines)) lines[(end + 1L):length(lines)] else character()) }
review_finalize_error_category <- function(message) { hit <- regmatches(message, regexpr("PLAN-(SCHEMA|TRACE|DERIVATION|MODEL|TREATMENT|PARITY|HASH)-[A-Z0-9_-]+", message)); if (length(hit) && nzchar(hit)) hit else if (grepl("TRACE", message)) "PLAN-TRACE-INVALID" else if (grepl("recode|derivation|cycle|target|source values", message, ignore.case = TRUE)) "PLAN-DERIVATION-INVALID" else if (grepl("treatment", message, ignore.case = TRUE)) "PLAN-TREATMENT-INVALID" else if (grepl("fixed|covariance|df_method|estimand", message, ignore.case = TRUE)) "PLAN-MODEL-INVALID" else "PLAN-SCHEMA-INVALID" }
review_finalize_project_dir <- function(study_dir) { current <- normalizePath(study_dir, winslash = "/", mustWork = TRUE); repeat { if (dir.exists(file.path(current, ".codex", "study-mmrm-analysis"))) return(current); parent <- dirname(current); if (parent == current) stop("Unable to locate project root."); current <- parent } }
# Reviewer-authored unresolved issues block finalization. Machine-generated PLAN-* rows (written
# by a prior blocked finalization) are excluded here because they are regenerated from live
# validation each run; otherwise a fixed study could never re-finalize.
review_finalize_existing_issues <- function(review) { issues <- statistical_review_issues(review); issues[trimws(as.character(issues$status)) != "resolved" & !grepl("^PLAN-", trimws(as.character(issues$issue_id))), , drop = FALSE] }
# Render a Section 7 issue table that preserves every existing reviewer row verbatim (including
# resolutions and resolved statuses) and appends the machine-generated validation blockers that
# are not already present. Only aggregate issue metadata is emitted; no legacy trap content.
review_finalize_render_blocked_section <- function(existing, generated) {
  header <- c("| issue_id | scope | question_or_risk | resolution | status |", "|---|---|---|---|---|")
  rows <- character(); existing_ids <- character()
  if (!is.null(existing) && nrow(existing)) {
    existing_ids <- as.character(existing$issue_id)
    rows <- c(rows, vapply(seq_len(nrow(existing)), function(i) paste0("| ", markdown_table_escape(existing$issue_id[[i]]), " | ", markdown_table_escape(existing$scope[[i]]), " | ", markdown_table_escape(existing$question_or_risk[[i]]), " | ", markdown_table_escape(existing$resolution[[i]]), " | ", markdown_table_escape(existing$status[[i]]), " |"), character(1)))
  }
  if (!is.null(generated) && nrow(generated)) {
    for (i in seq_len(nrow(generated))) {
      if (as.character(generated$issue_id[[i]]) %in% existing_ids) next
      rows <- c(rows, paste0("| ", markdown_table_escape(generated$issue_id[[i]]), " | ", markdown_table_escape(generated$scope[[i]]), " | field=", markdown_table_escape(generated$field[[i]]), "; observed=", markdown_table_escape(generated$observed[[i]]), "; requirement=", markdown_table_escape(generated$requirement[[i]]), " | ", markdown_table_escape(generated$resolution[[i]]), " | unresolved |"))
    }
  }
  c(header, rows)
}
review_finalize_atomic_write <- function(lines, target) {
  dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(paste0(".", basename(target), "."), tmpdir = dirname(target))
  backup <- NULL; success <- FALSE
  on.exit({
    unlink(temporary, force = TRUE)
    if (!success && !is.null(backup) && file.exists(backup)) file.copy(backup, target, overwrite = TRUE)
    if (!is.null(backup)) unlink(backup, force = TRUE)
  }, add = TRUE)
  writeLines(lines, temporary, useBytes = TRUE)
  if (file.exists(target)) { backup <- tempfile("review-backup-"); if (!file.copy(target, backup, overwrite = TRUE)) stop("Unable to back up review before publication.") }
  if (file.exists(target) && unlink(target, force = TRUE) != 0L) stop("Unable to replace existing finalized review.")
  if (!file.rename(temporary, target)) stop("Unable to atomically publish finalized review.")
  success <- TRUE
  invisible(target)
}

finalize_statistical_review <- function(study_dir, source_review, target_review, reviewer, allow_unresolved = TRUE) {
  if (!nzchar(trimws(reviewer))) stop("reviewer must be nonempty; the Compile trigger supplies reviewer identity to finalization.")
  project_dir <- review_finalize_project_dir(study_dir); issues <- list()
  review <- tryCatch(read_statistical_review(source_review), error = function(e) e)
  if (inherits(review, "error")) issues[[length(issues) + 1L]] <- review_finalize_issue_frame("PLAN-SCHEMA-REVIEW", "ALL", "statistical-review.md", conditionMessage(review), "valid review schema", "Correct the review.")
  # 只 finalize 已由 Compile 产出 candidate 的 review；状态不符时不改动任何文件，快速拒绝。
  if (!inherits(review, "error") && !identical(as.character(review$metadata$review_status), "ready_for_compilation")) {
    status_issue <- review_finalize_issue_frame("PLAN-SCHEMA-REVIEW-STATUS", "ALL", "review_status", as.character(review$metadata$review_status), "ready_for_compilation", "Run Compile Analysis Plan to produce analysis-plan.candidate.yaml and set review_status=ready_for_compilation before finalization.")
    return(invisible(list(target_review = normalizePath(target_review, winslash = "/", mustWork = FALSE), analysis_count = 0L, issue_count = 1L, approved = FALSE, issues = status_issue, report = "Finalization refused: review_status is not ready_for_compilation; nothing was changed.", published = FALSE)))
  }
  registry <- tryCatch(source_evidence_registry(project_dir, study_dir), error = function(e) e)
  if (inherits(registry, "error")) issues[[length(issues) + 1L]] <- review_finalize_issue_frame("PLAN-HASH-SOURCE", "ALL", "source_evidence", conditionMessage(registry), "canonical registered source projection", "Correct manifest paths and hashes.")
  plan <- NULL
  if (!inherits(review, "error") && !inherits(registry, "error")) {
    trace_ids <- tryCatch(statistical_review_trace_ids(review, registry$ids), error = function(e) e)
    if (inherits(trace_ids, "error")) issues[[length(issues) + 1L]] <- review_finalize_issue_frame("PLAN-TRACE-REVIEW", "ALL", "decision_ids", conditionMessage(trace_ids), "unique stable review decision IDs", "Correct review decision IDs.") else {
      plan <- tryCatch(read_analysis_plan(analysis_plan_candidate_path(study_dir), trace_ids), error = function(e) e)
      if (inherits(plan, "error")) { message <- conditionMessage(plan); issues[[length(issues) + 1L]] <- review_finalize_issue_frame(review_finalize_error_category(message), "ALL", "analysis-plan.candidate.yaml", message, "complete valid traced candidate plan", "Compile the plan again; leave ambiguous values null and resolve the resulting issue."); plan <- NULL }
    }
  }
  if (!inherits(review, "error") && !is.null(plan)) {
    identity_error <- tryCatch({ assert_analysis_study_identity(study_dir, review, plan); NULL }, error = function(e) e)
    if (inherits(identity_error, "error")) issues[[length(issues) + 1L]] <- review_finalize_issue_frame("PLAN-SCHEMA-STUDY-ID", "ALL", "study_id", conditionMessage(identity_error), "directory, review, and analysis plan study IDs match", "Correct the mismatched study_id before finalization.")
    linked_error <- tryCatch({
      registered_paths <- vapply(registry$entries, `[[`, character(1), "relative_path")
      registered_sha <- vapply(registry$entries, `[[`, character(1), "sha256")
      for (analysis in plan$analyses) if (identical(analysis$dataset$binding_mode, "linked")) {
        index <- which(tolower(registered_paths) == tolower(analysis$dataset$relative_path))
        if (length(index) != 1L || !identical(toupper(registered_sha[[index]]), toupper(analysis$dataset$sha256))) stop("PLAN-SCHEMA-DATASET-BINDING-LINKED-EVIDENCE: ", analysis$analysis_id, " does not match one registered entity path and SHA-256.")
      }
      NULL
    }, error = function(e) e)
    if (inherits(linked_error, "error")) issues[[length(issues) + 1L]] <- review_finalize_issue_frame("PLAN-SCHEMA-DATASET-BINDING-LINKED-EVIDENCE", "ALL", "dataset", conditionMessage(linked_error), "linked path/SHA matches registered entity evidence", "Correct the linked dataset binding or manifest evidence.")
  }
  if (!inherits(review, "error")) { unresolved <- tryCatch(review_finalize_existing_issues(review), error = function(e) e); if (inherits(unresolved, "error")) issues[[length(issues) + 1L]] <- review_finalize_issue_frame("PLAN-SCHEMA-ISSUES", "ALL", "Section 7", conditionMessage(unresolved), "valid issues table", "Correct Section 7.") else if (nrow(unresolved)) for (i in seq_len(nrow(unresolved))) issues[[length(issues) + 1L]] <- review_finalize_issue_frame(paste0("PLAN-SCHEMA-REVIEW-", sprintf("%03d", i)), as.character(unresolved$scope[[i]]), "review_issue", as.character(unresolved$question_or_risk[[i]]), "status=resolved", as.character(unresolved$resolution[[i]])) }
  issue_frame <- if (length(issues)) do.call(rbind, issues) else review_finalize_empty_issues()
  if (nrow(issue_frame)) {
    report <- paste(c("Finalization blocked:", paste0("- ", issue_frame$issue_id, ": ", issue_frame$observed)), collapse = "\n")
    if (!allow_unresolved) stop(report)
    unpublished <- function() invisible(list(target_review = normalizePath(target_review, winslash = "/", mustWork = FALSE), analysis_count = 0L, issue_count = nrow(issue_frame), approved = FALSE, issues = issue_frame, report = report, published = FALSE))
    # Only author a canonical blocked review when the review itself parses and its study_id matches
    # the study directory; otherwise publishing would corrupt the formal review identity.
    directory_study_id <- basename(normalizePath(study_dir, winslash = "/", mustWork = TRUE))
    if (inherits(review, "error") || !is.list(review) || is.null(review$lines) || !identical(as.character(review$metadata$study_id), directory_study_id)) return(unpublished())
    existing <- tryCatch(statistical_review_issues(review), error = function(e) NULL)
    generated <- issue_frame[!grepl("^PLAN-SCHEMA-REVIEW-[0-9]+$", as.character(issue_frame$issue_id)), , drop = FALSE]
    lines <- review$lines
    lines <- review_finalize_replace_section(lines, 7L, c("", review_finalize_render_blocked_section(existing, generated), ""))
    lines <- review_finalize_replace_section(lines, 8L, c("", "Finalization blocked; resolve the Section 7 issues before signature. Approval fingerprints are intentionally cleared.", ""))
    cleared <- list(finalization_status = "blocked_pending_resolution", review_status = "pending", reviewed_by = "", reviewed_at_utc = "", analysis_plan_sha256 = "", source_evidence_sha256 = "", review_execution_content_sha256 = "", approval_payload_sha256 = "")
    for (name in names(cleared)) lines <- statistical_review_set_metadata(lines, name, cleared[[name]])
    review_finalize_atomic_write(lines, target_review)
    return(invisible(list(target_review = normalizePath(target_review, winslash = "/", mustWork = TRUE), analysis_count = 0L, issue_count = nrow(issue_frame), approved = FALSE, issues = issue_frame, report = report, published = TRUE)))
  }
  # 校验通过：把 candidate 原子提升为正式 analysis-plan.yaml，并把 review 更新为 approved/published（双文件事务）。
  # 审批时间戳：保留已有的有效 ISO 值（同一决定重新 finalize 不churn 批准身份；完整性由内容 hash 保证），
  # 仅在缺失或被 block 清空后才写入当前时间。
  plan_sha <- attr(plan, "sha256"); source_sha <- source_evidence_sha256(registry)
  existing_at <- as.character(review$metadata$reviewed_at_utc); approved_at <- if (statistical_review_iso_utc(existing_at)) existing_at else format(Sys.time(), tz = "UTC", format = "%Y-%m-%dT%H:%M:%SZ")
  lines <- review$lines; lines <- review_finalize_replace_section(lines, 4L, c("", "<!-- ANALYSIS_PLAN_BEGIN -->", analysis_plan_render_lines(plan), "<!-- ANALYSIS_PLAN_END -->", "")); lines <- review_finalize_replace_section(lines, 7L, c("", review_finalize_issue_table(review_finalize_empty_issues()), ""))
  preview <- read_statistical_review_from_lines(lines); payload <- approval_payload(preview, plan_sha, source_sha); payload_sha <- approval_payload_sha256(payload)
  lines <- review_finalize_replace_section(lines, 8L, c("", paste0("Review execution content SHA-256: `", payload$review_execution_content_sha256, "`"), paste0("Analysis plan SHA-256: `", plan_sha, "`"), paste0("Source evidence SHA-256: `", source_sha, "`"), paste0("Approval payload SHA-256: `", payload_sha, "`")))
  metadata <- list(review_status = "approved", finalization_status = "published", reviewed_by = trimws(reviewer), reviewed_at_utc = approved_at, analysis_plan_file = project_relative_path(analysis_plan_path(study_dir), project_dir), analysis_plan_sha256 = plan_sha, source_evidence_sha256 = source_sha, review_execution_content_sha256 = payload$review_execution_content_sha256, approval_payload_sha256 = payload_sha)
  for (name in names(metadata)) lines <- statistical_review_set_metadata(lines, name, metadata[[name]])
  analysis_approval_recover(study_dir)
  plan_lines <- readLines(analysis_plan_candidate_path(study_dir), warn = FALSE)
  files <- setNames(list(lines, plan_lines), c(target_review, analysis_plan_path(study_dir)))
  analysis_transaction_publish(files, analysis_approval_journal_path(study_dir))
  unlink(analysis_plan_candidate_path(study_dir), force = TRUE)
  invisible(list(target_review = normalizePath(target_review, winslash = "/", mustWork = TRUE), analysis_count = length(plan$analyses), issue_count = 0L, approved = TRUE, issues = review_finalize_empty_issues(), report = "Finalization published the formal analysis plan and approved the review.", published = TRUE))
}

review_finalization_result_path <- function(study_dir) file.path(study_dir, "backup-trace", "statistical-review-finalization-result.yaml")
review_finalization_result_document <- function(result, source_review, target_review) list(result_schema_version = "2.1", generated_at_utc = format(Sys.time(), tz = "UTC", format = "%Y-%m-%dT%H:%M:%SZ"), source_review = normalizePath(source_review, winslash = "/", mustWork = FALSE), target_review = normalizePath(target_review, winslash = "/", mustWork = FALSE), published = isTRUE(result$published), approved = isTRUE(result$approved), analysis_count = as.integer(if (is.null(result$analysis_count)) 0L else result$analysis_count), issue_count = as.integer(result$issue_count), report = as.character(result$report), issues = if (nrow(result$issues)) lapply(seq_len(nrow(result$issues)), function(i) as.list(result$issues[i, , drop = FALSE])) else list())
review_finalization_write_result <- function(path, result, source_review, target_review) { dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE); yaml::write_yaml(review_finalization_result_document(result, source_review, target_review), path); invisible(path) }
review_finalization_self_check <- function() {
  standard_validate_execution_context(list(
    profile_version = standard_mmrm_profile_version(),
    data_availability = "none",
    data_classification = "none",
    intended_use = "code_generation",
    sas_execution_profile = "sas-9.4m5-self-contained/v1"
  ), "review_finalization.self_check.execution_context")
  invisible(TRUE)
}
