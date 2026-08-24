program_section_titles <- function() c(
  "第 1 部分：程序说明与用户配置",
  "第 2 部分：运行环境与安全检查",
  "第 3 部分：读取 ADaM 数据",
  "第 4 部分：数据处理与质量控制",
  "第 5 部分：MMRM 模型拟合",
  "第 6 部分：统计推断",
  "第 7 部分：TFL 结果整理与导出",
  "第 8 部分：诊断信息与运行记录"
)

program_assert_section <- function(number, title) {
  titles <- program_section_titles()
  if (!is.numeric(number) || length(number) != 1L || is.na(number) || number != as.integer(number) || number < 1L || number > length(titles)) stop("PROGRAM-SECTION-NUMBER: number must be an integer from 1 through 8.")
  if (!is.character(title) || length(title) != 1L || is.na(title) || !identical(title, titles[[as.integer(number)]])) stop("PROGRAM-SECTION-TITLE: title must be the fixed title for section ", as.integer(number), ".")
  invisible(TRUE)
}

render_r_section_header <- function(number, title) {
  program_assert_section(number, title)
  paste("# ==============================================================================", paste0("# ", title), "# ==============================================================================", sep = "\n")
}

render_sas_section_header <- function(number, title) {
  program_assert_section(number, title)
  paste("/* =============================================================================", paste0("   ", title), "   ========================================================================== */", sep = "\n")
}

program_r_string_literal <- function(value, context = "string") {
  if (!is.character(value) || length(value) != 1L || is.na(value) || is.na(iconv(value, from = "UTF-8", to = "UTF-8")) || grepl("\\x00", value)) stop("PROGRAM-R-LITERAL:", context)
  paste0('"', gsub('"', '\\\\"', gsub("\\\\", "\\\\\\\\", value)), '"')
}

program_sas_string_literal <- function(value, context = "string") {
  if (!is.character(value) || length(value) != 1L || is.na(value) || is.na(iconv(value, from = "UTF-8", to = "UTF-8")) || grepl("\\x00", value)) stop("PROGRAM-SAS-LITERAL:", context)
  paste0('"', gsub('"', '""', value, fixed = TRUE), '"')
}

program_validate_string_literals <- function(x, context = "ir") {
  if (is.character(x)) {
    for (i in seq_along(x)) {
      program_r_string_literal(x[[i]], paste0(context, "[[", i, "]]"))
      program_sas_string_literal(x[[i]], paste0(context, "[[", i, "]]"))
    }
  } else if (is.list(x)) {
    for (i in seq_along(x)) program_validate_string_literals(x[[i]], paste0(context, "[[", i, "]]"))
  }
  invisible(TRUE)
}

program_generation_semantic_registry <- function() list(
  recode = list(field_path = "derivations[].operation", r = "r.explicit_vector_recode.v1", sas = "sas.data_step_if_else_recode.v1"),
  filter = list(field_path = "filters[]", r = "r.logical_vector_filter.v1", sas = "sas.data_step_delete_filter.v1"),
  group_allocation = list(field_path = "groups[]", r = "r.boolean_group_allocation.v1", sas = "sas.data_step_group_allocation.v1"),
  baseline = list(field_path = "mappings.baseline", r = "r.numeric_baseline.v1", sas = "sas.numeric_baseline.v1"),
  visit = list(field_path = "mappings.visit", r = "r.factor_visit.v1", sas = "sas.class_visit.v1"),
  treatment_reference = list(field_path = "treatment.reference", r = "r.factor_reference.v1", sas = "sas.class_reference.v1"),
  reml = list(field_path = "reml", r = "r.mmrm_reml.v1", sas = "sas.proc_mixed_reml.v1"),
  UN = list(field_path = "covariance", r = "r.mmrm_covariance_us.v1", sas = "sas.proc_mixed_covariance_un.v1"),
  AR1 = list(field_path = "covariance", r = "r.mmrm_covariance_ar1.v1", sas = "sas.proc_mixed_covariance_ar1.v1"),
  CS = list(field_path = "covariance", r = "r.mmrm_covariance_cs.v1", sas = "sas.proc_mixed_covariance_cs.v1"),
  TOEP = list(field_path = "covariance", r = "r.mmrm_covariance_toep.v1", sas = "sas.proc_mixed_covariance_toep.v1"),
  `Kenward-Roger` = list(field_path = "df_method", r = "r.mmrm_control_kenward_roger.v1", sas = "sas.ddfm_kr.v1"),
  Satterthwaite = list(field_path = "df_method", r = "r.mmrm_control_satterthwaite.v1", sas = "sas.ddfm_satterth.v1"),
  lsmeans = list(field_path = "estimands", r = "r.emmeans_lsmeans.v1", sas = "sas.lsmeans_ods.v1"),
  pairwise_contrast = list(field_path = "estimands.pairwise_differences", r = "r.explicit_weight_contrast.v1", sas = "sas.control_direction_contrast.v1")
)

