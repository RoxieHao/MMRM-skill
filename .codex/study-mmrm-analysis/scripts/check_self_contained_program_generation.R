options(encoding = "UTF-8")

# ==============================================================================
# Phase 7 自检：端到端固定 fixtures（implementation plan 第 10 章）
#
# 语义前提（用户已明确，不可违背）：
#   * 本流水线从不执行 SAS。无论有无 ADaM 数据，SAS 只作为代码交付物生成，由统计师自行
#     在批准的目标环境运行。本脚本、collector 与任何检查都不调用 SAS 可执行文件；
#     SAS 侧只做静态 / conformance / golden 验证。
#   * 全部 fixture 都在本脚本自己创建的临时 study 目录中构造，全部为合成数据；
#     绝不引用、也绝不产生真实患者级数据。
#   * 四类主 fixture（A linked / B planned / C unsupported adapter / D tampered-input 与
#     transaction）全部走生产入口：finalize_statistical_review → approve_and_generate_analysis。
#     每个失败场景之后都用磁盘快照断言“逐字节恢复为上一套完整产物”。
#
# 失败一律使用稳定错误码（PROGRAM-*、PLAN-*、COLLECTOR-*），不依赖模糊文本匹配。
# ==============================================================================

find_root <- function(path) {
  current <- normalizePath(path, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "analysis_approval.R"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) stop("project root not found")
    current <- parent
  }
}
project_dir <- find_root(getwd())
helper_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
for (helper in c("study_paths.R", "io.R", "specification.R", "canonical_hash.R", "standard_contract.R",
                 "standard_analysis_definition.R", "analysis_plan.R", "analysis_contract_generation.R",
                 "program_generation_ir.R", "program_conformance.R", "self_contained_r.R", "self_contained_sas.R",
                 "standard_sas.R", "standard_engine.R", "standard_artifacts.R", "review_finalization.R",
                 "analysis_approval.R", "case_summary.R")) {
  source(file.path(helper_dir, helper), encoding = "UTF-8", local = globalenv())
}
if (!requireNamespace("digest", quietly = TRUE) || !requireNamespace("yaml", quietly = TRUE)) stop("digest and yaml are required")

p7_log <- function(...) { cat(paste0(c(...), collapse = "")); flush(stdout()); invisible(NULL) }
p7_section <- function(title) p7_log("\n== ", title, " ==\n")
p7_norm <- function(path) gsub("\\\\", "/", path)

p7_expect_error <- function(expression, fragment = NULL) {
  error <- try(force(expression), silent = TRUE)
  stopifnot(inherits(error, "try-error"))
  if (!is.null(fragment)) stopifnot(grepl(fragment, as.character(error), fixed = TRUE))
  invisible(trimws(as.character(error)))
}

# 进程级 override：把 globalenv 中的某个函数临时替换成注入失败的版本，求值结束后必定恢复。
p7_with_override <- function(name, replacement, expression) {
  original <- get(name, envir = globalenv())
  assign(name, replacement, envir = globalenv())
  on.exit({ assign(name, original, envir = globalenv()); stopifnot(identical(get(name, envir = globalenv()), original)) }, add = TRUE)
  force(expression)
}

p7_canonical_text <- function(text) paste(strsplit(gsub("\r\n", "\n", as.character(text), fixed = TRUE), "\n", fixed = TRUE)[[1L]], collapse = "\n")
p7_read_program <- function(path) {
  raw <- readBin(path, what = "raw", n = file.size(path))
  p7_canonical_text(iconv(rawToChar(raw), from = "UTF-8", to = "UTF-8"))
}
p7_bytes <- function(path) readBin(path, what = "raw", n = file.size(path))
p7_write_bytes <- function(bytes, path) {
  connection <- file(path, open = "wb")
  on.exit(close(connection), add = TRUE)
  writeBin(bytes, connection)
  invisible(path)
}
p7_write_text <- function(text, path) {
  connection <- file(path, open = "wb")
  on.exit(close(connection), add = TRUE)
  writeBin(charToRaw(enc2utf8(paste0(p7_canonical_text(text), "\n"))), connection)
  invisible(path)
}

# 磁盘快照：整个 study 目录逐文件 SHA-256。事务失败后必须逐字节相同。
p7_snapshot <- function(study_dir) {
  root <- normalizePath(study_dir, winslash = "/", mustWork = TRUE)
  files <- sort(p7_norm(list.files(root, recursive = TRUE, all.files = TRUE, full.names = TRUE, no.. = TRUE, include.dirs = FALSE)))
  if (!length(files)) return(setNames(character(), character()))
  setNames(vapply(files, file_sha256, character(1), USE.NAMES = FALSE), substring(files, nchar(root) + 2L))
}
p7_assert_snapshot <- function(study_dir, expected, label) {
  actual <- p7_snapshot(study_dir)
  if (!identical(actual, expected)) {
    added <- setdiff(names(actual), names(expected)); removed <- setdiff(names(expected), names(actual))
    common <- intersect(names(actual), names(expected)); changed <- common[actual[common] != expected[common]]
    stop("P7-ROLLBACK-INCOMPLETE: ", label, "；新增=", paste(added, collapse = ","),
         "；丢失=", paste(removed, collapse = ","), "；被改写=", paste(changed, collapse = ","))
  }
  p7_log("回滚断言通过（磁盘逐字节恢复为上一套完整产物）：", label, "\n")
  invisible(TRUE)
}
p7_assert_no_transaction_residue <- function(study_dir) {
  journal <- analysis_approval_journal_path(study_dir)
  txn_dir <- analysis_approval_transaction_dir(study_dir)
  residue <- if (dir.exists(txn_dir)) list.files(txn_dir, all.files = TRUE, no.. = TRUE) else character()
  if (file.exists(journal) || length(residue)) {
    stop("P7-TRANSACTION-RESIDUE: journal=", file.exists(journal), "; 残片=", paste(residue, collapse = ","))
  }
  invisible(TRUE)
}

p7_program_inventory <- function(study_dir) {
  r_dir <- file.path(study_dir, "analysis", "r"); sas_dir <- file.path(study_dir, "analysis", "sas")
  list(r = sort(if (dir.exists(r_dir)) list.files(r_dir, pattern = "[.][Rr]$") else character()),
       sas = sort(if (dir.exists(sas_dir)) list.files(sas_dir, pattern = "[.]sas$") else character()))
}

# 生成程序文本卫生断言：不得含 .codex、source(（R）、%include（SAS）、TODO/TBD 或未替换占位符。
p7_assert_program_hygiene <- function(text, language, label) {
  problems <- character()
  if (grepl(".codex", text, fixed = TRUE)) problems <- c(problems, ".codex")
  if (grepl("TODO", text, fixed = TRUE)) problems <- c(problems, "TODO")
  if (grepl("TBD", text, fixed = TRUE)) problems <- c(problems, "TBD")
  if (grepl("<[A-Za-z0-9_.:/|-]{1,60}>", text, perl = TRUE)) problems <- c(problems, "未替换占位符 <...>")
  if (grepl("run_standard_mmrm_analysis", text, fixed = TRUE)) problems <- c(problems, "run_standard_mmrm_analysis")
  if (identical(language, "r")) {
    if (grepl("source[[:space:]]*\\(", text)) problems <- c(problems, "source(")
  } else {
    if (grepl("%include", text, fixed = TRUE)) problems <- c(problems, "%include")
  }
  if (is.na(iconv(text, from = "UTF-8", to = "UTF-8"))) problems <- c(problems, "非法 UTF-8")
  if (length(problems)) stop("P7-PROGRAM-HYGIENE: ", label, " 含禁止内容：", paste(problems, collapse = ", "))
  invisible(TRUE)
}

# 完整发布断言（每次成功批准之后都要跑）：
#   * 严格 N 个 .R + N 个 .sas + run_all_mmrm.R，且没有任何 *_template.sas；
#   * 磁盘上的每个程序都通过真实 conformance validator，并与重新渲染的文本逐字符相同；
#   * 全量程序集合通过 validate_tfl_program_coverage；
#   * planned 程序含永久 code-generation-only gate，linked 程序含 SHA-256 gate；
#   * 生成程序文本不含 .codex / source( / %include / TODO / TBD / 未替换占位符。
p7_assert_full_generation <- function(study_dir, contract, payload_sha, contract_sha, label) {
  ids <- vapply(contract$analyses, function(x) as.character(x$analysis_id), character(1))
  r_paths <- vapply(ids, function(id) analysis_generation_program_path(study_dir, id, "r"), character(1), USE.NAMES = FALSE)
  sas_paths <- vapply(ids, function(id) analysis_generation_program_path(study_dir, id, "sas"), character(1), USE.NAMES = FALSE)
  collector <- analysis_generated_collector_target(study_dir)
  inventory <- p7_program_inventory(study_dir)
  stopifnot(
    all(file.exists(c(r_paths, sas_paths, collector))),
    setequal(inventory$r, c(basename(r_paths), "run_all_mmrm.R")),
    length(inventory$r) == length(ids) + 1L,
    setequal(inventory$sas, basename(sas_paths)),
    length(inventory$sas) == length(ids),
    !any(grepl("_template[.]sas$", inventory$sas)),
    !any(grepl("_template[.]sas$", basename(analysis_generated_targets(study_dir, contract))))
  )
  identities <- analysis_generation_identities(contract, payload_sha, contract_sha)
  texts <- list()
  for (analysis in contract$analyses) {
    ir <- build_program_generation_ir(contract, analysis, identities)
    r_path <- analysis_generation_program_path(study_dir, analysis$analysis_id, "r")
    sas_path <- analysis_generation_program_path(study_dir, analysis$analysis_id, "sas")
    r_text <- p7_read_program(r_path); sas_text <- p7_read_program(sas_path)
    validate_generated_r_program(r_text, ir)
    validate_generated_sas_program(sas_text, ir)
    stopifnot(identical(r_text, p7_canonical_text(render_self_contained_r_program(contract, analysis, identities))),
              identical(sas_text, p7_canonical_text(render_self_contained_sas_program(contract, analysis, identities))))
    p7_assert_program_hygiene(r_text, "r", basename(r_path))
    p7_assert_program_hygiene(sas_text, "sas", basename(sas_path))
    if (identical(as.character(analysis$dataset$binding_mode), "planned")) {
      stopifnot(
        grepl(program_marker("GATE", "PLANNED_CODE_GENERATION_ONLY"), r_text, fixed = TRUE),
        grepl("CODE_GENERATION_ONLY <- TRUE", r_text, fixed = TRUE),
        grepl("if (isTRUE(CODE_GENERATION_ONLY)) stop(", r_text, fixed = TRUE),
        grepl(program_marker("GATE", "PLANNED_CODE_GENERATION_ONLY"), sas_text, fixed = TRUE),
        grepl("%let CODE_GENERATION_ONLY=YES;", sas_text, fixed = TRUE),
        grepl("%let RUN_STATUS=code_generation_only;", sas_text, fixed = TRUE)
      )
    } else {
      stopifnot(
        grepl("CODE_GENERATION_ONLY <- FALSE", r_text, fixed = TRUE),
        grepl("%let CODE_GENERATION_ONLY=NO;", sas_text, fixed = TRUE),
        grepl(program_marker("GATE", "LINKED_SHA256"), r_text, fixed = TRUE),
        grepl(program_marker("GATE", "LINKED_SHA256"), sas_text, fixed = TRUE)
      )
    }
    texts[[r_path]] <- r_text; texts[[sas_path]] <- sas_text
  }
  validate_tfl_program_coverage(contract, texts)
  collector_text <- p7_read_program(collector)
  stopifnot(!grepl("<APPROVAL_PAYLOAD_SHA256>", collector_text, fixed = TRUE),
            !grepl("<CONTRACT_SHA256>", collector_text, fixed = TRUE),
            grepl(toupper(payload_sha), collector_text, fixed = TRUE),
            grepl(toupper(contract_sha), collector_text, fixed = TRUE))
  p7_log("完整发布断言通过：", label, "（", length(ids), " 个 analysis → ", length(r_paths), " 个 .R + ",
         length(sas_paths), " 个 .sas + run_all_mmrm.R；无 _template.sas；程序文本无 .codex/source(/%include/TODO/TBD/占位符）\n")
  invisible(texts)
}

