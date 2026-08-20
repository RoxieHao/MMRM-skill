markdown_table_escape <- function(value) {
  value <- gsub("\\\\", "\\\\\\\\", as.character(value))
  value <- gsub("\\|", "\\\\|", value)
  gsub("[\r\n]+", " ", value)
}

markdown_table_split_row <- function(line, context = "Markdown table") {
  text <- trimws(as.character(line))
  if (!startsWith(text, "|") || !endsWith(text, "|")) stop(context, " row must start and end with '|'.")
  text <- substr(text, 2L, nchar(text) - 1L)
  cells <- character(); current <- ""; escaped <- FALSE
  for (index in seq_len(nchar(text))) {
    character <- substr(text, index, index)
    if (escaped) {
      if (!character %in% c("|", "\\")) stop(context, " has unsupported escape sequence at character ", index, ".")
      current <- paste0(current, character); escaped <- FALSE
    } else if (identical(character, "\\")) {
      escaped <- TRUE
    } else if (identical(character, "|")) {
      cells <- c(cells, trimws(current)); current <- ""
    } else {
      current <- paste0(current, character)
    }
  }
  if (escaped) stop(context, " ends with an unclosed escape.")
  c(cells, trimws(current))
}

markdown_table_separator_valid <- function(line, column_count) {
  cells <- markdown_table_split_row(line, "Markdown separator")
  length(cells) == column_count && all(grepl("^:?-{3,}:?$", cells))
}

specification_sha256 <- function(path) {
  stopifnot(requireNamespace("digest", quietly = TRUE))
  digest::digest(file = path, algo = "sha256")
}

source_standard_contract_helper <- function(project_root) {
  if (exists("read_standard_mmrm_contract", mode = "function", inherits = TRUE)) return(invisible(TRUE))
  if (is.null(project_root)) stop("验证 execution contract 需要 project_root。")
  helper <- file.path(project_root, ".codex", "study-mmrm-analysis", "R", "standard_contract.R")
  if (!file.exists(helper)) stop("找不到 Standard MMRM contract helper：", helper)
  source(helper, encoding = "UTF-8", local = .GlobalEnv)
  invisible(TRUE)
}

source_standard_io_helper <- function(project_root) {
  if (exists("normalize_project_relative_path", mode = "function", inherits = TRUE)) return(invisible(TRUE))
  if (is.null(project_root)) stop("验证 project-relative path 需要 project_root。")
  helper <- file.path(project_root, ".codex", "study-mmrm-analysis", "R", "io.R")
  if (!file.exists(helper)) stop("找不到 Standard MMRM IO helper：", helper)
  source(helper, encoding = "UTF-8", local = .GlobalEnv)
  invisible(TRUE)
}

read_analysis_specification <- function(path) {
  if (!file.exists(path)) stop("找不到 analysis specification：", path)
  stopifnot(requireNamespace("yaml", quietly = TRUE))

  lines <- readLines(path, encoding = "UTF-8", warn = FALSE)
  if (length(lines) < 3 || trimws(lines[[1]]) != "---") {
    stop("analysis-specification.md 缺少 YAML front matter。")
  }
  closing <- which(trimws(lines[-1]) == "---")
  if (length(closing) == 0) stop("analysis-specification.md 的 YAML front matter 未结束。")
  closing <- closing[[1]] + 1L
  metadata <- yaml::yaml.load(paste(lines[2:(closing - 1L)], collapse = "\n"))
  if (!is.list(metadata)) stop("analysis-specification.md 的 YAML metadata 无效。")

  list(
    path = normalizePath(path, winslash = "/", mustWork = TRUE),
    sha256 = specification_sha256(path),
    metadata = metadata,
    lines = lines,
    body = paste(lines[(closing + 1L):length(lines)], collapse = "\n")
  )
}

analysis_specification_required_headings <- function() {
  c(
    "## 1. 文件状态与使用规则",
    "## 2. Study 和数据上下文",
    "## 3. MMRM Analysis 清单",
    "## 4. Analysis Specifications",
    "## 5. TFL 输出清单",
    "## 6. SAS Template 生成要求",
    "## 7. 运行与诊断报告要求",
    "## 8. 完整 QC 要求",
    "## 9. 溯源附录",
    "## 10. 校验结果"
  )
}

analysis_specification_execution_text <- function(spec) {
  body_lines <- strsplit(spec$body, "\n", fixed = TRUE)[[1]]
  trace_line <- which(trimws(body_lines) == "## 9. 溯源附录")
  if (length(trace_line) != 1) return(spec$body)
  paste(body_lines[seq_len(trace_line - 1L)], collapse = "\n")
}

analysis_specification_execution_sha256 <- function(spec) {
  stopifnot(requireNamespace("digest", quietly = TRUE))
  digest::digest(enc2utf8(analysis_specification_execution_text(spec)), algo = "sha256", serialize = FALSE)
}

validate_legacy_ai_review_source_disabled <- function(spec, source_path) {
  stop("Excel review workbook gate is disabled; use statistical-review.md and analysis-specification.md.")
}

statistical_review_required_headings <- function() {
  c(
    "## 1. 审阅结论与签核",
    "## 2. Study 与数据范围",
    "## 3. Analysis 与 TFL 清单",
    "## 4. Endpoint Mapping 与分组确认",
    "## 5. 模型、协方差与估计量确认",
    "## 6. Adapter / 派生 / 行分配确认",
    "## 7. 未解决问题与决议",
    "## 8. Execution 内容指纹"
  )
}

