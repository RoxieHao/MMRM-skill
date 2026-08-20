options(encoding = "UTF-8")

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
if (length(script_arg) != 1L) stop("请使用 Rscript 运行测试。")
script_file <- normalizePath(sub("^--file=", "", script_arg), winslash = "/", mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_file), "..", "..", "..", ".."), winslash = "/", mustWork = TRUE)
helper_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
source(file.path(helper_dir, "io.R"), encoding = "UTF-8")
source(file.path(helper_dir, "study_paths.R"), encoding = "UTF-8")
source(file.path(helper_dir, "specification.R"), encoding = "UTF-8")
source(file.path(helper_dir, "endpoint_mapping.R"), encoding = "UTF-8")
source(file.path(helper_dir, "intake_extraction.R"), encoding = "UTF-8")
source(file.path(helper_dir, "intake_review.R"), encoding = "UTF-8")
source(file.path(helper_dir, "runtime_dataset_binding.R"), encoding = "UTF-8")
source(file.path(helper_dir, "intake_enrichment.R"), encoding = "UTF-8")
source(file.path(helper_dir, "standard_contract.R"), encoding = "UTF-8")
source(file.path(helper_dir, "standard_engine.R"), encoding = "UTF-8")
source(file.path(helper_dir, "standard_artifacts.R"), encoding = "UTF-8")
source(file.path(helper_dir, "standard_sas.R"), encoding = "UTF-8")
source(file.path(helper_dir, "analysis_specification_generation.R"), encoding = "UTF-8")
source(file.path(helper_dir, "case_summary.R"), encoding = "UTF-8")

