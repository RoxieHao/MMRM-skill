options(encoding = "UTF-8")
find_program_generation_root <- function(path) { current <- normalizePath(path, winslash = "/", mustWork = TRUE); repeat { if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "program_generation_ir.R"))) return(current); parent <- dirname(current); if (parent == current) stop("project root not found"); current <- parent } }
program_generation_check_source <- function() { project_dir <- find_program_generation_root(getwd()); helper_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R"); for (helper in c("canonical_hash.R", "standard_contract.R", "standard_analysis_definition.R", "program_generation_ir.R", "program_conformance.R")) source(file.path(helper_dir, helper), encoding = "UTF-8", local = globalenv()); project_dir }
program_hash <- function(letter) paste(rep(letter, 64L), collapse = "")

program_generation_fixture <- function(binding_mode = c("linked", "planned"), analysis_id = "MMRM-01", tfl_id = "T14-01") {
  binding_mode <- match.arg(binding_mode)
  linked <- identical(binding_mode, "linked")
  analysis <- list(
    analysis_id = analysis_id, tfl_id = tfl_id, title = "Synthetic non-default analysis",
    dataset = list(binding_mode = binding_mode, file = "scores.csv", format = "csv", relative_path = if (linked) "studies/synthetic/input/scores.csv" else NULL, sha256 = if (linked) program_hash("A") else NULL),
    mappings = list(subject = "PERSON_ID", response = "DELTA_SCORE", baseline = "START_SCORE", visit = "TIME_INDEX", visit_label = "TIME_LABEL", treatment = "RANDOM_ARM"),
    derivations = list(list(id = "REPORTER_RECODE", operation = "recode", source_variable = "REPORTER", target_variable = "REPORTER_GROUP", levels = list(list(target_value = "Caregiver", source_values = c("Mother", "Father", "Guardian")), list(target_value = "Subject", source_values = "Self")), unmatched = "error", missing = "preserve", source_ref = list(review_rule = "T14-01/endpoint_dimension", reviewer_decision = "DEC-02"))),
    filters = list(list(variable = "ANALYSIS_FLAG", operator = "eq", value = "Y")),
    groups = list(list(id = "TOTAL", label = "Total score", predicates = list(list(variable = "PARAMCD", operator = "in", value = c("SCORE_B", "SCORE_A")), list(variable = "REPORTER_GROUP", operator = "in", value = c("Caregiver", "Subject"))))),
    endpoint_definitions = list(list(group_id = "TOTAL", endpoint_variable = "PARAMCD", selected_codes = c("SCORE_B", "SCORE_A"), selection_mode = "mutually_exclusive_versions", dimensions = list(instrument = list(variable = "fixed", values = "Scale X"), version = list(variable = "PARAMCD", values = c("SCORE_B", "SCORE_A")), reporter = list(variable = "REPORTER_GROUP", values = c("Caregiver", "Subject")), subscale = list(variable = "fixed", values = "total")), row_allocation_rule = "one_row_per_subject_endpoint_visit")),
    model_terms = list(list(kind = "main_effect", role = "baseline"), list(kind = "main_effect", role = "visit"), list(kind = "main_effect", role = "treatment"), list(kind = "interaction", of = list("baseline", "visit")), list(kind = "interaction", of = list("treatment", "visit"))), reml = TRUE,
    covariance = list(primary = "TOEP", fallback = as.list(c("CS", "AR1"))), df_method = "Satterthwaite",
    estimands = list(visit_lsmeans = TRUE, treatment_visit_lsmeans = TRUE, pairwise_differences = TRUE),
    treatment = list(variable = "RANDOM_ARM", levels = c("ZX-Control", "A-Active"), reference = "ZX-Control", comparator = "A-Active", contrast_direction = "comparator_minus_reference", confidence_level = 0.95, multiplicity_adjustment = "none"),
    output = standard_contract_expected_output(tfl_id)
  )
  approval <- list(review_file = "studies/synthetic/statistician-review/statistical-review.md", review_sha256 = program_hash("C"), analysis_plan_file = "studies/synthetic/statistician-review/analysis-plan.yaml", analysis_plan_sha256 = program_hash("B"), approval_payload_sha256 = program_hash("D"), source_evidence_sha256 = program_hash("E"), reviewed_by = "Synthetic Statistician", approved_at_utc = "2026-08-19T00:00:00Z")
  contract <- list(contract_schema_version = "2.1", profile_version = standard_mmrm_profile_version(), study = list(study_id = "SYNTHETIC"), execution = list(data_availability = if (linked) "available" else "none", data_classification = if (linked) "dummy" else "none", intended_use = if (linked) "technical_validation" else "code_generation", sas_execution_profile = "sas-9.4m5-self-contained/v1", fail_fast = FALSE), approval = approval, analyses = list(analysis))
  validate_standard_mmrm_contract(contract)
  contract
}

program_fixture_identities <- function(contract) list(plan_sha256 = contract$approval$analysis_plan_sha256, approval_payload_sha256 = contract$approval$approval_payload_sha256, contract_sha256 = program_hash("F"))
program_comment <- function(language, value) if (identical(language, "R")) paste0("# ", value) else paste0("/* ", value, " */")

program_conforming_skeleton <- function(ir, language = c("R", "SAS")) {
  language <- match.arg(language)
  comment <- function(value) program_comment(language, value)
  markers <- vapply(program_expected_markers(ir), comment, character(1))
  why <- vapply(program_expected_why_prefixes(ir), function(prefix) comment(paste0(prefix, "为忠实执行批准语义并保留审计轨迹")), character(1))
  gates <- if (identical(ir$dataset$binding_mode, "linked")) c(comment(program_marker("GATE", "LINKED_FILE")), comment(program_marker("GATE", "LINKED_SHA256"))) else c(comment(program_marker("GATE", "PLANNED_CODE_GENERATION_ONLY")), if (identical(language, "R")) "CODE_GENERATION_ONLY <- TRUE" else "%let CODE_GENERATION_ONLY=YES;")
  final <- comment(program_marker("FINAL_CSV_WRITE", "EXECUTABLE"))
  if (identical(language, "R")) {
    packages <- c("mmrm", "emmeans", if (identical(ir$dataset$binding_mode, "linked")) "digest")
    package_lines <- unlist(lapply(packages, function(package) c(comment(program_marker("PACKAGE", package)), paste0("if (!requireNamespace(\"", package, "\", quietly = TRUE)) stop(\"缺少包\")"))), use.names = FALSE)
    executable <- c(package_lines, gates, if (identical(ir$dataset$binding_mode, "linked")) c("if (!file.exists(input_file)) stop(\"输入文件不存在\")", "actual_sha256 <- digest::digest(file = input_file, algo = \"sha256\")"), final, "write.csv(final_table, file.path(OUTPUT_DIR, final_file), row.names = FALSE)")
    header <- function(i) render_r_section_header(i, program_section_titles()[[i]])
    sections <- list(c(header(1), markers, why), c(header(2), executable), header(3), c(header(4), "# 至此完成数据处理。以下代码开始进行 MMRM 模型拟合；请勿混淆两部分职责。"), header(5), header(6), header(7), header(8))
  } else {
    sas_controls <- c(gates, if (identical(ir$dataset$binding_mode, "linked")) c("libname INPUT \"&INPUT_DIR\" access=readonly;", "%if not %sysfunc(fileexist(&INPUT_DIR./scores.csv)) %then %put ERROR: missing;", "%macro verify_file_sha256; %mend verify_file_sha256;", "%verify_file_sha256;") else character(), comment(program_marker("SAS", "ODS_CAPTURE")), "ods output LSMeans=work.lsmeans Diffs=work.diffs SolutionF=work.solutionf ConvergenceStatus=work.convergence;", comment(program_marker("SAS", "FALLBACK_CONTROL")), "%macro fit_covariance; %mend fit_covariance;", comment(program_marker("SAS", "CONVERGENCE_GATE")), "%if &ConvergenceStatus ne 0 %then %put ERROR: nonconvergence;", final, "proc export data=work.final outfile=\"&OUTPUT_DIR./final.csv\" dbms=csv replace; run;")
    header <- function(i) render_sas_section_header(i, program_section_titles()[[i]])
    sections <- list(c(header(1), markers, why), c(header(2), sas_controls), header(3), c(header(4), "/* 至此完成数据处理。以下代码开始进行 MMRM 模型拟合；请勿混淆两部分职责。 */"), header(5), header(6), header(7), header(8))
  }
  paste(unlist(sections, use.names = FALSE), collapse = "\n")
}

program_expect_error <- function(expression, prefix) {
  error <- try(force(expression), silent = TRUE)
  stopifnot(inherits(error, "try-error"), grepl(prefix, as.character(error), fixed = TRUE))
  invisible(error)
}
program_remove_once <- function(text, value) sub(value, "", text, fixed = TRUE)

check_program_generation_ir_main <- function() {
  program_generation_check_source()
  linked <- program_generation_fixture("linked"); planned <- program_generation_fixture("planned")
  linked_analysis <- linked$analyses[[1L]]; planned_analysis <- planned$analyses[[1L]]
  linked_ir <- build_program_generation_ir(linked, linked_analysis, program_fixture_identities(linked)); linked_ir_again <- build_program_generation_ir(linked, linked_analysis, program_fixture_identities(linked))
  stopifnot(identical(linked_ir, linked_ir_again), identical(linked_ir$covariance_order, c("TOEP", "CS", "AR1")), identical(linked_ir$output, linked_analysis$output), identical(linked_ir$source_variables$derived, "REPORTER_GROUP"), !linked_ir$code_generation_only)
  planned_ir <- build_program_generation_ir(planned, planned_analysis, program_fixture_identities(planned)); stopifnot(planned_ir$code_generation_only, identical(planned_ir$dataset$relative_path, NULL), identical(planned_ir$path_interface$precedence, c("command_line", "environment", "file_configuration")))
  registry <- program_generation_semantic_registry(); program_validate_semantic_registry(registry, linked_analysis$analysis_id)
  for (operation in names(registry)) for (language in c("r", "sas")) { mutated <- registry; mutated[[operation]][[language]] <- NULL; error <- program_expect_error(program_validate_semantic_registry(mutated, linked_analysis$analysis_id), "PROGRAM-SEMANTIC-REGISTRY-MISSING"); stopifnot(grepl(linked_analysis$analysis_id, as.character(error), fixed = TRUE), grepl(registry[[operation]]$field_path, as.character(error), fixed = TRUE), grepl(toupper(language), as.character(error), fixed = TRUE)) }
  adapter <- linked; adapter$analyses[[1L]]$adapter_file <- "studies/synthetic/analysis/r/adapter.R"; adapter$analyses[[1L]]$adapter_sha256 <- program_hash("9"); program_expect_error(build_program_generation_ir(adapter, adapter$analyses[[1L]], program_fixture_identities(adapter)), paste0("PROGRAM-INLINE-ADAPTER-UNSUPPORTED:", linked_analysis$analysis_id))
  mismatched <- linked_analysis; mismatched$title <- "Tampered"; program_expect_error(build_program_generation_ir(linked, mismatched, program_fixture_identities(linked)), "PROGRAM-ANALYSIS-CONTRACT-MISMATCH")
  titles <- program_section_titles(); stopifnot(length(titles) == 8L, identical(render_r_section_header(4L, titles[[4L]]), paste("# ==============================================================================", "# 第 4 部分：数据处理与质量控制", "# ==============================================================================", sep = "\n")), identical(render_sas_section_header(4L, titles[[4L]]), paste("/* =============================================================================", "   第 4 部分：数据处理与质量控制", "   ========================================================================== */", sep = "\n")))
  program_expect_error(render_r_section_header(4L, titles[[5L]]), "PROGRAM-SECTION-TITLE")
  linked_r <- program_conforming_skeleton(linked_ir, "R"); linked_sas <- program_conforming_skeleton(linked_ir, "SAS"); planned_r <- program_conforming_skeleton(planned_ir, "R"); planned_sas <- program_conforming_skeleton(planned_ir, "SAS")
  validate_generated_r_program(linked_r, linked_ir); validate_generated_sas_program(linked_sas, linked_ir); validate_generated_r_program(planned_r, planned_ir); validate_generated_sas_program(planned_sas, planned_ir)
  r_mutations <- list(section = program_remove_once(linked_r, render_r_section_header(3L, titles[[3L]])), marker = program_remove_once(linked_r, program_marker("COVARIANCE", "TOEP")), source = paste(linked_r, "source(\"helper.R\")"), codex = paste(linked_r, "# .codex/helper.R"), todo = paste(linked_r, "# TODO"), placeholder = paste(linked_r, "# <INPUT>"), identity = sub(linked_ir$identity$tfl_id, "WRONG-TFL", linked_r, fixed = TRUE), linked_gate = program_remove_once(linked_r, program_marker("GATE", "LINKED_SHA256")))
  invisible(lapply(r_mutations, function(text) program_expect_error(validate_generated_r_program(text, linked_ir), "PROGRAM-R-CONFORMANCE-")))
  stopifnot(program_count_marker(linked_r, program_marker("FIXED_EFFECT", "baseline")) == 1L, program_count_marker(linked_r, program_marker("FIXED_EFFECT", "treatment")) == 1L)
  # placeholder 规则只能捕获真正的模板占位符，不能把合法的大小比较误判为占位符。
  program_expect_error(validate_generated_r_program(paste(linked_r, "# <OUTPUT_DIR>", sep = "\n"), linked_ir), "PROGRAM-R-CONFORMANCE-EXTERNAL-OR-PLACEHOLDER")
  validate_generated_r_program(paste(linked_r, "if (a < b && 0 < d) cat(\"ok\")", "if (x > y) cat(\"ok\")", "keep <- 1", sep = "\n"), linked_ir)
  program_expect_error(validate_generated_r_program(program_remove_once(linked_r, program_marker("FIXED_EFFECT", "baseline_by_visit")), linked_ir), paste0("PROGRAM-R-CONFORMANCE-MARKER:", program_marker("FIXED_EFFECT", "baseline_by_visit")))
  program_expect_error(validate_generated_r_program(paste(linked_r, program_comment("R", program_marker("COVARIANCE", "TOEP")), sep = "\n"), linked_ir), paste0("PROGRAM-R-CONFORMANCE-MARKER:", program_marker("COVARIANCE", "TOEP")))
  sas_mutations <- list(section = program_remove_once(linked_sas, render_sas_section_header(6L, titles[[6L]])), marker = program_remove_once(linked_sas, program_marker("ESTIMAND", "visit_lsmeans")), include = paste(linked_sas, "%include \"helper.sas\";"), codex = paste(linked_sas, "/* .codex/helper.sas */"), todo = paste(linked_sas, "/* TBD */"), placeholder = paste(linked_sas, "/* <INPUT> */"), identity = sub(linked_ir$identity$tfl_id, "WRONG-TFL", linked_sas, fixed = TRUE), linked_gate = program_remove_once(linked_sas, program_marker("GATE", "LINKED_FILE")), readonly = sub(" access=readonly", "", linked_sas, fixed = TRUE))
  invisible(lapply(sas_mutations, function(text) program_expect_error(validate_generated_sas_program(text, linked_ir), "PROGRAM-SAS-CONFORMANCE-")))
  # 注释不能冒充真实行为：把可执行的导出、ODS、fallback、SHA gate 包进注释后必须失败。
  commented_export <- sub("proc export data=work.final outfile=\"&OUTPUT_DIR./final.csv\" dbms=csv replace; run;", "/* proc export data=work.final outfile=\"&OUTPUT_DIR./final.csv\" dbms=csv replace; run; */", linked_sas, fixed = TRUE)
  program_expect_error(validate_generated_sas_program(commented_export, linked_ir), "PROGRAM-SAS-CONFORMANCE-FINAL-CSV-EXECUTABLE")
  commented_ods <- sub("ods output LSMeans=work.lsmeans Diffs=work.diffs SolutionF=work.solutionf ConvergenceStatus=work.convergence;", "/* ods output LSMeans=work.lsmeans Diffs=work.diffs SolutionF=work.solutionf ConvergenceStatus=work.convergence; */", linked_sas, fixed = TRUE)
  program_expect_error(validate_generated_sas_program(commented_ods, linked_ir), "PROGRAM-SAS-CONFORMANCE-")
  commented_sha <- sub("%macro verify_file_sha256; %mend verify_file_sha256;", "/* %macro verify_file_sha256; %mend verify_file_sha256; */", linked_sas, fixed = TRUE)
  commented_sha <- sub("%verify_file_sha256;", "/* %verify_file_sha256; */", commented_sha, fixed = TRUE)
  program_expect_error(validate_generated_sas_program(commented_sha, linked_ir), "PROGRAM-SAS-CONFORMANCE-LINKED-GATE-EXECUTABLE")
  # 显式 DATA step CSV writer 是被接受的真实导出实现（无 proc export 时也应通过）。
  data_step_sas <- sub("proc export data=work.final outfile=\"&OUTPUT_DIR./final.csv\" dbms=csv replace; run;", "data _null_; set work.final; file \"&OUTPUT_DIR./final.csv\" recfm=n lrecl=32767; put 'EFBBBF'x; run;", linked_sas, fixed = TRUE)
  validate_generated_sas_program(data_step_sas, linked_ir)
  program_expect_error(validate_generated_r_program(program_remove_once(planned_r, program_marker("GATE", "PLANNED_CODE_GENERATION_ONLY")), planned_ir), "PROGRAM-R-CONFORMANCE-PLANNED-GATE")
  program_expect_error(validate_generated_sas_program(program_remove_once(planned_sas, program_marker("GATE", "PLANNED_CODE_GENERATION_ONLY")), planned_ir), "PROGRAM-SAS-CONFORMANCE-PLANNED-GATE")
  rendered <- setNames(list(linked_r, linked_sas), c("MMRM-01.R", "MMRM-01.sas")); validate_tfl_program_coverage(linked, rendered)
  program_expect_error(validate_tfl_program_coverage(linked, rendered[1L]), "PROGRAM-TFL-COVERAGE-FILE-SET")
  program_expect_error(validate_tfl_program_coverage(linked, c(rendered, list("extra" = linked_r))), "PROGRAM-TFL-COVERAGE-FILE-SET")
  duplicate <- c(rendered, setNames(list(linked_r), "mmrm-01.r")); program_expect_error(validate_tfl_program_coverage(linked, duplicate), "PROGRAM-TFL-COVERAGE-FILE-SET")
  wrong_coverage <- rendered; wrong_coverage[[1L]] <- sub(linked_ir$identity$tfl_id, "WRONG-TFL", wrong_coverage[[1L]], fixed = TRUE); program_expect_error(validate_tfl_program_coverage(linked, wrong_coverage), "PROGRAM-TFL-COVERAGE-IDENTITY")
  cat("Program generation IR and conformance focused check passed.\n")
}
if (sys.nframe() == 0L) check_program_generation_ir_main()
