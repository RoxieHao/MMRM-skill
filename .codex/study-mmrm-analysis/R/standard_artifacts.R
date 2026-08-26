standard_required_raw_columns <- function() names(standard_raw_result_schema())
standard_required_final_columns <- function() names(standard_final_result_schema())
standard_required_diagnostic_columns <- function() names(standard_diagnostic_schema())
standard_required_run_record_columns <- function() names(standard_run_record_schema())

# ==============================================================================
# Phase 6：collector / manifest builder 的 closed set 与 schema
# ==============================================================================
# tfl-output-manifest.csv 只能由 collector / manifest builder 写。单个生成的 R/SAS 程序
# 只写自己那一个 analysis、那一种语言的 run record，永远不 append 或改写本文件。
# 每个 analysis 恰好两行：programming_language=R 与 programming_language=SAS。

standard_collector_execution_status_values <- function() {
  c("program_generated_not_executed", "code_generation_only", "executed", "blocked", "failed")
}
standard_collector_result_path_columns <- function() c("raw_output_file", "final_tfl_file", "diagnostic_file", "run_record_file")

# 生成程序（self_contained_r.R / self_contained_sas.R）写出的 language-specific run record 列。
# 两种语言必须完全一致；collector 以此为唯一导入接口。
standard_collector_run_record_columns <- function() {
  c(
    "study_id", "analysis_id", "tfl_id", "programming_language", "profile_version",
    "plan_sha256", "approval_payload_sha256", "contract_sha256", "dataset_binding_mode", "actual_input_sha256",
    "execution_status", "run_status", "computational_risk",
    "raw_output_file", "final_output_file", "diagnostic_file", "run_record_file",
    "run_started_utc", "run_finished_utc"
  )
}

standard_collector_manifest_columns <- function() {
  c(
    "study_id", "analysis_id", "tfl_id", "tfl_type", "title", "scope_status",
    "programming_language", "binding_mode", "program_file", "program_sha256",
    "execution_status", "run_status", "computational_risk",
    "raw_output_file", "final_tfl_file", "diagnostic_file", "run_record_file",
    "plan_sha256", "approval_payload_sha256", "contract_sha256",
    "expected_input_sha256", "actual_input_sha256",
    "collector_mode", "collected_at_utc", "note"
  )
}

standard_collector_manifest_schema <- function() {
  columns <- standard_collector_manifest_columns()
  frame <- as.data.frame(setNames(replicate(length(columns), character(), simplify = FALSE), columns), stringsAsFactors = FALSE)
  frame
}

# 旧的 engine 时代 manifest schema 保留名字以避免调用方静默拿到错误列，但直接阻断。
standard_output_manifest_schema <- function() {
  stop("standard_output_manifest_schema() has been replaced by standard_collector_manifest_schema(); the manifest is language-aware since Phase 6.")
}

standard_artifact_absolute <- function(relative_path, project_dir, analysis_root = NULL) {
  absolute <- normalize_project_relative_path(relative_path, project_dir, "artifact path")
  if (!file.exists(absolute)) stop("artifact does not exist: ", relative_path)
  if (!is.null(analysis_root)) {
    root <- paste0(normalizePath(analysis_root, winslash = "/", mustWork = TRUE), "/")
    normalized <- normalizePath(absolute, winslash = "/", mustWork = TRUE)
    comparable <- function(x) if (.Platform$OS.type == "windows") tolower(x) else x
    if (!startsWith(comparable(normalized), comparable(root))) stop("artifact is outside analysis root: ", relative_path)
  }
  absolute
}

standard_read_csv_schema <- function(path, expected_columns, context) {
  data <- read.csv(
    path, stringsAsFactors = FALSE, fileEncoding = "UTF-8-BOM", check.names = FALSE,
    colClasses = "character"
  )
  if (!identical(names(data), expected_columns)) stop(context, " CSV schema mismatch.")
  data
}

standard_allowed_estimands <- function(analysis) {
  values <- "visit_lsmean"
  if (isTRUE(analysis$estimands$treatment_visit_lsmeans)) values <- c(values, "treatment_visit_lsmean")
  if (isTRUE(analysis$estimands$pairwise_differences)) values <- c(values, "treatment_pairwise_difference")
  values
}

standard_validate_result_identity <- function(data, analysis, context) {
  if (!nrow(data)) return(invisible(TRUE))
  expected_groups <- vapply(analysis$groups, `[[`, character(1), "id")
  invalid <- is.na(data$analysis_id) | as.character(data$analysis_id) != analysis$analysis_id |
    is.na(data$tfl_id) | as.character(data$tfl_id) != analysis$tfl_id |
    is.na(data$analysis_group_id) | !as.character(data$analysis_group_id) %in% expected_groups |
    is.na(data$estimand) | !as.character(data$estimand) %in% standard_allowed_estimands(analysis)
  if (any(invalid)) stop(context, " identity/estimand does not match execution contract.")
  invisible(TRUE)
}

