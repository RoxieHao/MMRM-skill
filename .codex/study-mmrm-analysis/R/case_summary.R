standard_case_summary_pattern_schemas <- function() {
  list(
    analysis_catalog = c("analysis_id", "tfl_id", "title"),
    run_records = c("analysis_id", "run_id", "output_status", "computational_risk", "specification_sha256", "contract_sha256"),
    diagnostic_metadata = c("analysis_id", "analysis_group_id", "final_covariance", "fallback_used", "convergence_status", "computational_risk", "run_status"),
    registry = c("pattern_id", "adapter_family", "description", "status"),
    promotion_records = c("pattern_id", "decision", "reviewed_by", "reviewed_at", "evidence_ids", "regression_test_status", "note"),
    pattern_candidates = c("candidate_id", "pattern_id", "adapter_family", "candidate_summary", "candidate_status"),
    pattern_evidence = c(
      "evidence_id", "pattern_id", "study_id", "analysis_id", "aggregate_analysis_count",
      "aggregate_success_count", "aggregate_failure_count", "aggregate_status",
      "independent_study", "aggregate_only", "status"
    )
  )
}

standard_case_scalar_character <- function(value, context, allow_empty = FALSE) {
  if (!is.character(value) || length(value) != 1L || is.na(value) || (!allow_empty && !nzchar(trimws(value)))) {
    stop(context, " 必须是", if (allow_empty) "" else "非空", " scalar character。")
  }
  value
}

standard_case_nonnegative_integer <- function(value, context) {
  if (!is.numeric(value) || length(value) != 1L || is.na(value) || !is.finite(value) || value < 0 || value != floor(value)) {
    stop(context, " 必须是 nonnegative integer。")
  }
  invisible(TRUE)
}

standard_case_reject_subject_text <- function(value, context) {
  text <- paste(as.character(value), collapse = " ")
  subject_like <- "(?i)(subject[_ -]?id|usubjid|subjid|person[_ -]?key|subject[[:space:]]+[A-Za-z]*[0-9]+)"
  if (grepl(subject_like, text, perl = TRUE)) stop(context, " 不得包含 subject-like identifier/text。")
  invisible(TRUE)
}

standard_validate_pattern_items <- function(items, expected_keys, context, vector_keys = character()) {
  if (!is.list(items) || !is.null(names(items))) stop(context, " 必须是 sequence。")
  forbidden <- c("subject_id", "subject", "usubjid", "subjid", "person_key", "row_data", "subject_rows", "rows", "records")
  for (i in seq_along(items)) {
    item <- items[[i]]
    item_context <- paste0(context, "[[", i, "]]" )
    if (!is.list(item) || is.null(names(item)) || any(!nzchar(names(item))) || anyDuplicated(names(item))) stop(item_context, " 必须是唯一命名 mapping。")
    if (!identical(sort(names(item)), sort(expected_keys))) stop(item_context, " schema 不匹配。")
    if (any(tolower(names(item)) %in% forbidden)) stop(item_context, " 不得包含 row-level subject data。")
    for (name in names(item)) {
      value <- item[[name]]
      if (name %in% vector_keys) {
        if (!(is.atomic(value) && is.null(names(value))) && !(is.list(value) && length(value) == 0L)) stop(item_context, ".", name, " 必须是 flat unnamed vector。")
      } else if (!is.atomic(value) || length(value) != 1L || anyNA(value) || !is.null(names(value))) {
        stop(item_context, ".", name, " 必须是 single non-NA atomic scalar；禁止 nested/row data。")
      }
    }
  }
  invisible(TRUE)
}

standard_case_unique_ids <- function(items, field, context) {
  if (!length(items)) return(character())
  values <- vapply(seq_along(items), function(i) standard_case_scalar_character(items[[i]][[field]], paste0(context, "[[", i, "]]$", field)), character(1))
  if (anyDuplicated(values)) stop(context, ".", field, " 必须唯一。")
  values
}