# ------------------------------------------------------------------------------
# 合成 fixture 构造（全部为合成数据，绝不引用真实患者级数据）
# ------------------------------------------------------------------------------

# 合成 CSV：20 个受试者 × 3 次访视 × 2 个终点（版本码 + 子量表码），randomized 两臂，
# 含一行 ANALYSIS_FLAG=N（必须被 filter 排除）与一个缺失应答的受试者（诊断计数 1）。
p7_synthetic_frame <- function() {
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
          TIME_LABEL = paste0("\u7b2c ", visit, " \u6b21\u8bbf\u89c6"), RANDOM_ARM = arms[[i]],
          REPORTER = reporters[[i]], ANALYSIS_FLAG = "Y", START_SCORE = baseline[[i]],
          DELTA_SCORE = round(baseline[[i]] * 0.1 + visit * 1.5 + (if (identical(arms[[i]], "Active")) 2 else 0) + ((i * 7L + visit * 3L) %% 5L) - 2 + offset, 2),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  excluded <- data.frame(PERSON_ID = "S01", PARAMCD = "SCORE_A", TIME_INDEX = 9L, TIME_LABEL = "\u7b2c 9 \u6b21\u8bbf\u89c6",
                         RANDOM_ARM = "Placebo", REPORTER = "Mother", ANALYSIS_FLAG = "N", START_SCORE = 41,
                         DELTA_SCORE = 99, stringsAsFactors = FALSE)
  incomplete <- data.frame(PERSON_ID = "S21", PARAMCD = "SCORE_A", TIME_INDEX = 1L, TIME_LABEL = "\u7b2c 1 \u6b21\u8bbf\u89c6",
                           RANDOM_ARM = "Placebo", REPORTER = "Mother", ANALYSIS_FLAG = "Y", START_SCORE = 61,
                           DELTA_SCORE = NA_real_, stringsAsFactors = FALSE)
  do.call(rbind, c(pieces, list(excluded, incomplete)))
}

# 字节级可控的 UTF-8 BOM CSV writer（生成程序读入的输入文件必须与 contract SHA 完全一致）。
p7_write_utf8_bom_csv <- function(frame, path) {
  temporary <- tempfile(fileext = ".csv")
  on.exit(unlink(temporary, force = TRUE), add = TRUE)
  utils::write.csv(frame, file = temporary, row.names = FALSE, na = "", fileEncoding = "UTF-8")
  content <- readBin(temporary, what = "raw", n = file.size(temporary))
  connection <- file(path, open = "wb")
  on.exit(try(close(connection), silent = TRUE), add = TRUE)
  writeBin(c(as.raw(c(239L, 187L, 191L)), content), connection)
  invisible(path)
}

p7_dimension_na <- function() list(variable = "not_applicable", values = character())

# 一个 plan 级 analysis：可控 binding mode、treatment、recode 派生、filter、组数、
# covariance 序列、df method、estimands、adapter。
p7_plan_analysis <- function(analysis_id, tfl_id, evidence_id, binding_mode, source_path,
                             treatment = TRUE, pairwise = TRUE, derivations = TRUE, filters = TRUE,
                             group_count = 2L,
                             covariance = list(primary = "UN", fallback = as.list(c("AR1", "CS"))),
                             df_method = "Kenward-Roger", adapter = NULL) {
  linked <- identical(binding_mode, "linked")
  mappings <- list(subject = "PERSON_ID", response = "DELTA_SCORE", baseline = "START_SCORE",
                   visit = "TIME_INDEX", visit_label = "TIME_LABEL")
  if (treatment) mappings$treatment <- "RANDOM_ARM"
  derivation_list <- if (derivations) list(list(
    id = "REPORTER_RECODE", operation = "recode", source_variable = "REPORTER", target_variable = "REPORTER_GROUP",
    levels = list(list(target_value = "Caregiver", source_values = c("Mother", "Father", "Guardian")),
                  list(target_value = "Subject", source_values = "Self")),
    unmatched = "error", missing = "preserve",
    source_ref = list(review_rule = paste0(tfl_id, "/endpoint_dimension"), reviewer_decision = evidence_id)
  )) else list()
  filter_list <- if (filters) list(list(variable = "ANALYSIS_FLAG", operator = "eq", value = "Y")) else list()
  total_predicates <- list(list(variable = "PARAMCD", operator = "in", value = c("SCORE_A", "SCORE_B")))
  if (derivations) total_predicates <- c(total_predicates, list(list(variable = "REPORTER_GROUP", operator = "in", value = c("Caregiver", "Subject"))))
  groups <- list(list(id = "TOTAL", label = "Total score", predicates = total_predicates))
  endpoints <- list(list(group_id = "TOTAL", endpoint_variable = "PARAMCD", selected_codes = c("SCORE_A", "SCORE_B"),
                         selection_mode = "mutually_exclusive_versions",
                         dimensions = list(instrument = list(variable = "fixed", values = "Scale X"),
                                           version = list(variable = "PARAMCD", values = c("SCORE_A", "SCORE_B")),
                                           reporter = if (derivations) list(variable = "REPORTER_GROUP", values = c("Caregiver", "Subject")) else p7_dimension_na(),
                                           subscale = list(variable = "fixed", values = "total")),
                         row_allocation_rule = "one_row_per_subject_endpoint_visit"))
  if (2L <= group_count) {
    groups <- c(groups, list(list(id = "SUBSCALE", label = "Subscale score",
                                  predicates = list(list(variable = "PARAMCD", operator = "eq", value = "SCORE_C")))))
    endpoints <- c(endpoints, list(list(group_id = "SUBSCALE", endpoint_variable = "PARAMCD", selected_codes = "SCORE_C",
                                        selection_mode = "single_code",
                                        dimensions = list(instrument = list(variable = "fixed", values = "Scale X"),
                                                          version = list(variable = "PARAMCD", values = "SCORE_C"),
                                                          reporter = p7_dimension_na(),
                                                          subscale = list(variable = "fixed", values = "sub1")),
                                        row_allocation_rule = "one_row_per_subject_endpoint_visit")))
  }
  fixed_effects <- c("baseline", "visit", "baseline_by_visit")
  if (treatment) fixed_effects <- c(fixed_effects, "treatment", "treatment_by_visit")
  dataset <- if (linked) {
    list(binding_mode = "linked", file = "scores.csv", format = "csv",
         relative_path = project_relative_path(source_path, project_dir), sha256 = file_sha256(source_path))
  } else list(binding_mode = "planned", file = "scores.csv", format = "csv", relative_path = NULL, sha256 = NULL)
  trace <- setNames(rep(list(list()), length(analysis_plan_trace_keys())), analysis_plan_trace_keys())
  keys <- c("dataset", "mappings", "groups", "endpoint_definitions", "fixed_effects", "reml", "covariance", "df_method", "estimands")
  if (derivations) keys <- c(keys, "derivations")
  if (filters) keys <- c(keys, "filters")
  if (treatment) keys <- c(keys, "treatment")
  if (!is.null(adapter)) keys <- c(keys, "adapter")
  for (name in keys) trace[[name]] <- list(evidence_id)
  analysis <- list(analysis_id = analysis_id, source_tfl_id = tfl_id,
                   title = paste0("Phase 7 fixture ", analysis_id), dataset = dataset, adapter = adapter,
                   mappings = mappings, derivations = derivation_list, filters = filter_list,
                   groups = groups, endpoint_definitions = endpoints,
                   fixed_effects = as.list(fixed_effects), reml = TRUE, covariance = covariance,
                   df_method = df_method,
                   estimands = list(visit_lsmeans = TRUE, treatment_visit_lsmeans = treatment,
                                    pairwise_differences = treatment && pairwise),
                   treatment = NULL, trace = trace)
  if (treatment) {
    analysis$treatment <- list(variable = "RANDOM_ARM", levels = c("Placebo", "Active"), reference = "Placebo",
                               comparator = "Active", contrast_direction = "comparator_minus_reference",
                               confidence_level = 0.95, multiplicity_adjustment = "none")
  }
  analysis
}

p7_plan <- function(study_id, analyses) {
  linked <- any(vapply(analyses, function(x) identical(as.character(x$dataset$binding_mode), "linked"), logical(1)))
  list(analysis_plan_schema_version = "2.1", study_id = study_id,
       execution_context = list(profile_version = standard_mmrm_profile_version(),
                                data_availability = if (linked) "available" else "none",
                                data_classification = if (linked) "dummy" else "none",
                                intended_use = if (linked) "technical_validation" else "code_generation",
                                sas_execution_profile = "sas-9.4m5-self-contained/v1"),
       analyses = analyses)
}