standard_validate_model_rds <- function(model_path, expected_identity, model_file) {
  if (!requireNamespace("callr", quietly = TRUE)) stop("model RDS validation requires callr.")
  result <- tryCatch(callr::r(
    function(path, expected) {
      model <- readRDS(path)
      if (!inherits(model, "mmrm")) return(list(valid = FALSE, message = "object is not mmrm"))
      identity <- attr(model, "standard_artifact_identity", exact = TRUE)
      if (!is.list(identity)) return(list(valid = FALSE, message = "missing standard_artifact_identity"))
      missing <- setdiff(names(expected), names(identity))
      if (length(missing)) return(list(valid = FALSE, message = paste("identity missing", paste(missing, collapse = ", "))))
      mismatch <- names(expected)[!vapply(names(expected), function(name) {
        identical(as.character(identity[[name]]), as.character(expected[[name]]))
      }, logical(1))]
      if (length(mismatch)) return(list(valid = FALSE, message = paste("identity mismatch", paste(mismatch, collapse = ", "))))
      actual_formula <- tryCatch({
        formula_parts <- stats::formula(model)
        formula_object <- if (is.list(formula_parts) && !is.null(formula_parts$formula)) formula_parts$formula else formula_parts
        paste(deparse(formula_object, width.cutoff = 500L), collapse = " ")
      }, error = function(e) conditionMessage(e))
      if (!identical(actual_formula, as.character(expected$formula))) {
        return(list(valid = FALSE, message = paste0("model formula mismatch; actual=", actual_formula, "; expected=", as.character(expected$formula))))
      }
      list(valid = TRUE, message = "")
    },
    args = list(path = model_path, expected = expected_identity), spinner = FALSE, show = FALSE
  ), error = function(e) e)
  if (inherits(result, "error")) stop("model RDS read/validation failed: ", model_file, "; ", conditionMessage(result))
  if (!is.list(result) || !isTRUE(result$valid)) stop("model RDS identity invalid: ", model_file, "; ", result$message)
  invisible(TRUE)
}

# manifest 的机械闸门：schema、closed set、逐 analysis 双语言覆盖、planned 状态、
# 结果路径只在允许的状态下出现，并且 R 行与 SAS 行绝不共享任何 artifact 文件名。
standard_validate_collector_manifest <- function(manifest, contract = NULL) {
  if (!is.data.frame(manifest) || !identical(names(manifest), standard_collector_manifest_columns())) {
    stop("COLLECTOR-MANIFEST-SCHEMA: manifest columns must match standard_collector_manifest_columns().")
  }
  if (!nrow(manifest)) stop("COLLECTOR-MANIFEST-EMPTY: manifest must contain one row per analysis and language.")
  character_frame <- as.data.frame(lapply(manifest, as.character), stringsAsFactors = FALSE)
  if (any(!character_frame$programming_language %in% c("R", "SAS"))) stop("COLLECTOR-MANIFEST-LANGUAGE: programming_language must be R or SAS.")
  if (any(!character_frame$execution_status %in% standard_collector_execution_status_values())) {
    stop("COLLECTOR-MANIFEST-STATUS: execution_status outside the closed set: ", paste(sort(unique(character_frame$execution_status)), collapse = ", "))
  }
  if (any(!character_frame$binding_mode %in% c("linked", "planned"))) stop("COLLECTOR-MANIFEST-BINDING: binding_mode must be linked or planned.")
  if (any(character_frame$tfl_type != "table") || any(character_frame$scope_status != "approved")) stop("COLLECTOR-MANIFEST-IDENTITY: tfl_type/scope_status invalid.")
  keys <- paste0(character_frame$analysis_id, "\u0001", character_frame$programming_language)
  if (anyDuplicated(keys)) stop("COLLECTOR-MANIFEST-DUPLICATE: each analysis must appear once per programming_language.")
  planned <- character_frame$binding_mode == "planned"
  if (any(planned & character_frame$execution_status != "code_generation_only")) {
    stop("COLLECTOR-MANIFEST-PLANNED: planned analyses must be registered as code_generation_only.")
  }
  if (any(!planned & character_frame$execution_status == "code_generation_only")) {
    stop("COLLECTOR-MANIFEST-LINKED: linked analyses must not be registered as code_generation_only.")
  }
  for (column in standard_collector_result_path_columns()) {
    filled <- nzchar(trimws(character_frame[[column]]))
    if (any(filled & !character_frame$execution_status %in% c("executed", "failed"))) {
      stop("COLLECTOR-MANIFEST-RESULT-PATH: ", column, " may only be filled for an imported executed/failed run record.")
    }
  }
  if (any(character_frame$execution_status == "executed" &
          (!nzchar(trimws(character_frame$raw_output_file)) | !nzchar(trimws(character_frame$final_tfl_file))))) {
    stop("COLLECTOR-MANIFEST-EXECUTED: executed rows must carry verified raw and final TFL paths.")
  }
  artifacts <- unlist(lapply(standard_collector_result_path_columns(), function(column) character_frame[[column]]), use.names = FALSE)
  artifacts <- basename(gsub("\\\\", "/", artifacts[nzchar(trimws(artifacts))]))
  if (anyDuplicated(tolower(artifacts))) {
    stop("COLLECTOR-MANIFEST-ARTIFACT-COLLISION: R and SAS rows must not share artifact filenames: ",
         paste(unique(artifacts[duplicated(tolower(artifacts))]), collapse = ", "))
  }
  if (!is.null(contract)) {
    expected <- vapply(contract$analyses, function(x) as.character(x$analysis_id), character(1))
    if (!setequal(unique(character_frame$analysis_id), expected) || nrow(manifest) != 2L * length(expected)) {
      stop("COLLECTOR-MANIFEST-COVERAGE: manifest must contain exactly one R row and one SAS row per approved analysis.")
    }
  }
  invisible(TRUE)
}

