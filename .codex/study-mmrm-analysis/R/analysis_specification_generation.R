analysis_specification_escape <- function(value) {
  gsub("[\r\n]+", " ", as.character(value))
}

analysis_specification_yaml_lines <- function(values) {
  stopifnot(requireNamespace("yaml", quietly = TRUE))
  strsplit(yaml::as.yaml(values), "\n", fixed = TRUE)[[1]]
}

analysis_specification_table_lines <- function(data) {
  if (!is.data.frame(data) || nrow(data) == 0L) return(character())
  c(
    paste0("| ", paste(names(data), collapse = " | "), " |"),
    paste0("|", paste(rep("---", length(names(data))), collapse = "|"), "|"),
    vapply(seq_len(nrow(data)), function(i) {
      paste0("| ", paste(vapply(data[i, , drop = FALSE], analysis_specification_escape, character(1)), collapse = " | "), " |")
    }, character(1))
  )
}

analysis_specification_mapping_gate <- function(review, study_dir) {
  metadata <- review$metadata
  scalar <- function(value) { text <- as.character(value); if (length(text)) trimws(text[[1L]]) else "" }
  relative_path <- scalar(metadata$endpoint_mapping_file)
  expected_sha <- toupper(scalar(metadata$endpoint_mapping_sha256))
  if (!nzchar(relative_path) || !grepl("^[A-F0-9]{64}$", expected_sha)) stop("statistical-review.md is missing a finalized endpoint mapping path or SHA-256.")
  path <- file.path(study_dir, "statistician-review", "endpoint-mapping.yaml")
  if (!file.exists(path) || !identical(toupper(specification_sha256(path)), expected_sha)) stop("endpoint-mapping.yaml SHA-256 does not match the finalized review.")
  endpoint_mapping_read(path)
}

analysis_specification_review_gate <- function(review) {
  metadata <- review$metadata
  ok <- identical(as.character(metadata$finalization_status), "ready_for_final_signature")
  if (!ok) stop("statistical-review.md must have finalization_status: ready_for_final_signature before specification generation.")
  invisible(TRUE)
}

analysis_specification_review_tables <- function(review) {
  mapping <- parse_statistical_review_table(
    statistical_review_section_lines(review, "## 4. Endpoint Mapping 与分组确认"),
    c("analysis_id", "source_tfl_id", "group_id", "endpoint_label", "endpoint_variable", "selected_codes", "selection_mode", "instrument / version / reporter / subscale", "row_allocation_rule", "source_ref", "review_status", "reviewer_note"),
    "Endpoint Mapping"
  )
  issues <- parse_statistical_review_table(
    statistical_review_section_lines(review, "## 7. 未解决问题与决议"),
    c("issue_id", "scope", "question_or_risk", "resolution", "status"),
    "Issues"
  )
  candidates <- parse_statistical_review_candidate_tables(review)
  list(mapping = mapping, issues = issues, candidates = candidates)
}

