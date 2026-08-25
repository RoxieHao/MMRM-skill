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
# The only paths a recovered transaction may touch: the formal review/contract and the
# generator-owned R/SAS/collector programs inside the current study. Runtime evidence
# (raw/final/diagnostic/run-record/manifest under output/) is deliberately NOT reachable:
# per design 15.7 只有单独、显式、具有保留策略的归档流程才能处理运行产物。
analysis_approval_target_allowed <- function(real_target, study_root) {
  if (!analysis_approval_within_study(real_target, study_root)) return(FALSE)
  rel <- substring(real_target, nchar(study_root) + 2L)
  rel %in% c("statistician-review/statistical-review.md", "statistician-review/analysis-plan.yaml", "statistician-review/standard-mmrm-contract.yaml") ||
    analysis_approval_generator_owned_relative(rel)
}
# generator 拥有的 program 文件：analysis/r/*.R 与 analysis/sas/*.sas（含历史 *_template.sas）。
analysis_approval_generator_owned_relative <- function(rel) grepl("^analysis/r/[^/]+\\.R$", rel) || grepl("^analysis/sas/[^/]+\\.sas$", rel)
analysis_assert_generator_owned_programs <- function(paths, study_dir, context = "delete target") {
  if (!length(paths)) return(invisible(TRUE))
  study_root <- normalizePath(study_dir, winslash = "/", mustWork = TRUE)
  for (path in unique(as.character(paths))) {
    real <- analysis_approval_realpath(path, context)
    rel <- if (analysis_approval_within_study(real, study_root)) substring(real, nchar(study_root) + 2L) else ""
    if (!nzchar(rel) || !analysis_approval_generator_owned_relative(rel)) stop("PLAN-HASH-TRANSACTION: the approval publisher may only delete generator-owned programs, not runtime evidence: ", path)
  }
  invisible(TRUE)
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
  review <- read_statistical_review(file.path(study_dir, "statistician-review", "statistical-review.md")); metadata <- review$metadata
  required <- c("review_schema_version", "study_id", "review_status", "reviewed_by", "reviewed_at_utc", "finalization_status", "analysis_plan_file", "analysis_plan_sha256", "source_evidence_sha256", "review_execution_content_sha256", "approval_payload_sha256")
  if (any(!required %in% names(metadata)) || !identical(as.character(metadata$review_schema_version), "2.0") || !identical(as.character(metadata$review_status), "approved") || !identical(as.character(metadata$finalization_status), "published") || !nzchar(as.character(metadata$reviewed_by)) || !statistical_review_iso_utc(metadata$reviewed_at_utc)) stop("PLAN-HASH-APPROVAL: review is not validly approved.")
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
assert_analysis_execution_allowed <- function(chain, analysis = NULL, analysis_id = NULL) {
  context <- chain$plan$execution_context
  if (is.character(analysis) && length(analysis) == 1L && is.null(analysis_id)) { analysis_id <- analysis; analysis <- NULL }
  if (is.null(analysis)) {
    if (!is.null(analysis_id)) analysis <- standard_contract_get_analysis(chain$contract, analysis_id)
    else if (length(chain$contract$analyses) == 1L) analysis <- chain$contract$analyses[[1L]]
    else stop("PLAN-SCHEMA-DATASET-BINDING-EXECUTION: analysis or analysis_id is required for a multi-analysis contract.")
  } else {
    if (!is.list(analysis) || is.null(analysis$analysis_id)) stop("PLAN-SCHEMA-DATASET-BINDING-EXECUTION: analysis must identify an approved contract analysis.")
    approved <- standard_contract_get_analysis(chain$contract, as.character(analysis$analysis_id))
    if (!identical(canonical_bytes(analysis), canonical_bytes(approved))) stop("PLAN-SCHEMA-DATASET-BINDING-EXECUTION: supplied analysis differs from the approved contract analysis.")
    analysis <- approved
  }
  if (is.null(analysis$dataset$binding_mode)) stop("PLAN-SCHEMA-DATASET-BINDING-EXECUTION: validated analysis binding is required.")
  if (identical(analysis$dataset$binding_mode, "planned")) stop("PLAN-SCHEMA-DATASET-BINDING-EXECUTION: planned analysis is code-generation-only and cannot execute.")
  if (context$data_availability == "none" || context$data_classification %in% c("none", "unknown")) stop("PLAN-SCHEMA-CONTEXT-EXECUTION: approved study classification permits code generation only; model execution is blocked.")
  invisible(TRUE)
}
analysis_render_template <- function(template, replacements) { result <- template; for (name in names(replacements)) result <- gsub(paste0("<", name, ">"), replacements[[name]], result, fixed = TRUE); if (grepl("<[A-Z0-9_]+>", result)) stop("Generated program retains an unresolved placeholder."); result }
analysis_validate_adapter_pins <- function(contract, project_dir) {
  for (analysis in contract$analyses) if (!is.null(analysis$adapter_file)) { path <- normalize_project_relative_path(analysis$adapter_file, project_dir, "adapter_file"); if (!file.exists(path)) stop("Approved adapter does not exist: ", analysis$adapter_file); actual <- toupper(digest::digest(file = path, algo = "sha256")); if (!identical(actual, toupper(analysis$adapter_sha256))) stop("Approved adapter SHA-256 mismatch: ", analysis$adapter_file) }
  invisible(TRUE)
}
analysis_generated_collector_target <- function(study_dir) file.path(study_dir, "analysis", "r", "run_all_mmrm.R")
# 8.2 current target 集合：每个 analysis 一个自包含 R 程序和一个自包含 SAS 程序，
# 外加每次 generation 都必须产出的正式便利 collector。<analysis_id>_template.sas 不再是 target。
analysis_generated_targets <- function(study_dir, contract) {
  analysis_ids <- vapply(contract$analyses, function(x) as.character(x$analysis_id), character(1))
  c(vapply(analysis_ids, function(id) analysis_generation_program_path(study_dir, id, "r"), character(1), USE.NAMES = FALSE),
    vapply(analysis_ids, function(id) analysis_generation_program_path(study_dir, id, "sas"), character(1), USE.NAMES = FALSE),
    analysis_generated_collector_target(study_dir))
}
# 停用的旧正式 renderer 产物：任何 <analysis_id>_template.sas。
analysis_legacy_template_targets <- function(study_dir, contract = NULL) {
  directory <- file.path(study_dir, "analysis", "sas")
  on_disk <- if (dir.exists(directory)) list.files(directory, pattern = "_template[.]sas$", full.names = TRUE) else character()
  declared <- if (is.null(contract)) character() else vapply(contract$analyses, function(x) file.path(directory, paste0(standard_contract_safe_identity(x$analysis_id), "_template.sas")), character(1), USE.NAMES = FALSE)
  unique(gsub("\\\\", "/", c(on_disk, declared)))
}
# obsolete delete-set 只含 generator 拥有的 program：已移除 analysis 的 .R/.sas/_template.sas，
# 以及全部历史 _template.sas。当前 analysis 的同名旧 wrapper 由 write-set 原子替换，不进 delete-set。
# 运行证据（raw/final/diagnostic/run-record/manifest）永不进入该集合。
analysis_obsolete_generated_targets <- function(study_dir, previous_contract, current_files) {
  previous <- c(analysis_generated_targets(study_dir, previous_contract), analysis_legacy_template_targets(study_dir, previous_contract))
  obsolete <- setdiff(unique(gsub("\\\\", "/", previous)), gsub("\\\\", "/", names(current_files)))
  obsolete <- obsolete[file.exists(obsolete)]
  analysis_assert_generator_owned_programs(obsolete, study_dir, "obsolete program")
  obsolete
}
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
analysis_program_lines <- function(text) strsplit(as.character(text), "\n", fixed = TRUE)[[1L]]
# 8.3 完整 write-set：先在内存里把所有 analysis 的 R/SAS 程序渲染并校验通过、再做 coverage，
# 才把文本交给既有 transaction publisher。旧正式 renderer（render_standard_sas_template）
# 在审批链中已停用，审批链不再发布任何 template。
analysis_render_generated <- function(study_dir, project_dir, contract, payload_sha, contract_sha, test_only_drop_targets = character()) {
  texts <- analysis_generate_program_texts(study_dir, project_dir, contract, payload_sha, contract_sha, test_only_drop_targets = test_only_drop_targets)
  files <- lapply(texts, analysis_program_lines)
  collector_template <- paste(readLines(file.path(project_dir, ".codex", "study-mmrm-analysis", "R", "templates", "run_all_mmrm_template.R"), warn = FALSE), collapse = "\n")
  files[[analysis_generated_collector_target(study_dir)]] <- analysis_program_lines(analysis_render_template(collector_template, c(APPROVAL_PAYLOAD_SHA256 = payload_sha, CONTRACT_SHA256 = contract_sha)))
  files
}
analysis_transaction_publish <- function(files, journal, fail_after = Inf, delete_targets = character()) {
  if (file.exists(journal)) stop("PLAN-HASH-TRANSACTION: unresolved transaction journal must be recovered before publication: ", journal)
  targets <- names(files); delete_targets <- unique(as.character(delete_targets)); if (length(intersect(targets, delete_targets))) stop("PLAN-HASH-TRANSACTION: a target cannot be both published and deleted.")
  study_dir <- dirname(dirname(journal)); transaction_id <- analysis_approval_new_transaction_id()
  # 停用旧正式 renderer 的最后一道闸门：审批链不得再发布 SAS template。
  if (any(grepl("_template[.]sas$", basename(targets)))) stop("PLAN-HASH-TRANSACTION: publishing <analysis_id>_template.sas is disabled; the approval chain publishes self-contained .sas programs only.")
  # delete-set 只能是 generator 拥有的 program；运行证据（raw/final/diagnostic/run-record/manifest）永不删除。
  analysis_assert_generator_owned_programs(delete_targets, study_dir, "delete target")
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
# Phase 7: 只消费已由 R finalization 发布的 approved/published review + 正式 plan；不再修改 review status，
# 也不重签统计决定。reviewer 仅作为执行授权/audit actor，不覆盖 review 的 reviewed_by。
approve_and_generate_analysis <- function(study_dir, project_dir, reviewer = NULL, fail_after = Inf) {
  analysis_approval_recover(study_dir)
  review_path <- file.path(study_dir, "statistician-review", "statistical-review.md"); review <- read_statistical_review(review_path)
  if (!identical(as.character(review$metadata$review_status), "approved") || !identical(as.character(review$metadata$finalization_status), "published")) stop("Review is not approved/published; run Compile Analysis Plan and finalization before generation.")
  issues <- statistical_review_issues(review); if (nrow(issues) && any(trimws(as.character(issues$status)) != "resolved")) stop("Review has unresolved issues.")
  registry <- source_evidence_registry(project_dir, study_dir); plan <- read_analysis_plan(analysis_plan_path(study_dir), statistical_review_trace_ids(review, registry$ids)); assert_analysis_study_identity(study_dir, review, plan); plan_sha <- attr(plan, "sha256"); source_sha <- source_evidence_sha256(registry); payload <- approval_payload(review, plan_sha, source_sha); payload_sha <- approval_payload_sha256(payload)
  expected <- list(analysis_plan_sha256 = plan_sha, source_evidence_sha256 = source_sha, review_execution_content_sha256 = payload$review_execution_content_sha256, approval_payload_sha256 = payload_sha)
  for (name in names(expected)) if (!identical(toupper(as.character(review$metadata[[name]])), toupper(expected[[name]]))) stop("PLAN-HASH-FINALIZATION: approved review is stale; recompile and finalize before generation: ", name)
  contract_temp <- tempfile("contract-", fileext = ".yaml"); on.exit(unlink(contract_temp, force = TRUE), add = TRUE)
  approval <- list(review_file = project_relative_path(review_path, project_dir), review_sha256 = review$sha256, analysis_plan_file = project_relative_path(analysis_plan_path(study_dir), project_dir), analysis_plan_sha256 = plan_sha, approval_payload_sha256 = payload_sha, source_evidence_sha256 = source_sha, reviewed_by = as.character(review$metadata$reviewed_by), approved_at_utc = as.character(review$metadata$reviewed_at_utc))
  contract <- compile_analysis_plan_contract(plan, approval); analysis_validate_adapter_pins(contract, project_dir); write_standard_mmrm_contract(contract, contract_temp); staged_contract <- read_standard_mmrm_contract(contract_temp); assert_analysis_study_identity(study_dir, review, plan, staged_contract); assert_plan_contract_parity(plan, staged_contract); contract_sha <- attr(staged_contract, "sha256")
  rendered <- analysis_render_generated(study_dir, project_dir, staged_contract, payload_sha, contract_sha); files <- c(setNames(list(readLines(contract_temp, warn = FALSE)), analysis_contract_path(study_dir)), rendered)
  obsolete <- c(if (file.exists(analysis_contract_path(study_dir))) analysis_obsolete_generated_targets(study_dir, read_standard_mmrm_contract(analysis_contract_path(study_dir)), rendered) else character(), setdiff(analysis_legacy_template_targets(study_dir, staged_contract), names(rendered)))
  obsolete <- unique(obsolete[file.exists(obsolete)])
  # 运行证据不参与本 transaction：removed analysis 的 raw/final/diagnostic/run-record/manifest
  # 只能由单独、显式且具有保留策略的归档流程处理（design 15.7）。
  analysis_transaction_publish(files, analysis_approval_journal_path(study_dir), fail_after = fail_after, delete_targets = obsolete)
  invisible(assert_approved_analysis(study_dir, project_dir, pinned_approval_payload_sha256 = payload_sha, pinned_contract_sha256 = contract_sha))
}