# 内部 engine（技术验证路径）的产物校验。9.3 对齐后，engine 侧 raw/final/diagnostic/
# run-record 文件名全部来自 contract 的 r_* 字段。
standard_validate_analysis_artifacts <- function(paths, chain, analysis, expected_invocation = NULL) {
  contract <- chain$contract
  output_paths <- analysis_output_paths(paths, analysis$analysis_id)
  engine_paths <- standard_engine_r_artifact_paths(output_paths, analysis)
  if (!file.exists(engine_paths$run_record)) stop("missing internal engine run record: ", basename(engine_paths$run_record))
  record <- standard_read_csv_schema(engine_paths$run_record, standard_required_run_record_columns(), "run record")
  if (nrow(record) != 1L) stop("run record must have exactly one row.")
  scalar <- function(name) as.character(record[[name]][[1]])
  expected_record <- c(
    study_id = as.character(contract$study$study_id), analysis_id = analysis$analysis_id,
    tfl_id = analysis$tfl_id, tfl_type = "table", title = analysis$title, scope_status = "approved",
    profile_version = standard_mmrm_profile_version()
  )
  mismatch <- names(expected_record)[!vapply(names(expected_record), function(name) identical(scalar(name), expected_record[[name]]), logical(1))]
  if (length(mismatch)) stop("run record identity mismatch: ", paste(mismatch, collapse = ", "))
  if (!identical(toupper(scalar("review_sha256")), toupper(chain$review$sha256)) ||
      !identical(toupper(scalar("analysis_plan_sha256")), toupper(attr(chain$plan, "sha256"))) ||
      !identical(toupper(scalar("approval_payload_sha256")), toupper(chain$approval_payload_sha256)) ||
      !identical(toupper(scalar("contract_sha256")), toupper(chain$contract_sha256))) {
    stop("run record approval-plan-contract identity mismatch.")
  }
  if (!nzchar(scalar("run_id")) || !nzchar(scalar("invocation_id"))) stop("run record run/invocation identity missing.")
  if (!is.null(expected_invocation) && !identical(scalar("invocation_id"), expected_invocation)) stop("run record invocation mismatch.")
  if (!scalar("output_status") %in% standard_allowed_run_status() || !scalar("computational_risk") %in% standard_allowed_risk()) {
    stop("run record status/risk invalid.")
  }

  expected_paths <- c(
    diagnostic_file = project_relative_path(engine_paths$diagnostic, paths$project_dir),
    diagnostic_report = project_relative_path(output_paths$diagnostic_report, paths$project_dir),
    log_file = project_relative_path(output_paths$log_file, paths$project_dir),
    raw_output_file = project_relative_path(engine_paths$raw, paths$project_dir),
    final_tfl_file = project_relative_path(engine_paths$final, paths$project_dir)
  )
  for (field in names(expected_paths)) {
    if (!identical(gsub("\\\\", "/", scalar(field)), expected_paths[[field]])) stop("run record path mismatch: ", field)
    standard_artifact_absolute(scalar(field), paths$project_dir, output_paths$root)
  }

  raw <- standard_read_csv_schema(
    standard_artifact_absolute(scalar("raw_output_file"), paths$project_dir, output_paths$root),
    standard_required_raw_columns(), "raw output"
  )
  final <- standard_read_csv_schema(
    standard_artifact_absolute(scalar("final_tfl_file"), paths$project_dir, output_paths$root),
    standard_required_final_columns(), "final output"
  )
  successful <- scalar("output_status") %in% c("complete", "partial")
  if (successful && (nrow(raw) < 1L || nrow(final) < 1L)) stop("complete/partial raw/final CSV must have at least one row.")
  if (!successful && !identical(scalar("output_status"), "fit_failed") && (nrow(raw) != 0L || nrow(final) != 0L)) stop("blocked status raw/final CSV must keep 0-row schema.")
  if (identical(scalar("output_status"), "fit_failed") && nrow(raw) != 0L) stop("fit_failed raw inference CSV must keep 0-row schema.")
  standard_validate_result_identity(raw, analysis, "raw output")
  standard_validate_result_identity(final, analysis, "final output")

  diagnostics <- standard_read_csv_schema(engine_paths$diagnostic, standard_required_diagnostic_columns(), "diagnostics")
  if (nrow(diagnostics) == 0L) stop("diagnostics must not be empty.")
  diagnostic_mismatch <-
    is.na(diagnostics$study_id) | as.character(diagnostics$study_id) != as.character(contract$study$study_id) |
    is.na(diagnostics$analysis_id) | as.character(diagnostics$analysis_id) != analysis$analysis_id |
    is.na(diagnostics$profile_version) | as.character(diagnostics$profile_version) != standard_mmrm_profile_version() |
    is.na(diagnostics$run_id) | as.character(diagnostics$run_id) != scalar("run_id") |
    is.na(diagnostics$invocation_id) | as.character(diagnostics$invocation_id) != scalar("invocation_id") |
    is.na(diagnostics$review_sha256) | toupper(as.character(diagnostics$review_sha256)) != toupper(chain$review$sha256) |
    is.na(diagnostics$analysis_plan_sha256) | toupper(as.character(diagnostics$analysis_plan_sha256)) != toupper(attr(chain$plan, "sha256")) |
    is.na(diagnostics$approval_payload_sha256) | toupper(as.character(diagnostics$approval_payload_sha256)) != toupper(chain$approval_payload_sha256) |
    is.na(diagnostics$contract_sha256) | toupper(as.character(diagnostics$contract_sha256)) != toupper(chain$contract_sha256)
  if (any(diagnostic_mismatch)) stop("diagnostics identity mismatch.")
  if (any(!as.character(diagnostics$run_status) %in% standard_allowed_run_status()) ||
      any(!as.character(diagnostics$failure_domain) %in% standard_allowed_failure_domain()) ||
      any(is.na(diagnostics$failure_phase) | !nzchar(trimws(as.character(diagnostics$failure_phase)))) ||
      any(!as.character(diagnostics$computational_risk) %in% standard_allowed_risk())) stop("diagnostics status/failure/risk invalid.")
  if (!identical(standard_collapse_status(as.character(diagnostics$run_status)), scalar("output_status")) ||
      !identical(standard_highest_risk(as.character(diagnostics$computational_risk)), scalar("computational_risk"))) {
    stop("run record and diagnostics status/risk mismatch.")
  }
  expected_groups <- vapply(analysis$groups, `[[`, character(1), "id")
  observed_groups <- sort(unique(as.character(diagnostics$analysis_group_id)))
  if (successful && !identical(observed_groups, sort(expected_groups))) stop("diagnostics group catalog mismatch.")
  if (!successful && !all(observed_groups %in% c("ALL", expected_groups))) stop("failure diagnostics group identity invalid.")

  fitted <- !is.na(diagnostics$model_file) & nzchar(as.character(diagnostics$model_file))
  if (successful && !any(fitted)) stop("complete/partial diagnostics must include a fitted model RDS.")
  if (any(!fitted & as.character(diagnostics$run_status) %in% c("complete", "partial"))) stop("successful group missing model RDS.")
  if (nrow(raw)) {
    result_models <- unique(as.character(raw$model_rds))
    diagnostic_models <- unique(as.character(diagnostics$model_file[fitted]))
    if (any(is.na(result_models) | !nzchar(result_models)) || !identical(sort(result_models), sort(diagnostic_models))) {
      stop("raw output and diagnostics model RDS mismatch.")
    }
  }
  for (i in which(fitted)) {
    model_file <- as.character(diagnostics$model_file[[i]])
    covariance <- as.character(diagnostics$final_covariance[[i]])
    expected_identity <- list(
      study_id = as.character(contract$study$study_id), analysis_id = analysis$analysis_id,
      group_id = as.character(diagnostics$analysis_group_id[[i]]),
      profile = standard_mmrm_profile_version(), profile_version = standard_mmrm_profile_version(),
      review_sha256 = toupper(chain$review$sha256), analysis_plan_sha256 = toupper(attr(chain$plan, "sha256")),
      approval_payload_sha256 = toupper(chain$approval_payload_sha256), contract_sha256 = toupper(chain$contract_sha256),
      adapter_sha256 = if (is.null(analysis$adapter_sha256)) "" else toupper(analysis$adapter_sha256),
      run_id = scalar("run_id"), invocation_id = scalar("invocation_id"),
      treatment_levels = if (is.null(analysis$treatment)) "" else paste(analysis$treatment$levels, collapse = "|"),
      treatment_reference = if (is.null(analysis$treatment)) "" else analysis$treatment$reference,
      treatment_comparator = if (is.null(analysis$treatment)) "" else analysis$treatment$comparator,
      contrast_direction = if (is.null(analysis$treatment)) "" else analysis$treatment$contrast_direction,
      confidence_level = if (is.null(analysis$treatment)) "" else as.character(analysis$treatment$confidence_level),
      multiplicity_adjustment = if (is.null(analysis$treatment)) "" else analysis$treatment$multiplicity_adjustment,
      covariance = covariance, formula = standard_formula_text(standard_fixed_formula(analysis, covariance))
    )
    model_path <- standard_artifact_absolute(model_file, paths$project_dir, output_paths$root)
    standard_validate_model_rds(model_path, expected_identity, model_file)
  }

  if (!file.exists(output_paths$recode_audit)) stop("missing identity-bound recode audit artifact: ", analysis$analysis_id)
  recode_audit <- standard_read_csv_schema(output_paths$recode_audit, names(standard_recode_audit_schema()), "recode audit")
  expected_recode_ids <- if (is.null(analysis$derivations)) character() else vapply(analysis$derivations, function(d) as.character(d$id), character(1))
  if (nrow(recode_audit)) {
    recode_mismatch <-
      is.na(recode_audit$study_id) | as.character(recode_audit$study_id) != as.character(contract$study$study_id) |
      is.na(recode_audit$analysis_id) | as.character(recode_audit$analysis_id) != analysis$analysis_id |
      is.na(recode_audit$profile_version) | as.character(recode_audit$profile_version) != standard_mmrm_profile_version() |
      is.na(recode_audit$run_id) | as.character(recode_audit$run_id) != scalar("run_id") |
      is.na(recode_audit$invocation_id) | as.character(recode_audit$invocation_id) != scalar("invocation_id") |
      is.na(recode_audit$review_sha256) | toupper(as.character(recode_audit$review_sha256)) != toupper(chain$review$sha256) |
      is.na(recode_audit$analysis_plan_sha256) | toupper(as.character(recode_audit$analysis_plan_sha256)) != toupper(attr(chain$plan, "sha256")) |
      is.na(recode_audit$approval_payload_sha256) | toupper(as.character(recode_audit$approval_payload_sha256)) != toupper(chain$approval_payload_sha256) |
      is.na(recode_audit$contract_sha256) | toupper(as.character(recode_audit$contract_sha256)) != toupper(chain$contract_sha256)
    if (any(recode_mismatch)) stop("recode audit identity mismatch.")
    if (anyDuplicated(as.character(recode_audit$recode_id))) stop("recode audit recode_id must be unique.")
    if (any(!as.character(recode_audit$unmatched_policy) %in% c("error", "preserve", "set_missing")) ||
        any(!as.character(recode_audit$missing_policy) %in% c("error", "preserve", "set_missing")) ||
        any(!as.character(recode_audit$value_type) %in% c("character", "numeric", "logical"))) {
      stop("recode audit policy/value_type invalid.")
    }
    count_columns <- c("input_count", "matched_count", "unmatched_count", "missing_count", "output_missing_count")
    counts <- lapply(count_columns, function(name) suppressWarnings(as.integer(recode_audit[[name]])))
    names(counts) <- count_columns
    if (any(vapply(counts, function(x) any(is.na(x) | x < 0L), logical(1)))) stop("recode audit counts must be nonnegative integers.")
    if (any(counts$matched_count + counts$unmatched_count + counts$missing_count != counts$input_count) ||
        any(counts$matched_count + counts$unmatched_count > counts$input_count) ||
        any(counts$output_missing_count > counts$input_count)) {
      stop("recode audit aggregate counts are inconsistent.")
    }
  }
  successful_recode <- scalar("output_status") %in% c("complete", "partial")
  if (successful_recode && (!setequal(as.character(recode_audit$recode_id), expected_recode_ids) || nrow(recode_audit) != length(expected_recode_ids))) {
    stop("recode audit must record each approved recode exactly once for a successful run: ", analysis$analysis_id)
  }
  if (nrow(recode_audit) && any(!as.character(recode_audit$recode_id) %in% expected_recode_ids)) stop("recode audit references an unapproved recode: ", analysis$analysis_id)

  list(record = record, diagnostics = diagnostics, raw = raw, final = final, recode_audit = recode_audit)
}