read_statistical_review <- function(path) {
  if (!file.exists(path)) stop("找不到 statistical review：", path)
  stopifnot(requireNamespace("yaml", quietly = TRUE))

  lines <- readLines(path, encoding = "UTF-8", warn = FALSE)
  if (length(lines) < 3 || trimws(lines[[1]]) != "---") stop("statistical-review.md 缺少 YAML front matter。")
  closing <- which(trimws(lines[-1]) == "---")
  if (length(closing) == 0) stop("statistical-review.md 的 YAML front matter 未结束。")
  closing <- closing[[1]] + 1L
  metadata <- yaml::yaml.load(paste(lines[2:(closing - 1L)], collapse = "\n"))
  if (!is.list(metadata)) stop("statistical-review.md 的 YAML metadata 无效。")
  list(
    path = normalizePath(path, winslash = "/", mustWork = TRUE),
    sha256 = specification_sha256(path),
    metadata = metadata,
    body_lines = lines[(closing + 1L):length(lines)]
  )
}

statistical_review_section_lines <- function(review, heading) {
  headings <- statistical_review_required_headings()
  matches <- lapply(headings, function(x) which(trimws(review$body_lines) == x))
  if (!all(vapply(matches, length, integer(1)) == 1L)) return(character())
  positions <- vapply(matches, `[[`, integer(1), 1L)
  index <- match(heading, headings)
  start <- positions[[index]] + 1L
  end <- if (index == length(headings)) length(review$body_lines) else positions[[index + 1L]] - 1L
  if (start > end) character() else review$body_lines[start:end]
}

statistical_review_selected_codes <- function(value) {
  codes <- trimws(unlist(strsplit(gsub("[\\[\\]]", "", as.character(value)), "[,;]")))
  codes[nzchar(codes)]
}

statistical_review_dimensions_value <- function(definition) {
  dimension_names <- c("instrument", "version", "reporter", "subscale")
  dimensions <- definition$dimensions[dimension_names]
  if (all(vapply(dimensions, function(x) identical(x$variable, "not_applicable"), logical(1)))) {
    return("not_applicable")
  }
  paste(vapply(dimension_names, function(name) {
    dimension <- dimensions[[name]]
    if (identical(dimension$variable, "not_applicable")) return(paste0(name, "=not_applicable"))
    if (identical(dimension$variable, "fixed")) return(paste0(name, "=", as.character(dimension$values[[1L]])))
    paste0(name, "=", dimension$variable, ":[", paste(as.character(dimension$values), collapse = ","), "]")
  }, character(1)), collapse = "; ")
}

standard_contract_endpoint_mapping_catalog <- function(contract) {
  do.call(rbind, lapply(contract$analyses, function(analysis) {
    do.call(rbind, lapply(analysis$endpoint_definitions, function(definition) {
      data.frame(
        analysis_id = as.character(analysis$analysis_id),
        source_tfl_id = as.character(analysis$tfl_id),
        group_id = as.character(definition$group_id),
        endpoint_variable = as.character(definition$endpoint_variable),
        selected_codes = I(list(as.character(definition$selected_codes))),
        selection_mode = as.character(definition$selection_mode),
        dimensions = statistical_review_dimensions_value(definition),
        row_allocation_rule = as.character(definition$row_allocation_rule),
        stringsAsFactors = FALSE
      )
    }))
  }))
}

validate_review_contract_endpoint_mapping <- function(mapping, contract) {
  required_review_columns <- c(
    "analysis_id", "source_tfl_id", "group_id", "endpoint_variable", "selected_codes", "selection_mode",
    "instrument / version / reporter / subscale", "row_allocation_rule"
  )
  if (!is.data.frame(mapping) || !all(required_review_columns %in% names(mapping))) {
    return(list(valid = FALSE, message = "Review Endpoint Mapping 表无法用于与 execution contract 对照。"))
  }
  expected <- standard_contract_endpoint_mapping_catalog(contract)
  review_keys <- paste(trimws(mapping$analysis_id), trimws(mapping$group_id), sep = "\r")
  contract_keys <- paste(expected$analysis_id, expected$group_id, sep = "\r")
  if (anyDuplicated(review_keys) || !setequal(review_keys, contract_keys) || length(review_keys) != length(contract_keys)) {
    return(list(valid = FALSE, message = "Review Endpoint Mapping 必须与 execution contract 的 analysis_id/group_id 双向一一对应。"))
  }
  for (key in contract_keys) {
    review_row <- mapping[match(key, review_keys), , drop = FALSE]
    contract_row <- expected[match(key, contract_keys), , drop = FALSE]
    semantic_match <- identical(trimws(as.character(review_row$source_tfl_id)), contract_row$source_tfl_id) &&
      identical(trimws(as.character(review_row$endpoint_variable)), contract_row$endpoint_variable) &&
      identical(statistical_review_selected_codes(review_row$selected_codes[[1L]]), contract_row$selected_codes[[1L]]) &&
      identical(trimws(as.character(review_row$selection_mode)), contract_row$selection_mode) &&
      identical(trimws(as.character(review_row[["instrument / version / reporter / subscale"]])), contract_row$dimensions) &&
      identical(trimws(as.character(review_row$row_allocation_rule)), contract_row$row_allocation_rule)
    if (!semantic_match) {
      return(list(valid = FALSE, message = paste0("Review Endpoint Mapping 与 execution contract 不一致：", gsub("\r", "/", key), "。")))
    }
  }
  list(valid = TRUE, message = "Review Endpoint Mapping 与 execution contract endpoint_definitions 双向一致。")
}

