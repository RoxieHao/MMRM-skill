standard_mmrm_profile_version <- function() "standard-mmrm-profile/v1"

# SAS execution profile 只声明生成 SAS 代码时假定的目标运行环境能力。
# 本流水线不执行 SAS：无论有无 ADaM 数据，SAS 一律只作为代码交付，由统计师自行运行。
# 因此这里不存在"生成前必须先由生成器在 SAS 上跑通"的 qualification 闸门；
# 能力声明为 FALSE 才会阻断需要该能力的生成路径。
sas_execution_profile_registry <- function() list(
  `sas-9.4m5-self-contained/v1` = list(minimum_version = "SAS 9.4M5", encoding = "UTF-8", fcmp = TRUE, bit_operations = TRUE, sha256 = TRUE, csv_writer = "UTF-8 BOM data-step writer", generator_executes_sas = FALSE)
)
standard_validate_execution_context <- function(context, label = "execution_context") {
  standard_assert_keys(context, c("profile_version", "data_availability", "data_classification", "intended_use", "sas_execution_profile"), character(), label)
  if (!identical(context$profile_version, standard_mmrm_profile_version())) stop("PLAN-SCHEMA-PROFILE: unsupported profile_version.")
  if (!identical(context$sas_execution_profile, "sas-9.4m5-self-contained/v1") || is.null(sas_execution_profile_registry()[[context$sas_execution_profile]])) stop("PLAN-SCHEMA-SAS-EXECUTION-PROFILE: unsupported sas_execution_profile.")
  if (!context$data_availability %in% c("none", "available") || !context$data_classification %in% c("none", "dummy", "production", "unknown") || !context$intended_use %in% c("code_generation", "technical_validation", "formal_analysis")) stop("PLAN-SCHEMA-CONTEXT: execution context enum invalid.")
  valid <- (context$data_availability == "none" && context$data_classification == "none" && context$intended_use == "code_generation") || (context$data_availability == "available" && context$data_classification %in% c("dummy", "production", "unknown"))
  if (!valid || (context$data_classification == "unknown" && context$intended_use != "code_generation") || (context$intended_use == "formal_analysis" && context$data_classification != "production") || (context$intended_use == "technical_validation" && !context$data_classification %in% c("dummy", "production"))) stop("PLAN-SCHEMA-CONTEXT: incompatible availability/classification/intended_use.")
  invisible(TRUE)
}

standard_contract_sha256 <- function(path) {
  if (!requireNamespace("digest", quietly = TRUE)) stop("digest package is required.")
  toupper(digest::digest(file = path, algo = "sha256"))
}