# ==============================================================================
# Phase 6：自包含 collector（9.1）与 manifest builder（9.2）
# ==============================================================================
# 本 collector 的全部职责：
#   1. 在已批准的 approval chain 下，校验磁盘上的一一对应程序集合（每个 analysis 恰好
#      一个 .R 和一个 .sas，且逐个通过 conformance 校验）；
#   2. 按规范化 R program filename 升序逐个 analysis 处理；
#   3. 逐 analysis 判定 binding mode：planned 只登记 code_generation_only 且绝不启动 R；
#      linked 才用 Rscript 子进程运行对应 .R；不从任一 analysis 推导整个 study 的模式；
#   4. 只通过 Phase 2/3 固定路径接口（--input-dir/--output-dir）传路径，不改程序正文、
#      不传任何统计语义；
#   5. 导入 language-specific run record（identity 全部核对通过才填结果路径），
#      构建全局 tfl-output-manifest.csv。
#
# 本 collector 从不 source 共享 engine、从不调用 run_standard_mmrm_analysis，
# 也从不调用任何 SAS 可执行文件：SAS 只是代码交付物，由统计师在自己的 SAS 环境中运行，
# 之后 collect-only 模式才导入其 run record。

standard_collector_locate_project_dir <- function(script_file) {
  current <- dirname(normalizePath(script_file, winslash = "/", mustWork = TRUE))
  repeat {
    if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "standard_artifacts.R"))) {
      return(normalizePath(current, winslash = "/", mustWork = TRUE))
    }
    parent <- dirname(current)
    if (identical(parent, current)) stop("COLLECTOR-PROJECT-ROOT: cannot locate project root from ", script_file)
    current <- parent
  }
}

