# 逐 TFL 自包含 R 程序渲染器（Phase 3）。
# render_self_contained_r_program() 是纯函数：只读取已批准 contract/analysis/identities，
# 通过 build_program_generation_ir() 得到 normalized IR，返回一个 length-one UTF-8 字符串。
# 它不写文件、不读取 ADaM、不执行任何统计计算。
#
# 生成文本内不出现 ">" 字符，避免触发 conformance 的未替换 placeholder 规则；
# 所有大小比较统一写成 "较小值 < 较大值" 或 "<=" 形式。

scr_comment <- function(...) paste0("# ", paste0(c(...), collapse = ""))
scr_marker_line <- function(category, value) paste0("# ", program_marker(category, value))
scr_why_line <- function(category, value, reason) paste0("# ", program_why(category, value), " ", reason)
scr_blank <- function() ""

scr_string <- function(value, context = "self_contained_r") program_r_string_literal(as.character(value), context)

scr_scalar_literal <- function(value, context = "self_contained_r") {
  if (is.character(value)) return(program_r_string_literal(value, context))
  if (is.logical(value)) {
    if (length(value) != 1L || is.na(value)) stop("PROGRAM-R-RENDER-LITERAL:", context)
    return(if (isTRUE(value)) "TRUE" else "FALSE")
  }
  if (is.numeric(value)) {
    if (length(value) != 1L || is.na(value) || !is.finite(value)) stop("PROGRAM-R-RENDER-LITERAL:", context)
    return(format(value, scientific = FALSE, digits = 15L, trim = TRUE))
  }
  stop("PROGRAM-R-RENDER-LITERAL:", context)
}

scr_vector_literal <- function(values, context = "self_contained_r") {
  items <- vapply(as.list(values), function(value) scr_scalar_literal(value, context), character(1))
  paste0("c(", paste(items, collapse = ", "), ")")
}

scr_character_vector_literal <- function(values, context = "self_contained_r") {
  if (!length(values)) return("character(0)")
  paste0("c(", paste(vapply(as.character(values), function(value) scr_string(value, context), character(1)), collapse = ", "), ")")
}

scr_column <- function(frame, variable, context = "self_contained_r") paste0(frame, "[[", scr_string(variable, context), "]]")

scr_predicate_expression <- function(predicate, frame, context) {
  variable <- scr_column(frame, predicate$variable, context)
  operator <- predicate$operator
  set_literal <- function() scr_vector_literal(predicate$value, context)
  scalar_literal <- function() scr_scalar_literal(predicate$value, context)
  switch(
    operator,
    eq = paste0("(", variable, " == ", scalar_literal(), ")"),
    ne = paste0("(", variable, " != ", scalar_literal(), ")"),
    "in" = paste0("(", variable, " %in% ", set_literal(), ")"),
    not_in = paste0("(!", variable, " %in% ", set_literal(), ")"),
    gt = paste0("(", scalar_literal(), " < ", variable, ")"),
    ge = paste0("(", scalar_literal(), " <= ", variable, ")"),
    lt = paste0("(", variable, " < ", scalar_literal(), ")"),
    le = paste0("(", variable, " <= ", scalar_literal(), ")"),
    is_missing = paste0("(is.na(", variable, ") | trimws(as.character(", variable, ")) == \"\")"),
    not_missing = paste0("(!is.na(", variable, ") & trimws(as.character(", variable, ")) != \"\")"),
    stop("PROGRAM-R-RENDER-PREDICATE:", context)
  )
}

scr_missing_literal <- function(value_type) switch(value_type, character = "NA_character_", numeric = "NA_real_", logical = "NA", stop("PROGRAM-R-RENDER-RECODE-TYPE:", value_type))

scr_covariance_term <- function(covariance) {
  keyword <- switch(covariance, UN = "us", AR1 = "ar1", CS = "cs", TOEP = "toep", stop("PROGRAM-R-RENDER-COVARIANCE:", covariance))
  paste0(keyword, "(visit_f | subject_f)")
}

scr_fixed_effect_term <- function(effect) switch(
  effect,
  visit = "visit_f", baseline = "baseline", baseline_by_visit = "baseline:visit_f",
  treatment = "treatment_f", treatment_by_visit = "treatment_f:visit_f",
  stop("PROGRAM-R-RENDER-FIXED-EFFECT:", effect)
)

scr_fixed_effect_reason <- function(effect) switch(
  effect,
  visit = "批准的固定效应：以分类 visit 估计各访视的均值结构。",
  baseline = "批准的固定效应：以 baseline 作为连续协变量校正基线水平。",
  baseline_by_visit = "批准的固定效应：允许 baseline 的作用随访视变化。",
  treatment = "批准的固定效应：估计治疗组主效应。",
  treatment_by_visit = "批准的固定效应：估计治疗与访视交互，支持逐访视组间比较。",
  stop("PROGRAM-R-RENDER-FIXED-EFFECT:", effect)
)

scr_covariance_reason <- function(covariance, position) {
  label <- switch(covariance, UN = "非结构 (UN)", AR1 = "一阶自回归 (AR1)", CS = "复合对称 (CS)", TOEP = "Toeplitz (TOEP)", stop("PROGRAM-R-RENDER-COVARIANCE:", covariance))
  if (identical(position, 1L)) paste0("批准的主协方差结构 ", label, "，优先用于受试者内重复测量。") else paste0("批准的第 ", position - 1L, " 顺位 fallback 协方差结构 ", label, "，仅在前序结构未收敛时按批准顺序尝试。")
}

scr_mapping_reason <- function(name) switch(
  name,
  subject = "批准的受试者标识映射，用于受试者内相关结构与唯一性检查。",
  response = "批准的响应变量映射，是 MMRM 的因变量。",
  baseline = "批准的基线协变量映射，用于基线校正。",
  visit = "批准的访视变量映射，作为分类时间因子。",
  visit_label = "批准的访视标签映射，仅用于 TFL 展示，不改变统计模型。",
  treatment = "批准的治疗变量映射，用于治疗效应与组间对比。",
  paste0("批准的标准变量映射：", name, "。")
)

scr_estimand_reason <- function(name) switch(
  name,
  visit_lsmeans = "批准的估计量：逐访视 LS mean。",
  treatment_visit_lsmeans = "批准的估计量：逐治疗组、逐访视 LS mean。",
  pairwise_differences = "批准的估计量：按批准方向与置信水平的逐访视组间差值。",
  paste0("批准的估计量：", name, "。")
)

