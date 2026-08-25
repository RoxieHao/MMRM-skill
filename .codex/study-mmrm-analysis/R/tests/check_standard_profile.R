options(encoding = "UTF-8")
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
if (length(script_arg) != 1L) stop("Run this check with Rscript.")
script_file <- normalizePath(sub("^--file=", "", script_arg), winslash = "/", mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_file), "..", "..", "..", ".."), winslash = "/", mustWork = TRUE)
helper_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
for (helper in c("canonical_hash.R", "standard_analysis_definition.R", "standard_engine.R", "standard_sas.R")) source(file.path(helper_dir, helper), encoding = "UTF-8")

recode <- list(
  id = "REPORTER_RECODE", operation = "recode", source_variable = "REPORTER", target_variable = "REPORTER_GROUP",
  levels = list(
    list(target_value = "Caregiver", source_values = c("Mother", "Father", "Guardian")),
    list(target_value = "Subject", source_values = "Self")
  ),
  unmatched = "set_missing", missing = "preserve",
  source_ref = list(review_rule = "T14-01/endpoint_dimension", reviewer_decision = "DEC-02")
)
standard_validate_derivations(list(recode), c("REPORTER"), "typed_recode")
data <- data.frame(REPORTER = c("Mother", "Father", "Guardian", "Self", "Other", "", NA_character_), PARAMCD = c("A", "B", "A", "B", "A", "A", "B"), stringsAsFactors = FALSE)
derived <- standard_apply_derivations(data, list(recode))
stopifnot(identical(derived$REPORTER_GROUP, c("Caregiver", "Caregiver", "Caregiver", "Subject", NA_character_, "", NA_character_)))
diagnostics <- attr(derived, "derivation_diagnostics")[["REPORTER_RECODE"]]
stopifnot(diagnostics$matched_count == 4L, diagnostics$unmatched_count == 1L, diagnostics$missing_count == 2L, diagnostics$output_missing_count == 3L, is.list(diagnostics$input_value_counts), is.list(diagnostics$output_value_counts))
downstream <- standard_filter_rows(derived, list(list(variable = "REPORTER_GROUP", operator = "eq", value = "Caregiver")))
stopifnot(nrow(downstream) == 3L)
set_selected <- standard_filter_rows(data, list(list(variable = "PARAMCD", operator = "in", value = c("A", "B"))))
stopifnot(nrow(set_selected) == nrow(data), !"PARAM_GROUP" %in% names(set_selected))
error_recode <- recode; error_recode$unmatched <- "error"; stopifnot(inherits(try(standard_apply_derivations(data, list(error_recode)), silent = TRUE), "try-error"))
missing_error <- recode; missing_error$missing <- "error"; stopifnot(inherits(try(standard_apply_derivations(data, list(missing_error)), silent = TRUE), "try-error"))
preserve <- recode; preserve$unmatched <- "preserve"; preserved <- standard_apply_derivations(data, list(preserve)); stopifnot(identical(preserved$REPORTER_GROUP[[5L]], "Other"))
collision <- data; collision$REPORTER_GROUP <- "existing"; stopifnot(inherits(try(standard_apply_derivations(collision, list(recode)), silent = TRUE), "try-error"))
overlap <- recode; overlap$levels[[2]]$source_values <- c("Self", "Mother"); stopifnot(inherits(try(standard_validate_derivations(list(overlap), c("REPORTER"), "overlap"), silent = TRUE), "try-error"))
cycle <- recode; cycle$source_variable <- "REPORTER_GROUP"; stopifnot(inherits(try(standard_validate_derivations(list(cycle), character(), "cycle"), silent = TRUE), "try-error"))
unsupported <- recode; unsupported$operation <- "expression"; stopifnot(inherits(try(standard_sas_recode_lines(unsupported), silent = TRUE), "try-error"))
sas_lines <- standard_sas_recode_lines(recode)
expected <- c(
  "  /* recode REPORTER_RECODE; normalized_type=character; blank_is_missing=true */",
  "  length REPORTER_GROUP $32767;",
  "  if not missing(REPORTER) and REPORTER in ('Mother', 'Father', 'Guardian') then REPORTER_GROUP='Caregiver';",
  "  else if not missing(REPORTER) and REPORTER in ('Self') then REPORTER_GROUP='Subject';",
  "  else if not missing(REPORTER) then call missing(REPORTER_GROUP);",
  "  if missing(REPORTER) then REPORTER_GROUP=REPORTER;"
)
stopifnot(identical(sas_lines, expected))

# Macro-safe SAS character literal golden cases: single-quoted data literals must never
# expose SAS macro triggers (% or &) to resolution, and apostrophes must be doubled.
stopifnot(identical(standard_sas_quote("plain"), "'plain'"))
stopifnot(identical(standard_sas_quote("O'Brien"), "'O''Brien'"))
stopifnot(identical(standard_sas_quote("say \"hi\""), "'say \"hi\"'"))
stopifnot(identical(standard_sas_quote("100% &done"), "'100% &done'"))
stopifnot(identical(standard_sas_quote("&macro"), "'&macro'"))
stopifnot(identical(standard_sas_quote("%let"), "'%let'"))
stopifnot(identical(standard_sas_quote(""), "''"))
stopifnot(identical(standard_sas_quote("caf\u00e9"), "'caf\u00e9'"))
stopifnot(identical(standard_sas_predicate(list(variable = "ARM", operator = "eq", value = "A&B")), "ARM = 'A&B'"))
# Control characters and non-scalar/NA values cannot be represented as a data literal.
stopifnot(inherits(try(standard_sas_quote("tab\tvalue"), silent = TRUE), "try-error"))
stopifnot(inherits(try(standard_sas_quote("new\nline"), silent = TRUE), "try-error"))
stopifnot(inherits(try(standard_sas_quote(NA_character_), silent = TRUE), "try-error"))