program_validate_semantic_registry <- function(registry, analysis_id) {
  expected <- names(program_generation_semantic_registry())
  if (!is.list(registry) || is.null(names(registry)) || anyDuplicated(names(registry)) || !setequal(names(registry), expected)) stop("PROGRAM-SEMANTIC-REGISTRY-CLOSED:", analysis_id)
  for (operation in expected) {
    entry <- registry[[operation]]
    path <- if (is.list(entry) && is.character(entry$field_path) && length(entry$field_path) == 1L && nzchar(entry$field_path)) entry$field_path else paste0("semantic_registry.", operation)
    for (language in c("r", "sas")) if (!is.list(entry) || !is.character(entry[[language]]) || length(entry[[language]]) != 1L || is.na(entry[[language]]) || !nzchar(entry[[language]])) stop("PROGRAM-SEMANTIC-REGISTRY-MISSING:", analysis_id, ":", path, ":", toupper(language))
  }
  invisible(TRUE)
}

program_registry_binding <- function(registry, operation, field_path, analysis_id) {
  entry <- registry[[operation]]
  for (language in c("r", "sas")) if (is.null(entry) || !is.character(entry[[language]]) || length(entry[[language]]) != 1L || !nzchar(entry[[language]])) stop("PROGRAM-SEMANTIC-REGISTRY-MISSING:", analysis_id, ":", field_path, ":", toupper(language))
  list(operation = operation, field_path = field_path, r = entry$r, sas = entry$sas)
}

program_unique_ordered <- function(values) values[!duplicated(values) & nzchar(values)]

program_source_variable_inventory <- function(analysis) {
  derivation_sources <- vapply(analysis$derivations, `[[`, character(1), "source_variable")
  derivation_targets <- vapply(analysis$derivations, `[[`, character(1), "target_variable")
  filter_variables <- vapply(analysis$filters, `[[`, character(1), "variable")
  group_variables <- unlist(lapply(analysis$groups, function(group) vapply(group$predicates, `[[`, character(1), "variable")), use.names = FALSE)
  endpoint_variables <- unlist(lapply(analysis$endpoint_definitions, function(definition) c(definition$endpoint_variable, vapply(definition$dimensions, `[[`, character(1), "variable"))), use.names = FALSE)
  candidates <- c(unname(unlist(analysis$mappings, use.names = FALSE)), derivation_sources, filter_variables, group_variables, endpoint_variables)
  original <- program_unique_ordered(setdiff(candidates, c(derivation_targets, "fixed", "not_applicable")))
  list(original = original, derived = unname(derivation_targets), available_after_derivations = program_unique_ordered(c(original, derivation_targets)))
}

program_semantic_bindings <- function(analysis, registry) {
  id <- analysis$analysis_id
  bindings <- list()
  add <- function(operation, path) { bindings[[length(bindings) + 1L]] <<- program_registry_binding(registry, operation, path, id) }
  for (i in seq_along(analysis$derivations)) add(analysis$derivations[[i]]$operation, paste0("contract.analyses[", id, "].derivations[[", i, "]].operation"))
  for (i in seq_along(analysis$filters)) add("filter", paste0("contract.analyses[", id, "].filters[[", i, "]]"))
  for (i in seq_along(analysis$groups)) add("group_allocation", paste0("contract.analyses[", id, "].groups[[", i, "]]"))
  add("baseline", paste0("contract.analyses[", id, "].mappings.baseline")); add("visit", paste0("contract.analyses[", id, "].mappings.visit"))
  if (!is.null(analysis$treatment)) add("treatment_reference", paste0("contract.analyses[", id, "].treatment.reference"))
  add("reml", paste0("contract.analyses[", id, "].reml"))
  for (value in c(analysis$covariance$primary, unlist(analysis$covariance$fallback, use.names = FALSE))) add(value, paste0("contract.analyses[", id, "].covariance"))
  add(analysis$df_method, paste0("contract.analyses[", id, "].df_method"))
  if (any(unlist(analysis$estimands[c("visit_lsmeans", "treatment_visit_lsmeans")], use.names = FALSE))) add("lsmeans", paste0("contract.analyses[", id, "].estimands"))
  if (isTRUE(analysis$estimands$pairwise_differences)) add("pairwise_contrast", paste0("contract.analyses[", id, "].estimands.pairwise_differences"))
  bindings
}