scr_section_1 <- function(ir) {
  identity <- ir$identity
  linked <- identical(ir$dataset$binding_mode, "linked")
  packages <- c("mmrm", "emmeans")
  if (linked) packages <- c("digest", packages)
  if (identical(ir$dataset$format, "sas7bdat")) packages <- c(packages, "haven")
  output_markers <- vapply(names(ir$output), function(name) scr_marker_line("OUTPUT", paste0(name, ":", ir$output[[name]])), character(1))
  c(
    render_r_section_header(1L, program_section_titles()[[1L]]),
    scr_comment("本程序由已批准的 analysis plan 与机械编译的 runtime contract 确定性生成，逐 TFL 自包含。"),
    scr_comment("阅读本文件即可理解该 TFL 的数据处理、MMRM 拟合、统计推断与输出，无需阅读任何项目共享代码。"),
    scr_comment("研究：", identity$study_id, "；分析：", identity$analysis_id, "；TFL：", identity$tfl_id),
    scr_comment("标题：", identity$title),
    scr_comment("profile 版本：", identity$profile_version),
    scr_blank(),
    scr_comment("批准身份（用于审计追溯；本程序独立运行时不读取 review/plan/contract 文件）："),
    scr_marker_line("IDENTITY", paste0("STUDY:", identity$study_id)),
    scr_marker_line("IDENTITY", paste0("ANALYSIS:", identity$analysis_id)),
    scr_marker_line("IDENTITY", paste0("TFL:", identity$tfl_id)),
    scr_marker_line("IDENTITY", paste0("PROFILE:", identity$profile_version)),
    scr_marker_line("IDENTITY", paste0("PLAN_SHA256:", identity$plan_sha256)),
    scr_marker_line("IDENTITY", paste0("APPROVAL_SHA256:", identity$approval_payload_sha256)),
    scr_marker_line("IDENTITY", paste0("CONTRACT_SHA256:", identity$contract_sha256)),
    scr_blank(),
    scr_comment("数据绑定模式：", ir$dataset$binding_mode, if (linked) "（已登记实体 ADaM 文件与 SHA-256）" else "（计划引用模式：无实体 ADaM 文件，仅生成代码）"),
    scr_marker_line("BINDING", ir$dataset$binding_mode),
    scr_comment("批准的数据文件名：", ir$dataset$file, "；格式：", ir$dataset$format),
    scr_blank(),
    scr_comment("所需 R 包与最低功能要求："),
    scr_comment("  mmrm：拟合 REML MMRM 并提供批准的自由度方法；"),
    scr_comment("  emmeans：计算 LS mean 与批准方向的显式权重 contrast；"),
    if (linked) scr_comment("  digest：在读取数据之前计算输入文件 SHA-256 并与批准值比较；") else NULL,
    if (identical(ir$dataset$format, "sas7bdat")) scr_comment("  haven：读取 SAS7BDAT 格式的 ADaM 数据集；") else NULL,
    scr_comment("  本程序不自动安装任何包；缺失时立即以中文错误停止，由统计师在本机安装。"),
    scr_comment("所需包清单：", paste(packages, collapse = ", ")),
    scr_blank(),
    scr_comment("本 TFL 的输出文件名逐字来自 contract，程序运行时不自行推断或拼接："),
    unname(output_markers),
    scr_blank(),
    scr_comment("=========================== 用户配置区（开始） ==========================="),
    scr_comment("以下两个路径是本程序中唯一允许人工修改的内容。"),
    scr_comment("INPUT_DIR：存放批准数据文件的本机只读输入目录；"),
    scr_comment("OUTPUT_DIR：存放本 TFL 结果、诊断与运行记录的本机输出目录。"),
    scr_comment("也可以在运行时用 --input-dir/--output-dir 命令行参数或 MMRM_INPUT_DIR/MMRM_OUTPUT_DIR 环境变量覆盖。"),
    paste0("INPUT_DIR <- ", scr_string("", "input_dir")),
    paste0("OUTPUT_DIR <- ", scr_string("", "output_dir")),
    scr_comment("=========================== 用户配置区（结束） ==========================="),
    scr_blank(),
    scr_comment("除上面的用户配置区之外，请不要修改本程序的任何内容。"),
    scr_comment("任何统计语义变更（数据集、变量映射、派生、筛选、分组、模型、估计量、输出）"),
    scr_comment("都必须回到 analysis plan 修改并重新批准，然后重新生成本程序。"),
    scr_blank(),
    scr_comment("以下常量由生成器写入，属于批准语义，不是用户配置项。"),
    paste0("DATA_AVAILABLE <- ", if (linked) "TRUE" else "FALSE"),
    paste0("CODE_GENERATION_ONLY <- ", if (linked) "FALSE" else "TRUE"),
    paste0("STUDY_ID <- ", scr_string(identity$study_id, "study_id")),
    paste0("ANALYSIS_ID <- ", scr_string(identity$analysis_id, "analysis_id")),
    paste0("TFL_ID <- ", scr_string(identity$tfl_id, "tfl_id")),
    paste0("TFL_TITLE <- ", scr_string(identity$title, "title")),
    paste0("PROFILE_VERSION <- ", scr_string(identity$profile_version, "profile_version")),
    paste0("PLAN_SHA256 <- ", scr_string(identity$plan_sha256, "plan_sha256")),
    paste0("APPROVAL_PAYLOAD_SHA256 <- ", scr_string(identity$approval_payload_sha256, "approval_sha256")),
    paste0("CONTRACT_SHA256 <- ", scr_string(identity$contract_sha256, "contract_sha256")),
    paste0("DATASET_BINDING_MODE <- ", scr_string(ir$dataset$binding_mode, "binding_mode")),
    paste0("DATASET_FILE <- ", scr_string(ir$dataset$file, "dataset_file")),
    paste0("DATASET_FORMAT <- ", scr_string(ir$dataset$format, "dataset_format")),
    paste0("EXPECTED_INPUT_SHA256 <- ", if (linked) scr_string(toupper(ir$dataset$sha256), "dataset_sha256") else scr_string("", "dataset_sha256")),
    paste0("RAW_OUTPUT_FILE <- ", scr_string(ir$output$r_raw_file, "r_raw_file")),
    paste0("FINAL_OUTPUT_FILE <- ", scr_string(ir$output$r_final_file, "r_final_file")),
    paste0("DIAGNOSTIC_OUTPUT_FILE <- ", scr_string(ir$output$r_diagnostic_file, "r_diagnostic_file")),
    paste0("RUN_RECORD_OUTPUT_FILE <- ", scr_string(ir$output$r_run_record_file, "r_run_record_file")),
    "RUN_STARTED_UTC <- format(Sys.time(), tz = \"UTC\", format = \"%Y-%m-%dT%H:%M:%SZ\")"
  )
}

scr_section_2 <- function(ir) {
  linked <- identical(ir$dataset$binding_mode, "linked")
  packages <- c("mmrm", "emmeans")
  if (linked) packages <- c("digest", packages)
  if (identical(ir$dataset$format, "sas7bdat")) packages <- c(packages, "haven")
  package_lines <- unlist(lapply(packages, function(package) c(
    scr_marker_line("PACKAGE", package),
    paste0("if (!requireNamespace(", scr_string(package, "package"), ", quietly = TRUE)) stop(\"缺少必需的 R 包：", package, "。请在本机安装该包后重新运行本程序。\")")
  )), use.names = FALSE)
  gate_lines <- c(
    scr_comment("检查 1：code-generation-only gate。它是生成常量，位于全部数据与模型代码之前。"),
    if (!linked) scr_marker_line("GATE", "PLANNED_CODE_GENERATION_ONLY") else NULL,
    scr_comment("planned 模式属于合法状态，不是运行错误：打印中文说明后以退出码 0 正常结束，"),
    scr_comment("不读取数据、不拟合模型、不创建 raw/final/model/diagnostic/run-record 任何文件。"),
    scr_comment("仅把 DATA_AVAILABLE 改成 TRUE 不能绕过本 gate；获得数据后必须重新批准并生成 linked 版本。"),
    "if (isTRUE(CODE_GENERATION_ONLY)) {",
    "  cat(\"当前程序按无 ADaM 数据的 code-generation 模式生成。\\n\")",
    "  cat(\"批准语义已完整内联，但本程序不允许读取数据、拟合模型或生成任何结果文件。\\n\")",
    "  cat(\"请在 ADaM 数据到达并核对文件名、变量映射与批准版本后，重新编译 analysis plan、\\n\")",
    "  cat(\"重新 finalization 与批准，并重新生成 linked 版本的正式程序。\\n\")",
    "  cat(\"分析：\", ANALYSIS_ID, \"；TFL：\", TFL_ID, \"；数据绑定模式：\", DATASET_BINDING_MODE, \"\\n\", sep = \"\")",
    "  quit(save = \"no\", status = 0L)",
    "}",
    "if (!isTRUE(DATA_AVAILABLE)) {",
    "  cat(\"DATA_AVAILABLE 为 FALSE：本次运行不读取数据、不拟合模型，正常结束。\\n\")",
    "  quit(save = \"no\", status = 0L)",
    "}"
  )
  path_lines <- c(
    scr_comment("检查 3：解析输入/输出目录。优先级固定为命令行参数 --input-dir/--output-dir，"),
    scr_comment("其次环境变量 MMRM_INPUT_DIR/MMRM_OUTPUT_DIR，最后第 1 部分用户配置区的 INPUT_DIR/OUTPUT_DIR。"),
    scr_comment("这些通道只能传递路径，不能传递任何统计语义；未知命令行参数必须拒绝。"),
    "program_arguments <- commandArgs(trailingOnly = TRUE)",
    "command_line_input_dir <- \"\"",
    "command_line_output_dir <- \"\"",
    "argument_index <- 1L",
    "while (argument_index <= length(program_arguments)) {",
    "  token <- program_arguments[[argument_index]]",
    "  assign_option <- function(option) {",
    "    if (identical(token, option)) {",
    "      if (length(program_arguments) < argument_index + 1L) stop(\"命令行参数缺少取值：\", option)",
    "      value <- program_arguments[[argument_index + 1L]]",
    "      argument_index <<- argument_index + 2L",
    "      return(value)",
    "    }",
    "    prefix <- paste0(option, \"=\")",
    "    if (startsWith(token, prefix)) {",
    "      argument_index <<- argument_index + 1L",
    "      return(substring(token, nchar(prefix) + 1L))",
    "    }",
    "    NULL",
    "  }",
    "  input_value <- assign_option(\"--input-dir\")",
    "  if (!is.null(input_value)) {",
    "    command_line_input_dir <- input_value",
    "    next",
    "  }",
    "  output_value <- assign_option(\"--output-dir\")",
    "  if (!is.null(output_value)) {",
    "    command_line_output_dir <- output_value",
    "    next",
    "  }",
    "  stop(\"拒绝未知命令行参数：\", token, \"。本程序只接受 --input-dir 与 --output-dir。\")",
    "}",
    "resolve_directory <- function(command_line_value, environment_name, file_value) {",
    "  if (nzchar(command_line_value)) return(command_line_value)",
    "  environment_value <- Sys.getenv(environment_name, \"\")",
    "  if (nzchar(environment_value)) return(environment_value)",
    "  file_value",
    "}",
    "RESOLVED_INPUT_DIR <- resolve_directory(command_line_input_dir, \"MMRM_INPUT_DIR\", INPUT_DIR)",
    "RESOLVED_OUTPUT_DIR <- resolve_directory(command_line_output_dir, \"MMRM_OUTPUT_DIR\", OUTPUT_DIR)",
    "if (!nzchar(trimws(RESOLVED_INPUT_DIR))) stop(\"未配置输入目录：请设置第 1 部分的 INPUT_DIR，或使用 --input-dir / MMRM_INPUT_DIR。\")",
    "if (!nzchar(trimws(RESOLVED_OUTPUT_DIR))) stop(\"未配置输出目录：请设置第 1 部分的 OUTPUT_DIR，或使用 --output-dir / MMRM_OUTPUT_DIR。\")"
  )
  existence_lines <- c(
    scr_comment("检查 4：输入目录与批准数据文件是否存在。"),
    if (linked) scr_marker_line("GATE", "LINKED_FILE") else NULL,
    "if (!dir.exists(RESOLVED_INPUT_DIR)) stop(\"输入目录不存在：\", RESOLVED_INPUT_DIR)",
    "INPUT_FILE_PATH <- file.path(RESOLVED_INPUT_DIR, DATASET_FILE)",
    "if (!file.exists(INPUT_FILE_PATH)) stop(\"批准的输入数据文件不存在：\", INPUT_FILE_PATH)",
    scr_blank(),
    scr_comment("检查 5：输出目录是否存在或可创建。程序绝不写入输入目录。"),
    "if (!dir.exists(RESOLVED_OUTPUT_DIR)) dir.create(RESOLVED_OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)",
    "if (!dir.exists(RESOLVED_OUTPUT_DIR)) stop(\"输出目录不存在且无法创建：\", RESOLVED_OUTPUT_DIR)"
  )
  sha_lines <- if (linked) c(
    scr_blank(),
    scr_comment("检查 6：在读取任何数据之前，计算输入文件 SHA-256 并与批准值以大写比较。"),
    scr_marker_line("GATE", "LINKED_SHA256"),
    "ACTUAL_INPUT_SHA256 <- toupper(digest::digest(file = INPUT_FILE_PATH, algo = \"sha256\"))",
    "if (!identical(ACTUAL_INPUT_SHA256, toupper(EXPECTED_INPUT_SHA256))) {",
    "  stop(\"输入数据文件 SHA-256 与批准值不一致，按设计在读取数据之前阻断：文件=\", INPUT_FILE_PATH,",
    "       \"；expected=\", toupper(EXPECTED_INPUT_SHA256), \"；actual=\", ACTUAL_INPUT_SHA256)",
    "}",
    "cat(\"输入文件 SHA-256 校验通过：\", ACTUAL_INPUT_SHA256, \"\\n\", sep = \"\")"
  ) else c(
    scr_blank(),
    scr_comment("检查 6：planned 模式没有实体文件与批准 SHA-256，程序已在检查 1 正常结束，不进入本路径。"),
    "ACTUAL_INPUT_SHA256 <- \"\""
  )
  c(
    render_r_section_header(2L, program_section_titles()[[2L]]),
    scr_comment("本部分按固定顺序执行运行环境与安全检查；任一检查失败都在建模之前以中文错误停止。"),
    scr_blank(),
    gate_lines,
    scr_blank(),
    scr_comment("检查 2：所需 R 包是否存在。本程序只检查，不安装。"),
    package_lines,
    scr_blank(),
    path_lines,
    scr_blank(),
    existence_lines,
    sha_lines,
    scr_blank(),
    scr_comment("本分析是确定性 MMRM，不需要随机性，因此不设置也不虚构随机种子。")
  )
}

