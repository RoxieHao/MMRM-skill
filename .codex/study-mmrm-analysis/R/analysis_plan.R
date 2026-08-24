analysis_plan_path <- function(study_dir) file.path(study_dir, "statistician-review", "analysis-plan.yaml")
analysis_plan_trace_keys <- function() c("dataset", "adapter", "mappings", "derivations", "filters", "groups", "endpoint_definitions", "fixed_effects", "reml", "covariance", "df_method", "estimands", "treatment")

analysis_plan_validate_execution_context <- function(context) standard_validate_execution_context(context, "analysis_plan.execution_context")

analysis_plan_validate_trace <- function(analysis, valid_trace_ids = NULL, context = "analysis") {
  trace <- analysis$trace; standard_assert_keys(trace, analysis_plan_trace_keys(), character(), paste0(context, ".trace"))
  nonempty <- c(dataset = TRUE, adapter = !is.null(analysis$adapter), mappings = TRUE, derivations = length(analysis$derivations) > 0L, filters = length(analysis$filters) > 0L, groups = length(analysis$groups) > 0L, endpoint_definitions = length(analysis$endpoint_definitions) > 0L, fixed_effects = length(analysis$fixed_effects) > 0L, reml = TRUE, covariance = TRUE, df_method = TRUE, estimands = TRUE, treatment = !is.null(analysis$treatment))
  for (name in names(trace)) {
    refs <- if (!length(trace[[name]])) character() else unlist(trace[[name]], use.names = FALSE)
    if (!is.character(refs) || !is.null(names(trace[[name]])) || anyNA(refs) || any(!grepl("^[A-Za-z][A-Za-z0-9_./-]*$", refs)) || anyDuplicated(refs)) stop("PLAN-TRACE-MALFORMED: ", context, ".trace.", name, " must be a unique stable-ID sequence.")
    if (nonempty[[name]] && !length(refs)) stop("PLAN-TRACE-MISSING: ", context, ".trace.", name, " requires at least one reference.")
    if (!nonempty[[name]] && length(refs)) stop("PLAN-TRACE-ORPHAN: ", context, ".trace.", name, " must be empty when its field is empty/absent.")
    if (!is.null(valid_trace_ids) && any(!refs %in% valid_trace_ids)) stop("PLAN-TRACE-UNRESOLVED: ", context, ".trace.", name, " references unknown IDs: ", paste(setdiff(refs, valid_trace_ids), collapse = ", "))
  }
  invisible(TRUE)
}

validate_analysis_plan <- function(plan, valid_trace_ids = NULL) {
  standard_assert_keys(plan, c("analysis_plan_schema_version", "study_id", "execution_context", "analyses"), character(), "analysis_plan")
  if (identical(plan$analysis_plan_schema_version, "2.0")) stop("PLAN-SCHEMA-VERSION-MIGRATION: analysis plan 2.0 must be migrated to 2.1 and re-approved; compatibility defaults are forbidden.")
  if (!identical(plan$analysis_plan_schema_version, "2.1")) stop("PLAN-SCHEMA-VERSION: analysis_plan_schema_version must be 2.1.")
  standard_validate_id(plan$study_id, "analysis_plan.study_id"); analysis_plan_validate_execution_context(plan$execution_context)
  standard_sequence(plan$analyses, "analysis_plan.analyses", TRUE)
  ids <- tfl_ids <- character()
  for (i in seq_along(plan$analyses)) {
    analysis <- plan$analyses[[i]]; context <- paste0("analysis_plan.analyses[[", i, "]]" )
    validate_standard_analysis_definition(analysis, plan$execution_context, context, contract = FALSE); analysis_plan_validate_trace(analysis, valid_trace_ids, context)
    ids[[i]] <- analysis$analysis_id; tfl_ids[[i]] <- analysis$source_tfl_id
  }
  if (anyDuplicated(ids)) stop("PLAN-SCHEMA-IDENTITY: analysis_id must be unique.")
  if (anyDuplicated(tfl_ids)) stop("PLAN-SCHEMA-IDENTITY: source_tfl_id must be unique.")
  invisible(TRUE)
}

analysis_plan_normalize <- function(plan, valid_trace_ids = NULL) {
  validate_analysis_plan(plan, valid_trace_ids)
  plan$analyses <- lapply(plan$analyses, function(analysis) {
    if (!is.null(analysis$dataset$sha256)) analysis$dataset$sha256 <- toupper(analysis$dataset$sha256)
    if (!is.null(analysis$adapter)) analysis$adapter$sha256 <- toupper(analysis$adapter$sha256)
    analysis
  })
  plan
}

read_analysis_plan <- function(path, valid_trace_ids = NULL) {
  if (!file.exists(path)) stop("PLAN-SCHEMA-READ: analysis-plan.yaml not found: ", path)
  if (!requireNamespace("yaml", quietly = TRUE)) stop("yaml package is required.")
  plan <- yaml::read_yaml(path, eval.expr = FALSE)
  plan <- analysis_plan_normalize(plan, valid_trace_ids)
  attr(plan, "path") <- normalizePath(path, winslash = "/", mustWork = TRUE)
  attr(plan, "sha256") <- canonical_sha256(plan)
  plan
}
analysis_plan_sha256 <- function(plan) canonical_sha256(analysis_plan_normalize(plan))
analysis_plan_write <- function(plan, path) { dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE); yaml::write_yaml(plan, path); invisible(path) }

analysis_plan_empty_dimensions <- function() list(instrument = list(variable = "not_applicable", values = list()), version = list(variable = "not_applicable", values = list()), reporter = list(variable = "not_applicable", values = list()), subscale = list(variable = "not_applicable", values = list()))
analysis_plan_template_analysis <- function(analysis_id, source_tfl_id, title) {
  list(analysis_id = analysis_id, source_tfl_id = source_tfl_id, title = title,
       dataset = list(binding_mode = NULL, file = NULL, format = NULL, relative_path = NULL, sha256 = NULL), adapter = NULL,
       mappings = list(subject = NULL, response = NULL, baseline = NULL, visit = NULL), derivations = list(), filters = list(), groups = list(), endpoint_definitions = list(),
       fixed_effects = list(), reml = TRUE, covariance = list(primary = NULL, fallback = list()), df_method = NULL,
       estimands = list(visit_lsmeans = NULL, treatment_visit_lsmeans = NULL, pairwise_differences = NULL), treatment = NULL,
       trace = setNames(rep(list(list()), length(analysis_plan_trace_keys())), analysis_plan_trace_keys()))
}
analysis_plan_template <- function(study_id, tfls = list()) {
  analyses <- lapply(seq_along(tfls), function(i) analysis_plan_template_analysis(paste0("MMRM-", sprintf("%02d", i)), as.character(tfls[[i]]$tfl_id), as.character(tfls[[i]]$title)))
  list(analysis_plan_schema_version = "2.1", study_id = study_id, execution_context = list(profile_version = standard_mmrm_profile_version(), data_availability = NULL, data_classification = NULL, intended_use = NULL, sas_execution_profile = "sas-9.4m5-self-contained/v1"), analyses = analyses)
}
analysis_plan_render_lines <- function(plan) c("```yaml", strsplit(yaml::as.yaml(plan), "\n", fixed = TRUE)[[1]], "```")
