options(encoding = "UTF-8")
options(warn = 2L)

# 逐 TFL 自包含 SAS renderer 的定向检查（implementation plan 7.7）。
# 本机没有 SAS runtime：本脚本只做确定性渲染、静态 conformance 与 golden 校验，
# 不执行 SAS，不证明 SHA-256、fallback 与 UTF-8 BOM export 在真实 SAS 会话中成功。

find_scs_root <- function(path) {
  current <- normalizePath(path, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "self_contained_sas.R"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) stop("project root not found")
    current <- parent
  }
}

scs_check_source <- function() {
  project_dir <- find_scs_root(getwd())
  helper_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
  for (helper in c("canonical_hash.R", "standard_contract.R", "standard_analysis_definition.R", "standard_sas.R",
                   "program_generation_ir.R", "program_conformance.R", "self_contained_sas.R")) {
    source(file.path(helper_dir, helper), encoding = "UTF-8", local = globalenv())
  }
  project_dir
}

scs_log <- function(...) {
  cat(paste0(c(...), collapse = ""))
  flush(stdout())
  invisible(NULL)
}

scs_hash <- function(letter) paste(rep(letter, 64L), collapse = "")

scs_expect_error <- function(expression, prefix) {
  error <- try(force(expression), silent = TRUE)
  stopifnot(inherits(error, "try-error"), grepl(prefix, as.character(error), fixed = TRUE))
  invisible(error)
}

scs_special_text <- function(value) paste0(value, " \"quoted\" 'apostrophe' \\backslash ;#% 中文")
# machine marker 是以空白分隔的 token，因此出现在 marker 中的取值只能使用不含空白的特殊字符。
scs_special_token <- function(value) paste0(value, "\"quoted\"'apostrophe'\\backslash;#%中文")

# ---------------------------------------------------------------------------
# test-only：把目标环境能力声明临时改为缺少 FCMP/位运算/SHA-256，用于断言"能力不足时
# linked 生成必须阻断，且不降级为只检查文件名或大小"。本脚本不修改任何既有文件。
# 注意：生成流水线从不执行 SAS，因此不存在"生成前必须先在 SAS 上跑通"的闸门；
# 唯一闸门是下面这个能力声明。
# ---------------------------------------------------------------------------
scs_capability_override <- local({
  original <- NULL
  function(action) {
    if (identical(action, "begin")) {
      if (is.null(original)) original <<- get("sas_execution_profile_registry", envir = globalenv())
      captured <- original
      assign("sas_execution_profile_registry", function() {
        registry <- captured()
        for (name in names(registry)) { registry[[name]]$fcmp <- FALSE; registry[[name]]$bit_operations <- FALSE; registry[[name]]$sha256 <- FALSE }
        registry
      }, envir = globalenv())
    } else {
      assign("sas_execution_profile_registry", original, envir = globalenv())
    }
    invisible(NULL)
  }
})

scs_group <- function(id, label, codes, reporter_dimension, special = FALSE) {
  operator <- if (length(codes) == 1L) "eq" else "in"
  value <- if (length(codes) == 1L) codes[[1L]] else codes
  predicates <- list(list(variable = "PARAMCD", operator = operator, value = value))
  if (!is.null(reporter_dimension)) predicates <- c(predicates, list(list(variable = "REPORTER_GROUP", operator = "in", value = c("Caregiver", "Subject"))))
  list(id = id, label = if (special) scs_special_text(label) else label, predicates = predicates)
}

scs_endpoint <- function(id, codes, reporter_dimension, subscale) {
  list(
    group_id = id,
    endpoint_variable = "PARAMCD",
    selected_codes = codes,
    selection_mode = if (length(codes) == 1L) "single_code" else "mutually_exclusive_versions",
    dimensions = list(
      instrument = list(variable = "fixed", values = "Scale X"),
      version = list(variable = "PARAMCD", values = codes),
      reporter = if (is.null(reporter_dimension)) list(variable = "not_applicable", values = character(0)) else list(variable = "REPORTER_GROUP", values = c("Caregiver", "Subject")),
      subscale = list(variable = "fixed", values = subscale)
    ),
    row_allocation_rule = "one_row_per_subject_endpoint_visit"
  )
}

