intake_candidate_rule_categories <- function() {
  c(
    "分析数据集", "分析人群", "终点变量与取值", "终点维度", "响应与基线",
    "访视与窗口", "重复记录与行分配", "固定效应", "协方差与自由度", "估计量与输出"
  )
}

intake_candidate_table_columns <- function() {
  if (exists("statistical_review_candidate_table_columns", mode = "function", inherits = TRUE)) return(statistical_review_candidate_table_columns())
  c("规则类别", "AI 识别的候选规则", "证据来源与识别状态", "Standard MMRM Profile v1 评估", "统计师审阅意见", "结构化处置")
}

intake_markdown_split_row <- function(line) {
  trimws(strsplit(sub("^\\s*\\|\\s*", "", sub("\\|\\s*$", "", line)), "\\|", fixed = FALSE)[[1]])
}

intake_markdown_table_after_heading <- function(lines, heading_pattern) {
  heading <- grep(heading_pattern, lines, perl = TRUE)
  if (!length(heading)) return(NULL)
  start <- heading[[1]] + 1L
  table_start <- which(grepl("^\\s*\\|", lines[start:length(lines)]))
  if (!length(table_start)) return(NULL)
  table_start <- start + table_start[[1]] - 1L
  table_end <- table_start
  while (table_end <= length(lines) && grepl("^\\s*\\|", lines[[table_end]])) table_end <- table_end + 1L
  block <- lines[table_start:(table_end - 1L)]
  if (length(block) < 3L) return(NULL)
  header <- intake_markdown_split_row(block[[1]])
  rows <- lapply(block[-c(1L, 2L)], intake_markdown_split_row)
  rows <- rows[vapply(rows, length, integer(1)) == length(header)]
  if (!length(rows)) {
    return(as.data.frame(setNames(replicate(length(header), character(), simplify = FALSE), header), stringsAsFactors = FALSE))
  }
  data <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE, check.names = FALSE)
  names(data) <- header
  data
}