standard_collector_file_sha256 <- function(path) {
  if (!requireNamespace("digest", quietly = TRUE)) stop("COLLECTOR-PACKAGE: digest is required to record program SHA-256.")
  toupper(digest::digest(file = path, algo = "sha256"))
}

standard_collector_rscript <- function() {
  candidates <- c(
    file.path(R.home("bin"), if (identical(.Platform$OS.type, "windows")) "Rscript.exe" else "Rscript"),
    file.path(R.home("bin"), "x64", "Rscript.exe"),
    unname(Sys.which("Rscript"))
  )
  candidates <- candidates[nzchar(candidates) & file.exists(candidates)]
  if (!length(candidates)) stop("COLLECTOR-RSCRIPT: cannot resolve an Rscript executable for subprocess execution.")
  candidates[[1L]]
}

# 唯一的子进程启动点。它只启动 Rscript，且只传递固定路径接口参数。
# 自检脚本可以覆盖本函数以机械记录“哪些程序被真正调用、按什么顺序调用”。
standard_collector_invoke_r_program <- function(rscript, program_path, input_dir, output_dir, log_path) {
  output <- suppressWarnings(system2(
    rscript,
    c("--vanilla", shQuote(program_path), "--input-dir", shQuote(input_dir), "--output-dir", shQuote(output_dir)),
    stdout = TRUE, stderr = TRUE, wait = TRUE
  ))
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L
  if (length(output)) cat(paste0("    | ", output, collapse = "\n"), "\n", file = log_path, append = TRUE, sep = "")
  as.integer(status)
}

# coverage 已验证的一一对应程序集合：读取磁盘上的真实程序文本，先做 coverage 校验，
# 再逐个用真实 conformance validator 对照批准 contract 派生的 IR。任一不符即整体阻断。
standard_collector_program_set <- function(paths, contract, chain, project_dir) {
  analysis_generation_ensure_program_helpers(project_dir)
  identities <- analysis_generation_identities(contract, chain$approval_payload_sha256, chain$contract_sha256)
  rows <- lapply(contract$analyses, function(analysis) {
    analysis_id <- as.character(analysis$analysis_id)
    safe <- standard_contract_safe_identity(analysis_id)
    data.frame(
      analysis_id = analysis_id, safe_analysis_id = safe, tfl_id = as.character(analysis$tfl_id),
      binding_mode = as.character(analysis$dataset$binding_mode),
      r_program = file.path(paths$r_analysis_dir, paste0(safe, ".R")),
      sas_program = file.path(paths$sas_analysis_dir, paste0(safe, ".sas")),
      r_basename = paste0(safe, ".R"), sas_basename = paste0(safe, ".sas"),
      stringsAsFactors = FALSE
    )
  })
  programs <- do.call(rbind, rows)
  missing <- c(programs$r_program, programs$sas_program)
  missing <- missing[!file.exists(missing)]
  if (length(missing)) stop("COLLECTOR-PROGRAM-SET-MISSING: ", paste(basename(missing), collapse = ", "))
  extra_r <- setdiff(list.files(paths$r_analysis_dir, pattern = "[.][Rr]$"), c(programs$r_basename, "run_all_mmrm.R"))
  extra_sas <- setdiff(list.files(paths$sas_analysis_dir, pattern = "[.]sas$"), programs$sas_basename)
  if (length(c(extra_r, extra_sas))) stop("COLLECTOR-PROGRAM-SET-EXTRA: ", paste(c(extra_r, extra_sas), collapse = ", "))
  texts <- list()
  for (i in seq_len(nrow(programs))) {
    texts[[programs$r_program[[i]]]] <- paste0(paste(readLines(programs$r_program[[i]], warn = FALSE, encoding = "UTF-8"), collapse = "\n"), "\n")
    texts[[programs$sas_program[[i]]]] <- paste0(paste(readLines(programs$sas_program[[i]], warn = FALSE, encoding = "UTF-8"), collapse = "\n"), "\n")
  }
  validate_tfl_program_coverage(contract, texts)
  for (i in seq_len(nrow(programs))) {
    analysis <- standard_contract_get_analysis(contract, programs$analysis_id[[i]])
    ir <- build_program_generation_ir(contract, analysis, identities)
    validate_generated_r_program(texts[[programs$r_program[[i]]]], ir)
    validate_generated_sas_program(texts[[programs$sas_program[[i]]]], ir)
  }
  programs[order(programs$r_basename, method = "radix"), , drop = FALSE]
}