scs_fixture <- function(binding_mode = "linked", analysis_id = "MMRM-01", tfl_id = "T14-01",
                        treatment = TRUE, pairwise = TRUE, group_count = 2L,
                        derivations = TRUE, filters = TRUE,
                        covariance = list(primary = "TOEP", fallback = as.list(c("CS", "AR1"))),
                        special = FALSE, adapter = FALSE, format = "csv",
                        df_method = "Satterthwaite") {
  linked <- identical(binding_mode, "linked")
  file_name <- paste0("scores.", format)
  mappings <- list(subject = "PERSON_ID", response = "DELTA_SCORE", baseline = "START_SCORE", visit = "TIME_INDEX", visit_label = "TIME_LABEL")
  if (treatment) mappings$treatment <- "RANDOM_ARM"
  derivation_list <- if (derivations) list(list(
    id = "REPORTER_RECODE", operation = "recode", source_variable = "REPORTER", target_variable = "REPORTER_GROUP",
    levels = list(
      list(target_value = "Caregiver", source_values = c("Mother", "Father", "Guardian")),
      list(target_value = "Subject", source_values = "Self")
    ),
    unmatched = "error", missing = "preserve",
    source_ref = list(review_rule = paste0(tfl_id, "/endpoint_dimension"), reviewer_decision = "DEC-02")
  )) else list()
  filter_value <- if (special) scs_special_text("Y") else "Y"
  filter_list <- if (filters) list(list(variable = "ANALYSIS_FLAG", operator = "eq", value = filter_value)) else list()
  reporter_dimension <- if (derivations) TRUE else NULL
  groups <- list(scs_group("TOTAL", "Total score", c("SCORE_A", "SCORE_B"), reporter_dimension, special))
  endpoints <- list(scs_endpoint("TOTAL", c("SCORE_A", "SCORE_B"), reporter_dimension, "total"))
  if (2L <= group_count) {
    groups <- c(groups, list(scs_group("SUBSCALE", "Subscale score", "SCORE_C", NULL, special)))
    endpoints <- c(endpoints, list(scs_endpoint("SUBSCALE", "SCORE_C", NULL, "sub1")))
  }
  fixed_effects <- c("baseline", "visit", "baseline_by_visit")
  if (treatment) fixed_effects <- c(fixed_effects, "treatment", "treatment_by_visit")
  analysis <- list(
    analysis_id = analysis_id, tfl_id = tfl_id,
    title = if (special) scs_special_text("Synthetic self-contained analysis") else "Synthetic self-contained analysis",
    dataset = list(binding_mode = binding_mode, file = file_name, format = format,
                   relative_path = if (linked) paste0("studies/synthetic/input/adam/", file_name) else NULL,
                   sha256 = if (linked) scs_hash("A") else NULL),
    mappings = mappings, derivations = derivation_list, filters = filter_list,
    groups = groups, endpoint_definitions = endpoints,
    fixed_effects = as.list(fixed_effects), reml = TRUE, covariance = covariance,
    df_method = df_method,
    estimands = list(visit_lsmeans = TRUE, treatment_visit_lsmeans = treatment, pairwise_differences = treatment && pairwise),
    output = standard_contract_expected_output(tfl_id)
  )
  if (treatment) {
    levels <- if (special) c(scs_special_token("Placebo"), scs_special_token("Active")) else c("Placebo", "Active")
    analysis$treatment <- list(variable = "RANDOM_ARM", levels = levels, reference = levels[[1L]], comparator = levels[[2L]],
                               contrast_direction = "comparator_minus_reference", confidence_level = 0.95, multiplicity_adjustment = "none")
  }
  if (adapter) {
    analysis$adapter_file <- "studies/synthetic/analysis/r/adapter.R"
    analysis$adapter_sha256 <- scs_hash("9")
  }
  approval <- list(
    review_file = "studies/synthetic/statistician-review/statistical-review.md", review_sha256 = scs_hash("C"),
    analysis_plan_file = "studies/synthetic/statistician-review/analysis-plan.yaml", analysis_plan_sha256 = scs_hash("B"),
    approval_payload_sha256 = scs_hash("D"), source_evidence_sha256 = scs_hash("E"),
    reviewed_by = "Synthetic Statistician", approved_at_utc = "2026-08-21T00:00:00Z"
  )
  contract <- list(
    contract_schema_version = "2.1", profile_version = standard_mmrm_profile_version(),
    study = list(study_id = "SYNTHETIC"),
    execution = list(
      data_availability = if (linked) "available" else "none",
      data_classification = if (linked) "dummy" else "none",
      intended_use = if (linked) "technical_validation" else "code_generation",
      sas_execution_profile = "sas-9.4m5-self-contained/v1", fail_fast = FALSE
    ),
    approval = approval, analyses = list(analysis)
  )
  validate_standard_mmrm_contract(contract)
  contract
}

