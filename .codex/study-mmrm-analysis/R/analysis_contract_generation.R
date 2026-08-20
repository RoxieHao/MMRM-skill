validate_compiled_analysis_contract <- function(contract) {
  validate_standard_mmrm_contract(contract)
}

analysis_plan_statistical_projection <- function(plan) {
  validate_analysis_plan(plan)
  lapply(plan$analyses, function(x) list(analysis_id = x$analysis_id, tfl_id = x$source_tfl_id, title = x$title, dataset = x$dataset, adapter = x$adapter, mappings = x$mappings, derivations = x$derivations, filters = x$filters, groups = x$groups, endpoint_definitions = x$endpoint_definitions, fixed_effects = x$fixed_effects, covariance = x$covariance, df_method = x$df_method, estimands = x$estimands, treatment = x$treatment))
}
standard_contract_statistical_projection <- function(contract) {
  validate_compiled_analysis_contract(contract)
  lapply(contract$analyses, function(x) list(analysis_id = x$analysis_id, tfl_id = x$tfl_id, title = x$title, dataset = x$dataset, adapter = if (is.null(x$adapter_file)) NULL else list(file = x$adapter_file, sha256 = x$adapter_sha256), mappings = x$mappings, derivations = x$derivations, filters = x$filters, groups = x$groups, endpoint_definitions = x$endpoint_definitions, fixed_effects = x$fixed_effects, covariance = x$covariance, df_method = x$df_method, estimands = x$estimands, treatment = x$treatment))
}
assert_plan_contract_parity <- function(plan, contract) {
  left <- analysis_plan_statistical_projection(plan); right <- standard_contract_statistical_projection(contract)
  if (!identical(as.character(plan$study_id), as.character(contract$study$study_id))) stop("PLAN-PARITY-MISMATCH: contract study_id differs from approved analysis plan.")
  if (!identical(canonical_bytes(left), canonical_bytes(right))) stop("PLAN-PARITY-MISMATCH: contract statistical semantics differ from approved analysis plan.")
  invisible(TRUE)
}
compile_analysis_plan_contract <- function(plan, approval) {
  validate_analysis_plan(plan); standard_assert_keys(approval, c("review_file", "review_sha256", "analysis_plan_file", "analysis_plan_sha256", "approval_payload_sha256", "source_evidence_sha256", "reviewed_by", "approved_at_utc"), character(), "approval")
  analyses <- lapply(plan$analyses, function(x) {
    safe <- gsub("[^A-Za-z0-9_-]+", "_", x$analysis_id)
    result <- list(analysis_id = x$analysis_id, tfl_id = x$source_tfl_id, title = x$title, dataset = x$dataset, mappings = x$mappings, derivations = x$derivations, filters = x$filters, groups = x$groups, endpoint_definitions = x$endpoint_definitions, fixed_effects = x$fixed_effects, covariance = x$covariance, df_method = x$df_method, estimands = x$estimands, output = list(raw_file = paste0(safe, "_raw.csv"), final_file = paste0(safe, "_final.csv")))
    if (!is.null(x$treatment)) result$treatment <- x$treatment
    if (!is.null(x$adapter)) { result$adapter_file <- x$adapter$file; result$adapter_sha256 <- toupper(x$adapter$sha256) }
    result
  })
  contract <- list(profile_version = plan$execution_context$profile_version, study = list(study_id = plan$study_id), execution = list(fail_fast = FALSE), approval = approval, analyses = analyses)
  validate_compiled_analysis_contract(contract); assert_plan_contract_parity(plan, contract); contract
}
write_compiled_analysis_contract <- write_standard_mmrm_contract
read_compiled_analysis_contract <- read_standard_mmrm_contract