# linked analysis 的输入目录只来自批准 contract 里的 relative_path，collector 不猜测、
# 不改写、也不向程序传递任何统计语义。
standard_collector_input_dir <- function(analysis, project_dir) {
  relative_path <- as.character(analysis$dataset$relative_path)
  absolute <- normalize_project_relative_path(relative_path, project_dir, "dataset.relative_path")
  if (!file.exists(absolute)) stop("COLLECTOR-INPUT-MISSING: approved linked dataset does not exist: ", relative_path)
  dirname(normalizePath(absolute, winslash = "/", mustWork = TRUE))
}

standard_collector_language_output_names <- function(analysis, language) {
  prefix <- if (identical(language, "R")) "r_" else "sas_"
  list(
    raw = as.character(analysis$output[[paste0(prefix, "raw_file")]]),
    final = as.character(analysis$output[[paste0(prefix, "final_file")]]),
    diagnostic = as.character(analysis$output[[paste0(prefix, "diagnostic_file")]]),
    run_record = as.character(analysis$output[[paste0(prefix, "run_record_file")]])
  )
}

# run record 导入闸门。返回 list(ok, reason, record)。任一 identity / 路径 / artifact
# 校验不通过都返回 ok=FALSE，调用方据此登记 blocked 且不填任何结果路径。
standard_collector_validate_run_record <- function(analysis, contract, chain, language, output_dir) {
  names_expected <- standard_collector_language_output_names(analysis, language)
  record_path <- file.path(output_dir, names_expected$run_record)
  fail <- function(reason) list(ok = FALSE, reason = reason, record = NULL)
  if (!file.exists(record_path)) return(fail(paste0("run record 不存在：", names_expected$run_record)))
  record <- tryCatch(read_utf8_bom_csv(record_path), error = function(e) e)
  if (inherits(record, "error")) return(fail(paste0("run record 无法读取：", conditionMessage(record))))
  if (!identical(names(record), standard_collector_run_record_columns())) return(fail("run record 列结构与生成程序接口不一致"))
  if (nrow(record) != 1L) return(fail("run record 必须恰好一行"))
  record[] <- lapply(record, function(column) { value <- as.character(column); value[is.na(value)] <- ""; value })
  scalar <- function(name) {
    value <- record[[name]][[1L]]
    if (is.na(value)) "" else as.character(value)
  }
  expected_identity <- c(
    study_id = as.character(contract$study$study_id),
    analysis_id = as.character(analysis$analysis_id),
    tfl_id = as.character(analysis$tfl_id),
    programming_language = language,
    profile_version = standard_mmrm_profile_version(),
    dataset_binding_mode = as.character(analysis$dataset$binding_mode)
  )
  mismatch <- names(expected_identity)[!vapply(names(expected_identity), function(name) identical(scalar(name), expected_identity[[name]]), logical(1))]
  if (length(mismatch)) return(fail(paste0("run record identity 不符：", paste(mismatch, collapse = ", "))))
  expected_hashes <- c(
    plan_sha256 = toupper(as.character(contract$approval$analysis_plan_sha256)),
    approval_payload_sha256 = toupper(as.character(chain$approval_payload_sha256)),
    contract_sha256 = toupper(as.character(chain$contract_sha256))
  )
  hash_mismatch <- names(expected_hashes)[!vapply(names(expected_hashes), function(name) identical(toupper(scalar(name)), expected_hashes[[name]]), logical(1))]
  if (length(hash_mismatch)) return(fail(paste0("run record plan/approval/contract 指纹不符：", paste(hash_mismatch, collapse = ", "))))
  if (identical(as.character(analysis$dataset$binding_mode), "linked")) {
    if (!identical(toupper(scalar("actual_input_sha256")), toupper(as.character(analysis$dataset$sha256)))) {
      return(fail("run record actual_input_sha256 与批准的输入 SHA-256 不符"))
    }
  }
  if (!scalar("execution_status") %in% c("executed", "failed")) return(fail(paste0("run record execution_status 非法：", scalar("execution_status"))))
  if (!nzchar(trimws(scalar("run_status")))) return(fail("run record run_status 缺失"))
  if (!scalar("computational_risk") %in% c("Not assessed", "Green", "Yellow", "Red")) return(fail("run record computational_risk 非法"))
  declared <- c(diagnostic_file = names_expected$diagnostic, run_record_file = names_expected$run_record)
  declared_mismatch <- names(declared)[!vapply(names(declared), function(name) identical(scalar(name), declared[[name]]), logical(1))]
  if (length(declared_mismatch)) return(fail(paste0("run record 声明的产物文件名与 contract 不符：", paste(declared_mismatch, collapse = ", "))))
  if (!file.exists(file.path(output_dir, names_expected$diagnostic))) return(fail("run record 声明的 diagnostic 文件不存在"))
  if (identical(scalar("execution_status"), "executed")) {
    if (!identical(scalar("raw_output_file"), names_expected$raw) || !identical(scalar("final_output_file"), names_expected$final)) {
      return(fail("executed run record 的 raw/final 文件名与 contract 不符"))
    }
    for (name in c(names_expected$raw, names_expected$final)) {
      target <- file.path(output_dir, name)
      if (!file.exists(target) || is.na(file.size(target)) || file.size(target) <= 0) return(fail(paste0("executed run record 声明的结果文件不存在或为空：", name)))
    }
  } else {
    if (nzchar(scalar("raw_output_file")) && !identical(scalar("raw_output_file"), names_expected$raw)) return(fail("failed run record 的 raw 文件名与 contract 不符"))
    if (nzchar(scalar("final_output_file")) && !identical(scalar("final_output_file"), names_expected$final)) return(fail("failed run record 的 final 文件名与 contract 不符"))
  }
  list(ok = TRUE, reason = "", record = record)
}