scs_identities <- function(contract) list(
  plan_sha256 = contract$approval$analysis_plan_sha256,
  approval_payload_sha256 = contract$approval$approval_payload_sha256,
  contract_sha256 = scs_hash("F")
)

scs_render <- function(contract) {
  analysis <- contract$analyses[[1L]]
  render_self_contained_sas_program(contract, analysis, scs_identities(contract))
}

scs_position <- function(program, needle) regexpr(needle, program, fixed = TRUE)[[1L]]

scs_config_region <- function(lines) {
  begin <- grep("用户配置区（开始）", lines, fixed = TRUE)
  end <- grep("用户配置区（结束）", lines, fixed = TRUE)
  stopifnot(length(begin) == 1L, length(end) == 1L, begin < end)
  lines[(begin + 1L):(end - 1L)]
}

scs_assert_program <- function(contract, label) {
  analysis <- contract$analyses[[1L]]
  identities <- scs_identities(contract)
  ir <- build_program_generation_ir(contract, analysis, identities)
  program <- render_self_contained_sas_program(contract, analysis, identities)
  again <- render_self_contained_sas_program(contract, analysis, identities)
  linked <- identical(ir$dataset$binding_mode, "linked")
  lines <- strsplit(program, "\n", fixed = TRUE)[[1L]]

  # 确定性渲染 + UTF-8 + 无外部依赖/未替换 placeholder。
  stopifnot(
    is.character(program), length(program) == 1L, !is.na(program), nzchar(program),
    identical(program, again),
    !is.na(iconv(program, from = "UTF-8", to = "UTF-8")),
    !grepl(">", program, fixed = TRUE),
    !grepl("%include", program, ignore.case = TRUE),
    !grepl("[.]codex", program),
    !grepl("TODO", program, ignore.case = TRUE),
    !grepl("TBD", program, ignore.case = TRUE),
    !grepl("<[A-Za-z0-9_.:/|-]{1,60}>", program, perl = TRUE),
    !grepl("%sysexec", program, ignore.case = TRUE),
    !grepl("call[[:space:]]+system", program, ignore.case = TRUE),
    !grepl("call[[:space:]]+execute", program, ignore.case = TRUE),
    !grepl("filename[^;]+pipe", program, ignore.case = TRUE),
    !grepl("xcmd", program, ignore.case = TRUE),
    !grepl("powershell", program, ignore.case = TRUE),
    !grepl("python", program, ignore.case = TRUE),
    !grepl("systask", program, ignore.case = TRUE),
    !grepl("rsubmit", program, ignore.case = TRUE),
    !grepl("run_standard_mmrm_analysis", program, fixed = TRUE)
  )

  # 静态 conformance（八章/顺序/边界/marker/why/gate/ODS/fallback/收敛/导出）。
  validate_generated_sas_program(program, ir)

  # 八章各出现一次且顺序正确。
  header_positions <- vapply(seq_along(program_section_titles()), function(i) {
    header <- render_sas_section_header(i, program_section_titles()[[i]])
    stopifnot(program_count_fixed(program, header) == 1L)
    scs_position(program, header)
  }, numeric(1))
  stopifnot(!is.unsorted(header_positions, strictly = TRUE))

  # 第 4 部分结尾恰为批准 boundary 注释的 SAS 注释包装。
  boundary <- "/* 至此完成数据处理。以下代码开始进行 MMRM 模型拟合；请勿混淆两部分职责。 */"
  stopifnot(sum(lines == boundary) == 1L)
  section4 <- substr(program, header_positions[[4L]], header_positions[[5L]] - 1L)
  stopifnot(endsWith(trimws(section4), boundary))

  # 每个期望 marker 恰好一次；统计类 marker 行集合与期望完全一致（由 validate 断言）。
  for (marker in program_expected_markers(ir)) stopifnot(program_count_marker(program, marker) == 1L)
  for (prefix in program_expected_why_prefixes(ir)) stopifnot(1L == length(grep(prefix, lines, fixed = TRUE)))

  # 第 1 部分唯一用户配置区恰为三个 %let。
  region <- scs_config_region(lines)
  region_statements <- trimws(region[grepl("^%let", trimws(region))])
  stopifnot(identical(region_statements, c("%let EXECUTE_APPROVED_PROGRAM=NO;", "%let INPUT_DIR=;", "%let OUTPUT_DIR=;")))
  for (name in c("EXECUTE_APPROVED_PROGRAM", "INPUT_DIR", "OUTPUT_DIR")) {
    stopifnot(1L == length(grep(paste0("^%let ", name, "="), trimws(lines))))
  }
  # CODE_GENERATION_ONLY 是生成常量，不在用户配置区。
  stopifnot(
    !any(grepl("CODE_GENERATION_ONLY", region, fixed = TRUE)),
    1L == length(grep("^%let CODE_GENERATION_ONLY=", trimws(lines))),
    grepl(paste0("%let CODE_GENERATION_ONLY=", if (linked) "NO" else "YES", ";"), program, fixed = TRUE),
    grepl(paste0("%let DATA_AVAILABLE=", if (linked) "YES" else "NO", ";"), program, fixed = TRUE)
  )

  # 第 2 部分顺序：在 check_environment 宏体内，CODE_GENERATION_ONLY gate 必须在任何中止语句与其余检查之前。
  environment_begin <- grep("^%macro check_environment;$", trimws(lines))
  stopifnot(length(environment_begin) == 1L)
  environment_end <- environment_begin - 1L + which(trimws(lines[environment_begin:length(lines)]) == "%mend;")[[1L]]
  environment_block <- lines[environment_begin:environment_end]
  gate_line <- grep("%if %upcase(&CODE_GENERATION_ONLY) = YES %then %do;", environment_block, fixed = TRUE)
  return_line <- grep("^%return;$", trimws(environment_block))
  abort_in_block <- grep("%abort cancel;", environment_block, fixed = TRUE)
  execute_line <- grep("EXECUTE_APPROVED_PROGRAM) ne YES", environment_block, fixed = TRUE)
  input_line <- grep("%if %length(%superq(INPUT_DIR)) = 0 %then %do;", environment_block, fixed = TRUE)
  fileexist_line <- grep("%if %sysfunc(fileexist(&INPUT_PATH)) = 0 %then %do;", environment_block, fixed = TRUE)
  stopifnot(
    length(gate_line) == 1L,
    0L < length(return_line),
    gate_line < min(return_line),
    length(input_line) == 1L, length(fileexist_line) == 1L,
    gate_line < input_line, input_line < fileexist_line,
    grepl("%let RUN_STATUS=code_generation_only;", program, fixed = TRUE)
  )
  if (linked) {
    sha_call_line <- grep("%verify_file_sha256(path=&INPUT_PATH", environment_block, fixed = TRUE)
    stopifnot(length(execute_line) == 1L, gate_line < execute_line, execute_line < input_line,
              length(sha_call_line) == 1L, fileexist_line < sha_call_line,
              0L < length(abort_in_block), gate_line < min(abort_in_block))
  } else {
    stopifnot(length(execute_line) == 0L)
  }

  # QC hard gate 必须在 PROC MIXED 之前。
  qc_position <- scs_position(program, "%if &QC_ERROR_TOTAL gt 0 %then %do;")
  mixed_position <- scs_position(program, "proc mixed data=_standard_mmrm")
  stopifnot(0L < qc_position, 0L < mixed_position, qc_position < mixed_position)

  # ODS 捕获、fallback 控制流、收敛 gate、CSV writer。
  stopifnot(
    grepl("ods output ConvergenceStatus=work._ods_convergence", program, fixed = TRUE),
    grepl("LSMeans=work._ods_lsmeans", program, fixed = TRUE),
    grepl("SolutionF=work._ods_solutionf", program, fixed = TRUE),
    grepl("%macro run_mmrm_with_fallback;", program, fixed = TRUE),
    grepl("%run_mmrm_with_fallback;", program, fixed = TRUE),
    grepl("delete _ods_convergence _ods_lsmeans _ods_diffs _ods_solutionf;", program, fixed = TRUE),
    grepl("%if %length(&selected) = 0 and &group_ok = 1 %then %do;", program, fixed = TRUE),
    grepl("%let selected=&cov;", program, fixed = TRUE),
    grepl("call symputx('ATT_STATUS', Status, 'G');", program, fixed = TRUE),
    grepl("%let ATT_REASON=convergence_status_nonzero;", program, fixed = TRUE),
    grepl("rule_action='allow'", program, fixed = TRUE),
    grepl("rule_action='block'", program, fixed = TRUE),
    grepl("%let MMRM_FIT_SUCCESS=1;", program, fixed = TRUE),
    grepl("%let MMRM_FIT_SUCCESS=0;", program, fixed = TRUE),
    grepl("%let RUN_STATUS=fit_failed;", program, fixed = TRUE),
    grepl("%if &MMRM_FIT_SUCCESS ne 1 or &INFERENCE_COMPLETE ne 1 %then %do;", program, fixed = TRUE),
    grepl("%macro write_csv_utf8_bom(data=, path=, columns=);", program, fixed = TRUE),
    grepl("put 'EFBBBF'x;", program, fixed = TRUE),
    grepl("put '0D0A'x;", program, fixed = TRUE),
    grepl("tranwrd(_csv_field, '\"', '\"\"')", program, fixed = TRUE),
    grepl("%write_csv_utf8_bom(data=_final_table, path=&OUTPUT_DIR/&SAS_FINAL_FILE, columns=", program, fixed = TRUE),
    grepl("%write_csv_utf8_bom(data=_raw_export, path=&OUTPUT_DIR/&SAS_RAW_FILE, columns=", program, fixed = TRUE),
    grepl("%write_csv_utf8_bom(data=_diagnostic_table, path=&OUTPUT_DIR/&SAS_DIAGNOSTIC_FILE, columns=", program, fixed = TRUE),
    grepl("%write_csv_utf8_bom(data=_run_record_table, path=&OUTPUT_DIR/&SAS_RUN_RECORD_FILE, columns=", program, fixed = TRUE)
  )

  # 批准的 covariance 顺序（primary 在前）与 marker 顺序一致。
  stopifnot(
    grepl(paste0("%let COVARIANCE_KEYS=", paste(ir$covariance_order, collapse = " "), ";"), program, fixed = TRUE),
    grepl(paste0("%let COVARIANCE_TYPES=", paste(vapply(ir$covariance_order, scs_covariance_type, character(1)), collapse = " "), ";"), program, fixed = TRUE),
    grepl(paste0("%let COVARIANCE_COUNT=", length(ir$covariance_order), ";"), program, fixed = TRUE)
  )
  covariance_positions <- vapply(ir$covariance_order, function(value) scs_position(program, program_marker("COVARIANCE", value)), numeric(1))
  stopifnot(!is.unsorted(covariance_positions, strictly = TRUE))

  # linked / planned 分支。
  if (linked) {
    stopifnot(
      grepl("access=readonly", program, fixed = TRUE),
      grepl("%macro verify_file_sha256(path=, expected=);", program, fixed = TRUE),
      grepl("%verify_file_sha256(path=&INPUT_PATH, expected=&EXPECTED_INPUT_SHA256)", program, fixed = TRUE),
      grepl("proc fcmp outlib=work.scfuncs.sha256;", program, fixed = TRUE),
      grepl("infile _shafile recfm=n lrecl=64 encoding='any';", program, fixed = TRUE),
      grepl("input _chunk $char64.;", program, fixed = TRUE),
      grepl("_expected = upcase(", program, fixed = TRUE),
      grepl("%if %upcase(&ACTUAL_INPUT_SHA256) ne %upcase(&expected) %then %do;", program, fixed = TRUE),
      grepl(program_marker("GATE", "LINKED_FILE"), program, fixed = TRUE),
      grepl(program_marker("GATE", "LINKED_SHA256"), program, fixed = TRUE),
      grepl("%if %upcase(&EXECUTE_APPROVED_PROGRAM) ne YES %then %do;", program, fixed = TRUE),
      grepl(paste0("%let EXPECTED_INPUT_SHA256=", toupper(ir$dataset$sha256), ";"), program, fixed = TRUE)
    )
    sha_position <- scs_position(program, program_marker("GATE", "LINKED_SHA256"))
    verify_position <- scs_position(program, "%verify_file_sha256(path=&INPUT_PATH")
    read_position <- if (identical(ir$dataset$format, "csv")) scs_position(program, "proc import out=_source replace") else scs_position(program, "set _adamin.")
    stopifnot(0L < sha_position, 0L < verify_position, 0L < read_position, verify_position < read_position)
  } else {
    stopifnot(
      grepl(program_marker("GATE", "PLANNED_CODE_GENERATION_ONLY"), program, fixed = TRUE),
      !grepl(program_marker("GATE", "LINKED_SHA256"), program, fixed = TRUE),
      !grepl("verify_file_sha256", program, fixed = TRUE),
      !grepl("proc fcmp", program, fixed = TRUE),
      !grepl("EXECUTE_APPROVED_PROGRAM) ne YES", program, fixed = TRUE),
      grepl("%let EXPECTED_INPUT_SHA256=;", program, fixed = TRUE)
    )
  }

  scs_log("fixture 通过静态检查：", label, "（", length(lines), " 行）\n")
  list(ir = ir, program = program, lines = lines)
}