scr_section_3 <- function(ir) {
  read_lines <- if (identical(ir$dataset$format, "csv")) c(
    scr_comment("批准格式为 csv：以显式 UTF-8（容忍 BOM）读取，禁止自动改列名。"),
    "raw_data <- utils::read.csv(INPUT_FILE_PATH, stringsAsFactors = FALSE, check.names = FALSE,",
    "                            fileEncoding = \"UTF-8-BOM\", encoding = \"UTF-8\", na.strings = c(\"NA\", \"\"))"
  ) else c(
    scr_comment("批准格式为 sas7bdat：使用 haven::read_sas() 读取，随后转换为普通 data.frame 且不改列名。"),
    "raw_data <- haven::read_sas(INPUT_FILE_PATH)",
    "raw_data <- as.data.frame(raw_data, stringsAsFactors = FALSE, check.names = FALSE)"
  )
  c(
    render_r_section_header(3L, program_section_titles()[[3L]]),
    scr_comment("本部分只按批准的 dataset.format 生成唯一一种读取分支，读取后立即检查全部批准引用的源变量。"),
    scr_blank(),
    scr_comment("再次确认 code-generation-only 常量，防止有人删除第 2 部分的 gate 后直接读取数据。"),
    "if (isTRUE(CODE_GENERATION_ONLY)) stop(\"本程序为 code-generation-only，不允许读取 ADaM 数据。\")",
    scr_blank(),
    read_lines,
    "if (!is.data.frame(raw_data) || nrow(raw_data) == 0L) stop(\"读取到的 ADaM 数据不是非空 data.frame：\", INPUT_FILE_PATH)",
    "INPUT_ROWS <- nrow(raw_data)",
    "cat(\"已读取输入数据，行数=\", INPUT_ROWS, \"\\n\", sep = \"\")",
    scr_blank(),
    scr_comment("批准的 mappings、derivations、filters、groups 与 endpoint definitions 引用的全部源变量；"),
    scr_comment("缺列时一次列出全部缺失变量后停止，避免统计师逐个试错。"),
    paste0("REQUIRED_SOURCE_VARIABLES <- ", scr_character_vector_literal(ir$source_variables$original, "source_variables")),
    "missing_source_variables <- REQUIRED_SOURCE_VARIABLES[!REQUIRED_SOURCE_VARIABLES %in% names(raw_data)]",
    "if (0L < length(missing_source_variables)) stop(\"ADaM 数据缺少以下批准引用的源变量：\", paste(missing_source_variables, collapse = \", \"))"
  )
}

scr_derivation_lines <- function(ir) {
  if (!length(ir$derivations)) return(scr_comment("批准的 analysis plan 没有 derivations，本步骤没有需要执行的派生。"))
  unlist(lapply(seq_along(ir$derivations), function(index) {
    derivation <- ir$derivations[[index]]
    context <- paste0("derivations[[", index, "]]")
    level_lines <- unlist(lapply(derivation$levels, function(level) c(
      paste0("derivation_hit <- !derivation_missing & derivation_input %in% ", scr_vector_literal(level$source_values, context)),
      paste0("derivation_output[derivation_hit] <- ", scr_scalar_literal(level$target_value, context)),
      "derivation_matched <- derivation_matched | derivation_hit"
    )), use.names = FALSE)
    unmatched_lines <- switch(
      derivation$unmatched,
      error = paste0("if (any(derivation_unmatched)) stop(\"派生 ", derivation$id, " 存在未在批准 recode 规则中定义的源值，共 \", sum(derivation_unmatched), \" 行，按批准的 unmatched=error 策略停止。\")"),
      preserve = "derivation_output[derivation_unmatched] <- derivation_input[derivation_unmatched]",
      set_missing = scr_comment("批准的 unmatched=set_missing 策略：未匹配值保持缺失，无需额外赋值。"),
      stop("PROGRAM-R-RENDER-RECODE-POLICY:", context)
    )
    missing_lines <- switch(
      derivation$missing,
      error = paste0("if (any(derivation_missing)) stop(\"派生 ", derivation$id, " 的源变量存在缺失值，共 \", sum(derivation_missing), \" 行，按批准的 missing=error 策略停止。\")"),
      preserve = "derivation_output[derivation_missing] <- derivation_input[derivation_missing]",
      set_missing = scr_comment("批准的 missing=set_missing 策略：缺失值保持缺失，无需额外赋值。"),
      stop("PROGRAM-R-RENDER-RECODE-POLICY:", context)
    )
    c(
      scr_blank(),
      scr_marker_line("DERIVATION", derivation$id),
      scr_why_line("DERIVATION", derivation$id, paste0("按批准的 recode 规则把源变量 ", derivation$source_variable, " 归并为分析变量 ", derivation$target_variable, "，规范化类型为 ", derivation$value_type, "，未匹配策略=", derivation$unmatched, "，缺失策略=", derivation$missing, "。")),
      paste0("derivation_input <- ", scr_column("raw_data", derivation$source_variable, context)),
      paste0("derivation_output <- rep(", scr_missing_literal(derivation$value_type), ", length(derivation_input))"),
      "derivation_matched <- rep(FALSE, length(derivation_input))",
      "derivation_missing <- is.na(derivation_input) | (is.character(derivation_input) & !nzchar(trimws(as.character(derivation_input))))",
      level_lines,
      "derivation_unmatched <- !derivation_missing & !derivation_matched",
      unmatched_lines,
      missing_lines,
      paste0("if (", scr_string(derivation$target_variable, context), " %in% names(raw_data)) stop(\"派生目标变量已存在，与批准语义冲突：", derivation$target_variable, "\")"),
      paste0(scr_column("raw_data", derivation$target_variable, context), " <- derivation_output"),
      paste0("DERIVATION_COUNTS <- rbind(DERIVATION_COUNTS, data.frame(derivation_id = ", scr_string(derivation$id, context), ", matched_rows = sum(derivation_matched), unmatched_rows = sum(derivation_unmatched), missing_rows = sum(derivation_missing), stringsAsFactors = FALSE))")
    )
  }), use.names = FALSE)
}

