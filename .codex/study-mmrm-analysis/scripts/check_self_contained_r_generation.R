options(encoding = "UTF-8")
options(warn = 2L)

find_self_contained_root <- function(path) {
  current <- normalizePath(path, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "self_contained_r.R"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) stop("project root not found")
    current <- parent
  }
}

self_contained_check_source <- function() {
  project_dir <- find_self_contained_root(getwd())
  helper_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
  for (helper in c("canonical_hash.R", "standard_contract.R", "standard_analysis_definition.R", "program_generation_ir.R", "program_conformance.R", "self_contained_r.R")) {
    source(file.path(helper_dir, helper), encoding = "UTF-8", local = globalenv())
  }
  project_dir
}

self_contained_log <- function(...) {
  cat(paste0(c(...), collapse = ""))
  flush(stdout())
  invisible(NULL)
}

self_contained_hash <- function(letter) paste(rep(letter, 64L), collapse = "")
self_contained_expect_error <- function(expression, prefix) {
  error <- try(force(expression), silent = TRUE)
  stopifnot(inherits(error, "try-error"), grepl(prefix, as.character(error), fixed = TRUE))
  invisible(error)
}

self_contained_special_text <- function(value) paste0(value, " \"quoted\" \\backslash ;#% 中文")
# machine marker 是以空白分隔的 token，因此出现在 marker 中的取值只能使用不含空白的特殊字符。
self_contained_special_token <- function(value) paste0(value, "\"quoted\"\\backslash;#%中文")

self_contained_group <- function(id, label, codes, reporter_dimension, subscale, special = FALSE) {
  operator <- if (length(codes) == 1L) "eq" else "in"
  value <- if (length(codes) == 1L) codes[[1L]] else codes
  predicates <- list(list(variable = "PARAMCD", operator = operator, value = value))
  if (!is.null(reporter_dimension)) predicates <- c(predicates, list(list(variable = "REPORTER_GROUP", operator = "in", value = c("Caregiver", "Subject"))))
  list(
    id = id,
    label = if (special) self_contained_special_text(label) else label,
    predicates = predicates
  )
}