macro_recode <- recode
macro_recode$levels[[1]]$source_values <- c("Mother&Co", "Father%X", "O'Guardian")
macro_recode$levels[[1]]$target_value <- "Care&Giver"
macro_sas <- standard_sas_recode_lines(macro_recode)
stopifnot(any(grepl("REPORTER in ('Mother&Co', 'Father%X', 'O''Guardian') then REPORTER_GROUP='Care&Giver';", macro_sas, fixed = TRUE)))
stopifnot(!any(grepl("\"", macro_sas, fixed = TRUE)))

control_recode <- recode
control_recode$levels[[2]]$target_value <- "Sub\tject"
stopifnot(inherits(try(standard_sas_recode_lines(control_recode), silent = TRUE), "try-error"))

cat("Typed recode R evaluator and macro-safe SAS renderer conformance check passed.\n")

# ==============================================================================
# Phase 6 自检：collector（9.1）、manifest（9.2）、内部 engine 命名对齐（9.3）
#
# 语义前提（用户已明确，不可违背）：本流水线从不执行 SAS。无论有无 ADaM 数据，SAS 只作为
# 代码交付物；collector 绝不调用 SAS，只在统计师自行运行 SAS 后提供 run record 时才导入。
# ==============================================================================

for (helper in c("study_paths.R", "io.R", "specification.R", "analysis_plan.R", "standard_contract.R",
                 "analysis_contract_generation.R", "program_generation_ir.R", "program_conformance.R",
                 "self_contained_r.R", "self_contained_sas.R", "review_finalization.R", "analysis_approval.R",
                 "standard_artifacts.R")) {
  source(file.path(helper_dir, helper), encoding = "UTF-8", local = globalenv())
}
if (!requireNamespace("digest", quietly = TRUE) || !requireNamespace("yaml", quietly = TRUE)) stop("digest and yaml are required")

p6_log <- function(...) { cat(paste0(c(...), collapse = "")); flush(stdout()); invisible(NULL) }
p6_section <- function(title) p6_log("\n== ", title, " ==\n")
p6_expect_error <- function(expression, fragment = NULL) {
  error <- try(force(expression), silent = TRUE)
  stopifnot(inherits(error, "try-error"))
  if (!is.null(fragment)) stopifnot(grepl(fragment, as.character(error), fixed = TRUE))
  invisible(trimws(as.character(error)))
}
p6_rscript <- function() {
  candidates <- c(
    file.path(R.home("bin"), if (identical(.Platform$OS.type, "windows")) "Rscript.exe" else "Rscript"),
    file.path(R.home("bin"), "x64", "Rscript.exe"),
    unname(Sys.which("Rscript"))
  )
  candidates <- candidates[nzchar(candidates) & file.exists(candidates)]
  if (!length(candidates)) return("")
  candidates[[1L]]
}
p6_bytes <- function(path) readBin(path, what = "raw", n = file.size(path))
p6_read_manifest <- function(path) {
  manifest <- read_utf8_bom_csv(path)
  manifest[] <- lapply(manifest, function(column) { value <- as.character(column); value[is.na(value)] <- ""; value })
  manifest
}
p6_row <- function(manifest, analysis_id, language) {
  index <- which(manifest$analysis_id == analysis_id & manifest$programming_language == language)
  stopifnot(length(index) == 1L)
  manifest[index, , drop = FALSE]
}
p6_write_utf8_bom_csv <- function(frame, path) {
  temporary <- tempfile(fileext = ".csv")
  on.exit(unlink(temporary), add = TRUE)
  utils::write.csv(frame, file = temporary, row.names = FALSE, na = "", fileEncoding = "UTF-8")
  content <- readBin(temporary, what = "raw", n = file.size(temporary))
  connection <- file(path, open = "wb")
  on.exit(close(connection), add = TRUE)
  writeBin(c(as.raw(c(239L, 187L, 191L)), content), connection)
  invisible(path)
}

