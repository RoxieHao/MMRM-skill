options(encoding = "UTF-8")

# ==============================================================================
# Phase 5 自检：approval transaction 与自包含 program 文件清理（implementation plan 8.1–8.4）
#
# 语义前提（design 15.6/15.7，已批准）：
#   * 本流水线从不执行 SAS。SAS 只作为代码交付物生成，由统计师自行在批准的目标环境运行。
#     因此不存在“生成器必须先在 SAS 上跑通才允许生成”的 qualification 闸门；
#     唯一生成闸门是目标环境能力声明（fcmp/bit_operations/sha256 为 FALSE 时阻断 linked）。
#   * 一次 publication transaction 同时提交完整 program write-set 与 obsolete-program delete-set；
#     任一渲染 / 校验 / 写入 / 删除失败都必须恢复上一套完整产物，且绝不留下半套单语言产物。
#   * approval publisher 只删除 generator 拥有的 R/SAS program；raw/final/diagnostic/run-record/
#     manifest 等运行证据永不进入 delete-set。
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
source(file.path(project_dir, ".codex", "study-mmrm-analysis", "scripts", "check_analysis_plan.R"), encoding = "UTF-8")
if (!requireNamespace("digest", quietly = TRUE) || !requireNamespace("yaml", quietly = TRUE)) stop("digest and yaml are required")

p5_log <- function(...) { cat(paste0(c(...), collapse = "")); flush(stdout()); invisible(NULL) }
p5_section <- function(title) p5_log("\n== ", title, " ==\n")

p5_expect_error <- function(expression, fragment = NULL) {
  error <- try(force(expression), silent = TRUE)
  stopifnot(inherits(error, "try-error"))
  if (!is.null(fragment)) stopifnot(grepl(fragment, as.character(error), fixed = TRUE))
  invisible(trimws(as.character(error)))
}

# 进程级 override：把 globalenv 中的某个生成函数临时替换成注入失败的版本，
# 表达式求值结束后（无论成功或抛错）一定恢复原函数。
p5_with_override <- function(name, replacement, expression) {
  original <- get(name, envir = globalenv())
  assign(name, replacement, envir = globalenv())
  on.exit({ assign(name, original, envir = globalenv()); stopifnot(identical(get(name, envir = globalenv()), original)) }, add = TRUE)
  force(expression)
}

p5_norm <- function(path) gsub("\\\\", "/", path)

# 生成文本与磁盘文件的可比形式：统一换行并去掉行分隔造成的尾随空行，
# 使“内存渲染文本”与“publisher 落盘后再读回的文本”可以逐字符比较。
p5_canonical_text <- function(text) paste(strsplit(gsub("\r\n", "\n", as.character(text), fixed = TRUE), "\n", fixed = TRUE)[[1L]], collapse = "\n")

# 从磁盘按 UTF-8 读回生成程序文本，用于对磁盘产物（而不是内存文本）跑 conformance。
p5_read_program <- function(path) {
  raw <- readBin(path, what = "raw", n = file.size(path))
  p5_canonical_text(iconv(rawToChar(raw), from = "UTF-8", to = "UTF-8"))
}

# 磁盘快照：analysis/（程序）、statistician-review/（review+contract）、output/（运行证据）、
# backup-trace/（journal 与 staging 残留）全部按 SHA-256 记录。事务失败后必须逐字节相同。
p5_snapshot <- function(study_dir) {
  root <- normalizePath(study_dir, winslash = "/", mustWork = TRUE)
  files <- list.files(root, recursive = TRUE, all.files = TRUE, full.names = TRUE, no.. = TRUE, include.dirs = FALSE)
  files <- sort(p5_norm(files))
  if (!length(files)) return(setNames(character(), character()))
  setNames(vapply(files, file_sha256, character(1), USE.NAMES = FALSE), substring(files, nchar(root) + 2L))
}
p5_assert_snapshot <- function(study_dir, expected, label) {
  actual <- p5_snapshot(study_dir)
  if (!identical(actual, expected)) {
    added <- setdiff(names(actual), names(expected)); removed <- setdiff(names(expected), names(actual))
    common <- intersect(names(actual), names(expected)); changed <- common[actual[common] != expected[common]]
    stop("P5-ROLLBACK-INCOMPLETE: ", label, "；新增=", paste(added, collapse = ","),
         "；丢失=", paste(removed, collapse = ","), "；被改写=", paste(changed, collapse = ","))
  }
  p5_log("回滚断言通过（磁盘逐字节恢复为上一套完整产物）：", label, "\n")
  invisible(TRUE)
}

# 事务卫生：journal 必须已删除，transaction 目录不得留下 stage/backup 残片。
p5_assert_no_transaction_residue <- function(study_dir) {
  journal <- analysis_approval_journal_path(study_dir)
  txn_dir <- analysis_approval_transaction_dir(study_dir)
  residue <- if (dir.exists(txn_dir)) list.files(txn_dir, all.files = TRUE, no.. = TRUE) else character()
  stopifnot(!file.exists(journal), length(residue) == 0L)
  invisible(TRUE)
}

p5_program_paths <- function(study_dir, contract) {
  ids <- vapply(contract$analyses, function(x) as.character(x$analysis_id), character(1))
  list(r = vapply(ids, function(id) analysis_generation_program_path(study_dir, id, "r"), character(1), USE.NAMES = FALSE),
       sas = vapply(ids, function(id) analysis_generation_program_path(study_dir, id, "sas"), character(1), USE.NAMES = FALSE),
       collector = analysis_generated_collector_target(study_dir))
}