scr_filter_lines <- function(ir) {
  if (!length(ir$filters)) return(c(scr_comment("批准的 analysis plan 没有 population filters，全部读取记录进入后续分组。"), "POPULATION_FILTERED_ROWS <- nrow(analysis_input)"))
  lines <- unlist(lapply(seq_along(ir$filters), function(index) {
    filter <- ir$filters[[index]]
    context <- paste0("filters[[", index, "]]")
    c(
      scr_blank(),
      scr_marker_line("FILTER", as.character(index)),
      scr_why_line("FILTER", as.character(index), paste0("按批准的分析人群定义，仅保留变量 ", filter$variable, " 满足 ", filter$operator, " 条件的记录。")),
      paste0("filter_keep <- ", scr_predicate_expression(filter, "analysis_input", context)),
      "filter_keep[is.na(filter_keep)] <- FALSE",
      "analysis_input <- analysis_input[filter_keep, , drop = FALSE]"
    )
  }), use.names = FALSE)
  c(lines, "POPULATION_FILTERED_ROWS <- nrow(analysis_input)", "if (nrow(analysis_input) == 0L) stop(\"应用批准的 population filters 之后没有剩余记录。\")")
}

scr_group_lines <- function(ir) {
  unlist(lapply(seq_along(ir$groups), function(index) {
    group <- ir$groups[[index]]
    context <- paste0("groups[[", index, "]]")
    definitions <- Filter(function(definition) identical(definition$group_id, group$id), ir$endpoint_definitions)
    if (length(definitions) != 1L) stop("PROGRAM-R-RENDER-ENDPOINT:", group$id)
    definition <- definitions[[1L]]
    predicate_lines <- if (!length(group$predicates)) scr_comment("该分组没有额外 predicate，沿用筛选后的全部记录。") else vapply(seq_along(group$predicates), function(j) paste0("group_keep <- group_keep & ", scr_predicate_expression(group$predicates[[j]], "analysis_input", paste0(context, ".predicates[[", j, "]]"))), character(1))
    applicable <- Filter(function(dimension) !dimension$variable %in% c("fixed", "not_applicable"), definition$dimensions)
    dimension_lines <- unlist(lapply(names(applicable), function(name) {
      dimension <- applicable[[name]]
      c(
        paste0("endpoint_observed <- as.character(", scr_column("group_data", dimension$variable, context), ")"),
        "endpoint_observed <- endpoint_observed[!is.na(endpoint_observed)]",
        paste0("endpoint_unapproved <- unique(endpoint_observed[!endpoint_observed %in% ", scr_character_vector_literal(as.character(dimension$values), context), "])"),
        paste0("if (0L < length(endpoint_unapproved)) stop(\"分组 ", group$id, " 的 endpoint 维度 ", name, "（变量 ", dimension$variable, "）出现未批准取值：\", paste(endpoint_unapproved, collapse = \", \"))")
      )
    }), use.names = FALSE)
    c(
      scr_blank(),
      scr_marker_line("GROUP", group$id),
      scr_why_line("GROUP", group$id, paste0("按批准的分组定义选出属于 ", group$label, " 的记录，分组之间必须互斥。")),
      "group_keep <- rep(TRUE, nrow(analysis_input))",
      predicate_lines,
      "group_keep[is.na(group_keep)] <- FALSE",
      "group_data <- analysis_input[group_keep, , drop = FALSE]",
      scr_marker_line("ENDPOINT", definition$group_id),
      scr_why_line("ENDPOINT", definition$group_id, paste0("按批准的 endpoint definition 校验 endpoint 变量 ", definition$endpoint_variable, " 与各维度取值，行分配规则为 ", definition$row_allocation_rule, "。")),
      dimension_lines,
      paste0("GROUP_FRAMES[[", scr_string(group$id, context), "]] <- build_group_frame(group_data, ", scr_string(group$id, context), ", ", scr_string(group$label, context), ")"),
      paste0("GROUP_ALLOCATION <- rbind(GROUP_ALLOCATION, data.frame(source_row_id = group_data[[\".self_contained_row_id\"]], group_id = ", scr_string(group$id, context), ", stringsAsFactors = FALSE))")
    )
  }), use.names = FALSE)
}

