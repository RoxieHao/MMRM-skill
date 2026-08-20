analysis_contract_path <- function(study_dir) file.path(study_dir, "statistician-review", "standard-mmrm-contract.yaml")
analysis_approval_journal_path <- function(study_dir) file.path(study_dir, "backup-trace", "analysis-approval-transaction.yaml")
analysis_approval_transaction_dir <- function(study_dir) file.path(study_dir, "backup-trace", "analysis-approval-transaction-files")
analysis_approval_new_transaction_id <- function() paste0("txn-", format(Sys.time(), tz = "UTC", format = "%Y%m%d%H%M%S"), "-", Sys.getpid(), "-", paste(format(as.hexmode(sample(0:255, 8L, replace = TRUE)), width = 2L), collapse = ""))
analysis_approval_comparable <- function(x) if (.Platform$OS.type == "windows") tolower(x) else x
# Canonicalize a path by resolving reparse points (junctions/symlinks) on its parent and
# rejecting '.'/'..'/empty segments. Fail closed when the parent directory does not exist.
analysis_approval_realpath <- function(path, context) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) stop("PLAN-HASH-TRANSACTION: ", context, " must be a nonempty path.")
  norm <- gsub("\\\\", "/", path)
  if (grepl("(^|/)\\.\\.(/|$)", norm) || grepl("(^|/)\\.(/|$)", norm) || grepl("//", norm)) stop("PLAN-HASH-TRANSACTION: ", context, " must not contain '.', '..', or empty path segments.")
  base <- basename(norm); parent <- dirname(norm)
  if (!nzchar(base) || base %in% c(".", "..")) stop("PLAN-HASH-TRANSACTION: ", context, " has an invalid final segment.")
  if (!dir.exists(parent)) stop("PLAN-HASH-TRANSACTION: ", context, " parent directory does not exist: ", parent)
  file.path(normalizePath(parent, winslash = "/", mustWork = TRUE), base)
}
analysis_approval_within_study <- function(real_path, study_root) startsWith(analysis_approval_comparable(real_path), paste0(analysis_approval_comparable(study_root), "/"))
# The only paths a recovered transaction may touch: the formal review/contract, generated
# R/SAS/collector programs, and removed-analysis output roots inside the current study.
analysis_approval_target_allowed <- function(real_target, study_root) {
  if (!analysis_approval_within_study(real_target, study_root)) return(FALSE)
  rel <- substring(real_target, nchar(study_root) + 2L)
  rel %in% c("statistician-review/statistical-review.md", "statistician-review/standard-mmrm-contract.yaml") ||
    grepl("^analysis/r/[^/]+\\.R$", rel) ||
    grepl("^analysis/sas/[^/]+_template\\.sas$", rel) ||
    grepl("^output/analyses/[^/]+/.+$", rel)
}
analysis_approval_require_txn_file <- function(path, txn_dir_real, transaction_id, context) {
  real <- analysis_approval_realpath(path, context)
  if (!identical(analysis_approval_comparable(dirname(real)), analysis_approval_comparable(txn_dir_real))) stop("PLAN-HASH-TRANSACTION: ", context, " must reside in the study transaction directory.")
  if (!startsWith(basename(real), paste0(transaction_id, "."))) stop("PLAN-HASH-TRANSACTION: ", context, " must be transaction-specific.")
  real
}
# Closed-schema validation for a transaction journal. Rebuilds the allowed target set from
# the current study and confirms every stage/backup is a transaction-specific sibling in the
# study transaction directory. Any deviation fails closed before any filesystem mutation.
analysis_approval_validate_journal <- function(state, study_dir) {
  if (!is.list(state) || is.null(names(state)) || anyDuplicated(names(state)) || !setequal(names(state), c("schema_version", "phase", "entries", "updated_at_utc", "transaction_id"))) stop("PLAN-HASH-TRANSACTION: transaction journal schema is not closed.")
  if (!identical(as.character(state$schema_version), "1.1")) stop("PLAN-HASH-TRANSACTION: unsupported transaction journal schema_version.")
  if (!is.character(state$phase) || length(state$phase) != 1L || !state$phase %in% c("staging", "committing", "rolling_back", "completed", "rolled_back")) stop("PLAN-HASH-TRANSACTION: invalid transaction phase.")
  if (!is.character(state$transaction_id) || length(state$transaction_id) != 1L || !grepl("^txn-[A-Za-z0-9._-]+$", state$transaction_id)) stop("PLAN-HASH-TRANSACTION: invalid transaction id.")
  if (!is.list(state$entries) || (length(state$entries) && !is.null(names(state$entries)))) stop("PLAN-HASH-TRANSACTION: entries must be an unnamed sequence.")
  study_root <- normalizePath(study_dir, winslash = "/", mustWork = TRUE)
  txn_dir_real <- analysis_approval_realpath(analysis_approval_transaction_dir(study_dir), "transaction directory")
  seen <- character()
  for (i in seq_along(state$entries)) {
    entry <- state$entries[[i]]
    if (!is.list(entry) || is.null(names(entry)) || anyDuplicated(names(entry)) || !setequal(names(entry), c("target", "stage", "backup", "existed", "delete"))) stop("PLAN-HASH-TRANSACTION: entry schema is not closed at position ", i, ".")
    if (!is.logical(entry$existed) || length(entry$existed) != 1L || is.na(entry$existed)) stop("PLAN-HASH-TRANSACTION: entry.existed invalid at position ", i, ".")
    if (!is.logical(entry$delete) || length(entry$delete) != 1L || is.na(entry$delete)) stop("PLAN-HASH-TRANSACTION: entry.delete invalid at position ", i, ".")
    target_real <- analysis_approval_realpath(entry$target, paste0("entry[", i, "].target"))
    if (!analysis_approval_target_allowed(target_real, study_root)) stop("PLAN-HASH-TRANSACTION: entry target is outside the approved study target set: ", entry$target)
    seen <- c(seen, target_real)
    stage <- as.character(entry$stage)
    if (isTRUE(entry$delete)) {
      if (nzchar(stage)) stop("PLAN-HASH-TRANSACTION: delete entry must not carry a stage file at position ", i, ".")
    } else {
      if (!nzchar(stage)) stop("PLAN-HASH-TRANSACTION: publish entry requires a stage file at position ", i, ".")
      seen <- c(seen, analysis_approval_require_txn_file(stage, txn_dir_real, state$transaction_id, paste0("entry[", i, "].stage")))
    }
    backup <- as.character(entry$backup)
    if (isTRUE(entry$existed)) {
      if (!nzchar(backup)) stop("PLAN-HASH-TRANSACTION: existed entry requires a backup file at position ", i, ".")
      seen <- c(seen, analysis_approval_require_txn_file(backup, txn_dir_real, state$transaction_id, paste0("entry[", i, "].backup")))
    } else if (nzchar(backup)) {
      stop("PLAN-HASH-TRANSACTION: non-existed entry must not carry a backup file at position ", i, ".")
    }
  }
  if (anyDuplicated(analysis_approval_comparable(seen))) stop("PLAN-HASH-TRANSACTION: transaction paths collide (case-insensitive).")
  invisible(TRUE)
}
analysis_approval_write_journal <- function(path, phase, entries = list(), transaction_id) {
  if (missing(transaction_id) || !is.character(transaction_id) || length(transaction_id) != 1L || !grepl("^txn-[A-Za-z0-9._-]+$", transaction_id)) stop("PLAN-HASH-TRANSACTION: a valid transaction id is required to write the journal.")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(paste0(".", basename(path), "."), tmpdir = dirname(path))
  on.exit(unlink(temporary, force = TRUE), add = TRUE)
  yaml::write_yaml(list(schema_version = "1.1", phase = phase, transaction_id = transaction_id, entries = entries, updated_at_utc = format(Sys.time(), tz = "UTC", format = "%Y-%m-%dT%H:%M:%SZ")), temporary)
  if (!file.rename(temporary, path) && !file.copy(temporary, path, overwrite = TRUE, copy.mode = TRUE, copy.date = TRUE)) stop("PLAN-HASH-TRANSACTION: unable to publish transaction journal: ", path)
  invisible(path)
}
analysis_approval_cleanup_entries <- function(entries) {
  errors <- character()
  for (entry in entries) {
    for (path in c(as.character(entry$stage), as.character(entry$backup))) if (nzchar(path) && file.exists(path) && unlink(path, force = TRUE) != 0L) errors <- c(errors, path)
  }
  if (length(errors)) stop("PLAN-HASH-TRANSACTION: cleanup incomplete: ", paste(unique(errors), collapse = ", "))
  invisible(TRUE)
}
analysis_approval_rollback_entries <- function(entries) {
  missing <- vapply(entries, function(entry) isTRUE(entry$existed) && (!nzchar(as.character(entry$backup)) || !file.exists(as.character(entry$backup))), logical(1))
  if (any(missing)) stop("PLAN-HASH-TRANSACTION: required rollback backup is missing; targets were not changed: ", paste(vapply(entries[missing], function(entry) as.character(entry$target), character(1)), collapse = ", "))
  errors <- character()
  for (entry in rev(entries)) {
    target <- as.character(entry$target); backup <- as.character(entry$backup); existed <- isTRUE(entry$existed)
    if (existed) {
      if (!file.copy(backup, target, overwrite = TRUE, copy.mode = TRUE, copy.date = TRUE)) errors <- c(errors, target)
    } else if (file.exists(target) && unlink(target, force = TRUE) != 0L) errors <- c(errors, target)
  }
  if (length(errors)) stop("PLAN-HASH-TRANSACTION: rollback incomplete: ", paste(unique(errors), collapse = ", "))
  invisible(TRUE)
}
analysis_approval_recover <- function(study_dir) {
  journal <- analysis_approval_journal_path(study_dir); if (!file.exists(journal)) return(invisible(FALSE))
  state <- yaml::read_yaml(journal, eval.expr = FALSE)
  analysis_approval_validate_journal(state, study_dir)
  transaction_id <- as.character(state$transaction_id)
  if (state$phase %in% c("staging", "committing", "rolling_back")) {
    analysis_approval_write_journal(journal, "rolling_back", state$entries, transaction_id)
    analysis_approval_rollback_entries(state$entries)
    analysis_approval_write_journal(journal, "rolled_back", state$entries, transaction_id)
  }
  analysis_approval_cleanup_entries(state$entries)
  if (unlink(journal, force = TRUE) != 0L) stop("PLAN-HASH-TRANSACTION: unable to remove completed transaction journal: ", journal)
  invisible(TRUE)
}