# 5) fixture 必须故意让 contract analysis 顺序与规范化程序文件名排序不同。
p5_assert_contract_order_differs_from_filename_order <- function(contract) {
  basenames <- vapply(contract$analyses, function(x) analysis_generation_program_basename(x$analysis_id, "r"), character(1))
  if (length(basenames) < 2L) { p5_log("单 analysis contract：跳过顺序断言（多 analysis fixture 已单独断言）\n"); return(invisible(TRUE)) }
  stopifnot(!identical(basenames, sort(basenames)))
  p5_log("fixture 断言通过：contract analysis 顺序（", paste(basenames, collapse = ", "),
         "）与文件名升序（", paste(sort(basenames), collapse = ", "), "）不同\n")
  invisible(TRUE)
}

# 1) 正常发布断言：完整 N 个 .R + N 个 .sas + collector；没有 _template.sas；
#    每个磁盘程序都通过 validate_generated_*_program 与 validate_tfl_program_coverage；
#    planned 程序含永久 code-generation-only gate。
p5_assert_full_generation <- function(study_dir, contract, payload_sha, contract_sha, label) {
  targets <- p5_program_paths(study_dir, contract)
  r_dir <- file.path(study_dir, "analysis", "r"); sas_dir <- file.path(study_dir, "analysis", "sas")
  stopifnot(
    all(file.exists(c(targets$r, targets$sas, targets$collector))),
    setequal(list.files(r_dir), c(basename(targets$r), "run_all_mmrm.R")),
    setequal(list.files(sas_dir), basename(targets$sas)),
    length(list.files(sas_dir, pattern = "_template[.]sas$")) == 0L,
    !any(grepl("_template[.]sas$", basename(analysis_generated_targets(study_dir, contract))))
  )
  identities <- analysis_generation_identities(contract, payload_sha, contract_sha)
  texts <- list()
  for (analysis in contract$analyses) {
    ir <- build_program_generation_ir(contract, analysis, identities)
    r_path <- analysis_generation_program_path(study_dir, analysis$analysis_id, "r")
    sas_path <- analysis_generation_program_path(study_dir, analysis$analysis_id, "sas")
    r_text <- p5_read_program(r_path); sas_text <- p5_read_program(sas_path)
    validate_generated_r_program(r_text, ir)
    validate_generated_sas_program(sas_text, ir)
    stopifnot(identical(r_text, p5_canonical_text(render_self_contained_r_program(contract, analysis, identities))),
              identical(sas_text, p5_canonical_text(render_self_contained_sas_program(contract, analysis, identities))))
    if (identical(as.character(analysis$dataset$binding_mode), "planned")) {
      stopifnot(
        grepl(program_marker("GATE", "PLANNED_CODE_GENERATION_ONLY"), r_text, fixed = TRUE),
        grepl("CODE_GENERATION_ONLY <- TRUE", r_text, fixed = TRUE),
        grepl("if (isTRUE(CODE_GENERATION_ONLY)) {", r_text, fixed = TRUE),
        grepl("if (isTRUE(CODE_GENERATION_ONLY)) stop(", r_text, fixed = TRUE),
        grepl(program_marker("GATE", "PLANNED_CODE_GENERATION_ONLY"), sas_text, fixed = TRUE),
        grepl("%let CODE_GENERATION_ONLY=YES;", sas_text, fixed = TRUE),
        grepl("%let RUN_STATUS=code_generation_only;", sas_text, fixed = TRUE)
      )
    } else {
      stopifnot(grepl("CODE_GENERATION_ONLY <- FALSE", r_text, fixed = TRUE),
                grepl("%let CODE_GENERATION_ONLY=NO;", sas_text, fixed = TRUE))
    }
    texts[[r_path]] <- r_text; texts[[sas_path]] <- sas_text
  }
  validate_tfl_program_coverage(contract, texts)
  collector_text <- p5_read_program(targets$collector)
  stopifnot(!grepl("<APPROVAL_PAYLOAD_SHA256>", collector_text, fixed = TRUE),
            !grepl("<CONTRACT_SHA256>", collector_text, fixed = TRUE),
            grepl(toupper(payload_sha), collector_text, fixed = TRUE),
            grepl(toupper(contract_sha), collector_text, fixed = TRUE))
  p5_log("完整发布断言通过：", label, "（", length(contract$analyses), " 个 analysis → ",
         length(targets$r), " 个 .R + ", length(targets$sas), " 个 .sas + run_all_mmrm.R；无 _template.sas）\n")
  invisible(TRUE)
}