analysis_specification_candidate_summary <- function(candidates) {
  rows <- lapply(candidates, function(candidate) {
    table <- candidate$table
    data.frame(
      tfl_id = candidate$tfl_id,
      tfl_title = candidate$tfl_title,
      dataset = table[["AI 识别的候选规则"]][[1]],
      population = table[["AI 识别的候选规则"]][[2]],
      endpoint = table[["AI 识别的候选规则"]][[3]],
      response_baseline = table[["AI 识别的候选规则"]][[5]],
      visit = table[["AI 识别的候选规则"]][[6]],
      fixed_effects = table[["AI 识别的候选规则"]][[8]],
      covariance_df = table[["AI 识别的候选规则"]][[9]],
      estimand_output = table[["AI 识别的候选规则"]][[10]],
      statistician_decision = paste(unique(trimws(as.character(table[["统计师决定"]]))), collapse = "; "),
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
  })
  if (!length(rows)) {
    return(data.frame(stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

analysis_specification_infer_context <- function(review, project_dir) {
  source_file <- as.character(review$metadata$source_input_file)
  data <- list(
    compound = "unknown",
    data_availability = "available",
    data_classification = "unknown",
    intended_use = "code_generation"
  )
  if (!nzchar(source_file)) return(data)
  source_path <- tryCatch(normalize_project_relative_path(source_file, project_dir, "source_input_file"), error = function(e) NULL)
  if (is.null(source_path) || !file.exists(source_path) || tolower(tools::file_ext(source_path)) != "md") return(data)
  lines <- readLines(source_path, encoding = "UTF-8", warn = FALSE)
  blocks <- split(which(grepl("^\\s*\\|", lines)), cumsum(c(TRUE, diff(which(grepl("^\\s*\\|", lines))) != 1L)))
  for (block_index in blocks) {
    block <- lines[block_index]
    if (length(block) < 3L) next
    rows <- lapply(block[-c(1L, 2L)], function(line) trimws(strsplit(sub("^\\s*\\|\\s*", "", sub("\\|\\s*$", "", line)), "\\|")[[1]]))
    for (row in rows) {
      if (length(row) >= 2L && row[[1]] %in% names(data) && nzchar(row[[2]]) && !grepl("^<.*>$", row[[2]])) data[[row[[1]]]] <- row[[2]]
    }
  }
  if (!data$data_classification %in% c("none", "dummy", "production", "unknown")) data$data_classification <- "unknown"
  if (!data$intended_use %in% c("code_generation", "technical_validation", "formal_analysis")) data$intended_use <- if (data$data_classification == "unknown") "code_generation" else "technical_validation"
  data$data_availability <- if (data$data_classification == "none") "none" else "available"
  data
}

analysis_specification_body <- function(review, tables, project_dir) {
  mapping <- tables$mapping
  summary <- analysis_specification_candidate_summary(tables$candidates)
  analysis_ids <- sort(unique(trimws(as.character(mapping$analysis_id))))
  tfl_ids <- sort(unique(vapply(tables$candidates, `[[`, character(1), "tfl_id")))
  c(
    "## 1. 文件状态与使用规则",
    "本文件第 1-8 节为唯一 execution specification；R/SAS code generation 不得从 review、source 或 legacy artifact 补充未写入本文件的统计规则。",
    "",
    "## 2. Study 和数据上下文",
    paste0("Study ID：", as.character(review$metadata$study_id), "。Generation route：", as.character(review$metadata$generation_route), "。Source input：", as.character(review$metadata$source_input_file), "。"),
    "",
    "## 3. MMRM Analysis 清单",
    analysis_specification_table_lines(data.frame(analysis_id = analysis_ids, stringsAsFactors = FALSE)),
    "",
    "## 4. Analysis Specifications",
    analysis_specification_table_lines(summary),
    "",
    "Endpoint Mapping：",
    analysis_specification_table_lines(mapping),
    "",
    "## 5. TFL 输出清单",
    analysis_specification_table_lines(data.frame(tfl_id = tfl_ids, output_type = "table", source = "statistical-review section 3", stringsAsFactors = FALSE)),
    "",
    "## 6. SAS Template 生成要求",
    "为每个 approved Analysis ID 生成对应 SAS template；template 默认不执行，只有调用方显式启用时才访问数据。",
    "",
    "## 7. 运行与诊断报告要求",
    "运行时必须记录 model identity、covariance path、fallback、convergence、inference completeness、human-readable Chinese diagnostics 和 machine-readable diagnostics CSV。",
    "",
    "## 8. 完整 QC 要求",
    "执行输入 hash gate、review hash gate、Endpoint Mapping gate、重复记录检查、response/baseline/visit 缺失检查、模型收敛检查和输出 manifest 检查。",
    "",
    "## 9. 溯源附录",
    paste0("Review file：", project_relative_path(review$path, project_dir)),
    paste0("Review SHA-256：", toupper(review$sha256)),
    "",
    "## 10. 校验结果",
    "生成后必须运行 validate_analysis_specification.R。"
  )
}

analysis_specification_execution_sha_from_body <- function(body) {
  stopifnot(requireNamespace("digest", quietly = TRUE))
  end <- which(trimws(body) == "## 9. 溯源附录")
  execution <- if (length(end) == 1L) body[seq_len(end - 1L)] else body
  digest::digest(enc2utf8(paste(execution, collapse = "\n")), algo = "sha256", serialize = FALSE)
}

analysis_specification_safe_id <- function(value) {
  value <- gsub("[^A-Za-z0-9_-]+", "-", toupper(as.character(value)))
  value <- gsub("(^-+|-+$)", "", value)
  if (!nzchar(value)) "ID" else value
}

analysis_specification_not_applicable_dimensions <- function() {
  list(
    instrument = list(variable = "not_applicable", values = list()),
    version = list(variable = "not_applicable", values = list()),
    reporter = list(variable = "not_applicable", values = list()),
    subscale = list(variable = "not_applicable", values = list())
  )
}

analysis_specification_parse_dimensions <- function(value) {
  value <- trimws(as.character(value))
  if (!nzchar(value) || identical(value, "not_applicable")) return(analysis_specification_not_applicable_dimensions())
  result <- analysis_specification_not_applicable_dimensions()
  parts <- trimws(strsplit(value, ";", fixed = TRUE)[[1]])
  if (any(!nzchar(parts))) stop("Endpoint Mapping dimensions 包含空段。")
  for (part in parts) {
    key_match <- regexec("^([A-Za-z_]+)=(.+)$", part, perl = TRUE)
    key_group <- regmatches(part, key_match)[[1]]
    if (length(key_group) != 3L || !key_group[[2]] %in% names(result)) {
      stop("Endpoint Mapping dimensions 包含未知或无效维度：", part)
    }
    name <- key_group[[2]]
    encoded <- trimws(key_group[[3]])
    if (!identical(result[[name]]$variable, "not_applicable")) stop("Endpoint Mapping dimensions 重复声明维度：", name)
    if (identical(encoded, "not_applicable")) next
    list_match <- regexec("^([A-Za-z][A-Za-z0-9_]*)[:]\\[([^]]+)\\]$", encoded, perl = TRUE)
    list_group <- regmatches(encoded, list_match)[[1]]
    if (length(list_group) == 3L) {
      values <- trimws(strsplit(list_group[[3]], ",", fixed = TRUE)[[1]])
      if (any(!nzchar(values)) || anyDuplicated(values)) stop("Endpoint Mapping dimensions 列维度值必须非空且唯一：", part)
      if (identical(list_group[[2]], "fixed")) stop("Endpoint Mapping fixed 标签必须使用 name=value 形式：", part)
      result[[name]] <- list(variable = list_group[[2]], values = values)
    } else {
      if (!grepl("^[A-Za-z0-9_.-]+$", encoded, perl = TRUE) || identical(encoded, "fixed")) {
        stop("Endpoint Mapping fixed 标签无效：", part)
      }
      result[[name]] <- list(variable = "fixed", values = encoded)
    }
  }
  result
}

analysis_specification_mapping_tfl_index <- function(mapping, candidates) {
  required <- c("analysis_id", "source_tfl_id", "group_id")
  if (!all(required %in% names(mapping))) stop("Endpoint Mapping 缺少 source_tfl_id 外键列。")
  source_tfl_ids <- trimws(as.character(mapping$source_tfl_id))
  candidate_tfl_ids <- trimws(as.character(candidates$tfl_id))
  if (any(!nzchar(source_tfl_ids)) || any(!source_tfl_ids %in% candidate_tfl_ids)) {
    stop("Endpoint Mapping 的 source_tfl_id 必须精确引用 Section 3 中唯一存在的 TFL。")
  }
  by_analysis <- split(mapping, trimws(as.character(mapping$analysis_id)))
  analysis_tfl_ids <- vapply(by_analysis, function(rows) {
    values <- unique(trimws(as.character(rows$source_tfl_id)))
    if (length(values) != 1L) stop("同一 analysis_id 的所有 Endpoint Mapping 行必须引用同一 source_tfl_id。")
    values[[1L]]
  }, character(1))
  if (anyDuplicated(analysis_tfl_ids)) stop("每个 source_tfl_id 必须且只能对应一个 analysis_id。")
  if (!setequal(unname(analysis_tfl_ids), candidate_tfl_ids) || length(analysis_tfl_ids) != length(candidate_tfl_ids)) {
    stop("Section 3 TFL 集合必须与 Endpoint Mapping source_tfl_id 集合完全一致。")
  }
  list(by_analysis = by_analysis, analysis_tfl_ids = analysis_tfl_ids)
}

analysis_specification_contract <- function(review, tables) {
  mapping <- tables$mapping
  candidates <- analysis_specification_candidate_summary(tables$candidates)
  index <- analysis_specification_mapping_tfl_index(mapping, candidates)
  by_analysis <- index$by_analysis
  analyses <- lapply(names(by_analysis), function(analysis_id) {
    rows <- by_analysis[[analysis_id]]
    source_tfl_id <- index$analysis_tfl_ids[[analysis_id]]
    candidate <- candidates[match(source_tfl_id, candidates$tfl_id), , drop = FALSE]
    if (nrow(candidate) != 1L) stop("source_tfl_id 未能唯一解析为 Section 3 TFL：", source_tfl_id)
    tfl_id <- candidate$tfl_id[[1]]
    binding <- runtime_dataset_parse_binding(candidate$dataset[[1]])
    if (is.null(binding)) stop("Section 3 分析数据集必须是 finalizer 写入的完整 Runtime Dataset Binding。")
    population_filters <- statistical_review_parse_population_rule(candidate$population[[1]])
    selected_codes <- lapply(as.character(rows$selected_codes), statistical_review_selected_codes)
    groups <- lapply(seq_len(nrow(rows)), function(i) {
      operator <- if (length(selected_codes[[i]]) == 1L) "eq" else "in"
      value <- if (operator == "eq") selected_codes[[i]][[1]] else selected_codes[[i]]
      list(
        id = analysis_specification_safe_id(rows$group_id[[i]]),
        label = as.character(rows$endpoint_label[[i]]),
        predicates = list(list(variable = as.character(rows$endpoint_variable[[i]]), operator = operator, value = value))
      )
    })
    definitions <- lapply(seq_len(nrow(rows)), function(i) {
      list(
        group_id = analysis_specification_safe_id(rows$group_id[[i]]),
        endpoint_variable = as.character(rows$endpoint_variable[[i]]),
        selected_codes = selected_codes[[i]],
        selection_mode = as.character(rows$selection_mode[[i]]),
        dimensions = analysis_specification_parse_dimensions(rows[["instrument / version / reporter / subscale"]][[i]]),
        row_allocation_rule = as.character(rows$row_allocation_rule[[i]])
      )
    })
    safe_analysis <- analysis_specification_safe_id(analysis_id)
    list(
      analysis_id = analysis_id,
      tfl_id = tfl_id,
      title = rows$endpoint_label[[1]],
      dataset = binding,
      mappings = list(subject = "USUBJID", response = "CHG", baseline = "BASE", visit = "AVISITN"),
      filters = population_filters,
      groups = groups,
      endpoint_definitions = definitions,
      fixed_effects = c("visit", "baseline", "baseline_by_visit"),
      covariance = list(primary = "UN", fallback = c("AR1", "CS")),
      df_method = "Kenward-Roger",
      estimands = list(visit_lsmeans = TRUE, treatment_visit_lsmeans = FALSE, pairwise_differences = FALSE),
      output = list(raw_file = paste0(safe_analysis, "_raw.csv"), final_file = paste0(safe_analysis, "_final.csv"))
    )
  })
  list(
    profile_version = "standard-mmrm-profile/v1",
    study = list(study_id = as.character(review$metadata$study_id)),
    execution = list(fail_fast = FALSE),
    analyses = analyses
  )
}

analysis_specification_contract_text <- function(contract) {
  stopifnot(requireNamespace("yaml", quietly = TRUE))
  strsplit(yaml::as.yaml(contract), "\n", fixed = TRUE)[[1]]
}

analysis_specification_cleanup_orphaned_transaction_files <- function(directory) {
  if (!dir.exists(directory)) return(invisible(character()))
  paths <- list.files(directory, full.names = TRUE, recursive = FALSE, all.files = TRUE, no.. = TRUE)
  names_only <- basename(paths)
  temporary <- paths[
    grepl("^approval-publication-[0-9]+-", names_only) |
      grepl("^approved-review-", names_only) |
      grepl("^\\.(analysis-specification\\.md|standard-mmrm-contract\\.yaml)\\.", names_only) |
      grepl("\\.publish-backup-[0-9]+-", names_only)
  ]
  if (length(temporary) && any(!file.remove(temporary))) stop("Unable to remove orphaned specification transaction file(s): ", paste(temporary[file.exists(temporary)], collapse = ", "))
  invisible(temporary)
}

analysis_specification_publish_files <- function(files) {
  if (is.null(names(files)) || any(!nzchar(names(files)))) stop("Published files must be a named path-to-lines list.")
  targets <- names(files)
  invisible(lapply(unique(dirname(targets)), analysis_specification_cleanup_orphaned_transaction_files))
  invisible(lapply(unique(dirname(targets)), dir.create, recursive = TRUE, showWarnings = FALSE))
  temporary <- vapply(targets, function(path) tempfile(paste0(".", basename(path), "."), tmpdir = dirname(path)), character(1))
  backups <- paste0(targets, ".publish-backup-", Sys.getpid(), "-", format(Sys.time(), "%Y%m%d%H%M%S"))
  committed <- FALSE
  on.exit({
    unlink(temporary, force = TRUE)
    if (!committed) {
      unlink(targets, force = TRUE)
      for (i in seq_along(targets)) {
        if (file.exists(backups[[i]])) file.rename(backups[[i]], targets[[i]])
      }
    }
    unlink(backups, force = TRUE)
  }, add = TRUE)
  for (i in seq_along(targets)) writeLines(files[[i]], temporary[[i]], useBytes = TRUE)
  for (path in temporary) if (!file.exists(path) || file.info(path)$size < 1L) stop("Temporary publication file was not written.")
  existing <- file.exists(targets)
  for (i in which(existing)) if (!file.rename(targets[[i]], backups[[i]])) stop("Unable to stage existing published file: ", targets[[i]])
  for (i in seq_along(targets)) if (!file.rename(temporary[[i]], targets[[i]])) stop("Unable to publish file: ", targets[[i]])
  committed <- TRUE
  invisible(lapply(targets, specification_sha256))
}

analysis_specification_write_contract <- function(contract, path) {
  lines <- analysis_specification_contract_text(contract)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, path, useBytes = TRUE)
  toupper(specification_sha256(path))
}

generate_analysis_specification <- function(study_dir, project_dir, mode = "draft", output_path = NULL) {
  if (!mode %in% c("draft", "approved")) stop("mode must be draft or approved.")
  review_path <- file.path(study_dir, "statistician-review", "statistical-review.md")
  review <- read_statistical_review(review_path)
  analysis_specification_review_gate(review)
  mapping_yaml <- analysis_specification_mapping_gate(review, study_dir)
  tables <- analysis_specification_review_tables(review)
  yaml_keys <- paste(mapping_yaml$analysis_id, mapping_yaml$group_id, sep = "\r")
  review_keys <- paste(tables$mapping$analysis_id, tables$mapping$group_id, sep = "\r")
  if (!identical(yaml_keys, review_keys)) stop("Rendered Section 4 does not match the finalized endpoint-mapping.yaml.")
  if (nrow(tables$issues) > 0L && any(trimws(as.character(tables$issues$status)) != "resolved")) stop("Review has unresolved issues.")
  if (any(!trimws(as.character(tables$mapping$review_status)) %in% c("accepted", "modified"))) stop("Endpoint Mapping rows must be accepted or modified.")
  context <- analysis_specification_infer_context(review, project_dir)
  body <- analysis_specification_body(review, tables, project_dir)
  execution_sha <- toupper(analysis_specification_execution_sha_from_body(body))
  approved <- identical(mode, "approved")
  if (approved) {
    if (!identical(as.character(review$metadata$review_status), "approved")) stop("Approved specification generation requires review_status: approved.")
    if (!identical(toupper(as.character(review$metadata$approved_execution_sha256)), execution_sha)) {
      stop("approved_execution_sha256 mismatch. Expected statistician review value: ", execution_sha)
    }
  }
  contract_path <- file.path(study_dir, "statistician-review", "standard-mmrm-contract.yaml")
  contract <- analysis_specification_contract(review, tables)
  contract_lines <- analysis_specification_contract_text(contract)
  contract_temp <- tempfile("standard-mmrm-contract-")
  on.exit(unlink(contract_temp, force = TRUE), add = TRUE)
  writeLines(contract_lines, contract_temp, useBytes = TRUE)
  contract_hash <- toupper(specification_sha256(contract_temp))
  if (is.null(output_path)) output_path <- file.path(study_dir, "statistician-review", "analysis-specification.md")
  metadata <- c(
    list(
      schema_version = "1.0",
      specification_id = paste0(as.character(review$metadata$study_id), "-SPEC"),
      specification_version = "1.0",
      status = if (approved) "approved" else "draft",
      human_readable_language = "zh-CN",
      generation_route = as.character(review$metadata$generation_route),
      approval_mode = "human_review",
      study_id = as.character(review$metadata$study_id)
    ),
    context,
    list(
      source_input_file = as.character(review$metadata$source_input_file),
      source_input_sha256 = toupper(as.character(review$metadata$source_input_sha256)),
      endpoint_mapping_file = as.character(review$metadata$endpoint_mapping_file),
      endpoint_mapping_sha256 = toupper(as.character(review$metadata$endpoint_mapping_sha256)),
      execution_contract_file = project_relative_path(contract_path, project_dir),
      execution_contract_sha256 = contract_hash,
      analysis_ids = sort(unique(trimws(as.character(tables$mapping$analysis_id)))),
      tfl_ids = sort(unique(vapply(tables$candidates, `[[`, character(1), "tfl_id"))),
      review_file = project_relative_path(review_path, project_dir),
      review_sha256 = toupper(review$sha256),
      reviewed_by = if (approved) as.character(review$metadata$reviewed_by) else "",
      reviewed_at_utc = if (approved) as.character(review$metadata$reviewed_at_utc) else "",
      approved_execution_sha256 = if (approved) execution_sha else ""
    )
  )
  lines <- c("---", analysis_specification_yaml_lines(metadata), "---", body)
  analysis_specification_publish_files(setNames(list(contract_lines, lines), c(contract_path, output_path)))
  list(path = output_path, execution_sha256 = execution_sha, approved = approved)
}
