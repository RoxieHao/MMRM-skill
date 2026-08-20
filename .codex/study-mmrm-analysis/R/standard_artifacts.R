standard_required_raw_columns <- function() names(standard_raw_result_schema())
standard_required_final_columns <- function() names(standard_final_result_schema())
standard_required_diagnostic_columns <- function() names(standard_diagnostic_schema())
standard_required_run_record_columns <- function() names(standard_run_record_schema())

standard_output_manifest_schema <- function() {
  data.frame(
    tfl_id = character(), tfl_type = character(), title = character(), scope_status = character(),
    output_status = character(), raw_output_file = character(), final_tfl_file = character(),
    log_file = character(), qc_file = character(), note = character(), stringsAsFactors = FALSE
  )
}

standard_artifact_absolute <- function(relative_path, project_dir, analysis_root = NULL) {
  absolute <- normalize_project_relative_path(relative_path, project_dir, "artifact path")
  if (!file.exists(absolute)) stop("artifact does not exist: ", relative_path)
  if (!is.null(analysis_root)) {
    root <- paste0(normalizePath(analysis_root, winslash = "/", mustWork = TRUE), "/")
    normalized <- normalizePath(absolute, winslash = "/", mustWork = TRUE)
    comparable <- function(x) if (.Platform$OS.type == "windows") tolower(x) else x
    if (!startsWith(comparable(normalized), comparable(root))) stop("artifact is outside analysis root: ", relative_path)
  }
  absolute
}

standard_read_csv_schema <- function(path, expected_columns, context) {
  data <- read.csv(
    path, stringsAsFactors = FALSE, fileEncoding = "UTF-8-BOM", check.names = FALSE,
    colClasses = "character"
  )
  if (!identical(names(data), expected_columns)) stop(context, " CSV schema mismatch.")
  data
}

standard_allowed_estimands <- function(analysis) {
  values <- "visit_lsmean"
  if (isTRUE(analysis$estimands$treatment_visit_lsmeans)) values <- c(values, "treatment_visit_lsmean")
  if (isTRUE(analysis$estimands$pairwise_differences)) values <- c(values, "treatment_pairwise_difference")
  values
}

standard_validate_result_identity <- function(data, analysis, context) {
  if (!nrow(data)) return(invisible(TRUE))
  expected_groups <- vapply(analysis$groups, `[[`, character(1), "id")
  invalid <- is.na(data$analysis_id) | as.character(data$analysis_id) != analysis$analysis_id |
    is.na(data$tfl_id) | as.character(data$tfl_id) != analysis$tfl_id |
    is.na(data$analysis_group_id) | !as.character(data$analysis_group_id) %in% expected_groups |
    is.na(data$estimand) | !as.character(data$estimand) %in% standard_allowed_estimands(analysis)
  if (any(invalid)) stop(context, " identity/estimand does not match execution contract.")
  invisible(TRUE)
}