validate_review_contract_population_filters <- function(candidates, contract) {
  if (!is.list(candidates) || !length(candidates)) return(list(valid = FALSE, message = "Review 人群规则不可用于与 execution contract 对照。"))
  by_tfl <- setNames(candidates, vapply(candidates, `[[`, character(1), "tfl_id"))
  contract_tfl <- vapply(contract$analyses, `[[`, character(1), "tfl_id")
  if (anyDuplicated(contract_tfl) || !setequal(names(by_tfl), contract_tfl)) return(list(valid = FALSE, message = "Review Section 3 与 execution contract 的 TFL 集合不一致。"))
  for (analysis in contract$analyses) {
    table <- by_tfl[[analysis$tfl_id]]$table
    population <- table[["AI 识别的候选规则"]][[match("分析人群", table[["规则类别"]])]]
    expected <- tryCatch(statistical_review_parse_population_rule(population), error = function(e) e)
    if (inherits(expected, "error") || !identical(statistical_review_population_rule_text(expected), statistical_review_population_rule_text(analysis$filters))) {
      return(list(valid = FALSE, message = paste0("Review 分析人群与 execution contract filters 不一致：", analysis$analysis_id, "。")))
    }
  }
  list(valid = TRUE, message = "Review 分析人群规则与 execution contract filters 双向一致。")
}

parse_statistical_review_table <- function(section_lines, expected_columns, section_name) {
  table_lines <- which(grepl("^\\s*\\|", section_lines))
  if (length(table_lines) == 0) stop(section_name, " 缺少 Markdown 表。")
  blocks <- split(table_lines, cumsum(c(TRUE, diff(table_lines) != 1L)))
  if (length(blocks) != 1L) stop(section_name, " 必须恰有一张 Markdown 表。")
  block <- section_lines[blocks[[1]]]
  if (length(block) < 2L) stop(section_name, " 表缺少表头或分隔行。")
  header <- markdown_table_split_row(block[[1]], paste0(section_name, " header"))
  if (!identical(header, expected_columns)) stop(section_name, " 表头不符合固定列定义。")
  if (!markdown_table_separator_valid(block[[2]], length(expected_columns))) stop(section_name, " 表缺少标准分隔行。")
  rows <- lapply(block[-c(1L, 2L)], markdown_table_split_row, context = section_name)
  if (length(rows) == 0L) return(as.data.frame(setNames(replicate(length(expected_columns), character(), simplify = FALSE), expected_columns), stringsAsFactors = FALSE))
  if (any(vapply(rows, length, integer(1)) != length(expected_columns))) stop(section_name, " 存在列数不正确的表行。")
  result <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE, check.names = FALSE)
  names(result) <- expected_columns
  result
}

statistical_review_candidate_table_columns <- function() {
  c("规则类别", "AI 识别的候选规则", "证据来源与识别状态", "Standard MMRM Profile v1 评估", "统计师审阅意见", "结构化处置")
}

# An AI agent writes this controlled field after interpreting the human-readable opinion.
# R only parses and validates this field; it never infers meaning from the opinion.
statistical_review_parse_disposition <- function(value) {
  text <- trimws(as.character(value))
  if (!nzchar(text)) stop("结构化处置不得为空；请由 AI 代理写入 action=pending 或明确处置。")
  parts <- trimws(strsplit(text, ";", fixed = TRUE)[[1L]])
  if (any(!nzchar(parts))) stop("结构化处置不得包含空字段。")
  fields <- lapply(parts, function(part) {
    match <- regmatches(part, regexec("^([a-z_]+)=(.+)$", part, perl = TRUE))[[1L]]
    if (length(match) != 3L) stop("结构化处置必须使用 key=value；收到：", part)
    c(key = match[[2L]], value = trimws(match[[3L]]))
  })
  keys <- vapply(fields, `[[`, character(1), "key")
  values <- vapply(fields, `[[`, character(1), "value")
  allowed <- c("action", "rule", "dataset", "population_rule")
  if (any(!keys %in% allowed) || anyDuplicated(keys) || !"action" %in% keys || any(!nzchar(values))) {
    stop("结构化处置必须包含唯一 action，且只允许 action、rule、dataset、population_rule。")
  }
  action <- values[[match("action", keys)]]
  if (!action %in% c("pending", "approved", "modified", "needs_clarification")) {
    stop("结构化处置 action 只允许 pending、approved、modified 或 needs_clarification。")
  }
  result <- as.list(setNames(values, keys))
  result$action <- action
  result
}

statistical_review_candidate_rule_categories <- function() {
  c(
    "分析数据集", "分析人群", "终点变量与取值", "终点维度", "响应与基线",
    "访视与窗口", "重复记录与行分配", "固定效应", "协方差与自由度", "估计量与输出"
  )
}

# Population rules use a small deterministic DSL so review text can become typed contract filters.
# Examples: COAFL eq \"是\"; SAFFL in [\"是\",\"Y\"]; AGE ge 12; not_applicable.
statistical_review_parse_population_rule <- function(value) {
  text <- trimws(sub("^批准人群：", "", trimws(as.character(value))))
  if (identical(text, "not_applicable")) return(list())
  variable_pattern <- "[A-Za-z_][A-Za-z0-9_]*"
  unary <- regexec(paste0("^(", variable_pattern, ")\\s+(is_missing|not_missing)$"), text, perl = TRUE)
  unary_match <- regmatches(text, unary)[[1]]
  if (length(unary_match) == 3L) return(list(list(variable = unary_match[[2]], operator = unary_match[[3]])))
  binary <- regexec(paste0("^(", variable_pattern, ")\\s+(eq|ne|gt|ge|lt|le)\\s+(\\\"[^\\\"]+\\\"|[^[:space:]]+)$"), text, perl = TRUE)
  binary_match <- regmatches(text, binary)[[1]]
  if (length(binary_match) == 4L) {
    operator <- binary_match[[3]]
    encoded <- binary_match[[4]]
    value <- if (startsWith(encoded, "\"") && endsWith(encoded, "\"")) substr(encoded, 2L, nchar(encoded) - 1L) else encoded
    if (!nzchar(value)) stop("分析人群规则值不得为空。")
    if (operator %in% c("gt", "ge", "lt", "le")) {
      numeric_value <- suppressWarnings(as.numeric(value))
      if (!is.finite(numeric_value)) stop("分析人群数值比较必须使用有限 numeric value。")
      value <- numeric_value
    }
    return(list(list(variable = binary_match[[2]], operator = operator, value = value)))
  }
  set_rule <- regexec(paste0("^(", variable_pattern, ")\\s+(in|not_in)\\s+\\[([^]]+)\\]$"), text, perl = TRUE)
  set_match <- regmatches(text, set_rule)[[1]]
  if (length(set_match) == 4L) {
    values <- trimws(strsplit(set_match[[4]], ",", fixed = TRUE)[[1]])
    values <- sub('^\"(.*)\"$', '\\1', values)
    if (!length(values) || any(!nzchar(values)) || anyDuplicated(values)) stop("分析人群集合值必须非空且唯一。")
    return(list(list(variable = set_match[[2]], operator = set_match[[3]], value = values)))
  }
  stop("分析人群必须填写 not_applicable 或 <变量> <操作符> <值>；例如 COAFL eq \"是\"。")
}

