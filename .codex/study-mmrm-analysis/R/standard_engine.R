standard_allowed_run_status <- function() c("complete", "partial", "blocked_mapping", "blocked_environment", "blocked_data", "fit_failed")
standard_terminal_failure_status <- function() c("blocked_mapping", "blocked_environment", "blocked_data", "fit_failed")
standard_allowed_failure_domain <- function() c("none", "approval", "contract", "adapter", "environment", "data_mapping", "data", "fit", "inference")
standard_status_for_failure_domain <- function(domain) {
  switch(
    domain,
    approval = "blocked_mapping", contract = "blocked_mapping", adapter = "blocked_mapping", data_mapping = "blocked_mapping",
    environment = "blocked_environment", data = "blocked_data", fit = "fit_failed", inference = "fit_failed",
    stop("unknown failure_domain: ", domain)
  )
}
standard_allowed_risk <- function() c("Not assessed", "Green", "Yellow", "Red")

standard_raw_result_schema <- function() {
  data.frame(
    analysis_id = character(), tfl_id = character(), analysis_group_id = character(),
    analysis_group_label = character(), estimand = character(), treatment = character(),
    contrast = character(), visit = character(), emmean = numeric(), SE = numeric(), df = numeric(),
    lower.CL = numeric(), upper.CL = numeric(), t.ratio = numeric(), p.value = numeric(),
    covariance_used = character(), status = character(), model_rds = character(),
    stringsAsFactors = FALSE
  )
}

standard_final_result_schema <- function() {
  data.frame(
    analysis_id = character(), tfl_id = character(), analysis_group_id = character(),
    analysis_group_label = character(), row_type = character(), estimand = character(),
    treatment = character(), contrast = character(), visit = character(),
    observed_n = character(), observed_mean = character(), observed_sd = character(),
    observed_median = character(), observed_min = character(), observed_max = character(),
    baseline_n = character(), baseline_mean = character(), baseline_sd = character(),
    mmrm_estimate = character(), standard_error = character(), confidence_interval_95 = character(),
    degrees_of_freedom = character(), statistic = character(), p_value = character(),
    covariance_used = character(), status = character(), model_rds = character(),
    stringsAsFactors = FALSE
  )
}

standard_diagnostic_schema <- function() {
  data.frame(
    invocation_id = character(), run_id = character(), study_id = character(), analysis_id = character(),
    analysis_group_id = character(), profile_version = character(), review_sha256 = character(),
    analysis_plan_sha256 = character(), approval_payload_sha256 = character(), contract_sha256 = character(), covariance_path = character(), final_covariance = character(),
    fallback_used = character(), convergence_status = character(), inference_complete = character(),
    failure_domain = character(), failure_phase = character(), computational_risk = character(),
    risk_reason = character(), warning_summary = character(),
    input_rows = integer(), population_filtered_rows = integer(), analysis_rows = integer(), missing_required_rows = integer(),
    subject_count = integer(), visit_level_count = integer(), treatment_level_count = integer(),
    run_status = character(), model_file = character(), log_file = character(),
    stringsAsFactors = FALSE
  )
}

standard_recode_audit_schema <- function() {
  data.frame(
    invocation_id = character(), run_id = character(), study_id = character(), analysis_id = character(),
    profile_version = character(), review_sha256 = character(), analysis_plan_sha256 = character(),
    approval_payload_sha256 = character(), contract_sha256 = character(),
    recode_id = character(), source_variable = character(), target_variable = character(), value_type = character(),
    input_count = integer(), matched_count = integer(), unmatched_count = integer(), missing_count = integer(),
    output_missing_count = integer(), unmatched_policy = character(), missing_policy = character(),
    stringsAsFactors = FALSE
  )
}

# Build an identity-bound aggregate recode audit from derivation diagnostics. Only aggregate
# match/missing/policy counts are retained; no subject-level or per-value data is persisted.
standard_build_recode_audit <- function(derivation_diagnostics, identity) {
  if (!is.list(derivation_diagnostics) || !length(derivation_diagnostics)) return(standard_recode_audit_schema())
  do.call(rbind, lapply(derivation_diagnostics, function(d) {
    data.frame(
      invocation_id = identity$invocation_id, run_id = identity$run_id, study_id = identity$study_id, analysis_id = identity$analysis_id,
      profile_version = identity$profile_version, review_sha256 = identity$review_sha256, analysis_plan_sha256 = identity$analysis_plan_sha256,
      approval_payload_sha256 = identity$approval_payload_sha256, contract_sha256 = identity$contract_sha256,
      recode_id = as.character(d$id), source_variable = as.character(d$source_variable), target_variable = as.character(d$target_variable),
      value_type = as.character(d$value_type), input_count = as.integer(d$input_count), matched_count = as.integer(d$matched_count),
      unmatched_count = as.integer(d$unmatched_count), missing_count = as.integer(d$missing_count), output_missing_count = as.integer(d$output_missing_count),
      unmatched_policy = as.character(d$unmatched_policy), missing_policy = as.character(d$missing_policy), stringsAsFactors = FALSE
    )
  }))
}

standard_run_record_schema <- function() {
  data.frame(
    invocation_id = character(), run_id = character(), study_id = character(), analysis_id = character(),
    profile_version = character(), review_sha256 = character(), analysis_plan_sha256 = character(),
    approval_payload_sha256 = character(), contract_sha256 = character(), tfl_id = character(),
    tfl_type = character(), title = character(), scope_status = character(), output_status = character(),
    computational_risk = character(), raw_output_file = character(), final_tfl_file = character(),
    diagnostic_file = character(), diagnostic_report = character(), log_file = character(),
    stringsAsFactors = FALSE
  )
}

standard_apply_predicate <- function(data, predicate) {
  standard_validate_predicate(predicate, "runtime predicate")
  variable <- predicate$variable
  if (!variable %in% names(data)) stop("predicate variable does not exist: ", variable)
  x <- data[[variable]]
  operator <- predicate$operator
  keep <- switch(
    operator,
    eq = x == predicate$value,
    ne = x != predicate$value,
    "in" = x %in% unlist(predicate$value, use.names = FALSE),
    not_in = !x %in% unlist(predicate$value, use.names = FALSE),
    gt = x > predicate$value,
    ge = x >= predicate$value,
    lt = x < predicate$value,
    le = x <= predicate$value,
    is_missing = is.na(x) | trimws(as.character(x)) == "",
    not_missing = !is.na(x) & trimws(as.character(x)) != "",
    stop("unsupported predicate operator: ", operator)
  )
  keep[is.na(keep)] <- FALSE
  keep
}

standard_recode_count_list <- function(values) {
  labels <- ifelse(is.na(values), "<MISSING>", ifelse(is.character(values) & !nzchar(trimws(values)), "<BLANK>", as.character(values)))
  counts <- table(labels, useNA = "no")
  as.list(setNames(as.integer(counts), names(counts)))
}