validate_standard_case_summary <- function(summary) {
  required <- c(
    "schema_version", "study_id", "profile_version", "contract_sha256", "analysis_catalog",
    "run_records", "diagnostic_metadata", "adapter_patterns", "pattern_candidates", "pattern_evidence", "promotion"
  )
  if (!is.list(summary) || is.null(names(summary)) || anyDuplicated(names(summary)) || !identical(sort(names(summary)), sort(required))) {
    stop("case summary 顶层 schema 不匹配。")
  }
  if (!identical(summary$schema_version, "standard-mmrm-case-summary/v1") ||
      !identical(summary$profile_version, standard_mmrm_profile_version()) ||
      !is.character(summary$study_id) || length(summary$study_id) != 1L || !nzchar(summary$study_id) ||
      !is.character(summary$contract_sha256) || length(summary$contract_sha256) != 1L || !grepl("^[A-Fa-f0-9]{64}$", summary$contract_sha256)) {
    stop("case summary identity 无效。")
  }
  catalog_analysis_ids <- standard_case_unique_ids(summary$analysis_catalog, "analysis_id", "analysis_catalog")
  record_analysis_ids <- standard_case_unique_ids(summary$run_records, "analysis_id", "run_records")
  if (!setequal(catalog_analysis_ids, record_analysis_ids) || length(catalog_analysis_ids) != length(record_analysis_ids)) {
    stop("case summary 必须为 approved contract 中的每个 analysis/TFL 提供恰好一条 run record。")
  }
  schemas <- standard_case_summary_pattern_schemas()
  standard_validate_pattern_items(summary$analysis_catalog, schemas$analysis_catalog, "analysis_catalog")
  standard_validate_pattern_items(summary$run_records, schemas$run_records, "run_records")
  standard_validate_pattern_items(summary$diagnostic_metadata, schemas$diagnostic_metadata, "diagnostic_metadata")
  if (!is.list(summary$adapter_patterns) || is.null(names(summary$adapter_patterns)) ||
      !identical(sort(names(summary$adapter_patterns)), c("promotion_records", "registry"))) {
    stop("adapter_patterns 必须明确包含 registry 和 promotion_records。")
  }
  standard_validate_pattern_items(summary$adapter_patterns$registry, schemas$registry, "adapter_patterns.registry")
  standard_validate_pattern_items(summary$adapter_patterns$promotion_records, schemas$promotion_records, "adapter_patterns.promotion_records", vector_keys = "evidence_ids")
  standard_validate_pattern_items(summary$pattern_candidates, schemas$pattern_candidates, "pattern_candidates")
  standard_validate_pattern_items(summary$pattern_evidence, schemas$pattern_evidence, "pattern_evidence")

  registry <- summary$adapter_patterns$registry
  records <- summary$adapter_patterns$promotion_records
  candidates <- summary$pattern_candidates
  evidence <- summary$pattern_evidence
  registry_ids <- standard_case_unique_ids(registry, "pattern_id", "adapter_patterns.registry")
  standard_case_unique_ids(candidates, "candidate_id", "pattern_candidates")
  evidence_ids <- standard_case_unique_ids(evidence, "evidence_id", "pattern_evidence")

  for (i in seq_along(registry)) {
    item <- registry[[i]]
    if (!item$status %in% c("candidate", "promoted")) stop("adapter_patterns.registry status 只允许 candidate/promoted。")
    standard_case_scalar_character(item$adapter_family, paste0("adapter_patterns.registry[[", i, "]]$adapter_family"))
    standard_case_scalar_character(item$description, paste0("adapter_patterns.registry[[", i, "]]$description"))
    standard_case_reject_subject_text(item$description, paste0("adapter_patterns.registry[[", i, "]]$description"))
  }
  for (i in seq_along(candidates)) {
    item <- candidates[[i]]
    if (!item$pattern_id %in% registry_ids) stop("pattern_candidates 引用不存在的 pattern_id。")
    if (!item$candidate_status %in% c("candidate", "rejected")) stop("pattern_candidates.candidate_status 无效。")
    standard_case_reject_subject_text(item$candidate_summary, paste0("pattern_candidates[[", i, "]]$candidate_summary"))
  }
  for (i in seq_along(evidence)) {
    item <- evidence[[i]]
    if (!item$pattern_id %in% registry_ids) stop("pattern_evidence 引用不存在的 pattern_id。")
    if (!is.logical(item$independent_study) || !identical(item$independent_study, TRUE)) stop("所有 evidence 必须 independent_study=true。")
    if (!is.logical(item$aggregate_only) || !identical(item$aggregate_only, TRUE)) stop("所有 evidence 必须 aggregate_only=true。")
    if (!item$status %in% c("candidate", "accepted", "rejected")) stop("pattern_evidence.status 无效。")
    for (field in c("aggregate_analysis_count", "aggregate_success_count", "aggregate_failure_count")) {
      standard_case_nonnegative_integer(item[[field]], paste0("pattern_evidence[[", i, "]]$", field))
    }
    if (item$aggregate_success_count + item$aggregate_failure_count > item$aggregate_analysis_count) {
      stop("pattern_evidence aggregate counts 不一致。")
    }
    if (!item$aggregate_status %in% c("complete", "partial", "failed")) stop("pattern_evidence.aggregate_status 无效。")
  }

  approved_record_patterns <- character()
  for (i in seq_along(records)) {
    record <- records[[i]]
    context <- paste0("adapter_patterns.promotion_records[[", i, "]]" )
    if (!record$pattern_id %in% registry_ids) stop(context, " 引用不存在的 pattern_id。")
    if (!record$decision %in% c("pending", "rejected", "approved")) stop(context, ".decision 无效。")
    if (!record$regression_test_status %in% c("not_run", "failed", "passed")) stop(context, ".regression_test_status 无效。")
    if (!(is.list(record$evidence_ids) && length(record$evidence_ids) == 0L)) {
      if (!is.character(record$evidence_ids) || is.null(record$evidence_ids) || anyNA(record$evidence_ids) || any(!nzchar(trimws(record$evidence_ids))) || anyDuplicated(record$evidence_ids)) {
        stop(context, ".evidence_ids 必须是 unique nonempty character vector。")
      }
      if (any(!record$evidence_ids %in% evidence_ids)) stop(context, " 引用不存在的 evidence_id。")
    }
    standard_case_reject_subject_text(record$note, paste0(context, ".note"))
    if (identical(record$decision, "approved")) {
      approved_record_patterns <- c(approved_record_patterns, record$pattern_id)
      standard_case_scalar_character(record$reviewed_by, paste0(context, ".reviewed_by"))
      reviewed_at <- standard_case_scalar_character(record$reviewed_at, paste0(context, ".reviewed_at"))
      if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", reviewed_at)) stop(context, ".reviewed_at 必须是 UTC ISO-8601 时间。")
      if (!identical(record$regression_test_status, "passed")) stop(context, " approved promotion 必须 regression_test_status=passed。")
      if (!is.character(record$evidence_ids) || length(record$evidence_ids) < 2L) stop(context, " approved promotion 至少需要 2 个 evidence IDs。")
      selected <- evidence[match(record$evidence_ids, evidence_ids)]
      if (any(vapply(selected, function(item) !identical(item$pattern_id, record$pattern_id), logical(1)))) stop(context, " 的 evidence 必须引用同一 pattern。")
      if (any(vapply(selected, function(item) !identical(item$status, "accepted"), logical(1)))) stop(context, " 的 evidence 必须全部 accepted。")
      studies <- vapply(selected, `[[`, character(1), "study_id")
      if (length(unique(studies)) < 2L) stop(context, " 至少需要来自 2 个 unique studies 的 evidence。")
    }
  }

  promoted_patterns <- vapply(registry, function(item) identical(item$status, "promoted"), logical(1))
  promoted_ids <- registry_ids[promoted_patterns]
  if (length(promoted_ids)) {
    if (any(vapply(promoted_ids, function(id) sum(approved_record_patterns == id) != 1L, logical(1)))) {
      stop("每个 promoted registry pattern 必须恰有一个 approved promotion record。")
    }
  }
  if (any(approved_record_patterns %in% registry_ids[!promoted_patterns])) stop("approved promotion record 必须对应 promoted registry pattern。")

  promotion_required <- c("status", "engine_change", "minimum_evidence", "human_approval_required", "regression_tests_required", "automatic_engine_modification")
  if (!is.list(summary$promotion) || is.null(names(summary$promotion)) || !identical(sort(names(summary$promotion)), sort(promotion_required)) ||
      !identical(summary$promotion$minimum_evidence, "at_least_2_independent_studies") ||
      !identical(summary$promotion$human_approval_required, TRUE) || !identical(summary$promotion$regression_tests_required, TRUE) ||
      !identical(summary$promotion$automatic_engine_modification, FALSE)) {
    stop("case summary promotion control 无效。")
  }
  if (!length(promoted_ids)) {
    if (!identical(summary$promotion$status, "candidate") || !identical(summary$promotion$engine_change, "not_promoted")) {
      stop("无 promoted pattern 时 promotion 必须保持 candidate/not_promoted。")
    }
  } else if (!identical(summary$promotion$status, "promoted") || !identical(summary$promotion$engine_change, "approved_for_next_profile")) {
    stop("存在 promoted pattern 时 promotion 状态必须与 approved record 一致。")
  }
  invisible(TRUE)
}