standard_validate_model_rds <- function(model_path, expected_identity, model_file) {
  if (!requireNamespace("callr", quietly = TRUE)) stop("model RDS validation requires callr.")
  result <- tryCatch(callr::r(
    function(path, expected) {
      model <- readRDS(path)
      if (!inherits(model, "mmrm")) return(list(valid = FALSE, message = "object is not mmrm"))
      identity <- attr(model, "standard_artifact_identity", exact = TRUE)
      if (!is.list(identity)) return(list(valid = FALSE, message = "missing standard_artifact_identity"))
      missing <- setdiff(names(expected), names(identity))
      if (length(missing)) return(list(valid = FALSE, message = paste("identity missing", paste(missing, collapse = ", "))))
      mismatch <- names(expected)[!vapply(names(expected), function(name) {
        identical(as.character(identity[[name]]), as.character(expected[[name]]))
      }, logical(1))]
      if (length(mismatch)) return(list(valid = FALSE, message = paste("identity mismatch", paste(mismatch, collapse = ", "))))
      actual_formula <- tryCatch({
        formula_parts <- stats::formula(model)
        formula_object <- if (is.list(formula_parts) && !is.null(formula_parts$formula)) formula_parts$formula else formula_parts
        paste(deparse(formula_object, width.cutoff = 500L), collapse = " ")
      }, error = function(e) conditionMessage(e))
      if (!identical(actual_formula, as.character(expected$formula))) {
        return(list(valid = FALSE, message = paste0("model formula mismatch; actual=", actual_formula, "; expected=", as.character(expected$formula))))
      }
      list(valid = TRUE, message = "")
    },
    args = list(path = model_path, expected = expected_identity), spinner = FALSE, show = FALSE
  ), error = function(e) e)
  if (inherits(result, "error")) stop("model RDS read/validation failed: ", model_file, "; ", conditionMessage(result))
  if (!is.list(result) || !isTRUE(result$valid)) stop("model RDS identity invalid: ", model_file, "; ", result$message)
  invisible(TRUE)
}

standard_validate_output_manifest <- function(manifest) {
  if (!is.data.frame(manifest) || !identical(names(manifest), names(standard_output_manifest_schema()))) {
    stop("collector manifest schema mismatch.")
  }
  if (nrow(manifest)) {
    if (any(is.na(manifest$tfl_id) | !nzchar(trimws(as.character(manifest$tfl_id)))) ||
        any(as.character(manifest$tfl_type) != "table") ||
        any(as.character(manifest$scope_status) != "approved") ||
        any(!as.character(manifest$output_status) %in% standard_allowed_run_status())) {
      stop("collector manifest identity/status invalid.")
    }
  }
  invisible(TRUE)
}