standard_collector_manifest_row <- function(values) {
  columns <- standard_collector_manifest_columns()
  missing <- setdiff(columns, names(values))
  for (name in missing) values[[name]] <- ""
  frame <- as.data.frame(lapply(columns, function(name) as.character(values[[name]])), stringsAsFactors = FALSE)
  names(frame) <- columns
  frame
}

standard_collector_build_row <- function(analysis, contract, chain, paths, project_dir, language, program_path, output_dir,
                                         mode, attempted, exit_status, collected_at_utc) {
  binding_mode <- as.character(analysis$dataset$binding_mode)
  names_expected <- standard_collector_language_output_names(analysis, language)
  relative <- function(name) project_relative_path(file.path(output_dir, name), project_dir)
  base <- list(
    study_id = as.character(contract$study$study_id), analysis_id = as.character(analysis$analysis_id),
    tfl_id = as.character(analysis$tfl_id), tfl_type = "table", title = as.character(analysis$title),
    scope_status = "approved", programming_language = language, binding_mode = binding_mode,
    program_file = project_relative_path(program_path, project_dir),
    program_sha256 = standard_collector_file_sha256(program_path),
    plan_sha256 = toupper(as.character(contract$approval$analysis_plan_sha256)),
    approval_payload_sha256 = toupper(as.character(chain$approval_payload_sha256)),
    contract_sha256 = toupper(as.character(chain$contract_sha256)),
    expected_input_sha256 = if (identical(binding_mode, "linked")) toupper(as.character(analysis$dataset$sha256)) else "",
    collector_mode = mode, collected_at_utc = collected_at_utc
  )
  if (identical(binding_mode, "planned")) {
    return(standard_collector_manifest_row(c(base, list(
      execution_status = "code_generation_only", run_status = "not_run", computational_risk = "Not assessed",
      note = paste0(language, " 程序已生成并保留完整代码；planned analysis 为 code-generation-only，collector 未执行任何分析。")
    ))))
  }
  record_exists <- file.exists(file.path(output_dir, names_expected$run_record))
  if (!record_exists) {
    if (identical(language, "SAS")) {
      return(standard_collector_manifest_row(c(base, list(
        execution_status = "program_generated_not_executed", run_status = "not_run", computational_risk = "Not assessed",
        note = "SAS 程序已生成但尚未由统计师在 SAS 环境中运行；collector 从不执行 SAS。"
      ))))
    }
    if (!attempted) {
      return(standard_collector_manifest_row(c(base, list(
        execution_status = "program_generated_not_executed", run_status = "not_run", computational_risk = "Not assessed",
        note = "collect-only 模式未运行 R 程序，且尚无 R run record 可导入。"
      ))))
    }
    return(standard_collector_manifest_row(c(base, list(
      execution_status = "blocked", run_status = "unknown", computational_risk = "Red",
      note = paste0("R 程序以退出码 ", exit_status, " 结束且未写出 run record；结果路径留空。")
    ))))
  }
  validation <- standard_collector_validate_run_record(analysis, contract, chain, language, output_dir)
  if (!isTRUE(validation$ok)) {
    return(standard_collector_manifest_row(c(base, list(
      execution_status = "blocked", run_status = "unknown", computational_risk = "Red",
      note = paste0("run record identity 校验失败，结果路径留空：", validation$reason)
    ))))
  }
  record <- validation$record
  scalar <- function(name) {
    value <- record[[name]][[1L]]
    if (is.na(value)) "" else as.character(value)
  }
  executed <- identical(scalar("execution_status"), "executed")
  note <- if (identical(language, "SAS")) {
    "已导入统计师在 SAS 环境中运行后产出的 SAS run record；collector 未执行 SAS。"
  } else if (attempted) {
    paste0("collector 以固定路径接口运行 R 程序，退出码 ", exit_status, "。")
  } else {
    "collect-only 模式导入既有 R run record。"
  }
  standard_collector_manifest_row(c(base, list(
    execution_status = scalar("execution_status"), run_status = scalar("run_status"),
    computational_risk = scalar("computational_risk"),
    raw_output_file = if (executed) relative(names_expected$raw) else "",
    final_tfl_file = if (executed) relative(names_expected$final) else "",
    diagnostic_file = relative(names_expected$diagnostic),
    run_record_file = relative(names_expected$run_record),
    actual_input_sha256 = toupper(scalar("actual_input_sha256")),
    note = note
  )))
}