# test-only：把目标环境能力声明临时置为缺少 FCMP/位运算/SHA-256。
p5_capability_override <- local({
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

# 运行证据 fixture：raw/final/diagnostic/run-record/manifest。它们必须在任何一次
# approval transaction 之后仍然存在且逐字节不变。
p5_write_runtime_evidence <- function(study_dir, contract) {
  paths <- list(analysis_output_dir = file.path(study_dir, "output", "analyses"))
  manifest <- file.path(study_dir, "output", "tfl-output-manifest.csv")
  dir.create(dirname(manifest), recursive = TRUE, showWarnings = FALSE)
  writeLines("tfl_id,output_status,note", manifest, useBytes = TRUE)
  created <- manifest
  for (analysis in contract$analyses) {
    output_paths <- analysis_output_paths(paths, as.character(analysis$analysis_id))
    for (directory in c(output_paths$root, output_paths$tables, output_paths$diagnostics, output_paths$logs)) dir.create(directory, recursive = TRUE, showWarnings = FALSE)
    files <- c(output_paths$run_record, output_paths$diagnostic_csv, output_paths$diagnostic_report, output_paths$log_file,
               file.path(output_paths$tables, analysis$output$r_raw_file), file.path(output_paths$tables, analysis$output$r_final_file),
               file.path(output_paths$tables, analysis$output$sas_raw_file), file.path(output_paths$tables, analysis$output$sas_final_file))
    for (file_path in files) writeLines(paste0("runtime-evidence:", basename(file_path)), file_path, useBytes = TRUE)
    created <- c(created, files)
  }
  stopifnot(all(file.exists(created)))
  p5_log("已构造运行证据 ", length(created), " 个文件（raw/final/diagnostic/run-record/manifest）\n")
  created
}
p5_assert_runtime_evidence_intact <- function(evidence, expected_sha, label) {
  stopifnot(all(file.exists(evidence)), identical(vapply(evidence, file_sha256, character(1), USE.NAMES = FALSE), expected_sha))
  p5_log("运行证据未被 approval publisher 触碰：", label, "（", length(evidence), " 个文件）\n")
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# A 部分：contract 级 target 集合与 transaction primitive
# ------------------------------------------------------------------------------
p5_section("A. contract 级 target 集合与 transaction primitive")

plan_a <- synthetic_analysis_plan()
second_plan_analysis <- plan_a$analyses[[1L]]
second_plan_analysis$analysis_id <- "MMRM-02"; second_plan_analysis$source_tfl_id <- "T14-02"; second_plan_analysis$title <- "Second synthetic analysis"
# contract 顺序 MMRM-02、MMRM-01；文件名升序为 MMRM-01.R、MMRM-02.R —— 两者故意不同。
plan_a$analyses <- list(second_plan_analysis, plan_a$analyses[[1L]])
approval_a <- list(review_file = "synthetic/statistical-review.md", review_sha256 = paste(rep("A", 64L), collapse = ""),
                   analysis_plan_file = "synthetic/analysis-plan.yaml", analysis_plan_sha256 = analysis_plan_sha256(plan_a),
                   approval_payload_sha256 = paste(rep("B", 64L), collapse = ""), source_evidence_sha256 = paste(rep("C", 64L), collapse = ""),
                   reviewed_by = "Synthetic Reviewer", approved_at_utc = "2026-08-19T00:00:00Z")
contract_a <- compile_analysis_plan_contract(plan_a, approval_a)
assert_plan_contract_parity(plan_a, contract_a)
mismatched_contract <- contract_a; mismatched_contract$study$study_id <- "other-study"
p5_expect_error(assert_plan_contract_parity(plan_a, mismatched_contract), "PLAN-PARITY-MISMATCH")

contract_a_path <- tempfile("contract-", fileext = ".yaml"); on.exit(unlink(contract_a_path, force = TRUE), add = TRUE)
write_standard_mmrm_contract(contract_a, contract_a_path)
contract_a_read <- read_standard_mmrm_contract(contract_a_path)
contract_a_sha <- attr(contract_a_read, "sha256")
p5_assert_contract_order_differs_from_filename_order(contract_a_read)

study_a <- tempfile("zz_p5_contract_", tmpdir = project_dir)
dir.create(file.path(study_a, "analysis", "r"), recursive = TRUE)
dir.create(file.path(study_a, "analysis", "sas"), recursive = TRUE)
dir.create(file.path(study_a, "backup-trace"), recursive = TRUE)
on.exit(unlink(study_a, recursive = TRUE, force = TRUE), add = TRUE)
journal_a <- analysis_approval_journal_path(study_a)

targets_a <- analysis_generated_targets(study_a, contract_a_read)
stopifnot(length(targets_a) == 5L, !any(grepl("_template[.]sas$", targets_a)),
          setequal(p5_norm(targets_a), p5_norm(c(p5_program_paths(study_a, contract_a_read)$r, p5_program_paths(study_a, contract_a_read)$sas, analysis_generated_collector_target(study_a)))))
p5_log("8.2 target 集合：2 个 .R + 2 个 .sas + run_all_mmrm.R，且不含 _template.sas\n")

rendered_a <- analysis_render_generated(study_a, project_dir, contract_a_read, approval_a$approval_payload_sha256, contract_a_sha)
stopifnot(length(rendered_a) == 5L, setequal(p5_norm(names(rendered_a)), p5_norm(targets_a)),
          all(!vapply(rendered_a, function(x) grepl("<APPROVAL_PAYLOAD_SHA256>|<CONTRACT_SHA256>|specification_sha256", paste(x, collapse = "\n")), logical(1))))
analysis_transaction_publish(rendered_a, journal_a)
p5_assert_no_transaction_residue(study_a)
p5_assert_full_generation(study_a, contract_a_read, approval_a$approval_payload_sha256, contract_a_sha, "contract 级首次发布")

# 审批链不得再发布 template：任何 <analysis_id>_template.sas 目标都被 publisher 拒绝。
p5_expect_error(analysis_transaction_publish(setNames(list("x"), file.path(study_a, "analysis", "sas", "MMRM-01_template.sas")), journal_a),
                "publishing <analysis_id>_template.sas is disabled")
p5_assert_no_transaction_residue(study_a)

evidence_a <- p5_write_runtime_evidence(study_a, contract_a_read)
evidence_a_sha <- vapply(evidence_a, file_sha256, character(1), USE.NAMES = FALSE)

# 运行证据永远不能进入 delete-set。
p5_expect_error(analysis_transaction_publish(rendered_a, journal_a, delete_targets = evidence_a[[1L]]),
                "may only delete generator-owned programs")
p5_assert_runtime_evidence_intact(evidence_a, evidence_a_sha, "delete-set 越界被拒绝后")
p5_expect_error(analysis_assert_generator_owned_programs(evidence_a, study_a, "delete target"), "may only delete generator-owned programs")

# 旧正式 renderer 遗留的 _template.sas（含已移除 analysis 的）必须进入 obsolete delete-set。
legacy_templates <- file.path(study_a, "analysis", "sas", c("MMRM-01_template.sas", "MMRM-02_template.sas", "MMRM-99_template.sas"))
for (path in legacy_templates) writeLines("legacy template", path, useBytes = TRUE)
obsolete_a <- analysis_obsolete_generated_targets(study_a, contract_a_read, rendered_a)
stopifnot(setequal(p5_norm(obsolete_a), p5_norm(legacy_templates)))
snapshot_a <- p5_snapshot(study_a)

# 6) obsolete deletion 回滚：写集全部落盘后第一个删除失败，必须整体恢复。
p5_expect_error(analysis_transaction_publish(rendered_a, journal_a, fail_after = length(rendered_a), delete_targets = obsolete_a),
                "Injected target publication failure")
p5_assert_no_transaction_residue(study_a)
p5_assert_snapshot(study_a, snapshot_a, "obsolete deletion 回滚（contract 级）")
p5_assert_runtime_evidence_intact(evidence_a, evidence_a_sha, "obsolete deletion 回滚后")

analysis_transaction_publish(rendered_a, journal_a, delete_targets = obsolete_a)
stopifnot(all(!file.exists(legacy_templates)))
p5_assert_no_transaction_residue(study_a)
p5_assert_full_generation(study_a, contract_a_read, approval_a$approval_payload_sha256, contract_a_sha, "template 删除后仍是完整产物")
p5_assert_runtime_evidence_intact(evidence_a, evidence_a_sha, "template 事务删除后")

# 已移除 analysis 的 .R/.sas/_template.sas 必须进入 delete-set。
single_plan <- plan_a; single_plan$analyses <- list(plan_a$analyses[[1L]])
single_contract <- compile_analysis_plan_contract(single_plan, approval_a)
single_path <- tempfile("contract-single-", fileext = ".yaml"); on.exit(unlink(single_path, force = TRUE), add = TRUE)
write_standard_mmrm_contract(single_contract, single_path); single_contract_read <- read_standard_mmrm_contract(single_path)
removed_template <- file.path(study_a, "analysis", "sas", "MMRM-01_template.sas"); writeLines("legacy template", removed_template, useBytes = TRUE)
rendered_single <- analysis_render_generated(study_a, project_dir, single_contract_read, approval_a$approval_payload_sha256, attr(single_contract_read, "sha256"))
obsolete_single <- analysis_obsolete_generated_targets(study_a, contract_a_read, rendered_single)
stopifnot(setequal(p5_norm(obsolete_single), p5_norm(c(file.path(study_a, "analysis", "r", "MMRM-01.R"), file.path(study_a, "analysis", "sas", "MMRM-01.sas"), removed_template))))
snapshot_a <- p5_snapshot(study_a)
p5_expect_error(analysis_transaction_publish(rendered_single, journal_a, fail_after = 0L, delete_targets = obsolete_single), "Injected target publication failure")
p5_assert_no_transaction_residue(study_a)
p5_assert_snapshot(study_a, snapshot_a, "已移除 analysis 删除失败回滚（contract 级）")
analysis_transaction_publish(rendered_single, journal_a, delete_targets = obsolete_single)
stopifnot(all(!file.exists(obsolete_single)))
p5_assert_full_generation(study_a, single_contract_read, approval_a$approval_payload_sha256, attr(single_contract_read, "sha256"), "移除 analysis 后仍是完整产物")
p5_assert_runtime_evidence_intact(evidence_a, evidence_a_sha, "移除 analysis 之后")

# 4) 目标环境能力不足：linked 整套发布阻断，磁盘无新产物。
snapshot_a <- p5_snapshot(study_a)
p5_capability_override("begin")
p5_expect_error(analysis_render_generated(study_a, project_dir, contract_a_read, approval_a$approval_payload_sha256, contract_a_sha),
                "PROGRAM-SAS-CONFORMANCE-SHA256-UNSUPPORTED")
p5_capability_override("end")
p5_assert_snapshot(study_a, snapshot_a, "能力声明不足时 linked 生成阻断（contract 级）")

# 7) unsupported adapter：第一个 analysis 的 R 已在内存渲染成功也不得留下 R-only 文件。
adapter_plan <- plan_a
adapter_plan$analyses[[2L]]$adapter <- list(file = "studies/synthetic/analysis/r/adapter.R", sha256 = paste(rep("9", 64L), collapse = ""))
adapter_plan$analyses[[2L]]$trace$adapter <- list("DEC-11")
adapter_contract <- compile_analysis_plan_contract(adapter_plan, list(review_file = approval_a$review_file, review_sha256 = approval_a$review_sha256,
  analysis_plan_file = approval_a$analysis_plan_file, analysis_plan_sha256 = analysis_plan_sha256(adapter_plan),
  approval_payload_sha256 = approval_a$approval_payload_sha256, source_evidence_sha256 = approval_a$source_evidence_sha256,
  reviewed_by = approval_a$reviewed_by, approved_at_utc = approval_a$approved_at_utc))
p5_expect_error(analysis_render_generated(study_a, project_dir, adapter_contract, approval_a$approval_payload_sha256, contract_a_sha),
                "PROGRAM-INLINE-ADAPTER-UNSUPPORTED:MMRM-01")
p5_assert_snapshot(study_a, snapshot_a, "unsupported adapter 不留下 R-only 文件（contract 级）")

generator <- paste(readLines(file.path(project_dir, ".codex", "study-mmrm-analysis", "scripts", "generate_standard_study.R"), warn = FALSE), collapse = "\n")
stopifnot(grepl("approve_and_generate_analysis.R", generator, fixed = TRUE), !grepl("analysis_transaction_publish", generator, fixed = TRUE))
p5_log("单一 publisher 断言通过：generate_standard_study.R 只调用批准入口，不自行发布\n")

# ------------------------------------------------------------------------------
# B/C 部分：生产入口 approve_and_generate_analysis 的完整链路
# ------------------------------------------------------------------------------
p5_analysis_plan_analysis <- function(analysis_id, tfl_id, title, binding_mode, source_path, project_dir, evidence_id, adapter = NULL) {
  dimensions <- list(instrument = list(variable = "not_applicable", values = character()), version = list(variable = "not_applicable", values = character()),
                     reporter = list(variable = "not_applicable", values = character()), subscale = list(variable = "not_applicable", values = character()))
  trace <- setNames(rep(list(list()), length(analysis_plan_trace_keys())), analysis_plan_trace_keys())
  for (name in c("dataset", "mappings", "groups", "endpoint_definitions", "fixed_effects", "reml", "covariance", "df_method", "estimands")) trace[[name]] <- list(evidence_id)
  if (!is.null(adapter)) trace$adapter <- list(evidence_id)
  dataset <- if (identical(binding_mode, "linked")) {
    list(binding_mode = "linked", file = "scores.csv", format = "csv", relative_path = project_relative_path(source_path, project_dir), sha256 = file_sha256(source_path))
  } else list(binding_mode = "planned", file = "scores.csv", format = "csv", relative_path = NULL, sha256 = NULL)
  list(analysis_id = analysis_id, source_tfl_id = tfl_id, title = title, dataset = dataset, adapter = adapter,
       mappings = list(subject = "PERSON_ID", response = "DELTA_SCORE", baseline = "START_SCORE", visit = "TIME_INDEX"),
       derivations = list(), filters = list(),
       groups = list(list(id = "TOTAL", label = "Total", predicates = list(list(variable = "PARAMCD", operator = "eq", value = "SCORE_A")))),
       endpoint_definitions = list(list(group_id = "TOTAL", endpoint_variable = "PARAMCD", selected_codes = "SCORE_A", selection_mode = "single_code",
                                        dimensions = dimensions, row_allocation_rule = "one_row_per_subject_endpoint_visit")),
       fixed_effects = as.list(c("visit", "baseline", "baseline_by_visit")), reml = TRUE,
       covariance = list(primary = "UN", fallback = as.list(c("AR1", "CS"))), df_method = "Kenward-Roger",
       estimands = list(visit_lsmeans = TRUE, treatment_visit_lsmeans = FALSE, pairwise_differences = FALSE), treatment = NULL, trace = trace)
}

# 建立一个可以走完 finalize → approve 全链路的合成 study。
p5_build_study <- function(prefix, binding_mode) {
  study_dir <- tempfile(prefix, tmpdir = project_dir)
  for (directory in c("input", "backup-trace", "statistician-review")) dir.create(file.path(study_dir, directory), recursive = TRUE)
  source_path <- file.path(study_dir, "input", "scores.csv")
  write_utf8_bom_csv(data.frame(PERSON_ID = "P1", DELTA_SCORE = 1, START_SCORE = 0, TIME_INDEX = 1, PARAMCD = "SCORE_A", stringsAsFactors = FALSE), source_path)
  manifest <- data.frame(source_id = "SRC-DATA-01", input_type = "analysis_dataset", file_name = "scores.csv", relative_path = "input/scores.csv",
                         version = "1", file_size_bytes = file.info(source_path)$size, modified_at = "2026-08-19T00:00:00Z",
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
  list(study_dir = study_dir, review_path = review_path, source_path = source_path, evidence_id = evidence_id,
       study_id = study_id, binding_mode = binding_mode)
}

# contract 顺序（MMRM-20、MMRM-03）与文件名升序（MMRM-03.R、MMRM-20.R）故意不同。
p5_study_plan <- function(fixture, ids = list(c("MMRM-20", "T14-20"), c("MMRM-03", "T14-03")), adapter_index = NULL, adapter = NULL) {
  linked <- identical(fixture$binding_mode, "linked")
  analyses <- lapply(seq_along(ids), function(i) p5_analysis_plan_analysis(ids[[i]][[1L]], ids[[i]][[2L]], paste0("Synthetic analysis ", ids[[i]][[1L]]),
                                                                          fixture$binding_mode, fixture$source_path, project_dir, fixture$evidence_id,
                                                                          adapter = if (!is.null(adapter_index) && identical(i, adapter_index)) adapter else NULL))
  list(analysis_plan_schema_version = "2.1", study_id = fixture$study_id,
       execution_context = list(profile_version = standard_mmrm_profile_version(),
                                data_availability = if (linked) "available" else "none",
                                data_classification = if (linked) "dummy" else "none",
                                intended_use = if (linked) "technical_validation" else "code_generation",
                                sas_execution_profile = "sas-9.4m5-self-contained/v1"),
       analyses = analyses)
}

p5_publish_plan <- function(fixture, plan) {
  analysis_plan_write(plan, analysis_plan_candidate_path(fixture$study_dir))
  lines <- statistical_review_set_metadata(readLines(fixture$review_path, encoding = "UTF-8", warn = FALSE), "review_status", "ready_for_compilation")
  writeLines(lines, fixture$review_path, useBytes = TRUE)
  result <- finalize_statistical_review(fixture$study_dir, fixture$review_path, fixture$review_path, "Synthetic Reviewer", allow_unresolved = TRUE)
  if (!isTRUE(result$published) || !isTRUE(result$approved)) stop("P5-FIXTURE: finalization failed: ", paste(result$issues$observed, collapse = " | "))
  stopifnot(identical(result$analysis_count, length(plan$analyses)))
  invisible(result)
}

p5_run_full_chain <- function(fixture, label) {
  chain <- approve_and_generate_analysis(fixture$study_dir, project_dir, "Synthetic Reviewer")
  stopifnot(identical(as.character(chain$review$metadata$review_status), "approved"), file.exists(analysis_contract_path(fixture$study_dir)))
  p5_assert_no_transaction_residue(fixture$study_dir)
  p5_assert_contract_order_differs_from_filename_order(chain$contract)
  p5_assert_full_generation(fixture$study_dir, chain$contract, chain$approval_payload_sha256, chain$contract_sha256, label)
  chain
}

p5_section("B. 生产入口全链路（linked study，N=2）")
linked_fixture <- p5_build_study("zz_p5_linked_", "linked")
on.exit(unlink(linked_fixture$study_dir, recursive = TRUE, force = TRUE), add = TRUE)
linked_plan <- p5_study_plan(linked_fixture)
p5_publish_plan(linked_fixture, linked_plan)
linked_chain <- p5_run_full_chain(linked_fixture, "linked study 首次批准发布")

linked_evidence <- p5_write_runtime_evidence(linked_fixture$study_dir, linked_chain$contract)
linked_evidence_sha <- vapply(linked_evidence, file_sha256, character(1), USE.NAMES = FALSE)
baseline_snapshot <- p5_snapshot(linked_fixture$study_dir)

real_render_r <- render_self_contained_r_program
real_render_sas <- render_self_contained_sas_program
real_generate_texts <- analysis_generate_program_texts
first_analysis_id <- as.character(linked_chain$contract$analyses[[1L]]$analysis_id)
second_analysis_id <- as.character(linked_chain$contract$analyses[[2L]]$analysis_id)

p5_transaction_case <- function(label, fragment, expression) {
  p5_log("\n-- 8.4 事务用例：", label, " --\n")
  message_text <- p5_expect_error(expression, fragment)
  p5_log("失败注入生效：", strsplit(message_text, "\n", fixed = TRUE)[[1L]][[1L]], "\n")
  p5_assert_no_transaction_residue(linked_fixture$study_dir)
  p5_assert_snapshot(linked_fixture$study_dir, baseline_snapshot, label)
  p5_assert_runtime_evidence_intact(linked_evidence, linked_evidence_sha, label)
  invisible(TRUE)
}

# 8.4-1 第一个 renderer 失败。
p5_transaction_case("第一个 renderer 失败", "P5-INJECTED-R-RENDERER-FAILURE",
  p5_with_override("render_self_contained_r_program", function(contract, analysis, identities) {
    if (identical(as.character(analysis$analysis_id), first_analysis_id)) stop("P5-INJECTED-R-RENDERER-FAILURE:", first_analysis_id)
    real_render_r(contract, analysis, identities)
  }, approve_and_generate_analysis(linked_fixture$study_dir, project_dir, "Synthetic Reviewer")))

# 8.4-2 中间（第二个 analysis 的）SAS renderer 失败。
p5_transaction_case("第二个 analysis 的 SAS renderer 失败", "P5-INJECTED-SAS-RENDERER-FAILURE",
  p5_with_override("render_self_contained_sas_program", function(contract, analysis, identities) {
    if (identical(as.character(analysis$analysis_id), second_analysis_id)) stop("P5-INJECTED-SAS-RENDERER-FAILURE:", second_analysis_id)
    real_render_sas(contract, analysis, identities)
  }, approve_and_generate_analysis(linked_fixture$study_dir, project_dir, "Synthetic Reviewer")))

# 8.4-3 conformance 校验失败：渲染器返回缺少统计 marker 的文本，由真实 validator 阻断。
p5_transaction_case("conformance 校验失败", "PROGRAM-R-CONFORMANCE-",
  p5_with_override("render_self_contained_r_program", function(contract, analysis, identities) {
    text <- real_render_r(contract, analysis, identities)
    if (identical(as.character(analysis$analysis_id), second_analysis_id)) text <- sub(program_marker("REML", "TRUE"), "PROGRAM-MARKER-REMOVED", text, fixed = TRUE)
    text
  }, approve_and_generate_analysis(linked_fixture$study_dir, project_dir, "Synthetic Reviewer")))

# 8.4-4 coverage 缺一个文件：用 analysis_generate_program_texts 的 test_only_drop_targets 丢掉一个 .sas。
p5_transaction_case("coverage 缺一个文件", "PROGRAM-TFL-COVERAGE-FILE-SET",
  p5_with_override("analysis_generate_program_texts", function(study_dir, project_dir, contract, payload_sha, contract_sha, test_only_drop_targets = character()) {
    real_generate_texts(study_dir, project_dir, contract, payload_sha, contract_sha,
                        test_only_drop_targets = analysis_generation_program_path(study_dir, contract$analyses[[2L]]$analysis_id, "sas"))
  }, approve_and_generate_analysis(linked_fixture$study_dir, project_dir, "Synthetic Reviewer")))

# 8.4-5 publication 第 N 个 target 失败（fail_after = N-1，最后一个 target 提交失败）。
publish_target_count <- 1L + length(analysis_generated_targets(linked_fixture$study_dir, linked_chain$contract))
p5_transaction_case(paste0("publication 第 ", publish_target_count, " 个（最后一个）target 失败"), "Injected target publication failure",
  approve_and_generate_analysis(linked_fixture$study_dir, project_dir, "Synthetic Reviewer", fail_after = publish_target_count - 1L))
p5_transaction_case("publication 第 1 个 target 失败", "Injected target publication failure",
  approve_and_generate_analysis(linked_fixture$study_dir, project_dir, "Synthetic Reviewer", fail_after = 0L))

# 8.4-6 目标环境能力不足：整套 linked 发布阻断且磁盘无新产物。
p5_capability_override("begin")
p5_transaction_case("目标环境缺少 fcmp/bit_operations/sha256", "PROGRAM-SAS-CONFORMANCE-SHA256-UNSUPPORTED",
  approve_and_generate_analysis(linked_fixture$study_dir, project_dir, "Synthetic Reviewer"))
p5_capability_override("end")

# 8.4-7 unsupported adapter：不得留下 R-only 文件。
adapter_path <- file.path(linked_fixture$study_dir, "analysis", "adapter-source.R")
writeLines("# synthetic adapter", adapter_path, useBytes = TRUE)
adapter_plan_full <- p5_study_plan(linked_fixture, adapter_index = 2L,
                                   adapter = list(file = project_relative_path(adapter_path, project_dir), sha256 = file_sha256(adapter_path)))
p5_publish_plan(linked_fixture, adapter_plan_full)
adapter_snapshot <- p5_snapshot(linked_fixture$study_dir)
p5_log("\n-- 8.4 事务用例：unsupported adapter 不留下 R-only 文件 --\n")
p5_expect_error(approve_and_generate_analysis(linked_fixture$study_dir, project_dir, "Synthetic Reviewer"), paste0("PROGRAM-INLINE-ADAPTER-UNSUPPORTED:", second_analysis_id))
p5_assert_no_transaction_residue(linked_fixture$study_dir)
p5_assert_snapshot(linked_fixture$study_dir, adapter_snapshot, "unsupported adapter 不留下 R-only 文件")
p5_assert_runtime_evidence_intact(linked_evidence, linked_evidence_sha, "unsupported adapter 阻断后")
unlink(adapter_path, force = TRUE)
p5_publish_plan(linked_fixture, linked_plan)
stopifnot(identical(p5_snapshot(linked_fixture$study_dir)[names(baseline_snapshot)], baseline_snapshot))

p5_section("B2. 重新批准：旧 template 与已移除 analysis 被事务删除，运行证据保留")
legacy_full <- file.path(linked_fixture$study_dir, "analysis", "sas", c(paste0(first_analysis_id, "_template.sas"), paste0(second_analysis_id, "_template.sas"), "MMRM-99_template.sas"))
for (path in legacy_full) writeLines("legacy template", path, useBytes = TRUE)
removed_programs <- c(file.path(linked_fixture$study_dir, "analysis", "r", paste0(second_analysis_id, ".R")),
                      file.path(linked_fixture$study_dir, "analysis", "sas", paste0(second_analysis_id, ".sas")))
stopifnot(all(file.exists(c(legacy_full, removed_programs))))
reduced_plan <- p5_study_plan(linked_fixture, ids = list(c("MMRM-20", "T14-20")))
p5_publish_plan(linked_fixture, reduced_plan)
reapproval_snapshot <- p5_snapshot(linked_fixture$study_dir)
# 写集全部落盘后第一个删除失败 → 整体回滚到上一套完整产物（含旧 review/contract 与两套程序）。
write_target_count <- 1L + 3L
p5_expect_error(approve_and_generate_analysis(linked_fixture$study_dir, project_dir, "Synthetic Reviewer", fail_after = write_target_count),
                "Injected target publication failure")
p5_assert_no_transaction_residue(linked_fixture$study_dir)
p5_assert_snapshot(linked_fixture$study_dir, reapproval_snapshot, "obsolete deletion 回滚（生产入口）")
p5_assert_runtime_evidence_intact(linked_evidence, linked_evidence_sha, "obsolete deletion 回滚（生产入口）")

reduced_chain <- p5_run_full_chain(linked_fixture, "移除一个 analysis 后重新批准")
stopifnot(length(reduced_chain$contract$analyses) == 1L, all(!file.exists(legacy_full)), all(!file.exists(removed_programs)))
p5_assert_runtime_evidence_intact(linked_evidence, linked_evidence_sha, "重新批准并删除 obsolete program 之后")
p5_log("已移除 analysis 的 .R/.sas 与全部 _template.sas 已被事务删除；raw/final/diagnostic/run-record/manifest 全部保留\n")

p5_section("C. 生产入口全链路（planned study，N=2）")
planned_fixture <- p5_build_study("zz_p5_planned_", "planned")
on.exit(unlink(planned_fixture$study_dir, recursive = TRUE, force = TRUE), add = TRUE)
planned_plan <- p5_study_plan(planned_fixture)
p5_publish_plan(planned_fixture, planned_plan)
planned_chain <- p5_run_full_chain(planned_fixture, "planned study 首次批准发布")
stopifnot(all(vapply(planned_chain$contract$analyses, function(x) identical(as.character(x$dataset$binding_mode), "planned"), logical(1))))
p5_expect_error(assert_analysis_execution_allowed(planned_chain, analysis_id = as.character(planned_chain$contract$analyses[[1L]]$analysis_id)),
                "planned analysis is code-generation-only")
p5_log("planned study 断言通过：完整 2 个 .R + 2 个 .sas + collector，且永久 code-generation-only gate 存在\n")

# ------------------------------------------------------------------------------
# D 部分：transaction journal 恢复与恶意 journal 陷阱
# ------------------------------------------------------------------------------
p5_section("D. journal 恢复与恶意 journal 陷阱")
study_d <- tempfile("zz_p5_journal_", tmpdir = project_dir)
dir.create(file.path(study_d, "analysis", "r"), recursive = TRUE); dir.create(file.path(study_d, "analysis", "sas"), recursive = TRUE)
dir.create(file.path(study_d, "backup-trace"), recursive = TRUE)
on.exit(unlink(study_d, recursive = TRUE, force = TRUE), add = TRUE)
journal_path <- analysis_approval_journal_path(study_d)
first <- file.path(study_d, "analysis", "r", "WRAP-01.R"); second <- file.path(study_d, "analysis", "r", "WRAP-02.R")
writeLines("old-first", first); writeLines("old-second", second)
txn_dir <- analysis_approval_transaction_dir(study_d); dir.create(txn_dir, recursive = TRUE, showWarnings = FALSE)
txn_id <- "txn-test-000000000000-1-00112233445566778899aabbccddeeff"
txn_file <- function(kind) file.path(txn_dir, paste0(txn_id, ".WRAP.R.", kind, "-", basename(tempfile(""))))

failed <- try(analysis_transaction_publish(setNames(list("new-first", "new-second"), c(first, second)), journal_path, fail_after = 1L), silent = TRUE)
stopifnot(inherits(failed, "try-error"), identical(readLines(first), "old-first"), identical(readLines(second), "old-second"), !file.exists(journal_path))
missing_backup <- txn_file("backup"); missing_stage <- txn_file("stage"); writeLines("published-first", first)
missing_entries <- list(list(target = first, stage = missing_stage, backup = missing_backup, existed = TRUE, delete = FALSE))
analysis_approval_write_journal(journal_path, "committing", missing_entries, txn_id)
stopifnot(inherits(try(analysis_approval_recover(study_d), silent = TRUE), "try-error"), identical(readLines(first), "published-first"), file.exists(journal_path))
writeLines("old-first", missing_backup); stopifnot(analysis_approval_recover(study_d), identical(readLines(first), "old-first"))
backup_first <- txn_file("backup"); backup_second <- txn_file("backup"); stage_first <- txn_file("stage"); stage_second <- txn_file("stage")
writeLines("old-first", backup_first); writeLines("old-second", backup_second); writeLines("unused", stage_first); writeLines("unused", stage_second)
writeLines("old-first", first); writeLines("published-second", second)
rolling_entries <- list(list(target = first, stage = stage_first, backup = backup_first, existed = TRUE, delete = FALSE),
                        list(target = second, stage = stage_second, backup = backup_second, existed = TRUE, delete = FALSE))
analysis_approval_write_journal(journal_path, "rolling_back", rolling_entries, txn_id)
stopifnot(analysis_approval_recover(study_d), identical(readLines(first), "old-first"), identical(readLines(second), "old-second"), !file.exists(backup_first), !file.exists(backup_second))
completed_backup <- txn_file("backup"); completed_stage <- txn_file("stage"); writeLines("old-first", completed_backup); writeLines("unused", completed_stage); writeLines("published-first", first)
completed_entries <- list(list(target = first, stage = completed_stage, backup = completed_backup, existed = TRUE, delete = FALSE))
analysis_approval_write_journal(journal_path, "completed", completed_entries, txn_id)
stopifnot(analysis_approval_recover(study_d), identical(readLines(first), "published-first"), !file.exists(completed_backup), !file.exists(completed_stage))

outside_target <- tempfile("zz_p5_outside_target_", tmpdir = project_dir, fileext = ".txt"); writeLines("precious", outside_target)
on.exit(unlink(outside_target, force = TRUE), add = TRUE)
trap_backup <- txn_file("backup"); writeLines("attacker", trap_backup)
analysis_approval_write_journal(journal_path, "committing", list(list(target = outside_target, stage = "", backup = trap_backup, existed = TRUE, delete = TRUE)), txn_id)
stopifnot(inherits(try(analysis_approval_recover(study_d), silent = TRUE), "try-error"), file.exists(outside_target), identical(readLines(outside_target), "precious"), file.exists(trap_backup), file.exists(journal_path))
unlink(c(journal_path, outside_target), force = TRUE)
evil_backup <- tempfile("zz_p5_evil_backup_", tmpdir = project_dir, fileext = ".txt"); writeLines("evil", evil_backup)
on.exit(unlink(evil_backup, force = TRUE), add = TRUE)
analysis_approval_write_journal(journal_path, "committing", list(list(target = first, stage = "", backup = evil_backup, existed = TRUE, delete = TRUE)), txn_id)
stopifnot(inherits(try(analysis_approval_recover(study_d), silent = TRUE), "try-error"), file.exists(evil_backup), identical(readLines(evil_backup), "evil"), identical(readLines(first), "published-first"))
unlink(c(journal_path, evil_backup), force = TRUE)
analysis_approval_write_journal(journal_path, "committing", list(list(target = file.path(study_d, "analysis", "r", "..", "..", "escape.R"), stage = txn_file("stage"), backup = "", existed = FALSE, delete = FALSE)), txn_id)
stopifnot(inherits(try(analysis_approval_recover(study_d), silent = TRUE), "try-error")); unlink(journal_path, force = TRUE)
# 运行证据不可能通过 journal 被删除：output/ 下的目标不在允许集合内。
evidence_trap <- file.path(study_d, "output", "analyses", "WRAP", "analysis-run-record.csv")
dir.create(dirname(evidence_trap), recursive = TRUE, showWarnings = FALSE); writeLines("runtime-evidence", evidence_trap)
analysis_approval_write_journal(journal_path, "committing", list(list(target = evidence_trap, stage = "", backup = "", existed = FALSE, delete = TRUE)), txn_id)
stopifnot(inherits(try(analysis_approval_recover(study_d), silent = TRUE), "try-error"), file.exists(evidence_trap)); unlink(journal_path, force = TRUE)
yaml::write_yaml(list(schema_version = "1.1", phase = "committing", transaction_id = txn_id, entries = list(), updated_at_utc = "2026-08-19T00:00:00Z", malicious = "x"), journal_path)
stopifnot(inherits(try(analysis_approval_recover(study_d), silent = TRUE), "try-error")); unlink(journal_path, force = TRUE)
yaml::write_yaml(list(schema_version = "1.0", phase = "committing", transaction_id = txn_id, entries = list(), updated_at_utc = "2026-08-19T00:00:00Z"), journal_path)
stopifnot(inherits(try(analysis_approval_recover(study_d), silent = TRUE), "try-error")); unlink(journal_path, force = TRUE)
p5_log("journal 恢复与恶意 journal 陷阱全部 fail closed；运行证据不可达\n")

unlink(c(study_a, study_d, linked_fixture$study_dir, planned_fixture$study_dir), recursive = TRUE, force = TRUE)
p5_log("\nApproval transaction (Phase 5) focused check passed: 完整 N R + N SAS + collector、无 _template.sas、",
       "renderer/conformance/coverage/publication/obsolete-deletion/adapter/能力闸门失败全部恢复上一套完整产物、",
       "运行证据永不被 approval publisher 删除。\n")
p5_log("*** 说明：本检查从不执行 SAS。SAS 只作为代码交付物发布，由统计师在批准的目标环境自行运行；",
       "唯一生成闸门是目标环境能力声明。***\n")