standard_assert_named_list <- function(x, context) {
  if (!is.list(x) || is.null(names(x)) || any(!nzchar(names(x))) || anyDuplicated(names(x))) stop(context, " must be a mapping with unique nonempty keys.")
  invisible(TRUE)
}
standard_assert_keys <- function(x, required, optional = character(), context) {
  standard_assert_named_list(x, context)
  missing <- setdiff(required, names(x)); unknown <- setdiff(names(x), c(required, optional))
  if (length(missing)) stop(context, " missing keys: ", paste(missing, collapse = ", "))
  if (length(unknown)) stop(context, " unknown keys: ", paste(unknown, collapse = ", "))
  invisible(TRUE)
}
standard_scalar_character <- function(x, context, nonempty = TRUE) {
  ok <- is.character(x) && length(x) == 1L && !is.na(x) && (!nonempty || nzchar(trimws(x)))
  if (!ok) stop(context, " must be a ", if (nonempty) "nonempty " else "", "string.")
  x
}
standard_scalar_logical <- function(x, context) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) stop(context, " must be true/false.")
  x
}
standard_project_relative_path <- function(x, context) {
  x <- gsub("\\\\", "/", standard_scalar_character(x, context))
  if (grepl("^[A-Za-z]:/|^/|(^|/)\\.\\.(/|$)", x)) stop(context, " must be project-relative and may not contain '..'.")
  x
}
standard_validate_sas_v7_name <- function(x, context) {
  value <- standard_scalar_character(x, context)
  if (nchar(value, type = "chars") > 32L || !grepl("^[A-Za-z_][A-Za-z0-9_]*$", value)) stop(context, " must be a safe SAS V7 identifier of at most 32 characters.")
  invisible(TRUE)
}
standard_validate_predicate <- function(predicate, context) {
  standard_assert_keys(predicate, c("variable", "operator"), "value", context)
  standard_validate_sas_v7_name(predicate$variable, paste0(context, ".variable"))
  operator <- standard_scalar_character(predicate$operator, paste0(context, ".operator")); allowed <- c("eq", "ne", "in", "not_in", "gt", "ge", "lt", "le", "is_missing", "not_missing")
  if (!operator %in% allowed) stop(context, ".operator is invalid: ", operator)
  requires <- !operator %in% c("is_missing", "not_missing"); has <- "value" %in% names(predicate)
  if (requires && (!has || is.null(predicate$value))) stop(context, " requires value.")
  if (!requires && has) stop(context, " must omit value.")
  if (!requires) return(invisible(TRUE))
  value <- predicate$value; unnamed <- is.atomic(value) && is.null(names(value))
  if (operator %in% c("eq", "ne") && (!unnamed || length(value) != 1L || is.na(value))) stop(context, ".value must be one non-NA atomic scalar.")
  if (operator %in% c("in", "not_in") && (!unnamed || !length(value) || anyNA(value))) stop(context, ".value must be a nonempty atomic sequence without NA.")
  if (operator %in% c("gt", "ge", "lt", "le") && (!is.numeric(value) || length(value) != 1L || !is.finite(value))) stop(context, ".value must be one finite numeric scalar.")
  invisible(TRUE)
}
standard_validate_output_file <- function(value, context) {
  value <- standard_project_relative_path(value, context)
  if (grepl("/", value, fixed = TRUE) || !grepl("[.]csv$", value, ignore.case = TRUE)) stop(context, " must be a CSV filename in the analysis tables directory.")
  invisible(TRUE)
}
standard_validate_treatment <- function(treatment, context) {
  standard_assert_keys(treatment, c("variable", "levels", "reference", "comparator", "contrast_direction", "confidence_level", "multiplicity_adjustment"), character(), context)
  standard_validate_sas_v7_name(treatment$variable, paste0(context, ".variable"))
  levels <- treatment$levels
  if (!is.character(levels) || length(levels) != 2L || !is.null(names(levels)) || anyNA(levels) || any(!nzchar(trimws(levels))) || anyDuplicated(levels)) stop(context, ".levels must contain exactly two unique nonempty levels.")
  if (!identical(levels, c(treatment$reference, treatment$comparator))) stop(context, ".levels must be ordered reference then comparator.")
  if (!identical(treatment$contrast_direction, "comparator_minus_reference") || !identical(as.numeric(treatment$confidence_level), 0.95) || !identical(treatment$multiplicity_adjustment, "none")) stop(context, " contains unsupported treatment semantics.")
  invisible(TRUE)
}
standard_validate_endpoint_values <- function(x, context) {
  if (!is.character(x) || !is.null(names(x)) || !length(x) || anyNA(x) || any(!nzchar(trimws(x))) || anyDuplicated(x)) stop(context, " must be a unique nonempty character sequence.")
  invisible(TRUE)
}
standard_validate_endpoint_dimension <- function(dimension, context) {
  standard_assert_keys(dimension, c("variable", "values"), character(), context); variable <- standard_scalar_character(dimension$variable, paste0(context, ".variable")); values <- dimension$values
  if (identical(variable, "not_applicable")) { if (length(values) || !is.null(names(values))) stop(context, " not_applicable requires empty values.")
  } else if (identical(variable, "fixed")) { standard_validate_endpoint_values(values, paste0(context, ".values")); if (length(values) != 1L) stop(context, " fixed requires one value.")
  } else { standard_validate_sas_v7_name(variable, paste0(context, ".variable")); standard_validate_endpoint_values(values, paste0(context, ".values")) }
  invisible(TRUE)
}
standard_validate_endpoint_definition <- function(definition, context, has_adapter) {
  standard_assert_keys(definition, c("group_id", "endpoint_variable", "selected_codes", "selection_mode", "dimensions", "row_allocation_rule"), "non_overlap_allocation_proof", context)
  standard_validate_id(definition$group_id, paste0(context, ".group_id")); standard_validate_sas_v7_name(definition$endpoint_variable, paste0(context, ".endpoint_variable")); standard_validate_endpoint_values(definition$selected_codes, paste0(context, ".selected_codes"))
  if (!definition$selection_mode %in% c("single_code", "mutually_exclusive_versions", "approved_derivation")) stop(context, ".selection_mode invalid.")
  if (definition$selection_mode == "single_code" && length(definition$selected_codes) != 1L) stop(context, " single_code requires one code.")
  standard_assert_keys(definition$dimensions, c("instrument", "version", "reporter", "subscale"), character(), paste0(context, ".dimensions")); invisible(lapply(names(definition$dimensions), function(name) standard_validate_endpoint_dimension(definition$dimensions[[name]], paste0(context, ".dimensions.", name))))
  if (!identical(definition$row_allocation_rule, "one_row_per_subject_endpoint_visit")) stop(context, ".row_allocation_rule unsupported.")
  if (definition$selection_mode == "mutually_exclusive_versions" && definition$dimensions$version$variable %in% c("not_applicable", "fixed")) stop(context, " requires a data-driven version dimension.")
  if (definition$selection_mode == "approved_derivation" && (!has_adapter || !identical(definition$non_overlap_allocation_proof, "one_row_per_subject_endpoint_visit"))) stop(context, " approved_derivation requires pinned adapter and proof.")
  invisible(TRUE)
}
standard_endpoint_predicate_equivalent <- function(predicates, definition) {
  matches <- Filter(function(x) identical(x$variable, definition$endpoint_variable), predicates); if (length(matches) != 1L) return(FALSE); predicate <- matches[[1L]]; codes <- definition$selected_codes
  if (length(codes) == 1L) identical(predicate$operator, "eq") && identical(as.character(predicate$value), codes) else identical(predicate$operator, "in") && setequal(as.character(predicate$value), codes) && length(predicate$value) == length(codes)
}