assert_approved_analysis <- function(study_dir, project_dir, expected_analysis_id = NULL, pinned_approval_payload_sha256 = NULL, pinned_contract_sha256 = NULL) {
  reject_legacy_analysis_artifacts(study_dir)
  review <- read_statistical_review(file.path(study_dir, "statistician-review", "statistical-review.md")); metadata <- review$metadata
  required <- c("review_schema_version", "study_id", "review_status", "reviewed_by", "reviewed_at_utc", "finalization_status", "analysis_plan_file", "analysis_plan_sha256", "source_evidence_sha256", "review_execution_content_sha256", "approval_payload_sha256")
  if (any(!required %in% names(metadata)) || !identical(as.character(metadata$review_schema_version), "2.0") || !identical(as.character(metadata$review_status), "approved") || !identical(as.character(metadata$finalization_status), "ready_for_final_signature") || !nzchar(as.character(metadata$reviewed_by)) || !statistical_review_iso_utc(metadata$reviewed_at_utc)) stop("PLAN-HASH-APPROVAL: review is not validly approved.")
  registry <- source_evidence_registry(project_dir, study_dir); source_sha <- source_evidence_sha256(registry)
  plan <- read_analysis_plan(analysis_plan_path(study_dir), statistical_review_trace_ids(review, registry$ids)); plan_sha <- attr(plan, "sha256")
  assert_analysis_study_identity(study_dir, review, plan)
  payload <- approval_payload(review, plan_sha, source_sha); payload_sha <- approval_payload_sha256(payload)
  expected <- list(analysis_plan_sha256 = plan_sha, source_evidence_sha256 = source_sha, review_execution_content_sha256 = payload$review_execution_content_sha256, approval_payload_sha256 = payload_sha)
  mismatch <- names(expected)[vapply(names(expected), function(name) !identical(toupper(as.character(metadata[[name]])), toupper(expected[[name]])), logical(1))]
  if (length(mismatch)) stop("PLAN-HASH-MISMATCH: approved inputs changed: ", paste(mismatch, collapse = ", "))
  if (!is.null(pinned_approval_payload_sha256) && !identical(toupper(payload_sha), toupper(pinned_approval_payload_sha256))) stop("PLAN-HASH-STALE-WRAPPER: approved identity changed; rerun the sole approval-and-generation workflow.")
  contract <- read_standard_mmrm_contract(analysis_contract_path(study_dir)); contract_sha <- attr(contract, "sha256"); approval <- contract$approval
  assert_analysis_study_identity(study_dir, review, plan, contract)
  identity_ok <- identical(toupper(approval$review_sha256), toupper(review$sha256)) && identical(toupper(approval$analysis_plan_sha256), toupper(plan_sha)) && identical(toupper(approval$approval_payload_sha256), toupper(payload_sha)) && identical(toupper(approval$source_evidence_sha256), toupper(source_sha)) && identical(approval$reviewed_by, as.character(metadata$reviewed_by)) && identical(approval$approved_at_utc, as.character(metadata$reviewed_at_utc))
  if (!identity_ok) stop("PLAN-HASH-CONTRACT: contract approval identity is stale or mismatched.")
  assert_plan_contract_parity(plan, contract)
  if (!is.null(pinned_contract_sha256) && !identical(toupper(contract_sha), toupper(pinned_contract_sha256))) stop("PLAN-HASH-STALE-WRAPPER: approved contract changed; rerun the sole approval-and-generation workflow.")
  if (!is.null(expected_analysis_id)) standard_contract_get_analysis(contract, expected_analysis_id)
  list(review = review, plan = plan, payload = payload, approval_payload_sha256 = payload_sha, contract = contract, contract_sha256 = contract_sha)
}
assert_analysis_execution_allowed <- function(chain) {
  context <- chain$plan$execution_context
  if (context$data_availability == "none" || context$data_classification %in% c("none", "unknown")) stop("Approved context permits code generation only; model execution is blocked.")
  invisible(TRUE)
}
analysis_render_template <- function(template, replacements) { result <- template; for (name in names(replacements)) result <- gsub(paste0("<", name, ">"), replacements[[name]], result, fixed = TRUE); if (grepl("<[A-Z0-9_]+>", result)) stop("Generated program retains an unresolved placeholder."); result }
analysis_validate_adapter_pins <- function(contract, project_dir) {
  for (analysis in contract$analyses) if (!is.null(analysis$adapter_file)) { path <- normalize_project_relative_path(analysis$adapter_file, project_dir, "adapter_file"); if (!file.exists(path)) stop("Approved adapter does not exist: ", analysis$adapter_file); actual <- toupper(digest::digest(file = path, algo = "sha256")); if (!identical(actual, toupper(analysis$adapter_sha256))) stop("Approved adapter SHA-256 mismatch: ", analysis$adapter_file) }
  invisible(TRUE)
}
analysis_generated_targets <- function(study_dir, contract) {
  analysis_ids <- vapply(contract$analyses, function(x) as.character(x$analysis_id), character(1))
  c(file.path(study_dir, "analysis", "r", paste0(analysis_ids, ".R")), file.path(study_dir, "analysis", "sas", paste0(analysis_ids, "_template.sas")), file.path(study_dir, "analysis", "r", "run_all_mmrm.R"))
}
analysis_obsolete_generated_targets <- function(study_dir, previous_contract, current_files) setdiff(analysis_generated_targets(study_dir, previous_contract), names(current_files))
analysis_removed_analysis_ids <- function(previous_contract, current_contract) {
  previous_ids <- vapply(previous_contract$analyses, function(x) as.character(x$analysis_id), character(1))
  current_ids <- vapply(current_contract$analyses, function(x) as.character(x$analysis_id), character(1))
  setdiff(previous_ids, current_ids)
}
analysis_removed_output_roots <- function(study_dir, removed_ids) file.path(study_dir, "output", "analyses", gsub("[^A-Za-z0-9_-]+", "_", removed_ids))
analysis_removed_output_files <- function(study_dir, removed_ids) {
  roots <- analysis_removed_output_roots(study_dir, removed_ids)
  files <- character()
  for (root in roots) if (dir.exists(root)) files <- c(files, list.files(root, recursive = TRUE, all.files = TRUE, full.names = TRUE, no.. = TRUE, include.dirs = FALSE))
  unique(files)
}
analysis_render_generated <- function(study_dir, project_dir, contract, payload_sha, contract_sha) {
  skill <- file.path(project_dir, ".codex", "study-mmrm-analysis"); wrapper <- paste(readLines(file.path(skill, "R", "templates", "study_mmrm_template.R"), warn = FALSE), collapse = "\n"); collector <- paste(readLines(file.path(skill, "R", "templates", "run_all_mmrm_template.R"), warn = FALSE), collapse = "\n"); files <- list()
  for (analysis in contract$analyses) { replacements <- c(ANALYSIS_ID = analysis$analysis_id, APPROVAL_PAYLOAD_SHA256 = payload_sha, CONTRACT_SHA256 = contract_sha); files[[file.path(study_dir, "analysis", "r", paste0(analysis$analysis_id, ".R"))]] <- analysis_render_template(wrapper, replacements); files[[file.path(study_dir, "analysis", "sas", paste0(analysis$analysis_id, "_template.sas"))]] <- render_standard_sas_template(contract, analysis, payload_sha, contract_sha) }
  files[[file.path(study_dir, "analysis", "r", "run_all_mmrm.R")]] <- analysis_render_template(collector, c(APPROVAL_PAYLOAD_SHA256 = payload_sha, CONTRACT_SHA256 = contract_sha)); files
}
analysis_transaction_publish <- function(files, journal, fail_after = Inf, delete_targets = character()) {
  if (file.exists(journal)) stop("PLAN-HASH-TRANSACTION: unresolved transaction journal must be recovered before publication: ", journal)
  targets <- names(files); delete_targets <- unique(as.character(delete_targets)); if (length(intersect(targets, delete_targets))) stop("PLAN-HASH-TRANSACTION: a target cannot be both published and deleted.")
  study_dir <- dirname(dirname(journal)); transaction_id <- analysis_approval_new_transaction_id()
  txn_dir <- analysis_approval_transaction_dir(study_dir); dir.create(txn_dir, recursive = TRUE, showWarnings = FALSE)
  operations <- c(lapply(targets, function(target) list(target = target, delete = FALSE)), lapply(delete_targets, function(target) list(target = target, delete = TRUE)))
  invisible(lapply(unique(dirname(c(targets, delete_targets))), dir.create, recursive = TRUE, showWarnings = FALSE)); entries <- list()
  prepare_error <- tryCatch({
    for (operation in operations) {
      target <- operation$target; deleting <- isTRUE(operation$delete); existed <- file.exists(target)
      stage <- if (deleting) "" else tempfile(paste0(transaction_id, ".", basename(target), ".stage-"), tmpdir = txn_dir)
      backup <- if (existed) tempfile(paste0(transaction_id, ".", basename(target), ".backup-"), tmpdir = txn_dir) else ""
      entries[[length(entries) + 1L]] <- list(target = target, stage = stage, backup = backup, existed = existed, delete = deleting)
      if (!deleting) writeLines(files[[target]], stage, useBytes = TRUE)
      if (existed && !file.copy(target, backup, overwrite = FALSE, copy.mode = TRUE, copy.date = TRUE)) stop("Unable to stage backup: ", target)
    }
    NULL
  }, error = function(e) e)
  if (inherits(prepare_error, "error")) { analysis_approval_cleanup_entries(entries); stop(conditionMessage(prepare_error), call. = FALSE) }
  analysis_approval_write_journal(journal, "staging", entries, transaction_id); analysis_approval_write_journal(journal, "committing", entries, transaction_id)
  commit_error <- tryCatch({ for (i in seq_along(entries)) { entry <- entries[[i]]; if (file.exists(entry$target) && unlink(entry$target, force = TRUE) != 0L) stop("Unable to replace target: ", entry$target); if (i > fail_after) stop("Injected target publication failure: ", entry$target); if (!isTRUE(entry$delete) && !file.rename(entry$stage, entry$target)) stop("Real target replacement failure: ", entry$target) }; NULL }, error = function(e) e)
  if (inherits(commit_error, "error")) {
    analysis_approval_write_journal(journal, "rolling_back", entries, transaction_id)
    analysis_approval_rollback_entries(entries)
    analysis_approval_write_journal(journal, "rolled_back", entries, transaction_id)
    analysis_approval_cleanup_entries(entries)
    unlink(journal, force = TRUE)
    stop(conditionMessage(commit_error), call. = FALSE)
  }
  analysis_approval_write_journal(journal, "completed", entries, transaction_id)
  analysis_approval_cleanup_entries(entries)
  if (unlink(journal, force = TRUE) != 0L) stop("PLAN-HASH-TRANSACTION: unable to remove completed transaction journal: ", journal)
  invisible(targets)
}
approve_and_generate_analysis <- function(study_dir, project_dir, reviewer, fail_after = Inf) {
  if (!nzchar(trimws(reviewer))) stop("reviewer must be nonempty."); analysis_approval_recover(study_dir); reject_legacy_analysis_artifacts(study_dir)
  review_path <- file.path(study_dir, "statistician-review", "statistical-review.md"); review <- read_statistical_review(review_path)
  if (!identical(as.character(review$metadata$finalization_status), "ready_for_final_signature")) stop("Review is not ready for final signature.")
  issues <- statistical_review_issues(review); if (nrow(issues) && any(trimws(as.character(issues$status)) != "resolved")) stop("Review has unresolved issues.")
  registry <- source_evidence_registry(project_dir, study_dir); plan <- read_analysis_plan(analysis_plan_path(study_dir), statistical_review_trace_ids(review, registry$ids)); assert_analysis_study_identity(study_dir, review, plan); plan_sha <- attr(plan, "sha256"); source_sha <- source_evidence_sha256(registry); payload <- approval_payload(review, plan_sha, source_sha); payload_sha <- approval_payload_sha256(payload)
  expected <- list(analysis_plan_sha256 = plan_sha, source_evidence_sha256 = source_sha, review_execution_content_sha256 = payload$review_execution_content_sha256, approval_payload_sha256 = payload_sha)
  for (name in names(expected)) if (!identical(toupper(as.character(review$metadata[[name]])), toupper(expected[[name]]))) stop("PLAN-HASH-FINALIZATION: review must be finalized again before approval: ", name)
  approved_at <- format(Sys.time(), tz = "UTC", format = "%Y-%m-%dT%H:%M:%SZ"); approved_lines <- statistical_review_set_metadata(review$lines, "review_status", "approved"); approved_lines <- statistical_review_set_metadata(approved_lines, "reviewed_by", trimws(reviewer)); approved_lines <- statistical_review_set_metadata(approved_lines, "reviewed_at_utc", approved_at)
  review_temp <- tempfile("approved-review-", fileext = ".md"); contract_temp <- tempfile("contract-", fileext = ".yaml"); on.exit(unlink(c(review_temp, contract_temp), force = TRUE), add = TRUE); writeLines(approved_lines, review_temp, useBytes = TRUE); review_sha <- file_sha256(review_temp)
  approval <- list(review_file = project_relative_path(review_path, project_dir), review_sha256 = review_sha, analysis_plan_file = project_relative_path(analysis_plan_path(study_dir), project_dir), analysis_plan_sha256 = plan_sha, approval_payload_sha256 = payload_sha, source_evidence_sha256 = source_sha, reviewed_by = trimws(reviewer), approved_at_utc = approved_at)
  contract <- compile_analysis_plan_contract(plan, approval); analysis_validate_adapter_pins(contract, project_dir); write_standard_mmrm_contract(contract, contract_temp); staged_contract <- read_standard_mmrm_contract(contract_temp); assert_analysis_study_identity(study_dir, review, plan, staged_contract); assert_plan_contract_parity(plan, staged_contract); contract_sha <- attr(staged_contract, "sha256")
  rendered <- analysis_render_generated(study_dir, project_dir, staged_contract, payload_sha, contract_sha); files <- c(setNames(list(approved_lines), review_path), setNames(list(readLines(contract_temp, warn = FALSE)), analysis_contract_path(study_dir)), rendered)
  obsolete <- character(); removed_ids <- character(); if (file.exists(analysis_contract_path(study_dir))) { previous_contract <- read_standard_mmrm_contract(analysis_contract_path(study_dir)); obsolete <- analysis_obsolete_generated_targets(study_dir, previous_contract, rendered); removed_ids <- analysis_removed_analysis_ids(previous_contract, staged_contract) }
  removed_outputs <- analysis_removed_output_files(study_dir, removed_ids)
  analysis_transaction_publish(files, analysis_approval_journal_path(study_dir), fail_after = fail_after, delete_targets = c(obsolete, removed_outputs))
  # After a successful commit the removed-analysis output files are gone; drop the now-empty
  # output roots so they cannot be mistaken for current evidence by humans or glob consumers.
  for (root in analysis_removed_output_roots(study_dir, removed_ids)) if (dir.exists(root)) unlink(root, recursive = TRUE, force = TRUE)
  invisible(assert_approved_analysis(study_dir, project_dir, pinned_approval_payload_sha256 = payload_sha, pinned_contract_sha256 = contract_sha))
}