self_contained_endpoint <- function(id, codes, reporter_dimension, subscale) {
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

self_contained_fixture <- function(binding_mode = "linked", analysis_id = "MMRM-01", tfl_id = "T14-01",
                                   treatment = TRUE, pairwise = TRUE, group_count = 2L,
                                   derivations = TRUE, filters = TRUE,
                                   covariance = list(primary = "TOEP", fallback = as.list(c("CS", "AR1"))),
                                   special = FALSE, adapter = FALSE, format = "csv",
                                   dataset_sha256 = NULL, dataset_file = NULL) {
  linked <- identical(binding_mode, "linked")
  file_name <- if (!is.null(dataset_file)) dataset_file else paste0("scores.", format)
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
  filter_value <- if (special) self_contained_special_text("Y") else "Y"
  filter_list <- if (filters) list(list(variable = "ANALYSIS_FLAG", operator = "eq", value = filter_value)) else list()
  reporter_dimension <- if (derivations) TRUE else NULL
  groups <- list(self_contained_group("TOTAL", "Total score", c("SCORE_A", "SCORE_B"), reporter_dimension, "total", special))
  endpoints <- list(self_contained_endpoint("TOTAL", c("SCORE_A", "SCORE_B"), reporter_dimension, "total"))
  if (2L <= group_count) {
    groups <- c(groups, list(self_contained_group("SUBSCALE", "Subscale score", "SCORE_C", NULL, "sub1", special)))
    endpoints <- c(endpoints, list(self_contained_endpoint("SUBSCALE", "SCORE_C", NULL, "sub1")))
  }
  model_terms <- list(list(kind = "main_effect", role = "baseline"), list(kind = "main_effect", role = "visit"), list(kind = "interaction", of = list("baseline", "visit")))
  if (treatment) model_terms <- c(model_terms, list(list(kind = "main_effect", role = "treatment"), list(kind = "interaction", of = list("treatment", "visit"))))
  analysis <- list(
    analysis_id = analysis_id, tfl_id = tfl_id,
    title = if (special) self_contained_special_text("Synthetic self-contained analysis") else "Synthetic self-contained analysis",
    dataset = list(binding_mode = binding_mode, file = file_name, format = format,
                   relative_path = if (linked) paste0("studies/synthetic/input/adam/", file_name) else NULL,
                   sha256 = if (linked) (if (is.null(dataset_sha256)) self_contained_hash("A") else dataset_sha256) else NULL),
    mappings = mappings, derivations = derivation_list, filters = filter_list,
    groups = groups, endpoint_definitions = endpoints,
    model_terms = model_terms, reml = TRUE, covariance = covariance,
    df_method = "Satterthwaite",
    estimands = list(visit_lsmeans = TRUE, treatment_visit_lsmeans = treatment, pairwise_differences = treatment && pairwise),
    output = standard_contract_expected_output(tfl_id)
  )
  if (treatment) {
    levels <- if (special) c(self_contained_special_token("Placebo"), self_contained_special_token("Active")) else c("Placebo", "Active")
    analysis$treatment <- list(variable = "RANDOM_ARM", levels = levels, reference = levels[[1L]], comparator = levels[[2L]],
                               contrast_direction = "comparator_minus_reference", confidence_level = 0.95, multiplicity_adjustment = "none")
  }
  if (adapter) {
    analysis$adapter_file <- "studies/synthetic/analysis/r/adapter.R"
    analysis$adapter_sha256 <- self_contained_hash("9")
  }
  approval <- list(
    review_file = "studies/synthetic/statistician-review/statistical-review.md", review_sha256 = self_contained_hash("C"),
    analysis_plan_file = "studies/synthetic/statistician-review/analysis-plan.yaml", analysis_plan_sha256 = self_contained_hash("B"),
    approval_payload_sha256 = self_contained_hash("D"), source_evidence_sha256 = self_contained_hash("E"),
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

self_contained_identities <- function(contract) list(
  plan_sha256 = contract$approval$analysis_plan_sha256,
  approval_payload_sha256 = contract$approval$approval_payload_sha256,
  contract_sha256 = self_contained_hash("F")
)

self_contained_render <- function(contract) {
  analysis <- contract$analyses[[1L]]
  render_self_contained_r_program(contract, analysis, self_contained_identities(contract))
}

self_contained_assert_program <- function(contract, label) {
  analysis <- contract$analyses[[1L]]
  identities <- self_contained_identities(contract)
  ir <- build_program_generation_ir(contract, analysis, identities)
  program <- render_self_contained_r_program(contract, analysis, identities)
  again <- render_self_contained_r_program(contract, analysis, identities)
  stopifnot(
    is.character(program), length(program) == 1L, !is.na(program), nzchar(program),
    identical(program, again),
    !is.na(iconv(program, from = "UTF-8", to = "UTF-8")),
    !grepl(">", program, fixed = TRUE),
    !grepl("%include", program, fixed = TRUE)
  )
  parsed <- parse(text = program)
  stopifnot(0L < length(parsed))
  validate_generated_r_program(program, ir)
  for (marker in program_expected_markers(ir)) stopifnot(program_count_marker(program, marker) == 1L)
  lines <- strsplit(program, "\n", fixed = TRUE)[[1L]]
  boundary <- "# 至此完成数据处理。以下代码开始进行 MMRM 模型拟合；请勿混淆两部分职责。"
  stopifnot(sum(lines == boundary) == 1L)
  self_contained_log("fixture 通过静态检查：", label, "（", length(lines), " 行）\n", sep = "")
  list(ir = ir, program = program, lines = lines)
}

self_contained_synthetic_frame <- function() {
  subjects <- sprintf("S%02d", seq_len(20L))
  arms <- rep(c("Placebo", "Active"), length.out = 20L)
  versions <- rep(c("SCORE_A", "SCORE_B"), length.out = 20L)
  reporters <- rep(c("Mother", "Self"), length.out = 20L)
  baseline <- 40 + seq_len(20L)
  pieces <- list()
  for (i in seq_along(subjects)) {
    for (visit in 1:3) {
      for (code in c(versions[[i]], "SCORE_C")) {
        offset <- if (identical(code, "SCORE_C")) 1.25 else 0
        pieces[[length(pieces) + 1L]] <- data.frame(
          PERSON_ID = subjects[[i]], PARAMCD = code, TIME_INDEX = visit,
          TIME_LABEL = paste0("第 ", visit, " 次访视"), RANDOM_ARM = arms[[i]],
          REPORTER = reporters[[i]], ANALYSIS_FLAG = "Y", START_SCORE = baseline[[i]],
          DELTA_SCORE = round(baseline[[i]] * 0.1 + visit * 1.5 + (if (identical(arms[[i]], "Active")) 2 else 0) + ((i * 7L + visit * 3L) %% 5L) - 2 + offset, 2),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  excluded <- data.frame(PERSON_ID = "S01", PARAMCD = "SCORE_A", TIME_INDEX = 9L, TIME_LABEL = "第 9 次访视",
                         RANDOM_ARM = "Placebo", REPORTER = "Mother", ANALYSIS_FLAG = "N", START_SCORE = 41,
                         DELTA_SCORE = 99, stringsAsFactors = FALSE)
  incomplete <- data.frame(PERSON_ID = "S21", PARAMCD = "SCORE_A", TIME_INDEX = 1L, TIME_LABEL = "第 1 次访视",
                           RANDOM_ARM = "Placebo", REPORTER = "Mother", ANALYSIS_FLAG = "Y", START_SCORE = 61,
                           DELTA_SCORE = NA_real_, stringsAsFactors = FALSE)
  do.call(rbind, c(pieces, list(excluded, incomplete)))
}

self_contained_write_utf8_bom_csv <- function(frame, path) {
  temporary <- tempfile(fileext = ".csv")
  on.exit(unlink(temporary), add = TRUE)
  utils::write.csv(frame, file = temporary, row.names = FALSE, na = "", fileEncoding = "UTF-8")
  content <- readBin(temporary, what = "raw", n = file.size(temporary))
  connection <- file(path, open = "wb")
  on.exit(close(connection), add = TRUE)
  writeBin(c(as.raw(c(239L, 187L, 191L)), content), connection)
  invisible(path)
}

self_contained_rscript <- function() {
  candidates <- c(
    file.path(R.home("bin"), if (identical(.Platform$OS.type, "windows")) "Rscript.exe" else "Rscript"),
    file.path(R.home("bin"), "x64", "Rscript.exe"),
    unname(Sys.which("Rscript"))
  )
  candidates <- candidates[nzchar(candidates) & file.exists(candidates)]
  if (!length(candidates)) return("")
  candidates[[1L]]
}

self_contained_run <- function(rscript, program_path, input_dir, output_dir, log_path) {
  suppressWarnings(system2(
    rscript,
    c("--vanilla", shQuote(program_path), "--input-dir", shQuote(input_dir), "--output-dir", shQuote(output_dir)),
    stdout = log_path, stderr = log_path
  ))
}

self_contained_log_text <- function(log_path) {
  if (!file.exists(log_path)) return("")
  paste(readLines(log_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

self_contained_has_execution_packages <- function() {
  installed <- rownames(utils::installed.packages(lib.loc = .libPaths()))
  setdiff(c("digest", "mmrm", "emmeans"), installed)
}

check_self_contained_r_generation_main <- function() {
  self_contained_check_source()

  randomized <- self_contained_fixture()
  single_arm <- self_contained_fixture(analysis_id = "MMRM-02", tfl_id = "T14-02", treatment = FALSE)
  planned <- self_contained_fixture(binding_mode = "planned", analysis_id = "MMRM-03", tfl_id = "T14-03")
  sas_format <- self_contained_fixture(analysis_id = "MMRM-04", tfl_id = "T14-04", format = "sas7bdat")
  multi_fallback <- self_contained_fixture(analysis_id = "MMRM-05", tfl_id = "T14-05",
                                           covariance = list(primary = "UN", fallback = as.list(c("TOEP", "CS", "AR1"))))
  pairwise_off <- self_contained_fixture(analysis_id = "MMRM-06", tfl_id = "T14-06", pairwise = FALSE)
  minimal <- self_contained_fixture(analysis_id = "MMRM-07", tfl_id = "T14-07", group_count = 1L, derivations = FALSE, filters = FALSE)
  special <- self_contained_fixture(analysis_id = "MMRM-08", tfl_id = "T14-08", special = TRUE)

  randomized_program <- self_contained_assert_program(randomized, "randomized linked (derivation + filter + 2 groups + primary/fallback)")
  single_arm_program <- self_contained_assert_program(single_arm, "single-arm linked")
  planned_program <- self_contained_assert_program(planned, "planned code-generation-only")
  sas_program <- self_contained_assert_program(sas_format, "linked sas7bdat 读取分支")
  multi_fallback_program <- self_contained_assert_program(multi_fallback, "primary + 3 个 fallback covariance")
  pairwise_off_program <- self_contained_assert_program(pairwise_off, "pairwise differences 关闭")
  minimal_program <- self_contained_assert_program(minimal, "无 derivation / 无 filter / 单组")
  special_program <- self_contained_assert_program(special, "恶意与特殊字符 literal 转义")

  # 各 fixture 的分支断言。
  stopifnot(
    grepl("DATA_AVAILABLE <- TRUE", randomized_program$program, fixed = TRUE),
    grepl("CODE_GENERATION_ONLY <- FALSE", randomized_program$program, fixed = TRUE),
    grepl("utils::read.csv(", randomized_program$program, fixed = TRUE),
    !grepl("haven::read_sas", randomized_program$program, fixed = TRUE),
    grepl("PROGRAM-MARKER:PACKAGE:digest", randomized_program$program, fixed = TRUE),
    grepl("emmeans::contrast(", randomized_program$program, fixed = TRUE)
  )
  stopifnot(
    grepl("haven::read_sas(", sas_program$program, fixed = TRUE),
    !grepl("utils::read.csv(", sas_program$program, fixed = TRUE),
    grepl("PROGRAM-MARKER:PACKAGE:haven", sas_program$program, fixed = TRUE)
  )
  stopifnot(
    grepl("DATA_AVAILABLE <- FALSE", planned_program$program, fixed = TRUE),
    grepl("CODE_GENERATION_ONLY <- TRUE", planned_program$program, fixed = TRUE),
    grepl("PROGRAM-MARKER:GATE:PLANNED_CODE_GENERATION_ONLY", planned_program$program, fixed = TRUE),
    !grepl("PROGRAM-MARKER:GATE:LINKED_SHA256", planned_program$program, fixed = TRUE),
    !grepl("digest::digest", planned_program$program, fixed = TRUE),
    grepl("quit(save = \"no\", status = 0L)", planned_program$program, fixed = TRUE)
  )
  stopifnot(
    !grepl("PROGRAM-MARKER:TREATMENT_REFERENCE", single_arm_program$program, fixed = TRUE),
    !grepl("PROGRAM-MARKER:ESTIMAND:pairwise_differences", single_arm_program$program, fixed = TRUE),
    !grepl("emmeans::contrast(", single_arm_program$program, fixed = TRUE),
    !grepl("treatment_f:visit_f", single_arm_program$program, fixed = TRUE)
  )
  stopifnot(
    grepl("PROGRAM-MARKER:ESTIMAND:treatment_visit_lsmeans", pairwise_off_program$program, fixed = TRUE),
    !grepl("PROGRAM-MARKER:ESTIMAND:pairwise_differences", pairwise_off_program$program, fixed = TRUE),
    !grepl("emmeans::contrast(", pairwise_off_program$program, fixed = TRUE)
  )
  covariance_markers <- vapply(c("UN", "TOEP", "CS", "AR1"), function(value) program_count_marker(multi_fallback_program$program, program_marker("COVARIANCE", value)), integer(1))
  stopifnot(all(covariance_markers == 1L),
            grepl("COVARIANCE_ORDER <- c(\"UN\", \"TOEP\", \"CS\", \"AR1\")", multi_fallback_program$program, fixed = TRUE))
  stopifnot(
    !grepl("PROGRAM-MARKER:DERIVATION:", minimal_program$program, fixed = TRUE),
    !grepl("PROGRAM-MARKER:FILTER:", minimal_program$program, fixed = TRUE),
    program_count_marker(minimal_program$program, program_marker("GROUP", "TOTAL")) == 1L
  )

  # 恶意/特殊字符必须被 escape 成合法 R literal，且求值后与原值逐字相同。
  special_value <- self_contained_special_text("Y")
  special_literal <- program_r_string_literal(special_value, "special")
  stopifnot(
    grepl(special_literal, special_program$program, fixed = TRUE),
    identical(eval(parse(text = special_literal)), special_value),
    grepl(program_r_string_literal(self_contained_special_token("Placebo"), "special"), special_program$program, fixed = TRUE),
    identical(eval(parse(text = program_r_string_literal(self_contained_special_token("Placebo"), "special"))), self_contained_special_token("Placebo"))
  )

  # SHA gate 必须出现在任何数据读取之前。
  sha_position <- regexpr("PROGRAM-MARKER:GATE:LINKED_SHA256", randomized_program$program, fixed = TRUE)[[1L]]
  read_position <- regexpr("utils::read.csv(", randomized_program$program, fixed = TRUE)[[1L]]
  digest_position <- regexpr("digest::digest(file = INPUT_FILE_PATH", randomized_program$program, fixed = TRUE)[[1L]]
  stopifnot(0L < sha_position, 0L < digest_position, sha_position < read_position, digest_position < read_position)

  # unsupported adapter 必须在渲染前阻断。
  adapter_contract <- self_contained_fixture(analysis_id = "MMRM-09", tfl_id = "T14-09", adapter = TRUE)
  self_contained_expect_error(
    render_self_contained_r_program(adapter_contract, adapter_contract$analyses[[1L]], self_contained_identities(adapter_contract)),
    "PROGRAM-INLINE-ADAPTER-UNSUPPORTED:MMRM-09"
  )
  self_contained_log("fixture 通过静态检查：unsupported adapter 在渲染前阻断\n")

  self_contained_execution_check()
  self_contained_log("Self-contained R generation focused check passed.\n")
}

self_contained_write_program <- function(program, path) {
  connection <- file(path, open = "wb")
  on.exit(close(connection), add = TRUE)
  writeBin(charToRaw(enc2utf8(program)), connection)
  invisible(path)
}

self_contained_first_bytes <- function(path, count = 3L) readBin(path, what = "raw", n = count)

self_contained_execution_check <- function() {
  rscript <- self_contained_rscript()
  run_root <- file.path(normalizePath(tempdir(), winslash = "/", mustWork = TRUE), paste0("self-contained-r-check-", Sys.getpid()))
  unlink(run_root, recursive = TRUE, force = TRUE)
  dir.create(run_root, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(run_root, recursive = TRUE, force = TRUE), add = TRUE)
  input_dir <- file.path(run_root, "input")
  tampered_input_dir <- file.path(run_root, "tampered-input")
  program_dir <- file.path(run_root, "program")
  for (path in c(input_dir, tampered_input_dir, program_dir)) dir.create(path, recursive = TRUE, showWarnings = FALSE)

  if (!nzchar(rscript)) {
    self_contained_log("跳过全部执行类断言：本机未解析到 Rscript 可执行文件，无法启动独立子进程。\n")
    return(invisible(FALSE))
  }

  # planned 程序：必须打印中文说明、以退出码 0 正常结束，且不产生任何输出文件。
  planned_contract <- self_contained_fixture(binding_mode = "planned", analysis_id = "MMRM-03", tfl_id = "T14-03")
  planned_program <- self_contained_render(planned_contract)
  planned_path <- file.path(program_dir, "planned.R")
  self_contained_write_program(planned_program, planned_path)
  planned_output <- file.path(run_root, "planned-output")
  dir.create(planned_output, recursive = TRUE, showWarnings = FALSE)
  planned_log <- file.path(run_root, "planned.log")
  planned_status <- self_contained_run(rscript, planned_path, input_dir, planned_output, planned_log)
  planned_text <- self_contained_log_text(planned_log)
  planned_artifacts <- list.files(planned_output, all.files = TRUE, no.. = TRUE, recursive = TRUE)
  stopifnot(
    identical(as.integer(planned_status), 0L),
    grepl("code-generation", planned_text, fixed = TRUE),
    length(planned_artifacts) == 0L,
    length(list.files(run_root, pattern = "[.]rds$", recursive = TRUE)) == 0L,
    !dir.exists(file.path(run_root, ".codex"))
  )
  self_contained_log("执行类断言已运行：planned 程序退出码 0、正常结束、未生成任何 TFL/model 文件。\n")

  missing_packages <- self_contained_has_execution_packages()
  if (length(missing_packages)) {
    self_contained_log("跳过 linked 执行类断言：本机缺少必需 R 包 ", paste(missing_packages, collapse = ", "),
        "；本次仅完成静态与 planned 执行验证，不声称 linked 执行已通过。\n", sep = "")
    return(invisible(FALSE))
  }

  frame <- self_contained_synthetic_frame()
  csv_path <- file.path(input_dir, "scores.csv")
  self_contained_write_utf8_bom_csv(frame, csv_path)
  actual_sha256 <- toupper(digest::digest(file = csv_path, algo = "sha256"))
  linked_contract <- self_contained_fixture(dataset_sha256 = actual_sha256)
  linked_program <- self_contained_render(linked_contract)
  stopifnot(!grepl(".codex", linked_program, fixed = TRUE))
  linked_path <- file.path(program_dir, "linked.R")
  self_contained_write_program(linked_program, linked_path)
  linked_output <- file.path(run_root, "linked-output")
  linked_log <- file.path(run_root, "linked.log")
  linked_status <- self_contained_run(rscript, linked_path, input_dir, linked_output, linked_log)
  linked_text <- self_contained_log_text(linked_log)
  if (!identical(as.integer(linked_status), 0L)) {
    self_contained_log("linked 程序独立执行失败，日志如下：\n", linked_text, "\n", sep = "")
    stop("linked synthetic fixture 独立执行必须成功。")
  }
  output <- linked_contract$analyses[[1L]]$output
  expected_files <- c(output$r_raw_file, output$r_final_file, output$r_diagnostic_file, output$r_run_record_file)
  for (file_name in expected_files) stopifnot(file.exists(file.path(linked_output, file_name)))
  stopifnot(setequal(list.files(linked_output), expected_files))
  final_path <- file.path(linked_output, output$r_final_file)
  stopifnot(identical(self_contained_first_bytes(final_path), as.raw(c(239L, 187L, 191L))))
  final_table <- utils::read.csv(final_path, stringsAsFactors = FALSE, check.names = FALSE, fileEncoding = "UTF-8-BOM")
  run_record <- utils::read.csv(file.path(linked_output, output$r_run_record_file), stringsAsFactors = FALSE, check.names = FALSE, fileEncoding = "UTF-8-BOM")
  diagnostic <- utils::read.csv(file.path(linked_output, output$r_diagnostic_file), stringsAsFactors = FALSE, check.names = FALSE, fileEncoding = "UTF-8-BOM")
  stopifnot(
    0L < nrow(final_table),
    setequal(unique(final_table$analysis_group_id), c("TOTAL", "SUBSCALE")),
    "treatment_contrast" %in% final_table$row_type,
    any(grepl("第 1 次访视", final_table$visit, fixed = TRUE)),
    identical(run_record$execution_status[[1L]], "executed"),
    identical(diagnostic$actual_input_sha256[[1L]], actual_sha256),
    identical(as.integer(diagnostic$missing_required_rows[[1L]]), 1L),
    !dir.exists(file.path(run_root, ".codex")),
    length(list.files(run_root, pattern = "[.]rds$", recursive = TRUE)) == 0L
  )
  self_contained_log("执行类断言已运行：linked 程序在合成 CSV fixture 上独立生成 raw/final/diagnostic/run-record，且不接触共享代码目录。\n")

  # 篡改输入：SHA gate 必须在读取数据之前失败，且不写出任何 TFL。
  tampered_frame <- frame
  tampered_frame$DELTA_SCORE[[1L]] <- tampered_frame$DELTA_SCORE[[1L]] + 1
  self_contained_write_utf8_bom_csv(tampered_frame, file.path(tampered_input_dir, "scores.csv"))
  tampered_output <- file.path(run_root, "tampered-output")
  tampered_log <- file.path(run_root, "tampered.log")
  tampered_status <- self_contained_run(rscript, linked_path, tampered_input_dir, tampered_output, tampered_log)
  tampered_text <- self_contained_log_text(tampered_log)
  stopifnot(
    !identical(as.integer(tampered_status), 0L),
    grepl("SHA-256", tampered_text, fixed = TRUE),
    grepl("expected=", tampered_text, fixed = TRUE),
    !file.exists(file.path(tampered_output, output$r_raw_file)),
    !file.exists(file.path(tampered_output, output$r_final_file))
  )
  self_contained_log("执行类断言已运行：篡改输入后 SHA-256 gate 在读取数据之前阻断，且未写出 raw/final TFL。\n")
  invisible(TRUE)
}

if (sys.nframe() == 0L) check_self_contained_r_generation_main()