statistical_review_population_rule_text <- function(predicates) {
  if (!length(predicates)) return("not_applicable")
  if (length(predicates) != 1L) stop("Section 3 分析人群当前只允许一条 predicate。")
  predicate <- predicates[[1L]]
  if (predicate$operator %in% c("is_missing", "not_missing")) return(paste(predicate$variable, predicate$operator))
  if (predicate$operator %in% c("in", "not_in")) return(paste0(predicate$variable, " ", predicate$operator, " [", paste(paste0("\"", predicate$value, "\""), collapse = ","), "]"))
  value <- if (is.character(predicate$value)) paste0("\"", predicate$value, "\"") else as.character(predicate$value)
  paste(predicate$variable, predicate$operator, value)
}

parse_statistical_review_candidate_tables <- function(review) {
  section_lines <- statistical_review_section_lines(review, "## 3. Analysis 与 TFL 清单")
  heading_pattern <- "^###\\s+表\\s+([^：:]+)[：:]\\s*(.+)$"
  matched <- regexec(heading_pattern, section_lines, perl = TRUE)
  groups <- regmatches(section_lines, matched)
  indices <- which(vapply(groups, length, integer(1)) == 3L)
  if (!length(indices)) stop("Analysis 与 TFL 清单缺少逐 TFL 候选审阅表。")
  tables <- lapply(seq_along(indices), function(i) {
    start <- indices[[i]]
    end <- if (i == length(indices)) length(section_lines) else indices[[i + 1L]] - 1L
    heading <- groups[[start]]
    table <- parse_statistical_review_table(
      section_lines[(start + 1L):end], statistical_review_candidate_table_columns(),
      paste0("候选 TFL 表 ", trimws(heading[[2]]))
    )
    list(tfl_id = trimws(heading[[2]]), tfl_title = trimws(heading[[3]]), table = table)
  })
  keys <- vapply(tables, `[[`, character(1), "tfl_id")
  if (any(!nzchar(keys)) || any(!vapply(tables, function(x) nzchar(x$tfl_title), logical(1))) || anyDuplicated(keys)) {
    stop("候选 TFL 表的 TFL ID 和标题必须非空且 TFL ID 唯一。")
  }
  tables
}

validate_statistical_review_candidate_tables <- function(review) {
  result <- list(valid = FALSE, tables = list(), message = "")
  tryCatch({
    tables <- parse_statistical_review_candidate_tables(review)
    categories <- statistical_review_candidate_rule_categories()
    profile_assessments <- c("可表达，待数据核对", "可表达，待统计师确认", "需要补充规则", "需要 Profile 扩展", "当前不可执行")
    decisions <- c("待确认", "采用", "修改", "拒绝")
    for (candidate in tables) {
      table <- candidate$table
      if (nrow(table) != length(categories) || !identical(as.character(table[["规则类别"]]), categories)) {
        stop("候选 TFL 表 ", candidate$tfl_id, " 必须恰有十条固定规则类别，且顺序不得改变。")
      }
      required <- c("AI 识别的候选规则", "证据来源与识别状态", "Standard MMRM Profile v1 评估", "结构化处置")
      if (!all(vapply(required, function(name) all(nzchar(trimws(as.character(table[[name]])))), logical(1)))) {
        stop("候选 TFL 表 ", candidate$tfl_id, " 的候选、证据、Profile 评估和结构化处置不得为空。")
      }
      assessment <- trimws(as.character(table[["Standard MMRM Profile v1 评估"]]))
      dispositions <- lapply(table[["结构化处置"]], statistical_review_parse_disposition)
      actions <- vapply(dispositions, `[[`, character(1), "action")
      if (any(!assessment %in% profile_assessments)) stop("候选 TFL 表 ", candidate$tfl_id, " 存在无效 Profile 评估。")
      if (identical(as.character(review$metadata$review_status), "approved") && any(!actions %in% c("approved", "modified"))) {
        stop("approved review 不得保留 pending 或 needs_clarification 的结构化处置。")
      }
      if (!identical(as.character(review$metadata$review_status), "pending")) {
        population <- dispositions[[match("分析人群", table[["规则类别"]])]]
        if (!is.null(population$population_rule)) statistical_review_parse_population_rule(population$population_rule)
      }
    }
    result$valid <- TRUE
    result$tables <- tables
    result$message <- "逐 TFL 候选审阅表已完整、可追溯且已按当前 review 状态处置。"
    result
  }, error = function(e) {
    result$message <<- conditionMessage(e)
    result
  })
}

statistical_review_iso_utc <- function(value) {
  grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\\.[0-9]+)?(?:Z|[+]00:00)$", trimws(as.character(value)), perl = TRUE)
}