scs_golden_dir <- function(project_dir) file.path(project_dir, ".codex", "study-mmrm-analysis", "assets", "golden", "self-contained-sas")

scs_read_golden <- function(path) {
  raw <- readBin(path, what = "raw", n = file.size(path))
  iconv(rawToChar(raw), from = "UTF-8", to = "UTF-8")
}

scs_assert_golden <- function(project_dir, name, program) {
  path <- file.path(scs_golden_dir(project_dir), name)
  if (!file.exists(path)) {
    stop("GOLDEN-MISSING: 缺少 golden 文件 ", path,
         "。请在人工复核渲染结果后显式生成该 golden 文件；本检查不会自动写入 golden，也不会在缺失时声称通过。")
  }
  golden <- scs_read_golden(path)
  if (!identical(golden, program)) {
    golden_lines <- strsplit(golden, "\n", fixed = TRUE)[[1L]]
    program_lines <- strsplit(program, "\n", fixed = TRUE)[[1L]]
    limit <- min(length(golden_lines), length(program_lines))
    first <- which(golden_lines[seq_len(limit)] != program_lines[seq_len(limit)])
    detail <- if (length(first)) paste0("首个不同行=", first[[1L]], "；golden=", golden_lines[[first[[1L]]]], "；actual=", program_lines[[first[[1L]]]]) else paste0("行数不同：golden=", length(golden_lines), "，actual=", length(program_lines))
    stop("GOLDEN-MISMATCH: ", name, " 与渲染结果不是逐字相同。", detail)
  }
  scs_log("golden 逐字匹配：", name, "\n")
  invisible(TRUE)
}