# ------------------------------------------------------------------------------
# 9.1/9.2 静态断言：collector 模板不依赖共享 engine，且全代码路径只启动 Rscript。
# ------------------------------------------------------------------------------
p6_section("collector 静态断言：不依赖共享 engine，且从不调用 SAS 可执行文件")
collector_template <- paste(readLines(file.path(helper_dir, "templates", "run_all_mmrm_template.R"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
stopifnot(
  !grepl("standard_engine.R", collector_template, fixed = TRUE),
  !grepl("run_standard_mmrm_analysis", collector_template, fixed = TRUE),
  !grepl("system2(", collector_template, fixed = TRUE),
  !grepl("system(", collector_template, fixed = TRUE),
  !grepl("shell(", collector_template, fixed = TRUE),
  grepl("run_self_contained_mmrm_collector(", collector_template, fixed = TRUE),
  grepl("--mode=collect-only", collector_template, fixed = TRUE)
)
collector_function_names <- c(ls(envir = globalenv(), pattern = "^standard_collector_"), "run_self_contained_mmrm_collector", "standard_validate_collector_manifest")
collector_bodies <- vapply(collector_function_names, function(name) paste(deparse(get(name, envir = globalenv())), collapse = "\n"), character(1))
launcher_counts <- vapply(collector_bodies, function(body) {
  sum(vapply(c("system2(", "system(", "shell(", "processx"), function(pattern) length(gregexpr(pattern, body, fixed = TRUE)[[1L]][gregexpr(pattern, body, fixed = TRUE)[[1L]] > 0L]), integer(1)))
}, integer(1))
stopifnot(
  identical(unname(launcher_counts[["standard_collector_invoke_r_program"]]), 1L),
  all(unname(launcher_counts[setdiff(names(launcher_counts), "standard_collector_invoke_r_program")]) == 0L),
  grepl("--input-dir", collector_bodies[["standard_collector_invoke_r_program"]], fixed = TRUE),
  grepl("--output-dir", collector_bodies[["standard_collector_invoke_r_program"]], fixed = TRUE),
  !grepl("sas", tolower(collector_bodies[["standard_collector_invoke_r_program"]]), fixed = TRUE)
)
stopifnot(!any(grepl("(^|[^_a-z])sas(\\.exe)?(\"|'|\\s|,|\\))", tolower(collector_bodies[["run_self_contained_mmrm_collector"]]), perl = TRUE) &
               grepl("system", tolower(collector_bodies[["run_self_contained_mmrm_collector"]]), fixed = TRUE)))
p6_log("collector 只有一个子进程启动点 standard_collector_invoke_r_program，且它只启动 Rscript 并只传固定路径参数。\n")

manifest_template <- readLines(file.path(project_dir, ".codex", "study-mmrm-analysis", "assets", "study-control", "tfl-output-manifest.csv"), warn = FALSE, encoding = "UTF-8")
stopifnot(identical(strsplit(sub("^\ufeff", "", manifest_template[[1L]]), ",", fixed = TRUE)[[1L]], standard_collector_manifest_columns()))
p6_log("manifest 模板表头与 standard_collector_manifest_columns() 一致（", length(standard_collector_manifest_columns()), " 列）。\n")

# 9.3：内部 engine 的 R 侧产物命名必须全部来自 contract 的 r_* 字段。
engine_output <- standard_contract_expected_output("T14-90")
engine_paths_probe <- standard_engine_r_artifact_paths(
  list(root = "ROOT", tables = "ROOT/tables", diagnostics = "ROOT/diagnostics"),
  list(output = engine_output)
)
stopifnot(
  identical(basename(engine_paths_probe$raw), engine_output$r_raw_file),
  identical(basename(engine_paths_probe$final), engine_output$r_final_file),
  identical(basename(engine_paths_probe$diagnostic), engine_output$r_diagnostic_file),
  identical(basename(engine_paths_probe$run_record), engine_output$r_run_record_file)
)
engine_source <- paste(readLines(file.path(helper_dir, "standard_engine.R"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
stopifnot(!grepl("output_paths$diagnostic_csv", engine_source, fixed = TRUE), !grepl("output_paths$run_record", engine_source, fixed = TRUE))
p6_expect_error(standard_engine_r_artifact_paths(list(root = "ROOT", tables = "T", diagnostics = "D"), list(output = list(raw_file = "x.csv"))),
                "PLAN-SCHEMA-IDENTITY-OUTPUT-CLOSED-SHAPE")
p6_log("内部 engine 输出命名对齐断言通过：raw/final/diagnostic/run-record 全部来自 contract r_* 字段，旧 engine 私有文件名已消失。\n")
p6_expect_error(standard_output_manifest_schema(), "standard_collector_manifest_schema()")

# ------------------------------------------------------------------------------
# 混合 study fixture：一个 planned analysis + 两个 linked analysis。
# contract 顺序（MMRM-30、MMRM-10、MMRM-20）故意与文件名升序
# （MMRM-10.R、MMRM-20.R、MMRM-30.R）不同。
# ------------------------------------------------------------------------------
p6_missing_packages <- setdiff(c("digest", "mmrm", "emmeans"), rownames(utils::installed.packages(lib.loc = .libPaths())))
p6_rscript_path <- p6_rscript()
if (length(p6_missing_packages) || !nzchar(p6_rscript_path)) {
  p6_log("跳过全部 collector 执行类断言（不声称通过）：",
         if (length(p6_missing_packages)) paste0("本机缺少必需 R 包 ", paste(p6_missing_packages, collapse = ", "), "；") else "",
         if (!nzchar(p6_rscript_path)) "本机未解析到 Rscript 可执行文件；" else "",
         "只完成了静态断言。\n")
  cat("Typed recode / macro-safe SAS renderer / Phase 6 static collector checks passed; collector execution checks SKIPPED.\n")
  quit(save = "no", status = 0L)
}

p6_synthetic_frame <- function() {
  subjects <- sprintf("P%02d", seq_len(24L))
  baseline <- 40 + seq_len(24L) * 0.5
  pieces <- list()
  for (i in seq_along(subjects)) {
    for (visit in 1:3) {
      pieces[[length(pieces) + 1L]] <- data.frame(
        PERSON_ID = subjects[[i]], PARAMCD = "SCORE_A", TIME_INDEX = visit,
        START_SCORE = baseline[[i]],
        DELTA_SCORE = round(baseline[[i]] * 0.08 + visit * 1.4 + ((i * 7L + visit * 3L) %% 5L) - 2, 3),
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, pieces)
}

p6_plan_analysis <- function(analysis_id, tfl_id, binding_mode, source_path, project_dir, evidence_id) {
  dimensions <- list(instrument = list(variable = "not_applicable", values = character()), version = list(variable = "not_applicable", values = character()),
                     reporter = list(variable = "not_applicable", values = character()), subscale = list(variable = "not_applicable", values = character()))
  trace <- setNames(rep(list(list()), length(analysis_plan_trace_keys())), analysis_plan_trace_keys())
  for (name in c("dataset", "mappings", "groups", "endpoint_definitions", "fixed_effects", "reml", "covariance", "df_method", "estimands")) trace[[name]] <- list(evidence_id)
  dataset <- if (identical(binding_mode, "linked")) {
    list(binding_mode = "linked", file = "scores.csv", format = "csv", relative_path = project_relative_path(source_path, project_dir), sha256 = file_sha256(source_path))
  } else list(binding_mode = "planned", file = "scores.csv", format = "csv", relative_path = NULL, sha256 = NULL)
  list(analysis_id = analysis_id, source_tfl_id = tfl_id, title = paste0("Phase 6 collector fixture ", analysis_id),
       dataset = dataset, adapter = NULL,
       mappings = list(subject = "PERSON_ID", response = "DELTA_SCORE", baseline = "START_SCORE", visit = "TIME_INDEX"),
       derivations = list(), filters = list(),
       groups = list(list(id = "TOTAL", label = "Total", predicates = list(list(variable = "PARAMCD", operator = "eq", value = "SCORE_A")))),
       endpoint_definitions = list(list(group_id = "TOTAL", endpoint_variable = "PARAMCD", selected_codes = "SCORE_A", selection_mode = "single_code",
                                        dimensions = dimensions, row_allocation_rule = "one_row_per_subject_endpoint_visit")),
       fixed_effects = as.list(c("visit", "baseline", "baseline_by_visit")), reml = TRUE,
       covariance = list(primary = "CS", fallback = as.list("AR1")), df_method = "Satterthwaite",
       estimands = list(visit_lsmeans = TRUE, treatment_visit_lsmeans = FALSE, pairwise_differences = FALSE), treatment = NULL, trace = trace)
}

p6_build_study <- function(prefix) {
  study_dir <- tempfile(prefix, tmpdir = project_dir)
  for (directory in c("input", "backup-trace", "statistician-review")) dir.create(file.path(study_dir, directory), recursive = TRUE)
  source_path <- file.path(study_dir, "input", "scores.csv")
  p6_write_utf8_bom_csv(p6_synthetic_frame(), source_path)
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
  list(study_dir = study_dir, review_path = review_path, source_path = source_path, evidence_id = evidence_id, study_id = study_id)
}

p6_section("混合 study fixture：1 个 planned + 2 个 linked analysis")
fixture <- p6_build_study("zz_p6_collector_")
p6_cleanup <- function() unlink(fixture$study_dir, recursive = TRUE, force = TRUE)
on.exit(p6_cleanup(), add = TRUE)
mixed_ids <- list(c("MMRM-30", "T14-30", "linked"), c("MMRM-10", "T14-10", "planned"), c("MMRM-20", "T14-20", "linked"))
plan <- list(
  analysis_plan_schema_version = "2.1", study_id = fixture$study_id,
  execution_context = list(profile_version = standard_mmrm_profile_version(), data_availability = "available",
                           data_classification = "dummy", intended_use = "technical_validation",
                           sas_execution_profile = "sas-9.4m5-self-contained/v1"),
  analyses = lapply(mixed_ids, function(item) p6_plan_analysis(item[[1L]], item[[2L]], item[[3L]], fixture$source_path, project_dir, fixture$evidence_id))
)
analysis_plan_write(plan, analysis_plan_candidate_path(fixture$study_dir))
profile_review_lines <- statistical_review_set_metadata(readLines(fixture$review_path, encoding = "UTF-8", warn = FALSE), "review_status", "ready_for_compilation")
writeLines(profile_review_lines, fixture$review_path, useBytes = TRUE)
finalization <- finalize_statistical_review(fixture$study_dir, fixture$review_path, fixture$review_path, "Synthetic Reviewer", allow_unresolved = TRUE)
stopifnot(isTRUE(finalization$published), isTRUE(finalization$approved), identical(finalization$analysis_count, 3L))
chain <- approve_and_generate_analysis(fixture$study_dir, project_dir, "Synthetic Reviewer")
contract <- chain$contract
contract_order <- vapply(contract$analyses, function(x) as.character(x$analysis_id), character(1))
filename_order <- sort(paste0(vapply(contract$analyses, function(x) standard_contract_safe_identity(x$analysis_id), character(1)), ".R"), method = "radix")
stopifnot(
  identical(contract_order, c("MMRM-30", "MMRM-10", "MMRM-20")),
  identical(filename_order, c("MMRM-10.R", "MMRM-20.R", "MMRM-30.R")),
  !identical(paste0(contract_order, ".R"), filename_order),
  identical(vapply(contract$analyses, function(x) as.character(x$dataset$binding_mode), character(1)), c("linked", "planned", "linked"))
)
collector_path <- file.path(fixture$study_dir, "analysis", "r", "run_all_mmrm.R")
stopifnot(file.exists(collector_path), all(file.exists(file.path(fixture$study_dir, "analysis", "r", filename_order))))
p6_log("fixture 就绪：contract 顺序 = ", paste(contract_order, collapse = ", "),
       "；文件名升序 = ", paste(filename_order, collapse = ", "), "（两者故意不同）\n")

analysis_output_root <- function(analysis_id) file.path(fixture$study_dir, "output", "analyses", standard_contract_safe_identity(analysis_id))
contract_analysis <- function(analysis_id) standard_contract_get_analysis(contract, analysis_id)

# ------------------------------------------------------------------------------
# 生成的 collector 以子进程运行（run-and-collect）。PATH 前置一个会写 sentinel 的假 sas
# 命令：collector 全程不得触发它。
# ------------------------------------------------------------------------------
p6_section("run-and-collect：生成的 run_all_mmrm.R 子进程运行")
fake_bin <- file.path(fixture$study_dir, "backup-trace", "fake-bin")
dir.create(fake_bin, recursive = TRUE, showWarnings = FALSE)
sas_sentinel <- file.path(fixture$study_dir, "backup-trace", "sas-was-invoked.txt")
for (fake in c("sas.bat", "sas.cmd", "sas9.bat")) {
  writeLines(c("@echo off", paste0("echo invoked > \"", gsub("/", "\\\\", sas_sentinel), "\"")), file.path(fake_bin, fake), useBytes = TRUE)
}
collector_log_path <- file.path(fixture$study_dir, "output", "logs", "run_all_mmrm.log")
subprocess_log <- file.path(fixture$study_dir, "backup-trace", "collector-subprocess.log")
old_path <- Sys.getenv("PATH")
Sys.setenv(PATH = paste(fake_bin, old_path, sep = .Platform$path.sep))
collector_status <- suppressWarnings(system2(p6_rscript_path, c("--vanilla", shQuote(collector_path)), stdout = subprocess_log, stderr = subprocess_log))
Sys.setenv(PATH = old_path)
if (!identical(as.integer(collector_status), 0L)) {
  p6_log("collector 子进程失败，日志如下：\n", paste(readLines(subprocess_log, warn = FALSE, encoding = "UTF-8"), collapse = "\n"), "\n")
  stop("生成的 collector 在混合 study 上必须以退出码 0 结束。")
}
stopifnot(!file.exists(sas_sentinel))
manifest_path <- file.path(fixture$study_dir, "output", "tfl-output-manifest.csv")
manifest <- p6_read_manifest(manifest_path)
stopifnot(
  identical(names(manifest), standard_collector_manifest_columns()),
  nrow(manifest) == 6L,
  identical(manifest$analysis_id, rep(c("MMRM-10", "MMRM-20", "MMRM-30"), each = 2L)),
  identical(manifest$programming_language, rep(c("R", "SAS"), times = 3L)),
  all(manifest$execution_status %in% standard_collector_execution_status_values())
)
p6_log("manifest 行顺序按 R 程序文件名升序：", paste(unique(manifest$analysis_id), collapse = ", "), "\n")

planned_r <- p6_row(manifest, "MMRM-10", "R"); planned_sas <- p6_row(manifest, "MMRM-10", "SAS")
stopifnot(
  identical(planned_r$execution_status[[1L]], "code_generation_only"),
  identical(planned_sas$execution_status[[1L]], "code_generation_only"),
  identical(planned_r$binding_mode[[1L]], "planned"),
  all(!nzchar(unlist(planned_r[standard_collector_result_path_columns()], use.names = FALSE))),
  all(!nzchar(unlist(planned_sas[standard_collector_result_path_columns()], use.names = FALSE))),
  nzchar(planned_r$program_sha256[[1L]]), nzchar(planned_sas$program_sha256[[1L]]),
  identical(planned_r$program_sha256[[1L]], file_sha256(file.path(fixture$study_dir, "analysis", "r", "MMRM-10.R"))),
  identical(planned_sas$program_sha256[[1L]], file_sha256(file.path(fixture$study_dir, "analysis", "sas", "MMRM-10.sas")))
)
stopifnot(length(list.files(analysis_output_root("MMRM-10"), all.files = TRUE, no.. = TRUE, recursive = TRUE)) == 0L)
p6_log("planned analysis 断言通过：R 与 SAS 均登记 code_generation_only、结果路径留空、输出目录无任何产物。\n")

for (linked_id in c("MMRM-20", "MMRM-30")) {
  analysis <- contract_analysis(linked_id)
  row_r <- p6_row(manifest, linked_id, "R"); row_sas <- p6_row(manifest, linked_id, "SAS")
  output_dir <- analysis_output_root(linked_id)
  stopifnot(
    identical(row_r$execution_status[[1L]], "executed"),
    identical(row_r$run_status[[1L]], "complete"),
    identical(basename(row_r$raw_output_file[[1L]]), analysis$output$r_raw_file),
    identical(basename(row_r$final_tfl_file[[1L]]), analysis$output$r_final_file),
    identical(basename(row_r$diagnostic_file[[1L]]), analysis$output$r_diagnostic_file),
    identical(basename(row_r$run_record_file[[1L]]), analysis$output$r_run_record_file),
    file.exists(file.path(output_dir, analysis$output$r_final_file)),
    identical(row_r$expected_input_sha256[[1L]], toupper(as.character(analysis$dataset$sha256))),
    identical(row_r$actual_input_sha256[[1L]], toupper(as.character(analysis$dataset$sha256))),
    identical(row_sas$execution_status[[1L]], "program_generated_not_executed"),
    all(!nzchar(unlist(row_sas[standard_collector_result_path_columns()], use.names = FALSE))),
    !file.exists(file.path(output_dir, analysis$output$sas_run_record_file))
  )
}
p6_log("linked analysis 断言通过：R 行 executed 且结果路径经存在性校验后才填写；SAS 行 program_generated_not_executed 且结果路径留空。\n")

r_artifacts <- basename(unlist(manifest[manifest$programming_language == "R", standard_collector_result_path_columns()], use.names = FALSE))
sas_artifacts <- basename(unlist(manifest[manifest$programming_language == "SAS", standard_collector_result_path_columns()], use.names = FALSE))
r_artifacts <- r_artifacts[nzchar(r_artifacts)]; sas_artifacts <- sas_artifacts[nzchar(sas_artifacts)]
stopifnot(!length(intersect(tolower(r_artifacts), tolower(sas_artifacts))), !anyDuplicated(tolower(r_artifacts)))
for (linked_id in c("MMRM-20", "MMRM-30")) {
  analysis <- contract_analysis(linked_id)
  written <- list.files(analysis_output_root(linked_id))
  stopifnot(setequal(written, c(analysis$output$r_raw_file, analysis$output$r_final_file, analysis$output$r_diagnostic_file, analysis$output$r_run_record_file)))
}
p6_log("R/SAS 产物文件名互不重叠，且每个 analysis 的输出目录只包含本语言 run record 声明的文件。\n")

collector_log <- readLines(collector_log_path, warn = FALSE, encoding = "UTF-8")
invoke_lines <- grep("invoke Rscript", collector_log, fixed = TRUE, value = TRUE)
planned_lines <- grep("binding_mode=planned", collector_log, fixed = TRUE, value = TRUE)
stopifnot(
  length(invoke_lines) == 2L,
  grepl("MMRM-20.R", invoke_lines[[1L]], fixed = TRUE),
  grepl("MMRM-30.R", invoke_lines[[2L]], fixed = TRUE),
  length(planned_lines) == 1L,
  grepl("MMRM-10", planned_lines[[1L]], fixed = TRUE),
  grepl("Rscript subprocess not invoked", planned_lines[[1L]], fixed = TRUE),
  any(grepl("--input-dir", collector_log, fixed = TRUE)) || any(grepl("input_dir=", collector_log, fixed = TRUE)),
  !any(grepl("code-generation", collector_log, fixed = TRUE))
)
p6_log("collector 日志断言通过：只有两个 linked analysis 触发 Rscript，顺序为 MMRM-20.R → MMRM-30.R；planned analysis 明确记录未调用 R。\n")

# ------------------------------------------------------------------------------
# 单独运行某个 .R 与 collector 运行该 .R 必须得到逐字节相同的 final TFL。
# ------------------------------------------------------------------------------
p6_section("standalone 与 collector 的单 TFL 输出逐字节一致")
standalone_root <- file.path(fixture$study_dir, "backup-trace", "standalone-output")
dir.create(standalone_root, recursive = TRUE, showWarnings = FALSE)
standalone_log <- file.path(fixture$study_dir, "backup-trace", "standalone.log")
standalone_status <- suppressWarnings(system2(
  p6_rscript_path,
  c("--vanilla", shQuote(file.path(fixture$study_dir, "analysis", "r", "MMRM-20.R")),
    "--input-dir", shQuote(file.path(fixture$study_dir, "input")), "--output-dir", shQuote(standalone_root)),
  stdout = standalone_log, stderr = standalone_log
))
if (!identical(as.integer(standalone_status), 0L)) {
  p6_log("standalone 运行失败，日志如下：\n", paste(readLines(standalone_log, warn = FALSE, encoding = "UTF-8"), collapse = "\n"), "\n")
  stop("MMRM-20.R 单独运行必须成功。")
}
analysis_20 <- contract_analysis("MMRM-20")
standalone_final <- file.path(standalone_root, analysis_20$output$r_final_file)
collector_final <- file.path(analysis_output_root("MMRM-20"), analysis_20$output$r_final_file)
standalone_raw <- file.path(standalone_root, analysis_20$output$r_raw_file)
collector_raw <- file.path(analysis_output_root("MMRM-20"), analysis_20$output$r_raw_file)
stopifnot(
  file.exists(standalone_final), file.exists(collector_final),
  identical(p6_bytes(standalone_final), p6_bytes(collector_final)),
  identical(p6_bytes(standalone_raw), p6_bytes(collector_raw))
)
p6_log("逐字节一致断言通过：standalone final TFL 与 collector final TFL 完全相同（raw TFL 亦相同）。\n")

# ------------------------------------------------------------------------------
# 进程内 instrumented 运行：机械记录“哪个程序被调用、按什么顺序调用”。
# ------------------------------------------------------------------------------
p6_section("逐 analysis binding mode：planned 绝不调用 R")
p6_invocations <- character()
real_invoke <- standard_collector_invoke_r_program
assign("standard_collector_invoke_r_program", function(rscript, program_path, input_dir, output_dir, log_path) {
  p6_invocations <<- c(p6_invocations, basename(program_path))
  real_invoke(rscript, program_path, input_dir, output_dir, log_path)
}, envir = globalenv())
instrumented <- run_self_contained_mmrm_collector(collector_path, chain$approval_payload_sha256, chain$contract_sha256, mode = "run-and-collect")
assign("standard_collector_invoke_r_program", real_invoke, envir = globalenv())
stopifnot(
  identical(p6_invocations, c("MMRM-20.R", "MMRM-30.R")),
  !("MMRM-10.R" %in% p6_invocations),
  identical(instrumented$order, c("MMRM-10.R", "MMRM-20.R", "MMRM-30.R"))
)
standard_validate_collector_manifest(instrumented$manifest, contract)
p6_log("instrumented 断言通过：collector 只为 linked analysis 启动子进程，调用序列 = ",
       paste(p6_invocations, collapse = " -> "), "；planned analysis 从未被调用。\n")

# ------------------------------------------------------------------------------
# collect-only：导入统计师自行运行 SAS 后的 run record。
# ------------------------------------------------------------------------------
p6_section("collect-only：SAS run record 导入与篡改阻断")
p6_write_sas_evidence <- function(analysis_id, overrides = list(), skip_files = character()) {
  analysis <- contract_analysis(analysis_id)
  output_dir <- analysis_output_root(analysis_id)
  values <- list(
    study_id = as.character(contract$study$study_id), analysis_id = analysis_id, tfl_id = as.character(analysis$tfl_id),
    programming_language = "SAS", profile_version = standard_mmrm_profile_version(),
    plan_sha256 = toupper(as.character(contract$approval$analysis_plan_sha256)),
    approval_payload_sha256 = toupper(as.character(chain$approval_payload_sha256)),
    contract_sha256 = toupper(as.character(chain$contract_sha256)),
    dataset_binding_mode = "linked", actual_input_sha256 = toupper(as.character(analysis$dataset$sha256)),
    execution_status = "executed", run_status = "complete", computational_risk = "Green",
    raw_output_file = analysis$output$sas_raw_file, final_output_file = analysis$output$sas_final_file,
    diagnostic_file = analysis$output$sas_diagnostic_file, run_record_file = analysis$output$sas_run_record_file,
    run_started_utc = "2026-08-21T01:00:00Z", run_finished_utc = "2026-08-21T01:05:00Z"
  )
  for (name in names(overrides)) values[[name]] <- overrides[[name]]
  record <- as.data.frame(values[standard_collector_run_record_columns()], stringsAsFactors = FALSE)
  names(record) <- standard_collector_run_record_columns()
  payload <- data.frame(analysis_id = analysis_id, tfl_id = as.character(analysis$tfl_id), value = "synthetic SAS evidence", stringsAsFactors = FALSE)
  for (target in setdiff(c(analysis$output$sas_raw_file, analysis$output$sas_final_file, analysis$output$sas_diagnostic_file), skip_files)) {
    p6_write_utf8_bom_csv(payload, file.path(output_dir, target))
  }
  p6_write_utf8_bom_csv(record, file.path(output_dir, analysis$output$sas_run_record_file))
  invisible(output_dir)
}
p6_clear_sas_evidence <- function(analysis_id) {
  analysis <- contract_analysis(analysis_id)
  unlink(file.path(analysis_output_root(analysis_id), c(analysis$output$sas_raw_file, analysis$output$sas_final_file,
                                                        analysis$output$sas_diagnostic_file, analysis$output$sas_run_record_file)), force = TRUE)
}

manifest_before_import <- p6_read_manifest(manifest_path)
p6_write_sas_evidence("MMRM-20")
collect_only <- run_self_contained_mmrm_collector(collector_path, chain$approval_payload_sha256, chain$contract_sha256, mode = "collect-only")
manifest <- p6_read_manifest(manifest_path)
row_r_20 <- p6_row(manifest, "MMRM-20", "R"); row_sas_20 <- p6_row(manifest, "MMRM-20", "SAS")
previous_r_20 <- p6_row(manifest_before_import, "MMRM-20", "R")
compare_columns <- setdiff(standard_collector_manifest_columns(), c("collector_mode", "collected_at_utc", "note"))
stopifnot(
  identical(row_sas_20$execution_status[[1L]], "executed"),
  identical(basename(row_sas_20$final_tfl_file[[1L]]), analysis_20$output$sas_final_file),
  identical(basename(row_sas_20$raw_output_file[[1L]]), analysis_20$output$sas_raw_file),
  identical(row_r_20$execution_status[[1L]], "executed"),
  identical(unlist(row_r_20[compare_columns], use.names = FALSE), unlist(previous_r_20[compare_columns], use.names = FALSE)),
  identical(row_sas_20$collector_mode[[1L]], "collect-only"),
  !length(intersect(tolower(basename(unlist(row_r_20[standard_collector_result_path_columns()], use.names = FALSE))),
                    tolower(basename(unlist(row_sas_20[standard_collector_result_path_columns()], use.names = FALSE)))))
)
stopifnot(identical(p6_row(manifest, "MMRM-30", "SAS")$execution_status[[1L]], "program_generated_not_executed"),
          identical(p6_row(manifest, "MMRM-10", "SAS")$execution_status[[1L]], "code_generation_only"))
p6_log("collect-only 断言通过：合法 SAS run record 被导入为 executed，R 行逐列未被覆盖，其余 analysis 的 SAS 行保持未运行/code-only 状态。\n")

p6_tamper_cases <- list(
  list(label = "伪造 analysis_id", overrides = list(analysis_id = "MMRM-99"), skip = character()),
  list(label = "篡改 contract_sha256", overrides = list(contract_sha256 = paste(rep("A", 64L), collapse = "")), skip = character()),
  list(label = "篡改 plan_sha256", overrides = list(plan_sha256 = paste(rep("B", 64L), collapse = "")), skip = character()),
  list(label = "篡改实际 input SHA", overrides = list(actual_input_sha256 = paste(rep("C", 64L), collapse = "")), skip = character()),
  list(label = "伪造 programming_language", overrides = list(programming_language = "R"), skip = character()),
  list(label = "伪造 artifact path", overrides = list(final_output_file = "forged_final.csv"), skip = character()),
  list(label = "声明 executed 但结果文件不存在", overrides = list(), skip = "final"),
  list(label = "非法 execution_status", overrides = list(execution_status = "totally_fine"), skip = character())
)
for (case in p6_tamper_cases) {
  p6_clear_sas_evidence("MMRM-20")
  skip_files <- if (identical(case$skip, "final")) analysis_20$output$sas_final_file else character()
  p6_write_sas_evidence("MMRM-20", overrides = case$overrides, skip_files = skip_files)
  p6_expect_error(run_self_contained_mmrm_collector(collector_path, chain$approval_payload_sha256, chain$contract_sha256, mode = "collect-only"),
                  "COLLECTOR-BLOCKED")
  tampered_manifest <- p6_read_manifest(manifest_path)
  tampered_row <- p6_row(tampered_manifest, "MMRM-20", "SAS")
  stopifnot(
    identical(tampered_row$execution_status[[1L]], "blocked"),
    all(!nzchar(unlist(tampered_row[standard_collector_result_path_columns()], use.names = FALSE))),
    grepl("run record", tampered_row$note[[1L]], fixed = TRUE),
    identical(p6_row(tampered_manifest, "MMRM-20", "R")$execution_status[[1L]], "executed")
  )
  p6_log("篡改阻断断言通过（登记 blocked 且结果路径留空）：", case$label, "\n")
}
p6_clear_sas_evidence("MMRM-20")

# planned analysis 永远不接受 run record 导入：即使伪造一份也只登记 code_generation_only。
planned_analysis <- contract_analysis("MMRM-10")
p6_write_utf8_bom_csv(
  data.frame(matrix("x", nrow = 1L, ncol = length(standard_collector_run_record_columns()), dimnames = list(NULL, standard_collector_run_record_columns())), stringsAsFactors = FALSE),
  file.path(analysis_output_root("MMRM-10"), planned_analysis$output$sas_run_record_file)
)
planned_collect <- run_self_contained_mmrm_collector(collector_path, chain$approval_payload_sha256, chain$contract_sha256, mode = "collect-only")
stopifnot(identical(p6_row(planned_collect$manifest, "MMRM-10", "SAS")$execution_status[[1L]], "code_generation_only"),
          !nzchar(p6_row(planned_collect$manifest, "MMRM-10", "SAS")$run_record_file[[1L]]))
unlink(file.path(analysis_output_root("MMRM-10"), planned_analysis$output$sas_run_record_file), force = TRUE)
p6_log("planned analysis 断言通过：伪造的 SAS run record 不会把 planned 提升为 executed。\n")

# manifest 校验器自身的 closed set 与不覆盖闸门。
p6_expect_error(standard_validate_collector_manifest(transform(planned_collect$manifest, execution_status = "made_up"), contract), "COLLECTOR-MANIFEST-STATUS")
p6_expect_error(standard_validate_collector_manifest(planned_collect$manifest[planned_collect$manifest$programming_language == "R", , drop = FALSE], contract), "COLLECTOR-MANIFEST-COVERAGE")
duplicated_artifacts <- planned_collect$manifest
duplicated_artifacts$final_tfl_file[duplicated_artifacts$analysis_id == "MMRM-20"] <- "output/analyses/MMRM-20/shared.csv"
duplicated_artifacts$execution_status[duplicated_artifacts$analysis_id == "MMRM-20"] <- "executed"
duplicated_artifacts$raw_output_file[duplicated_artifacts$analysis_id == "MMRM-20"] <- "output/analyses/MMRM-20/shared_raw.csv"
p6_expect_error(standard_validate_collector_manifest(duplicated_artifacts, contract), "COLLECTOR-MANIFEST-ARTIFACT-COLLISION")
p6_log("manifest 校验器断言通过：closed set、双语言覆盖、R/SAS 产物不共享文件名全部机械阻断。\n")

stopifnot(!file.exists(sas_sentinel))
p6_log("全程未触发任何 SAS 命令（PATH 前置的假 sas 命令 sentinel 始终不存在）。\n")

p6_cleanup()
stopifnot(!dir.exists(fixture$study_dir))
cat("Standard MMRM profile check passed: typed recode / macro-safe SAS renderer / Phase 6 collector + manifest + internal engine alignment.\n")