standard_validate_contract_approval <- function(approval, context = "contract.approval") {
  standard_assert_keys(approval, c("review_file", "review_sha256", "analysis_plan_file", "analysis_plan_sha256", "approval_payload_sha256", "source_evidence_sha256", "reviewed_by", "approved_at_utc"), character(), context)
  for (name in c("review_file", "analysis_plan_file")) standard_project_relative_path(approval[[name]], paste0(context, ".", name))
  for (name in c("review_sha256", "analysis_plan_sha256", "approval_payload_sha256", "source_evidence_sha256")) if (!grepl("^[A-Fa-f0-9]{64}$", standard_scalar_character(approval[[name]], paste0(context, ".", name)))) stop(context, ".", name, " invalid.")
  standard_scalar_character(approval$reviewed_by, paste0(context, ".reviewed_by")); if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", approval$approved_at_utc)) stop(context, ".approved_at_utc invalid.")
  invisible(TRUE)
}
standard_contract_safe_identity <- function(value) gsub("[^A-Za-z0-9_-]+", "_", as.character(value))
standard_contract_output_names <- function() c("r_raw_file", "r_final_file", "r_diagnostic_file", "r_run_record_file", "sas_raw_file", "sas_final_file", "sas_diagnostic_file", "sas_run_record_file")
standard_contract_expected_output <- function(tfl_id) {
  safe <- standard_contract_safe_identity(tfl_id)
  setNames(lapply(c("r_raw", "r_final", "r_diagnostic", "r_run_record", "sas_raw", "sas_final", "sas_diagnostic", "sas_run_record"), function(suffix) paste0(safe, "_", suffix, ".csv")), standard_contract_output_names())
}
standard_contract_collision_values <- function(values) {
  normalized <- tolower(as.character(values)); unique(as.character(values)[duplicated(normalized) | duplicated(normalized, fromLast = TRUE)])
}
# Phase 5 只消费 Phase 1 已验证的八字段 output closed shape，不新增也不放宽 schema。
# 在把 contract 接入 program generation 之前，逐 analysis 再次断言：
#   1. output 恰好是八个有序字段（旧 shape 直接阻断，不提供任何 compatibility fallback）；
#   2. 八个文件名逐字等于从安全化 TFL identity 机械派生的结果；
#   3. 八个文件名两两不覆盖，且跨 analysis 也不覆盖（大小写不敏感）。
standard_contract_legacy_output_names <- function() c("raw_file", "final_file", "diagnostic_file", "run_record_file", "log_file", "qc_file", "model_file")
standard_contract_assert_output_closed_shape <- function(contract) {
  if (!is.list(contract) || !is.list(contract$analyses) || !length(contract$analyses)) stop("PLAN-SCHEMA-IDENTITY-OUTPUT-CLOSED-SHAPE: contract.analyses must be a nonempty sequence before program generation.")
  expected_names <- standard_contract_output_names(); all_files <- character()
  for (i in seq_along(contract$analyses)) {
    analysis <- contract$analyses[[i]]; context <- paste0("contract.analyses[[", i, "]].output"); output <- analysis$output
    if (!is.list(output) || is.null(names(output)) || anyDuplicated(names(output))) stop("PLAN-SCHEMA-IDENTITY-OUTPUT-CLOSED-SHAPE: ", context, " must be a mapping with unique keys.")
    legacy <- intersect(names(output), standard_contract_legacy_output_names())
    if (length(legacy)) stop("PLAN-SCHEMA-IDENTITY-OUTPUT-LEGACY-SHAPE: ", context, " uses the removed output shape (", paste(legacy, collapse = ", "), "); the eight-field closed shape is required and no compatibility fallback exists.")
    if (!identical(names(output), expected_names)) stop("PLAN-SCHEMA-IDENTITY-OUTPUT-CLOSED-SHAPE: ", context, " must declare exactly these ordered fields: ", paste(expected_names, collapse = ", "), ".")
    for (name in expected_names) standard_validate_output_file(output[[name]], paste0(context, ".", name))
    safe <- standard_contract_safe_identity(standard_scalar_character(analysis$tfl_id, paste0("contract.analyses[[", i, "]].tfl_id")))
    if (!identical(output, standard_contract_expected_output(analysis$tfl_id))) stop("PLAN-SCHEMA-IDENTITY-OUTPUT-CLOSED-SHAPE: ", context, " must be mechanically derived from the safe TFL identity ", safe, ".")
    overlap <- standard_contract_collision_values(unlist(output, use.names = FALSE))
    if (length(overlap)) stop("PLAN-SCHEMA-IDENTITY-OUTPUT-CLOSED-SHAPE: ", context, " filenames overlap pairwise: ", paste(overlap, collapse = ", "))
    all_files <- c(all_files, unlist(output, use.names = FALSE))
  }
  global_overlap <- standard_contract_collision_values(all_files)
  if (length(global_overlap)) stop("PLAN-SCHEMA-IDENTITY-OUTPUT-CLOSED-SHAPE: output filenames overlap across analyses: ", paste(global_overlap, collapse = ", "))
  invisible(TRUE)
}
standard_contract_assert_global_identity_uniqueness <- function(contract) {
  analyses <- contract$analyses
  categories <- list(
    analysis_id = vapply(analyses, `[[`, character(1), "analysis_id"),
    tfl_id = vapply(analyses, `[[`, character(1), "tfl_id"),
    program_filename = unlist(lapply(analyses, function(x) { safe <- standard_contract_safe_identity(x$analysis_id); c(paste0(safe, ".R"), paste0(safe, ".sas")) }), use.names = FALSE),
    output_directory = vapply(analyses, function(x) standard_contract_safe_identity(x$analysis_id), character(1)),
    output_filename = unlist(lapply(analyses, function(x) unlist(x$output, use.names = FALSE)), use.names = FALSE)
  )
  collisions <- unlist(lapply(names(categories), function(name) { values <- standard_contract_collision_values(categories[[name]]); if (length(values)) paste0(name, "=[", paste(values, collapse = ", "), "]") else character() }), use.names = FALSE)
  if (length(collisions)) stop("PLAN-SCHEMA-IDENTITY-COLLISION: ", paste(collisions, collapse = "; "))
  invisible(TRUE)
}
validate_standard_mmrm_contract <- function(contract) {
  standard_assert_keys(contract, c("contract_schema_version", "profile_version", "study", "execution", "approval", "analyses"), character(), "contract")
  if (!identical(contract$contract_schema_version, "2.1")) stop("PLAN-SCHEMA-CONTRACT-VERSION: contract_schema_version must be 2.1.")
  if (!identical(contract$profile_version, standard_mmrm_profile_version())) stop("Unsupported contract profile_version.")
  standard_assert_keys(contract$study, "study_id", character(), "contract.study"); standard_validate_id(contract$study$study_id, "contract.study.study_id")
  standard_assert_keys(contract$execution, c("data_availability", "data_classification", "intended_use", "sas_execution_profile", "fail_fast"), character(), "contract.execution")
  standard_validate_execution_context(c(list(profile_version = contract$profile_version), contract$execution[c("data_availability", "data_classification", "intended_use", "sas_execution_profile")]), "contract.execution")
  if (isTRUE(standard_scalar_logical(contract$execution$fail_fast, "contract.execution.fail_fast"))) stop("contract.execution.fail_fast must be false.")
  standard_validate_contract_approval(contract$approval)
  standard_sequence(contract$analyses, "contract.analyses", TRUE)
  for (i in seq_along(contract$analyses)) {
    analysis <- contract$analyses[[i]]; context <- paste0("contract.analyses[[", i, "]]" )
    validate_standard_analysis_definition(analysis, contract$execution, context, contract = TRUE)
    expected <- standard_contract_expected_output(analysis$tfl_id)
    if (!identical(analysis$output, expected)) stop("PLAN-SCHEMA-IDENTITY-OUTPUT: ", context, ".output must be mechanically derived from safe tfl_id.")
  }
  standard_contract_assert_global_identity_uniqueness(contract)
  invisible(TRUE)
}
standard_contract_fail_fast <- function(contract) { validate_standard_mmrm_contract(contract); FALSE }
standard_resolve_fail_fast <- function(contract, cli_value = NULL) { validate_standard_mmrm_contract(contract); if (isTRUE(cli_value)) stop("Standard MMRM collector requires fail_fast=false."); FALSE }
write_standard_mmrm_contract <- function(contract, path) { validate_standard_mmrm_contract(contract); dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE); yaml::write_yaml(contract, path); invisible(path) }
read_standard_mmrm_contract <- function(path) { if (!file.exists(path)) stop("Execution contract not found: ", path); contract <- yaml::read_yaml(path, eval.expr = FALSE); validate_standard_mmrm_contract(contract); attr(contract, "path") <- normalizePath(path, winslash = "/", mustWork = TRUE); attr(contract, "sha256") <- standard_contract_sha256(path); contract }
standard_contract_catalog <- function(contract) {
  validate_standard_mmrm_contract(contract)
  do.call(rbind, lapply(contract$analyses, function(x) data.frame(
    analysis_id = x$analysis_id, safe_analysis_id = standard_contract_safe_identity(x$analysis_id), tfl_id = x$tfl_id, title = x$title,
    dataset_binding_mode = x$dataset$binding_mode, dataset_file = x$dataset$file, dataset_format = x$dataset$format,
    dataset_relative_path = if (is.null(x$dataset$relative_path)) NA_character_ else x$dataset$relative_path,
    dataset_sha256 = if (is.null(x$dataset$sha256)) NA_character_ else toupper(x$dataset$sha256),
    adapter_file = if (is.null(x$adapter_file)) "" else x$adapter_file, adapter_sha256 = if (is.null(x$adapter_sha256)) "" else toupper(x$adapter_sha256), stringsAsFactors = FALSE
  )))
}
standard_contract_get_analysis <- function(contract, analysis_id) { validate_standard_mmrm_contract(contract); matches <- which(vapply(contract$analyses, function(x) identical(x$analysis_id, analysis_id), logical(1))); if (length(matches) != 1L) stop("Contract must contain exactly one analysis_id: ", analysis_id); contract$analyses[[matches]] }