intake_auto_register_inputs_if_needed <- function(manifest_path, study_dir, project_dir) {
  manifest <- read_utf8_bom_csv(manifest_path)
  if (nrow(manifest) > 0L && any(trimws(as.character(manifest$status)) == "registered_input")) return(invisible(FALSE))
  input_dir <- file.path(study_dir, "input")
  if (!dir.exists(input_dir)) return(invisible(FALSE))
  files <- list.files(input_dir, recursive = TRUE, full.names = TRUE, all.files = FALSE, no.. = TRUE)
  files <- files[file.exists(files) & !dir.exists(files)]
  if (!length(files)) return(invisible(FALSE))
  stopifnot(requireNamespace("digest", quietly = TRUE))
  input_root <- normalizePath(input_dir, winslash = "/", mustWork = TRUE)
  rows <- data.frame(
    input_type = ifelse(basename(files) == "statistician-analysis-input.md", "statistician_briefing", "source_material"),
    file_name = basename(files),
    relative_path = vapply(files, function(path) {
      normalized <- normalizePath(path, winslash = "/", mustWork = TRUE)
      file.path("input", gsub("\\\\", "/", substr(normalized, nchar(input_root) + 2L, nchar(normalized))))
    }, character(1)),
    version = "current",
    file_size_bytes = file.info(files)$size,
    modified_at = format(as.POSIXct(file.info(files)$mtime, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    sha256 = toupper(vapply(files, digest::digest, character(1), file = TRUE, algo = "sha256")),
    status = "registered_input",
    note = "auto_registered_by_generate_intake_review",
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  write_utf8_bom_csv(rows, manifest_path)
  invisible(TRUE)
}

intake_manifest_for_review <- function(study_dir, project_dir) {
  manifest_path <- file.path(study_dir, "backup-trace", "input-manifest.csv")
  if (!file.exists(manifest_path)) stop("创建 intake review 前必须先登记 input-manifest.csv：", manifest_path)
  intake_auto_register_inputs_if_needed(manifest_path, study_dir, project_dir)
  manifest <- read_utf8_bom_csv(manifest_path)
  required <- c("relative_path", "sha256", "status")
  missing <- setdiff(required, names(manifest))
  if (length(missing)) stop("input-manifest.csv 缺少列：", paste(missing, collapse = ", "))
  manifest$relative_path <- gsub("\\\\", "/", trimws(as.character(manifest$relative_path)))
  manifest$status <- trimws(as.character(manifest$status))
  manifest$sha256 <- toupper(trimws(as.character(manifest$sha256)))
  if (any(!grepl("^[A-F0-9]{64}$", manifest$sha256))) stop("input-manifest.csv 存在无效 SHA-256。")
  study_relative <- project_relative_path(study_dir, project_dir)
  project_relative <- ifelse(
    startsWith(manifest$relative_path, paste0(study_relative, "/")),
    manifest$relative_path,
    file.path(study_relative, manifest$relative_path)
  )
  manifest$absolute_path <- vapply(
    project_relative,
    normalize_project_relative_path,
    character(1),
    project_dir = project_dir,
    context = "manifest.relative_path"
  )
  list(path = manifest_path, rows = manifest)
}

intake_text_sources <- function(manifest, study_dir) {
  input_root <- paste0(normalizePath(file.path(study_dir, "input"), winslash = "/", mustWork = TRUE), "/")
  rows <- manifest$rows
  text_extensions <- c("txt", "md")
  extension <- tolower(tools::file_ext(rows$absolute_path))
  inside_input <- startsWith(tolower(rows$absolute_path), tolower(input_root))
  selected <- rows[inside_input & extension %in% text_extensions, , drop = FALSE]
  if (nrow(selected) == 0L) return(selected)
  if (any(selected$status != "registered_input")) {
    bad <- selected$relative_path[selected$status != "registered_input"]
    stop("intake text source 必须以 registered_input 登记：", paste(bad, collapse = ", "))
  }
  selected
}

intake_source_reference <- function(relative_path, start_line, end_line = start_line) {
  paste0(relative_path, ":L", start_line, "-L", end_line)
}

intake_escape_markdown <- function(value) {
  value <- gsub("\\|", "\\\\|", as.character(value))
  gsub("[\r\n]+", " ", value)
}

intake_markdown_table_blocks <- function(lines) {
  table_lines <- which(grepl("^\\s*\\|", lines))
  if (!length(table_lines)) return(list())
  split(table_lines, cumsum(c(TRUE, diff(table_lines) != 1L)))
}

intake_briefing_fields <- function(lines) {
  fields <- list()
  for (block_index in intake_markdown_table_blocks(lines)) {
    block <- lines[block_index]
    if (length(block) < 3L) next
    rows <- lapply(block, intake_markdown_split_row)
    for (row in rows[-c(1L, 2L)]) {
      if (length(row) < 2L) next
      key <- trimws(row[[1]])
      value <- trimws(row[[2]])
      if (grepl("^[A-Za-z][A-Za-z0-9_]*$", key) && nzchar(value) && !grepl("^<.*>$", value)) {
        fields[[key]] <- value
      }
    }
  }
  fields
}

intake_briefing_section3_table <- function(lines) {
  table <- intake_markdown_table_after_heading(lines, "^##\\s+3\\.")
  if (is.null(table) || !"tfl_id" %in% names(table) || !"title" %in% names(table)) return(NULL)
  table
}

intake_detect_tfls_in_briefing <- function(lines, ref_fun) {
  if (!any(grepl("statistician-analysis-input|TFL briefing|TFL Analysis", lines, ignore.case = TRUE, perl = TRUE))) {
    return(list())
  }
  tfl_table <- intake_briefing_section3_table(lines)
  if (is.null(tfl_table) || nrow(tfl_table) == 0L) return(list())
  tfl_table$tfl_id <- gsub("`", "", trimws(as.character(tfl_table$tfl_id)))
  tfl_table$title <- trimws(as.character(tfl_table$title))
  tfl_table <- tfl_table[nzchar(tfl_table$tfl_id) & !grepl("^<.*>$", tfl_table$tfl_id), , drop = FALSE]
  if (nrow(tfl_table) == 0L) return(list())
  analysis_headings <- grep("^##\\s+4\\.\\s+TFL Analysis", lines, perl = TRUE)
  lapply(seq_len(nrow(tfl_table)), function(i) {
    tfl_id <- tfl_table$tfl_id[[i]]
    title <- tfl_table$title[[i]]
    heading <- analysis_headings[grepl(tfl_id, lines[analysis_headings], fixed = TRUE)]
    start <- if (length(heading)) heading[[1]] else 1L
    next_headings <- analysis_headings[analysis_headings > start]
    finish <- if (length(next_headings)) next_headings[[1]] - 1L else length(lines)
    block <- lines[start:finish]
    fields <- intake_briefing_fields(block)
    list(
      tfl_id = tfl_id,
      title = title,
      title_line = start,
      end_line = finish,
      source_ref = ref_fun(start, finish),
      evidence_score = 100L,
      window = block,
      source_kind = "statistician_briefing",
      fields = fields
    )
  })
}

intake_detect_tfls_in_text <- function(lines, ref_fun) {
  # TFL 编号后可直接紧接中文标题；目录和正文均允许以此格式出现。
  title_pattern <- "^\\s*(表\\s*[0-9]+(?:\\.[0-9]+)+)\\s*(.*MMRM.*)$"
  matches <- regexec(title_pattern, lines, perl = TRUE)
  groups <- regmatches(lines, matches)
  candidates <- Filter(function(x) length(x) == 3L, groups)
  if (!length(candidates)) return(list())
  results <- lapply(which(vapply(groups, length, integer(1)) == 3L), function(index) {
    match <- groups[[index]]
    tfl_id <- gsub("\\s+", "", match[[2]])
    title <- trimws(match[[3]])
    finish <- min(length(lines), index + 80L)
    window <- lines[index:finish]
    evidence <- c(
      if (any(grepl("重复测量的混合模型|PROC MIXED|proc mixed", window, ignore.case = TRUE, perl = TRUE))) "模型说明" else "",
      if (any(grepl("MMRM结果", window, fixed = TRUE))) "MMRM结果" else ""
    )
    evidence <- evidence[nzchar(evidence)]
    list(
      tfl_id = tfl_id, title = title, title_line = index, end_line = finish,
      source_ref = ref_fun(index, finish),
      evidence_score = length(evidence), window = window
    )
  })
  by_id <- split(results, vapply(results, `[[`, character(1), "tfl_id"))
  lapply(by_id, function(items) items[[which.max(vapply(items, `[[`, numeric(1), "evidence_score"))]])
}

intake_candidate_rows <- function(tfl) {
  if (identical(tfl$source_kind, "statistician_briefing")) {
    fields <- tfl$fields
    value <- function(name, default = "未识别") {
      item <- fields[[name]]
      if (is.null(item) || !nzchar(trimws(as.character(item)))) default else trimws(as.character(item))
    }
    has_field <- function(name) !identical(value(name), "未识别")
    window <- paste(tfl$window, collapse = "\n")
    text_or_unknown <- function(pattern, label) if (grepl(pattern, window, ignore.case = TRUE, perl = TRUE)) label else "未识别"
    candidate <- c(
      value("source_dataset"),
      paste0(value("analysis_population"), "; ", value("population_rule")),
      paste0(value("endpoint_variable"), " in ", value("endpoint_codes")),
      "instrument/version/reporter/subscale 未识别；如 TFL 需要分量表或报告者分层，统计师需补充",
      paste0("response=", value("response_variable"), "; baseline=", value("baseline_variable")),
      paste0("visit=", value("visit_variable")),
      text_or_unknown("one row|每个.*一行|subject.*visit|受试者.*访视", "每个 subject × endpoint × visit 最多一行；具体去重规则待统计师确认"),
      text_or_unknown("fixed_effects|fixed effects|baseline|visit|treatment|region|country", "从 TFL briefing 自然语言识别固定效应；需统计师逐行确认"),
      text_or_unknown("UN|AR\\(1\\)|CS|Kenward|Roger|covariance", "从 TFL briefing 自然语言识别协方差/自由度；需统计师逐行确认"),
      text_or_unknown("LSMean|difference|p-value|CI|估计|输出", "从 TFL briefing 自然语言识别估计量/输出；AI 后续生成 estimate_id")
    )
    evidence <- paste0(tfl$source_ref, "；statistician-analysis-input.md structured briefing")
    rows <- data.frame(
      "规则类别" = intake_candidate_rule_categories(),
      "AI 识别的候选规则" = candidate,
      "证据来源与识别状态" = rep(evidence, 10L),
      "Standard MMRM Profile v1 评估" = c(
        if (has_field("source_dataset")) "可表达，待数据核对" else "当前不可执行",
        if (has_field("analysis_population") || has_field("population_rule")) "可表达，待统计师确认" else "需要补充规则",
        if (has_field("endpoint_variable") && has_field("endpoint_codes")) "可表达，待数据核对" else "当前不可执行",
        "需要补充规则",
        if (has_field("response_variable")) "可表达，待数据核对" else "当前不可执行",
        if (has_field("visit_variable")) "可表达，待数据核对" else "需要补充规则",
        "需要补充规则",
        if (candidate[[8]] != "未识别") "可表达，待统计师确认" else "需要补充规则",
        if (candidate[[9]] != "未识别") "可表达，待统计师确认" else "需要补充规则",
        if (candidate[[10]] != "未识别") "可表达，待统计师确认" else "需要补充规则"
      ),
      "统计师审阅意见" = rep("", 10L),
      "结构化处置" = rep("action=pending", 10L),
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
    names(rows) <- intake_candidate_table_columns()
    return(rows)
  }
  window <- paste(tfl$window, collapse = "\n")
  has <- function(pattern) grepl(pattern, window, ignore.case = TRUE, perl = TRUE)
  coafl <- if (grepl("COA.?分析集", tfl$title, perl = TRUE)) "COA 分析集；具体分析标志未识别" else "未识别"
  endpoint <- if (grepl("PedsQL", tfl$title, ignore.case = TRUE)) "PedsQL 总分及可能的分量表；终点变量和 PARAMCD 未识别" else if (grepl("疼痛强度", tfl$title, fixed = TRUE)) "疼痛强度；终点变量和 PARAMCD 未识别" else if (grepl("疼痛干扰", tfl$title, fixed = TRUE)) "疼痛干扰；终点变量和 PARAMCD 未识别" else if (grepl("肌力", tfl$title, fixed = TRUE)) "肌力评估；终点变量和 PARAMCD 未识别" else if (grepl("关节活动范围", tfl$title, fixed = TRUE)) "关节活动范围；终点变量和 PARAMCD 未识别" else "未识别"
  dimensions <- if (has("受试者报告|家长报告")) "报告者可能区分患者和家长；量表、版本和分量表未识别" else "量表、版本、报告者和分量表未识别"
  response_baseline <- if (has("model\\s+CHG|CHG")) "响应变量候选 `CHG`；基线变量候选 `BASE`" else "相对基线变化为候选响应；变量名未识别"
  visit <- if (has("AVISITN|avisitn")) "访视变量候选 `AVISITN`；访视窗口和窗口内选择规则未识别" else "访视、窗口和窗口内选择规则未识别"
  fixed <- if (has("model\\s+CHG.*avisitn.*region.*base")) "访视、地区、基线、基线×访视" else if (has("基线分数.*检查周期.*地区")) "访视、地区、基线、基线×访视" else "未识别"
  covariance <- if (has("无结构型|type\\s*=\\s*un")) "UN；不收敛时 AR1；Kenward–Roger" else "协方差和自由度未识别"
  estimand <- if (has("lsmeans|校正均值")) "各访视校正均值、95% CI 和 P 值" else "未识别"
  evidence <- function(extra = "") paste0(tfl$source_ref, "；", if (nzchar(extra)) extra else "候选")
  rows <- data.frame(
    "规则类别" = intake_candidate_rule_categories(),
    "AI 识别的候选规则" = c(
      "未识别；需从候选 ADaM 数据集和 ADaM specification 核对",
      coafl,
      endpoint,
      dimensions,
      response_baseline,
      visit,
      "每个受试者 × 终点 × 访视最多一行；具体去重和行分配规则未识别",
      fixed,
      covariance,
      estimand
    ),
    "证据来源与识别状态" = c(
      evidence("未识别"), evidence(if (coafl == "未识别") "未识别" else "候选"), evidence("候选"),
      evidence(if (has("受试者报告|家长报告")) "候选" else "未识别"), evidence(if (has("CHG")) "候选" else "未识别"),
      evidence(if (has("AVISITN|avisitn")) "候选" else "未识别"), evidence("Standard Profile v1 要求；需数据核对"),
      evidence(if (fixed == "未识别") "未识别" else "候选"), evidence(if (has("无结构型|type\\s*=\\s*un")) "候选" else "未识别"),
      evidence(if (has("lsmeans|校正均值")) "候选" else "未识别")
    ),
    "Standard MMRM Profile v1 评估" = c(
      "当前不可执行", "需要补充规则", "当前不可执行", "需要补充规则", "可表达，待数据核对",
      "需要补充规则", "需要补充规则", if (fixed != "未识别" && grepl("地区", fixed, fixed = TRUE)) "需要 Profile 扩展" else "需要补充规则",
      if (has("无结构型|type\\s*=\\s*un")) "可表达，待统计师确认" else "需要补充规则", if (has("lsmeans|校正均值")) "可表达，待统计师确认" else "需要补充规则"
    ),
    "统计师审阅意见" = rep("", 10L),
    "结构化处置" = rep("action=pending", 10L),
    stringsAsFactors = FALSE, check.names = FALSE
  )
  rows
}

intake_source_ref_fun <- function(relative_path, location_map_path) {
  if (is.null(location_map_path) || is.na(location_map_path) || !nzchar(location_map_path)) {
    return(function(start_line, end_line) intake_source_reference(relative_path, start_line, end_line))
  }
  map <- read_utf8_bom_csv(location_map_path)
  map$extracted_line <- suppressWarnings(as.integer(map$extracted_line))
  function(start_line, end_line) {
    idx <- which(map$extracted_line >= start_line & map$extracted_line <= end_line)
    locators <- intake_compress_locators(as.character(map$source_locator[idx]))
    if (length(locators)) paste0(relative_path, ":", paste(locators, collapse = ",")) else relative_path
  }
}

intake_discover_mmrm_tfls <- function(study_dir, project_dir) {
  extraction <- intake_prepare_extractions(study_dir, project_dir)
  on.exit(unlink(extraction$extract_root, recursive = TRUE, force = TRUE), add = TRUE)
  manifest <- intake_manifest_for_review(study_dir, project_dir)
  sources <- intake_scannable_sources(manifest, study_dir, extraction$temporary_sources)
  discoveries <- unlist(lapply(seq_len(nrow(sources)), function(i) {
    scan_path <- sources$scan_path[[i]]
    if (!file.exists(scan_path)) return(list())
    lines <- readLines(scan_path, encoding = "UTF-8", warn = FALSE)
    ref_fun <- intake_source_ref_fun(
      sources$relative_path[[i]],
      sources$location_map_path[[i]]
    )
    briefing <- intake_detect_tfls_in_briefing(lines, ref_fun)
    if (length(briefing)) return(briefing)
    text_tfls <- intake_detect_tfls_in_text(lines, ref_fun)
    lapply(text_tfls, function(item) {
      item$source_kind <- "source_text"
      item
    })
  }), recursive = FALSE)
  if (!length(discoveries)) return(list(manifest = manifest, tfls = list(), sources = sources))
  keys <- vapply(discoveries, function(x) paste(x$tfl_id, x$source_ref, sep = "\r"), character(1))
  discoveries <- discoveries[!duplicated(keys)]
  discoveries <- discoveries[order(vapply(discoveries, `[[`, character(1), "tfl_id"))]
  list(manifest = manifest, tfls = discoveries, sources = sources)
}

intake_render_candidate_block <- function(tfl) {
  rows <- intake_candidate_rows(tfl)
  table <- c(
    paste0("### 表 ", sub("^表", "", tfl$tfl_id), "：", tfl$title),
    "",
    paste0("| ", paste(intake_candidate_table_columns(), collapse = " | "), " |"),
    "|---|---|---|---|---|---|",
    vapply(seq_len(nrow(rows)), function(i) paste0("| ", paste(vapply(rows[i, , drop = FALSE], intake_escape_markdown, character(1)), collapse = " | "), " |"), character(1))
  )
  c(table, "")
}

intake_render_review <- function(study_dir, project_dir, route, discovery) {
  study_id <- basename(normalizePath(study_dir, winslash = "/", mustWork = TRUE))
  manifest_relative <- project_relative_path(discovery$manifest$path, project_dir)
  manifest_hash <- toupper(specification_sha256(discovery$manifest$path))
  candidate_blocks <- if (length(discovery$tfls)) unlist(lapply(discovery$tfls, intake_render_candidate_block), use.names = FALSE) else c(
    "未发现明确的 MMRM TFL；统计师可在此补充材料或明确不适用。", ""
  )
  issues <- if (length(discovery$tfls)) c(
    "| issue_id | scope | question_or_risk | resolution | status |",
    "|---|---|---|---|---|",
    "| INTAKE-001 | ALL | 所有候选 TFL 的待确认规则必须逐行处置，且采用/修改结果须形成最终 Endpoint Mapping 和 execution contract。 | 待统计师处置 | unresolved |"
  ) else c(
    "| issue_id | scope | question_or_risk | resolution | status |",
    "|---|---|---|---|---|",
    "| INTAKE-001 | ALL | 当前 registered input 中未发现明确 MMRM TFL。 | 待统计师确认是否补充材料或声明不适用 | unresolved |"
  )
  metadata <- c(
    "---", "review_schema_version: '1.1'", paste0("study_id: ", study_id), paste0("generation_route: ", route),
    "review_status: pending", "reviewed_by: ''", "reviewed_at_utc: ''", "approved_execution_sha256: ''",
    paste0("source_input_file: ", manifest_relative), paste0("source_input_sha256: ", manifest_hash), "---", ""
  )
  body <- c(
    "# 统计师 MMRM 审阅", "",
    "> 本文件是当前 study 唯一人工审阅与签核文件。AI 候选仅来自已登记的当前 study input；候选不等同于批准的执行规则。pending 状态不得填写签核信息。", "",
    "## 1. 审阅结论与签核", "当前为 pending。统计师必须处置第 3 节所有候选规则、解决全部 Issues，并完成最终 Endpoint Mapping 后方可签核。", "",
    "## 2. Study 与数据范围", paste0("Study：", study_id, "。已扫描 ", nrow(discovery$sources), " 个已登记文本材料，识别 ", length(discovery$tfls), " 个明确 MMRM TFL。"), "",
    "## 3. Analysis 与 TFL 清单", "以下每张表均为 AI 候选规则表。统计师仅填写“统计师审阅意见”；AI 代理生成或更新“结构化处置”，并在审阅完成后重建 Endpoint Mapping。R finalizer 只校验结构化处置和生成的 mapping，不从自由文本推断统计规则。", "",
    candidate_blocks,
    "## 4. Endpoint Mapping 与分组确认",
    "| analysis_id | source_tfl_id | group_id | endpoint_label | endpoint_variable | selected_codes | selection_mode | instrument / version / reporter / subscale | row_allocation_rule | source_ref | review_status | reviewer_note |",
    "|---|---|---|---|---|---|---|---|---|---|---|---|",
    "| <待统计师确认> | <由 finalizer 自动填充> | <待统计师确认> | <待统计师确认> | <待统计师确认> | <待统计师确认> | <待统计师确认> | <待统计师确认> | <待统计师确认> | <待统计师确认> | <待填写 accepted/modified> | <待填写> |", "",
    "## 5. 模型、协方差与估计量确认", "第 3 节候选仅作审阅输入。不得将未处置、Profile 不支持或未映射的数据规则写入最终执行定义。", "",
    "## 6. Adapter / 派生 / 行分配确认", "如需 adapter、窗口内记录选择或复杂 endpoint 分配，必须在批准前明确并固定到 typed contract。", "",
    "## 7. 未解决问题与决议", issues, "",
    "## 8. Execution 内容指纹", "当前 pending，尚未生成 approved execution SHA-256。"
  )
  c(metadata, body)
}

write_intake_statistical_review <- function(study_dir, project_dir, route, replace_pending = FALSE) {
  review_path <- file.path(study_dir, "statistician-review", "statistical-review.md")
  if (file.exists(review_path)) {
    current <- read_statistical_review(review_path)
    finalized <- !is.null(current$metadata$finalization_status) && nzchar(trimws(as.character(current$metadata$finalization_status)))
    if (finalized) {
      stop("statistical-review.md 已经进入 finalization 阶段；不要用 intake generator 覆盖。若要重新开始，请先人工归档或删除该 review。")
    }
    if (!isTRUE(replace_pending) || !identical(as.character(current$metadata$review_status), "pending")) {
      stop("仅允许使用 replace_pending=true 覆盖现有 pending statistical-review.md；approved review 不可覆盖。")
    }
  }
  discovery <- intake_discover_mmrm_tfls(study_dir, project_dir)
  mapping_path <- file.path(study_dir, "statistician-review", "endpoint-mapping.yaml")
  endpoint_mapping_write_template(mapping_path, discovery$tfls)
  dir.create(dirname(review_path), recursive = TRUE, showWarnings = FALSE)
  writeLines(intake_render_review(study_dir, project_dir, route, discovery), review_path, useBytes = TRUE)
  trace_path <- file.path(study_dir, "backup-trace", "intake-mmrm-tfl-scan.md")
  extraction_lines <- intake_extraction_trace_lines(discovery$manifest$rows)
  trace_lines <- c(
    "# Intake MMRM TFL 扫描记录", "",
    paste0("已扫描文本材料数：", nrow(discovery$sources)),
    paste0("明确 MMRM TFL 数：", length(discovery$tfls)), "",
    "## 输入抽取审计", extraction_lines, "",
    "## 发现的 TFL",
    if (length(discovery$tfls)) vapply(discovery$tfls, function(x) paste0("- ", x$tfl_id, "：", x$title, "（", x$source_ref, "）"), character(1)) else "- 未发现明确 MMRM TFL。"
  )
  writeLines(trace_lines, trace_path, useBytes = TRUE)
  list(review_path = review_path, trace_path = trace_path, tfl_count = length(discovery$tfls))
}