scs_fixture_catalog <- function() list(
  list(name = "linked-randomized-csv.sas", label = "linked randomized csv（derivation + filter + 2 组 + primary/fallback）", contract = function() scs_fixture()),
  list(name = "linked-randomized-sas7bdat.sas", label = "linked randomized sas7bdat 读取分支", contract = function() scs_fixture(analysis_id = "MMRM-04", tfl_id = "T14-04", format = "sas7bdat")),
  list(name = "linked-single-arm.sas", label = "linked 单臂（无 treatment/无 pairwise）", contract = function() scs_fixture(analysis_id = "MMRM-02", tfl_id = "T14-02", treatment = FALSE)),
  list(name = "linked-pairwise-off.sas", label = "linked pairwise differences 关闭", contract = function() scs_fixture(analysis_id = "MMRM-06", tfl_id = "T14-06", pairwise = FALSE)),
  list(name = "linked-multi-fallback-kr.sas", label = "linked primary + 3 个 fallback、Kenward-Roger", contract = function() scs_fixture(analysis_id = "MMRM-05", tfl_id = "T14-05", covariance = list(primary = "UN", fallback = as.list(c("TOEP", "CS", "AR1"))), df_method = "Kenward-Roger")),
  list(name = "linked-minimal.sas", label = "linked 无 derivation / 无 filter / 单组", contract = function() scs_fixture(analysis_id = "MMRM-07", tfl_id = "T14-07", group_count = 1L, derivations = FALSE, filters = FALSE)),
  list(name = "linked-special-literals.sas", label = "linked 恶意与特殊字符 literal 转义", contract = function() scs_fixture(analysis_id = "MMRM-08", tfl_id = "T14-08", special = TRUE)),
  list(name = "planned-code-generation-only.sas", label = "planned code-generation-only", contract = function() scs_fixture(binding_mode = "planned", analysis_id = "MMRM-03", tfl_id = "T14-03"))
)