# 可以走完 finalize → approve 全链路的合成 study。
p7_build_study <- function(prefix) {
  study_dir <- tempfile(prefix, tmpdir = project_dir)
  for (directory in c("input", "backup-trace", "statistician-review")) dir.create(file.path(study_dir, directory), recursive = TRUE)
  source_path <- file.path(study_dir, "input", "scores.csv")
  p7_write_utf8_bom_csv(p7_synthetic_frame(), source_path)
  manifest <- data.frame(source_id = "SRC-DATA-01", input_type = "analysis_dataset", file_name = "scores.csv",
                         relative_path = "input/scores.csv", version = "1",
                         file_size_bytes = file.info(source_path)$size, modified_at = "2026-08-21T00:00:00Z",
                         sha256 = file_sha256(source_path), status = "linked_source", note = "synthetic", stringsAsFactors = FALSE)
  manifest_path <- file.path(study_dir, "backup-trace", "input-manifest.csv"); write_utf8_bom_csv(manifest, manifest_path)
  registry <- source_evidence_registry(project_dir, study_dir); evidence_id <- registry$ids[[1L]]; study_id <- basename(study_dir)
  review_path <- file.path(study_dir, "statistician-review", "statistical-review.md")
  metadata <- list(review_schema_version = "2.0", study_id = study_id, generation_route = "synthetic_check", review_status = "pending",
                   reviewed_by = "", reviewed_at_utc = "", finalization_status = "pending",
                   source_manifest_file = project_relative_path(manifest_path, project_dir), analysis_plan_file = "", analysis_plan_sha256 = "",
                   source_evidence_sha256 = "", review_execution_content_sha256 = "", approval_payload_sha256 = "")
  body <- c("# Synthetic statistical review", "", "## 1. \u5ba1\u9605\u7ed3\u8bba\u4e0e\u7b7e\u6838", "Pending.", "",
            "## 2. Study \u4e0e\u6570\u636e\u8303\u56f4", "Synthetic evidence.", "", "## 3. Analysis \u4e0e TFL \u6e05\u5355", "Typed plan only.", "",
            "## 4. Analysis Plan\uff08\u53ea\u8bfb\uff09", "<!-- ANALYSIS_PLAN_BEGIN -->", "Pending.", "<!-- ANALYSIS_PLAN_END -->", "",
            "## 5. \u6a21\u578b\u3001\u534f\u65b9\u5dee\u4e0e\u4f30\u8ba1\u91cf\u786e\u8ba4", "Typed plan only.", "",
            "## 6. Adapter / \u6d3e\u751f / \u884c\u5206\u914d\u786e\u8ba4", "Typed plan only.", "",
            "## 7. \u672a\u89e3\u51b3\u95ee\u9898\u4e0e\u51b3\u8bae", "| issue_id | scope | question_or_risk | resolution | status |", "|---|---|---|---|---|", "",
            "## 8. Approval Payload \u6307\u7eb9", "Pending.")
  writeLines(c("---", strsplit(yaml::as.yaml(metadata), "\n", fixed = TRUE)[[1L]], "---", "", body), review_path, useBytes = TRUE)
  list(study_dir = study_dir, review_path = review_path, source_path = source_path, evidence_id = evidence_id, study_id = study_id)
}

p7_publish_plan <- function(fixture, plan) {
  analysis_plan_write(plan, analysis_plan_candidate_path(fixture$study_dir))
  lines <- statistical_review_set_metadata(readLines(fixture$review_path, encoding = "UTF-8", warn = FALSE), "review_status", "ready_for_compilation")
  writeLines(lines, fixture$review_path, useBytes = TRUE)
  result <- finalize_statistical_review(fixture$study_dir, fixture$review_path, fixture$review_path, "Synthetic Reviewer", allow_unresolved = TRUE)
  if (!isTRUE(result$published) || !isTRUE(result$approved)) {
    stop("P7-FIXTURE: finalization failed: ", paste(result$issues$observed, collapse = " | "))
  }
  stopifnot(identical(result$analysis_count, length(plan$analyses)))
  invisible(result)
}

# 生产入口：finalize 之后走 approve_and_generate_analysis，并立刻做完整发布断言。
p7_run_chain <- function(fixture, label) {
  chain <- approve_and_generate_analysis(fixture$study_dir, project_dir, "Synthetic Reviewer")
  stopifnot(identical(as.character(chain$review$metadata$review_status), "approved"),
            file.exists(analysis_contract_path(fixture$study_dir)))
  p7_assert_no_transaction_residue(fixture$study_dir)
  p7_assert_full_generation(fixture$study_dir, chain$contract, chain$approval_payload_sha256, chain$contract_sha256, label)
  chain
}

# 运行证据 fixture（raw/final/diagnostic/run-record/manifest）：任何 approval transaction
# 之后都必须仍然存在且逐字节不变。
p7_write_runtime_evidence <- function(study_dir, contract) {
  paths <- list(analysis_output_dir = file.path(study_dir, "output", "analyses"))
  manifest <- file.path(study_dir, "output", "tfl-output-manifest.csv")
  dir.create(dirname(manifest), recursive = TRUE, showWarnings = FALSE)
  writeLines("tfl_id,output_status,note", manifest, useBytes = TRUE)
  created <- manifest
  for (analysis in contract$analyses) {
    output_paths <- analysis_output_paths(paths, as.character(analysis$analysis_id))
    for (directory in c(output_paths$root, output_paths$tables, output_paths$diagnostics, output_paths$logs)) dir.create(directory, recursive = TRUE, showWarnings = FALSE)
    files <- c(output_paths$run_record, output_paths$diagnostic_csv, output_paths$log_file,
               file.path(output_paths$tables, analysis$output$r_raw_file), file.path(output_paths$tables, analysis$output$r_final_file),
               file.path(output_paths$tables, analysis$output$sas_raw_file), file.path(output_paths$tables, analysis$output$sas_final_file))
    for (file_path in files) writeLines(paste0("runtime-evidence:", basename(file_path)), file_path, useBytes = TRUE)
    created <- c(created, files)
  }
  stopifnot(all(file.exists(created)))
  p7_log("\u5df2\u6784\u9020\u8fd0\u884c\u8bc1\u636e ", length(created), " \u4e2a\u6587\u4ef6\uff08raw/final/diagnostic/run-record/manifest\uff09\n")
  created
}
p7_assert_runtime_evidence_intact <- function(evidence, expected_sha, label) {
  stopifnot(all(file.exists(evidence)), identical(vapply(evidence, file_sha256, character(1), USE.NAMES = FALSE), expected_sha))
  p7_log("\u8fd0\u884c\u8bc1\u636e\u672a\u88ab approval publisher \u89e6\u78b0\uff1a", label, "\uff08", length(evidence), " \u4e2a\u6587\u4ef6\uff09\n")
  invisible(TRUE)
}

# 目标环境能力声明 override（test-only）：置为缺少 FCMP / 位运算 / SHA-256。
p7_capability_override <- local({
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
      stopifnot(isTRUE(sas_execution_profile_registry()[["sas-9.4m5-self-contained/v1"]]$sha256))
    }
    invisible(NULL)
  }
})