standard_apply_derivations <- function(data, derivations) {
  if (!length(derivations)) { attr(data, "derivation_diagnostics") <- list(); return(data) }
  diagnostics <- list()
  for (i in seq_along(derivations)) {
    ir <- standard_normalize_recode(derivations[[i]])
    source <- data[[ir$source_variable]]
    if (is.null(source)) stop("PLAN-DERIVATION-RUNTIME: source variable missing: ", ir$source_variable)
    if (ir$target_variable %in% names(data)) stop("PLAN-DERIVATION-RUNTIME: target variable already exists: ", ir$target_variable)
    observed <- source[!is.na(source)]
    if (length(observed) && !identical(standard_recode_value_family(observed[[1L]]), ir$value_type)) stop("PLAN-DERIVATION-RUNTIME: source type differs from approved normalized recode type in ", ir$id)
    target <- switch(ir$value_type, character = rep(NA_character_, length(source)), numeric = rep(NA_real_, length(source)), logical = rep(NA, length(source)), stop("PLAN-DERIVATION-RUNTIME: unsupported normalized type."))
    matched <- rep(FALSE, length(source)); missing <- is.na(source) | (is.character(source) & !nzchar(trimws(source)))
    for (level in ir$levels) { hit <- !missing & source %in% unlist(level$source_values, use.names = FALSE); target[hit] <- level$target_value; matched <- matched | hit }
    unmatched <- !missing & !matched
    if (any(unmatched) && ir$unmatched == "error") stop("PLAN-DERIVATION-RUNTIME: unmatched values in ", ir$id)
    if (any(missing) && ir$missing == "error") stop("PLAN-DERIVATION-RUNTIME: missing values in ", ir$id)
    if (ir$unmatched == "preserve") target[unmatched] <- source[unmatched]
    if (ir$missing == "preserve") target[missing] <- source[missing]
    data[[ir$target_variable]] <- target
    output_missing <- is.na(target) | (is.character(target) & !nzchar(trimws(target)))
    diagnostics[[ir$id]] <- list(id = ir$id, source_variable = ir$source_variable, target_variable = ir$target_variable, value_type = ir$value_type, input_count = length(source), matched_count = sum(matched), unmatched_count = sum(unmatched), missing_count = sum(missing), output_missing_count = sum(output_missing), unmatched_policy = ir$unmatched, missing_policy = ir$missing, input_value_counts = standard_recode_count_list(source), output_value_counts = standard_recode_count_list(target))
  }
  attr(data, "derivation_diagnostics") <- diagnostics
  data
}

standard_filter_rows <- function(data, predicates) {
  if (length(predicates) == 0L) return(data)
  keep <- rep(TRUE, nrow(data))
  for (predicate in predicates) keep <- keep & standard_apply_predicate(data, predicate)
  data[keep, , drop = FALSE]
}

standard_load_adapter <- function(project_dir, adapter_file, adapter_sha256 = NULL) {
  if (is.null(adapter_file)) return(NULL)
  adapter_path <- normalize_project_relative_path(adapter_file, project_dir, "adapter_file")
  if (!file.exists(adapter_path)) stop("adapter_file does not exist: ", adapter_file)
  if (!requireNamespace("digest", quietly = TRUE)) stop("digest package is required to validate adapter_file.")
  expected_sha <- toupper(as.character(adapter_sha256))
  if (!grepl("^[A-F0-9]{64}$", expected_sha)) stop("adapter_sha256 invalid: ", adapter_file)
  actual_sha <- toupper(digest::digest(file = adapter_path, algo = "sha256"))
  if (!identical(actual_sha, expected_sha)) stop("adapter_file SHA-256 mismatch against contract: ", adapter_file)
  environment <- new.env(parent = baseenv())
  sys.source(adapter_path, envir = environment)
  if (!exists("standard_mmrm_adapter", envir = environment, mode = "function", inherits = FALSE)) {
    stop("adapter_file must define standard_mmrm_adapter(data, analysis, context).")
  }
  get("standard_mmrm_adapter", envir = environment, inherits = FALSE)
}