standard_case_summary <- function(paths, contract) {
  catalog <- standard_contract_catalog(contract)
  manifest_path <- paths$output_manifest
  if (!file.exists(manifest_path)) stop("缺少 tfl-output-manifest.csv，无法生成覆盖全部 TFL 的 case summary。")
  manifest <- read_utf8_bom_csv(manifest_path)
  required_manifest <- c("tfl_id", "output_status", "note")
  if (!all(required_manifest %in% names(manifest)) || anyDuplicated(manifest$tfl_id) ||
      !setequal(as.character(manifest$tfl_id), as.character(catalog$tfl_id)) || nrow(manifest) != nrow(catalog)) {
    stop("tfl-output-manifest.csv 必须为 contract 中的每个 TFL 提供恰好一行。")
  }
  records <- lapply(seq_len(nrow(catalog)), function(i) {
    analysis_id <- catalog$analysis_id[[i]]
    path <- analysis_output_paths(paths, analysis_id)$run_record
    if (file.exists(path)) {
      data <- read_utf8_bom_csv(path)
      required <- c("analysis_id", "tfl_id", "run_id", "output_status", "computational_risk", "specification_sha256", "contract_sha256")
      manifest_row <- manifest[match(catalog$tfl_id[[i]], as.character(manifest$tfl_id)), , drop = FALSE]
      if (nrow(data) == 1L && all(required %in% names(data)) &&
          identical(as.character(data$analysis_id[[1L]]), analysis_id) &&
          identical(as.character(data$tfl_id[[1L]]), as.character(catalog$tfl_id[[i]])) &&
          identical(toupper(as.character(data$contract_sha256[[1L]])), toupper(attr(contract, "sha256"))) &&
          identical(as.character(data$output_status[[1L]]), as.character(manifest_row$output_status[[1L]]))) {
        return(data[c("analysis_id", "run_id", "output_status", "computational_risk", "specification_sha256", "contract_sha256")])
      }
    }
    manifest_row <- manifest[match(catalog$tfl_id[[i]], as.character(manifest$tfl_id)), , drop = FALSE]
    data.frame(
      analysis_id = analysis_id,
      run_id = "collector-synthesized",
      output_status = as.character(manifest_row$output_status[[1L]]),
      computational_risk = "Not assessed",
      specification_sha256 = "not_available",
      contract_sha256 = toupper(attr(contract, "sha256")),
      stringsAsFactors = FALSE
    )
  })
  diagnostics <- lapply(catalog$analysis_id, function(analysis_id) {
    path <- analysis_output_paths(paths, analysis_id)$diagnostic_csv
    if (!file.exists(path)) return(NULL)
    data <- read_utf8_bom_csv(path)
    required <- c("analysis_id", "analysis_group_id", "final_covariance", "fallback_used", "convergence_status", "computational_risk", "run_status")
    if (!all(required %in% names(data))) return(NULL)
    data[required]
  })
  diagnostics <- diagnostics[!vapply(diagnostics, is.null, logical(1))]
  record_data <- do.call(rbind, records)
  diagnostic_data <- if (length(diagnostics)) do.call(rbind, diagnostics) else NULL
  summary <- list(
    schema_version = "standard-mmrm-case-summary/v1", study_id = contract$study$study_id,
    profile_version = contract$profile_version, contract_sha256 = toupper(attr(contract, "sha256")),
    analysis_catalog = lapply(seq_len(nrow(catalog)), function(i) as.list(catalog[i, c("analysis_id", "tfl_id", "title"), drop = FALSE])),
    run_records = if (!is.null(record_data)) lapply(seq_len(nrow(record_data)), function(i) as.list(record_data[i, , drop = FALSE])) else list(),
    diagnostic_metadata = if (!is.null(diagnostic_data)) lapply(seq_len(nrow(diagnostic_data)), function(i) as.list(diagnostic_data[i, , drop = FALSE])) else list(),
    adapter_patterns = list(registry = list(), promotion_records = list()), pattern_candidates = list(), pattern_evidence = list(),
    promotion = list(
      status = "candidate", engine_change = "not_promoted", minimum_evidence = "at_least_2_independent_studies",
      human_approval_required = TRUE, regression_tests_required = TRUE, automatic_engine_modification = FALSE
    )
  )
  validate_standard_case_summary(summary)
  summary
}

write_standard_case_summary <- function(paths, contract, output_path) {
  if (!requireNamespace("yaml", quietly = TRUE)) stop("缺少 yaml package。")
  summary <- standard_case_summary(paths, contract)
  validate_standard_case_summary(summary)
  yaml::write_yaml(summary, output_path)
  invisible(summary)
}