scr_section_4 <- function(ir) {
  mappings <- ir$mappings
  has_treatment <- !is.null(mappings$treatment)
  visit_label_variable <- if (is.null(mappings$visit_label)) mappings$visit else mappings$visit_label
  mapping_lines <- unlist(lapply(names(mappings), function(name) c(
    scr_marker_line("MAPPING", paste0(name, ":", mappings[[name]])),
    scr_why_line("MAPPING", name, scr_mapping_reason(name))
  )), use.names = FALSE)
  treatment_lines <- if (has_treatment) c(
    scr_blank(),
    scr_comment("步骤 9：校验观测到的 treatment level 与批准 levels 完全一致。"),
    scr_marker_line("TREATMENT_REFERENCE", ir$treatment$reference),
    scr_why_line("TREATMENT_REFERENCE", ir$treatment$reference, paste0("批准的参照组为 ", ir$treatment$reference, "，对比方向为 ", ir$treatment$contrast_direction, "；factor 首个水平必须是参照组。")),
    paste0("APPROVED_TREATMENT_LEVELS <- ", scr_character_vector_literal(ir$treatment$levels, "treatment_levels")),
    paste0("TREATMENT_REFERENCE_LEVEL <- ", scr_string(ir$treatment$reference, "treatment_reference")),
    paste0("TREATMENT_COMPARATOR_LEVEL <- ", scr_string(ir$treatment$comparator, "treatment_comparator")),
    "observed_treatment_levels <- unique(analysis_data$treatment)",
    "unapproved_treatment_levels <- setdiff(observed_treatment_levels, APPROVED_TREATMENT_LEVELS)",
    "if (0L < length(unapproved_treatment_levels)) stop(\"观测到未批准的 treatment level：\", paste(unapproved_treatment_levels, collapse = \", \"))",
    "if (!all(APPROVED_TREATMENT_LEVELS %in% observed_treatment_levels)) stop(\"批准的全部 treatment level 必须都出现在分析数据中：\", paste(APPROVED_TREATMENT_LEVELS, collapse = \", \"))"
  ) else c(
    scr_blank(),
    scr_comment("步骤 9：批准的 analysis plan 没有 treatment 映射（单臂研究），因此没有 treatment level 校验。"),
    "APPROVED_TREATMENT_LEVELS <- \"ALL\"",
    "TREATMENT_REFERENCE_LEVEL <- \"\"",
    "TREATMENT_COMPARATOR_LEVEL <- \"\""
  )
  required_complete <- c("subject", "response", "baseline", "visit")
  if (has_treatment) required_complete <- c(required_complete, "treatment")
  c(
    render_r_section_header(4L, program_section_titles()[[4L]]),
    scr_comment("本部分严格按批准设计的 1-11 顺序执行数据处理与质量控制；任一硬性 QC 失败都在建模之前停止。"),
    "DERIVATION_COUNTS <- data.frame(derivation_id = character(), matched_rows = integer(), unmatched_rows = integer(), missing_rows = integer(), stringsAsFactors = FALSE)",
    "GROUP_FRAMES <- list()",
    "GROUP_ALLOCATION <- data.frame(source_row_id = integer(), group_id = character(), stringsAsFactors = FALSE)",
    scr_blank(),
    scr_comment("步骤 5 使用的标准变量构造 helper，内联在本部分，不依赖任何外部代码。"),
    "build_group_frame <- function(group_data, group_id, group_label) {",
    "  if (nrow(group_data) == 0L) return(NULL)",
    "  data.frame(",
    paste0("    subject = as.character(", scr_column("group_data", mappings$subject, "mappings.subject"), "),"),
    paste0("    response = suppressWarnings(as.numeric(", scr_column("group_data", mappings$response, "mappings.response"), ")),"),
    paste0("    baseline = suppressWarnings(as.numeric(", scr_column("group_data", mappings$baseline, "mappings.baseline"), ")),"),
    paste0("    visit = as.character(", scr_column("group_data", mappings$visit, "mappings.visit"), "),"),
    paste0("    visit_label = as.character(", scr_column("group_data", visit_label_variable, "mappings.visit_label"), "),"),
    if (has_treatment) paste0("    treatment = as.character(", scr_column("group_data", mappings$treatment, "mappings.treatment"), "),") else "    treatment = rep(\"ALL\", nrow(group_data)),",
    "    analysis_group_id = group_id,",
    "    analysis_group_label = group_label,",
    "    stringsAsFactors = FALSE, check.names = FALSE",
    "  )",
    "}",
    scr_blank(),
    scr_comment("步骤 1：执行批准的 derivations。派生只按批准的显式取值向量归并，不做任何推断。"),
    scr_derivation_lines(ir),
    scr_blank(),
    scr_comment("步骤 2：应用批准的 population filters。"),
    "analysis_input <- raw_data",
    scr_filter_lines(ir),
    scr_blank(),
    scr_comment("步骤 3：为每条筛选后记录分配唯一行号，然后按批准定义分配 analysis groups 与 endpoint definitions。"),
    "analysis_input[[\".self_contained_row_id\"]] <- seq_len(nrow(analysis_input))",
    scr_group_lines(ir),
    scr_blank(),
    scr_comment("步骤 4：检查一条源记录不能同时进入多个互斥分组。"),
    "overlapping_rows <- unique(GROUP_ALLOCATION$source_row_id[duplicated(GROUP_ALLOCATION$source_row_id)])",
    "if (0L < length(overlapping_rows)) {",
    "  overlapping_detail <- vapply(overlapping_rows, function(row_id) paste0(row_id, \"=[\", paste(GROUP_ALLOCATION$group_id[GROUP_ALLOCATION$source_row_id == row_id], collapse = \", \"), \"]\"), character(1))",
    "  stop(\"互斥分组重叠：以下筛选后源记录同时进入多个分组：\", paste(overlapping_detail, collapse = \"; \"))",
    "}",
    scr_blank(),
    scr_comment("步骤 5：创建标准变量 subject、response、baseline、visit、visit label 与 treatment。"),
    scr_comment("下列 marker 逐字记录批准的变量映射，便于审阅时与 analysis plan 对照。"),
    mapping_lines,
    "GROUP_FRAMES <- GROUP_FRAMES[!vapply(GROUP_FRAMES, is.null, logical(1))]",
    "if (length(GROUP_FRAMES) == 0L) stop(\"批准的 filters 与 groups 未产生任何分析记录。\")",
    "analysis_data <- do.call(rbind, GROUP_FRAMES)",
    "row.names(analysis_data) <- NULL",
    scr_blank(),
    scr_comment("步骤 6：删除批准规则定义的必需变量缺失行，并记录删除数量。"),
    paste0("REQUIRED_COMPLETE_COLUMNS <- ", scr_character_vector_literal(required_complete, "required_complete")),
    "complete_rows <- stats::complete.cases(analysis_data[REQUIRED_COMPLETE_COLUMNS]) & nzchar(trimws(analysis_data$subject))",
    if (has_treatment) "complete_rows <- complete_rows & nzchar(trimws(analysis_data$treatment))" else scr_comment("单臂研究的 treatment 为常量 ALL，不参与缺失判断。"),
    "MISSING_REQUIRED_ROWS <- sum(!complete_rows)",
    "analysis_data <- analysis_data[complete_rows, , drop = FALSE]",
    "if (nrow(analysis_data) == 0L) stop(\"删除必需变量缺失行之后没有剩余分析记录。\")",
    "cat(\"删除必需变量缺失行数=\", MISSING_REQUIRED_ROWS, \"\\n\", sep = \"\")",
    scr_blank(),
    scr_comment("步骤 7：检查 subject/分组/visit 组合唯一。"),
    "duplicate_keys <- duplicated(analysis_data[c(\"subject\", \"analysis_group_id\", \"visit\")]) | duplicated(analysis_data[c(\"subject\", \"analysis_group_id\", \"visit\")], fromLast = TRUE)",
    "if (any(duplicate_keys)) stop(\"subject/分组/visit 组合必须唯一，发现重复记录 \", sum(duplicate_keys), \" 行。\")",
    scr_blank(),
    scr_comment("步骤 8：检查同一 subject 与分组内 baseline 一致。"),
    "baseline_consistency <- stats::aggregate(baseline ~ subject + analysis_group_id, analysis_data, function(values) length(unique(values)))",
    "if (any(1L < baseline_consistency$baseline)) stop(\"同一 subject 与分组内的 baseline 必须一致，发现不一致的 subject 数=\", sum(1L < baseline_consistency$baseline))",
    treatment_lines,
    scr_blank(),
    scr_comment("步骤 10：固定 visit 与 treatment 的 factor levels，保证模型与 TFL 顺序确定。"),
    "visit_levels <- unique(analysis_data[c(\"visit\", \"visit_label\")])",
    "numeric_visit <- suppressWarnings(as.numeric(visit_levels$visit))",
    "visit_order <- if (all(!is.na(numeric_visit))) order(numeric_visit) else order(visit_levels$visit)",
    "visit_levels <- visit_levels[visit_order, , drop = FALSE]",
    "if (anyDuplicated(visit_levels$visit)) stop(\"一个 visit 取值对应多个 visit label，无法确定 TFL 行顺序。\")",
    "analysis_data$subject_f <- factor(analysis_data$subject)",
    "analysis_data$visit_f <- factor(analysis_data$visit, levels = visit_levels$visit)",
    "analysis_data$treatment_f <- factor(analysis_data$treatment, levels = APPROVED_TREATMENT_LEVELS)",
    "if (any(is.na(analysis_data$visit_f)) || any(is.na(analysis_data$treatment_f))) stop(\"固定 factor levels 之后出现未覆盖取值，请核对批准的 levels。\")",
    scr_blank(),
    scr_comment("步骤 11：汇总数据处理计数，留在内存中供第 8 部分诊断使用。"),
    "PROCESSING_COUNTS <- list(",
    "  input_rows = INPUT_ROWS,",
    "  population_filtered_rows = POPULATION_FILTERED_ROWS,",
    "  analysis_rows = nrow(analysis_data),",
    "  missing_required_rows = MISSING_REQUIRED_ROWS,",
    "  subject_count = length(unique(analysis_data$subject)),",
    "  visit_level_count = nlevels(analysis_data$visit_f),",
    "  treatment_level_count = nlevels(analysis_data$treatment_f)",
    ")",
    "cat(\"数据处理计数：输入=\", PROCESSING_COUNTS$input_rows, \"，筛选后=\", PROCESSING_COUNTS$population_filtered_rows,",
    "    \"，分析=\", PROCESSING_COUNTS$analysis_rows, \"，缺失删除=\", PROCESSING_COUNTS$missing_required_rows, \"\\n\", sep = \"\")",
    scr_blank(),
    "# 至此完成数据处理。以下代码开始进行 MMRM 模型拟合；请勿混淆两部分职责。"
  )
}

