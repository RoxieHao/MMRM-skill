validate_compiled_analysis_contract <- function(contract) {
  validate_standard_mmrm_contract(contract)
}

analysis_plan_statistical_projection <- function(plan) {
  validate_analysis_plan(plan)
  list(
    execution_context = plan$execution_context,
    analyses = lapply(plan$analyses, function(x) list(analysis_id = x$analysis_id, tfl_id = x$source_tfl_id, title = x$title, dataset = x$dataset, adapter = x$adapter, mappings = x$mappings, derivations = x$derivations, filters = x$filters, groups = x$groups, endpoint_definitions = x$endpoint_definitions, model_terms = x$model_terms, reml = x$reml, covariance = x$covariance, df_method = x$df_method, estimands = x$estimands, treatment = x$treatment))
  )
}
standard_contract_statistical_projection <- function(contract) {
  validate_compiled_analysis_contract(contract)
  list(
    execution_context = c(list(profile_version = contract$profile_version), contract$execution[c("data_availability", "data_classification", "intended_use", "sas_execution_profile")]),
    analyses = lapply(contract$analyses, function(x) list(analysis_id = x$analysis_id, tfl_id = x$tfl_id, title = x$title, dataset = x$dataset, adapter = if (is.null(x$adapter_file)) NULL else list(file = x$adapter_file, sha256 = x$adapter_sha256), mappings = x$mappings, derivations = x$derivations, filters = x$filters, groups = x$groups, endpoint_definitions = x$endpoint_definitions, model_terms = x$model_terms, reml = x$reml, covariance = x$covariance, df_method = x$df_method, estimands = x$estimands, treatment = x$treatment))
  )
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
    result <- list(analysis_id = x$analysis_id, tfl_id = x$source_tfl_id, title = x$title, dataset = x$dataset, mappings = x$mappings, derivations = x$derivations, filters = x$filters, groups = x$groups, endpoint_definitions = x$endpoint_definitions, model_terms = x$model_terms, reml = x$reml, covariance = x$covariance, df_method = x$df_method, estimands = x$estimands, output = standard_contract_expected_output(x$source_tfl_id))
    if (!is.null(x$treatment)) result$treatment <- x$treatment
    if (!is.null(x$adapter)) { result$adapter_file <- x$adapter$file; result$adapter_sha256 <- toupper(x$adapter$sha256) }
    result
  })
  execution <- c(plan$execution_context[c("data_availability", "data_classification", "intended_use", "sas_execution_profile")], list(fail_fast = FALSE))
  contract <- list(contract_schema_version = "2.1", profile_version = plan$execution_context$profile_version, study = list(study_id = plan$study_id), execution = execution, approval = approval, analyses = analyses)
  validate_compiled_analysis_contract(contract); assert_plan_contract_parity(plan, contract); contract
}
write_compiled_analysis_contract <- write_standard_mmrm_contract
read_compiled_analysis_contract <- read_standard_mmrm_contract

# ==============================================================================
# Phase 5：自包含 program generation 的正式接线点
# ==============================================================================

# 8.1 接线前的 output contract 闭合门。先断言八字段 closed shape（旧 shape 在这里就被
# 阻断，错误信息明确说明没有 compatibility fallback），再做完整 contract 校验。
analysis_generation_assert_output_contract <- function(contract) {
  standard_contract_assert_output_closed_shape(contract)
  validate_compiled_analysis_contract(contract)
  invisible(TRUE)
}

# 生成器所需的 helper 只在缺失时按需载入，使既有入口脚本（approve_and_generate_analysis.R、
# collector 模板）无需改变 source 列表即可使用自包含 renderer。已存在的定义一律不覆盖，
# 因此自检脚本对 renderer/conformance 的显式替换（失败注入）不会被这里悄悄还原。
analysis_generation_program_helpers <- function() c(program_generation_ir.R = "build_program_generation_ir", program_conformance.R = "validate_tfl_program_coverage", self_contained_r.R = "render_self_contained_r_program", self_contained_sas.R = "render_self_contained_sas_program")
analysis_generation_ensure_program_helpers <- function(project_dir) {
  helper_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R"); helpers <- analysis_generation_program_helpers()
  for (file_name in names(helpers)) {
    if (!exists(helpers[[file_name]], mode = "function")) {
      path <- file.path(helper_dir, file_name)
      if (!file.exists(path)) stop("PROGRAM-GENERATION-HELPER-MISSING: ", path)
      source(path, encoding = "UTF-8", local = globalenv())
    }
    if (!exists(helpers[[file_name]], mode = "function")) stop("PROGRAM-GENERATION-HELPER-MISSING: ", helpers[[file_name]])
  }
  invisible(TRUE)
}

analysis_generation_identities <- function(contract, payload_sha, contract_sha) list(plan_sha256 = toupper(as.character(contract$approval$analysis_plan_sha256)), approval_payload_sha256 = toupper(as.character(payload_sha)), contract_sha256 = toupper(as.character(contract_sha)))

# 生成程序的规范化文件名只来自安全化 analysis identity；与 program coverage 校验同源。
analysis_generation_program_basename <- function(analysis_id, language) paste0(standard_contract_safe_identity(analysis_id), if (identical(language, "r")) ".R" else ".sas")
analysis_generation_program_path <- function(study_dir, analysis_id, language) file.path(study_dir, "analysis", if (identical(language, "r")) "r" else "sas", analysis_generation_program_basename(analysis_id, language))

# 8.3 逐 analysis：build IR → render R → validate R → render SAS → validate SAS；
# 全部 analysis 完成后统一做 validate_tfl_program_coverage()。任一步失败即整体抛错，
# 调用方（approval publisher）此时还没有接触磁盘，因此不可能留下半套单语言产物。
#
# test_only_drop_targets 仅供自检脚本注入“coverage 缺一个文件”场景；正式审批链从不传值。
analysis_generate_program_texts <- function(study_dir, project_dir, contract, payload_sha, contract_sha, test_only_drop_targets = character()) {
  analysis_generation_ensure_program_helpers(project_dir)
  analysis_generation_assert_output_contract(contract)
  identities <- analysis_generation_identities(contract, payload_sha, contract_sha)
  texts <- list()
  for (analysis in contract$analyses) {
    ir <- build_program_generation_ir(contract, analysis, identities)
    r_text <- render_self_contained_r_program(contract, analysis, identities)
    validate_generated_r_program(r_text, ir)
    sas_text <- render_self_contained_sas_program(contract, analysis, identities)
    validate_generated_sas_program(sas_text, ir)
    texts[[analysis_generation_program_path(study_dir, analysis$analysis_id, "r")]] <- r_text
    texts[[analysis_generation_program_path(study_dir, analysis$analysis_id, "sas")]] <- sas_text
  }
  if (length(test_only_drop_targets)) texts <- texts[setdiff(names(texts), as.character(test_only_drop_targets))]
  validate_tfl_program_coverage(contract, texts)
  texts
}