standard_validate_analysis_artifacts <- function(paths, chain, analysis, expected_invocation = NULL) {
  contract <- chain$contract
  output_paths <- analysis_output_paths(paths, analysis$analysis_id)
  if (!file.exists(output_paths$run_record)) stop("missing analysis-run-record.csv: ", analysis$analysis_id)
  record <- standard_read_csv_schema(output_paths$run_record, standard_required_run_record_columns(), "run record")
  if (nrow(record) != 1L) stop("run record must have exactly one row.")
  scalar <- function(name) as.character(record[[name]][[1]])
  expected_record <- c(
    study_id = as.character(contract$study$study_id), analysis_id = analysis$analysis_id,
    tfl_id = analysis$tfl_id, tfl_type = "table", title = analysis$title, scope_status = "approved",
    profile_version = standard_mmrm_profile_version()
  )
  mismatch <- names(expected_record)[!vapply(names(expected_record), function(name) identical(scalar(name), expected_record[[name]]), logical(1))]
  if (length(mismatch)) stop("run record identity mismatch: ", paste(mismatch, collapse = ", "))
  if (!identical(toupper(scalar("review_sha256")), toupper(chain$review$sha256)) ||
      !identical(toupper(scalar("analysis_plan_sha256")), toupper(attr(chain$plan, "sha256"))) ||
      !identical(toupper(scalar("approval_payload_sha256")), toupper(chain$approval_payload_sha256)) ||
      !identical(toupper(scalar("contract_sha256")), toupper(chain$contract_sha256))) {
    stop("run record approval-plan-contract identity mismatch.")
  }
  if (!nzchar(scalar("run_id")) || !nzchar(scalar("invocation_id"))) stop("run record run/invocation identity missing.")
  if (!is.null(expected_invocation) && !identical(scalar("invocation_id"), expected_invocation)) stop("run record invocation mismatch.")
  if (!scalar("output_status") %in% standard_allowed_run_status() || !scalar("computational_risk") %in% standard_allowed_risk()) {
    stop("run record status/risk invalid.")
  }

  expected_paths <- c(
    diagnostic_file = project_relative_path(output_paths$diagnostic_csv, paths$project_dir),
    diagnostic_report = project_relative_path(output_paths$diagnostic_report, paths$project_dir),
    log_file = project_relative_path(output_paths$log_file, paths$project_dir),
    raw_output_file = project_relative_path(file.path(output_paths$tables, analysis$output$raw_file), paths$project_dir),
    final_tfl_file = project_relative_path(file.path(output_paths$tables, analysis$output$final_file), paths$project_dir)
  )
  for (field in names(expected_paths)) {
    if (!identical(gsub("\\\\", "/", scalar(field)), expected_paths[[field]])) stop("run record path mismatch: ", field)
    standard_artifact_absolute(scalar(field), paths$project_dir, output_paths$root)
  }

  raw <- standard_read_csv_schema(
    standard_artifact_absolute(scalar("raw_output_file"), paths$project_dir, output_paths$root),
    standard_required_raw_columns(), "raw output"
  )
  final <- standard_read_csv_schema(
    standard_artifact_absolute(scalar("final_tfl_file"), paths$project_dir, output_paths$root),
    standard_required_final_columns(), "final output"
  )
  successful <- scalar("output_status") %in% c("complete", "partial")
  if (successful && (nrow(raw) < 1L || nrow(final) < 1L)) stop("complete/partial raw/final CSV must have at least one row.")
  if (!successful && !identical(scalar("output_status"), "fit_failed") && (nrow(raw) != 0L || nrow(final) != 0L)) stop("blocked status raw/final CSV must keep 0-row schema.")
  if (identical(scalar("output_status"), "fit_failed") && nrow(raw) != 0L) stop("fit_failed raw inference CSV must keep 0-row schema.")
  standard_validate_result_identity(raw, analysis, "raw output")
  standard_validate_result_identity(final, analysis, "final output")

  diagnostics <- standard_read_csv_schema(output_paths$diagnostic_csv, standard_required_diagnostic_columns(), "diagnostics")
  if (nrow(diagnostics) == 0L) stop("diagnostics must not be empty.")
  diagnostic_mismatch <-
    is.na(diagnostics$study_id) | as.character(diagnostics$study_id) != as.character(contract$study$study_id) |
    is.na(diagnostics$analysis_id) | as.character(diagnostics$analysis_id) != analysis$analysis_id |
    is.na(diagnostics$profile_version) | as.character(diagnostics$profile_version) != standard_mmrm_profile_version() |
    is.na(diagnostics$run_id) | as.character(diagnostics$run_id) != scalar("run_id") |
    is.na(diagnostics$invocation_id) | as.character(diagnostics$invocation_id) != scalar("invocation_id") |
    is.na(diagnostics$review_sha256) | toupper(as.character(diagnostics$review_sha256)) != toupper(chain$review$sha256) |
    is.na(diagnostics$analysis_plan_sha256) | toupper(as.character(diagnostics$analysis_plan_sha256)) != toupper(attr(chain$plan, "sha256")) |
    is.na(diagnostics$approval_payload_sha256) | toupper(as.character(diagnostics$approval_payload_sha256)) != toupper(chain$approval_payload_sha256) |
    is.na(diagnostics$contract_sha256) | toupper(as.character(diagnostics$contract_sha256)) != toupper(chain$contract_sha256)
  if (any(diagnostic_mismatch)) stop("diagnostics identity mismatch.")
  if (any(!as.character(diagnostics$run_status) %in% standard_allowed_run_status()) ||
      any(!as.character(diagnostics$failure_domain) %in% standard_allowed_failure_domain()) ||
      any(is.na(diagnostics$failure_phase) | !nzchar(trimws(as.character(diagnostics$failure_phase)))) ||
      any(!as.character(diagnostics$computational_risk) %in% standard_allowed_risk())) stop("diagnostics status/failure/risk invalid.")
  if (!identical(standard_collapse_status(as.character(diagnostics$run_status)), scalar("output_status")) ||
      !identical(standard_highest_risk(as.character(diagnostics$computational_risk)), scalar("computational_risk"))) {
    stop("run record and diagnostics status/risk mismatch.")
  }
  expected_groups <- vapply(analysis$groups, `[[`, character(1), "id")
  observed_groups <- sort(unique(as.character(diagnostics$analysis_group_id)))
  if (successful && !identical(observed_groups, sort(expected_groups))) stop("diagnostics group catalog mismatch.")
  if (!successful && !all(observed_groups %in% c("ALL", expected_groups))) stop("failure diagnostics group identity invalid.")

  fitted <- !is.na(diagnostics$model_file) & nzchar(as.character(diagnostics$model_file))
  if (successful && !any(fitted)) stop("complete/partial diagnostics must include a fitted model RDS.")
  if (any(!fitted & as.character(diagnostics$run_status) %in% c("complete", "partial"))) stop("successful group missing model RDS.")
  if (nrow(raw)) {
    result_models <- unique(as.character(raw$model_rds))
    diagnostic_models <- unique(as.character(diagnostics$model_file[fitted]))
    if (any(is.na(result_models) | !nzchar(result_models)) || !identical(sort(result_models), sort(diagnostic_models))) {
      stop("raw output and diagnostics model RDS mismatch.")
    }
  }
  for (i in which(fitted)) {
    model_file <- as.character(diagnostics$model_file[[i]])
    covariance <- as.character(diagnostics$final_covariance[[i]])
    expected_identity <- list(
      study_id = as.character(contract$study$study_id), analysis_id = analysis$analysis_id,
      group_id = as.character(diagnostics$analysis_group_id[[i]]),
      profile = standard_mmrm_profile_version(), profile_version = standard_mmrm_profile_version(),
      review_sha256 = toupper(chain$review$sha256), analysis_plan_sha256 = toupper(attr(chain$plan, "sha256")),
      approval_payload_sha256 = toupper(chain$approval_payload_sha256), contract_sha256 = toupper(chain$contract_sha256),
      adapter_sha256 = if (is.null(analysis$adapter_sha256)) "" else toupper(analysis$adapter_sha256),
      run_id = scalar("run_id"), invocation_id = scalar("invocation_id"),
      treatment_levels = if (is.null(analysis$treatment)) "" else paste(analysis$treatment$levels, collapse = "|"),
      treatment_reference = if (is.null(analysis$treatment)) "" else analysis$treatment$reference,
      treatment_comparator = if (is.null(analysis$treatment)) "" else analysis$treatment$comparator,
      contrast_direction = if (is.null(analysis$treatment)) "" else analysis$treatment$contrast_direction,
      confidence_level = if (is.null(analysis$treatment)) "" else as.character(analysis$treatment$confidence_level),
      multiplicity_adjustment = if (is.null(analysis$treatment)) "" else analysis$treatment$multiplicity_adjustment,
      covariance = covariance, formula = standard_formula_text(standard_fixed_formula(analysis, covariance))
    )
    model_path <- standard_artifact_absolute(model_file, paths$project_dir, output_paths$root)
    standard_validate_model_rds(model_path, expected_identity, model_file)
  }

  if (!file.exists(output_paths$recode_audit)) stop("missing identity-bound recode audit artifact: ", analysis$analysis_id)
  recode_audit <- standard_read_csv_schema(output_paths$recode_audit, names(standard_recode_audit_schema()), "recode audit")
  expected_recode_ids <- if (is.null(analysis$derivations)) character() else vapply(analysis$derivations, function(d) as.character(d$id), character(1))
  if (nrow(recode_audit)) {
    recode_mismatch <-
      is.na(recode_audit$study_id) | as.character(recode_audit$study_id) != as.character(contract$study$study_id) |
      is.na(recode_audit$analysis_id) | as.character(recode_audit$analysis_id) != analysis$analysis_id |
      is.na(recode_audit$profile_version) | as.character(recode_audit$profile_version) != standard_mmrm_profile_version() |
      is.na(recode_audit$run_id) | as.character(recode_audit$run_id) != scalar("run_id") |
      is.na(recode_audit$invocation_id) | as.character(recode_audit$invocation_id) != scalar("invocation_id") |
      is.na(recode_audit$review_sha256) | toupper(as.character(recode_audit$review_sha256)) != toupper(chain$review$sha256) |
      is.na(recode_audit$analysis_plan_sha256) | toupper(as.character(recode_audit$analysis_plan_sha256)) != toupper(attr(chain$plan, "sha256")) |
      is.na(recode_audit$approval_payload_sha256) | toupper(as.character(recode_audit$approval_payload_sha256)) != toupper(chain$approval_payload_sha256) |
      is.na(recode_audit$contract_sha256) | toupper(as.character(recode_audit$contract_sha256)) != toupper(chain$contract_sha256)
    if (any(recode_mismatch)) stop("recode audit identity mismatch.")
    if (anyDuplicated(as.character(recode_audit$recode_id))) stop("recode audit recode_id must be unique.")
    if (any(!as.character(recode_audit$unmatched_policy) %in% c("error", "preserve", "set_missing")) ||
        any(!as.character(recode_audit$missing_policy) %in% c("error", "preserve", "set_missing")) ||
        any(!as.character(recode_audit$value_type) %in% c("character", "numeric", "logical"))) {
      stop("recode audit policy/value_type invalid.")
    }
    count_columns <- c("input_count", "matched_count", "unmatched_count", "missing_count", "output_missing_count")
    counts <- lapply(count_columns, function(name) suppressWarnings(as.integer(recode_audit[[name]])))
    names(counts) <- count_columns
    if (any(vapply(counts, function(x) any(is.na(x) | x < 0L), logical(1)))) stop("recode audit counts must be nonnegative integers.")
    if (any(counts$matched_count + counts$unmatched_count + counts$missing_count != counts$input_count) ||
        any(counts$matched_count + counts$unmatched_count > counts$input_count) ||
        any(counts$output_missing_count > counts$input_count)) {
      stop("recode audit aggregate counts are inconsistent.")
    }
  }
  successful_recode <- scalar("output_status") %in% c("complete", "partial")
  if (successful_recode && (!setequal(as.character(recode_audit$recode_id), expected_recode_ids) || nrow(recode_audit) != length(expected_recode_ids))) {
    stop("recode audit must record each approved recode exactly once for a successful run: ", analysis$analysis_id)
  }
  if (nrow(recode_audit) && any(!as.character(recode_audit$recode_id) %in% expected_recode_ids)) stop("recode audit references an unapproved recode: ", analysis$analysis_id)

  list(record = record, diagnostics = diagnostics, raw = raw, final = final, recode_audit = recode_audit)
}

