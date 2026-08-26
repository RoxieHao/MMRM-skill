options(encoding = "UTF-8")
find_analysis_plan_root <- function(path) { current <- normalizePath(path, winslash = "/", mustWork = TRUE); repeat { if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "analysis_plan.R"))) return(current); parent <- dirname(current); if (parent == current) stop("project root not found"); current <- parent } }
analysis_plan_check_source <- function() { project_dir <- find_analysis_plan_root(getwd()); helper_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R"); for (helper in c("canonical_hash.R", "standard_contract.R", "standard_analysis_definition.R", "analysis_plan.R", "analysis_contract_generation.R")) source(file.path(helper_dir, helper), encoding = "UTF-8", local = globalenv()); project_dir }
synthetic_trace_ids <- function() c("SRC-DATA-01", paste0("DEC-", sprintf("%02d", 1:11)))
synthetic_analysis_plan <- function() {
  trace <- list(dataset = list("SRC-DATA-01"), adapter = list(), mappings = list("DEC-01"), derivations = list("DEC-02"), filters = list("DEC-03"), groups = list("DEC-04"), endpoint_definitions = list("DEC-05"), model_terms = list("DEC-06"), reml = list("DEC-06"), covariance = list("DEC-07"), df_method = list("DEC-08"), estimands = list("DEC-09"), treatment = list("DEC-10"))
  analysis <- list(
    analysis_id = "MMRM-01", source_tfl_id = "T14-01", title = "Synthetic non-default analysis",
    dataset = list(binding_mode = "linked", file = "scores.csv", format = "csv", relative_path = "studies/synthetic/input/scores.csv", sha256 = paste(rep("A", 64L), collapse = "")),
    adapter = NULL,
    mappings = list(subject = "PERSON_ID", response = "DELTA_SCORE", baseline = "START_SCORE", visit = "TIME_INDEX", visit_label = "TIME_LABEL", treatment = "RANDOM_ARM"),
    derivations = list(list(id = "REPORTER_RECODE", operation = "recode", source_variable = "REPORTER", target_variable = "REPORTER_GROUP", levels = list(list(target_value = "Caregiver", source_values = c("Mother", "Father", "Guardian")), list(target_value = "Subject", source_values = "Self")), unmatched = "error", missing = "preserve", source_ref = list(review_rule = "T14-01/endpoint_dimension", reviewer_decision = "DEC-02"))),
    filters = list(list(variable = "ANALYSIS_FLAG", operator = "eq", value = "Y")),
    groups = list(list(id = "TOTAL", label = "Total score", predicates = list(list(variable = "PARAMCD", operator = "in", value = c("SCORE_B", "SCORE_A")), list(variable = "REPORTER_GROUP", operator = "in", value = c("Caregiver", "Subject"))))),
    endpoint_definitions = list(list(group_id = "TOTAL", endpoint_variable = "PARAMCD", selected_codes = c("SCORE_B", "SCORE_A"), selection_mode = "mutually_exclusive_versions", dimensions = list(instrument = list(variable = "fixed", values = "Scale X"), version = list(variable = "PARAMCD", values = c("SCORE_B", "SCORE_A")), reporter = list(variable = "REPORTER_GROUP", values = c("Caregiver", "Subject")), subscale = list(variable = "fixed", values = "total")), row_allocation_rule = "one_row_per_subject_endpoint_visit")),
    model_terms = list(
      list(kind = "main_effect", role = "visit"),
      list(kind = "main_effect", role = "baseline"),
      list(kind = "main_effect", role = "treatment"),
      list(kind = "interaction", of = list("baseline", "visit")),
      list(kind = "interaction", of = list("treatment", "visit")),
      list(kind = "main_effect", variable = "REPORTER_GROUP", variable_type = "categorical"),
      list(kind = "interaction", of = list("REPORTER_GROUP", "visit"))
    ), reml = TRUE,
    covariance = list(primary = "TOEP", fallback = as.list(c("CS", "AR1"))), df_method = "Satterthwaite",
    estimands = list(visit_lsmeans = TRUE, treatment_visit_lsmeans = TRUE, pairwise_differences = TRUE),
    treatment = list(variable = "RANDOM_ARM", levels = c("ZX-Control", "A-Active"), reference = "ZX-Control", comparator = "A-Active", contrast_direction = "comparator_minus_reference", confidence_level = 0.95, multiplicity_adjustment = "none"), trace = trace)
  list(analysis_plan_schema_version = "2.2", study_id = "SYNTHETIC", execution_context = list(profile_version = standard_mmrm_profile_version(), data_availability = "available", data_classification = "dummy", intended_use = "technical_validation", sas_execution_profile = "sas-9.4m5-self-contained/v1"), analyses = list(analysis))
}
check_analysis_plan_main <- function() {
  analysis_plan_check_source(); plan <- synthetic_analysis_plan(); trace_ids <- synthetic_trace_ids(); validate_analysis_plan(plan, trace_ids)
  normalized <- analysis_plan_normalize(plan, trace_ids); stopifnot(grepl("^[A-F0-9]{64}$", analysis_plan_sha256(normalized)))
  alternate <- plan; alternate$analyses[[1]]$dataset$sha256 <- tolower(alternate$analyses[[1]]$dataset$sha256); stopifnot(identical(analysis_plan_sha256(plan), analysis_plan_sha256(alternate)))
  contexts <- list(
    list(profile_version = standard_mmrm_profile_version(), data_availability = "none", data_classification = "none", intended_use = "code_generation", sas_execution_profile = "sas-9.4m5-self-contained/v1"),
    list(profile_version = standard_mmrm_profile_version(), data_availability = "available", data_classification = "production", intended_use = "formal_analysis", sas_execution_profile = "sas-9.4m5-self-contained/v1"))
  invisible(lapply(contexts, analysis_plan_validate_execution_context))
  invalid_context <- plan; invalid_context$execution_context$data_classification <- "dummy"; invalid_context$execution_context$intended_use <- "formal_analysis"; stopifnot(inherits(try(validate_analysis_plan(invalid_context, trace_ids), silent = TRUE), "try-error"))
  mixed_planned <- plan; mixed_planned$analyses[[1]]$dataset <- list(binding_mode = "planned", file = "scores.csv", format = "csv", relative_path = NULL, sha256 = NULL); validate_analysis_plan(mixed_planned, trace_ids)
  planned <- mixed_planned; planned$execution_context[c("data_availability", "data_classification", "intended_use")] <- list("none", "none", "code_generation"); validate_analysis_plan(planned, trace_ids); stopifnot(is.null(analysis_plan_normalize(planned, trace_ids)$analyses[[1]]$dataset$sha256))
  fake_planned <- planned; fake_planned$analyses[[1]]$dataset$relative_path <- "studies/synthetic/input/scores.csv"; fake_planned$analyses[[1]]$dataset$sha256 <- paste(rep("A", 64L), collapse = ""); stopifnot(inherits(try(validate_analysis_plan(fake_planned, trace_ids), silent = TRUE), "try-error"))
  incomplete_linked <- plan; incomplete_linked$analyses[[1]]$dataset$relative_path <- NULL; stopifnot(inherits(try(validate_analysis_plan(incomplete_linked, trace_ids), silent = TRUE), "try-error"))
  linked_none <- plan; linked_none$execution_context[c("data_availability", "data_classification", "intended_use")] <- list("none", "none", "code_generation"); stopifnot(inherits(try(validate_analysis_plan(linked_none, trace_ids), silent = TRUE), "try-error"))
  old_plan <- plan; old_plan$analysis_plan_schema_version <- "2.0"; old_error <- try(validate_analysis_plan(old_plan, trace_ids), silent = TRUE); stopifnot(inherits(old_error, "try-error"), grepl("MIGRATION", as.character(old_error), fixed = TRUE))
  legacy_21 <- plan; legacy_21$analysis_plan_schema_version <- "2.1"; legacy_error <- try(validate_analysis_plan(legacy_21, trace_ids), silent = TRUE); stopifnot(inherits(legacy_error, "try-error"), grepl("MIGRATION", as.character(legacy_error), fixed = TRUE))
  # model_terms 负例：缺核心 baseline*visit / 未知协变量 / 交互引用未声明主效应 / 角色-only 非法交互。
  drop_core <- plan; drop_core$analyses[[1]]$model_terms <- list(list(kind = "main_effect", role = "visit"), list(kind = "main_effect", role = "baseline"), list(kind = "main_effect", role = "treatment"), list(kind = "interaction", of = list("treatment", "visit"))); stopifnot(inherits(try(validate_analysis_plan(drop_core, trace_ids), silent = TRUE), "try-error"))
  unknown_cov <- plan; unknown_cov$analyses[[1]]$model_terms <- c(plan$analyses[[1]]$model_terms, list(list(kind = "main_effect", variable = "NOT_A_VARIABLE", variable_type = "numeric"))); stopifnot(inherits(try(validate_analysis_plan(unknown_cov, trace_ids), silent = TRUE), "try-error"))
  undeclared_ix <- plan; undeclared_ix$analyses[[1]]$model_terms <- c(plan$analyses[[1]]$model_terms, list(list(kind = "interaction", of = list("START_SCORE", "visit")))); stopifnot(inherits(try(validate_analysis_plan(undeclared_ix, trace_ids), silent = TRUE), "try-error"))
  bad_role_ix <- plan; bad_role_ix$analyses[[1]]$model_terms <- c(plan$analyses[[1]]$model_terms, list(list(kind = "interaction", of = list("baseline", "treatment")))); stopifnot(inherits(try(validate_analysis_plan(bad_role_ix, trace_ids), silent = TRUE), "try-error"))
  rds_plan <- planned; rds_plan$analyses[[1]]$dataset$file <- "scores.rds"; rds_plan$analyses[[1]]$dataset$format <- "rds"; rds_error <- try(validate_analysis_plan(rds_plan, trace_ids), silent = TRUE); stopifnot(inherits(rds_error, "try-error"), grepl("PLAN-SCHEMA-DATASET-FORMAT-CROSS-LANGUAGE", as.character(rds_error), fixed = TRUE))
  missing_cases <- list(mappings = function(x) { x$analyses[[1]]$mappings$response <- NULL; x }, derivation_source = function(x) { x$analyses[[1]]$derivations[[1]]$source_variable <- NULL; x }, endpoint = function(x) { x$analyses[[1]]$endpoint_definitions <- list(); x }, model_terms = function(x) { x$analyses[[1]]$model_terms <- list(); x }, reml = function(x) { x$analyses[[1]]$reml <- NULL; x }, df_method = function(x) { x$analyses[[1]]$df_method <- NULL; x }, covariance = function(x) { x$analyses[[1]]$covariance$primary <- NULL; x }, estimand = function(x) { x$analyses[[1]]$estimands$visit_lsmeans <- NULL; x }, contrast = function(x) { x$analyses[[1]]$treatment$reference <- NULL; x })
  invisible(lapply(missing_cases, function(mutate) stopifnot(inherits(try(validate_analysis_plan(mutate(planned), trace_ids), silent = TRUE), "try-error"))))
  adapter <- plan; adapter$analyses[[1]]$adapter <- list(file = "studies/synthetic/analysis/r/adapter.R", sha256 = paste(rep("B", 64L), collapse = "")); adapter$analyses[[1]]$trace$adapter <- list("DEC-11"); validate_analysis_plan(adapter, trace_ids)
  unknown <- plan; unknown$analyses[[1]]$unexpected <- TRUE; stopifnot(inherits(try(validate_analysis_plan(unknown, trace_ids), silent = TRUE), "try-error"))
  incomplete <- plan; incomplete$analyses[[1]]$df_method <- NULL; stopifnot(inherits(try(validate_analysis_plan(incomplete, trace_ids), silent = TRUE), "try-error"))
  inherited <- plan; inherited$defaults <- list(covariance = "UN"); stopifnot(inherits(try(validate_analysis_plan(inherited, trace_ids), silent = TRUE), "try-error"))
  unsupported <- plan; unsupported$analyses[[1]]$derivations[[1]]$operation <- "expression"; stopifnot(inherits(try(validate_analysis_plan(unsupported, trace_ids), silent = TRUE), "try-error"))
  overlap <- plan; overlap$analyses[[1]]$derivations[[1]]$levels[[2]]$source_values <- c("Self", "Mother"); stopifnot(inherits(try(validate_analysis_plan(overlap, trace_ids), silent = TRUE), "try-error"))
  collision <- plan; collision$analyses[[1]]$derivations[[1]]$target_variable <- "REPORTER"; stopifnot(inherits(try(validate_analysis_plan(collision, trace_ids), silent = TRUE), "try-error"))
  cycle <- plan; cycle$analyses[[1]]$derivations[[1]]$source_variable <- "REPORTER_GROUP"; stopifnot(inherits(try(validate_analysis_plan(cycle, trace_ids), silent = TRUE), "try-error"))
  missing_policy <- plan; missing_policy$analyses[[1]]$derivations[[1]]$missing <- NULL; stopifnot(inherits(try(validate_analysis_plan(missing_policy, trace_ids), silent = TRUE), "try-error"))
  approval <- list(review_file = "studies/synthetic/statistician-review/statistical-review.md", review_sha256 = paste(rep("C", 64L), collapse = ""), analysis_plan_file = "studies/synthetic/statistician-review/analysis-plan.yaml", analysis_plan_sha256 = analysis_plan_sha256(plan), approval_payload_sha256 = paste(rep("D", 64L), collapse = ""), source_evidence_sha256 = paste(rep("E", 64L), collapse = ""), reviewed_by = "Synthetic Statistician", approved_at_utc = "2026-08-19T00:00:00Z")
  contract <- compile_analysis_plan_contract(plan, approval); assert_plan_contract_parity(plan, contract)
  contract_path <- tempfile("compiled-contract-", fileext = ".yaml"); on.exit(unlink(contract_path), add = TRUE); write_standard_mmrm_contract(contract, contract_path); production_contract <- read_standard_mmrm_contract(contract_path); assert_plan_contract_parity(plan, production_contract)
  planned_contract <- compile_analysis_plan_contract(planned, approval); assert_plan_contract_parity(planned, planned_contract); stopifnot(is.null(planned_contract$analyses[[1]]$dataset$relative_path), is.null(planned_contract$analyses[[1]]$dataset$sha256), identical(planned_contract$execution$sas_execution_profile, "sas-9.4m5-self-contained/v1"))
  null_tamper <- planned_contract; null_tamper$analyses[[1]]$dataset$relative_path <- ""; stopifnot(inherits(try(assert_plan_contract_parity(planned, null_tamper), silent = TRUE), "try-error"))
  identity_collision <- plan; duplicate <- identity_collision$analyses[[1]]; duplicate$analysis_id <- tolower(duplicate$analysis_id); duplicate$source_tfl_id <- "T14-02"; identity_collision$analyses <- c(identity_collision$analyses, list(duplicate)); collision_error <- try(compile_analysis_plan_contract(identity_collision, approval), silent = TRUE); stopifnot(inherits(collision_error, "try-error"), grepl("PLAN-SCHEMA-IDENTITY-COLLISION", as.character(collision_error), fixed = TRUE))
  tfl_collision <- plan; duplicate <- tfl_collision$analyses[[1]]; duplicate$analysis_id <- "MMRM-02"; duplicate$source_tfl_id <- tolower(duplicate$source_tfl_id); tfl_collision$analyses <- c(tfl_collision$analyses, list(duplicate)); tfl_error <- try(compile_analysis_plan_contract(tfl_collision, approval), silent = TRUE); stopifnot(inherits(tfl_error, "try-error"), grepl("PLAN-SCHEMA-IDENTITY-COLLISION", as.character(tfl_error), fixed = TRUE))
  output_collision <- contract; output_collision$analyses[[1]]$output$sas_raw_file <- output_collision$analyses[[1]]$output$r_raw_file; stopifnot(inherits(try(validate_standard_mmrm_contract(output_collision), silent = TRUE), "try-error"))
  compiled <- contract$analyses[[1]]; stopifnot(identical(compiled$mappings, plan$analyses[[1]]$mappings), identical(compiled$model_terms, plan$analyses[[1]]$model_terms), identical(compiled$reml, TRUE), identical(compiled$covariance, plan$analyses[[1]]$covariance), identical(compiled$df_method, "Satterthwaite"), identical(compiled$estimands, plan$analyses[[1]]$estimands), identical(names(compiled$output), standard_contract_output_names()), length(unique(tolower(unlist(compiled$output)))) == 8L)
  tampered <- contract; tampered$analyses[[1]]$covariance$fallback <- rev(tampered$analyses[[1]]$covariance$fallback); stopifnot(inherits(try(assert_plan_contract_parity(plan, tampered), silent = TRUE), "try-error"))
  canonical_verify_golden_vectors()
  cat("Analysis plan and internal contract compiler focused check passed.\n")
}
if (sys.nframe() == 0L) check_analysis_plan_main()
