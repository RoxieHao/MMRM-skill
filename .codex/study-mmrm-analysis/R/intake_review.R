intake_candidate_rule_categories <- function() {
  c(
    "分析数据集", "分析人群", "终点变量与取值", "终点维度", "响应与基线",
    "访视与窗口", "重复记录与行分配", "固定效应", "协方差与自由度", "估计量与输出"
  )
}

intake_candidate_table_columns <- function() {
  if (exists("statistical_review_candidate_table_columns", mode = "function", inherits = TRUE)) return(statistical_review_candidate_table_columns())
  c("规则类别", "AI 识别的候选规则", "证据来源与识别状态", "Standard MMRM Profile v1 评估", "统计师审阅意见")
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

intake_escape_markdown <- function(value) markdown_table_escape(value)

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

# R 只生成五列十类候选骨架，并把已登记 evidence（TFL source_ref、profile、specification）指给显式的
# AI Candidate Generation step 去填写。R 不猜测 dataset/PARAMCD/模型，也不硬编码任何 study 专属内容；
# 唯一确定的候选由 AI 从 registered input 与 profile/spec 得出，无法唯一确定时写“未识别/当前不可执行”并建 Section 7 issue。
intake_candidate_rows <- function(tfl) {
  categories <- intake_candidate_rule_categories()
  evidence <- paste0(tfl$source_ref, "；已登记 evidence：backup-trace/intake-mmrm-profile.yaml（变量、类型、真实水平、PARAMCD/PARAM、treatment levels 与 specification 对齐）及 ADaM specification / SAP / shell")
  rows <- data.frame(
    "规则类别" = categories,
    "AI 识别的候选规则" = rep("待 AI Candidate Generation 填写：依据 registered input 与 profile/specification 给出唯一、带证据的候选；无法唯一确定时写“未识别/当前不可执行”并在第 7 节建 issue", length(categories)),
    "证据来源与识别状态" = rep(evidence, length(categories)),
    "Standard MMRM Profile v1 评估" = rep("待 AI Candidate Generation 评估", length(categories)),
    "统计师审阅意见" = rep("", length(categories)),
    stringsAsFactors = FALSE, check.names = FALSE
  )
  names(rows) <- intake_candidate_table_columns()
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
    paste0("|", paste(rep("---", length(intake_candidate_table_columns())), collapse = "|"), "|"),
    vapply(seq_len(nrow(rows)), function(i) paste0("| ", paste(vapply(rows[i, , drop = FALSE], intake_escape_markdown, character(1)), collapse = " | "), " |"), character(1))
  )
  c(table, "")
}

# Analysis-plan workflow overrides. Markdown is evidence/reviewer interface only.
intake_render_review <- function(study_dir, project_dir, route, discovery) {
  study_id <- basename(normalizePath(study_dir, winslash = "/", mustWork = TRUE)); manifest_relative <- project_relative_path(discovery$manifest$path, project_dir)
  candidate_blocks <- if (length(discovery$tfls)) unlist(lapply(discovery$tfls, intake_render_candidate_block), use.names = FALSE) else c("No explicit MMRM TFL was found in registered input.", "")
  issues <- c("| issue_id | scope | question_or_risk | resolution | status |", "|---|---|---|---|---|", "| INTAKE-001 | ALL | Required analysis-plan decisions remain unresolved. | Statistician records decisions; AI compiles analysis-plan.yaml. | unresolved |")
  c("---", "review_schema_version: '2.0'", paste0("study_id: '", study_id, "'"), paste0("generation_route: '", route, "'"), "review_status: 'pending'", "reviewed_by: ''", "reviewed_at_utc: ''", "finalization_status: 'pending'", paste0("source_manifest_file: '", manifest_relative, "'"), "analysis_plan_file: ''", "analysis_plan_sha256: ''", "source_evidence_sha256: ''", "review_execution_content_sha256: ''", "approval_payload_sha256: ''", "---", "",
    "# 统计师 MMRM 审阅", "", "> 统计师只编辑本 Markdown 的审阅意见和 issue resolution。analysis-plan.yaml 由显式 Compile Analysis Plan agent step 生成；R 不从自由文本推断执行参数。", "",
    "## 1. 审阅结论与签核", "当前为 pending；签核字段由 approve_and_generate_analysis.R 在通过全部 gate 后写入。", "",
    "## 2. Study 与数据范围", paste0("Study：", study_id, "。Registered evidence：manifest ", manifest_relative, "；全量 ADaM profile backup-trace/intake-mmrm-profile.yaml（变量、类型、真实水平、PARAMCD/PARAM、treatment levels 与 specification 对齐）。"), "",
    "## 3. Analysis 与 TFL 清单", "候选与证据单元格由显式 AI Candidate Generation step 依据 registered input 与 profile/specification 填写；trace ID 由 <TFL ID>/<规则类别> 自动派生。统计师只编辑“统计师审阅意见”单元格，并须保持在同一 Markdown 物理行；需要换行时使用 <br>。不得在候选 TFL 标题下新增或粘贴其他 Markdown 表格；歧义必须保留并形成 issue。", "", candidate_blocks,
    "## 4. Analysis Plan（只读）", "<!-- ANALYSIS_PLAN_BEGIN -->", "Pending: compile and validate analysis-plan.yaml.", "<!-- ANALYSIS_PLAN_END -->", "",
    "## 5. 模型、协方差与估计量确认", "完整 typed values 仅见第 4 节只读渲染；本节是人类审阅记录，不是执行输入。", "",
    "## 6. Adapter / 派生 / 行分配确认", "Adapter 必须 SHA-pinned；built-in derivation 仅支持 typed recode；复杂转换必须使用批准 adapter。", "",
    "## 7. 未解决问题与决议", issues, "",
    "## 8. Approval Payload 指纹", "Pending; finalization computes canonical plan, review, source-evidence, and approval-payload hashes.")
}

write_intake_statistical_review <- function(study_dir, project_dir, route, replace_pending = FALSE) {
  review_path <- file.path(study_dir, "statistician-review", "statistical-review.md"); plan_path <- analysis_plan_path(study_dir)
  if (file.exists(review_path)) {
    current <- read_statistical_review(review_path)
    review_status <- trimws(as.character(current$metadata$review_status))
    finalization_status <- trimws(as.character(current$metadata$finalization_status))
    replaceable <- identical(review_status, "pending") && finalization_status %in% c("", "pending")
    if (!isTRUE(replace_pending) || !replaceable) {
      stop("Intake may replace only an unfinalized pending review. Archive or explicitly remove a finalized, blocked, or approved review before restarting intake.")
    }
  }
  discovery <- intake_discover_mmrm_tfls(study_dir, project_dir); dir.create(dirname(review_path), recursive = TRUE, showWarnings = FALSE)
  analysis_plan_write(analysis_plan_template(basename(normalizePath(study_dir, winslash = "/", mustWork = TRUE)), discovery$tfls), plan_path)
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
  list(review_path = review_path, analysis_plan_path = plan_path, trace_path = trace_path, tfl_count = length(discovery$tfls))
}