validate_statistical_review <- function(review, spec) {
  result <- list(
    metadata_valid = FALSE, sections_valid = FALSE, candidate_tables_valid = FALSE, mapping_valid = FALSE,
    issues_valid = FALSE, identity_valid = FALSE, execution_match = FALSE,
    candidate_tables = list(), mapping = NULL, message = ""
  )
  tryCatch({
    metadata <- review$metadata
    required_metadata <- c(
      "review_schema_version", "study_id", "generation_route", "review_status", "reviewed_by",
      "reviewed_at_utc", "approved_execution_sha256", "source_input_file", "source_input_sha256",
      "finalization_status"
    )
    has_metadata <- all(required_metadata %in% names(metadata))
    reviewer <- trimws(as.character(metadata$reviewed_by))
    reviewed_at <- trimws(as.character(metadata$reviewed_at_utc))
    execution_hash <- toupper(trimws(as.character(metadata$approved_execution_sha256)))
    source_hash <- toupper(trimws(as.character(metadata$source_input_sha256)))
    result$metadata_valid <- has_metadata &&
      identical(as.character(metadata$review_schema_version), "1.1") &&
      identical(as.character(metadata$review_status), "approved") &&
      identical(as.character(metadata$finalization_status), "ready_for_final_signature") &&
      nzchar(reviewer) && statistical_review_iso_utc(reviewed_at) &&
      grepl("^[A-F0-9]{64}$", execution_hash) &&
      nzchar(trimws(as.character(metadata$source_input_file))) && grepl("^[A-F0-9]{64}$", source_hash)

    headings <- statistical_review_required_headings()
    heading_counts <- vapply(headings, function(x) sum(trimws(review$body_lines) == x), integer(1))
    result$sections_valid <- all(heading_counts == 1L)
    candidate_tables <- validate_statistical_review_candidate_tables(review)
    result$candidate_tables_valid <- candidate_tables$valid
    result$candidate_tables <- candidate_tables$tables
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
    required_mapping <- c("analysis_id", "source_tfl_id", "group_id", "endpoint_label", "endpoint_variable", "selected_codes", "selection_mode", "instrument / version / reporter / subscale", "row_allocation_rule", "source_ref", "review_status")
    mapping_values_present <- nrow(mapping) > 0L && all(vapply(required_mapping, function(x) all(nzchar(trimws(as.character(mapping[[x]])))), logical(1)))
    selection_mode <- trimws(as.character(mapping$selection_mode))
    codes <- lapply(as.character(mapping$selected_codes), statistical_review_selected_codes)
    source_tfl_ids <- trimws(as.character(mapping$source_tfl_id))
    candidate_tfl_ids <- trimws(vapply(candidate_tables$tables, `[[`, character(1), "tfl_id"))
    analysis_source_tfl <- vapply(split(source_tfl_ids, trimws(as.character(mapping$analysis_id))), function(values) {
      unique_values <- unique(values)
      if (length(unique_values) != 1L) return("")
      unique_values[[1L]]
    }, character(1))
    analysis_source_tfl_valid <- all(nzchar(analysis_source_tfl)) && !anyDuplicated(analysis_source_tfl)
    source_refs <- trimws(as.character(mapping$source_ref))
    source_ref_valid <- vapply(seq_along(source_refs), function(i) {
      mentioned_candidates <- candidate_tfl_ids[vapply(candidate_tfl_ids, grepl, logical(1), x = source_refs[[i]], fixed = TRUE)]
      numeric_ids <- regmatches(source_refs[[i]], gregexpr("[0-9]+(?:\\.[0-9]+)+", source_refs[[i]], perl = TRUE))[[1L]]
      if (length(mentioned_candidates)) return(length(unique(mentioned_candidates)) == 1L && identical(mentioned_candidates[[1L]], source_tfl_ids[[i]]))
      !length(numeric_ids) || identical(unique(numeric_ids), source_tfl_ids[[i]])
    }, logical(1))
    source_ref_valid <- all(source_ref_valid)
    mapping_rules_valid <- all(selection_mode %in% c("single_code", "mutually_exclusive_versions", "approved_derivation")) &&
      all(vapply(seq_along(codes), function(i) selection_mode[[i]] != "single_code" || length(codes[[i]]) == 1L, logical(1))) &&
      all(trimws(as.character(mapping$review_status)) %in% c("accepted", "modified")) &&
      !anyDuplicated(paste(mapping$analysis_id, mapping$group_id, sep = "\r")) &&
      all(source_tfl_ids %in% candidate_tfl_ids) && analysis_source_tfl_valid &&
      setequal(unique(source_tfl_ids), candidate_tfl_ids) &&
      source_ref_valid
    result$mapping_valid <- mapping_values_present && mapping_rules_valid
    result$mapping <- mapping
    result$issues_valid <- nrow(issues) == 0L || all(trimws(as.character(issues$status)) == "resolved")

    spec_analysis_ids <- sort(unique(as.character(unlist(spec$metadata$analysis_ids))))
    mapping_analysis_ids <- sort(unique(trimws(as.character(mapping$analysis_id))))
    result$identity_valid <- identical(as.character(metadata$study_id), as.character(spec$metadata$study_id)) &&
      identical(as.character(metadata$generation_route), as.character(spec$metadata$generation_route)) &&
      identical(reviewer, as.character(spec$metadata$reviewed_by)) &&
      identical(reviewed_at, as.character(spec$metadata$reviewed_at_utc)) &&
      identical(as.character(metadata$source_input_file), as.character(spec$metadata$source_input_file)) &&
      identical(source_hash, toupper(as.character(spec$metadata$source_input_sha256))) &&
      identical(mapping_analysis_ids, spec_analysis_ids) &&
      all(vapply(spec_analysis_ids, function(id) sum(trimws(as.character(mapping$analysis_id)) == id) > 0L, logical(1)))
    result$execution_match <- identical(execution_hash, toupper(analysis_specification_execution_sha256(spec)))
    result$message <- paste("单一 Markdown statistical review 已完成结构、候选 TFL、签核、mapping、issue、identity 和 execution hash 校验。", candidate_tables$message)
    result
  }, error = function(e) {
    result$message <<- conditionMessage(e)
    result
  })
}