program_validate_identities <- function(identities, contract) {
  required <- c("plan_sha256", "approval_payload_sha256", "contract_sha256")
  if (!is.list(identities) || is.null(names(identities)) || anyDuplicated(names(identities)) || !identical(names(identities), required)) stop("PROGRAM-IDENTITY-SCHEMA: identities must contain plan_sha256, approval_payload_sha256, contract_sha256 in that order.")
  for (name in required) if (!is.character(identities[[name]]) || length(identities[[name]]) != 1L || is.na(identities[[name]]) || !grepl("^[A-Fa-f0-9]{64}$", identities[[name]])) stop("PROGRAM-IDENTITY-HASH:", name)
  if (!identical(toupper(identities$plan_sha256), toupper(contract$approval$analysis_plan_sha256))) stop("PROGRAM-IDENTITY-MISMATCH:plan_sha256")
  if (!identical(toupper(identities$approval_payload_sha256), toupper(contract$approval$approval_payload_sha256))) stop("PROGRAM-IDENTITY-MISMATCH:approval_payload_sha256")
  lapply(identities, toupper)
}

build_program_generation_ir <- function(contract, analysis, identities) {
  validate_standard_mmrm_contract(contract)
  if (!is.list(analysis) || !is.character(analysis$analysis_id) || length(analysis$analysis_id) != 1L) stop("PROGRAM-ANALYSIS-CONTRACT-MISMATCH:unknown")
  approved <- standard_contract_get_analysis(contract, analysis$analysis_id)
  if (!identical(analysis, approved)) stop("PROGRAM-ANALYSIS-CONTRACT-MISMATCH:", analysis$analysis_id)
  if ((!is.null(analysis$adapter_file) && nzchar(as.character(analysis$adapter_file))) || (!is.null(analysis$adapter_sha256) && nzchar(as.character(analysis$adapter_sha256)))) stop("PROGRAM-INLINE-ADAPTER-UNSUPPORTED:", analysis$analysis_id)
  identity <- program_validate_identities(identities, contract)
  registry <- program_generation_semantic_registry(); program_validate_semantic_registry(registry, analysis$analysis_id)
  normalized_derivations <- lapply(analysis$derivations, standard_normalize_recode)
  profile_name <- contract$execution$sas_execution_profile
  profile <- sas_execution_profile_registry()[[profile_name]]
  ir <- list(
    ir_schema_version = "program-generation-ir/v1",
    identity = list(study_id = contract$study$study_id, analysis_id = analysis$analysis_id, tfl_id = analysis$tfl_id, title = analysis$title, profile_version = contract$profile_version, plan_sha256 = identity$plan_sha256, approval_payload_sha256 = identity$approval_payload_sha256, contract_sha256 = identity$contract_sha256, review_sha256 = toupper(contract$approval$review_sha256), source_evidence_sha256 = toupper(contract$approval$source_evidence_sha256)),
    contract_analysis_ids = vapply(contract$analyses, `[[`, character(1), "analysis_id"),
    execution = contract$execution,
    dataset = analysis$dataset,
    source_variables = program_source_variable_inventory(analysis),
    derivations = normalized_derivations,
    filters = analysis$filters,
    groups = analysis$groups,
    endpoint_definitions = analysis$endpoint_definitions,
    mappings = analysis$mappings,
    treatment = analysis$treatment,
    fixed_effects = analysis$fixed_effects,
    covariance_order = c(analysis$covariance$primary, unlist(analysis$covariance$fallback, use.names = FALSE)),
    df_method = analysis$df_method,
    reml = analysis$reml,
    estimands = analysis$estimands,
    output = analysis$output,
    sas_execution_profile = c(list(id = profile_name), profile),
    path_interface = list(precedence = c("command_line", "environment", "file_configuration"), command_line = c(input = "--input-dir", output = "--output-dir"), environment = c(input = "MMRM_INPUT_DIR", output = "MMRM_OUTPUT_DIR"), file_configuration = c(input = "INPUT_DIR", output = "OUTPUT_DIR"), reject_unknown_arguments = TRUE, paths_only = TRUE),
    code_generation_only = identical(analysis$dataset$binding_mode, "planned"),
    semantic_registry = registry,
    semantic_bindings = program_semantic_bindings(analysis, registry)
  )
  program_validate_string_literals(ir)
  ir
}