scr_section_5 <- function(ir) {
  effects <- as.character(unlist(ir$fixed_effects, use.names = FALSE))
  terms <- vapply(effects, scr_fixed_effect_term, character(1))
  effect_lines <- unlist(lapply(seq_along(effects), function(index) c(
    scr_marker_line("FIXED_EFFECT", effects[[index]]),
    scr_why_line("FIXED_EFFECT", effects[[index]], scr_fixed_effect_reason(effects[[index]]))
  )), use.names = FALSE)
  covariance_lines <- unlist(lapply(seq_along(ir$covariance_order), function(index) c(
    scr_marker_line("COVARIANCE", ir$covariance_order[[index]]),
    scr_why_line("COVARIANCE", ir$covariance_order[[index]], scr_covariance_reason(ir$covariance_order[[index]], index))
  )), use.names = FALSE)
  covariance_map <- paste0("c(", paste(vapply(ir$covariance_order, function(covariance) paste0(scr_string(covariance, "covariance"), " = ", scr_string(scr_covariance_term(covariance), "covariance_term")), character(1)), collapse = ", "), ")")
  c(
    render_r_section_header(5L, program_section_titles()[[5L]]),
    scr_comment("本部分显式构造并打印固定效应 formula、REML 设定、自由度方法与协方差主/fallback 顺序，"),
    scr_comment("对每个 analysis group 独立拟合，并逐次记录每个协方差结构的尝试结果。"),
    scr_blank(),
    scr_comment("批准的固定效应（顺序逐字来自 analysis plan）："),
    effect_lines,
    scr_blank(),
    scr_comment("批准的估计方法为 REML；本 profile 不允许改为 ML。"),
    scr_marker_line("REML", "TRUE"),
    scr_why_line("REML", "TRUE", "批准的方差成分估计方法为 REML，可减少小样本方差低估。"),
    scr_blank(),
    scr_comment("批准的协方差结构顺序（第一个为 primary，其后按顺序 fallback）："),
    covariance_lines,
    scr_blank(),
    scr_comment("批准的自由度方法："),
    scr_marker_line("DF_METHOD", ir$df_method),
    scr_why_line("DF_METHOD", ir$df_method, paste0("批准的小样本自由度方法为 ", ir$df_method, "，用于 LS mean 与对比的推断。")),
    scr_blank(),
    paste0("MODEL_FIXED_TERMS <- ", scr_character_vector_literal(unname(terms), "fixed_terms")),
    paste0("COVARIANCE_ORDER <- ", scr_character_vector_literal(ir$covariance_order, "covariance_order")),
    paste0("COVARIANCE_TERMS <- ", covariance_map),
    paste0("DF_METHOD <- ", scr_string(ir$df_method, "df_method")),
    "MODEL_REML <- TRUE",
    "model_formula_text <- function(covariance) paste(\"response ~\", paste(c(MODEL_FIXED_TERMS, COVARIANCE_TERMS[[covariance]]), collapse = \" + \"))",
    "mmrm_control_for <- function(covariance) {",
    "  control_arguments <- list(method = DF_METHOD)",
    "  if (identical(DF_METHOD, \"Kenward-Roger\") && identical(covariance, \"UN\")) control_arguments$vcov <- \"Kenward-Roger-Linear\"",
    "  do.call(mmrm::mmrm_control, control_arguments)",
    "}",
    "for (covariance in COVARIANCE_ORDER) cat(\"批准协方差 \", covariance, \" 对应 formula：\", model_formula_text(covariance), \"\\n\", sep = \"\")",
    "cat(\"REML=\", MODEL_REML, \"；自由度方法=\", DF_METHOD, \"\\n\", sep = \"\")",
    scr_blank(),
    "FIT_ATTEMPTS <- data.frame(analysis_group_id = character(), covariance = character(), outcome = character(), detail = character(), stringsAsFactors = FALSE)",
    "GROUP_FITS <- list()",
    "for (group_id in names(GROUP_FRAMES)) {",
    "  group_analysis_data <- analysis_data[analysis_data$analysis_group_id == group_id, , drop = FALSE]",
    "  selected_fit <- NULL",
    "  selected_covariance <- \"\"",
    "  group_warnings <- character()",
    "  if (length(unique(group_analysis_data$subject)) < 2L || nlevels(droplevels(group_analysis_data$visit_f)) < 2L) {",
    "    stop(\"分组 \", group_id, \" 的 subject 或 visit 水平不足，无法拟合 MMRM。\")",
    "  }",
    "  for (covariance in COVARIANCE_ORDER) {",
    "    attempt_warnings <- character()",
    "    fit <- tryCatch(",
    "      withCallingHandlers(",
    "        mmrm::mmrm(stats::as.formula(model_formula_text(covariance)), data = group_analysis_data, reml = MODEL_REML, control = mmrm_control_for(covariance)),",
    "        warning = function(condition) { attempt_warnings <<- c(attempt_warnings, conditionMessage(condition)); invokeRestart(\"muffleWarning\") },",
    "        message = function(condition) { attempt_warnings <<- c(attempt_warnings, conditionMessage(condition)); invokeRestart(\"muffleMessage\") }",
    "      ),",
    "      error = function(condition) condition",
    "    )",
    "    nonconverged <- any(grepl(\"non.?converg|fail.*converg|optimizer.*fail|diverg\", attempt_warnings, ignore.case = TRUE, perl = TRUE))",
    "    outcome <- if (inherits(fit, \"error\")) \"failed\" else if (nonconverged) \"not_converged\" else \"success\"",
    "    detail <- if (inherits(fit, \"error\")) conditionMessage(fit) else paste(attempt_warnings, collapse = \" | \")",
    "    FIT_ATTEMPTS <- rbind(FIT_ATTEMPTS, data.frame(analysis_group_id = group_id, covariance = covariance, outcome = outcome, detail = detail, stringsAsFactors = FALSE))",
    "    group_warnings <- c(group_warnings, attempt_warnings)",
    "    cat(\"分组 \", group_id, \" 尝试协方差 \", covariance, \"：\", outcome, \"\\n\", sep = \"\")",
    "    if (identical(outcome, \"success\")) {",
    "      selected_fit <- fit",
    "      selected_covariance <- covariance",
    "      break",
    "    }",
    "  }",
    "  if (is.null(selected_fit)) cat(\"分组 \", group_id, \" 的全部批准协方差结构均未成功，按设计不生成完整状态的 TFL。\\n\", sep = \"\")",
    "  GROUP_FITS[[group_id]] <- list(fit = selected_fit, covariance = selected_covariance, warnings = unique(group_warnings), data = group_analysis_data)",
    "}",
    "MODEL_SUCCESS <- 0L < length(GROUP_FITS) && all(vapply(GROUP_FITS, function(entry) !is.null(entry$fit), logical(1)))",
    "COVARIANCE_PATH <- if (nrow(FIT_ATTEMPTS) == 0L) \"\" else paste(paste0(FIT_ATTEMPTS$analysis_group_id, \"/\", FIT_ATTEMPTS$covariance, \"=\", FIT_ATTEMPTS$outcome), collapse = \" | \")",
    "SELECTED_COVARIANCE <- paste(unique(vapply(GROUP_FITS, function(entry) entry$covariance, character(1))), collapse = \" | \")"
  )
}

scr_section_6 <- function(ir) {
  enabled <- names(ir$estimands)[vapply(ir$estimands, isTRUE, logical(1))]
  estimand_lines <- unlist(lapply(enabled, function(name) c(
    scr_marker_line("ESTIMAND", name),
    scr_why_line("ESTIMAND", name, scr_estimand_reason(name))
  )), use.names = FALSE)
  confidence_level <- if (is.null(ir$treatment)) 0.95 else as.numeric(ir$treatment$confidence_level)
  treatment_blocks <- if ("treatment_visit_lsmeans" %in% enabled) c(
    "    treatment_grid <- emmeans::emmeans(entry$fit, ~ treatment_f | visit_f)",
    "    RAW_ROWS[[length(RAW_ROWS) + 1L]] <- inference_rows(",
    "      summary(treatment_grid, infer = c(TRUE, TRUE), level = CONFIDENCE_LEVEL, adjust = MULTIPLICITY_ADJUSTMENT),",
    "      group_id, group_label, \"treatment_visit_lsmean\", entry$covariance, \"treatment_f\", \"\")",
    if ("pairwise_differences" %in% enabled) c(
      "    contrast_weights <- stats::setNames(list(CONTRAST_WEIGHTS), CONTRAST_LABEL)",
      "    comparison <- emmeans::contrast(treatment_grid, method = contrast_weights, by = \"visit_f\", adjust = MULTIPLICITY_ADJUSTMENT)",
      "    RAW_ROWS[[length(RAW_ROWS) + 1L]] <- inference_rows(",
      "      summary(comparison, infer = c(TRUE, TRUE), level = CONFIDENCE_LEVEL, adjust = MULTIPLICITY_ADJUSTMENT),",
      "      group_id, group_label, \"treatment_pairwise_difference\", entry$covariance, \"\", \"contrast\")"
    ) else NULL
  ) else NULL
  c(
    render_r_section_header(6L, program_section_titles()[[6L]]),
    scr_comment("本部分只渲染批准 plan 中显式为 true 的估计量；未批准的估计量不会出现在代码中。"),
    scr_blank(),
    estimand_lines,
    scr_blank(),
    paste0("CONFIDENCE_LEVEL <- ", scr_scalar_literal(confidence_level, "confidence_level")),
    paste0("MULTIPLICITY_ADJUSTMENT <- ", scr_string(if (is.null(ir$treatment)) "none" else ir$treatment$multiplicity_adjustment, "multiplicity")),
    if (!is.null(ir$treatment)) paste0("CONTRAST_LABEL <- ", scr_string(paste0(ir$treatment$comparator, " - ", ir$treatment$reference), "contrast_label")) else "CONTRAST_LABEL <- \"\"",
    scr_comment("显式权重按批准的 factor 顺序（参照组在前、比较组在后）与批准方向 comparator 减 reference 构造。"),
    if (!is.null(ir$treatment)) "CONTRAST_WEIGHTS <- c(-1, 1)" else "CONTRAST_WEIGHTS <- numeric(0)",
    scr_blank(),
    scr_comment("推断结果整形 helper，内联在本部分。"),
    "inference_rows <- function(summary_data, group_id, group_label, estimand, covariance, treatment_column, contrast_column) {",
    "  frame <- as.data.frame(summary_data, stringsAsFactors = FALSE)",
    "  numeric_column <- function(name) if (name %in% names(frame)) as.numeric(frame[[name]]) else rep(NA_real_, nrow(frame))",
    "  estimate <- if (\"emmean\" %in% names(frame)) as.numeric(frame$emmean) else numeric_column(\"estimate\")",
    "  if (!\"visit_f\" %in% names(frame)) stop(\"推断结果缺少 visit_f 列，无法与批准的 TFL 行结构对齐。\")",
    "  data.frame(",
    "    analysis_id = ANALYSIS_ID, tfl_id = TFL_ID, analysis_group_id = group_id, analysis_group_label = group_label,",
    "    estimand = estimand,",
    "    treatment = if (nzchar(treatment_column) && treatment_column %in% names(frame)) as.character(frame[[treatment_column]]) else \"\",",
    "    contrast = if (nzchar(contrast_column) && contrast_column %in% names(frame)) as.character(frame[[contrast_column]]) else \"\",",
    "    visit = as.character(frame$visit_f),",
    "    estimate = estimate, standard_error = numeric_column(\"SE\"), degrees_of_freedom = numeric_column(\"df\"),",
    "    lower_confidence_limit = numeric_column(\"lower.CL\"), upper_confidence_limit = numeric_column(\"upper.CL\"),",
    "    statistic = numeric_column(\"t.ratio\"), p_value = numeric_column(\"p.value\"),",
    "    covariance_used = covariance, stringsAsFactors = FALSE",
    "  )",
    "}",
    scr_blank(),
    "RAW_ROWS <- list()",
    "INFERENCE_COMPLETE <- TRUE",
    "for (group_id in names(GROUP_FITS)) {",
    "  entry <- GROUP_FITS[[group_id]]",
    "  if (is.null(entry$fit)) {",
    "    INFERENCE_COMPLETE <- FALSE",
    "    next",
    "  }",
    "  group_label <- unique(entry$data$analysis_group_label)[[1L]]",
    "  visit_grid <- emmeans::emmeans(entry$fit, ~ visit_f)",
    "  RAW_ROWS[[length(RAW_ROWS) + 1L]] <- inference_rows(",
    "    summary(visit_grid, infer = c(TRUE, TRUE), level = CONFIDENCE_LEVEL, adjust = MULTIPLICITY_ADJUSTMENT),",
    "    group_id, group_label, \"visit_lsmean\", entry$covariance, \"\", \"\")",
    treatment_blocks,
    "}",
    "RAW_RESULTS <- if (length(RAW_ROWS) == 0L) NULL else do.call(rbind, RAW_ROWS)",
    scr_blank(),
    scr_comment("输出前检查 estimate、SE、df、置信区间与 p-value 是否完整；任一缺失都不允许写出正式 TFL。"),
    "INFERENCE_COLUMNS <- c(\"estimate\", \"standard_error\", \"degrees_of_freedom\", \"lower_confidence_limit\", \"upper_confidence_limit\", \"p_value\")",
    "if (is.null(RAW_RESULTS) || nrow(RAW_RESULTS) == 0L) INFERENCE_COMPLETE <- FALSE",
    "if (!is.null(RAW_RESULTS) && 0L < nrow(RAW_RESULTS) && !all(stats::complete.cases(RAW_RESULTS[INFERENCE_COLUMNS]))) INFERENCE_COMPLETE <- FALSE",
    "cat(\"推断字段完整性=\", INFERENCE_COMPLETE, \"\\n\", sep = \"\")"
  )
}