validate_analysis_specification <- function(path, project_root = NULL) {
  spec <- tryCatch(read_analysis_specification(path), error = function(e) e)
  checks <- list()
  add_check <- function(check_id, passed, message_cn) {
    checks[[length(checks) + 1L]] <<- data.frame(
      check_id = check_id,
      result = if (isTRUE(passed)) "Pass" else "Fail",
      message_cn = message_cn,
      stringsAsFactors = FALSE
    )
  }

  if (inherits(spec, "error")) {
    add_check("SPEC-READ", FALSE, conditionMessage(spec))
    return(do.call(rbind, checks))
  }
  add_check("SPEC-READ", TRUE, "已读取 analysis specification。")

  metadata <- spec$metadata
  required_metadata <- c(
    "schema_version", "specification_id", "specification_version", "status",
    "human_readable_language", "generation_route", "approval_mode", "study_id",
    "compound", "data_availability", "data_classification", "intended_use",
    "source_input_file", "source_input_sha256", "analysis_ids", "tfl_ids",
    "review_file", "review_sha256", "reviewed_by", "reviewed_at_utc", "approved_execution_sha256"
  )
  missing_metadata <- required_metadata[!vapply(required_metadata, function(x) {
    !is.null(metadata[[x]]) && length(metadata[[x]]) > 0 && nzchar(paste(metadata[[x]], collapse = ""))
  }, logical(1))]
  add_check(
    "SPEC-METADATA",
    length(missing_metadata) == 0,
    if (length(missing_metadata) == 0) "必需 metadata 完整。" else paste("缺少 metadata：", paste(missing_metadata, collapse = ", "))
  )

  add_check("SPEC-STATUS", identical(as.character(metadata$status), "approved"), "Specification 状态必须为 approved。")
  add_check("SPEC-LANGUAGE", identical(as.character(metadata$human_readable_language), "zh-CN"), "人读内容语言必须为 zh-CN。")

  route <- as.character(metadata$generation_route)
  approval_mode <- as.character(metadata$approval_mode)
  route_valid <- route %in% c("statistician_authored", "ai_source_extraction")
  approval_valid <- identical(approval_mode, "human_review")
  add_check("SPEC-ROUTE", route_valid && approval_valid, "所有 generation route 必须使用 approval_mode: human_review。")

  reviewer_valid <- !is.null(metadata$reviewed_by) && nzchar(trimws(as.character(metadata$reviewed_by))) &&
    !is.null(metadata$reviewed_at_utc) && statistical_review_iso_utc(metadata$reviewed_at_utc) &&
    !is.null(metadata$approved_execution_sha256) && grepl("^[A-Fa-f0-9]{64}$", trimws(as.character(metadata$approved_execution_sha256)))
  add_check("SPEC-HUMAN-REVIEW-METADATA", reviewer_valid, "两条 route 都必须记录 reviewer、UTC 时间和 approved execution SHA-256。")

  availability <- as.character(metadata$data_availability)
  classification <- as.character(metadata$data_classification)
  intended_use <- as.character(metadata$intended_use)
  data_valid <- availability %in% c("none", "available") &&
    classification %in% c("none", "dummy", "production", "unknown") &&
    intended_use %in% c("code_generation", "technical_validation", "formal_analysis") &&
    ((availability == "none" && classification == "none" && intended_use == "code_generation") ||
      (availability == "available" && classification %in% c("dummy", "production", "unknown"))) &&
    !(classification == "unknown" && intended_use != "code_generation") &&
    !(intended_use == "formal_analysis" && classification != "production") &&
    !(intended_use == "technical_validation" && !classification %in% c("dummy", "production"))
  add_check("SPEC-DATA-CONTEXT", data_valid, "数据可用性、类别和用途必须相互一致。")

  source_hash <- toupper(as.character(metadata$source_input_sha256))
  add_check("SPEC-SOURCE-HASH", grepl("^[A-F0-9]{64}$", source_hash), "Source input SHA-256 必须为 64 位十六进制。")
  source_path <- NULL
  source_exists <- FALSE
  source_matches <- FALSE
  if (!is.null(project_root) && !is.null(metadata$source_input_file)) {
    source_standard_io_helper(project_root)
    source_path <- tryCatch(
      normalize_project_relative_path(as.character(metadata$source_input_file), project_root, "source_input_file"),
      error = function(e) e
    )
    source_path_valid <- !inherits(source_path, "error")
    add_check("SPEC-SOURCE-PATH", source_path_valid, "Source input path 必须是安全的 project-relative path。")
    source_exists <- source_path_valid && file.exists(source_path)
    source_matches <- source_exists && identical(toupper(specification_sha256(source_path)), source_hash)
    add_check("SPEC-SOURCE-FILE", source_exists, "Source input 文件必须存在。")
    add_check("SPEC-SOURCE-MATCH", source_matches, "Source input 文件 SHA-256 必须与 metadata 一致。")
  }

  contract_file_declared <- !is.null(metadata$execution_contract_file) && nzchar(trimws(as.character(metadata$execution_contract_file)))
  contract_hash_declared <- !is.null(metadata$execution_contract_sha256) && nzchar(trimws(as.character(metadata$execution_contract_sha256)))
  contract <- NULL
  contract_schema_valid <- FALSE
  add_check(
    "SPEC-CONTRACT-DECLARATION",
    identical(contract_file_declared, contract_hash_declared),
    "execution_contract_file 和 execution_contract_sha256 必须同时声明或同时省略。"
  )
  if (contract_file_declared && contract_hash_declared) {
    if (!is.null(project_root)) source_standard_io_helper(project_root)
    contract_path <- if (is.null(project_root)) simpleError("验证 execution contract 需要 project_root。") else tryCatch(
      normalize_project_relative_path(as.character(metadata$execution_contract_file), project_root, "execution_contract_file"),
      error = function(e) e
    )
    contract_path_valid <- !inherits(contract_path, "error")
    add_check("SPEC-CONTRACT-PATH", contract_path_valid, "Execution contract path 必须是安全的 project-relative path。")
    contract_hash <- toupper(as.character(metadata$execution_contract_sha256))
    contract_hash_valid <- grepl("^[A-F0-9]{64}$", contract_hash)
    add_check("SPEC-CONTRACT-HASH", contract_hash_valid, "Execution contract SHA-256 必须为 64 位十六进制。")
    contract_exists <- contract_path_valid && file.exists(contract_path)
    add_check("SPEC-CONTRACT-FILE", contract_exists, "Execution contract 文件必须存在。")
    contract_matches <- contract_exists && contract_hash_valid && identical(toupper(specification_sha256(contract_path)), contract_hash)
    add_check("SPEC-CONTRACT-MATCH", contract_matches, "Execution contract 文件 SHA-256 必须与 metadata 一致。")
    contract <- if (contract_matches) tryCatch({
      source_standard_contract_helper(project_root)
      read_standard_mmrm_contract(contract_path)
    }, error = function(e) e) else simpleError("Execution contract file/hash gate 未通过。")
    contract_schema_valid <- !inherits(contract, "error")
    add_check(
      "SPEC-CONTRACT-SCHEMA",
      contract_schema_valid,
      if (contract_schema_valid) "Execution contract schema 有效。" else paste0("Execution contract schema 无效：", conditionMessage(contract))
    )
    identity_valid <- FALSE
    if (contract_schema_valid) {
      catalog <- standard_contract_catalog(contract)
      identity_valid <- identical(as.character(contract$study$study_id), as.character(metadata$study_id)) &&
        identical(sort(unique(as.character(catalog$analysis_id))), sort(unique(as.character(unlist(metadata$analysis_ids))))) &&
        identical(sort(unique(as.character(catalog$tfl_id))), sort(unique(as.character(unlist(metadata$tfl_ids)))))
    }
    add_check("SPEC-CONTRACT-IDENTITY", identity_valid, "Execution contract 的 study/Analysis/TFL identity 必须与 specification 一致。")
  }

  mapping_file_declared <- !is.null(metadata$endpoint_mapping_file) && nzchar(trimws(as.character(metadata$endpoint_mapping_file)))
  mapping_hash <- toupper(trimws(as.character(metadata$endpoint_mapping_sha256)))
  mapping_hash_valid <- grepl("^[A-F0-9]{64}$", mapping_hash)
  add_check("SPEC-ENDPOINT-MAPPING-HASH", mapping_file_declared && mapping_hash_valid, "endpoint_mapping_file 和 endpoint_mapping_sha256 必须有效。")
  if (!is.null(project_root) && mapping_file_declared) {
    source_standard_io_helper(project_root)
    mapping_path <- tryCatch(normalize_project_relative_path(as.character(metadata$endpoint_mapping_file), project_root, "endpoint_mapping_file"), error = function(e) e)
    mapping_exists <- !inherits(mapping_path, "error") && file.exists(mapping_path)
    mapping_matches <- mapping_exists && mapping_hash_valid && identical(toupper(specification_sha256(mapping_path)), mapping_hash)
    add_check("SPEC-ENDPOINT-MAPPING-FILE", mapping_exists, "endpoint-mapping.yaml 必须存在。")
    add_check("SPEC-ENDPOINT-MAPPING-MATCH", mapping_matches, "endpoint-mapping.yaml SHA-256 必须与 specification metadata 一致。")
  }

  review_file_declared <- !is.null(metadata$review_file) && nzchar(trimws(as.character(metadata$review_file)))
  review_hash <- toupper(trimws(as.character(metadata$review_sha256)))
  review_hash_valid <- grepl("^[A-F0-9]{64}$", review_hash)
  add_check("SPEC-REVIEW-FILE-HASH", review_hash_valid, "review_sha256 必须为 64 位十六进制。")
  review_path <- NULL
  review_exists <- FALSE
  review_matches <- FALSE
  review_file_name_valid <- FALSE
  if (!is.null(project_root) && review_file_declared) {
    source_standard_io_helper(project_root)
    review_path <- tryCatch(
      normalize_project_relative_path(as.character(metadata$review_file), project_root, "review_file"),
      error = function(e) e
    )
    review_path_valid <- !inherits(review_path, "error")
    add_check("SPEC-REVIEW-FILE-SAFE-PATH", review_path_valid, "review_file 必须是安全的 project-relative path。")
    if (review_path_valid) {
      expected_review_path <- normalizePath(file.path(dirname(spec$path), "statistical-review.md"), winslash = "/", mustWork = FALSE)
      review_file_name_valid <- identical(tolower(review_path), tolower(expected_review_path))
    }
    review_exists <- review_path_valid && file.exists(review_path)
    add_check("SPEC-REVIEW-FILE", review_exists, "statistical-review.md 必须存在。")
    review_matches <- review_exists && review_hash_valid && identical(toupper(specification_sha256(review_path)), review_hash)
  }
  add_check("SPEC-REVIEW-FILE-PATH", review_file_declared && review_file_name_valid, "review_file 必须是当前 study 的 statistician-review/statistical-review.md。")
  review <- if (review_matches) tryCatch(read_statistical_review(review_path), error = function(e) e) else simpleError("statistical-review.md 文件或 SHA-256 gate 未通过。")
  review_gate <- if (inherits(review, "error")) list(
    metadata_valid = FALSE, sections_valid = FALSE, candidate_tables_valid = FALSE, mapping_valid = FALSE,
    issues_valid = FALSE, identity_valid = FALSE, execution_match = FALSE,
    candidate_tables = list(), mapping = NULL, message = conditionMessage(review)
  ) else validate_statistical_review(review, spec)
  review_contract_gate <- if (contract_schema_valid && !is.null(review_gate$mapping)) {
    validate_review_contract_endpoint_mapping(review_gate$mapping, contract)
  } else {
    list(valid = FALSE, message = "Endpoint Mapping 与 execution contract 的对照前置校验未通过。")
  }
  population_contract_gate <- if (contract_schema_valid && length(review_gate$candidate_tables)) {
    validate_review_contract_population_filters(review_gate$candidate_tables, contract)
  } else {
    list(valid = FALSE, message = "分析人群与 execution contract filters 的对照前置校验未通过。")
  }
  add_check("SPEC-REVIEW-GATE", review_gate$metadata_valid && review_gate$sections_valid && review_gate$candidate_tables_valid && review_gate$mapping_valid && review_gate$issues_valid, review_gate$message)
  add_check("SPEC-REVIEW-FILE-MATCH", review_matches, "statistical-review.md SHA-256 必须与 metadata 一致。")
  add_check("SPEC-REVIEW-IDENTITY", review_gate$identity_valid, "Review 的 study/route/reviewer/analysis identity 必须与 specification 一致。")
  add_check("SPEC-ENDPOINT-MAPPING-IDENTITY", review_gate$mapping_valid && review_gate$identity_valid, "Endpoint Mapping 必须存在、已审核，并覆盖且仅覆盖 specification Analysis ID。")
  add_check("SPEC-ENDPOINT-MAPPING-CONTRACT-MATCH", review_contract_gate$valid, review_contract_gate$message)
  add_check("SPEC-POPULATION-FILTER-CONTRACT-MATCH", population_contract_gate$valid, population_contract_gate$message)
  add_check("SPEC-EXECUTION-APPROVAL", review_gate$execution_match && identical(toupper(trimws(as.character(metadata$approved_execution_sha256))), toupper(analysis_specification_execution_sha256(spec))), "Specification 第 1–8 节 SHA-256 必须同时匹配 review 和 specification metadata。")

  body <- spec$body
  missing_headings <- analysis_specification_required_headings()[
    !vapply(analysis_specification_required_headings(), grepl, logical(1), x = body, fixed = TRUE)
  ]
  add_check(
    "SPEC-SECTIONS",
    length(missing_headings) == 0,
    if (length(missing_headings) == 0) "固定章节完整。" else paste("缺少章节：", paste(missing_headings, collapse = "; "))
  )

  analysis_ids <- unique(as.character(unlist(metadata$analysis_ids)))
  tfl_ids <- unique(as.character(unlist(metadata$tfl_ids)))
  execution_text <- analysis_specification_execution_text(spec)
  missing_analysis <- analysis_ids[!vapply(analysis_ids, grepl, logical(1), x = execution_text, fixed = TRUE)]
  missing_tfl <- tfl_ids[!vapply(tfl_ids, grepl, logical(1), x = execution_text, fixed = TRUE)]
  add_check("SPEC-ANALYSIS-REF", length(analysis_ids) > 0 && length(missing_analysis) == 0, "所有 analysis ID 必须出现在执行规格中。")
  add_check("SPEC-TFL-REF", length(tfl_ids) > 0 && length(missing_tfl) == 0, "所有 TFL ID 必须出现在执行规格中。")

  ambiguous_pattern <- "TODO|TBD|待定|待确认|可能需要|其他合适|例如其他|\\bpending\\b|\\bblocked\\b"
  ambiguous <- grepl(ambiguous_pattern, execution_text, ignore.case = TRUE, perl = TRUE)
  add_check("SPEC-NO-AMBIGUITY", !ambiguous, "执行规格不得包含待定、候选或模糊统计规则。")

  do.call(rbind, checks)
}