scs_generate_golden <- function(project_dir) {
  directory <- scs_golden_dir(project_dir)
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  for (entry in scs_fixture_catalog()) {
    program <- scs_render(entry$contract())
    connection <- file(file.path(directory, entry$name), open = "wb")
    writeBin(charToRaw(enc2utf8(program)), connection)
    close(connection)
    scs_log("已写出 golden：", entry$name, "\n")
  }
  invisible(TRUE)
}

check_self_contained_sas_generation_main <- function() {
  project_dir <- scs_check_source()

  # ---------------------------------------------------------------------
  # 生产路径断言：SAS 一律只作为代码交付，生成流水线从不执行 SAS，
  # 因此 linked 与 planned 都必须能在生产路径正常渲染，不存在 execution qualification 闸门。
  # ---------------------------------------------------------------------
  linked_production <- scs_render(scs_fixture())
  planned_program_production <- scs_render(scs_fixture(binding_mode = "planned", analysis_id = "MMRM-03", tfl_id = "T14-03"))
  stopifnot(is.character(linked_production), nzchar(linked_production), is.character(planned_program_production), nzchar(planned_program_production))
  scs_log("生产路径断言：linked 与 planned SAS 均正常渲染；SAS 只交付代码，不由生成流水线执行。\n")

  # 唯一生成闸门：目标环境缺少 FCMP/位运算/SHA-256 能力时，linked 必须阻断且不降级。
  scs_capability_override("begin")
  scs_expect_error(scs_render(scs_fixture()), "PROGRAM-SAS-CONFORMANCE-SHA256-UNSUPPORTED:MMRM-01")
  planned_without_capability <- scs_render(scs_fixture(binding_mode = "planned", analysis_id = "MMRM-03", tfl_id = "T14-03"))
  stopifnot(is.character(planned_without_capability), nzchar(planned_without_capability))
  scs_capability_override("end")
  stopifnot(isTRUE(sas_execution_profile_registry()[["sas-9.4m5-self-contained/v1"]]$sha256))
  scs_log("生产路径断言：目标环境缺少 FCMP/位运算/SHA-256 能力时 linked 生成阻断，planned 不受影响。\n")

  rendered <- list()
  for (entry in scs_fixture_catalog()) {
    result <- scs_assert_program(entry$contract(), entry$label)
    scs_assert_golden(project_dir, entry$name, result$program)
    rendered[[entry$name]] <- result
  }

  # 生产路径渲染结果必须与 golden 逐字相同（linked 与 planned 都不存在 test-only 差异）。
  scs_assert_golden(project_dir, "planned-code-generation-only.sas", planned_program_production)
  scs_assert_golden(project_dir, "linked-randomized-csv.sas", linked_production)

  randomized <- rendered[["linked-randomized-csv.sas"]]
  sas_format <- rendered[["linked-randomized-sas7bdat.sas"]]
  single_arm <- rendered[["linked-single-arm.sas"]]
  pairwise_off <- rendered[["linked-pairwise-off.sas"]]
  multi_fallback <- rendered[["linked-multi-fallback-kr.sas"]]
  minimal <- rendered[["linked-minimal.sas"]]
  special <- rendered[["linked-special-literals.sas"]]
  planned <- rendered[["planned-code-generation-only.sas"]]

  # 读取分支互斥。
  stopifnot(
    grepl("proc import out=_source replace", randomized$program, fixed = TRUE),
    !grepl("set _adamin.", randomized$program, fixed = TRUE),
    grepl("set _adamin.SCORES;", sas_format$program, fixed = TRUE),
    !grepl("proc import", sas_format$program, fixed = TRUE)
  )

  # 单臂：无 treatment marker、无 diff、无 treatment CLASS。
  stopifnot(
    !grepl("PROGRAM-MARKER:TREATMENT_REFERENCE", single_arm$program, fixed = TRUE),
    !grepl("PROGRAM-MARKER:ESTIMAND:pairwise_differences", single_arm$program, fixed = TRUE),
    !grepl("lsmeans _treatment*_visit", single_arm$program, fixed = TRUE),
    !grepl("Diffs=work._ods_diffs", single_arm$program, fixed = TRUE),
    grepl("class _subject _visit;", single_arm$program, fixed = TRUE),
    grepl("_treatment = 'ALL';", single_arm$program, fixed = TRUE)
  )

  # pairwise 关闭：有 treatment*visit LS mean，但没有 DIFF 与 Diffs 捕获。
  stopifnot(
    grepl("PROGRAM-MARKER:ESTIMAND:treatment_visit_lsmeans", pairwise_off$program, fixed = TRUE),
    !grepl("PROGRAM-MARKER:ESTIMAND:pairwise_differences", pairwise_off$program, fixed = TRUE),
    grepl("lsmeans _treatment*_visit / cl alpha=0.05;", pairwise_off$program, fixed = TRUE),
    !grepl("Diffs=work._ods_diffs", pairwise_off$program, fixed = TRUE)
  )

  # randomized：DIFF + 批准方向筛选 + ADJUST。
  stopifnot(
    grepl("lsmeans _treatment*_visit / cl alpha=0.05 diff adjust=t;", randomized$program, fixed = TRUE),
    grepl("Diffs=work._ods_diffs", randomized$program, fixed = TRUE),
    grepl("and _treatment = 'Active'", randomized$program, fixed = TRUE),
    grepl("and __treatment = 'Placebo'", randomized$program, fixed = TRUE),
    grepl("class _subject _visit _treatment(ref='Placebo');", randomized$program, fixed = TRUE),
    grepl("ddfm=satterth", randomized$program, fixed = TRUE)
  )

  # Kenward-Roger 与 4 个 covariance。
  stopifnot(
    grepl("ddfm=kr", multi_fallback$program, fixed = TRUE),
    grepl("%let COVARIANCE_TYPES=UN TOEP CS AR(1);", multi_fallback$program, fixed = TRUE),
    all(vapply(c("UN", "TOEP", "CS", "AR1"), function(value) program_count_marker(multi_fallback$program, program_marker("COVARIANCE", value)) == 1L, logical(1)))
  )

  # 最小 fixture：无 derivation/filter marker，仍有分组。
  stopifnot(
    !grepl("PROGRAM-MARKER:DERIVATION:", minimal$program, fixed = TRUE),
    !grepl("PROGRAM-MARKER:FILTER:", minimal$program, fixed = TRUE),
    program_count_marker(minimal$program, program_marker("GROUP", "TOTAL")) == 1L,
    grepl("%let GROUP_COUNT=1;", minimal$program, fixed = TRUE)
  )

  # 特殊字符 literal 必须按 SAS 规则转义（单引号成对翻倍），且不产生未闭合注释。
  special_value <- scs_special_text("Y")
  special_literal <- standard_sas_quote(special_value)
  stopifnot(
    grepl(special_literal, special$program, fixed = TRUE),
    grepl("''apostrophe''", special$program, fixed = TRUE),
    grepl(standard_sas_quote(scs_special_token("Placebo")), special$program, fixed = TRUE),
    !grepl("*/*/", special$program, fixed = TRUE)
  )
  # marker 中的特殊 token 不含空白，因此 marker 仍是单个 token。
  stopifnot(program_count_marker(special$program, program_marker("TREATMENT_REFERENCE", scs_special_token("Placebo"))) == 1L)

  # planned：正常结束路径在任何中止语句之前，且不含 SHA/FCMP 代码。
  planned_gate <- grep("%let RUN_STATUS=code_generation_only;", planned$lines, fixed = TRUE)
  planned_return <- grep("^%return;$", trimws(planned$lines))
  planned_abort <- grep("%abort cancel;", planned$lines, fixed = TRUE)
  stopifnot(
    0L < length(planned_gate), 0L < length(planned_return), 0L < length(planned_abort),
    min(planned_gate) < min(planned_abort),
    min(planned_return) < min(planned_abort),
    grepl("%put NOTE: 当前程序按无 ADaM 数据的 code-generation 模式生成。;", planned$program, fixed = TRUE),
    grepl("%if &PROGRAM_ACTIVE ne 1 %then %do;", planned$program, fixed = TRUE)
  )

  # unsupported adapter 必须在渲染前阻断。
  adapter_contract <- scs_fixture(analysis_id = "MMRM-09", tfl_id = "T14-09", adapter = TRUE)
  scs_expect_error(scs_render(adapter_contract), "PROGRAM-INLINE-ADAPTER-UNSUPPORTED:MMRM-09")
  scs_log("fixture 通过静态检查：unsupported adapter 在渲染前阻断\n")

  # 渲染确定性：同一 contract 连续渲染逐字相同（已在 scs_assert_program 内断言），
  # 这里再断言不同 analysis 之间不会互相污染文件名与 identity。
  stopifnot(
    grepl("%let SAS_FINAL_FILE=T14-01_sas_final.csv;", randomized$program, fixed = TRUE),
    !grepl("T14-02", randomized$program, fixed = TRUE),
    grepl("%let SAS_FINAL_FILE=T14-02_sas_final.csv;", single_arm$program, fixed = TRUE)
  )

  scs_log("Self-contained SAS generation focused check passed.\n")
  scs_log("*** 说明：SAS 只作为代码交付，生成流水线从不执行 SAS。本检查完成确定性渲染、conformance 与 golden 校验；",
          "内联 SHA-256、QC hard abort、covariance fallback、推断完整性与 UTF-8 BOM CSV 导出的运行行为需由统计师",
          "在批准的目标环境（", sas_execution_profile_registry()[["sas-9.4m5-self-contained/v1"]]$minimum_version,
          "，UTF-8 会话）中运行确认，本仓库未做 compile-and-run。***\n")
  invisible(TRUE)
}

if (sys.nframe() == 0L) {
  arguments <- commandArgs(trailingOnly = TRUE)
  if ("--write-golden" %in% arguments) {
    scs_generate_golden(scs_check_source())
  } else {
    check_self_contained_sas_generation_main()
  }
}