scr_section_7 <- function(ir) {
  enabled <- names(ir$estimands)[vapply(ir$estimands, isTRUE, logical(1))]
  primary_estimand <- if ("treatment_visit_lsmeans" %in% enabled) "treatment_visit_lsmean" else "visit_lsmean"
  contrast_block <- if ("pairwise_differences" %in% enabled) c(
    "  contrast_source <- raw[raw$estimand == \"treatment_pairwise_difference\", , drop = FALSE]",
    "  for (i in seq_len(nrow(contrast_source))) {",
    "    row <- contrast_source[i, , drop = FALSE]",
    "    visit_label <- unique(prepared$visit_label[prepared$visit == row$visit])",
    "    rows[[length(rows) + 1L]] <- data.frame(",
    "      analysis_id = ANALYSIS_ID, tfl_id = TFL_ID, analysis_group_id = row$analysis_group_id,",
    "      analysis_group_label = row$analysis_group_label, row_type = \"treatment_contrast\",",
    "      estimand = \"treatment_pairwise_difference\", treatment = \"\", contrast = row$contrast,",
    "      visit = if (length(visit_label) == 1L) visit_label else row$visit,",
    "      observed_n = \"\", observed_mean = \"\", observed_sd = \"\", observed_median = \"\", observed_min = \"\", observed_max = \"\",",
    "      baseline_n = \"\", baseline_mean = \"\", baseline_sd = \"\",",
    "      mmrm_estimate = format_number(row$estimate, 3L), standard_error = format_number(row$standard_error, 3L),",
    "      confidence_interval = format_confidence_interval(row$lower_confidence_limit, row$upper_confidence_limit),",
    "      degrees_of_freedom = format_number(row$degrees_of_freedom, 1L), statistic = format_number(row$statistic, 3L),",
    "      p_value = format_p_value(row$p_value), covariance_used = row$covariance_used, stringsAsFactors = FALSE)",
    "  }"
  ) else "  # 批准的 plan 未启用 pairwise differences，最终 table 不包含对比行。"
  c(
    render_r_section_header(7L, program_section_titles()[[7L]]),
    scr_comment("本部分把 observed summary 与 MMRM 推断结果整理成该 TFL 专属的最终 table，"),
    scr_comment("使用固定小数位与 p-value 格式，输出文件名逐字来自 contract，编码为 UTF-8 BOM CSV。"),
    scr_blank(),
    paste0("PRIMARY_ESTIMAND <- ", scr_string(primary_estimand, "primary_estimand")),
    "format_number <- function(value, digits) ifelse(is.na(value), \"\", formatC(as.numeric(value), format = \"f\", digits = digits))",
    "format_confidence_interval <- function(lower, upper) ifelse(is.na(lower) | is.na(upper), \"\", paste0(\"(\", format_number(lower, 3L), \", \", format_number(upper, 3L), \")\"))",
    "format_p_value <- function(value) ifelse(is.na(value), \"\", ifelse(as.numeric(value) < 0.0001, \"<0.0001\", format_number(value, 4L)))",
    "summary_statistics <- function(values) {",
    "  present <- as.numeric(values)",
    "  present <- present[!is.na(present)]",
    "  count <- length(present)",
    "  c(n = as.character(count),",
    "    mean = if (0L < count) format_number(mean(present), 3L) else \"\",",
    "    sd = if (1L < count) format_number(stats::sd(present), 3L) else \"\",",
    "    median = if (0L < count) format_number(stats::median(present), 3L) else \"\",",
    "    min = if (0L < count) format_number(min(present), 3L) else \"\",",
    "    max = if (0L < count) format_number(max(present), 3L) else \"\")",
    "}",
    scr_blank(),
    scr_comment("UTF-8 BOM CSV writer：先用 write.csv 生成 UTF-8 文本，再在文件开头写入 BOM 三字节。"),
    "write_utf8_bom_csv <- function(data, path) {",
    "  temporary_path <- tempfile(fileext = \".csv\")",
    "  on.exit(unlink(temporary_path), add = TRUE)",
    "  write.csv(data, file = temporary_path, row.names = FALSE, na = \"\", fileEncoding = \"UTF-8\")",
    "  content <- readBin(temporary_path, what = \"raw\", n = file.size(temporary_path))",
    "  connection <- file(path, open = \"wb\")",
    "  on.exit(close(connection), add = TRUE)",
    "  writeBin(c(as.raw(c(239L, 187L, 191L)), content), connection)",
    "  invisible(path)",
    "}",
    scr_blank(),
    "build_final_table <- function(prepared, raw) {",
    "  keys <- unique(prepared[c(\"analysis_group_id\", \"analysis_group_label\", \"treatment\", \"visit\", \"visit_label\")])",
    "  keys <- keys[order(keys$analysis_group_id, match(keys$visit, levels(prepared$visit_f)), keys$treatment), , drop = FALSE]",
    "  rows <- list()",
    "  for (i in seq_len(nrow(keys))) {",
    "    key <- keys[i, , drop = FALSE]",
    "    piece <- prepared[prepared$analysis_group_id == key$analysis_group_id & prepared$treatment == key$treatment & prepared$visit == key$visit, , drop = FALSE]",
    "    observed <- summary_statistics(piece$response)",
    "    baseline <- summary_statistics(piece$baseline)",
    "    matched <- raw[raw$estimand == PRIMARY_ESTIMAND & raw$analysis_group_id == key$analysis_group_id & raw$visit == key$visit, , drop = FALSE]",
    "    if (identical(PRIMARY_ESTIMAND, \"treatment_visit_lsmean\")) matched <- matched[matched$treatment == key$treatment, , drop = FALSE]",
    "    rows[[length(rows) + 1L]] <- data.frame(",
    "      analysis_id = ANALYSIS_ID, tfl_id = TFL_ID, analysis_group_id = key$analysis_group_id,",
    "      analysis_group_label = key$analysis_group_label, row_type = \"observed_with_mmrm\",",
    "      estimand = PRIMARY_ESTIMAND, treatment = key$treatment, contrast = \"\", visit = key$visit_label,",
    "      observed_n = observed[[\"n\"]], observed_mean = observed[[\"mean\"]], observed_sd = observed[[\"sd\"]],",
    "      observed_median = observed[[\"median\"]], observed_min = observed[[\"min\"]], observed_max = observed[[\"max\"]],",
    "      baseline_n = baseline[[\"n\"]], baseline_mean = baseline[[\"mean\"]], baseline_sd = baseline[[\"sd\"]],",
    "      mmrm_estimate = if (nrow(matched) == 1L) format_number(matched$estimate, 3L) else \"\",",
    "      standard_error = if (nrow(matched) == 1L) format_number(matched$standard_error, 3L) else \"\",",
    "      confidence_interval = if (nrow(matched) == 1L) format_confidence_interval(matched$lower_confidence_limit, matched$upper_confidence_limit) else \"\",",
    "      degrees_of_freedom = if (nrow(matched) == 1L) format_number(matched$degrees_of_freedom, 1L) else \"\",",
    "      statistic = if (nrow(matched) == 1L) format_number(matched$statistic, 3L) else \"\",",
    "      p_value = if (nrow(matched) == 1L) format_p_value(matched$p_value) else \"\",",
    "      covariance_used = if (nrow(matched) == 1L) matched$covariance_used else \"\", stringsAsFactors = FALSE)",
    "  }",
    contrast_block,
    "  final <- do.call(rbind, rows)",
    "  row.names(final) <- NULL",
    "  final",
    "}",
    scr_blank(),
    scr_marker_line("FINAL_CSV_WRITE", "EXECUTABLE"),
    scr_comment("只有在全部分组拟合成功且推断字段完整时才写 raw 与 final TFL；"),
    scr_comment("否则只在第 8 部分写诊断与运行记录，绝不创建冒充正式结果的 final 文件。"),
    "RAW_OUTPUT_PATH <- \"\"",
    "FINAL_OUTPUT_PATH <- \"\"",
    "if (isTRUE(MODEL_SUCCESS) && isTRUE(INFERENCE_COMPLETE)) {",
    "  RAW_OUTPUT_PATH <- file.path(RESOLVED_OUTPUT_DIR, RAW_OUTPUT_FILE)",
    "  write_utf8_bom_csv(RAW_RESULTS, RAW_OUTPUT_PATH)",
    "  FINAL_TABLE <- build_final_table(analysis_data, RAW_RESULTS)",
    "  FINAL_OUTPUT_PATH <- file.path(RESOLVED_OUTPUT_DIR, FINAL_OUTPUT_FILE)",
    "  write_utf8_bom_csv(FINAL_TABLE, FINAL_OUTPUT_PATH)",
    "  RUN_STATUS <- \"complete\"",
    "  cat(\"已写出 raw 与 final TFL：\", RAW_OUTPUT_PATH, \" / \", FINAL_OUTPUT_PATH, \"\\n\", sep = \"\")",
    "} else {",
    "  RUN_STATUS <- if (isTRUE(MODEL_SUCCESS)) \"partial\" else \"fit_failed\"",
    "  cat(\"模型或推断未满足批准的完整性条件，按设计不写出 raw 与 final TFL。\\n\")",
    "}"
  )
}