standard_prepare_analysis_data <- function(raw, analysis, project_dir) {
  adapter <- standard_load_adapter(project_dir, analysis$adapter_file, analysis$adapter_sha256)
  if (!is.null(adapter)) {
    raw <- adapter(raw, analysis, list(project_dir = project_dir, profile_version = standard_mmrm_profile_version()))
    if (!is.data.frame(raw)) stop("standard_mmrm_adapter must return a data.frame.")
    raw <- as.data.frame(raw, stringsAsFactors = FALSE, check.names = FALSE)
  }
  input_rows <- nrow(raw)
  raw <- standard_apply_derivations(raw, if (is.null(analysis$derivations)) list() else analysis$derivations)
  derivation_diagnostics <- attr(raw, "derivation_diagnostics")
  filtered <- standard_filter_rows(raw, analysis$filters)
  population_filtered_rows <- nrow(filtered)
  filtered$.standard_source_row_id <- seq_len(nrow(filtered))
  mappings <- analysis$mappings
  required_variables <- unique(unname(unlist(mappings, use.names = FALSE)))
  missing_columns <- setdiff(required_variables, names(filtered))
  if (length(missing_columns)) stop("mapping variables missing: ", paste(missing_columns, collapse = ", "))

  endpoint_allocation_error <- function(...) stop("PLAN-ENDPOINT-ALLOCATION: ", paste0(..., collapse = ""))
  group_selections <- lapply(analysis$groups, function(group) {
    definitions <- Filter(function(definition) identical(definition$group_id, group$id), analysis$endpoint_definitions)
    if (length(definitions) != 1L) endpoint_allocation_error("group ", group$id, " must have exactly one endpoint_definition.")
    definition <- definitions[[1L]]
    dimensions <- definition$dimensions
    applicable_dimensions <- Filter(function(dimension) !dimension$variable %in% c("not_applicable", "fixed"), dimensions)
    required_endpoint_columns <- c(as.character(definition$endpoint_variable), vapply(applicable_dimensions, function(dimension) as.character(dimension$variable), character(1)))
    missing_endpoint_columns <- setdiff(required_endpoint_columns, names(filtered))
    if (length(missing_endpoint_columns)) {
      endpoint_allocation_error("group ", group$id, " endpoint/dimension variables missing: ", paste(missing_endpoint_columns, collapse = ", "))
    }

    group_data <- standard_filter_rows(filtered, group$predicates)
    for (dimension_name in names(applicable_dimensions)) {
      dimension <- applicable_dimensions[[dimension_name]]
      variable <- as.character(dimension$variable)
      observed <- as.character(group_data[[variable]][!is.na(group_data[[variable]])])
      unapproved <- setdiff(unique(observed), as.character(dimension$values))
      if (length(unapproved)) {
        endpoint_allocation_error("group ", group$id, " endpoint dimension ", dimension_name, " (", variable,
          ") contains unapproved values: ", paste(unapproved, collapse = ", "))
      }
    }
    list(group = group, data = group_data)
  })
  allocation <- do.call(rbind, lapply(group_selections, function(selection) {
    data.frame(source_row_id = selection$data$.standard_source_row_id, group_id = selection$group$id, stringsAsFactors = FALSE)
  }))
  duplicate_source_rows <- unique(allocation$source_row_id[duplicated(allocation$source_row_id) | duplicated(allocation$source_row_id, fromLast = TRUE)])
  if (length(duplicate_source_rows)) {
    allocations <- vapply(duplicate_source_rows, function(source_row_id) {
      paste0(source_row_id, "=[", paste(allocation$group_id[allocation$source_row_id == source_row_id], collapse = ", "), "]")
    }, character(1))
    endpoint_allocation_error("source row allocated to multiple groups: ", paste(allocations, collapse = "; "))
  }

  pieces <- lapply(group_selections, function(selection) {
    group <- selection$group
    group_data <- selection$data
    if (nrow(group_data) == 0L) return(NULL)
    data.frame(
      subject = as.character(group_data[[mappings$subject]]),
      response = suppressWarnings(as.numeric(group_data[[mappings$response]])),
      baseline = suppressWarnings(as.numeric(group_data[[mappings$baseline]])),
      visit = group_data[[mappings$visit]],
      visit_label = if (is.null(mappings$visit_label)) as.character(group_data[[mappings$visit]]) else as.character(group_data[[mappings$visit_label]]),
      treatment = if (is.null(mappings$treatment)) "" else as.character(group_data[[mappings$treatment]]),
      analysis_group_id = group$id,
      analysis_group_label = group$label,
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
  })
  pieces <- pieces[!vapply(pieces, is.null, logical(1))]
  if (length(pieces) == 0L) stop("approved filters/groups produced no data.")
  data <- do.call(rbind, pieces)
  required_complete <- c("subject", "response", "baseline", "visit")
  if (!is.null(mappings$treatment)) required_complete <- c(required_complete, "treatment")
  complete <- stats::complete.cases(data[required_complete]) & nzchar(trimws(data$subject))
  if (!is.null(mappings$treatment)) complete <- complete & nzchar(trimws(data$treatment))
  missing_required_rows <- sum(!complete)
  data <- data[complete, , drop = FALSE]
  if (nrow(data) == 0L) stop("no data after removing rows with missing required mappings.")

  inconsistent <- aggregate(baseline ~ subject + analysis_group_id, data, function(x) length(unique(x)))
  if (any(inconsistent$baseline > 1L)) stop("baseline inconsistent within subject/group.")
  duplicate <- duplicated(data[c("subject", "analysis_group_id", "visit")]) |
    duplicated(data[c("subject", "analysis_group_id", "visit")], fromLast = TRUE)
  if (any(duplicate)) stop("subject/group/visit must be unique.")

  visit_levels <- unique(data[c("visit", "visit_label")])
  numeric_visit <- suppressWarnings(as.numeric(as.character(visit_levels$visit)))
  ordering <- if (all(!is.na(numeric_visit))) order(numeric_visit) else order(as.character(visit_levels$visit))
  visit_levels <- visit_levels[ordering, , drop = FALSE]
  if (anyDuplicated(as.character(visit_levels$visit))) stop("one visit value maps to multiple visit_label values.")
  data$subject_f <- factor(data$subject)
  data$visit_f <- factor(as.character(data$visit), levels = as.character(visit_levels$visit))
  if (is.null(mappings$treatment)) {
    data$treatment_f <- factor(rep("ALL", nrow(data)), levels = "ALL")
  } else {
    approved_levels <- analysis$treatment$levels
    observed_levels <- unique(data$treatment)
    unapproved <- setdiff(observed_levels, approved_levels)
    if (length(unapproved)) stop("observed treatment not in approved levels: ", paste(unapproved, collapse = ", "))
    if (!all(approved_levels %in% observed_levels)) stop("both approved treatment levels must exist in analysis data.")
    data$treatment_f <- factor(data$treatment, levels = approved_levels)
  }
  attr(data, "input_rows") <- input_rows
  attr(data, "derivation_diagnostics") <- derivation_diagnostics
  attr(data, "population_filtered_rows") <- population_filtered_rows
  attr(data, "missing_required_rows") <- missing_required_rows
  data
}

standard_covariance_term <- function(covariance) {
  function_name <- switch(covariance, UN = "us", AR1 = "ar1", CS = "cs", TOEP = "toep", stop("unsupported covariance."))
  paste0(function_name, "(visit_f | subject_f)")
}

standard_fixed_formula <- function(analysis, covariance) {
  fixed_map <- c(
    visit = "visit_f", baseline = "baseline", baseline_by_visit = "baseline:visit_f",
    treatment = "treatment_f", treatment_by_visit = "treatment_f:visit_f"
  )
  fixed <- unname(fixed_map[as.character(unlist(analysis$fixed_effects, use.names = FALSE))])
  stats::as.formula(paste("response ~", paste(c(fixed, standard_covariance_term(covariance)), collapse = " + ")))
}

standard_formula_text <- function(formula) paste(deparse(formula, width.cutoff = 500L), collapse = " ")

standard_mmrm_control <- function(analysis, covariance) {
  args <- list(method = analysis$df_method)
  if (identical(analysis$df_method, "Kenward-Roger") && identical(covariance, "UN")) args$vcov <- "Kenward-Roger-Linear"
  do.call(mmrm::mmrm_control, args)
}

standard_summary_rows <- function(summary_data, analysis, group_id, group_label, estimand, covariance, model_file,
                                  treatment_col = NULL, contrast_col = NULL) {
  data <- as.data.frame(summary_data, stringsAsFactors = FALSE)
  visit_col <- intersect(c("visit_f", "visit"), names(data))
  if (length(visit_col) != 1L) stop("emmeans output must contain exactly one visit column.")
  numeric_column <- function(name) if (name %in% names(data)) as.numeric(data[[name]]) else rep(NA_real_, nrow(data))
  data.frame(
    analysis_id = analysis$analysis_id,
    tfl_id = analysis$tfl_id,
    analysis_group_id = group_id,
    analysis_group_label = group_label,
    estimand = estimand,
    treatment = if (is.null(treatment_col) || !treatment_col %in% names(data)) "" else as.character(data[[treatment_col]]),
    contrast = if (is.null(contrast_col) || !contrast_col %in% names(data)) "" else as.character(data[[contrast_col]]),
    visit = as.character(data[[visit_col]]),
    emmean = if ("emmean" %in% names(data)) as.numeric(data$emmean) else if ("estimate" %in% names(data)) as.numeric(data$estimate) else NA_real_,
    SE = numeric_column("SE"), df = numeric_column("df"), lower.CL = numeric_column("lower.CL"),
    upper.CL = numeric_column("upper.CL"), t.ratio = numeric_column("t.ratio"), p.value = numeric_column("p.value"),
    covariance_used = covariance, status = "complete", model_rds = model_file,
    stringsAsFactors = FALSE
  )
}

standard_fit_group_worker <- function(args) {
  Sys.setenv(OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1", VECLIB_MAXIMUM_THREADS = "1")
  if (!requireNamespace("mmrm", quietly = TRUE) || !requireNamespace("emmeans", quietly = TRUE)) stop("mmrm and emmeans packages are required.")
  data <- args$data
  analysis <- args$analysis
  group_id <- args$group_id
  group_label <- unique(data$analysis_group_label)[[1]]
  has_treatment <- "treatment" %in% names(analysis$mappings)
  if (length(unique(data$subject)) < 2L || nlevels(droplevels(data$visit_f)) < 2L) stop("subject or visit levels insufficient.")
  if (has_treatment && nlevels(droplevels(data$treatment_f)) < 2L) stop("treatment levels insufficient.")
  covariance_order <- c(analysis$covariance$primary, unlist(analysis$covariance$fallback, use.names = FALSE))
  attempts <- list()
  selected <- NULL
  selected_covariance <- ""
  all_warnings <- character()
  for (covariance in covariance_order) {
    warnings <- character()
    fit <- tryCatch(
      withCallingHandlers(
        mmrm::mmrm(standard_fixed_formula(analysis, covariance), data = data, reml = TRUE, control = standard_mmrm_control(analysis, covariance)),
        warning = function(w) { warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning") },
        message = function(m) { warnings <<- c(warnings, conditionMessage(m)); invokeRestart("muffleMessage") }
      ),
      error = function(e) e
    )
    nonconverged <- grepl("non.?converg|fail.*converg|optimizer.*fail|diverg", paste(warnings, collapse = " | "), ignore.case = TRUE, perl = TRUE)
    attempts[[covariance]] <- if (inherits(fit, "error")) paste0("failed: ", conditionMessage(fit)) else if (nonconverged) "not_converged" else "success"
    all_warnings <- c(all_warnings, warnings)
    if (!inherits(fit, "error") && !nonconverged) {
      selected <- fit
      selected_covariance <- covariance
      break
    }
  }
  covariance_path <- paste(vapply(names(attempts), function(name) paste0(name, "=", attempts[[name]]), character(1)), collapse = " -> ")
  if (is.null(selected)) stop("all approved covariance attempts failed: ", covariance_path)
  rows <- list()
  confidence_level <- if (has_treatment) analysis$treatment$confidence_level else 0.95
  visit_grid <- emmeans::emmeans(selected, ~ visit_f)
  rows[[length(rows) + 1L]] <- standard_summary_rows(
    summary(visit_grid, infer = c(TRUE, TRUE), level = confidence_level, adjust = "none"), analysis, group_id, group_label,
    "visit_lsmean", selected_covariance, args$model_relative
  )
  if (isTRUE(analysis$estimands$treatment_visit_lsmeans)) {
    treatment_grid <- emmeans::emmeans(selected, ~ treatment_f | visit_f)
    rows[[length(rows) + 1L]] <- standard_summary_rows(
      summary(treatment_grid, infer = c(TRUE, TRUE), level = analysis$treatment$confidence_level, adjust = "none"),
      analysis, group_id, group_label, "treatment_visit_lsmean", selected_covariance, args$model_relative,
      treatment_col = "treatment_f"
    )
    if (isTRUE(analysis$estimands$pairwise_differences)) {
      contrast_label <- paste0(analysis$treatment$comparator, " - ", analysis$treatment$reference)
      explicit_weights <- setNames(list(c(-1, 1)), contrast_label)
      comparison <- emmeans::contrast(treatment_grid, method = explicit_weights, by = "visit_f", adjust = "none")
      rows[[length(rows) + 1L]] <- standard_summary_rows(
        summary(comparison, infer = c(TRUE, TRUE), level = analysis$treatment$confidence_level, adjust = "none"),
        analysis, group_id, group_label, "treatment_pairwise_difference", selected_covariance,
        args$model_relative, contrast_col = "contrast"
      )
    }
  }
  result <- do.call(rbind, rows)
  inference_columns <- c("emmean", "SE", "df", "lower.CL", "upper.CL", "p.value")
  inference_complete <- nrow(result) > 0L && all(stats::complete.cases(result[inference_columns]))
  fallback <- !identical(selected_covariance, analysis$covariance$primary)
  status <- if (inference_complete && !fallback && length(all_warnings) == 0L) "complete" else "partial"
  result$status <- status
  risk <- if (!inference_complete) "Red" else if (fallback || length(all_warnings)) "Yellow" else "Green"
  identity <- args$artifact_identity
  identity$treatment_levels <- if (has_treatment) paste(analysis$treatment$levels, collapse = "|") else ""
  identity$treatment_reference <- if (has_treatment) analysis$treatment$reference else ""
  identity$treatment_comparator <- if (has_treatment) analysis$treatment$comparator else ""
  identity$contrast_direction <- if (has_treatment) analysis$treatment$contrast_direction else ""
  identity$confidence_level <- if (has_treatment) as.character(analysis$treatment$confidence_level) else ""
  identity$multiplicity_adjustment <- if (has_treatment) analysis$treatment$multiplicity_adjustment else ""
  identity$covariance <- selected_covariance
  identity$formula <- standard_formula_text(standard_fixed_formula(analysis, selected_covariance))
  attr(selected, "standard_artifact_identity") <- identity
  saveRDS(selected, args$model_path)
  list(
    results = result,
    covariance_path = covariance_path,
    final_covariance = selected_covariance,
    fallback_used = if (fallback) "yes" else "no",
    inference_complete = if (inference_complete) "yes" else "no",
    warnings = paste(unique(all_warnings), collapse = " | "),
    status = status,
    risk = risk,
    reason = if (!inference_complete) "inference fields incomplete." else if (fallback) "approved fallback covariance used." else if (length(all_warnings)) "model produced warning/message." else "model and inference complete."
  )
}

standard_highest_risk <- function(values) {
  rank <- c("Not assessed" = 0L, Green = 1L, Yellow = 2L, Red = 3L)
  values <- values[values %in% names(rank)]
  if (!length(values)) return("Not assessed")
  names(rank)[max(match(values, names(rank)))]
}

standard_collapse_status <- function(values) {
  if (!length(values)) return("blocked_mapping")
  values <- as.character(values)
  if (length(unique(values)) == 1L) return(values[[1]])
  "partial"
}

standard_format_number <- function(x, digits) {
  ifelse(is.na(x), "", formatC(as.numeric(x), format = "f", digits = digits))
}

standard_format_ci <- function(lower, upper) {
  ifelse(is.na(lower) | is.na(upper), "", paste0("(", standard_format_number(lower, 3L), ", ", standard_format_number(upper, 3L), ")"))
}

standard_format_p <- function(x) {
  ifelse(is.na(x), "", ifelse(as.numeric(x) < 0.0001, "<0.0001", standard_format_number(x, 4L)))
}

standard_shell_summary <- function(x) {
  present <- as.numeric(x)
  present <- present[!is.na(present)]
  n <- length(present)
  c(
    n = as.character(n),
    mean = if (n) standard_format_number(mean(present), 3L) else "",
    sd = if (n > 1L) standard_format_number(stats::sd(present), 3L) else "",
    median = if (n) standard_format_number(stats::median(present), 3L) else "",
    min = if (n) standard_format_number(min(present), 3L) else "",
    max = if (n) standard_format_number(max(present), 3L) else ""
  )
}

standard_build_shell_like_final <- function(raw, prepared, analysis, run_status) {
  if (is.null(prepared) || !nrow(prepared)) return(standard_final_result_schema())
  has_treatment <- "treatment" %in% names(analysis$mappings)
  pieces <- split(prepared, interaction(prepared[c("analysis_group_id", "treatment", "visit")], drop = TRUE, lex.order = TRUE), drop = TRUE)
  desc <- do.call(rbind, lapply(pieces, function(piece) {
    observed <- standard_shell_summary(piece$response)
    baseline <- standard_shell_summary(piece$baseline)
    data.frame(
      analysis_id = analysis$analysis_id, tfl_id = analysis$tfl_id,
      analysis_group_id = unique(piece$analysis_group_id)[[1]],
      analysis_group_label = unique(piece$analysis_group_label)[[1]],
      row_type = "observed_with_mmrm",
      estimand = if (has_treatment) "treatment_visit_lsmean" else "visit_lsmean",
      treatment = if (has_treatment) unique(piece$treatment)[[1]] else "",
      contrast = "", visit = unique(piece$visit_label)[[1]],
      visit_key = as.character(unique(piece$visit)[[1]]),
      observed_n = observed[["n"]], observed_mean = observed[["mean"]],
      observed_sd = observed[["sd"]], observed_median = observed[["median"]],
      observed_min = observed[["min"]], observed_max = observed[["max"]],
      baseline_n = baseline[["n"]], baseline_mean = baseline[["mean"]],
      baseline_sd = baseline[["sd"]], stringsAsFactors = FALSE
    )
  }))
  desc <- desc[order(desc$analysis_group_id, suppressWarnings(as.numeric(desc$visit_key)), desc$visit_key, desc$treatment), , drop = FALSE]
  final <- cbind(
    desc[setdiff(names(desc), "visit_key")],
    data.frame(
      mmrm_estimate = rep("", nrow(desc)), standard_error = rep("", nrow(desc)),
      confidence_interval_95 = rep("", nrow(desc)), degrees_of_freedom = rep("", nrow(desc)),
      statistic = rep("", nrow(desc)), p_value = rep("", nrow(desc)),
      covariance_used = rep("", nrow(desc)), status = rep(run_status, nrow(desc)),
      model_rds = rep("", nrow(desc)), stringsAsFactors = FALSE
    )
  )

  if (nrow(raw)) {
    lsmeans <- raw[raw$estimand %in% c("visit_lsmean", "treatment_visit_lsmean"), , drop = FALSE]
    for (i in seq_len(nrow(final))) {
      model <- lsmeans[
        as.character(lsmeans$analysis_group_id) == final$analysis_group_id[[i]] &
          as.character(lsmeans$visit) == desc$visit_key[[i]] &
          as.character(lsmeans$estimand) == final$estimand[[i]] &
          as.character(lsmeans$treatment) == final$treatment[[i]],
        , drop = FALSE
      ]
      if (nrow(model)) {
        model <- model[1L, , drop = FALSE]
        final$mmrm_estimate[[i]] <- standard_format_number(model$emmean, 3L)
        final$standard_error[[i]] <- standard_format_number(model$SE, 3L)
        final$confidence_interval_95[[i]] <- standard_format_ci(model$lower.CL, model$upper.CL)
        final$degrees_of_freedom[[i]] <- standard_format_number(model$df, 1L)
        final$statistic[[i]] <- standard_format_number(model$t.ratio, 3L)
        final$p_value[[i]] <- standard_format_p(model$p.value)
        final$covariance_used[[i]] <- as.character(model$covariance_used)
        final$status[[i]] <- as.character(model$status)
        final$model_rds[[i]] <- as.character(model$model_rds)
      }
    }

    contrasts <- raw[raw$estimand == "treatment_pairwise_difference", , drop = FALSE]
    if (nrow(contrasts)) {
      final <- rbind(final, data.frame(
        analysis_id = contrasts$analysis_id, tfl_id = contrasts$tfl_id,
        analysis_group_id = contrasts$analysis_group_id, analysis_group_label = contrasts$analysis_group_label,
        row_type = "mmrm_contrast", estimand = contrasts$estimand, treatment = contrasts$treatment,
        contrast = contrasts$contrast, visit = contrasts$visit,
        observed_n = "", observed_mean = "", observed_sd = "", observed_median = "",
        observed_min = "", observed_max = "", baseline_n = "", baseline_mean = "", baseline_sd = "",
        mmrm_estimate = standard_format_number(contrasts$emmean, 3L),
        standard_error = standard_format_number(contrasts$SE, 3L),
        confidence_interval_95 = standard_format_ci(contrasts$lower.CL, contrasts$upper.CL),
        degrees_of_freedom = standard_format_number(contrasts$df, 1L),
        statistic = standard_format_number(contrasts$t.ratio, 3L),
        p_value = standard_format_p(contrasts$p.value), covariance_used = contrasts$covariance_used,
        status = contrasts$status, model_rds = contrasts$model_rds, stringsAsFactors = FALSE
      ))
    }
  }
  final[names(standard_final_result_schema())]
}

standard_risk_label_cn <- function(risk) {
  switch(
    as.character(risk),
    Green = "\u4f4e\u98ce\u9669\uff1a\u6a21\u578b\u548c\u63a8\u65ad\u5b8c\u6574\u3002",
    Yellow = "\u4e2d\u7b49\u98ce\u9669\uff1a\u5b58\u5728 fallback\u3001warning/message \u6216\u90e8\u5206\u4e0d\u5b8c\u6574\uff0c\u9700\u8981\u590d\u6838\u3002",
    Red = "\u9ad8\u98ce\u9669\uff1a\u6a21\u578b\u6216\u63a8\u65ad\u5931\u8d25\uff0c\u4e0d\u5e94\u89e3\u91ca\u4e3a\u6b63\u5f0f\u4f30\u8ba1\u3002",
    "Not assessed" = "\u672a\u8bc4\u4f30\uff1a\u6a21\u578b\u672a\u6267\u884c\u6216\u524d\u7f6e gate \u963b\u65ad\u3002",
    paste0("\u672a\u77e5\u98ce\u9669\uff1a", as.character(risk))
  )
}

standard_sas_status <- function(analysis) {
  if (!is.null(analysis$adapter_file)) return("sas_adapter_required\uff1aR adapter \u6ca1\u6709\u9690\u5f0f SAS \u7b49\u4ef7\u5b9e\u73b0\uff0c\u6a21\u677f\u4fdd\u6301\u963b\u65ad\u3002")
  "template_generated_not_executed\uff1a\u5df2\u751f\u6210\u53ea\u8bfb SAS \u6a21\u677f\uff0c\u9ed8\u8ba4\u4e0d\u6267\u884c\u3002"
}

standard_write_report <- function(path, analysis, diagnostics, status, risk, chain, output_paths = NULL, project_dir = NULL) {
  rel <- function(value) {
    if (is.null(value) || is.null(project_dir) || !nzchar(value)) return("")
    project_relative_path(value, project_dir)
  }
  primary_covariance <- as.character(analysis$covariance$primary)
  fallback_covariance <- paste(as.character(unlist(analysis$covariance$fallback, use.names = FALSE)), collapse = " -> ")
  if (!nzchar(fallback_covariance)) fallback_covariance <- "\u65e0"
  report_path <- if (is.null(output_paths)) "" else rel(output_paths$diagnostic_report)
  diagnostic_csv <- if (is.null(output_paths)) "" else rel(output_paths$diagnostic_csv)
  log_file <- if (is.null(output_paths)) unique(as.character(diagnostics$log_file))[[1]] else rel(output_paths$log_file)
  manifest_path <- "output/tfl-output-manifest.csv"
  lines <- c(
    "# Standard MMRM \u8fd0\u884c\u8bca\u65ad\u62a5\u544a", "",
    "## \u57fa\u672c\u4fe1\u606f", "",
    paste0("- Study ID\uff1a`", chain$contract$study$study_id, "`"),
    paste0("- Analysis ID\uff1a`", analysis$analysis_id, "`"),
    paste0("- TFL ID\uff1a`", analysis$tfl_id, "`"),
    paste0("- \u6570\u636e\u7c7b\u522b\uff1a`", chain$plan$execution_context$data_classification, "`\uff1b\u7528\u9014\uff1a`", chain$plan$execution_context$intended_use, "`"),
    paste0("- Analysis plan SHA-256\uff1a`", toupper(attr(chain$plan, "sha256")), "`"),
    paste0("- Approval payload SHA-256\uff1a`", toupper(chain$approval_payload_sha256), "`"),
    paste0("- Contract SHA-256\uff1a`", toupper(chain$contract_sha256), "`"), "",
    "## \u6a21\u578b\u6267\u884c", "",
    paste0("- Primary covariance\uff1a`", primary_covariance, "`"),
    paste0("- Fallback \u987a\u5e8f\uff1a`", fallback_covariance, "`"),
    paste0("- Run status\uff1a`", status, "`"),
    paste0("- \u4e2d\u6587\u8ba1\u7b97\u98ce\u9669\uff1a", standard_risk_label_cn(risk), "\uff08\u673a\u5668\u7801 `", risk, "`\uff09"),
    paste0("- SAS status\uff1a", standard_sas_status(analysis)), "",
    "## \u8def\u5f84", "",
    paste0("- Formal manifest\uff1a`", manifest_path, "`"),
    paste0("- Diagnostic CSV\uff1a`", diagnostic_csv, "`"),
    paste0("- Diagnostic report\uff1a`", report_path, "`"),
    paste0("- Log\uff1a`", log_file, "`"), "",
    "## \u5206\u7ec4\u8bca\u65ad", "",
    "| \u5206\u7ec4 | \u6267\u884c\u8def\u5f84 | \u6700\u7ec8 covariance | \u6536\u655b | \u63a8\u65ad\u5b8c\u6574 | \u4e2d\u6587\u98ce\u9669 | \u5173\u6ce8\u4e8b\u9879 |",
    "|---|---|---|---|---|---|---|",
    vapply(seq_len(nrow(diagnostics)), function(i) paste0(
      "| `", diagnostics$analysis_group_id[[i]], "` | ", gsub("\\|", "\\\\|", diagnostics$covariance_path[[i]]),
      " | `", diagnostics$final_covariance[[i]], "` | `", diagnostics$convergence_status[[i]], "` | `",
      diagnostics$inference_complete[[i]], "` | ", standard_risk_label_cn(diagnostics$computational_risk[[i]]),
      " | ", gsub("\\|", "\\\\|", diagnostics$risk_reason[[i]]), " |"
    ), character(1))
  )
  writeLines(lines, path, useBytes = TRUE)
}

run_standard_mmrm_analysis_stage <- function(script_file, analysis_id, pinned_approval_payload_sha256,
                                             pinned_contract_sha256, stage, exchange_path, marker_path,
                                             run_id, invocation_id) {
  stage <- match.arg(stage, c("prepare", "fit"))
  project_dir <- find_project_dir(script_file)
  helper_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
  for (helper in c("study_paths.R", "io.R", "specification.R", "canonical_hash.R", "standard_contract.R", "standard_analysis_definition.R", "analysis_plan.R", "analysis_contract_generation.R", "analysis_approval.R", "runtime_dataset_binding.R")) source(file.path(helper_dir, helper), encoding = "UTF-8", local = environment())
  paths <- study_paths(script_file)

  preflight_domain <- "approval"
  preflight_phase <- "approved_analysis_chain_gate"
  preflight <- tryCatch({
    chain <- assert_approved_analysis(paths$study_dir, project_dir, expected_analysis_id = analysis_id, pinned_approval_payload_sha256 = pinned_approval_payload_sha256, pinned_contract_sha256 = pinned_contract_sha256)
    assert_analysis_execution_allowed(chain)
    analysis <- standard_contract_get_analysis(chain$contract, analysis_id)
    list(chain = chain, contract = chain$contract, contract_sha = chain$contract_sha256, analysis = analysis)
  }, error = function(e) e)
  if (inherits(preflight, "error")) {
    stop("Standard MMRM preflight failed [", preflight_domain, "/", preflight_phase, "]: ", conditionMessage(preflight))
  }

  chain <- preflight$chain
  contract <- preflight$contract
  contract_sha <- preflight$contract_sha
  analysis <- preflight$analysis
  output_paths <- analysis_output_paths(paths, analysis_id)
  if (identical(stage, "fit")) {
    invisible(lapply(output_paths[c("root", "tables", "figures", "listings", "models", "diagnostics", "logs")], dir.create, recursive = TRUE, showWarnings = FALSE))
    writeLines(character(), output_paths$log_file, useBytes = TRUE)
  }
  log_line <- function(...) {
    if (identical(stage, "fit")) {
      cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " | ", paste0(..., collapse = ""), "\n", file = output_paths$log_file, append = TRUE, sep = "")
    }
  }
  raw_path <- file.path(output_paths$tables, analysis$output$raw_file)
  final_path <- file.path(output_paths$tables, analysis$output$final_file)
  failure_domain <- "environment"
  failure_phase <- "runtime_package_gate"
  prepared_data <- NULL
  publish_exchange <- function(exchange) {
    temporary_exchange <- paste0(exchange_path, ".tmp-", Sys.getpid())
    on.exit(unlink(temporary_exchange, force = TRUE), add = TRUE)
    saveRDS(exchange, temporary_exchange, version = 3)
    if (file.exists(exchange_path) && !unlink(exchange_path, force = TRUE)) stop("Cannot replace stale MMRM stage exchange: ", exchange_path)
    if (!file.rename(temporary_exchange, exchange_path)) stop("Cannot atomically publish MMRM stage exchange: ", exchange_path)
    writeLines("complete", marker_path, useBytes = TRUE)
    invisible(exchange_path)
  }

  outcome <- tryCatch({
    if (identical(stage, "fit") && !requireNamespace("callr", quietly = TRUE)) {
      stop("callr package is required to run isolated MMRM workers.")
    }
    if (identical(stage, "prepare")) {
      failure_domain <- "adapter"
      failure_phase <- "approved_adapter_gate"
      standard_load_adapter(project_dir, analysis$adapter_file, analysis$adapter_sha256)
      failure_domain <- "data"
      failure_phase <- "linked_source_gate"
      raw_data <- read_linked_source_data(project_dir, file.path(paths$backup_trace_dir, "input-manifest.csv"), analysis$dataset)
      failure_phase <- "data_preparation_qc"
      prepared <- standard_prepare_analysis_data(raw_data, analysis, project_dir)
      prepared_data <<- prepared

      exchange <- list(
        schema_version = "1.0",
        analysis_id = analysis_id,
        review_sha256 = toupper(chain$review$sha256),
        analysis_plan_sha256 = toupper(attr(chain$plan, "sha256")),
        approval_payload_sha256 = toupper(chain$approval_payload_sha256),
        contract_sha256 = toupper(contract_sha),
        run_id = run_id,
        invocation_id = invocation_id,
        prepared = prepared
      )
      publish_exchange(exchange)
      return(invisible(list(stage = "prepare", rows = nrow(prepared))))
    }

    failure_domain <- "data"
    failure_phase <- "prepared_exchange_gate"
    if (!file.exists(marker_path) || !file.exists(exchange_path)) stop("Prepared MMRM stage exchange is incomplete.")
    exchange <- readRDS(exchange_path)
    required_exchange <- c("schema_version", "analysis_id", "review_sha256", "analysis_plan_sha256", "approval_payload_sha256", "contract_sha256", "run_id", "invocation_id", "prepared")
    if (!is.list(exchange) || any(!required_exchange %in% names(exchange))) stop("Prepared MMRM stage exchange schema is invalid.")
    if (!identical(exchange$schema_version, "1.0")) stop("Prepared MMRM stage exchange version is unsupported.")
    identity_ok <- identical(exchange$analysis_id, analysis_id) &&
      identical(toupper(exchange$review_sha256), toupper(chain$review$sha256)) &&
      identical(toupper(exchange$analysis_plan_sha256), toupper(attr(chain$plan, "sha256"))) &&
      identical(toupper(exchange$approval_payload_sha256), toupper(chain$approval_payload_sha256)) &&
      identical(toupper(exchange$contract_sha256), toupper(contract_sha)) &&
      identical(exchange$run_id, run_id) && identical(exchange$invocation_id, invocation_id)
    if (!identity_ok) stop("Prepared MMRM stage exchange identity does not match this run.")
    if (!is.null(exchange$prepare_error)) {
      failure_domain <- as.character(exchange$prepare_error$domain)
      failure_phase <- as.character(exchange$prepare_error$phase)
      stop(as.character(exchange$prepare_error$message))
    }
    prepared <- exchange$prepared
    if (!is.data.frame(prepared)) stop("Prepared MMRM stage exchange does not contain a data.frame.")
    prepared_data <<- prepared
    log_line("data preparation completed in isolated top-level stage; rows=", nrow(prepared), ".")

    failure_domain <- "contract"
    failure_phase <- "model_destination_gate"
    group_ids <- vapply(analysis$groups, `[[`, character(1), "id")
    model_names <- paste0(group_ids, "_mmrm.rds")
    if (anyDuplicated(tolower(model_names))) stop("approved group model destinations are not unique.")

    failure_domain <- "fit"
    failure_phase <- "isolated_group_fit"
    engine_file <- file.path(helper_dir, "standard_engine.R")
    results <- lapply(seq_along(group_ids), function(index) {
      group_id <- group_ids[[index]]
      group_data <- prepared[prepared$analysis_group_id == group_id, , drop = FALSE]
      model_path <- file.path(output_paths$models, model_names[[index]])
      model_relative <- project_relative_path(model_path, project_dir)
      if (!nrow(group_data)) return(list(error = "approved group has no rows in analysis data.", group_id = group_id, model_relative = model_relative))
      log_line("start isolated fit group=", group_id, ".")
      worker <- tryCatch(callr::r(
        function(worker_args) {
          source(worker_args$engine_file, encoding = "UTF-8")
          standard_fit_group_worker(worker_args)
        },
        args = list(list(
          engine_file = engine_file, data = group_data, analysis = analysis, group_id = group_id,
          model_path = model_path, model_relative = model_relative,
          artifact_identity = list(
            study_id = as.character(contract$study$study_id), analysis_id = analysis_id, group_id = group_id,
            profile = standard_mmrm_profile_version(), profile_version = standard_mmrm_profile_version(),
            review_sha256 = toupper(chain$review$sha256), analysis_plan_sha256 = toupper(attr(chain$plan, "sha256")),
            approval_payload_sha256 = toupper(chain$approval_payload_sha256), contract_sha256 = toupper(contract_sha),
            adapter_sha256 = if (is.null(analysis$adapter_sha256)) "" else toupper(analysis$adapter_sha256),
            run_id = run_id, invocation_id = invocation_id
          )
        )), spinner = FALSE, show = FALSE
      ), error = function(e) e)
      log_line("isolated fit returned group=", group_id, "; error=", inherits(worker, "error"), ".")
      if (inherits(worker, "error")) list(error = conditionMessage(worker), group_id = group_id, model_relative = model_relative) else worker
    })

    raw_parts <- lapply(results, function(x) if (is.null(x$error)) x$results else NULL)
    raw_parts <- raw_parts[!vapply(raw_parts, is.null, logical(1))]
    raw_result <- if (length(raw_parts)) do.call(rbind, raw_parts) else standard_raw_result_schema()
    diagnostics <- do.call(rbind, lapply(seq_along(results), function(i) {
      item <- results[[i]]
      group_id <- group_ids[[i]]
      group_data <- prepared[prepared$analysis_group_id == group_id, , drop = FALSE]
      failed <- !is.null(item$error)
      data.frame(
        invocation_id = invocation_id, run_id = run_id, study_id = contract$study$study_id,
        analysis_id = analysis_id, analysis_group_id = group_id, profile_version = standard_mmrm_profile_version(),
        review_sha256 = toupper(chain$review$sha256), analysis_plan_sha256 = toupper(attr(chain$plan, "sha256")),
        approval_payload_sha256 = toupper(chain$approval_payload_sha256), contract_sha256 = toupper(contract_sha),
        covariance_path = if (failed) "not_fitted" else item$covariance_path,
        final_covariance = if (failed) "" else item$final_covariance,
        fallback_used = if (failed) "no" else item$fallback_used,
        convergence_status = if (failed) "not_converged" else "converged",
        inference_complete = if (failed) "no" else item$inference_complete,
        failure_domain = if (failed) "fit" else "none", failure_phase = if (failed) "covariance_fit" else "completed",
        computational_risk = if (failed) "Red" else item$risk,
        risk_reason = if (failed) item$error else item$reason,
        warning_summary = if (failed) "" else item$warnings,
        input_rows = as.integer(attr(prepared, "input_rows")), population_filtered_rows = as.integer(attr(prepared, "population_filtered_rows")), analysis_rows = nrow(group_data),
        missing_required_rows = as.integer(attr(prepared, "missing_required_rows")),
        subject_count = length(unique(group_data$subject)), visit_level_count = length(unique(group_data$visit)),
        treatment_level_count = length(unique(group_data$treatment[group_data$treatment != ""])),
        run_status = if (failed) "fit_failed" else item$status,
        model_file = if (failed) "" else item$results$model_rds[[1]],
        log_file = project_relative_path(output_paths$log_file, project_dir), stringsAsFactors = FALSE
      )
    }))
    run_status <- standard_collapse_status(diagnostics$run_status)
    risk <- standard_highest_risk(diagnostics$computational_risk)
    log_line("diagnostics collapsed; status=", run_status, "; risk=", risk, ".")
    list(raw = raw_result, final = standard_build_shell_like_final(raw_result, prepared, analysis, run_status), diagnostics = diagnostics, status = run_status, risk = risk)
  }, error = function(e) {
    if (identical(stage, "prepare")) {
      exchange <- list(
        schema_version = "1.0",
        analysis_id = analysis_id,
        review_sha256 = toupper(chain$review$sha256),
        analysis_plan_sha256 = toupper(attr(chain$plan, "sha256")),
        approval_payload_sha256 = toupper(chain$approval_payload_sha256),
        contract_sha256 = toupper(contract_sha),
        run_id = run_id,
        invocation_id = invocation_id,
        prepared = NULL,
        prepare_error = list(domain = failure_domain, phase = failure_phase, message = conditionMessage(e))
      )
      publish_exchange(exchange)
      return(invisible(list(stage = "prepare", error = conditionMessage(e))))
    }
    if (grepl("PLAN-DERIVATION|PLAN-ENDPOINT-ALLOCATION", conditionMessage(e), ignore.case = TRUE)) {
      failure_domain <- "data_mapping"
      failure_phase <- "endpoint_allocation_gate"
    }
    log_line("run failed [", failure_domain, "/", failure_phase, "]: ", conditionMessage(e))
    status <- standard_status_for_failure_domain(failure_domain)
    risk <- if (failure_domain %in% c("fit", "inference")) "Red" else "Not assessed"
    diagnostics <- standard_diagnostic_schema()[0, ]
    diagnostics[1, ] <- data.frame(
      invocation_id = invocation_id, run_id = run_id, study_id = as.character(contract$study$study_id), analysis_id = analysis_id,
      analysis_group_id = "ALL", profile_version = standard_mmrm_profile_version(), review_sha256 = toupper(chain$review$sha256),
      analysis_plan_sha256 = toupper(attr(chain$plan, "sha256")), approval_payload_sha256 = toupper(chain$approval_payload_sha256),
      contract_sha256 = toupper(contract_sha), covariance_path = "not_fitted", final_covariance = "", fallback_used = "no",
      convergence_status = "not_assessed", inference_complete = "no", failure_domain = failure_domain,
      failure_phase = failure_phase, computational_risk = risk, risk_reason = conditionMessage(e), warning_summary = "",
      input_rows = 0L, population_filtered_rows = 0L, analysis_rows = 0L, missing_required_rows = 0L, subject_count = 0L, visit_level_count = 0L,
      treatment_level_count = 0L, run_status = status, model_file = "",
      log_file = project_relative_path(output_paths$log_file, project_dir), stringsAsFactors = FALSE
    )
    list(raw = standard_raw_result_schema(), final = standard_build_shell_like_final(standard_raw_result_schema(), prepared_data, analysis, status), diagnostics = diagnostics, status = status, risk = risk)
  })

  if (identical(stage, "prepare")) return(invisible(outcome))

  log_line("writing analysis artifacts.")
  write_utf8_bom_csv(outcome$raw, raw_path)
  write_utf8_bom_csv(outcome$final, final_path)
  write_utf8_bom_csv(outcome$diagnostics, output_paths$diagnostic_csv)
  recode_identity <- list(
    invocation_id = invocation_id, run_id = run_id, study_id = as.character(contract$study$study_id), analysis_id = analysis_id,
    profile_version = standard_mmrm_profile_version(), review_sha256 = toupper(chain$review$sha256),
    analysis_plan_sha256 = toupper(attr(chain$plan, "sha256")), approval_payload_sha256 = toupper(chain$approval_payload_sha256),
    contract_sha256 = toupper(contract_sha)
  )
  recode_diagnostics <- if (is.null(prepared_data)) list() else attr(prepared_data, "derivation_diagnostics")
  if (is.null(recode_diagnostics)) recode_diagnostics <- list()
  write_utf8_bom_csv(standard_build_recode_audit(recode_diagnostics, recode_identity), output_paths$recode_audit)
  report_error <- tryCatch({
    standard_write_report(output_paths$diagnostic_report, analysis, outcome$diagnostics, outcome$status, outcome$risk, chain, output_paths, project_dir)
    NULL
  }, error = function(e) e)
  if (inherits(report_error, "error")) {
    log_line("diagnostic report rendering failed: ", conditionMessage(report_error), "; writing minimal report.")
    writeLines(c("# Standard MMRM \u8fd0\u884c\u8bca\u65ad\u62a5\u544a", "", paste0("- Analysis ID\uff1a`", analysis_id, "`"), paste0("- Run status\uff1a`", outcome$status, "`"), paste0("- Report rendering error: ", conditionMessage(report_error))), output_paths$diagnostic_report, useBytes = TRUE)
  }
  record <- standard_run_record_schema()[0, ]
  record[1, ] <- list(
    invocation_id, run_id, as.character(contract$study$study_id), analysis_id, standard_mmrm_profile_version(),
    toupper(chain$review$sha256), toupper(attr(chain$plan, "sha256")), toupper(chain$approval_payload_sha256),
    toupper(contract_sha), analysis$tfl_id, "table", analysis$title, "approved", outcome$status, outcome$risk,
    project_relative_path(raw_path, project_dir), project_relative_path(final_path, project_dir),
    project_relative_path(output_paths$diagnostic_csv, project_dir), project_relative_path(output_paths$diagnostic_report, project_dir),
    project_relative_path(output_paths$log_file, project_dir)
  )
  write_utf8_bom_csv(record, output_paths$run_record)
  log_line("run finished; status=", outcome$status, "; risk=", outcome$risk, ".")
  if (outcome$status %in% standard_terminal_failure_status()) stop("Standard MMRM analysis \u7ec8\u6b62\u5931\u8d25\uff1astatus=", outcome$status)
  invisible(outcome)
}


standard_shell_quote_windows <- function(value) {
  paste0('"', gsub('"', '""', as.character(value), fixed = TRUE), '"')
}

standard_write_stage_launcher <- function(path, rscript, runner, stage_arguments) {
  prepare_arguments <- c("--stage=prepare", stage_arguments)
  fit_arguments <- c("--stage=fit", stage_arguments)
  if (.Platform$OS.type == "windows") {
    quote_windows <- function(values) vapply(values, standard_shell_quote_windows, character(1))
    prepare_command <- paste(c(standard_shell_quote_windows(rscript), "--vanilla", standard_shell_quote_windows(runner), quote_windows(prepare_arguments)), collapse = " ")
    fit_command <- paste(c(standard_shell_quote_windows(rscript), "--vanilla", standard_shell_quote_windows(runner), quote_windows(fit_arguments)), collapse = " ")
    writeLines(c(
      "@echo off",
      "setlocal",
      prepare_command,
      "if errorlevel 1 exit /b %errorlevel%",
      fit_command,
      "exit /b %errorlevel%"
    ), path, useBytes = TRUE)
  } else {
    quote_sh <- function(values) vapply(values, shQuote, character(1))
    prepare_command <- paste(c(shQuote(rscript), "--vanilla", shQuote(runner), quote_sh(prepare_arguments)), collapse = " ")
    fit_command <- paste(c(shQuote(rscript), "--vanilla", shQuote(runner), quote_sh(fit_arguments)), collapse = " ")
    writeLines(c("#!/bin/sh", "set -e", prepare_command, fit_command), path, useBytes = TRUE)
  }
  invisible(path)
}

run_standard_mmrm_analysis <- function(script_file, analysis_id, pinned_approval_payload_sha256, pinned_contract_sha256) {
  project_dir <- find_project_dir(script_file)
  runner <- file.path(project_dir, ".codex", "study-mmrm-analysis", "scripts", "run_standard_mmrm_stage.R")
  if (!file.exists(runner)) stop("Standard MMRM stage runner is missing: ", runner)

  rscript_name <- if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
  rscript <- file.path(R.home("bin"), rscript_name)
  if (!file.exists(rscript)) stop("Cannot locate current Rscript: ", rscript)

  run_id <- paste0(format(Sys.time(), "%Y%m%d-%H%M%S"), "-", analysis_id, "-", Sys.getpid())
  invocation_arg <- grep("^--collector-invocation-id=", commandArgs(trailingOnly = TRUE), value = TRUE)
  invocation_id <- if (length(invocation_arg) == 1L) sub("^--collector-invocation-id=", "", invocation_arg) else paste0("standalone-", run_id)

  exchange_dir <- tempfile(paste0("mmrm-stage-", analysis_id, "-"))
  if (!dir.create(exchange_dir, recursive = TRUE, showWarnings = FALSE)) stop("Cannot create MMRM stage exchange directory: ", exchange_dir)
  on.exit(unlink(exchange_dir, recursive = TRUE, force = TRUE), add = TRUE)
  exchange_path <- file.path(exchange_dir, "prepared.rds")
  marker_path <- file.path(exchange_dir, "prepared.complete")
  launcher_extension <- if (.Platform$OS.type == "windows") ".cmd" else ".sh"
  launcher_path <- file.path(exchange_dir, paste0("run-stages", launcher_extension))

  stage_arguments <- c(
    paste0("--script-file=", normalizePath(script_file, winslash = "/", mustWork = TRUE)),
    paste0("--analysis-id=", analysis_id),
    paste0("--approval-payload-sha256=", pinned_approval_payload_sha256),
    paste0("--contract-sha256=", pinned_contract_sha256),
    paste0("--exchange=", normalizePath(exchange_path, winslash = "/", mustWork = FALSE)),
    paste0("--marker=", normalizePath(marker_path, winslash = "/", mustWork = FALSE)),
    paste0("--run-id=", run_id),
    paste0("--invocation-id=", invocation_id)
  )
  standard_write_stage_launcher(launcher_path, normalizePath(rscript, winslash = "/", mustWork = TRUE), normalizePath(runner, winslash = "/", mustWork = TRUE), stage_arguments)

  status <- tryCatch({
    if (.Platform$OS.type == "windows") {
      comspec <- Sys.getenv("COMSPEC", unset = "cmd.exe")
      suppressWarnings(system2(comspec, c("/d", "/s", "/c", shQuote(launcher_path)), wait = TRUE))
    } else {
      suppressWarnings(system2("/bin/sh", shQuote(launcher_path), wait = TRUE))
    }
  }, error = function(e) structure(1L, stage_error = conditionMessage(e)))
  stage_error <- attr(status, "stage_error")
  status <- as.integer(status)
  if (!identical(status, 0L)) {
    detail <- if (is.null(stage_error)) "see stage output above" else stage_error
    stop("Standard MMRM top-level stage launcher failed (exit=", status, "): ", detail)
  }
  invisible(TRUE)
}