run_standard_mmrm_collector <- function(script_file, pinned_approval_payload_sha256, pinned_contract_sha256, mode = "run-and-collect", fail_fast = NULL) {
  if (!mode %in% c("run-and-collect", "collect-only")) stop("mode must be run-and-collect or collect-only.")
  if (!is.null(fail_fast) && (!is.logical(fail_fast) || length(fail_fast) != 1L || is.na(fail_fast))) stop("fail_fast must be true, false, or NULL.")
  project_dir <- find_project_dir(script_file)
  helper_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
  for (helper in c("study_paths.R", "io.R", "specification.R", "canonical_hash.R", "standard_contract.R", "standard_analysis_definition.R", "analysis_plan.R", "analysis_contract_generation.R", "analysis_approval.R", "standard_engine.R")) source(file.path(helper_dir, helper), encoding = "UTF-8", local = environment())
  paths <- study_paths(script_file)
  chain <- assert_approved_analysis(paths$study_dir, project_dir, pinned_approval_payload_sha256 = pinned_approval_payload_sha256, pinned_contract_sha256 = pinned_contract_sha256)
  contract <- chain$contract
  effective_fail_fast <- standard_resolve_fail_fast(contract, fail_fast)
  catalog <- standard_contract_catalog(contract)
  dir.create(paths$output_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(paths$log_output_dir, recursive = TRUE, showWarnings = FALSE)
  collector_log <- file.path(paths$log_output_dir, "run_all_mmrm.log")
  writeLines(character(), collector_log, useBytes = TRUE)
  add_log <- function(...) cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " | ", paste0(..., collapse = ""), "\n", file = collector_log, append = TRUE, sep = "")
  invocation_id <- paste0("collector-", format(Sys.time(), "%Y%m%d-%H%M%S"), "-", Sys.getpid())
  expected_invocation <- if (mode == "run-and-collect") invocation_id else NULL
  artifacts <- list()
  notes <- setNames(rep("", nrow(catalog)), catalog$analysis_id)
  stopped <- FALSE

  if (mode == "run-and-collect") {
    rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
    for (analysis_id in catalog$analysis_id) {
      if (stopped) {
        notes[[analysis_id]] <- "skipped by fail_fast after prior terminal failure"
        next
      }
      analysis <- standard_contract_get_analysis(contract, analysis_id)
      wrapper <- file.path(paths$r_analysis_dir, paste0(analysis_id, ".R"))
      if (!file.exists(wrapper)) {
        notes[[analysis_id]] <- "missing generated wrapper"
        if (effective_fail_fast) stopped <- TRUE
        next
      }
      output <- tryCatch(suppressWarnings(system2(
        rscript,
        c("--vanilla", shQuote(wrapper), paste0("--collector-invocation-id=", invocation_id)),
        stdout = TRUE, stderr = TRUE, wait = TRUE
      )), error = function(e) structure(conditionMessage(e), status = 1L))
      if (length(output)) cat(paste(output, collapse = "\n"), "\n", file = collector_log, append = TRUE)
      exit_status <- attr(output, "status")
      if (is.null(exit_status)) exit_status <- 0L
      artifact <- tryCatch(standard_validate_analysis_artifacts(paths, chain, analysis, expected_invocation), error = function(e) e)
      if (inherits(artifact, "error")) {
        notes[[analysis_id]] <- paste0("artifact validation failed: ", conditionMessage(artifact))
      } else {
        artifacts[[analysis_id]] <- artifact
        if (exit_status != 0L) notes[[analysis_id]] <- paste0("wrapper exited ", exit_status, " after writing a valid terminal artifact")
      }
      terminal <- is.null(artifacts[[analysis_id]]) || artifacts[[analysis_id]]$record$output_status[[1]] %in% standard_terminal_failure_status()
      if (effective_fail_fast && (exit_status != 0L || terminal)) stopped <- TRUE
      add_log(analysis_id, " exit=", exit_status, " collected=", !is.null(artifacts[[analysis_id]]))
    }
  } else {
    add_log("collect-only: wrapper execution skipped")
    for (analysis_id in catalog$analysis_id) {
      analysis <- standard_contract_get_analysis(contract, analysis_id)
      artifact <- tryCatch(standard_validate_analysis_artifacts(paths, chain, analysis), error = function(e) e)
      if (inherits(artifact, "error")) notes[[analysis_id]] <- paste0("artifact validation failed: ", conditionMessage(artifact)) else artifacts[[analysis_id]] <- artifact
    }
  }

  manifest_rows <- lapply(seq_len(nrow(catalog)), function(i) {
    analysis_id <- catalog$analysis_id[[i]]
    analysis <- standard_contract_get_analysis(contract, analysis_id)
    artifact <- artifacts[[analysis_id]]
    if (is.null(artifact)) {
      data.frame(
        tfl_id = analysis$tfl_id, tfl_type = "table", title = analysis$title, scope_status = "approved",
        output_status = "blocked_mapping", raw_output_file = "", final_tfl_file = "",
        log_file = project_relative_path(collector_log, project_dir), qc_file = "",
        note = notes[[analysis_id]], stringsAsFactors = FALSE
      )
    } else {
      record <- artifact$record
      data.frame(
        tfl_id = as.character(record$tfl_id), tfl_type = as.character(record$tfl_type), title = as.character(record$title),
        scope_status = as.character(record$scope_status), output_status = as.character(record$output_status),
        raw_output_file = as.character(record$raw_output_file), final_tfl_file = as.character(record$final_tfl_file),
        log_file = as.character(record$log_file), qc_file = as.character(record$diagnostic_file),
        note = notes[[analysis_id]], stringsAsFactors = FALSE
      )
    }
  })
  manifest <- do.call(rbind, manifest_rows)
  standard_validate_output_manifest(manifest)
  diagnostics <- lapply(artifacts, `[[`, "diagnostics")
  diagnostics <- if (length(diagnostics)) do.call(rbind, diagnostics) else standard_diagnostic_schema()
  write_utf8_bom_csv(manifest, paths$output_manifest)
  write_utf8_bom_csv(diagnostics, paths$run_diagnostics_file)
  overall <- if (all(manifest$output_status == "complete")) "complete" else if (all(manifest$output_status %in% standard_terminal_failure_status())) "failed" else "partial"
  summary_details <- lapply(seq_len(nrow(catalog)), function(i) {
    analysis_id <- catalog$analysis_id[[i]]
    artifact <- artifacts[[analysis_id]]
    if (is.null(artifact)) {
      list(
        analysis_id = analysis_id, tfl_id = catalog$tfl_id[[i]], status = "blocked_mapping",
        final_covariance = "", convergence = "not_assessed", risk = standard_risk_label_cn("Not assessed"),
        report = "", run_id = ""
      )
    } else {
      record <- artifact$record
      diag <- artifact$diagnostics[1L, , drop = FALSE]
      list(
        analysis_id = analysis_id, tfl_id = as.character(record$tfl_id[[1]]),
        status = as.character(record$output_status[[1]]),
        final_covariance = as.character(diag$final_covariance[[1]]),
        convergence = as.character(diag$convergence_status[[1]]),
        risk = standard_risk_label_cn(as.character(record$computational_risk[[1]])),
        report = as.character(record$diagnostic_report[[1]]),
        run_id = as.character(record$run_id[[1]])
      )
    }
  })
  summary_lines <- c(
    "# Standard MMRM 运行汇总", "",
    paste0("- 运行模式：`", mode, "`"), paste0("- 有效 fail_fast：`", tolower(as.character(effective_fail_fast)), "`"),
    paste0("- Invocation：`", invocation_id, "`"),
    paste0("- Overall status：`", overall, "`"), paste0("- Profile：`", standard_mmrm_profile_version(), "`"), "",
    "| Analysis ID | TFL ID | Status | 最终 covariance | 收敛 | 中文风险 | 报告链接 | Run ID |",
    "|---|---|---|---|---|---|---|---|",
    vapply(summary_details, function(item) paste0(
      "| `", item$analysis_id, "` | `", item$tfl_id, "` | `", item$status,
      "` | `", item$final_covariance, "` | `", item$convergence, "` | ", item$risk,
      " | `", item$report, "` | `", item$run_id, "` |"
    ), character(1))
  )
  writeLines(summary_lines, paths$run_summary_file, useBytes = TRUE)
  add_log("collector finished; overall_status=", overall, "; effective_fail_fast=", effective_fail_fast)
  result <- list(manifest = manifest, diagnostics = diagnostics, overall_status = overall, invocation_id = invocation_id, fail_fast = effective_fail_fast)
  if (identical(overall, "failed")) stop("Standard MMRM collector overall_status=failed after writing manifest/diagnostics/summary.")
  invisible(result)
}