scr_section_8 <- function(ir) {
  c(
    render_r_section_header(8L, program_section_titles()[[8L]]),
    scr_comment("本部分写出诊断信息与运行记录。无论运行成功或被阻断，这两个文件都会写出，用于审计与排查。"),
    scr_comment("本程序只写本 analysis、本语言的运行记录，不写也不修改任何全局 manifest。"),
    scr_blank(),
    "RUN_FINISHED_UTC <- format(Sys.time(), tz = \"UTC\", format = \"%Y-%m-%dT%H:%M:%SZ\")",
    "COMPUTATIONAL_RISK <- if (identical(RUN_STATUS, \"complete\") && !any(FIT_ATTEMPTS$outcome != \"success\")) \"Green\" else if (identical(RUN_STATUS, \"complete\")) \"Yellow\" else \"Red\"",
    "RISK_REASON <- if (identical(COMPUTATIONAL_RISK, \"Green\")) \"主协方差结构一次成功，推断字段完整。\" else if (identical(COMPUTATIONAL_RISK, \"Yellow\")) \"使用了批准的 fallback 协方差结构或出现 warning，需人工复核。\" else \"模型或推断未完成，不得把本次结果当作正式 TFL 使用。\"",
    "DIAGNOSTIC_TABLE <- data.frame(",
    "  study_id = STUDY_ID, analysis_id = ANALYSIS_ID, tfl_id = TFL_ID, title = TFL_TITLE,",
    "  profile_version = PROFILE_VERSION, programming_language = \"R\",",
    "  plan_sha256 = PLAN_SHA256, approval_payload_sha256 = APPROVAL_PAYLOAD_SHA256, contract_sha256 = CONTRACT_SHA256,",
    "  dataset_binding_mode = DATASET_BINDING_MODE, dataset_file = DATASET_FILE, dataset_format = DATASET_FORMAT,",
    "  expected_input_sha256 = toupper(EXPECTED_INPUT_SHA256), actual_input_sha256 = ACTUAL_INPUT_SHA256,",
    "  covariance_path = COVARIANCE_PATH, selected_covariance = SELECTED_COVARIANCE,",
    "  convergence_status = if (isTRUE(MODEL_SUCCESS)) \"converged\" else \"not_converged\",",
    "  inference_complete = if (isTRUE(INFERENCE_COMPLETE)) \"yes\" else \"no\",",
    "  input_rows = PROCESSING_COUNTS$input_rows, population_filtered_rows = PROCESSING_COUNTS$population_filtered_rows,",
    "  analysis_rows = PROCESSING_COUNTS$analysis_rows, missing_required_rows = PROCESSING_COUNTS$missing_required_rows,",
    "  subject_count = PROCESSING_COUNTS$subject_count, visit_level_count = PROCESSING_COUNTS$visit_level_count,",
    "  treatment_level_count = PROCESSING_COUNTS$treatment_level_count,",
    "  derivation_count = nrow(DERIVATION_COUNTS),",
    "  run_status = RUN_STATUS, computational_risk = COMPUTATIONAL_RISK, risk_reason = RISK_REASON,",
    "  run_started_utc = RUN_STARTED_UTC, run_finished_utc = RUN_FINISHED_UTC, stringsAsFactors = FALSE)",
    "DIAGNOSTIC_OUTPUT_PATH <- file.path(RESOLVED_OUTPUT_DIR, DIAGNOSTIC_OUTPUT_FILE)",
    "write_utf8_bom_csv(DIAGNOSTIC_TABLE, DIAGNOSTIC_OUTPUT_PATH)",
    scr_blank(),
    "RUN_RECORD_TABLE <- data.frame(",
    "  study_id = STUDY_ID, analysis_id = ANALYSIS_ID, tfl_id = TFL_ID, programming_language = \"R\",",
    "  profile_version = PROFILE_VERSION, plan_sha256 = PLAN_SHA256, approval_payload_sha256 = APPROVAL_PAYLOAD_SHA256,",
    "  contract_sha256 = CONTRACT_SHA256, dataset_binding_mode = DATASET_BINDING_MODE,",
    "  actual_input_sha256 = ACTUAL_INPUT_SHA256, execution_status = if (identical(RUN_STATUS, \"complete\")) \"executed\" else \"failed\",",
    "  run_status = RUN_STATUS, computational_risk = COMPUTATIONAL_RISK,",
    "  raw_output_file = if (nzchar(RAW_OUTPUT_PATH)) RAW_OUTPUT_FILE else \"\",",
    "  final_output_file = if (nzchar(FINAL_OUTPUT_PATH)) FINAL_OUTPUT_FILE else \"\",",
    "  diagnostic_file = DIAGNOSTIC_OUTPUT_FILE, run_record_file = RUN_RECORD_OUTPUT_FILE,",
    "  run_started_utc = RUN_STARTED_UTC, run_finished_utc = RUN_FINISHED_UTC, stringsAsFactors = FALSE)",
    "write_utf8_bom_csv(RUN_RECORD_TABLE, file.path(RESOLVED_OUTPUT_DIR, RUN_RECORD_OUTPUT_FILE))",
    scr_blank(),
    "cat(\"协方差尝试路径：\", COVARIANCE_PATH, \"\\n\", sep = \"\")",
    "cat(\"运行状态=\", RUN_STATUS, \"；计算风险=\", COMPUTATIONAL_RISK, \"\\n\", sep = \"\")",
    "if (!identical(RUN_STATUS, \"complete\")) stop(\"本次运行未产生完整的正式 TFL，运行状态=\", RUN_STATUS, \"。请阅读诊断文件后处理。\")"
  )
}

render_self_contained_r_program <- function(contract, analysis, identities) {
  ir <- build_program_generation_ir(contract, analysis, identities)
  lines <- c(
    scr_section_1(ir), scr_blank(),
    scr_section_2(ir), scr_blank(),
    scr_section_3(ir), scr_blank(),
    scr_section_4(ir), scr_blank(),
    scr_section_5(ir), scr_blank(),
    scr_section_6(ir), scr_blank(),
    scr_section_7(ir), scr_blank(),
    scr_section_8(ir)
  )
  lines <- unlist(lines, use.names = FALSE)
  lines <- lines[!vapply(lines, is.null, logical(1))]
  program <- paste0(paste(as.character(lines), collapse = "\n"), "\n")
  if (!is.character(program) || length(program) != 1L || is.na(program)) stop("PROGRAM-R-RENDER-OUTPUT:", ir$identity$analysis_id)
  validate_generated_r_program(program, ir)
  program
}