analysis_specification_is_valid <- function(checks) {
  nrow(checks) > 0 && all(checks$result == "Pass")
}

write_analysis_specification_validation <- function(checks, output_path) {
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  status <- if (analysis_specification_is_valid(checks)) "Pass" else "Fail"
  lines <- c(
    "# Analysis Specification 校验报告",
    "",
    paste0("校验结论：**", status, "**"),
    "",
    "| Check ID | 结果 | 说明 |",
    "|---|---|---|",
    vapply(seq_len(nrow(checks)), function(i) {
      paste0("| `", checks$check_id[[i]], "` | ", checks$result[[i]], " | ", gsub("\\|", "\\\\|", checks$message_cn[[i]]), " |")
    }, character(1))
  )
  writeLines(lines, output_path, useBytes = TRUE)
  invisible(status)
}

assert_approved_specification <- function(path, expected_analysis_id = NULL, project_root = NULL) {
  checks <- validate_analysis_specification(path, project_root = project_root)
  if (!analysis_specification_is_valid(checks)) {
    failed <- checks$message_cn[checks$result == "Fail"]
    stop("analysis specification 校验失败：", paste(failed, collapse = "；"))
  }
  spec <- read_analysis_specification(path)
  if (!is.null(expected_analysis_id)) {
    analysis_ids <- as.character(unlist(spec$metadata$analysis_ids))
    if (!expected_analysis_id %in% analysis_ids) stop("Specification 未包含 analysis_id：", expected_analysis_id)
  }
  spec
}

assert_specification_execution_allowed <- function(spec) {
  metadata <- spec$metadata
  availability <- as.character(metadata$data_availability)
  classification <- as.character(metadata$data_classification)
  if (availability == "none" || classification %in% c("none", "unknown")) {
    stop(
      "当前 specification 只允许生成代码，禁止执行模型：data_availability=", availability,
      ", data_classification=", classification
    )
  }
  invisible(TRUE)
}