p7_rscript <- function() {
  candidates <- c(file.path(R.home("bin"), if (identical(.Platform$OS.type, "windows")) "Rscript.exe" else "Rscript"),
                  file.path(R.home("bin"), "x64", "Rscript.exe"), unname(Sys.which("Rscript")))
  candidates <- candidates[nzchar(candidates) & file.exists(candidates)]
  if (!length(candidates)) "" else candidates[[1L]]
}
p7_run_program <- function(rscript, program_path, input_dir, output_dir, log_path) {
  suppressWarnings(system2(rscript, c("--vanilla", shQuote(program_path), "--input-dir", shQuote(input_dir), "--output-dir", shQuote(output_dir)),
                           stdout = log_path, stderr = log_path))
}
p7_log_text <- function(log_path) if (!file.exists(log_path)) "" else paste(readLines(log_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")

p7_missing_packages <- setdiff(c("digest", "mmrm", "emmeans"), rownames(utils::installed.packages(lib.loc = .libPaths())))
p7_rscript_path <- p7_rscript()
p7_can_execute <- !length(p7_missing_packages) && nzchar(p7_rscript_path)
if (!p7_can_execute) {
  p7_log("\n*** \u8df3\u8fc7\u5168\u90e8\u6267\u884c\u7c7b\u65ad\u8a00\uff08\u4e0d\u58f0\u79f0\u901a\u8fc7\uff09\uff1a",
         if (length(p7_missing_packages)) paste0("\u672c\u673a\u7f3a\u5c11\u5fc5\u9700 R \u5305 ", paste(p7_missing_packages, collapse = ", "), "\uff1b") else "",
         if (!nzchar(p7_rscript_path)) "\u672c\u673a\u672a\u89e3\u6790\u5230 Rscript \u53ef\u6267\u884c\u6587\u4ef6\uff1b" else "",
         "\u53ea\u5b8c\u6210\u9759\u6001\u4e0e\u4e8b\u52a1\u7c7b\u65ad\u8a00\u3002***\n")
} else {
  p7_log("\n\u6267\u884c\u73af\u5883\u5c31\u7ef2\uff1adigest/mmrm/emmeans \u5747\u5df2\u5b89\u88c5\uff1bRscript=", p7_rscript_path, "\n")
}

p7_temp_root <- file.path(normalizePath(tempdir(), winslash = "/", mustWork = TRUE), paste0("p7-e2e-", Sys.getpid()))
unlink(p7_temp_root, recursive = TRUE, force = TRUE)
dir.create(p7_temp_root, recursive = TRUE, showWarnings = FALSE)
p7_studies <- character()
p7_cleanup <- function() {
  unlink(p7_temp_root, recursive = TRUE, force = TRUE)
  if (length(p7_studies)) unlink(p7_studies, recursive = TRUE, force = TRUE)
}
# 注意：不在顶层使用 on.exit（顶层 on.exit 的作用域不可靠）。清理在脚本末尾显式执行；
# 中途失败时残留的临时 study 会以 zz_p7_ 前缀留在项目根目录，便于人工核对后手动删除。

# ==============================================================================
# A. linked fixture：合成 CSV、randomized treatment、recode + filter + 两个 group、
#    covariance UN → AR1 → CS、treatment LS means 与 pairwise differences、N=1 R/SAS，
#    R 程序独立执行并产出带语言后缀的结果文件，篡改输入后 SHA gate 在读取前失败。
# ==============================================================================
p7_section("A. linked fixture（N=1，生产入口 finalize \u2192 approve）")

linked_fixture <- p7_build_study("zz_p7_linked_")
p7_studies <- c(p7_studies, linked_fixture$study_dir)
linked_analysis <- p7_plan_analysis("MMRM-A1", "T14-A1", linked_fixture$evidence_id, "linked", linked_fixture$source_path)
linked_plan <- p7_plan(linked_fixture$study_id, list(linked_analysis))
p7_publish_plan(linked_fixture, linked_plan)
linked_chain <- p7_run_chain(linked_fixture, "A linked \u9996\u6b21\u6279\u51c6\u53d1\u5e03")
linked_contract <- linked_chain$contract
linked_contract_analysis <- linked_contract$analyses[[1L]]
linked_output_names <- linked_contract_analysis$output
linked_r_path <- analysis_generation_program_path(linked_fixture$study_dir, "MMRM-A1", "r")
linked_sas_path <- analysis_generation_program_path(linked_fixture$study_dir, "MMRM-A1", "sas")

# A 的统计语义必须真的落到生成程序里（不是只有 contract 层面）。
linked_r_text <- p7_read_program(linked_r_path)
linked_sas_text <- p7_read_program(linked_sas_path)
stopifnot(
  identical(length(linked_contract$analyses), 1L),
  identical(as.character(linked_contract_analysis$dataset$binding_mode), "linked"),
  # randomized treatment + 两臂对比方向
  program_count_marker(linked_r_text, program_marker("TREATMENT_REFERENCE", "Placebo")) == 1L,
  program_count_marker(linked_sas_text, program_marker("TREATMENT_REFERENCE", "Placebo")) == 1L,
  program_count_marker(linked_r_text, program_marker("MAPPING", "treatment:RANDOM_ARM")) == 1L,
  # recode 派生 + filter + 两个 group
  program_count_marker(linked_r_text, program_marker("DERIVATION", "REPORTER_RECODE")) == 1L,
  program_count_marker(linked_sas_text, program_marker("DERIVATION", "REPORTER_RECODE")) == 1L,
  program_count_marker(linked_r_text, program_marker("FILTER", "1")) == 1L,
  program_count_marker(linked_r_text, program_marker("GROUP", "TOTAL")) == 1L,
  program_count_marker(linked_r_text, program_marker("GROUP", "SUBSCALE")) == 1L,
  program_count_marker(linked_sas_text, program_marker("GROUP", "TOTAL")) == 1L,
  program_count_marker(linked_sas_text, program_marker("GROUP", "SUBSCALE")) == 1L,
  # covariance UN → AR1 → CS 的顺序
  grepl("COVARIANCE_ORDER <- c(\"UN\", \"AR1\", \"CS\")", linked_r_text, fixed = TRUE),
  all(vapply(c("UN", "AR1", "CS"), function(x) program_count_marker(linked_r_text, program_marker("COVARIANCE", x)) == 1L, logical(1))),
  all(vapply(c("UN", "AR1", "CS"), function(x) program_count_marker(linked_sas_text, program_marker("COVARIANCE", x)) == 1L, logical(1))),
  # treatment LS means 与 pairwise differences
  program_count_marker(linked_r_text, program_marker("ESTIMAND", "treatment_visit_lsmeans")) == 1L,
  program_count_marker(linked_r_text, program_marker("ESTIMAND", "pairwise_differences")) == 1L,
  program_count_marker(linked_sas_text, program_marker("ESTIMAND", "pairwise_differences")) == 1L,
  grepl("emmeans::contrast(", linked_r_text, fixed = TRUE),
  # 结果文件名带语言后缀，R 与 SAS 互不重叠
  identical(as.character(linked_output_names$r_final_file), "T14-A1_r_final.csv"),
  identical(as.character(linked_output_names$sas_final_file), "T14-A1_sas_final.csv"),
  !length(intersect(tolower(unlist(linked_output_names[c("r_raw_file", "r_final_file", "r_diagnostic_file", "r_run_record_file")], use.names = FALSE)),
                    tolower(unlist(linked_output_names[c("sas_raw_file", "sas_final_file", "sas_diagnostic_file", "sas_run_record_file")], use.names = FALSE))))
)
p7_log("A \u9759\u6001\u65ad\u8a00\u901a\u8fc7\uff1arandomized treatment / recode / filter / \u4e24\u4e2a group / UN\u2192AR1\u2192CS / ",
       "treatment LS means \u4e0e pairwise differences \u5168\u90e8\u843d\u5230 R \u4e0e SAS \u7a0b\u5e8f\uff0c\u4e14\u7ed3\u679c\u6587\u4ef6\u540d\u5e26\u8bed\u8a00\u540e\u7f00\u3002\n")

# SHA gate 必须在任何数据读取之前（文本位置断言，与执行断言互补）。
sha_position <- regexpr(program_marker("GATE", "LINKED_SHA256"), linked_r_text, fixed = TRUE)[[1L]]
digest_position <- regexpr("digest::digest(file = INPUT_FILE_PATH", linked_r_text, fixed = TRUE)[[1L]]
read_position <- regexpr("utils::read.csv(", linked_r_text, fixed = TRUE)[[1L]]
stopifnot(0L < sha_position, 0L < digest_position, 0L < read_position, sha_position < read_position, digest_position < read_position)
p7_log("A \u9759\u6001\u65ad\u8a00\u901a\u8fc7\uff1aSHA-256 gate \u4e0e digest \u8ba1\u7b97\u5747\u4f4d\u4e8e\u6570\u636e\u8bfb\u53d6\u4e4b\u524d\u3002\n")

if (!p7_can_execute) {
  p7_log("A \u6267\u884c\u7c7b\u65ad\u8a00\u672a\u8fd0\u884c\uff08\u539f\u56e0\u5df2\u5728\u4e0a\u65b9\u6253\u5370\uff09\uff1b\u4e0d\u5f97\u89c6\u4e3a\u5df2\u901a\u8fc7\u3002\n")
} else {
  a_output_dir <- file.path(p7_temp_root, "a-linked-output")
  a_log <- file.path(p7_temp_root, "a-linked.log")
  a_status <- p7_run_program(p7_rscript_path, linked_r_path, file.path(linked_fixture$study_dir, "input"), a_output_dir, a_log)
  if (!identical(as.integer(a_status), 0L)) {
    p7_log("A linked \u7a0b\u5e8f\u72ec\u7acb\u6267\u884c\u5931\u8d25\uff0c\u65e5\u5fd7\uff1a\n", p7_log_text(a_log), "\n")
    stop("P7-A-EXECUTION: linked \u5408\u6210 fixture \u7684 R \u7a0b\u5e8f\u5fc5\u987b\u72ec\u7acb\u6267\u884c\u6210\u529f\u3002")
  }
  expected_files <- unname(unlist(linked_output_names[c("r_raw_file", "r_final_file", "r_diagnostic_file", "r_run_record_file")], use.names = FALSE))
  stopifnot(setequal(list.files(a_output_dir), expected_files))
  a_final <- file.path(a_output_dir, linked_output_names$r_final_file)
  stopifnot(identical(readBin(a_final, what = "raw", n = 3L), as.raw(c(239L, 187L, 191L))))
  a_final_table <- utils::read.csv(a_final, stringsAsFactors = FALSE, check.names = FALSE, fileEncoding = "UTF-8-BOM")
  a_run_record <- utils::read.csv(file.path(a_output_dir, linked_output_names$r_run_record_file), stringsAsFactors = FALSE, check.names = FALSE, fileEncoding = "UTF-8-BOM")
  a_diagnostic <- utils::read.csv(file.path(a_output_dir, linked_output_names$r_diagnostic_file), stringsAsFactors = FALSE, check.names = FALSE, fileEncoding = "UTF-8-BOM")
  stopifnot(
    0L < nrow(a_final_table),
    setequal(unique(a_final_table$analysis_group_id), c("TOTAL", "SUBSCALE")),
    "treatment_contrast" %in% a_final_table$row_type,
    any(grepl("\u7b2c 1 \u6b21\u8bbf\u89c6", a_final_table$visit, fixed = TRUE)),
    identical(a_run_record$execution_status[[1L]], "executed"),
    identical(a_run_record$programming_language[[1L]], "R"),
    identical(toupper(a_diagnostic$actual_input_sha256[[1L]]), toupper(as.character(linked_contract_analysis$dataset$sha256))),
    identical(as.integer(a_diagnostic$missing_required_rows[[1L]]), 1L),
    !dir.exists(file.path(a_output_dir, ".codex"))
  )
  p7_log("A \u6267\u884c\u7c7b\u65ad\u8a00\u5df2\u5b9e\u9645\u8fd0\u884c\uff1aN=1 \u7684 R \u7a0b\u5e8f\u7528 --input-dir/--output-dir \u72ec\u7acb\u6267\u884c\u6210\u529f\uff0c",
         "\u4ea7\u51fa r_raw/r_final/r_diagnostic/r_run_record \u56db\u4e2a\u5e26\u8bed\u8a00\u540e\u7f00\u7684\u7ed3\u679c\u6587\u4ef6\uff0cfinal CSV \u4e3a UTF-8 BOM\u3002\n")

  # 篡改输入：SHA gate 必须在读取数据之前失败，且不写 raw/final。
  a_tampered_input <- file.path(p7_temp_root, "a-tampered-input")
  dir.create(a_tampered_input, recursive = TRUE, showWarnings = FALSE)
  tampered_frame <- p7_synthetic_frame()
  tampered_frame$DELTA_SCORE[[1L]] <- tampered_frame$DELTA_SCORE[[1L]] + 1
  p7_write_utf8_bom_csv(tampered_frame, file.path(a_tampered_input, "scores.csv"))
  a_tampered_output <- file.path(p7_temp_root, "a-tampered-output")
  a_tampered_log <- file.path(p7_temp_root, "a-tampered.log")
  a_tampered_status <- p7_run_program(p7_rscript_path, linked_r_path, a_tampered_input, a_tampered_output, a_tampered_log)
  a_tampered_text <- p7_log_text(a_tampered_log)
  stopifnot(
    !identical(as.integer(a_tampered_status), 0L),
    grepl("SHA-256", a_tampered_text, fixed = TRUE),
    grepl("expected=", a_tampered_text, fixed = TRUE),
    !file.exists(file.path(a_tampered_output, linked_output_names$r_raw_file)),
    !file.exists(file.path(a_tampered_output, linked_output_names$r_final_file)),
    !any(grepl("\u5df2\u5b8c\u6210\u6a21\u578b\u62df\u5408", a_tampered_text, fixed = TRUE))
  )
  p7_log("A \u6267\u884c\u7c7b\u65ad\u8a00\u5df2\u5b9e\u9645\u8fd0\u884c\uff1a\u7be1\u6539\u8f93\u5165\u540e SHA-256 gate \u5728\u8bfb\u53d6\u6570\u636e\u4e4b\u524d\u963b\u65ad\uff0c",
         "\u9000\u51fa\u7801\u975e 0\uff0c\u4e14\u672a\u5199\u51fa raw/final\u3002\n")
}

# A study 的运行证据 fixture（供 C/D 的回滚与“运行证据永不删除”断言使用）。
linked_evidence <- p7_write_runtime_evidence(linked_fixture$study_dir, linked_contract)
linked_evidence_sha <- vapply(linked_evidence, file_sha256, character(1), USE.NAMES = FALSE)
linked_baseline <- p7_snapshot(linked_fixture$study_dir)
linked_r_bytes <- p7_bytes(linked_r_path)
linked_sas_bytes <- p7_bytes(linked_sas_path)

# ==============================================================================
# B. planned fixture：dataset relative_path 与 sha256 均为 null，其余统计语义完整；
#    批准与生成成功；R、SAS 与 collector 都保留完整代码但阻断运行；输出目录没有
#    final/model 文件；collector manifest 中 R 与 SAS 行均为 code_generation_only
#    且结果路径留空。
# ==============================================================================
p7_section("B. planned fixture（N=1，null path/hash，code-generation-only）")

planned_fixture <- p7_build_study("zz_p7_planned_")
p7_studies <- c(p7_studies, planned_fixture$study_dir)
planned_analysis <- p7_plan_analysis("MMRM-B1", "T14-B1", planned_fixture$evidence_id, "planned", planned_fixture$source_path)
planned_plan <- p7_plan(planned_fixture$study_id, list(planned_analysis))
stopifnot(is.null(planned_plan$analyses[[1L]]$dataset$relative_path), is.null(planned_plan$analyses[[1L]]$dataset$sha256),
          identical(planned_plan$execution_context$data_availability, "none"),
          identical(planned_plan$execution_context$intended_use, "code_generation"))
p7_publish_plan(planned_fixture, planned_plan)
planned_chain <- p7_run_chain(planned_fixture, "B planned \u9996\u6b21\u6279\u51c6\u53d1\u5e03")
planned_contract <- planned_chain$contract
planned_contract_analysis <- planned_contract$analyses[[1L]]
planned_r_path <- analysis_generation_program_path(planned_fixture$study_dir, "MMRM-B1", "r")
planned_sas_path <- analysis_generation_program_path(planned_fixture$study_dir, "MMRM-B1", "sas")
planned_r_text <- p7_read_program(planned_r_path)
planned_sas_text <- p7_read_program(planned_sas_path)

stopifnot(
  is.null(planned_contract_analysis$dataset$relative_path), is.null(planned_contract_analysis$dataset$sha256),
  identical(as.character(planned_contract_analysis$dataset$binding_mode), "planned"),
  # 其余统计语义完整：treatment / recode / filter / 两个 group / UN→AR1→CS / pairwise
  program_count_marker(planned_r_text, program_marker("TREATMENT_REFERENCE", "Placebo")) == 1L,
  program_count_marker(planned_r_text, program_marker("DERIVATION", "REPORTER_RECODE")) == 1L,
  program_count_marker(planned_r_text, program_marker("FILTER", "1")) == 1L,
  program_count_marker(planned_r_text, program_marker("GROUP", "TOTAL")) == 1L,
  program_count_marker(planned_r_text, program_marker("GROUP", "SUBSCALE")) == 1L,
  program_count_marker(planned_r_text, program_marker("ESTIMAND", "pairwise_differences")) == 1L,
  all(vapply(c("UN", "AR1", "CS"), function(x) program_count_marker(planned_r_text, program_marker("COVARIANCE", x)) == 1L, logical(1))),
  all(vapply(c("UN", "AR1", "CS"), function(x) program_count_marker(planned_sas_text, program_marker("COVARIANCE", x)) == 1L, logical(1))),
  # 保留完整代码但阻断运行
  grepl("mmrm::mmrm(", planned_r_text, fixed = TRUE),
  grepl("emmeans::contrast(", planned_r_text, fixed = TRUE),
  grepl("proc mixed", tolower(planned_sas_text), fixed = TRUE),
  grepl("CODE_GENERATION_ONLY <- TRUE", planned_r_text, fixed = TRUE),
  grepl("%let CODE_GENERATION_ONLY=YES;", planned_sas_text, fixed = TRUE),
  # linked 专属 SHA gate 不得出现在 planned 程序里
  !grepl(program_marker("GATE", "LINKED_SHA256"), planned_r_text, fixed = TRUE),
  !grepl("digest::digest", planned_r_text, fixed = TRUE)
)
p7_expect_error(assert_analysis_execution_allowed(planned_chain, analysis_id = "MMRM-B1"), "planned analysis is code-generation-only")
p7_log("B \u9759\u6001\u65ad\u8a00\u901a\u8fc7\uff1anull path/hash\u3001\u7edf\u8ba1\u8bed\u4e49\u5b8c\u6574\u3001R \u4e0e SAS \u4fdd\u7559\u5b8c\u6574\u5efa\u6a21\u4ee3\u7801\u4f46\u5e26\u6c38\u4e45 code-generation-only gate\uff0c",
       "\u4e14\u751f\u4ea7\u5165\u53e3 assert_analysis_execution_allowed \u62d2\u7ecd\u6267\u884c\u3002\n")

if (!p7_can_execute) {
  p7_log("B \u7684 R/collector \u6267\u884c\u7c7b\u65ad\u8a00\u672a\u8fd0\u884c\uff08\u539f\u56e0\u5df2\u5728\u4e0a\u65b9\u6253\u5370\uff09\uff1b\u4e0d\u5f97\u89c6\u4e3a\u5df2\u901a\u8fc7\u3002\n")
} else {
  # planned 程序独立执行：以退出码 0 结束、打印 code-generation 说明、不产生任何输出文件。
  b_output_dir <- file.path(p7_temp_root, "b-planned-output")
  dir.create(b_output_dir, recursive = TRUE, showWarnings = FALSE)
  b_log <- file.path(p7_temp_root, "b-planned.log")
  b_status <- p7_run_program(p7_rscript_path, planned_r_path, file.path(planned_fixture$study_dir, "input"), b_output_dir, b_log)
  stopifnot(identical(as.integer(b_status), 0L), grepl("code-generation", p7_log_text(b_log), fixed = TRUE),
            length(list.files(b_output_dir, all.files = TRUE, no.. = TRUE, recursive = TRUE)) == 0L)
  p7_log("B \u6267\u884c\u7c7b\u65ad\u8a00\u5df2\u5b9e\u9645\u8fd0\u884c\uff1aplanned R \u7a0b\u5e8f\u9000\u51fa\u7801 0\u3001\u672a\u62df\u5408\u6a21\u578b\u3001\u672a\u751f\u6210\u4efb\u4f55\u8f93\u51fa\u6587\u4ef6\u3002\n")

  # collector 子进程运行。PATH 前置会写 sentinel 的假 sas 命令：collector 全程不得触发。
  b_collector <- analysis_generated_collector_target(planned_fixture$study_dir)
  b_fake_bin <- file.path(planned_fixture$study_dir, "backup-trace", "fake-bin")
  dir.create(b_fake_bin, recursive = TRUE, showWarnings = FALSE)
  b_sentinel <- file.path(planned_fixture$study_dir, "backup-trace", "sas-was-invoked.txt")
  for (fake in c("sas.bat", "sas.cmd", "sas9.bat")) {
    writeLines(c("@echo off", paste0("echo invoked > \"", gsub("/", "\\\\", b_sentinel), "\"")), file.path(b_fake_bin, fake), useBytes = TRUE)
  }
  b_collector_log <- file.path(planned_fixture$study_dir, "backup-trace", "collector-subprocess.log")
  b_old_path <- Sys.getenv("PATH")
  Sys.setenv(PATH = paste(b_fake_bin, b_old_path, sep = .Platform$path.sep))
  b_collector_status <- suppressWarnings(system2(p7_rscript_path, c("--vanilla", shQuote(b_collector)), stdout = b_collector_log, stderr = b_collector_log))
  Sys.setenv(PATH = b_old_path)
  if (!identical(as.integer(b_collector_status), 0L)) {
    p7_log("B collector \u5b50\u8fdb\u7a0b\u5931\u8d25\uff0c\u65e5\u5fd7\uff1a\n", p7_log_text(b_collector_log), "\n")
    stop("P7-B-COLLECTOR: planned study \u7684 collector \u5fc5\u987b\u4ee5\u9000\u51fa\u7801 0 \u7ed3\u675f\u3002")
  }
  stopifnot(!file.exists(b_sentinel))
  b_manifest <- read_utf8_bom_csv(file.path(planned_fixture$study_dir, "output", "tfl-output-manifest.csv"))
  b_manifest[] <- lapply(b_manifest, function(column) { value <- as.character(column); value[is.na(value)] <- ""; value })
  standard_validate_collector_manifest(b_manifest, planned_contract)
  b_row_r <- b_manifest[b_manifest$analysis_id == "MMRM-B1" & b_manifest$programming_language == "R", , drop = FALSE]
  b_row_sas <- b_manifest[b_manifest$analysis_id == "MMRM-B1" & b_manifest$programming_language == "SAS", , drop = FALSE]
  b_analysis_output <- file.path(planned_fixture$study_dir, "output", "analyses", standard_contract_safe_identity("MMRM-B1"))
  stopifnot(
    identical(nrow(b_manifest), 2L),
    identical(nrow(b_row_r), 1L), identical(nrow(b_row_sas), 1L),
    identical(b_row_r$execution_status[[1L]], "code_generation_only"),
    identical(b_row_sas$execution_status[[1L]], "code_generation_only"),
    identical(b_row_r$binding_mode[[1L]], "planned"), identical(b_row_sas$binding_mode[[1L]], "planned"),
    identical(b_row_r$run_status[[1L]], "not_run"), identical(b_row_sas$run_status[[1L]], "not_run"),
    all(!nzchar(unlist(b_row_r[standard_collector_result_path_columns()], use.names = FALSE))),
    all(!nzchar(unlist(b_row_sas[standard_collector_result_path_columns()], use.names = FALSE))),
    identical(b_row_r$program_sha256[[1L]], file_sha256(planned_r_path)),
    identical(b_row_sas$program_sha256[[1L]], file_sha256(planned_sas_path)),
    # 输出目录没有 final/model 文件（planned analysis 不产出任何运行产物）
    length(list.files(b_analysis_output, all.files = TRUE, no.. = TRUE, recursive = TRUE)) == 0L,
    !file.exists(file.path(b_analysis_output, planned_contract_analysis$output$r_final_file)),
    !file.exists(file.path(b_analysis_output, planned_contract_analysis$output$sas_final_file)),
    !length(list.files(file.path(planned_fixture$study_dir, "output"), pattern = "(final|model)", recursive = TRUE))
  )
  b_collector_run_log <- readLines(file.path(planned_fixture$study_dir, "output", "logs", "run_all_mmrm.log"), warn = FALSE, encoding = "UTF-8")
  stopifnot(
    !any(grepl("invoke Rscript", b_collector_run_log, fixed = TRUE)),
    any(grepl("binding_mode=planned", b_collector_run_log, fixed = TRUE)),
    any(grepl("Rscript subprocess not invoked", b_collector_run_log, fixed = TRUE)),
    any(grepl("collector never executes SAS", b_collector_run_log, fixed = TRUE))
  )
  p7_log("B \u6267\u884c\u7c7b\u65ad\u8a00\u5df2\u5b9e\u9645\u8fd0\u884c\uff1acollector \u4ee5\u9000\u51fa\u7801 0 \u7ed3\u675f\u4f46\u4ece\u672a\u542f\u52a8\u4efb\u4f55 R \u5b50\u8fdb\u7a0b\u3001",
         "\u4ece\u672a\u89e6\u53d1\u4efb\u4f55 sas \u53ef\u6267\u884c\u6587\u4ef6\uff08sentinel \u672a\u88ab\u5199\u5165\uff09\uff1bmanifest \u7684 R \u4e0e SAS \u884c\u5747\u4e3a ",
         "code_generation_only \u4e14\u7ed3\u679c\u8def\u5f84\u7559\u7a7a\uff1b\u8f93\u51fa\u76ee\u5f55\u6ca1\u6709 final/model \u6587\u4ef6\u3002\n")
}

# ==============================================================================
# C. unsupported adapter：adapter binding 非 null → build_program_generation_ir 失败
#    （PROGRAM-INLINE-ADAPTER-UNSUPPORTED）；R 与 SAS 均不发布（磁盘上不出现新的 .R 或
#    .sas）；上一套已发布程序逐字节保持不变。
# ==============================================================================
p7_section("C. unsupported adapter（IR build \u5931\u8d25\uff0cR/SAS \u5747\u4e0d\u53d1\u5e03\uff09")

c_adapter_path <- file.path(linked_fixture$study_dir, "analysis", "adapter-source.R")
writeLines("# synthetic adapter deliverable", c_adapter_path, useBytes = TRUE)
c_adapter <- list(file = project_relative_path(c_adapter_path, project_dir), sha256 = file_sha256(c_adapter_path))
c_plan <- p7_plan(linked_fixture$study_id, list(p7_plan_analysis("MMRM-A1", "T14-A1", linked_fixture$evidence_id, "linked",
                                                                 linked_fixture$source_path, adapter = c_adapter)))
stopifnot(!is.null(c_plan$analyses[[1L]]$adapter))
p7_publish_plan(linked_fixture, c_plan)
c_snapshot <- p7_snapshot(linked_fixture$study_dir)
c_inventory <- p7_program_inventory(linked_fixture$study_dir)

# 1) IR builder 层的稳定错误码（不依赖模糊文本匹配）。
c_contract <- compile_analysis_plan_contract(c_plan, list(
  review_file = "synthetic/statistical-review.md", review_sha256 = paste(rep("A", 64L), collapse = ""),
  analysis_plan_file = "synthetic/analysis-plan.yaml", analysis_plan_sha256 = analysis_plan_sha256(c_plan),
  approval_payload_sha256 = paste(rep("B", 64L), collapse = ""), source_evidence_sha256 = paste(rep("C", 64L), collapse = ""),
  reviewed_by = "Synthetic Reviewer", approved_at_utc = "2026-08-21T00:00:00Z"))
c_identities <- analysis_generation_identities(c_contract, paste(rep("B", 64L), collapse = ""), paste(rep("F", 64L), collapse = ""))
p7_expect_error(build_program_generation_ir(c_contract, c_contract$analyses[[1L]], c_identities), "PROGRAM-INLINE-ADAPTER-UNSUPPORTED:MMRM-A1")

# 2) 生产入口整链阻断。
p7_expect_error(approve_and_generate_analysis(linked_fixture$study_dir, project_dir, "Synthetic Reviewer"),
                "PROGRAM-INLINE-ADAPTER-UNSUPPORTED:MMRM-A1")
p7_assert_no_transaction_residue(linked_fixture$study_dir)
p7_assert_snapshot(linked_fixture$study_dir, c_snapshot, "C unsupported adapter \u963b\u65ad\u540e\u7684\u78c1\u76d8\u72b6\u6001")
stopifnot(
  identical(p7_program_inventory(linked_fixture$study_dir), c_inventory),
  identical(p7_bytes(linked_r_path), linked_r_bytes),
  identical(p7_bytes(linked_sas_path), linked_sas_bytes)
)
p7_assert_runtime_evidence_intact(linked_evidence, linked_evidence_sha, "C unsupported adapter \u963b\u65ad\u540e")
p7_log("C \u65ad\u8a00\u901a\u8fc7\uff1a\u78c1\u76d8\u4e0a\u6ca1\u6709\u51fa\u73b0\u4efb\u4f55\u65b0\u7684 .R \u6216 .sas\uff08.R=", paste(c_inventory$r, collapse = ","),
       "\uff1b.sas=", paste(c_inventory$sas, collapse = ","), "\uff09\uff0c\u4e0a\u4e00\u5957\u5df2\u53d1\u5e03\u7a0b\u5e8f\u9010\u5b57\u8282\u4e0d\u53d8\u3002\n")

# 恢复原 plan（不重新批准）：磁盘应逐字节回到 A 的基线。
unlink(c_adapter_path, force = TRUE)
p7_publish_plan(linked_fixture, linked_plan)
p7_assert_snapshot(linked_fixture$study_dir, linked_baseline, "C \u4e4b\u540e\u6062\u590d\u5230 A \u57fa\u7ebf")

# ==============================================================================
# D. tampered input / transaction：
#    D1 linked 输入 SHA 被修改；
#    D2 已批准 contract 的 identity 被修改；
#    D3 已发布 program 的 identity 被修改（手改磁盘上程序里的 TFL ID）；
#    D4 publication 中间某个 target 注入失败（approve_and_generate_analysis 的 fail_after）。
#    每种情况都必须 fail closed 且事务回滚，journal 已清除、transaction 目录无残片。
# ==============================================================================
p7_section("D1. linked \u8f93\u5165 SHA \u88ab\u4fee\u6539\uff08\u6279\u51c6\u65f6\u95f8\u95e8\uff09")
d_snapshot <- p7_snapshot(linked_fixture$study_dir)
d_input_bytes <- p7_bytes(linked_fixture$source_path)
d_tampered_frame <- p7_synthetic_frame()
d_tampered_frame$DELTA_SCORE[[2L]] <- d_tampered_frame$DELTA_SCORE[[2L]] + 3
p7_write_utf8_bom_csv(d_tampered_frame, linked_fixture$source_path)
stopifnot(!identical(p7_bytes(linked_fixture$source_path), d_input_bytes))
p7_expect_error(approve_and_generate_analysis(linked_fixture$study_dir, project_dir, "Synthetic Reviewer"), "PLAN-HASH-SOURCE")
p7_expect_error(assert_approved_analysis(linked_fixture$study_dir, project_dir), "PLAN-HASH-SOURCE")
p7_assert_no_transaction_residue(linked_fixture$study_dir)
p7_write_bytes(d_input_bytes, linked_fixture$source_path)
stopifnot(identical(p7_bytes(linked_fixture$source_path), d_input_bytes))
p7_assert_snapshot(linked_fixture$study_dir, d_snapshot, "D1 \u8f93\u5165\u7be1\u6539\u963b\u65ad\u540e\uff08\u6062\u590d\u539f\u8f93\u5165\uff09")
stopifnot(!inherits(try(assert_approved_analysis(linked_fixture$study_dir, project_dir), silent = TRUE), "try-error"))
p7_log("D1 \u65ad\u8a00\u901a\u8fc7\uff1a\u8f93\u5165\u5b57\u8282\u88ab\u6539\u540e\u6279\u51c6\u4e0e\u518d\u6821\u9a8c\u5747\u4ee5 PLAN-HASH-SOURCE fail closed\uff0c\u4e14\u4e8b\u52a1\u672a\u542f\u52a8\u3001\u65e0\u6b8b\u7247\u3002\n")

p7_section("D2. \u5df2\u6279\u51c6 contract \u7684 identity \u88ab\u4fee\u6539")
d_contract_path <- analysis_contract_path(linked_fixture$study_dir)
d_contract_bytes <- p7_bytes(d_contract_path)
d_contract_lines <- readLines(d_contract_path, warn = FALSE, encoding = "UTF-8")
# 篡改 approval identity（reviewed_by）。
d_tampered_lines <- sub("Synthetic Reviewer", "Impostor Reviewer", d_contract_lines, fixed = TRUE)
stopifnot(!identical(d_contract_lines, d_tampered_lines))
writeLines(d_tampered_lines, d_contract_path, useBytes = TRUE)
p7_expect_error(assert_approved_analysis(linked_fixture$study_dir, project_dir), "PLAN-HASH-CONTRACT")
# 篡改 TFL identity：plan/contract 语义奇偶校验必须拒绝。
d_tfl_lines <- sub("T14-A1", "T14-A9", d_contract_lines, fixed = TRUE)
stopifnot(!identical(d_contract_lines, d_tfl_lines))
writeLines(d_tfl_lines, d_contract_path, useBytes = TRUE)
p7_expect_error(assert_approved_analysis(linked_fixture$study_dir, project_dir), "PLAN-")
p7_write_bytes(d_contract_bytes, d_contract_path)
stopifnot(identical(p7_bytes(d_contract_path), d_contract_bytes))
p7_assert_snapshot(linked_fixture$study_dir, d_snapshot, "D2 contract \u7be1\u6539\u963b\u65ad\u540e\uff08\u6062\u590d\u539f contract\uff09")
p7_log("D2 \u65ad\u8a00\u901a\u8fc7\uff1acontract \u7684 reviewed_by \u4e0e tfl_id \u88ab\u624b\u6539\u540e\uff0c\u751f\u4ea7\u6821\u9a8c\u5165\u53e3 fail closed\u3002\n")

p7_section("D3. \u5df2\u53d1\u5e03 program \u7684 identity \u88ab\u4fee\u6539\uff08conformance/coverage \u5fc5\u987b\u62d2\u7ecd\uff09")
d_chain <- assert_approved_analysis(linked_fixture$study_dir, project_dir)
d_paths <- study_paths(analysis_generated_collector_target(linked_fixture$study_dir))
stopifnot(!inherits(try(standard_collector_program_set(d_paths, d_chain$contract, d_chain, project_dir), silent = TRUE), "try-error"))
d_ir <- build_program_generation_ir(d_chain$contract, d_chain$contract$analyses[[1L]],
                                   analysis_generation_identities(d_chain$contract, d_chain$approval_payload_sha256, d_chain$contract_sha256))

# D3-a 手改磁盘上 R 程序里的 TFL ID：coverage 的 identity 闸门先于其他检查拒绝。
p7_write_text(gsub("T14-A1", "T14-A9", linked_r_text, fixed = TRUE), linked_r_path)
p7_expect_error(standard_collector_program_set(d_paths, d_chain$contract, d_chain, project_dir), "PROGRAM-TFL-COVERAGE-IDENTITY:MMRM-A1:R")
p7_expect_error(validate_generated_r_program(p7_read_program(linked_r_path), d_ir), "PROGRAM-R-CONFORMANCE-")
p7_write_bytes(linked_r_bytes, linked_r_path)

# D3-b 手改 R 程序的统计 marker（保留 identity）：conformance 必须拒绝。
p7_write_text(sub(program_marker("COVARIANCE", "AR1"), "PROGRAM-MARKER-REMOVED", linked_r_text, fixed = TRUE), linked_r_path)
p7_expect_error(standard_collector_program_set(d_paths, d_chain$contract, d_chain, project_dir), "PROGRAM-R-CONFORMANCE-")
p7_write_bytes(linked_r_bytes, linked_r_path)

# D3-c 同样篡改 SAS 程序：SAS 侧只做静态 / conformance 校验，绝不执行 SAS。
p7_write_text(gsub("T14-A1", "T14-A9", linked_sas_text, fixed = TRUE), linked_sas_path)
p7_expect_error(standard_collector_program_set(d_paths, d_chain$contract, d_chain, project_dir), "PROGRAM-TFL-COVERAGE-IDENTITY:MMRM-A1:sas")
p7_write_bytes(linked_sas_bytes, linked_sas_path)
p7_write_text(sub(program_marker("DF_METHOD", "Kenward-Roger"), "PROGRAM-MARKER-REMOVED", linked_sas_text, fixed = TRUE), linked_sas_path)
p7_expect_error(standard_collector_program_set(d_paths, d_chain$contract, d_chain, project_dir), "PROGRAM-SAS-CONFORMANCE-")
p7_write_bytes(linked_sas_bytes, linked_sas_path)
stopifnot(identical(p7_bytes(linked_r_path), linked_r_bytes), identical(p7_bytes(linked_sas_path), linked_sas_bytes))
p7_assert_snapshot(linked_fixture$study_dir, d_snapshot, "D3 program identity \u7be1\u6539\u963b\u65ad\u540e\uff08\u6062\u590d\u539f\u7a0b\u5e8f\uff09")
stopifnot(!inherits(try(standard_collector_program_set(d_paths, d_chain$contract, d_chain, project_dir), silent = TRUE), "try-error"))
p7_log("D3 \u65ad\u8a00\u901a\u8fc7\uff1a\u78c1\u76d8\u4e0a R \u6216 SAS \u7a0b\u5e8f\u7684 TFL ID \u88ab\u624b\u6539\u540e\uff0ccollector \u7684\u7a0b\u5e8f\u96c6\u5408\u95f8\u95e8\u3001",
       "\u9010\u8bed\u8a00 conformance \u4e0e coverage \u5747\u4ee5\u7a33\u5b9a\u9519\u8bef\u7801\u62d2\u7ecd\u3002\n")

p7_section("D4. publication \u4e2d\u95f4 target \u6ce8\u5165\u5931\u8d25\uff08\u4e8b\u52a1\u56de\u6eda\uff09")
d_publish_targets <- 1L + length(analysis_generated_targets(linked_fixture$study_dir, d_chain$contract))
stopifnot(identical(d_publish_targets, 4L))
for (fail_after in c(0L, 1L, 2L, 3L)) {
  label <- paste0("D4 publication \u7b2c ", fail_after + 1L, " / ", d_publish_targets, " \u4e2a target \u5931\u8d25")
  p7_expect_error(approve_and_generate_analysis(linked_fixture$study_dir, project_dir, "Synthetic Reviewer", fail_after = fail_after),
                  "Injected target publication failure")
  p7_assert_no_transaction_residue(linked_fixture$study_dir)
  p7_assert_snapshot(linked_fixture$study_dir, d_snapshot, label)
  p7_assert_runtime_evidence_intact(linked_evidence, linked_evidence_sha, label)
}
# 回滚之后生产入口仍然可以正常重新批准并发布完整产物。
d_final_chain <- p7_run_chain(linked_fixture, "D4 \u5168\u90e8\u56de\u6eda\u4e4b\u540e\u91cd\u65b0\u6279\u51c6")
p7_assert_runtime_evidence_intact(linked_evidence, linked_evidence_sha, "D4 \u4e4b\u540e\u91cd\u65b0\u6279\u51c6")
stopifnot(identical(length(d_final_chain$contract$analyses), 1L))
p7_log("D4 \u65ad\u8a00\u901a\u8fc7\uff1a5 \u4e2a publication target \u9010\u4e2a\u6ce8\u5165\u5931\u8d25\uff0c\u6bcf\u6b21\u90fd fail closed\u3001journal \u5df2\u6e05\u9664\u3001",
       "transaction \u76ee\u5f55\u65e0\u6b8b\u7247\u3001\u78c1\u76d8\u9010\u5b57\u8282\u6062\u590d\u4e3a\u4e0a\u4e00\u5957\u5b8c\u6574\u4ea7\u7269\uff0c\u4e14\u4e4b\u540e\u4ecd\u53ef\u6b63\u5e38\u91cd\u65b0\u6279\u51c6\u3002\n")

# ==============================================================================
# E. 额外 fixture：N>1、mixed planned/linked、single-arm、无 derivation/filter、
#    无 fallback、contract 顺序与文件名顺序不同、目标环境能力不足阻断 linked、
#    移除 TFL 后 obsolete program 清理（且绝不删除 runtime artifacts）。
# ==============================================================================
p7_section("E. \u989d\u5916 fixture（N=2 mixed planned/linked\uff0csingle-arm\uff0c\u65e0 derivation/filter\uff0c\u65e0 fallback）")

mixed_fixture <- p7_build_study("zz_p7_mixed_")
p7_studies <- c(p7_studies, mixed_fixture$study_dir)
mixed_linked <- p7_plan_analysis("MMRM-E2", "T14-E2", mixed_fixture$evidence_id, "linked", mixed_fixture$source_path,
                                 treatment = FALSE, pairwise = FALSE, derivations = FALSE, filters = TRUE, group_count = 1L,
                                 covariance = list(primary = "CS", fallback = as.list("AR1")), df_method = "Satterthwaite")
mixed_planned <- p7_plan_analysis("MMRM-E1", "T14-E1", mixed_fixture$evidence_id, "planned", mixed_fixture$source_path,
                                  treatment = FALSE, pairwise = FALSE, derivations = FALSE, filters = FALSE, group_count = 1L,
                                  covariance = list(primary = "UN", fallback = list()), df_method = "Kenward-Roger")
# contract 顺序（MMRM-E2、MMRM-E1）故意与文件名升序（MMRM-E1.R、MMRM-E2.R）不同。
mixed_plan <- p7_plan(mixed_fixture$study_id, list(mixed_linked, mixed_planned))
p7_publish_plan(mixed_fixture, mixed_plan)
mixed_chain <- p7_run_chain(mixed_fixture, "E mixed study \u9996\u6b21\u6279\u51c6\u53d1\u5e03（N=2）")
mixed_contract <- mixed_chain$contract
mixed_order <- vapply(mixed_contract$analyses, function(x) as.character(x$analysis_id), character(1))
mixed_filenames <- sort(vapply(mixed_contract$analyses, function(x) analysis_generation_program_basename(x$analysis_id, "r"), character(1)))
mixed_linked_r <- p7_read_program(analysis_generation_program_path(mixed_fixture$study_dir, "MMRM-E2", "r"))
mixed_planned_r <- p7_read_program(analysis_generation_program_path(mixed_fixture$study_dir, "MMRM-E1", "r"))
stopifnot(
  identical(mixed_order, c("MMRM-E2", "MMRM-E1")),
  identical(mixed_filenames, c("MMRM-E1.R", "MMRM-E2.R")),
  !identical(paste0(mixed_order, ".R"), mixed_filenames),
  identical(vapply(mixed_contract$analyses, function(x) as.character(x$dataset$binding_mode), character(1)), c("linked", "planned")),
  # single-arm：没有 treatment 相关 marker，也没有 pairwise 对比代码
  !grepl("PROGRAM-MARKER:TREATMENT_REFERENCE", mixed_linked_r, fixed = TRUE),
  !grepl("PROGRAM-MARKER:ESTIMAND:pairwise_differences", mixed_linked_r, fixed = TRUE),
  !grepl("emmeans::contrast(", mixed_linked_r, fixed = TRUE),
  # 无 derivation；linked 侧保留 filter，planned 侧连 filter 也没有
  !grepl("PROGRAM-MARKER:DERIVATION:", mixed_linked_r, fixed = TRUE),
  !grepl("PROGRAM-MARKER:DERIVATION:", mixed_planned_r, fixed = TRUE),
  program_count_marker(mixed_linked_r, program_marker("FILTER", "1")) == 1L,
  !grepl("PROGRAM-MARKER:FILTER:", mixed_planned_r, fixed = TRUE),
  # 无 fallback：covariance 序列只有一个元素
  grepl("COVARIANCE_ORDER <- c(\"UN\")", mixed_planned_r, fixed = TRUE),
  grepl("COVARIANCE_ORDER <- c(\"CS\", \"AR1\")", mixed_linked_r, fixed = TRUE)
)
p7_log("E \u9759\u6001\u65ad\u8a00\u901a\u8fc7\uff1acontract \u9876\u5e8f=", paste(mixed_order, collapse = ", "), "\uff1b\u6587\u4ef6\u540d\u5347\u5e8f=",
       paste(mixed_filenames, collapse = ", "), "\uff08\u4e24\u8005\u4e0d\u540c\uff09\uff1bsingle-arm / \u65e0 derivation / \u65e0 filter / \u65e0 fallback \u5206\u652f\u5747\u5df2\u8986\u76d6\u3002\n")

# 目标环境能力声明不足：linked 整套发布阻断，磁盘无新产物（planned 不受影响的语义由
# check_self_contained_sas_generation.R 覆盖）。
mixed_snapshot <- p7_snapshot(mixed_fixture$study_dir)
p7_capability_override("begin")
p7_expect_error(approve_and_generate_analysis(mixed_fixture$study_dir, project_dir, "Synthetic Reviewer"),
                "PROGRAM-SAS-CONFORMANCE-SHA256-UNSUPPORTED")
p7_capability_override("end")
p7_assert_no_transaction_residue(mixed_fixture$study_dir)
p7_assert_snapshot(mixed_fixture$study_dir, mixed_snapshot, "E \u76ee\u6807\u73af\u5883\u7f3a\u5c11 fcmp/bit_operations/sha256 \u65f6 linked \u53d1\u5e03\u963b\u65ad")
p7_log("E \u65ad\u8a00\u901a\u8fc7\uff1alinked SAS \u5728\u80fd\u529b\u58f0\u660e\u4e0d\u8db3\u7684 profile \u4e0a\u5fc5\u987b\u963b\u65ad\uff0c\u4e0d\u80fd\u88ab\u9759\u6001 golden \u5192\u5145\u4e3a qualified\u3002\n")

if (!p7_can_execute) {
  p7_log("E \u7684 collector \u6267\u884c\u7c7b\u65ad\u8a00\u672a\u8fd0\u884c\uff08\u539f\u56e0\u5df2\u5728\u4e0a\u65b9\u6253\u5370\uff09\uff1b\u4e0d\u5f97\u89c6\u4e3a\u5df2\u901a\u8fc7\u3002\n")
  mixed_runtime <- character()
} else {
  e_collector <- analysis_generated_collector_target(mixed_fixture$study_dir)
  e_fake_bin <- file.path(mixed_fixture$study_dir, "backup-trace", "fake-bin")
  dir.create(e_fake_bin, recursive = TRUE, showWarnings = FALSE)
  e_sentinel <- file.path(mixed_fixture$study_dir, "backup-trace", "sas-was-invoked.txt")
  for (fake in c("sas.bat", "sas.cmd", "sas9.bat")) {
    writeLines(c("@echo off", paste0("echo invoked > \"", gsub("/", "\\\\", e_sentinel), "\"")), file.path(e_fake_bin, fake), useBytes = TRUE)
  }
  e_log <- file.path(mixed_fixture$study_dir, "backup-trace", "collector-subprocess.log")
  e_old_path <- Sys.getenv("PATH")
  Sys.setenv(PATH = paste(e_fake_bin, e_old_path, sep = .Platform$path.sep))
  e_status <- suppressWarnings(system2(p7_rscript_path, c("--vanilla", shQuote(e_collector)), stdout = e_log, stderr = e_log))
  Sys.setenv(PATH = e_old_path)
  if (!identical(as.integer(e_status), 0L)) {
    p7_log("E collector \u5b50\u8fdb\u7a0b\u5931\u8d25\uff0c\u65e5\u5fd7\uff1a\n", p7_log_text(e_log), "\n")
    stop("P7-E-COLLECTOR: mixed study \u7684 collector \u5fc5\u987b\u4ee5\u9000\u51fa\u7801 0 \u7ed3\u675f\u3002")
  }
  stopifnot(!file.exists(e_sentinel))
  e_manifest <- read_utf8_bom_csv(file.path(mixed_fixture$study_dir, "output", "tfl-output-manifest.csv"))
  e_manifest[] <- lapply(e_manifest, function(column) { value <- as.character(column); value[is.na(value)] <- ""; value })
  standard_validate_collector_manifest(e_manifest, mixed_contract)
  e_row <- function(id, language) e_manifest[e_manifest$analysis_id == id & e_manifest$programming_language == language, , drop = FALSE]
  e_linked_analysis <- standard_contract_get_analysis(mixed_contract, "MMRM-E2")
  e_linked_output <- file.path(mixed_fixture$study_dir, "output", "analyses", standard_contract_safe_identity("MMRM-E2"))
  stopifnot(
    identical(nrow(e_manifest), 4L),
    identical(unique(e_manifest$analysis_id), c("MMRM-E1", "MMRM-E2")),
    identical(e_row("MMRM-E1", "R")$execution_status[[1L]], "code_generation_only"),
    identical(e_row("MMRM-E1", "SAS")$execution_status[[1L]], "code_generation_only"),
    all(!nzchar(unlist(e_row("MMRM-E1", "R")[standard_collector_result_path_columns()], use.names = FALSE))),
    all(!nzchar(unlist(e_row("MMRM-E1", "SAS")[standard_collector_result_path_columns()], use.names = FALSE))),
    identical(e_row("MMRM-E2", "R")$execution_status[[1L]], "executed"),
    identical(basename(e_row("MMRM-E2", "R")$final_tfl_file[[1L]]), as.character(e_linked_analysis$output$r_final_file)),
    # collector 从不执行 SAS：linked analysis 的 SAS 行只能是 program_generated_not_executed
    identical(e_row("MMRM-E2", "SAS")$execution_status[[1L]], "program_generated_not_executed"),
    all(!nzchar(unlist(e_row("MMRM-E2", "SAS")[standard_collector_result_path_columns()], use.names = FALSE))),
    setequal(list.files(e_linked_output), unname(unlist(e_linked_analysis$output[c("r_raw_file", "r_final_file", "r_diagnostic_file", "r_run_record_file")], use.names = FALSE))),
    length(list.files(file.path(mixed_fixture$study_dir, "output", "analyses", standard_contract_safe_identity("MMRM-E1")), recursive = TRUE, all.files = TRUE, no.. = TRUE)) == 0L
  )
  e_run_log <- readLines(file.path(mixed_fixture$study_dir, "output", "logs", "run_all_mmrm.log"), warn = FALSE, encoding = "UTF-8")
  e_invoked <- grep("invoke Rscript", e_run_log, fixed = TRUE, value = TRUE)
  stopifnot(length(e_invoked) == 1L, grepl("MMRM-E2.R", e_invoked[[1L]], fixed = TRUE),
            any(grepl("binding_mode=planned", e_run_log, fixed = TRUE)))
  mixed_runtime <- list.files(e_linked_output, full.names = TRUE)
  p7_log("E \u6267\u884c\u7c7b\u65ad\u8a00\u5df2\u5b9e\u9645\u8fd0\u884c\uff1amixed study \u7684 collector \u9010 analysis \u5904\u7406\uff1aplanned \u4ec5\u767b\u8bb0 ",
         "code_generation_only \u4e14\u4ece\u672a\u542f\u52a8 R\uff1blinked \u7684 R \u884c executed\u3001SAS \u884c program_generated_not_executed\uff1b",
         "\u5168\u7a0b\u672a\u89e6\u53d1\u4efb\u4f55 sas \u53ef\u6267\u884c\u6587\u4ef6\u3002\n")
}

# 移除 linked TFL：obsolete program 必须被事务删除，runtime artifacts 必须原样保留。
mixed_runtime_sha <- if (length(mixed_runtime)) vapply(mixed_runtime, file_sha256, character(1), USE.NAMES = FALSE) else character()
mixed_removed_r <- analysis_generation_program_path(mixed_fixture$study_dir, "MMRM-E2", "r")
mixed_removed_sas <- analysis_generation_program_path(mixed_fixture$study_dir, "MMRM-E2", "sas")
stopifnot(all(file.exists(c(mixed_removed_r, mixed_removed_sas))))
reduced_plan <- p7_plan(mixed_fixture$study_id, list(mixed_planned))
p7_publish_plan(mixed_fixture, reduced_plan)
reduced_snapshot <- p7_snapshot(mixed_fixture$study_dir)
# 写集全部落盘后第一个删除失败 → 整体回滚到上一套完整产物。
p7_expect_error(approve_and_generate_analysis(mixed_fixture$study_dir, project_dir, "Synthetic Reviewer", fail_after = 1L + 3L),
                "Injected target publication failure")
p7_assert_no_transaction_residue(mixed_fixture$study_dir)
p7_assert_snapshot(mixed_fixture$study_dir, reduced_snapshot, "E obsolete deletion \u5931\u8d25\u56de\u6eda")
reduced_chain <- p7_run_chain(mixed_fixture, "E \u79fb\u9664 linked analysis \u540e\u91cd\u65b0\u6279\u51c6")
stopifnot(
  identical(length(reduced_chain$contract$analyses), 1L),
  !file.exists(mixed_removed_r), !file.exists(mixed_removed_sas),
  length(mixed_runtime) == 0L || all(file.exists(mixed_runtime)),
  length(mixed_runtime) == 0L || identical(vapply(mixed_runtime, file_sha256, character(1), USE.NAMES = FALSE), mixed_runtime_sha)
)
p7_log("E \u65ad\u8a00\u901a\u8fc7\uff1a\u88ab\u79fb\u9664 TFL \u7684 .R/.sas \u5df2\u88ab\u4e8b\u52a1\u5220\u9664\uff0c\u800c\u5b83\u7684 runtime artifacts\uff08raw/final/",
       "diagnostic/run-record\uff09\u9010\u5b57\u8282\u4fdd\u7559\uff0c\u672a\u88ab approval publisher \u89e6\u78b0\u3002\n")

# ==============================================================================
# 收尾
# ==============================================================================
p7_section("\u6536\u5c3e\uff1a\u6e05\u7406\u4e34\u65f6 study \u4e0e\u4e2d\u95f4\u4ea7\u7269")
p7_cleanup()
stopifnot(!any(dir.exists(p7_studies)), !dir.exists(p7_temp_root))
p7_log("\u5df2\u5220\u9664\u672c\u811a\u672c\u81ea\u5df1\u521b\u5efa\u7684\u5168\u90e8\u4e34\u65f6 study \u4e0e\u4e2d\u95f4\u4ea7\u7269\uff1a", paste(basename(p7_studies), collapse = ", "), "\n")

p7_log("\nSelf-contained program generation end-to-end (Phase 7) fixtures passed: ",
       "A linked\uff08\u771f\u5b9e\u6267\u884c ", if (p7_can_execute) "\u5df2\u8fd0\u884c" else "\u5df2\u8df3\u8fc7", "\uff09\u3001B planned\u3001",
       "C unsupported adapter\u3001D tampered-input/transaction \u56db\u7c7b\u4e3b fixture \u5168\u90e8\u901a\u8fc7\uff1b",
       "\u6bcf\u4e2a study \u4e25\u683c N \u4e2a .R + N \u4e2a .sas + run_all_mmrm.R\u3001\u65e0 *_template.sas\u3001",
       "\u751f\u6210\u7a0b\u5e8f\u6587\u672c\u4e0d\u542b .codex/source(/%include/TODO/TBD/\u672a\u66ff\u6362\u5360\u4f4d\u7b26\u3002\n")
p7_log("*** \u8bf4\u660e\uff1a\u672c\u68c0\u67e5\u4ece\u4e0d\u6267\u884c SAS\u3002SAS \u53ea\u4f5c\u4e3a\u4ee3\u7801\u4ea4\u4ed8\u7269\u53d1\u5e03\uff0cSAS \u4fa7\u53ea\u5b8c\u6210\u9759\u6001 / conformance / ",
       "identity \u7be1\u6539\u62d2\u7ecd\u9a8c\u8bc1\uff1b\u5185\u8054 SHA-256\u3001QC hard abort\u3001covariance fallback \u4e0e UTF-8 BOM \u5bfc\u51fa\u7684\u8fd0\u884c\u884c\u4e3a",
       "\u9700\u7531\u7edf\u8ba1\u5e08\u5728\u6279\u51c6\u7684\u76ee\u6807\u73af\u5883\u4e2d\u786e\u8ba4\uff0c\u672c\u4ed3\u5e93\u672a\u505a compile-and-run\u3002***\n")
if (!p7_can_execute) {
  p7_log("*** \u672c\u6b21\u8fd0\u884c\u672a\u5305\u542b\u4efb\u4f55 R \u6267\u884c\u7c7b\u65ad\u8a00\uff08\u7f3a\u5305\u6216\u65e0 Rscript\uff09\uff0c\u4e0d\u5f97\u89c6\u4e3a A \u7c7b\u771f\u5b9e\u6267\u884c\u5df2\u901a\u8fc7\u3002***\n")
}