run_self_contained_mmrm_collector <- function(script_file, pinned_approval_payload_sha256, pinned_contract_sha256, mode = "run-and-collect") {
  if (!is.character(mode) || length(mode) != 1L || !mode %in% c("run-and-collect", "collect-only")) {
    stop("COLLECTOR-MODE: mode must be run-and-collect or collect-only.")
  }
  project_dir <- standard_collector_locate_project_dir(script_file)
  paths <- study_paths(script_file)
  chain <- assert_approved_analysis(
    paths$study_dir, project_dir,
    pinned_approval_payload_sha256 = pinned_approval_payload_sha256,
    pinned_contract_sha256 = pinned_contract_sha256
  )
  contract <- chain$contract
  standard_contract_assert_output_closed_shape(contract)
  programs <- standard_collector_program_set(paths, contract, chain, project_dir)
  dir.create(paths$output_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(paths$log_output_dir, recursive = TRUE, showWarnings = FALSE)
  collector_log <- file.path(paths$log_output_dir, "run_all_mmrm.log")
  writeLines(character(), collector_log, useBytes = TRUE)
  add_log <- function(...) cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " | ", paste0(..., collapse = ""), "\n", file = collector_log, append = TRUE, sep = "")
  collected_at_utc <- format(Sys.time(), tz = "UTC", format = "%Y-%m-%dT%H:%M:%SZ")
  add_log("collector start; mode=", mode, "; profile=", standard_mmrm_profile_version())
  add_log("collector never executes SAS; SAS programs are code deliverables imported through their own run record only.")
  add_log("program order (normalized R filename ascending): ", paste(programs$r_basename, collapse = ", "))
  rscript <- if (identical(mode, "run-and-collect") && any(programs$binding_mode == "linked")) standard_collector_rscript() else ""
  rows <- list()
  for (i in seq_len(nrow(programs))) {
    analysis_id <- programs$analysis_id[[i]]
    analysis <- standard_contract_get_analysis(contract, analysis_id)
    binding_mode <- as.character(analysis$dataset$binding_mode)
    output_dir <- file.path(paths$analysis_output_dir, programs$safe_analysis_id[[i]])
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
    attempted <- FALSE
    exit_status <- NA_integer_
    if (identical(binding_mode, "planned")) {
      add_log(programs$r_basename[[i]], " analysis=", analysis_id, " binding_mode=planned; code_generation_only; Rscript subprocess not invoked")
    } else if (identical(mode, "run-and-collect")) {
      input_dir <- standard_collector_input_dir(analysis, project_dir)
      add_log(programs$r_basename[[i]], " analysis=", analysis_id, " binding_mode=linked; invoke Rscript; input_dir=",
              project_relative_path(input_dir, project_dir), "; output_dir=", project_relative_path(output_dir, project_dir))
      attempted <- TRUE
      exit_status <- standard_collector_invoke_r_program(rscript, programs$r_program[[i]], input_dir, output_dir, collector_log)
      add_log(programs$r_basename[[i]], " analysis=", analysis_id, " exit=", exit_status)
    } else {
      add_log(programs$r_basename[[i]], " analysis=", analysis_id, " binding_mode=linked; collect-only; Rscript subprocess not invoked")
    }
    for (language in c("R", "SAS")) {
      program_path <- if (identical(language, "R")) programs$r_program[[i]] else programs$sas_program[[i]]
      row <- standard_collector_build_row(
        analysis, contract, chain, paths, project_dir, language, program_path, output_dir,
        mode, attempted && identical(language, "R"), exit_status, collected_at_utc
      )
      add_log("  manifest row analysis=", analysis_id, " language=", language, " execution_status=", row$execution_status[[1L]])
      rows[[length(rows) + 1L]] <- row
    }
  }
  manifest <- do.call(rbind, rows)
  standard_validate_collector_manifest(manifest, contract)
  write_utf8_bom_csv(manifest, paths$output_manifest)
  add_log("manifest written: ", project_relative_path(paths$output_manifest, project_dir))
  summary_lines <- c(
    "# Standard MMRM collector \u8fd0\u884c\u6c47\u603b", "",
    paste0("- \u8fd0\u884c\u6a21\u5f0f\uff1a`", mode, "`"),
    paste0("- Profile\uff1a`", standard_mmrm_profile_version(), "`"),
    paste0("- \u7a0b\u5e8f\u8fd0\u884c\u987a\u5e8f\uff08R \u7a0b\u5e8f\u6587\u4ef6\u540d\u5347\u5e8f\uff09\uff1a`", paste(programs$r_basename, collapse = ", "), "`"),
    paste0("- Collector \u4ece\u4e0d\u6267\u884c SAS\uff1aSAS \u53ea\u4f5c\u4e3a\u4ee3\u7801\u4ea4\u4ed8\u7269\u3002"), "",
    "| Analysis ID | TFL ID | \u8bed\u8a00 | Binding | Execution status | Run status | Final TFL |",
    "|---|---|---|---|---|---|---|",
    vapply(seq_len(nrow(manifest)), function(i) paste0(
      "| `", manifest$analysis_id[[i]], "` | `", manifest$tfl_id[[i]], "` | `", manifest$programming_language[[i]],
      "` | `", manifest$binding_mode[[i]], "` | `", manifest$execution_status[[i]], "` | `", manifest$run_status[[i]],
      "` | `", manifest$final_tfl_file[[i]], "` |"
    ), character(1))
  )
  writeLines(summary_lines, paths$run_summary_file, useBytes = TRUE)
  blocked <- manifest$analysis_id[manifest$execution_status %in% c("blocked", "failed")]
  add_log("collector finished; blocked_or_failed=", if (length(blocked)) paste(unique(blocked), collapse = ", ") else "none")
  result <- list(manifest = manifest, mode = mode, order = programs$r_basename, log_file = collector_log,
                 manifest_file = paths$output_manifest)
  if (length(blocked)) {
    stop("COLLECTOR-BLOCKED: manifest/summary written; blocked or failed analyses: ", paste(unique(blocked), collapse = ", "))
  }
  invisible(result)
}