main <- function() {
required_packages <- c("yaml", "digest", "mmrm", "emmeans", "callr")
missing_packages <- required_packages[!vapply(required_packages, function(package) nzchar(system.file(package = package)), logical(1))]
if (length(missing_packages)) stop("测试缺少 package：", paste(missing_packages, collapse = ", "))

pedsql_dimensions_text <- "instrument=PedsQL; version=PARAMCD:[TS1,TS2]; reporter=patient; subscale=total_score"
pedsql_dimensions <- analysis_specification_parse_dimensions(pedsql_dimensions_text)
stopifnot(
  identical(pedsql_dimensions$instrument, list(variable = "fixed", values = "PedsQL")),
  identical(pedsql_dimensions$version, list(variable = "PARAMCD", values = c("TS1", "TS2"))),
  identical(pedsql_dimensions$reporter, list(variable = "fixed", values = "patient")),
  identical(pedsql_dimensions$subscale, list(variable = "fixed", values = "total_score")),
  identical(statistical_review_dimensions_value(list(dimensions = pedsql_dimensions)), pedsql_dimensions_text)
)
standard_validate_endpoint_dimension(pedsql_dimensions$instrument, "test.fixed.instrument")
stopifnot(inherits(try(standard_validate_endpoint_dimension(list(variable = "fixed", values = c("patient", "parent")), "test.fixed.multivalue"), silent = TRUE), "try-error"))
stopifnot(inherits(try(analysis_specification_parse_dimensions("instrument=PedsQL; unknown=value"), silent = TRUE), "try-error"))

study_parent <- file.path(project_dir, "studies")
study_name <- paste0("zz_standard_profile_test_", Sys.getpid(), "_", sample.int(999999L, 1L))
study_dir <- file.path(study_parent, study_name)
if (dir.exists(study_dir)) stop("测试 study 已存在。")
dir.create(file.path(study_dir, "input"), recursive = TRUE)
dir.create(file.path(study_dir, "backup-trace"), recursive = TRUE)
dir.create(file.path(study_dir, "statistician-review"), recursive = TRUE)
on.exit(unlink(study_dir, recursive = TRUE, force = TRUE), add = TRUE)
checkpoint <- function(stage) writeLines(stage, file.path(study_dir, "checkpoint.txt"), useBytes = TRUE)
checkpoint("study_created")

set.seed(20260812)
subject_count <- 48L
visits <- 1:4
subjects <- sprintf("P%03d", seq_len(subject_count))
arm <- rep(c("ZX-Control", "A-Active"), length.out = subject_count)
baseline <- rnorm(subject_count, 50, 6)
subject_effect <- rnorm(subject_count, 0, 1.2)
data <- do.call(rbind, lapply(seq_len(subject_count), function(i) data.frame(
  PERSON_KEY = subjects[[i]],
  SCORE_DELTA = -0.35 * visits - 1.2 * (arm[[i]] == "A-Active") * visits + 0.025 * baseline[[i]] + subject_effect[[i]] + rnorm(length(visits), 0, 0.8),
  START_SCORE = baseline[[i]],
  TIME_INDEX = visits,
  TIME_TEXT = paste("Cycle", visits),
  RANDOMIZED_ARM = arm[[i]],
  RECORD_USE = "INCLUDE",
  MEASURE_KEY = "SCOREX",
  stringsAsFactors = FALSE
)))
dataset_file <- paste0(study_name, "_scores.csv")
dataset_path <- file.path(study_dir, "input", dataset_file)
write_utf8_bom_csv(data, dataset_path)
dataset_hash <- digest::digest(file = dataset_path, algo = "sha256")
adapter_relative <- gsub("\\\\", "/", file.path("studies", study_name, "analysis", "r", "synthetic_adapter.R"))
adapter_path <- file.path(project_dir, adapter_relative)
dir.create(dirname(adapter_path), recursive = TRUE, showWarnings = FALSE)
adapter_lines <- c(
  "# Approved aggregate-data adapter for the non-study-specific synthetic test.",
  "standard_mmrm_adapter <- function(data, analysis, context) data"
)
writeLines(adapter_lines, adapter_path, useBytes = TRUE)
adapter_hash <- digest::digest(file = adapter_path, algo = "sha256")

analysis_id <- "MMRM-SCOREX-001"
tfl_id <- "TABLE-SCOREX-01"
contract <- list(
  profile_version = standard_mmrm_profile_version(),
  study = list(study_id = study_name),
  execution = list(fail_fast = FALSE),
  analyses = list(list(
    analysis_id = analysis_id,
    tfl_id = tfl_id,
    title = "Randomized score change by cycle",
    dataset = list(file = dataset_file, format = "csv", relative_path = gsub("\\\\", "/", file.path("studies", study_name, "input", dataset_file)), sha256 = toupper(dataset_hash)),
    mappings = list(
      subject = "PERSON_KEY", response = "SCORE_DELTA", baseline = "START_SCORE",
      visit = "TIME_INDEX", visit_label = "TIME_TEXT", treatment = "RANDOMIZED_ARM"
    ),
    treatment = list(
      levels = c("ZX-Control", "A-Active"), reference = "ZX-Control", comparator = "A-Active",
      contrast_direction = "comparator_minus_reference", confidence_level = 0.95,
      multiplicity_adjustment = "none"
    ),
    filters = list(list(variable = "RECORD_USE", operator = "eq", value = "INCLUDE")),
    groups = list(list(
      id = "SCOREX-GROUP", label = "Synthetic randomized score",
      predicates = list(list(variable = "MEASURE_KEY", operator = "eq", value = "SCOREX"))
    )),
    endpoint_definitions = list(list(
      group_id = "SCOREX-GROUP", endpoint_variable = "MEASURE_KEY", selected_codes = "SCOREX",
      selection_mode = "single_code",
      dimensions = list(
        instrument = list(variable = "not_applicable", values = character()),
        version = list(variable = "not_applicable", values = character()),
        reporter = list(variable = "not_applicable", values = character()),
        subscale = list(variable = "not_applicable", values = character())
      ),
      row_allocation_rule = "one_row_per_subject_endpoint_visit"
    )),
    fixed_effects = c("visit", "baseline", "baseline_by_visit", "treatment", "treatment_by_visit"),
    covariance = list(primary = "UN", fallback = c("AR1", "CS")),
    df_method = "Kenward-Roger",
    estimands = list(visit_lsmeans = TRUE, treatment_visit_lsmeans = TRUE, pairwise_differences = TRUE),
    output = list(raw_file = "scorex_mmrm_raw.csv", final_file = "scorex_mmrm_final.csv"),
    adapter_file = adapter_relative, adapter_sha256 = toupper(adapter_hash)
  ))
)
contract_relative <- file.path("studies", study_name, "statistician-review", "standard-mmrm-contract.yaml")
contract_path <- file.path(project_dir, contract_relative)
yaml::write_yaml(contract, contract_path)
contract_hash <- digest::digest(file = contract_path, algo = "sha256")
read_contract <- read_standard_mmrm_contract(contract_path)
stopifnot(identical(standard_contract_get_analysis(read_contract, analysis_id)$tfl_id, tfl_id))
invalid_contract <- contract
invalid_contract$unexpected <- TRUE
stopifnot(inherits(try(validate_standard_mmrm_contract(invalid_contract), silent = TRUE), "try-error"))
invalid_adapter_contract <- contract
invalid_adapter_contract$analyses[[1]]$adapter_sha256 <- NULL
stopifnot(inherits(try(validate_standard_mmrm_contract(invalid_adapter_contract), silent = TRUE), "try-error"))

# Contract and R/SAS predicate parity gates.
valid_predicates <- list(
  list(variable = "X", operator = "eq", value = "A"),
  list(variable = "X", operator = "ne", value = "A"),
  list(variable = "X", operator = "in", value = c("A", "B")),
  list(variable = "X", operator = "not_in", value = c("A", "B")),
  list(variable = "N", operator = "gt", value = 1),
  list(variable = "X", operator = "is_missing")
)
invisible(lapply(seq_along(valid_predicates), function(i) standard_validate_predicate(valid_predicates[[i]], paste0("test.predicate.", i))))
predicate_data <- data.frame(X = c("A", "B", NA), N = c(1, 2, 3), check.names = FALSE)
stopifnot(identical(standard_apply_predicate(predicate_data, valid_predicates[[1]]), c(TRUE, FALSE, FALSE)))
stopifnot(identical(standard_apply_predicate(predicate_data, valid_predicates[[3]]), c(TRUE, TRUE, FALSE)))
stopifnot(grepl("X = \\\"A\\\"", standard_sas_predicate(valid_predicates[[1]])))
stopifnot(grepl("X in \\(\\\"A\\\", \\\"B\\\"\\)", standard_sas_predicate(valid_predicates[[3]])))
invalid_predicates <- list(
  list(variable = "X", operator = "eq", value = c("A", "B")),
  list(variable = "X", operator = "ne", value = NA_character_),
  list(variable = "X", operator = "in", value = character()),
  list(variable = "X", operator = "not_in", value = structure("A", names = "named")),
  list(variable = "X", operator = "in", value = list("A", 1)),
  list(variable = "N", operator = "gt", value = Inf),
  list(variable = "X", operator = "is_missing", value = "A"),
  list(variable = "BAD-NAME", operator = "eq", value = "A")
)
for (predicate in invalid_predicates) {
  stopifnot(inherits(try(standard_validate_predicate(predicate, "negative predicate"), silent = TRUE), "try-error"))
  stopifnot(inherits(try(standard_sas_predicate(predicate), silent = TRUE), "try-error"))
}

missing_treatment_contract <- contract
missing_treatment_contract$analyses[[1]]$treatment <- NULL
stopifnot(inherits(try(validate_standard_mmrm_contract(missing_treatment_contract), silent = TRUE), "try-error"))
forbidden_treatment_contract <- contract
forbidden_treatment_contract$analyses[[1]]$mappings$treatment <- NULL
forbidden_treatment_contract$analyses[[1]]$fixed_effects <- c("visit", "baseline", "baseline_by_visit")
forbidden_treatment_contract$analyses[[1]]$estimands$treatment_visit_lsmeans <- FALSE
forbidden_treatment_contract$analyses[[1]]$estimands$pairwise_differences <- FALSE
stopifnot(inherits(try(validate_standard_mmrm_contract(forbidden_treatment_contract), silent = TRUE), "try-error"))
unsafe_group_contract <- contract
unsafe_group_contract$analyses[[1]]$groups[[1]]$id <- "A/B"
stopifnot(inherits(try(validate_standard_mmrm_contract(unsafe_group_contract), silent = TRUE), "try-error"))
collision_group_contract <- contract
collision_group_contract$analyses[[1]]$groups <- list(
  list(id = "Group", label = "One", predicates = list()),
  list(id = "group", label = "Two", predicates = list())
)
stopifnot(inherits(try(validate_standard_mmrm_contract(collision_group_contract), silent = TRUE), "try-error"))
unsafe_sas_contract <- contract
unsafe_sas_contract$analyses[[1]]$mappings$response <- "BAD-NAME"
stopifnot(inherits(try(validate_standard_mmrm_contract(unsafe_sas_contract), silent = TRUE), "try-error"))
multi_code_single_code_contract <- contract
multi_code_single_code_contract$analyses[[1]]$endpoint_definitions[[1]]$selected_codes <- c("SCOREX", "SCOREY")
stopifnot(inherits(try(validate_standard_mmrm_contract(multi_code_single_code_contract), silent = TRUE), "try-error"))

runtime_dimension_contract <- contract
runtime_dimension_contract$analyses[[1]]$endpoint_definitions[[1]]$dimensions$version <- list(variable = "TIME_TEXT", values = "Cycle 1")
runtime_dimension_failure <- try(standard_prepare_analysis_data(data, runtime_dimension_contract$analyses[[1]], project_dir), silent = TRUE)
stopifnot(inherits(runtime_dimension_failure, "try-error"), grepl("ENDPOINT_MAPPING:", as.character(runtime_dimension_failure), fixed = TRUE))
stopifnot(identical(standard_status_for_failure_domain("contract"), "blocked_mapping"))

prepared_direction <- standard_prepare_analysis_data(data, contract$analyses[[1]], project_dir)
stopifnot(identical(levels(prepared_direction$treatment_f), c("ZX-Control", "A-Active")))
excluded_population_data <- data
excluded_population_data$RECORD_USE[[1L]] <- "EXCLUDE"
prepared_population <- standard_prepare_analysis_data(excluded_population_data, contract$analyses[[1]], project_dir)
stopifnot(identical(attr(prepared_population, "input_rows"), nrow(excluded_population_data)), identical(attr(prepared_population, "population_filtered_rows"), nrow(excluded_population_data) - 1L))
unapproved_data <- data
unapproved_data$RANDOMIZED_ARM[[1]] <- "UNAPPROVED"
stopifnot(inherits(try(standard_prepare_analysis_data(unapproved_data, contract$analyses[[1]], project_dir), silent = TRUE), "try-error"))
one_level_data <- data[data$RANDOMIZED_ARM == "ZX-Control", , drop = FALSE]
stopifnot(inherits(try(standard_prepare_analysis_data(one_level_data, contract$analyses[[1]], project_dir), silent = TRUE), "try-error"))
stopifnot(!isTRUE(standard_contract_fail_fast(contract)), identical(standard_resolve_fail_fast(contract, NULL), FALSE))
stopifnot(identical(standard_resolve_fail_fast(contract, FALSE), FALSE), inherits(try(standard_resolve_fail_fast(contract, TRUE), silent = TRUE), "try-error"))
stopifnot(identical(standard_status_for_failure_domain("contract"), "blocked_mapping"))
stopifnot(identical(standard_status_for_failure_domain("adapter"), "blocked_mapping"))
stopifnot(identical(standard_status_for_failure_domain("environment"), "blocked_environment"))
stopifnot(identical(standard_status_for_failure_domain("data"), "blocked_data"))
stopifnot(identical(standard_status_for_failure_domain("fit"), "fit_failed"))

manifest <- data.frame(
  input_type = "analysis_dataset", file_name = dataset_file,
  relative_path = gsub("\\\\", "/", file.path("studies", study_name, "input", dataset_file)),
  version = "1", file_size_bytes = file.info(dataset_path)$size,
  modified_at = format(file.info(dataset_path)$mtime, "%Y-%m-%dT%H:%M:%S"),
  sha256 = dataset_hash, status = "linked_source", note = "synthetic randomized test",
  stringsAsFactors = FALSE
)
write_utf8_bom_csv(manifest, file.path(study_dir, "backup-trace", "input-manifest.csv"))

endpoint_mapping_relative <- gsub("\\\\", "/", file.path("studies", study_name, "statistician-review", "endpoint-mapping.yaml"))
endpoint_mapping_file_path <- file.path(study_dir, "statistician-review", "endpoint-mapping.yaml")
dir.create(dirname(endpoint_mapping_file_path), recursive = TRUE, showWarnings = FALSE)
yaml::write_yaml(list(mapping_schema_version = "1.0", rows = list(list(
  analysis_id = analysis_id, source_tfl_id = tfl_id, group_id = "SCOREX-GROUP", endpoint_label = "合成评分",
  endpoint_variable = "MEASURE_KEY", selected_codes = "SCOREX", selection_mode = "single_code",
  `instrument / version / reporter / subscale` = "not_applicable", row_allocation_rule = "one_row_per_subject_endpoint_visit",
  source_ref = tfl_id, review_status = "accepted", reviewer_note = "已确认"
))), endpoint_mapping_file_path)
endpoint_mapping_hash <- toupper(specification_sha256(endpoint_mapping_file_path))

metadata <- list(
  schema_version = "1.0", specification_id = paste0(study_name, "-SPEC"), specification_version = "1.0",
  status = "approved", human_readable_language = "zh-CN", generation_route = "statistician_authored",
  approval_mode = "human_review", study_id = study_name, compound = "SYNTHETIC-COMPOUND",
  data_availability = "available", data_classification = "dummy", intended_use = "technical_validation",
  source_input_file = gsub("\\\\", "/", contract_relative), source_input_sha256 = toupper(contract_hash),
  endpoint_mapping_file = endpoint_mapping_relative, endpoint_mapping_sha256 = endpoint_mapping_hash,
  execution_contract_file = gsub("\\\\", "/", contract_relative), execution_contract_sha256 = toupper(contract_hash),
  analysis_ids = analysis_id, tfl_ids = tfl_id,
  review_file = gsub("\\\\", "/", file.path("studies", study_name, "statistician-review", "statistical-review.md")), review_sha256 = paste(rep("0", 64L), collapse = ""),
  reviewed_by = "Synthetic Statistician", reviewed_at_utc = "2026-08-14T12:00:00Z",
  approved_execution_sha256 = paste(rep("0", 64L), collapse = "")
)
body <- c(
  "## 1. 文件状态与使用规则", "本文件已批准用于技术验证。",
  "## 2. Study 和数据上下文", paste("Study", study_name, "使用随机合成数据。"),
  "## 3. MMRM Analysis 清单", paste("Analysis", analysis_id, "。"),
  "## 4. Analysis Specifications", paste("执行", analysis_id, "并遵循 typed contract。"),
  "## 5. TFL 输出清单", paste("输出", tfl_id, "。"),
  "## 6. SAS Template 生成要求", "生成只读输入 SAS 模板。",
  "## 7. 运行与诊断报告要求", "记录模型、推断、风险和路径。",
  "## 8. 完整 QC 要求", "检查缺失、基线一致性、唯一性和水平数。",
  "## 9. 溯源附录", "合成测试溯源。",
  "## 10. 校验结果", "批准校验通过。"
)
spec_path <- file.path(study_dir, "statistician-review", "analysis-specification.md")
write_specification <- function(path, values) {
  writeLines(c("---", strsplit(yaml::as.yaml(values), "\n", fixed = TRUE)[[1]], "---", body), path, useBytes = TRUE)
}
write_specification(spec_path, metadata)
review_path <- file.path(study_dir, "statistician-review", "statistical-review.md")
candidate_table_lines <- function(review_status) {
  categories <- statistical_review_candidate_rule_categories()
  c(
    paste0("### 表 ", tfl_id, "：合成评分 MMRM 汇总"),
    "",
    paste0("| ", paste(statistical_review_candidate_table_columns(), collapse = " | "), " |"),
    "|---|---|---|---|---|---|",
    vapply(categories, function(category) {
      candidate <- if (identical(category, "分析人群")) "RECORD_USE eq \"INCLUDE\"" else "合成候选规则"
      opinion <- if (identical(review_status, "approved")) "确认" else ""
      disposition <- if (!identical(review_status, "approved")) "action=pending" else if (identical(category, "分析人群")) "action=modified;rule=RECORD_USE eq \"INCLUDE\";population_rule=RECORD_USE eq \"INCLUDE\"" else "action=approved;rule=合成候选规则"
      paste0("| ", category, " | ", candidate, " | 合成测试来源；已识别 | 可表达，待统计师确认 | ", opinion, " | ", disposition, " |")
    }, character(1))
  )
}
write_statistical_review <- function(path, execution_sha256, review_status = "approved") {
  review_metadata <- list(
    review_schema_version = "1.1", study_id = study_name, generation_route = "statistician_authored",
    review_status = review_status,
    finalization_status = if (identical(review_status, "approved")) "ready_for_final_signature" else "",
    reviewed_by = if (identical(review_status, "approved")) "Synthetic Statistician" else "",
    reviewed_at_utc = if (identical(review_status, "approved")) "2026-08-14T12:00:00Z" else "",
    approved_execution_sha256 = if (identical(review_status, "approved")) toupper(execution_sha256) else "",
    source_input_file = gsub("\\\\", "/", contract_relative), source_input_sha256 = toupper(contract_hash)
  )
  review_body <- c(
    "## 1. 审阅结论与签核", "已批准合成技术验证。",
    "## 2. Study 与数据范围", "合成随机数据和已固定 contract。",
    "## 3. Analysis 与 TFL 清单", paste(analysis_id, "对应", tfl_id, "。"), candidate_table_lines(review_status),
    "## 4. Endpoint Mapping 与分组确认",
    "| analysis_id | source_tfl_id | group_id | endpoint_label | endpoint_variable | selected_codes | selection_mode | instrument / version / reporter / subscale | row_allocation_rule | source_ref | review_status | reviewer_note |",
    "|---|---|---|---|---|---|---|---|---|---|---|---|",
    paste0("| ", analysis_id, " | ", tfl_id, " | SCOREX-GROUP | 合成评分 | MEASURE_KEY | SCOREX | single_code | not_applicable | one_row_per_subject_endpoint_visit | ", tfl_id, " | accepted | 已确认 |"),
    "## 5. 模型、协方差与估计量确认", "已确认 MMRM、协方差和估计量。",
    "## 6. Adapter / 派生 / 行分配确认", "Adapter 已固定；每个 subject、endpoint 和 visit 最多一行。",
    "## 7. 未解决问题与决议",
    "| issue_id | scope | question_or_risk | resolution | status |",
    "|---|---|---|---|---|",
    "## 8. Execution 内容指纹", toupper(execution_sha256)
  )
  writeLines(c("---", strsplit(yaml::as.yaml(review_metadata), "\n", fixed = TRUE)[[1]], "---", review_body), path, useBytes = TRUE)
}
execution_sha256 <- analysis_specification_execution_sha256(read_analysis_specification(spec_path))
write_statistical_review(review_path, execution_sha256)
metadata$review_sha256 <- toupper(specification_sha256(review_path))
metadata$approved_execution_sha256 <- toupper(execution_sha256)
write_specification(spec_path, metadata)
valid_review <- validate_statistical_review(read_statistical_review(review_path), read_analysis_specification(spec_path))
stopifnot(valid_review$metadata_valid, valid_review$sections_valid, valid_review$candidate_tables_valid, valid_review$mapping_valid, valid_review$issues_valid, valid_review$identity_valid, valid_review$execution_match)
invalid_candidate_lines <- readLines(review_path, warn = FALSE, encoding = "UTF-8")
invalid_candidate_lines <- sub("action=approved;rule=合成候选规则", "action=pending", invalid_candidate_lines, fixed = TRUE)
writeLines(invalid_candidate_lines, review_path, useBytes = TRUE)
invalid_candidate <- validate_statistical_review(read_statistical_review(review_path), read_analysis_specification(spec_path))
stopifnot(!invalid_candidate$candidate_tables_valid)
write_statistical_review(review_path, execution_sha256)
valid_checks <- validate_analysis_specification(spec_path, project_root = project_dir)
stopifnot(any(valid_checks$check_id == "SPEC-ENDPOINT-MAPPING-CONTRACT-MATCH" & valid_checks$result == "Pass"))

mismatched_review_lines <- readLines(review_path, warn = FALSE, encoding = "UTF-8")
mismatched_review_lines <- sub("\\| SCOREX \\| single_code \\|", "| UNAPPROVED_CODE | single_code |", mismatched_review_lines)
writeLines(mismatched_review_lines, review_path, useBytes = TRUE)
mismatched_metadata <- metadata
mismatched_metadata$review_sha256 <- toupper(specification_sha256(review_path))
write_specification(spec_path, mismatched_metadata)
mismatched_mapping_checks <- validate_analysis_specification(spec_path, project_root = project_dir)
stopifnot(any(mismatched_mapping_checks$check_id == "SPEC-ENDPOINT-MAPPING-CONTRACT-MATCH" & mismatched_mapping_checks$result == "Fail"))
write_statistical_review(review_path, execution_sha256)
metadata$review_sha256 <- toupper(specification_sha256(review_path))
write_specification(spec_path, metadata)

stopifnot(inherits(try(normalize_project_relative_path(contract_path, project_dir, "test.absolute"), silent = TRUE), "try-error"))
stopifnot(inherits(try(normalize_project_relative_path("../outside.yaml", project_dir, "test.parent"), silent = TRUE), "try-error"))
for (unsafe_path in c(contract_path, "../outside.yaml")) {
  unsafe_metadata <- metadata
  unsafe_metadata$execution_contract_file <- unsafe_path
  unsafe_spec <- file.path(study_dir, "statistician-review", paste0("unsafe-", length(list.files(file.path(study_dir, "statistician-review"))), ".md"))
  write_specification(unsafe_spec, unsafe_metadata)
  unsafe_checks <- validate_analysis_specification(unsafe_spec, project_root = project_dir)
  stopifnot(any(unsafe_checks$check_id == "SPEC-CONTRACT-PATH" & unsafe_checks$result == "Fail"))
}
automatic_metadata <- metadata
automatic_metadata$approval_mode <- "automatic_after_validation"
automatic_spec <- file.path(study_dir, "statistician-review", "automatic-after-validation.md")
write_specification(automatic_spec, automatic_metadata)
automatic_checks <- validate_analysis_specification(automatic_spec, project_root = study_dir)
stopifnot(any(automatic_checks$check_id == "SPEC-ROUTE" & automatic_checks$result == "Fail"))

rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
run_script <- function(script, arguments = character(), allow_nonzero = FALSE) {
  result <- tryCatch(callr::r(
    function(executable, child_script, child_arguments) {
      output <- suppressWarnings(system2(
        executable,
        c("--vanilla", shQuote(child_script), child_arguments),
        stdout = TRUE, stderr = TRUE, wait = TRUE
      ))
      status <- attr(output, "status")
      if (is.null(status)) status <- 0L
      list(output = output, status = status)
    },
    args = list(executable = rscript, child_script = script, child_arguments = arguments),
    spinner = FALSE, show = FALSE
  ), error = function(e) e)
  if (inherits(result, "error")) {
    if (!allow_nonzero) stop("命令进程失败：", script, "\n", conditionMessage(result))
    return(invisible(list(output = conditionMessage(result), status = 1L)))
  }
  if (result$status != 0L && !allow_nonzero) stop("命令失败：", script, "\n", paste(result$output, collapse = "\n"))
  invisible(result)
}

generator <- file.path(project_dir, ".codex", "study-mmrm-analysis", "scripts", "generate_standard_study.R")
intake_generator <- file.path(project_dir, ".codex", "study-mmrm-analysis", "scripts", "generate_intake_review.R")
intake_study_dir <- file.path(study_parent, paste0("zz_intake_review_test_", Sys.getpid(), "_", sample.int(999999L, 1L)))
dir.create(file.path(intake_study_dir, "input", "shell"), recursive = TRUE)
dir.create(file.path(intake_study_dir, "backup-trace"), recursive = TRUE)
dir.create(file.path(intake_study_dir, "statistician-review"), recursive = TRUE)
intake_shell_path <- file.path(intake_study_dir, "input", "shell", "mmrm-shell.txt")
writeLines(c("表1.2.3 疼痛强度-MMRM-汇总（COA分析集）", "重复测量的混合模型（MMRM）"), intake_shell_path, useBytes = TRUE)
intake_manifest <- data.frame(
  input_type = "analysis_source", file_name = "mmrm-shell.txt", relative_path = "input/shell/mmrm-shell.txt",
  version = "1", file_size_bytes = file.info(intake_shell_path)$size,
  modified_at = format(file.info(intake_shell_path)$mtime, "%Y-%m-%dT%H:%M:%S"),
  sha256 = toupper(digest::digest(file = intake_shell_path, algo = "sha256")), status = "registered_input",
  note = "intake review smoke test", stringsAsFactors = FALSE
)
write_utf8_bom_csv(intake_manifest, file.path(intake_study_dir, "backup-trace", "input-manifest.csv"))
run_script(intake_generator, c(shQuote(paste0("--study-dir=", intake_study_dir)), "--route=ai_source_extraction"))
intake_review_path <- file.path(intake_study_dir, "statistician-review", "statistical-review.md")
intake_review <- read_statistical_review(intake_review_path)
intake_tables <- parse_statistical_review_candidate_tables(intake_review)
stopifnot(
  identical(as.character(intake_review$metadata$review_status), "pending"), length(intake_tables) == 1L,
  identical(intake_tables[[1]]$tfl_id, "1.2.3"),
  identical(as.character(intake_tables[[1]]$table[["规则类别"]]), statistical_review_candidate_rule_categories()),
  all(intake_tables[[1]]$table[["结构化处置"]] == "action=pending")
)
writeLines(sub("review_status: pending", "review_status: approved", readLines(intake_review_path, warn = FALSE, encoding = "UTF-8"), fixed = TRUE), intake_review_path, useBytes = TRUE)
approved_intake_overwrite <- run_script(intake_generator, c(shQuote(paste0("--study-dir=", intake_study_dir)), "--route=ai_source_extraction", "--replace-pending=true"), allow_nonzero = TRUE)
stopifnot(approved_intake_overwrite$status != 0L)
unlink(intake_study_dir, recursive = TRUE, force = TRUE)
pending_execution_sha256 <- execution_sha256
write_statistical_review(review_path, pending_execution_sha256, review_status = "pending")
pending_metadata <- metadata
pending_metadata$review_sha256 <- toupper(specification_sha256(review_path))
write_specification(spec_path, pending_metadata)
pending_checks <- validate_analysis_specification(spec_path, project_root = study_dir)
stopifnot(any(pending_checks$check_id == "SPEC-REVIEW-GATE" & pending_checks$result == "Fail"))
pending_generation <- run_script(generator, shQuote(paste0("--study-dir=", study_dir)), allow_nonzero = TRUE)
stopifnot(pending_generation$status != 0L, !dir.exists(file.path(study_dir, "output")))

write_statistical_review(review_path, execution_sha256)
metadata$review_sha256 <- toupper(specification_sha256(review_path))
write_specification(spec_path, metadata)
writeLines(c(readLines(review_path, warn = FALSE, encoding = "UTF-8"), "tampered"), review_path, useBytes = TRUE)
tampered_review_checks <- validate_analysis_specification(spec_path, project_root = study_dir)
stopifnot(any(tampered_review_checks$check_id == "SPEC-REVIEW-FILE-MATCH" & tampered_review_checks$result == "Fail"))
tampered_review_generation <- run_script(generator, shQuote(paste0("--study-dir=", study_dir)), allow_nonzero = TRUE)
stopifnot(tampered_review_generation$status != 0L, !dir.exists(file.path(study_dir, "output")))
write_statistical_review(review_path, execution_sha256)
metadata$review_sha256 <- toupper(specification_sha256(review_path))
write_specification(spec_path, metadata)

run_script(generator, shQuote(paste0("--study-dir=", study_dir)))
cat("Generated synthetic study.\n"); flush.console(); checkpoint("generated")
stopifnot(!dir.exists(file.path(study_dir, "output")))
wrapper <- file.path(study_dir, "analysis", "r", paste0(analysis_id, ".R"))
collector <- file.path(study_dir, "analysis", "r", "run_all_mmrm.R")
sas_template <- file.path(study_dir, "analysis", "sas", paste0(analysis_id, "_template.sas"))
stopifnot(file.exists(wrapper), file.exists(collector), file.exists(sas_template))

# SAS activation/identity text and generator no-write-on-preflight-failure.
regular_analysis <- contract$analyses[[1]]
regular_analysis$adapter_file <- NULL
regular_analysis$adapter_sha256 <- NULL
sas_lines <- render_standard_sas_template(contract, regular_analysis, specification_sha256(spec_path), contract_hash)
sas_text <- paste(sas_lines, collapse = "\n")
stopifnot(grepl("execute_approved_template=YES", sas_text, fixed = TRUE))
stopifnot(grepl("%abort cancel;", sas_text, fixed = TRUE))
stopifnot(regexpr("%abort cancel;", sas_text, fixed = TRUE)[[1]] < regexpr("proc import", sas_text, fixed = TRUE)[[1]])
for (required_sas in c("LSMeans=work._mmrm_lsmeans", "Diffs=work._mmrm_diffs", "SolutionF=work._mmrm_solutionf", "ConvergenceStatus=work._mmrm_convergence_status", "ref=\"ZX-Control\"", "diff=control(\"ZX-Control\")", "alpha=0.05", "multiplicity_adjustment=none", "options validvarname=v7")) {
  stopifnot(grepl(required_sas, sas_text, fixed = TRUE))
}
stopifnot(!grepl("validvarname=any", sas_text, fixed = TRUE))
adapter_sas_text <- paste(readLines(sas_template, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
stopifnot(grepl("execute_approved_template=YES", adapter_sas_text, fixed = TRUE), grepl("sas_adapter_required", adapter_sas_text, fixed = TRUE))

generated_paths <- c(wrapper, collector, sas_template)
generated_hashes <- function() vapply(generated_paths, function(path) digest::digest(file = path, algo = "sha256"), character(1))
generated_before_failure <- generated_hashes()
writeLines(c(adapter_lines, "# tampered before generation"), adapter_path, useBytes = TRUE)
tampered_generation <- run_script(generator, shQuote(paste0("--study-dir=", study_dir)), allow_nonzero = TRUE)
stopifnot(tampered_generation$status != 0L, identical(generated_before_failure, generated_hashes()))
writeLines(adapter_lines, adapter_path, useBytes = TRUE)
adapter_hold <- paste0(adapter_path, ".missing-hold")
stopifnot(file.rename(adapter_path, adapter_hold))
missing_generation <- run_script(generator, shQuote(paste0("--study-dir=", study_dir)), allow_nonzero = TRUE)
stopifnot(missing_generation$status != 0L, !file.exists(adapter_path), identical(generated_before_failure, generated_hashes()))
stopifnot(file.rename(adapter_hold, adapter_path))
stopifnot(identical(toupper(digest::digest(file = adapter_path, algo = "sha256")), toupper(adapter_hash)))

wrapper_initial <- run_script(wrapper, allow_nonzero = TRUE)
if (wrapper_initial$status != 0L) {
  initial_log <- file.path(study_dir, "output", "analyses", analysis_id, "logs", "run.log")
  log_text <- if (file.exists(initial_log)) paste(readLines(initial_log, warn = FALSE, encoding = "UTF-8"), collapse = "\n") else "<missing log>"
  stop("Standalone wrapper failed:\n", paste(wrapper_initial$output, collapse = "\n"), "\nAnalysis log:\n", log_text)
}
cat("Standalone wrapper completed.\n"); flush.console(); checkpoint("wrapper_completed")
run_script(collector, "--mode=run-and-collect")
cat("Run-and-collect completed with contract fail_fast default.\n"); flush.console(); checkpoint("run_and_collect_completed")
initial_summary_text <- paste(readLines(file.path(study_dir, "output", "mmrm-run-summary.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
stopifnot(grepl("有效 fail_fast：`false`", initial_summary_text, fixed = TRUE))
stopifnot(grepl("中文风险", initial_summary_text, fixed = TRUE), grepl("最终 covariance", initial_summary_text, fixed = TRUE))
run_record_path <- file.path(study_dir, "output", "analyses", analysis_id, "analysis-run-record.csv")
run_record_before <- standard_read_csv_schema(run_record_path, standard_required_run_record_columns(), "test run record")
run_id_before <- run_record_before$run_id[[1]]
stopifnot(
  run_record_before$specification_id[[1]] == metadata$specification_id,
  run_record_before$specification_version[[1]] == metadata$specification_version,
  run_record_before$title[[1]] == contract$analyses[[1]]$title,
  run_record_before$tfl_type[[1]] == "table",
  run_record_before$scope_status[[1]] == "approved"
)
stable_files <- c(wrapper, list.files(file.path(study_dir, "output", "analyses", analysis_id), recursive = TRUE, full.names = TRUE))
stable_files <- sort(stable_files[file.exists(stable_files)])
stable_hashes_before <- vapply(stable_files, function(path) digest::digest(file = path, algo = "sha256"), character(1))
run_script(collector, "--mode=collect-only")
cat("Collect-only completed.\n"); flush.console(); checkpoint("collect_only_completed")
run_record_after <- standard_read_csv_schema(run_record_path, standard_required_run_record_columns(), "test run record")
stable_hashes_after <- vapply(stable_files, function(path) digest::digest(file = path, algo = "sha256"), character(1))
stopifnot(identical(run_id_before, run_record_after$run_id[[1]]), identical(stable_hashes_before, stable_hashes_after))

manifest_path <- file.path(study_dir, "output", "tfl-output-manifest.csv")
diagnostics_path <- file.path(study_dir, "output", "mmrm-run-diagnostics.csv")
manifest_result <- standard_read_csv_schema(manifest_path, names(standard_output_manifest_schema()), "test manifest")
diagnostics <- standard_read_csv_schema(diagnostics_path, standard_required_diagnostic_columns(), "test diagnostics")
stopifnot(nrow(manifest_result) == 1L)
stopifnot(identical(names(manifest_result), names(standard_output_manifest_schema())))
stopifnot(!any(c("analysis_id", "run_id", "invocation_id") %in% names(manifest_result)))
standard_validate_output_manifest(manifest_result)
stopifnot(manifest_result$tfl_id[[1]] == tfl_id, manifest_result$tfl_type[[1]] == "table", manifest_result$scope_status[[1]] == "approved")
if (!manifest_result$output_status[[1]] %in% c("complete", "partial")) {
  stop("collector 未收集成功 artifact；status=", manifest_result$output_status[[1]], "；note=", manifest_result$note[[1]])
}
stopifnot(nrow(diagnostics) == 1L)
stopifnot(diagnostics$convergence_status[[1]] == "converged", diagnostics$inference_complete[[1]] == "yes")
stopifnot(diagnostics$failure_domain[[1]] == "none", diagnostics$failure_phase[[1]] == "completed")
raw <- read_utf8_bom_csv(file.path(project_dir, manifest_result$raw_output_file[[1]]))
final <- read_utf8_bom_csv(file.path(project_dir, manifest_result$final_tfl_file[[1]]))
report_text <- paste(readLines(file.path(study_dir, "output", "analyses", analysis_id, "diagnostics", "mmrm-run-diagnostic-report.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
stopifnot(grepl("中文计算风险", report_text, fixed = TRUE))
stopifnot(grepl("数据类别", report_text, fixed = TRUE), grepl("Primary covariance", report_text, fixed = TRUE))
stopifnot(grepl("SAS status", report_text, fixed = TRUE), grepl("Formal manifest", report_text, fixed = TRUE))
stopifnot(!grepl("Computational risk:", report_text, fixed = TRUE))
  stopifnot(nrow(raw) > 0L, nrow(final) > 0L)
  stopifnot(all(c("observed_n", "observed_mean", "observed_sd", "baseline_mean", "mmrm_estimate", "row_type") %in% names(final)))
  observed_final <- final[final$row_type == "observed_with_mmrm", , drop = FALSE]
  contrast_final <- final[final$row_type == "mmrm_contrast", , drop = FALSE]
  stopifnot(nrow(observed_final) == length(visits) * length(unique(arm)))
  stopifnot(nrow(contrast_final) == length(visits))
  stopifnot(all(as.integer(observed_final$observed_n) > 0L))
  stopifnot(any(nzchar(observed_final$observed_mean)), any(nzchar(observed_final$mmrm_estimate)))
  prepared_for_failed_final <- standard_prepare_analysis_data(data, contract$analyses[[1]], project_dir)
  failed_final <- standard_build_shell_like_final(standard_raw_result_schema(), prepared_for_failed_final, contract$analyses[[1]], "fit_failed")
  stopifnot(nrow(failed_final) == length(visits) * length(unique(arm)))
  stopifnot(all(failed_final$row_type == "observed_with_mmrm"))
  stopifnot(all(as.integer(failed_final$observed_n) > 0L))
  stopifnot(all(!nzchar(failed_final$mmrm_estimate)), all(failed_final$status == "fit_failed"))
  stopifnot(all(c("visit_lsmean", "treatment_visit_lsmean", "treatment_pairwise_difference") %in% unique(raw$estimand)))
contrast_rows <- raw[raw$estimand == "treatment_pairwise_difference", , drop = FALSE]
stopifnot(nrow(contrast_rows) == length(visits))
stopifnot(identical(unique(contrast_rows$contrast), "A-Active - ZX-Control"))
stopifnot(all(contrast_rows$emmean < 0))
cat("CSV and diagnostics assertions passed.\n"); flush.console(); checkpoint("csv_assertions_passed")
model_paths <- unique(diagnostics$model_file[nzchar(diagnostics$model_file)])
stopifnot(length(model_paths) == 1L)
model_path <- file.path(project_dir, model_paths[[1]])
stopifnot(file.exists(model_path))
rds_details <- callr::r(function(path) {
  model <- readRDS(path)
  formula_parts <- stats::formula(model)
  formula_object <- if (is.list(formula_parts) && !is.null(formula_parts$formula)) formula_parts$formula else formula_parts
  details <- list(
    is_mmrm = inherits(model, "mmrm"),
    identity = attr(model, "standard_artifact_identity", exact = TRUE),
    formula = paste(deparse(formula_object, width.cutoff = 500L), collapse = " ")
  )
  rm(model)
  invisible(gc())
  details
}, args = list(path = model_path), spinner = FALSE, show = FALSE)
expected_formula <- standard_formula_text(standard_fixed_formula(contract$analyses[[1]], diagnostics$final_covariance[[1]]))
expected_identity <- list(
  study_id = study_name, analysis_id = analysis_id, group_id = "SCOREX-GROUP",
  profile = standard_mmrm_profile_version(), profile_version = standard_mmrm_profile_version(),
  specification_id = metadata$specification_id, specification_version = metadata$specification_version,
  specification_sha256 = toupper(specification_sha256(spec_path)), contract_sha256 = toupper(contract_hash),
  adapter_sha256 = toupper(adapter_hash),
  run_id = run_record_after$run_id[[1]], invocation_id = run_record_after$invocation_id[[1]],
  treatment_levels = "ZX-Control|A-Active", treatment_reference = "ZX-Control", treatment_comparator = "A-Active",
  contrast_direction = "comparator_minus_reference", confidence_level = "0.95", multiplicity_adjustment = "none",
  covariance = diagnostics$final_covariance[[1]], formula = expected_formula
)
stopifnot(isTRUE(rds_details$is_mmrm), identical(rds_details$formula, expected_formula))
stopifnot(all(vapply(names(expected_identity), function(name) {
  identical(as.character(rds_details$identity[[name]]), as.character(expected_identity[[name]]))
}, logical(1))))

paths <- study_paths(wrapper)
approved_spec <- assert_approved_specification(spec_path, project_root = project_dir)
validated <- standard_validate_analysis_artifacts(paths, approved_spec, read_contract, contract$analyses[[1]])
stopifnot(nrow(validated$raw) > 0L, nrow(validated$final) > 0L)

record_original <- standard_read_csv_schema(run_record_path, standard_required_run_record_columns(), "test run record")
record_tampered <- record_original
record_tampered$specification_id[[1]] <- "WRONG-SPEC"
write_utf8_bom_csv(record_tampered, run_record_path)
stopifnot(inherits(try(standard_validate_analysis_artifacts(paths, approved_spec, read_contract, contract$analyses[[1]]), silent = TRUE), "try-error"))
write_utf8_bom_csv(record_original, run_record_path)
raw_path <- file.path(project_dir, manifest_result$raw_output_file[[1]])
raw_original <- read_utf8_bom_csv(raw_path)
write_utf8_bom_csv(raw_original[0, , drop = FALSE], raw_path)
stopifnot(inherits(try(standard_validate_analysis_artifacts(paths, approved_spec, read_contract, contract$analyses[[1]]), silent = TRUE), "try-error"))
write_utf8_bom_csv(raw_original, raw_path)
model_backup <- paste0(model_path, ".identity-backup")
stopifnot(file.copy(model_path, model_backup, overwrite = TRUE))
callr::r(function(path) {
  model <- readRDS(path)
  identity <- attr(model, "standard_artifact_identity", exact = TRUE)
  identity$analysis_id <- "WRONG-ANALYSIS"
  attr(model, "standard_artifact_identity") <- identity
  saveRDS(model, path)
  rm(model)
  invisible(gc())
}, args = list(path = model_path), spinner = FALSE, show = FALSE)
stopifnot(inherits(try(standard_validate_analysis_artifacts(paths, approved_spec, read_contract, contract$analyses[[1]]), silent = TRUE), "try-error"))
stopifnot(file.copy(model_backup, model_path, overwrite = TRUE))
unlink(model_backup, force = TRUE)
standard_validate_analysis_artifacts(paths, approved_spec, read_contract, contract$analyses[[1]])

case_summary_script <- file.path(project_dir, ".codex", "study-mmrm-analysis", "scripts", "generate_case_summary.R")
run_script(case_summary_script, shQuote(paste0("--study-dir=", study_dir)))
case_summary_path <- file.path(study_dir, "backup-trace", "study-case-summary.yaml")
stopifnot(file.exists(case_summary_path))
case_summary <- yaml::read_yaml(case_summary_path, eval.expr = FALSE)
validate_standard_case_summary(case_summary)
stopifnot(all(c("adapter_patterns", "pattern_candidates", "pattern_evidence") %in% names(case_summary)))
stopifnot(identical(case_summary$promotion$engine_change, "not_promoted"), identical(case_summary$adapter_patterns$registry, list()))
stale_record <- standard_read_csv_schema(run_record_path, standard_required_run_record_columns(), "stale run record")
stale_record$contract_sha256[[1]] <- paste(rep("0", 64L), collapse = "")
write_utf8_bom_csv(stale_record, run_record_path)
stale_summary <- standard_case_summary(paths, read_contract)
stale_record_summary <- stale_summary$run_records[[match(analysis_id, vapply(stale_summary$run_records, `[[`, character(1), "analysis_id"))]]
stopifnot(identical(stale_record_summary$run_id, "collector-synthesized"), identical(stale_record_summary$output_status, manifest_result$output_status[[1]]))
write_utf8_bom_csv(run_record_before, run_record_path)
promoted_summary <- case_summary
promoted_summary$adapter_patterns$registry <- list(list(
  pattern_id = "PATTERN-1", adapter_family = "aggregate_adapter", description = "Approved aggregate transformation", status = "promoted"
))
promoted_summary$pattern_evidence <- list(
  list(
    evidence_id = "EVIDENCE-1", pattern_id = "PATTERN-1", study_id = "STUDY-A", analysis_id = "ANALYSIS-A",
    aggregate_analysis_count = 1L, aggregate_success_count = 1L, aggregate_failure_count = 0L,
    aggregate_status = "complete", independent_study = TRUE, aggregate_only = TRUE, status = "accepted"
  ),
  list(
    evidence_id = "EVIDENCE-2", pattern_id = "PATTERN-1", study_id = "STUDY-B", analysis_id = "ANALYSIS-B",
    aggregate_analysis_count = 2L, aggregate_success_count = 2L, aggregate_failure_count = 0L,
    aggregate_status = "complete", independent_study = TRUE, aggregate_only = TRUE, status = "accepted"
  )
)
promoted_summary$adapter_patterns$promotion_records <- list(list(
  pattern_id = "PATTERN-1", decision = "approved", reviewed_by = "independent-reviewer",
  reviewed_at = "2026-08-13T15:47:02Z", evidence_ids = c("EVIDENCE-1", "EVIDENCE-2"),
  regression_test_status = "passed", note = "Approved for a future versioned profile"
))
promoted_summary$promotion$status <- "promoted"
promoted_summary$promotion$engine_change <- "approved_for_next_profile"
validate_standard_case_summary(promoted_summary)
expect_case_failure <- function(value) stopifnot(inherits(try(validate_standard_case_summary(value), silent = TRUE), "try-error"))

single_study_summary <- promoted_summary
single_study_summary$pattern_evidence[[2]]$study_id <- "STUDY-A"
expect_case_failure(single_study_summary)
false_aggregate_summary <- promoted_summary
false_aggregate_summary$pattern_evidence[[1]]$aggregate_only <- FALSE
expect_case_failure(false_aggregate_summary)
non_independent_summary <- promoted_summary
non_independent_summary$pattern_evidence[[1]]$independent_study <- FALSE
expect_case_failure(non_independent_summary)
empty_reviewer_summary <- promoted_summary
empty_reviewer_summary$adapter_patterns$promotion_records[[1]]$reviewed_by <- ""
expect_case_failure(empty_reviewer_summary)
failed_regression_summary <- promoted_summary
failed_regression_summary$adapter_patterns$promotion_records[[1]]$regression_test_status <- "failed"
expect_case_failure(failed_regression_summary)
subject_like_summary <- promoted_summary
subject_like_summary$pattern_evidence[[1]]$aggregate_status <- "subject P001"
expect_case_failure(subject_like_summary)
nested_evidence_summary <- promoted_summary
nested_evidence_summary$pattern_evidence[[1]]$aggregate_status <- list(list(subject_id = "P001"))
expect_case_failure(nested_evidence_summary)
duplicate_evidence_summary <- promoted_summary
duplicate_evidence_summary$pattern_evidence[[2]]$evidence_id <- "EVIDENCE-1"
expect_case_failure(duplicate_evidence_summary)
wrong_pattern_summary <- promoted_summary
wrong_pattern_summary$pattern_evidence[[2]]$pattern_id <- "MISSING-PATTERN"
expect_case_failure(wrong_pattern_summary)
free_aggregate_summary <- promoted_summary
free_aggregate_summary$pattern_evidence[[1]]$aggregate_summary <- "subject P001"
expect_case_failure(free_aggregate_summary)
bad_record_summary <- case_summary
bad_record_summary$run_records[[1]]$subject_rows <- list(list(subject_id = "P001"))
expect_case_failure(bad_record_summary)

writeLines(c(adapter_lines, "# unauthorized mutation"), adapter_path, useBytes = TRUE)
adapter_error <- try(standard_load_adapter(project_dir, adapter_relative, toupper(adapter_hash)), silent = TRUE)
stopifnot(inherits(adapter_error, "try-error"), grepl("adapter_file SHA-256", as.character(adapter_error), fixed = TRUE))
adapter_rejection <- run_script(wrapper, allow_nonzero = TRUE)
stopifnot(adapter_rejection$status != 0L)
blocked_adapter_record <- standard_read_csv_schema(run_record_path, standard_required_run_record_columns(), "blocked adapter record")
blocked_adapter_diagnostics <- standard_read_csv_schema(file.path(study_dir, "output", "analyses", analysis_id, "diagnostics", "mmrm-run-diagnostics.csv"), standard_required_diagnostic_columns(), "blocked adapter diagnostics")
stopifnot(blocked_adapter_record$output_status[[1]] == "blocked_mapping")
stopifnot(blocked_adapter_diagnostics$failure_domain[[1]] == "adapter", blocked_adapter_diagnostics$failure_phase[[1]] == "approved_adapter_gate")
writeLines(adapter_lines, adapter_path, useBytes = TRUE)
stopifnot(identical(toupper(digest::digest(file = adapter_path, algo = "sha256")), toupper(adapter_hash)))

# Ordered two-TFL collector regression: a valid blocked terminal artifact must not prevent the next TFL from running.
dual_study_name <- paste0("zz_standard_profile_dual_tfl_", Sys.getpid(), "_", sample.int(999999L, 1L))
dual_study_dir <- file.path(study_parent, dual_study_name)
dir.create(file.path(dual_study_dir, "input"), recursive = TRUE)
dir.create(file.path(dual_study_dir, "backup-trace"), recursive = TRUE)
dir.create(file.path(dual_study_dir, "statistician-review"), recursive = TRUE)
on.exit(unlink(dual_study_dir, recursive = TRUE, force = TRUE), add = TRUE)
dual_dataset_file <- paste0(dual_study_name, "_scores.csv")
dual_dataset_path <- file.path(dual_study_dir, "input", dual_dataset_file)
write_utf8_bom_csv(data, dual_dataset_path)
write_utf8_bom_csv(data.frame(
  input_type = "analysis_dataset", file_name = dual_dataset_file,
  relative_path = gsub("\\\\", "/", file.path("studies", dual_study_name, "input", dual_dataset_file)),
  version = "1", file_size_bytes = file.info(dual_dataset_path)$size,
  modified_at = format(file.info(dual_dataset_path)$mtime, "%Y-%m-%dT%H:%M:%S"),
  sha256 = digest::digest(file = dual_dataset_path, algo = "sha256"), status = "linked_source",
  note = "ordered dual TFL continuation regression", stringsAsFactors = FALSE
), file.path(dual_study_dir, "backup-trace", "input-manifest.csv"))

dual_analysis_ids <- c("MMRM-SCOREX-TERMINAL", "MMRM-SCOREX-CONTINUES")
dual_tfl_ids <- c("TABLE-SCOREX-TERMINAL", "TABLE-SCOREX-CONTINUES")
dual_adapter_paths <- file.path(project_dir, "studies", dual_study_name, "analysis", "r", c("blocked_adapter.R", "continues_adapter.R"))
dir.create(dirname(dual_adapter_paths[[1]]), recursive = TRUE, showWarnings = FALSE)
writeLines(adapter_lines, dual_adapter_paths[[1]], useBytes = TRUE)
writeLines(adapter_lines, dual_adapter_paths[[2]], useBytes = TRUE)
dual_contract <- contract
dual_contract$study$study_id <- dual_study_name
dual_contract$analyses <- lapply(seq_along(dual_analysis_ids), function(i) {
  analysis <- contract$analyses[[1]]
  analysis$analysis_id <- dual_analysis_ids[[i]]
  analysis$tfl_id <- dual_tfl_ids[[i]]
  analysis$title <- paste("Ordered dual-TFL", if (i == 1L) "blocked terminal artifact" else "continues after terminal artifact")
  analysis$dataset <- list(file = dual_dataset_file, format = "csv", relative_path = gsub("\\\\", "/", file.path("studies", dual_study_name, "input", dual_dataset_file)), sha256 = toupper(digest::digest(file = dual_dataset_path, algo = "sha256")))
  analysis$output <- list(raw_file = paste0("dual_", i, "_raw.csv"), final_file = paste0("dual_", i, "_final.csv"))
  analysis$adapter_file <- gsub("\\\\", "/", file.path("studies", dual_study_name, "analysis", "r", basename(dual_adapter_paths[[i]])))
  analysis$adapter_sha256 <- toupper(digest::digest(file = dual_adapter_paths[[i]], algo = "sha256"))
  analysis
})
dual_contract_relative <- file.path("studies", dual_study_name, "statistician-review", "standard-mmrm-contract.yaml")
dual_contract_path <- file.path(project_dir, dual_contract_relative)
yaml::write_yaml(dual_contract, dual_contract_path)
dual_contract_hash <- digest::digest(file = dual_contract_path, algo = "sha256")
dual_metadata <- metadata
dual_metadata$specification_id <- paste0(dual_study_name, "-SPEC")
dual_metadata$study_id <- dual_study_name
dual_metadata$source_input_file <- gsub("\\\\", "/", dual_contract_relative)
dual_metadata$source_input_sha256 <- toupper(dual_contract_hash)
dual_metadata$execution_contract_file <- gsub("\\\\", "/", dual_contract_relative)
dual_metadata$execution_contract_sha256 <- toupper(dual_contract_hash)
dual_metadata$analysis_ids <- dual_analysis_ids
dual_metadata$tfl_ids <- dual_tfl_ids
dual_endpoint_mapping_path <- file.path(dual_study_dir, "statistician-review", "endpoint-mapping.yaml")
dir.create(dirname(dual_endpoint_mapping_path), recursive = TRUE, showWarnings = FALSE)
yaml::write_yaml(list(mapping_schema_version = "1.0", rows = lapply(seq_along(dual_analysis_ids), function(i) list(
  analysis_id = dual_analysis_ids[[i]], source_tfl_id = dual_tfl_ids[[i]], group_id = "SCOREX-GROUP", endpoint_label = "合成评分",
  endpoint_variable = "MEASURE_KEY", selected_codes = "SCOREX", selection_mode = "single_code",
  `instrument / version / reporter / subscale` = "not_applicable", row_allocation_rule = "one_row_per_subject_endpoint_visit",
  source_ref = dual_tfl_ids[[i]], review_status = "accepted", reviewer_note = "已确认"
))), dual_endpoint_mapping_path)
dual_metadata$endpoint_mapping_file <- gsub("\\\\", "/", file.path("studies", dual_study_name, "statistician-review", "endpoint-mapping.yaml"))
dual_metadata$endpoint_mapping_sha256 <- toupper(specification_sha256(dual_endpoint_mapping_path))
dual_review_path <- file.path(dual_study_dir, "statistician-review", "statistical-review.md")
dual_spec_path <- file.path(dual_study_dir, "statistician-review", "analysis-specification.md")
dual_metadata$review_file <- gsub("\\\\", "/", file.path("studies", dual_study_name, "statistician-review", "statistical-review.md"))
dual_metadata$review_sha256 <- paste(rep("0", 64L), collapse = "")
dual_metadata$approved_execution_sha256 <- paste(rep("0", 64L), collapse = "")
dual_body <- c(
  "## 1. 文件状态与使用规则", "本文件已批准用于双 TFL 技术验证。",
  "## 2. Study 和数据上下文", paste("Study", dual_study_name, "使用随机合成数据。"),
  "## 3. MMRM Analysis 清单", paste0("Analysis ", dual_analysis_ids, "。"),
  "## 4. Analysis Specifications", paste0("执行 ", dual_analysis_ids, " 并遵循 typed contract。"),
  "## 5. TFL 输出清单", paste0("输出 ", dual_tfl_ids, "。"),
  "## 6. SAS Template 生成要求", "生成只读输入 SAS 模板。",
  "## 7. 运行与诊断报告要求", "记录模型、推断、风险和路径。",
  "## 8. 完整 QC 要求", "检查缺失、基线一致性、唯一性和水平数。",
  "## 9. 溯源附录", "合成测试溯源。",
  "## 10. 校验结果", "批准校验通过。"
)
dual_write_specification <- function(path, values) {
  writeLines(c("---", strsplit(yaml::as.yaml(values), "\n", fixed = TRUE)[[1]], "---", dual_body), path, useBytes = TRUE)
}
dual_write_specification(dual_spec_path, dual_metadata)
dual_execution_sha256 <- analysis_specification_execution_sha256(read_analysis_specification(dual_spec_path))
dual_candidate_lines <- unlist(lapply(dual_tfl_ids, function(id) c(
  paste0("### 表 ", id, "：合成评分 MMRM 汇总"), "",
  paste0("| ", paste(statistical_review_candidate_table_columns(), collapse = " | "), " |"),
  "|---|---|---|---|---|---|",
  vapply(statistical_review_candidate_rule_categories(), function(category) {
    candidate <- if (identical(category, "分析人群")) "RECORD_USE eq \"INCLUDE\"" else "合成候选规则"
    disposition <- if (identical(category, "分析人群")) "action=modified;rule=RECORD_USE eq \"INCLUDE\";population_rule=RECORD_USE eq \"INCLUDE\"" else "action=approved;rule=合成候选规则"
    paste0("| ", category, " | ", candidate, " | 合成测试来源；已识别 | 可表达，待统计师确认 | 确认 | ", disposition, " |")
  }, character(1))
)), use.names = FALSE)
dual_mapping_lines <- vapply(seq_along(dual_analysis_ids), function(i) paste0(
  "| ", dual_analysis_ids[[i]], " | ", dual_tfl_ids[[i]], " | SCOREX-GROUP | 合成评分 | MEASURE_KEY | SCOREX | single_code | not_applicable | one_row_per_subject_endpoint_visit | ", dual_tfl_ids[[i]], " | accepted | 已确认 |"
), character(1))
dual_review_metadata <- list(
  review_schema_version = "1.1", study_id = dual_study_name, generation_route = "statistician_authored",
  review_status = "approved", finalization_status = "ready_for_final_signature", reviewed_by = "Synthetic Statistician",
  reviewed_at_utc = "2026-08-14T12:00:00Z", approved_execution_sha256 = toupper(dual_execution_sha256),
  source_input_file = gsub("\\\\", "/", dual_contract_relative), source_input_sha256 = toupper(dual_contract_hash)
)
writeLines(c("---", strsplit(yaml::as.yaml(dual_review_metadata), "\n", fixed = TRUE)[[1]], "---",
  "## 1. 审阅结论与签核", "已批准双 TFL 合成技术验证。",
  "## 2. Study 与数据范围", "合成随机数据和已固定 contract。",
  "## 3. Analysis 与 TFL 清单", dual_candidate_lines,
  "## 4. Endpoint Mapping 与分组确认",
  "| analysis_id | source_tfl_id | group_id | endpoint_label | endpoint_variable | selected_codes | selection_mode | instrument / version / reporter / subscale | row_allocation_rule | source_ref | review_status | reviewer_note |",
  "|---|---|---|---|---|---|---|---|---|---|---|---|", dual_mapping_lines,
  "## 5. 模型、协方差与估计量确认", "已确认 MMRM、协方差和估计量。",
  "## 6. Adapter / 派生 / 行分配确认", "Adapter 已固定；每个 subject、endpoint 和 visit 最多一行。",
  "## 7. 未解决问题与决议", "| issue_id | scope | question_or_risk | resolution | status |", "|---|---|---|---|---|",
  "## 8. Execution 内容指纹", toupper(dual_execution_sha256)
), dual_review_path, useBytes = TRUE)
dual_metadata$review_sha256 <- toupper(specification_sha256(dual_review_path))
dual_metadata$approved_execution_sha256 <- toupper(dual_execution_sha256)
dual_write_specification(dual_spec_path, dual_metadata)
dual_execution_text <- analysis_specification_execution_text(read_analysis_specification(dual_spec_path))
if (!all(vapply(c(dual_analysis_ids, dual_tfl_ids), grepl, logical(1), x = dual_execution_text, fixed = TRUE))) {
  stop("dual-TFL specification execution text is missing required IDs: ", dual_execution_text)
}
stopifnot(isTRUE(validate_statistical_review(read_statistical_review(dual_review_path), read_analysis_specification(dual_spec_path))$execution_match))
run_script(generator, shQuote(paste0("--study-dir=", dual_study_dir)))
dual_collector <- file.path(dual_study_dir, "analysis", "r", "run_all_mmrm.R")
stopifnot(all(file.exists(file.path(dual_study_dir, "analysis", "r", paste0(dual_analysis_ids, ".R")))))
writeLines(c(adapter_lines, "# deliberately mutated after generation"), dual_adapter_paths[[1]], useBytes = TRUE)
run_script(dual_collector, "--mode=run-and-collect")
dual_manifest <- standard_read_csv_schema(file.path(dual_study_dir, "output", "tfl-output-manifest.csv"), names(standard_output_manifest_schema()), "dual-TFL manifest")
dual_summary_text <- paste(readLines(file.path(dual_study_dir, "output", "mmrm-run-summary.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
stopifnot(nrow(dual_manifest) == 2L, identical(as.character(dual_manifest$tfl_id), dual_tfl_ids))
stopifnot(dual_manifest$output_status[[1]] == "blocked_mapping", nzchar(dual_manifest$raw_output_file[[1]]), nzchar(dual_manifest$final_tfl_file[[1]]))
stopifnot(dual_manifest$output_status[[2]] %in% c("complete", "partial"), nzchar(dual_manifest$raw_output_file[[2]]), nzchar(dual_manifest$final_tfl_file[[2]]))
stopifnot(grepl("Overall status：`partial`", dual_summary_text, fixed = TRUE))
dual_paths <- study_paths(dual_collector)
dual_blocked_record <- standard_read_csv_schema(analysis_output_paths(dual_paths, dual_analysis_ids[[1]])$run_record, standard_required_run_record_columns(), "dual blocked run record")
dual_blocked_diagnostics <- standard_read_csv_schema(analysis_output_paths(dual_paths, dual_analysis_ids[[1]])$diagnostic_csv, standard_required_diagnostic_columns(), "dual blocked diagnostics")
dual_continued_record <- standard_read_csv_schema(analysis_output_paths(dual_paths, dual_analysis_ids[[2]])$run_record, standard_required_run_record_columns(), "dual continued run record")
stopifnot(dual_blocked_record$output_status[[1]] == "blocked_mapping", dual_blocked_diagnostics$failure_domain[[1]] == "adapter", dual_blocked_diagnostics$failure_phase[[1]] == "approved_adapter_gate")
stopifnot(identical(dual_blocked_record$invocation_id[[1]], dual_continued_record$invocation_id[[1]]))
dual_blocked_diagnostic_hold <- paste0(analysis_output_paths(dual_paths, dual_analysis_ids[[1]])$diagnostic_csv, ".case-summary-hold")
stopifnot(file.rename(analysis_output_paths(dual_paths, dual_analysis_ids[[1]])$diagnostic_csv, dual_blocked_diagnostic_hold))
dual_case_summary <- standard_case_summary(dual_paths, read_standard_mmrm_contract(dual_contract_path))
stopifnot(file.rename(dual_blocked_diagnostic_hold, analysis_output_paths(dual_paths, dual_analysis_ids[[1]])$diagnostic_csv))
validate_standard_case_summary(dual_case_summary)
stopifnot(
  identical(vapply(dual_case_summary$analysis_catalog, `[[`, character(1), "tfl_id"), dual_tfl_ids),
  identical(vapply(dual_case_summary$run_records, `[[`, character(1), "output_status"), as.character(dual_manifest$output_status))
)
writeLines(adapter_lines, dual_adapter_paths[[1]], useBytes = TRUE)

# All-terminal collector failure must still write the ten-column manifest and then exit nonzero.
wrapper_hold <- paste0(wrapper, ".collector-failure-hold")
stopifnot(file.rename(wrapper, wrapper_hold))
failed_collection <- run_script(collector, "--mode=run-and-collect", allow_nonzero = TRUE)
stopifnot(failed_collection$status != 0L, file.exists(manifest_path), file.exists(file.path(study_dir, "output", "mmrm-run-summary.md")))
failed_manifest <- standard_read_csv_schema(manifest_path, names(standard_output_manifest_schema()), "failed collector manifest")
stopifnot(nrow(failed_manifest) == 1L, failed_manifest$output_status[[1]] == "blocked_mapping")
stopifnot(file.rename(wrapper_hold, wrapper))
run_script(collector, c("--mode=run-and-collect", "--fail-fast=false"))
cli_summary_text <- paste(readLines(file.path(study_dir, "output", "mmrm-run-summary.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
stopifnot(grepl("有效 fail_fast：`false`", cli_summary_text, fixed = TRUE))
cat("RDS, artifact tamper, adapter digest, case-summary, and collector failure assertions passed.\n"); flush.console(); checkpoint("rds_assertion_passed")

text_files <- c(list.files(file.path(study_dir, "analysis"), recursive = TRUE, full.names = TRUE, pattern = "[.](R|sas)$"),
                list.files(file.path(study_dir, "output"), recursive = TRUE, full.names = TRUE, pattern = "[.](csv|md|log)$"))
all_text <- paste(unlist(lapply(text_files, readLines, warn = FALSE, encoding = "UTF-8")), collapse = "\n")
forbidden <- c("FCN", "PedsQL", "REGION", "COUNTRY", "COAFL", "ANL01FL")
stopifnot(!any(vapply(forbidden, grepl, logical(1), x = all_text, fixed = TRUE)))
unlink(study_dir, recursive = TRUE, force = TRUE)
stopifnot(!dir.exists(study_dir))
cat("Standard MMRM Profile v1 synthetic integration test passed.\n")
}

main()
