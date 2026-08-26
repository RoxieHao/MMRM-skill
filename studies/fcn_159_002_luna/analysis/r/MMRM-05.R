# ==============================================================================
# 第 1 部分：程序说明与用户配置
# ==============================================================================
# 本程序由已批准的 analysis plan 与机械编译的 runtime contract 确定性生成，逐 TFL 自包含。
# 阅读本文件即可理解该 TFL 的数据处理、MMRM 拟合、统计推断与输出，无需阅读任何项目共享代码。
# 研究：fcn_159_002_luna；分析：MMRM-05；TFL：T14-2-14-1-2
# 标题：关节活动范围评估观测值及相对基线变化-MMRM-汇总（COA分析集）
# profile 版本：standard-mmrm-profile/v1

# 批准身份（用于审计追溯；本程序独立运行时不读取 review/plan/contract 文件）：
# PROGRAM-MARKER:IDENTITY:STUDY:fcn_159_002_luna
# PROGRAM-MARKER:IDENTITY:ANALYSIS:MMRM-05
# PROGRAM-MARKER:IDENTITY:TFL:T14-2-14-1-2
# PROGRAM-MARKER:IDENTITY:PROFILE:standard-mmrm-profile/v1
# PROGRAM-MARKER:IDENTITY:PLAN_SHA256:390B7B6FD8B1F9389611F96A609A10A6D68156D35E447E9DEC61A4C209E22EB0
# PROGRAM-MARKER:IDENTITY:APPROVAL_SHA256:DF5328CC62FACE241492B58C1CAA6462E43F919709F0D924CFEE5B91BA6BB4AF
# PROGRAM-MARKER:IDENTITY:CONTRACT_SHA256:59C6ED60E9EFF09D9D0F7CE20F7B7688B29EA1842AD44BB6FBA1881BF8806EC6

# 数据绑定模式：linked（已登记实体 ADaM 文件与 SHA-256）
# PROGRAM-MARKER:BINDING:linked
# 批准的数据文件名：admk.sas7bdat；格式：sas7bdat

# 所需 R 包与最低功能要求：
#   mmrm：拟合 REML MMRM 并提供批准的自由度方法；
#   emmeans：计算 LS mean 与批准方向的显式权重 contrast；
#   digest：在读取数据之前计算输入文件 SHA-256 并与批准值比较；
#   haven：读取 SAS7BDAT 格式的 ADaM 数据集；
#   本程序不自动安装任何包；缺失时立即以中文错误停止，由统计师在本机安装。
# 所需包清单：digest, mmrm, emmeans, haven

# 本 TFL 的输出文件名逐字来自 contract，程序运行时不自行推断或拼接：
# PROGRAM-MARKER:OUTPUT:r_raw_file:T14-2-14-1-2_r_raw.csv
# PROGRAM-MARKER:OUTPUT:r_final_file:T14-2-14-1-2_r_final.csv
# PROGRAM-MARKER:OUTPUT:r_diagnostic_file:T14-2-14-1-2_r_diagnostic.csv
# PROGRAM-MARKER:OUTPUT:r_run_record_file:T14-2-14-1-2_r_run_record.csv
# PROGRAM-MARKER:OUTPUT:sas_raw_file:T14-2-14-1-2_sas_raw.csv
# PROGRAM-MARKER:OUTPUT:sas_final_file:T14-2-14-1-2_sas_final.csv
# PROGRAM-MARKER:OUTPUT:sas_diagnostic_file:T14-2-14-1-2_sas_diagnostic.csv
# PROGRAM-MARKER:OUTPUT:sas_run_record_file:T14-2-14-1-2_sas_run_record.csv

# =========================== 用户配置区（开始） ===========================
# 以下两个路径是本程序中唯一允许人工修改的内容。
# INPUT_DIR：存放批准数据文件的本机只读输入目录；
# OUTPUT_DIR：存放本 TFL 结果、诊断与运行记录的本机输出目录。
# 也可以在运行时用 --input-dir/--output-dir 命令行参数或 MMRM_INPUT_DIR/MMRM_OUTPUT_DIR 环境变量覆盖。
INPUT_DIR <- ""
OUTPUT_DIR <- ""
# =========================== 用户配置区（结束） ===========================

# 除上面的用户配置区之外，请不要修改本程序的任何内容。
# 任何统计语义变更（数据集、变量映射、派生、筛选、分组、模型、估计量、输出）
# 都必须回到 analysis plan 修改并重新批准，然后重新生成本程序。

# 以下常量由生成器写入，属于批准语义，不是用户配置项。
DATA_AVAILABLE <- TRUE
CODE_GENERATION_ONLY <- FALSE
STUDY_ID <- "fcn_159_002_luna"
ANALYSIS_ID <- "MMRM-05"
TFL_ID <- "T14-2-14-1-2"
TFL_TITLE <- "关节活动范围评估观测值及相对基线变化-MMRM-汇总（COA分析集）"
PROFILE_VERSION <- "standard-mmrm-profile/v1"
PLAN_SHA256 <- "390B7B6FD8B1F9389611F96A609A10A6D68156D35E447E9DEC61A4C209E22EB0"
APPROVAL_PAYLOAD_SHA256 <- "DF5328CC62FACE241492B58C1CAA6462E43F919709F0D924CFEE5B91BA6BB4AF"
CONTRACT_SHA256 <- "59C6ED60E9EFF09D9D0F7CE20F7B7688B29EA1842AD44BB6FBA1881BF8806EC6"
DATASET_BINDING_MODE <- "linked"
DATASET_FILE <- "admk.sas7bdat"
DATASET_FORMAT <- "sas7bdat"
EXPECTED_INPUT_SHA256 <- "FD7577DA53D2C129B3C6A3B2DD41387FD05F9A9824601023C9D16FB4C357708D"
RAW_OUTPUT_FILE <- "T14-2-14-1-2_r_raw.csv"
FINAL_OUTPUT_FILE <- "T14-2-14-1-2_r_final.csv"
DIAGNOSTIC_OUTPUT_FILE <- "T14-2-14-1-2_r_diagnostic.csv"
RUN_RECORD_OUTPUT_FILE <- "T14-2-14-1-2_r_run_record.csv"
RUN_STARTED_UTC <- format(Sys.time(), tz = "UTC", format = "%Y-%m-%dT%H:%M:%SZ")

# ==============================================================================
# 第 2 部分：运行环境与安全检查
# ==============================================================================
# 本部分按固定顺序执行运行环境与安全检查；任一检查失败都在建模之前以中文错误停止。

# 检查 1：code-generation-only gate。它是生成常量，位于全部数据与模型代码之前。
# planned 模式属于合法状态，不是运行错误：打印中文说明后以退出码 0 正常结束，
# 不读取数据、不拟合模型、不创建 raw/final/model/diagnostic/run-record 任何文件。
# 仅把 DATA_AVAILABLE 改成 TRUE 不能绕过本 gate；获得数据后必须重新批准并生成 linked 版本。
if (isTRUE(CODE_GENERATION_ONLY)) {
  cat("当前程序按无 ADaM 数据的 code-generation 模式生成。\n")
  cat("批准语义已完整内联，但本程序不允许读取数据、拟合模型或生成任何结果文件。\n")
  cat("请在 ADaM 数据到达并核对文件名、变量映射与批准版本后，重新编译 analysis plan、\n")
  cat("重新 finalization 与批准，并重新生成 linked 版本的正式程序。\n")
  cat("分析：", ANALYSIS_ID, "；TFL：", TFL_ID, "；数据绑定模式：", DATASET_BINDING_MODE, "\n", sep = "")
  quit(save = "no", status = 0L)
}
if (!isTRUE(DATA_AVAILABLE)) {
  cat("DATA_AVAILABLE 为 FALSE：本次运行不读取数据、不拟合模型，正常结束。\n")
  quit(save = "no", status = 0L)
}

# 检查 2：所需 R 包是否存在。本程序只检查，不安装。
# PROGRAM-MARKER:PACKAGE:digest
if (!requireNamespace("digest", quietly = TRUE)) stop("缺少必需的 R 包：digest。请在本机安装该包后重新运行本程序。")
# PROGRAM-MARKER:PACKAGE:mmrm
if (!requireNamespace("mmrm", quietly = TRUE)) stop("缺少必需的 R 包：mmrm。请在本机安装该包后重新运行本程序。")
# PROGRAM-MARKER:PACKAGE:emmeans
if (!requireNamespace("emmeans", quietly = TRUE)) stop("缺少必需的 R 包：emmeans。请在本机安装该包后重新运行本程序。")
# PROGRAM-MARKER:PACKAGE:haven
if (!requireNamespace("haven", quietly = TRUE)) stop("缺少必需的 R 包：haven。请在本机安装该包后重新运行本程序。")

# 检查 3：解析输入/输出目录。优先级固定为命令行参数 --input-dir/--output-dir，
# 其次环境变量 MMRM_INPUT_DIR/MMRM_OUTPUT_DIR，最后第 1 部分用户配置区的 INPUT_DIR/OUTPUT_DIR。
# 这些通道只能传递路径，不能传递任何统计语义；未知命令行参数必须拒绝。
program_arguments <- commandArgs(trailingOnly = TRUE)
command_line_input_dir <- ""
command_line_output_dir <- ""
argument_index <- 1L
while (argument_index <= length(program_arguments)) {
  token <- program_arguments[[argument_index]]
  assign_option <- function(option) {
    if (identical(token, option)) {
      if (length(program_arguments) < argument_index + 1L) stop("命令行参数缺少取值：", option)
      value <- program_arguments[[argument_index + 1L]]
      argument_index <<- argument_index + 2L
      return(value)
    }
    prefix <- paste0(option, "=")
    if (startsWith(token, prefix)) {
      argument_index <<- argument_index + 1L
      return(substring(token, nchar(prefix) + 1L))
    }
    NULL
  }
  input_value <- assign_option("--input-dir")
  if (!is.null(input_value)) {
    command_line_input_dir <- input_value
    next
  }
  output_value <- assign_option("--output-dir")
  if (!is.null(output_value)) {
    command_line_output_dir <- output_value
    next
  }
  stop("拒绝未知命令行参数：", token, "。本程序只接受 --input-dir 与 --output-dir。")
}
resolve_directory <- function(command_line_value, environment_name, file_value) {
  if (nzchar(command_line_value)) return(command_line_value)
  environment_value <- Sys.getenv(environment_name, "")
  if (nzchar(environment_value)) return(environment_value)
  file_value
}
RESOLVED_INPUT_DIR <- resolve_directory(command_line_input_dir, "MMRM_INPUT_DIR", INPUT_DIR)
RESOLVED_OUTPUT_DIR <- resolve_directory(command_line_output_dir, "MMRM_OUTPUT_DIR", OUTPUT_DIR)
if (!nzchar(trimws(RESOLVED_INPUT_DIR))) stop("未配置输入目录：请设置第 1 部分的 INPUT_DIR，或使用 --input-dir / MMRM_INPUT_DIR。")
if (!nzchar(trimws(RESOLVED_OUTPUT_DIR))) stop("未配置输出目录：请设置第 1 部分的 OUTPUT_DIR，或使用 --output-dir / MMRM_OUTPUT_DIR。")

# 检查 4：输入目录与批准数据文件是否存在。
# PROGRAM-MARKER:GATE:LINKED_FILE
if (!dir.exists(RESOLVED_INPUT_DIR)) stop("输入目录不存在：", RESOLVED_INPUT_DIR)
INPUT_FILE_PATH <- file.path(RESOLVED_INPUT_DIR, DATASET_FILE)
if (!file.exists(INPUT_FILE_PATH)) stop("批准的输入数据文件不存在：", INPUT_FILE_PATH)

# 检查 5：输出目录是否存在或可创建。程序绝不写入输入目录。
if (!dir.exists(RESOLVED_OUTPUT_DIR)) dir.create(RESOLVED_OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
if (!dir.exists(RESOLVED_OUTPUT_DIR)) stop("输出目录不存在且无法创建：", RESOLVED_OUTPUT_DIR)

# 检查 6：在读取任何数据之前，计算输入文件 SHA-256 并与批准值以大写比较。
# PROGRAM-MARKER:GATE:LINKED_SHA256
ACTUAL_INPUT_SHA256 <- toupper(digest::digest(file = INPUT_FILE_PATH, algo = "sha256"))
if (!identical(ACTUAL_INPUT_SHA256, toupper(EXPECTED_INPUT_SHA256))) {
  stop("输入数据文件 SHA-256 与批准值不一致，按设计在读取数据之前阻断：文件=", INPUT_FILE_PATH,
       "；expected=", toupper(EXPECTED_INPUT_SHA256), "；actual=", ACTUAL_INPUT_SHA256)
}
cat("输入文件 SHA-256 校验通过：", ACTUAL_INPUT_SHA256, "\n", sep = "")

# 本分析是确定性 MMRM，不需要随机性，因此不设置也不虚构随机种子。

# ==============================================================================
# 第 3 部分：读取 ADaM 数据
# ==============================================================================
# 本部分只按批准的 dataset.format 生成唯一一种读取分支，读取后立即检查全部批准引用的源变量。

# 再次确认 code-generation-only 常量，防止有人删除第 2 部分的 gate 后直接读取数据。
if (isTRUE(CODE_GENERATION_ONLY)) stop("本程序为 code-generation-only，不允许读取 ADaM 数据。")

# 批准格式为 sas7bdat：使用 haven::read_sas() 读取，随后转换为普通 data.frame 且不改列名。
raw_data <- haven::read_sas(INPUT_FILE_PATH)
raw_data <- as.data.frame(raw_data, stringsAsFactors = FALSE, check.names = FALSE)
if (!is.data.frame(raw_data) || nrow(raw_data) == 0L) stop("读取到的 ADaM 数据不是非空 data.frame：", INPUT_FILE_PATH)
INPUT_ROWS <- nrow(raw_data)
cat("已读取输入数据，行数=", INPUT_ROWS, "\n", sep = "")

# 批准的 mappings、derivations、filters、groups 与 endpoint definitions 引用的全部源变量；
# 缺列时一次列出全部缺失变量后停止，避免统计师逐个试错。
REQUIRED_SOURCE_VARIABLES <- c("USUBJID", "CHG", "BASE", "AVISITN", "COAFL", "ANL01FL", "PARAMCD")
missing_source_variables <- REQUIRED_SOURCE_VARIABLES[!REQUIRED_SOURCE_VARIABLES %in% names(raw_data)]
if (0L < length(missing_source_variables)) stop("ADaM 数据缺少以下批准引用的源变量：", paste(missing_source_variables, collapse = ", "))

# ==============================================================================
# 第 4 部分：数据处理与质量控制
# ==============================================================================
# 本部分严格按批准设计的 1-11 顺序执行数据处理与质量控制；任一硬性 QC 失败都在建模之前停止。
DERIVATION_COUNTS <- data.frame(derivation_id = character(), matched_rows = integer(), unmatched_rows = integer(), missing_rows = integer(), stringsAsFactors = FALSE)
GROUP_FRAMES <- list()
GROUP_ALLOCATION <- data.frame(source_row_id = integer(), group_id = character(), stringsAsFactors = FALSE)

# 步骤 5 使用的标准变量构造 helper，内联在本部分，不依赖任何外部代码。
build_group_frame <- function(group_data, group_id, group_label) {
  if (nrow(group_data) == 0L) return(NULL)
  data.frame(
    subject = as.character(group_data[["USUBJID"]]),
    response = suppressWarnings(as.numeric(group_data[["CHG"]])),
    baseline = suppressWarnings(as.numeric(group_data[["BASE"]])),
    visit = as.character(group_data[["AVISITN"]]),
    visit_label = as.character(group_data[["AVISITN"]]),
    treatment = rep("ALL", nrow(group_data)),
    analysis_group_id = group_id,
    analysis_group_label = group_label,
    stringsAsFactors = FALSE, check.names = FALSE
  )
}

# 步骤 1：执行批准的 derivations。派生只按批准的显式取值向量归并，不做任何推断。
# 批准的 analysis plan 没有 derivations，本步骤没有需要执行的派生。

# 步骤 2：应用批准的 population filters。
analysis_input <- raw_data

# PROGRAM-MARKER:FILTER:1
# PROGRAM-WHY:FILTER:1: 按批准的分析人群定义，仅保留变量 COAFL 满足 eq 条件的记录。
filter_keep <- (analysis_input[["COAFL"]] == "是")
filter_keep[is.na(filter_keep)] <- FALSE
analysis_input <- analysis_input[filter_keep, , drop = FALSE]

# PROGRAM-MARKER:FILTER:2
# PROGRAM-WHY:FILTER:2: 按批准的分析人群定义，仅保留变量 ANL01FL 满足 eq 条件的记录。
filter_keep <- (analysis_input[["ANL01FL"]] == "是")
filter_keep[is.na(filter_keep)] <- FALSE
analysis_input <- analysis_input[filter_keep, , drop = FALSE]
POPULATION_FILTERED_ROWS <- nrow(analysis_input)
if (nrow(analysis_input) == 0L) stop("应用批准的 population filters 之后没有剩余记录。")

# 步骤 3：为每条筛选后记录分配唯一行号，然后按批准定义分配 analysis groups 与 endpoint definitions。
analysis_input[[".self_contained_row_id"]] <- seq_len(nrow(analysis_input))

# PROGRAM-MARKER:GROUP:SUMALL
# PROGRAM-WHY:GROUP:SUMALL: 按批准的分组定义选出属于 SUMALL 的记录，分组之间必须互斥。
group_keep <- rep(TRUE, nrow(analysis_input))
group_keep <- group_keep & (analysis_input[["PARAMCD"]] == "SUMALL")
group_keep[is.na(group_keep)] <- FALSE
group_data <- analysis_input[group_keep, , drop = FALSE]
# PROGRAM-MARKER:ENDPOINT:SUMALL
# PROGRAM-WHY:ENDPOINT:SUMALL: 按批准的 endpoint definition 校验 endpoint 变量 PARAMCD 与各维度取值，行分配规则为 one_row_per_subject_endpoint_visit。
GROUP_FRAMES[["SUMALL"]] <- build_group_frame(group_data, "SUMALL", "SUMALL")
GROUP_ALLOCATION <- rbind(GROUP_ALLOCATION, data.frame(source_row_id = group_data[[".self_contained_row_id"]], group_id = "SUMALL", stringsAsFactors = FALSE))

# PROGRAM-MARKER:GROUP:SUMNECK
# PROGRAM-WHY:GROUP:SUMNECK: 按批准的分组定义选出属于 SUMNECK 的记录，分组之间必须互斥。
group_keep <- rep(TRUE, nrow(analysis_input))
group_keep <- group_keep & (analysis_input[["PARAMCD"]] == "SUMNECK")
group_keep[is.na(group_keep)] <- FALSE
group_data <- analysis_input[group_keep, , drop = FALSE]
# PROGRAM-MARKER:ENDPOINT:SUMNECK
# PROGRAM-WHY:ENDPOINT:SUMNECK: 按批准的 endpoint definition 校验 endpoint 变量 PARAMCD 与各维度取值，行分配规则为 one_row_per_subject_endpoint_visit。
GROUP_FRAMES[["SUMNECK"]] <- build_group_frame(group_data, "SUMNECK", "SUMNECK")
GROUP_ALLOCATION <- rbind(GROUP_ALLOCATION, data.frame(source_row_id = group_data[[".self_contained_row_id"]], group_id = "SUMNECK", stringsAsFactors = FALSE))

# PROGRAM-MARKER:GROUP:SUMHIP
# PROGRAM-WHY:GROUP:SUMHIP: 按批准的分组定义选出属于 SUMHIP 的记录，分组之间必须互斥。
group_keep <- rep(TRUE, nrow(analysis_input))
group_keep <- group_keep & (analysis_input[["PARAMCD"]] == "SUMHIP")
group_keep[is.na(group_keep)] <- FALSE
group_data <- analysis_input[group_keep, , drop = FALSE]
# PROGRAM-MARKER:ENDPOINT:SUMHIP
# PROGRAM-WHY:ENDPOINT:SUMHIP: 按批准的 endpoint definition 校验 endpoint 变量 PARAMCD 与各维度取值，行分配规则为 one_row_per_subject_endpoint_visit。
GROUP_FRAMES[["SUMHIP"]] <- build_group_frame(group_data, "SUMHIP", "SUMHIP")
GROUP_ALLOCATION <- rbind(GROUP_ALLOCATION, data.frame(source_row_id = group_data[[".self_contained_row_id"]], group_id = "SUMHIP", stringsAsFactors = FALSE))

# PROGRAM-MARKER:GROUP:SUMSHOU
# PROGRAM-WHY:GROUP:SUMSHOU: 按批准的分组定义选出属于 SUMSHOU 的记录，分组之间必须互斥。
group_keep <- rep(TRUE, nrow(analysis_input))
group_keep <- group_keep & (analysis_input[["PARAMCD"]] == "SUMSHOU")
group_keep[is.na(group_keep)] <- FALSE
group_data <- analysis_input[group_keep, , drop = FALSE]
# PROGRAM-MARKER:ENDPOINT:SUMSHOU
# PROGRAM-WHY:ENDPOINT:SUMSHOU: 按批准的 endpoint definition 校验 endpoint 变量 PARAMCD 与各维度取值，行分配规则为 one_row_per_subject_endpoint_visit。
GROUP_FRAMES[["SUMSHOU"]] <- build_group_frame(group_data, "SUMSHOU", "SUMSHOU")
GROUP_ALLOCATION <- rbind(GROUP_ALLOCATION, data.frame(source_row_id = group_data[[".self_contained_row_id"]], group_id = "SUMSHOU", stringsAsFactors = FALSE))

# PROGRAM-MARKER:GROUP:SUMELBOW
# PROGRAM-WHY:GROUP:SUMELBOW: 按批准的分组定义选出属于 SUMELBOW 的记录，分组之间必须互斥。
group_keep <- rep(TRUE, nrow(analysis_input))
group_keep <- group_keep & (analysis_input[["PARAMCD"]] == "SUMELBOW")
group_keep[is.na(group_keep)] <- FALSE
group_data <- analysis_input[group_keep, , drop = FALSE]
# PROGRAM-MARKER:ENDPOINT:SUMELBOW
# PROGRAM-WHY:ENDPOINT:SUMELBOW: 按批准的 endpoint definition 校验 endpoint 变量 PARAMCD 与各维度取值，行分配规则为 one_row_per_subject_endpoint_visit。
GROUP_FRAMES[["SUMELBOW"]] <- build_group_frame(group_data, "SUMELBOW", "SUMELBOW")
GROUP_ALLOCATION <- rbind(GROUP_ALLOCATION, data.frame(source_row_id = group_data[[".self_contained_row_id"]], group_id = "SUMELBOW", stringsAsFactors = FALSE))

# PROGRAM-MARKER:GROUP:SUMWRIST
# PROGRAM-WHY:GROUP:SUMWRIST: 按批准的分组定义选出属于 SUMWRIST 的记录，分组之间必须互斥。
group_keep <- rep(TRUE, nrow(analysis_input))
group_keep <- group_keep & (analysis_input[["PARAMCD"]] == "SUMWRIST")
group_keep[is.na(group_keep)] <- FALSE
group_data <- analysis_input[group_keep, , drop = FALSE]
# PROGRAM-MARKER:ENDPOINT:SUMWRIST
# PROGRAM-WHY:ENDPOINT:SUMWRIST: 按批准的 endpoint definition 校验 endpoint 变量 PARAMCD 与各维度取值，行分配规则为 one_row_per_subject_endpoint_visit。
GROUP_FRAMES[["SUMWRIST"]] <- build_group_frame(group_data, "SUMWRIST", "SUMWRIST")
GROUP_ALLOCATION <- rbind(GROUP_ALLOCATION, data.frame(source_row_id = group_data[[".self_contained_row_id"]], group_id = "SUMWRIST", stringsAsFactors = FALSE))

# PROGRAM-MARKER:GROUP:SUMKNEE
# PROGRAM-WHY:GROUP:SUMKNEE: 按批准的分组定义选出属于 SUMKNEE 的记录，分组之间必须互斥。
group_keep <- rep(TRUE, nrow(analysis_input))
group_keep <- group_keep & (analysis_input[["PARAMCD"]] == "SUMKNEE")
group_keep[is.na(group_keep)] <- FALSE
group_data <- analysis_input[group_keep, , drop = FALSE]
# PROGRAM-MARKER:ENDPOINT:SUMKNEE
# PROGRAM-WHY:ENDPOINT:SUMKNEE: 按批准的 endpoint definition 校验 endpoint 变量 PARAMCD 与各维度取值，行分配规则为 one_row_per_subject_endpoint_visit。
GROUP_FRAMES[["SUMKNEE"]] <- build_group_frame(group_data, "SUMKNEE", "SUMKNEE")
GROUP_ALLOCATION <- rbind(GROUP_ALLOCATION, data.frame(source_row_id = group_data[[".self_contained_row_id"]], group_id = "SUMKNEE", stringsAsFactors = FALSE))

# PROGRAM-MARKER:GROUP:SUMANKLE
# PROGRAM-WHY:GROUP:SUMANKLE: 按批准的分组定义选出属于 SUMANKLE 的记录，分组之间必须互斥。
group_keep <- rep(TRUE, nrow(analysis_input))
group_keep <- group_keep & (analysis_input[["PARAMCD"]] == "SUMANKLE")
group_keep[is.na(group_keep)] <- FALSE
group_data <- analysis_input[group_keep, , drop = FALSE]
# PROGRAM-MARKER:ENDPOINT:SUMANKLE
# PROGRAM-WHY:ENDPOINT:SUMANKLE: 按批准的 endpoint definition 校验 endpoint 变量 PARAMCD 与各维度取值，行分配规则为 one_row_per_subject_endpoint_visit。
GROUP_FRAMES[["SUMANKLE"]] <- build_group_frame(group_data, "SUMANKLE", "SUMANKLE")
GROUP_ALLOCATION <- rbind(GROUP_ALLOCATION, data.frame(source_row_id = group_data[[".self_contained_row_id"]], group_id = "SUMANKLE", stringsAsFactors = FALSE))

# 步骤 4：检查一条源记录不能同时进入多个互斥分组。
overlapping_rows <- unique(GROUP_ALLOCATION$source_row_id[duplicated(GROUP_ALLOCATION$source_row_id)])
if (0L < length(overlapping_rows)) {
  overlapping_detail <- vapply(overlapping_rows, function(row_id) paste0(row_id, "=[", paste(GROUP_ALLOCATION$group_id[GROUP_ALLOCATION$source_row_id == row_id], collapse = ", "), "]"), character(1))
  stop("互斥分组重叠：以下筛选后源记录同时进入多个分组：", paste(overlapping_detail, collapse = "; "))
}

# 步骤 5：创建标准变量 subject、response、baseline、visit、visit label 与 treatment。
# 下列 marker 逐字记录批准的变量映射，便于审阅时与 analysis plan 对照。
# PROGRAM-MARKER:MAPPING:subject:USUBJID
# PROGRAM-WHY:MAPPING:subject: 批准的受试者标识映射，用于受试者内相关结构与唯一性检查。
# PROGRAM-MARKER:MAPPING:response:CHG
# PROGRAM-WHY:MAPPING:response: 批准的响应变量映射，是 MMRM 的因变量。
# PROGRAM-MARKER:MAPPING:baseline:BASE
# PROGRAM-WHY:MAPPING:baseline: 批准的基线协变量映射，用于基线校正。
# PROGRAM-MARKER:MAPPING:visit:AVISITN
# PROGRAM-WHY:MAPPING:visit: 批准的访视变量映射，作为分类时间因子。
GROUP_FRAMES <- GROUP_FRAMES[!vapply(GROUP_FRAMES, is.null, logical(1))]
if (length(GROUP_FRAMES) == 0L) stop("批准的 filters 与 groups 未产生任何分析记录。")
analysis_data <- do.call(rbind, GROUP_FRAMES)
row.names(analysis_data) <- NULL

# 步骤 6：删除批准规则定义的必需变量缺失行，并记录删除数量。
REQUIRED_COMPLETE_COLUMNS <- c("subject", "response", "baseline", "visit")
complete_rows <- stats::complete.cases(analysis_data[REQUIRED_COMPLETE_COLUMNS]) & nzchar(trimws(analysis_data$subject))
# 单臂研究的 treatment 为常量 ALL，不参与缺失判断。
MISSING_REQUIRED_ROWS <- sum(!complete_rows)
analysis_data <- analysis_data[complete_rows, , drop = FALSE]
if (nrow(analysis_data) == 0L) stop("删除必需变量缺失行之后没有剩余分析记录。")
cat("删除必需变量缺失行数=", MISSING_REQUIRED_ROWS, "\n", sep = "")

# 步骤 7：检查 subject/分组/visit 组合唯一。
duplicate_keys <- duplicated(analysis_data[c("subject", "analysis_group_id", "visit")]) | duplicated(analysis_data[c("subject", "analysis_group_id", "visit")], fromLast = TRUE)
if (any(duplicate_keys)) stop("subject/分组/visit 组合必须唯一，发现重复记录 ", sum(duplicate_keys), " 行。")

# 步骤 8：检查同一 subject 与分组内 baseline 一致。
baseline_consistency <- stats::aggregate(baseline ~ subject + analysis_group_id, analysis_data, function(values) length(unique(values)))
if (any(1L < baseline_consistency$baseline)) stop("同一 subject 与分组内的 baseline 必须一致，发现不一致的 subject 数=", sum(1L < baseline_consistency$baseline))

# 步骤 9：批准的 analysis plan 没有 treatment 映射（单臂研究），因此没有 treatment level 校验。
APPROVED_TREATMENT_LEVELS <- "ALL"
TREATMENT_REFERENCE_LEVEL <- ""
TREATMENT_COMPARATOR_LEVEL <- ""

# 步骤 10：固定 visit 与 treatment 的 factor levels，保证模型与 TFL 顺序确定。
visit_levels <- unique(analysis_data[c("visit", "visit_label")])
numeric_visit <- suppressWarnings(as.numeric(visit_levels$visit))
visit_order <- if (all(!is.na(numeric_visit))) order(numeric_visit) else order(visit_levels$visit)
visit_levels <- visit_levels[visit_order, , drop = FALSE]
if (anyDuplicated(visit_levels$visit)) stop("一个 visit 取值对应多个 visit label，无法确定 TFL 行顺序。")
analysis_data$subject_f <- factor(analysis_data$subject)
analysis_data$visit_f <- factor(analysis_data$visit, levels = visit_levels$visit)
analysis_data$treatment_f <- factor(analysis_data$treatment, levels = APPROVED_TREATMENT_LEVELS)
if (any(is.na(analysis_data$visit_f)) || any(is.na(analysis_data$treatment_f))) stop("固定 factor levels 之后出现未覆盖取值，请核对批准的 levels。")

# 步骤 11：汇总数据处理计数，留在内存中供第 8 部分诊断使用。
PROCESSING_COUNTS <- list(
  input_rows = INPUT_ROWS,
  population_filtered_rows = POPULATION_FILTERED_ROWS,
  analysis_rows = nrow(analysis_data),
  missing_required_rows = MISSING_REQUIRED_ROWS,
  subject_count = length(unique(analysis_data$subject)),
  visit_level_count = nlevels(analysis_data$visit_f),
  treatment_level_count = nlevels(analysis_data$treatment_f)
)
cat("数据处理计数：输入=", PROCESSING_COUNTS$input_rows, "，筛选后=", PROCESSING_COUNTS$population_filtered_rows,
    "，分析=", PROCESSING_COUNTS$analysis_rows, "，缺失删除=", PROCESSING_COUNTS$missing_required_rows, "\n", sep = "")

# 至此完成数据处理。以下代码开始进行 MMRM 模型拟合；请勿混淆两部分职责。

# ==============================================================================
# 第 5 部分：MMRM 模型拟合
# ==============================================================================
# 本部分显式构造并打印固定效应 formula、REML 设定、自由度方法与协方差主/fallback 顺序，
# 对每个 analysis group 独立拟合，并逐次记录每个协方差结构的尝试结果。

# 批准的固定效应（顺序逐字来自 analysis plan）：
# PROGRAM-MARKER:FIXED_EFFECT:visit
# PROGRAM-WHY:FIXED_EFFECT:visit: 批准的固定效应：以分类 visit 估计各访视的均值结构。
# PROGRAM-MARKER:FIXED_EFFECT:baseline
# PROGRAM-WHY:FIXED_EFFECT:baseline: 批准的固定效应：以 baseline 作为连续协变量校正基线水平。
# PROGRAM-MARKER:FIXED_EFFECT:baseline_by_visit
# PROGRAM-WHY:FIXED_EFFECT:baseline_by_visit: 批准的固定效应：允许 baseline 的作用随访视变化。

# 批准的估计方法为 REML；本 profile 不允许改为 ML。
# PROGRAM-MARKER:REML:TRUE
# PROGRAM-WHY:REML:TRUE: 批准的方差成分估计方法为 REML，可减少小样本方差低估。

# 批准的协方差结构顺序（第一个为 primary，其后按顺序 fallback）：
# PROGRAM-MARKER:COVARIANCE:UN
# PROGRAM-WHY:COVARIANCE:UN: 批准的主协方差结构 非结构 (UN)，优先用于受试者内重复测量。
# PROGRAM-MARKER:COVARIANCE:AR1
# PROGRAM-WHY:COVARIANCE:AR1: 批准的第 1 顺位 fallback 协方差结构 一阶自回归 (AR1)，仅在前序结构未收敛时按批准顺序尝试。

# 批准的自由度方法：
# PROGRAM-MARKER:DF_METHOD:Kenward-Roger
# PROGRAM-WHY:DF_METHOD:Kenward-Roger: 批准的小样本自由度方法为 Kenward-Roger，用于 LS mean 与对比的推断。

MODEL_FIXED_TERMS <- c("visit_f", "baseline", "baseline:visit_f")
COVARIANCE_ORDER <- c("UN", "AR1")
COVARIANCE_TERMS <- c("UN" = "us(visit_f | subject_f)", "AR1" = "ar1(visit_f | subject_f)")
DF_METHOD <- "Kenward-Roger"
MODEL_REML <- TRUE
model_formula_text <- function(covariance) paste("response ~", paste(c(MODEL_FIXED_TERMS, COVARIANCE_TERMS[[covariance]]), collapse = " + "))
mmrm_control_for <- function(covariance) {
  control_arguments <- list(method = DF_METHOD)
  if (identical(DF_METHOD, "Kenward-Roger") && identical(covariance, "UN")) control_arguments$vcov <- "Kenward-Roger-Linear"
  do.call(mmrm::mmrm_control, control_arguments)
}
for (covariance in COVARIANCE_ORDER) cat("批准协方差 ", covariance, " 对应 formula：", model_formula_text(covariance), "\n", sep = "")
cat("REML=", MODEL_REML, "；自由度方法=", DF_METHOD, "\n", sep = "")

FIT_ATTEMPTS <- data.frame(analysis_group_id = character(), covariance = character(), outcome = character(), detail = character(), stringsAsFactors = FALSE)
GROUP_FITS <- list()
for (group_id in names(GROUP_FRAMES)) {
  group_analysis_data <- analysis_data[analysis_data$analysis_group_id == group_id, , drop = FALSE]
  selected_fit <- NULL
  selected_covariance <- ""
  group_warnings <- character()
  if (length(unique(group_analysis_data$subject)) < 2L || nlevels(droplevels(group_analysis_data$visit_f)) < 2L) {
    stop("分组 ", group_id, " 的 subject 或 visit 水平不足，无法拟合 MMRM。")
  }
  for (covariance in COVARIANCE_ORDER) {
    attempt_warnings <- character()
    fit <- tryCatch(
      withCallingHandlers(
        mmrm::mmrm(stats::as.formula(model_formula_text(covariance)), data = group_analysis_data, reml = MODEL_REML, control = mmrm_control_for(covariance)),
        warning = function(condition) { attempt_warnings <<- c(attempt_warnings, conditionMessage(condition)); invokeRestart("muffleWarning") },
        message = function(condition) { attempt_warnings <<- c(attempt_warnings, conditionMessage(condition)); invokeRestart("muffleMessage") }
      ),
      error = function(condition) condition
    )
    nonconverged <- any(grepl("non.?converg|fail.*converg|optimizer.*fail|diverg", attempt_warnings, ignore.case = TRUE, perl = TRUE))
    outcome <- if (inherits(fit, "error")) "failed" else if (nonconverged) "not_converged" else "success"
    detail <- if (inherits(fit, "error")) conditionMessage(fit) else paste(attempt_warnings, collapse = " | ")
    FIT_ATTEMPTS <- rbind(FIT_ATTEMPTS, data.frame(analysis_group_id = group_id, covariance = covariance, outcome = outcome, detail = detail, stringsAsFactors = FALSE))
    group_warnings <- c(group_warnings, attempt_warnings)
    cat("分组 ", group_id, " 尝试协方差 ", covariance, "：", outcome, "\n", sep = "")
    if (identical(outcome, "success")) {
      selected_fit <- fit
      selected_covariance <- covariance
      break
    }
  }
  if (is.null(selected_fit)) cat("分组 ", group_id, " 的全部批准协方差结构均未成功，按设计不生成完整状态的 TFL。\n", sep = "")
  GROUP_FITS[[group_id]] <- list(fit = selected_fit, covariance = selected_covariance, warnings = unique(group_warnings), data = group_analysis_data)
}
MODEL_SUCCESS <- 0L < length(GROUP_FITS) && all(vapply(GROUP_FITS, function(entry) !is.null(entry$fit), logical(1)))
COVARIANCE_PATH <- if (nrow(FIT_ATTEMPTS) == 0L) "" else paste(paste0(FIT_ATTEMPTS$analysis_group_id, "/", FIT_ATTEMPTS$covariance, "=", FIT_ATTEMPTS$outcome), collapse = " | ")
SELECTED_COVARIANCE <- paste(unique(vapply(GROUP_FITS, function(entry) entry$covariance, character(1))), collapse = " | ")

# ==============================================================================
# 第 6 部分：统计推断
# ==============================================================================
# 本部分只渲染批准 plan 中显式为 true 的估计量；未批准的估计量不会出现在代码中。

# PROGRAM-MARKER:ESTIMAND:visit_lsmeans
# PROGRAM-WHY:ESTIMAND:visit_lsmeans: 批准的估计量：逐访视 LS mean。

CONFIDENCE_LEVEL <- 0.95
MULTIPLICITY_ADJUSTMENT <- "none"
CONTRAST_LABEL <- ""
# 显式权重按批准的 factor 顺序（参照组在前、比较组在后）与批准方向 comparator 减 reference 构造。
CONTRAST_WEIGHTS <- numeric(0)

# 推断结果整形 helper，内联在本部分。
inference_rows <- function(summary_data, group_id, group_label, estimand, covariance, treatment_column, contrast_column) {
  frame <- as.data.frame(summary_data, stringsAsFactors = FALSE)
  numeric_column <- function(name) if (name %in% names(frame)) as.numeric(frame[[name]]) else rep(NA_real_, nrow(frame))
  estimate <- if ("emmean" %in% names(frame)) as.numeric(frame$emmean) else numeric_column("estimate")
  if (!"visit_f" %in% names(frame)) stop("推断结果缺少 visit_f 列，无法与批准的 TFL 行结构对齐。")
  data.frame(
    analysis_id = ANALYSIS_ID, tfl_id = TFL_ID, analysis_group_id = group_id, analysis_group_label = group_label,
    estimand = estimand,
    treatment = if (nzchar(treatment_column) && treatment_column %in% names(frame)) as.character(frame[[treatment_column]]) else "",
    contrast = if (nzchar(contrast_column) && contrast_column %in% names(frame)) as.character(frame[[contrast_column]]) else "",
    visit = as.character(frame$visit_f),
    estimate = estimate, standard_error = numeric_column("SE"), degrees_of_freedom = numeric_column("df"),
    lower_confidence_limit = numeric_column("lower.CL"), upper_confidence_limit = numeric_column("upper.CL"),
    statistic = numeric_column("t.ratio"), p_value = numeric_column("p.value"),
    covariance_used = covariance, stringsAsFactors = FALSE
  )
}

RAW_ROWS <- list()
INFERENCE_COMPLETE <- TRUE
for (group_id in names(GROUP_FITS)) {
  entry <- GROUP_FITS[[group_id]]
  if (is.null(entry$fit)) {
    INFERENCE_COMPLETE <- FALSE
    next
  }
  group_label <- unique(entry$data$analysis_group_label)[[1L]]
  visit_grid <- emmeans::emmeans(entry$fit, ~ visit_f)
  RAW_ROWS[[length(RAW_ROWS) + 1L]] <- inference_rows(
    summary(visit_grid, infer = c(TRUE, TRUE), level = CONFIDENCE_LEVEL, adjust = MULTIPLICITY_ADJUSTMENT),
    group_id, group_label, "visit_lsmean", entry$covariance, "", "")
}
RAW_RESULTS <- if (length(RAW_ROWS) == 0L) NULL else do.call(rbind, RAW_ROWS)

# 输出前检查 estimate、SE、df、置信区间与 p-value 是否完整；任一缺失都不允许写出正式 TFL。
INFERENCE_COLUMNS <- c("estimate", "standard_error", "degrees_of_freedom", "lower_confidence_limit", "upper_confidence_limit", "p_value")
if (is.null(RAW_RESULTS) || nrow(RAW_RESULTS) == 0L) INFERENCE_COMPLETE <- FALSE
if (!is.null(RAW_RESULTS) && 0L < nrow(RAW_RESULTS) && !all(stats::complete.cases(RAW_RESULTS[INFERENCE_COLUMNS]))) INFERENCE_COMPLETE <- FALSE
cat("推断字段完整性=", INFERENCE_COMPLETE, "\n", sep = "")

# ==============================================================================
# 第 7 部分：TFL 结果整理与导出
# ==============================================================================
# 本部分把 observed summary 与 MMRM 推断结果整理成该 TFL 专属的最终 table，
# 使用固定小数位与 p-value 格式，输出文件名逐字来自 contract，编码为 UTF-8 BOM CSV。

PRIMARY_ESTIMAND <- "visit_lsmean"
format_number <- function(value, digits) ifelse(is.na(value), "", formatC(as.numeric(value), format = "f", digits = digits))
format_confidence_interval <- function(lower, upper) ifelse(is.na(lower) | is.na(upper), "", paste0("(", format_number(lower, 3L), ", ", format_number(upper, 3L), ")"))
format_p_value <- function(value) ifelse(is.na(value), "", ifelse(as.numeric(value) < 0.0001, "<0.0001", format_number(value, 4L)))
summary_statistics <- function(values) {
  present <- as.numeric(values)
  present <- present[!is.na(present)]
  count <- length(present)
  c(n = as.character(count),
    mean = if (0L < count) format_number(mean(present), 3L) else "",
    sd = if (1L < count) format_number(stats::sd(present), 3L) else "",
    median = if (0L < count) format_number(stats::median(present), 3L) else "",
    min = if (0L < count) format_number(min(present), 3L) else "",
    max = if (0L < count) format_number(max(present), 3L) else "")
}

# UTF-8 BOM CSV writer：先用 write.csv 生成 UTF-8 文本，再在文件开头写入 BOM 三字节。
write_utf8_bom_csv <- function(data, path) {
  temporary_path <- tempfile(fileext = ".csv")
  on.exit(unlink(temporary_path), add = TRUE)
  write.csv(data, file = temporary_path, row.names = FALSE, na = "", fileEncoding = "UTF-8")
  content <- readBin(temporary_path, what = "raw", n = file.size(temporary_path))
  connection <- file(path, open = "wb")
  on.exit(close(connection), add = TRUE)
  writeBin(c(as.raw(c(239L, 187L, 191L)), content), connection)
  invisible(path)
}

build_final_table <- function(prepared, raw) {
  keys <- unique(prepared[c("analysis_group_id", "analysis_group_label", "treatment", "visit", "visit_label")])
  keys <- keys[order(keys$analysis_group_id, match(keys$visit, levels(prepared$visit_f)), keys$treatment), , drop = FALSE]
  rows <- list()
  for (i in seq_len(nrow(keys))) {
    key <- keys[i, , drop = FALSE]
    piece <- prepared[prepared$analysis_group_id == key$analysis_group_id & prepared$treatment == key$treatment & prepared$visit == key$visit, , drop = FALSE]
    observed <- summary_statistics(piece$response)
    baseline <- summary_statistics(piece$baseline)
    matched <- raw[raw$estimand == PRIMARY_ESTIMAND & raw$analysis_group_id == key$analysis_group_id & raw$visit == key$visit, , drop = FALSE]
    if (identical(PRIMARY_ESTIMAND, "treatment_visit_lsmean")) matched <- matched[matched$treatment == key$treatment, , drop = FALSE]
    rows[[length(rows) + 1L]] <- data.frame(
      analysis_id = ANALYSIS_ID, tfl_id = TFL_ID, analysis_group_id = key$analysis_group_id,
      analysis_group_label = key$analysis_group_label, row_type = "observed_with_mmrm",
      estimand = PRIMARY_ESTIMAND, treatment = key$treatment, contrast = "", visit = key$visit_label,
      observed_n = observed[["n"]], observed_mean = observed[["mean"]], observed_sd = observed[["sd"]],
      observed_median = observed[["median"]], observed_min = observed[["min"]], observed_max = observed[["max"]],
      baseline_n = baseline[["n"]], baseline_mean = baseline[["mean"]], baseline_sd = baseline[["sd"]],
      mmrm_estimate = if (nrow(matched) == 1L) format_number(matched$estimate, 3L) else "",
      standard_error = if (nrow(matched) == 1L) format_number(matched$standard_error, 3L) else "",
      confidence_interval = if (nrow(matched) == 1L) format_confidence_interval(matched$lower_confidence_limit, matched$upper_confidence_limit) else "",
      degrees_of_freedom = if (nrow(matched) == 1L) format_number(matched$degrees_of_freedom, 1L) else "",
      statistic = if (nrow(matched) == 1L) format_number(matched$statistic, 3L) else "",
      p_value = if (nrow(matched) == 1L) format_p_value(matched$p_value) else "",
      covariance_used = if (nrow(matched) == 1L) matched$covariance_used else "", stringsAsFactors = FALSE)
  }
  # 批准的 plan 未启用 pairwise differences，最终 table 不包含对比行。
  final <- do.call(rbind, rows)
  row.names(final) <- NULL
  final
}

# PROGRAM-MARKER:FINAL_CSV_WRITE:EXECUTABLE
# 只有在全部分组拟合成功且推断字段完整时才写 raw 与 final TFL；
# 否则只在第 8 部分写诊断与运行记录，绝不创建冒充正式结果的 final 文件。
RAW_OUTPUT_PATH <- ""
FINAL_OUTPUT_PATH <- ""
if (isTRUE(MODEL_SUCCESS) && isTRUE(INFERENCE_COMPLETE)) {
  RAW_OUTPUT_PATH <- file.path(RESOLVED_OUTPUT_DIR, RAW_OUTPUT_FILE)
  write_utf8_bom_csv(RAW_RESULTS, RAW_OUTPUT_PATH)
  FINAL_TABLE <- build_final_table(analysis_data, RAW_RESULTS)
  FINAL_OUTPUT_PATH <- file.path(RESOLVED_OUTPUT_DIR, FINAL_OUTPUT_FILE)
  write_utf8_bom_csv(FINAL_TABLE, FINAL_OUTPUT_PATH)
  RUN_STATUS <- "complete"
  cat("已写出 raw 与 final TFL：", RAW_OUTPUT_PATH, " / ", FINAL_OUTPUT_PATH, "\n", sep = "")
} else {
  RUN_STATUS <- if (isTRUE(MODEL_SUCCESS)) "partial" else "fit_failed"
  cat("模型或推断未满足批准的完整性条件，按设计不写出 raw 与 final TFL。\n")
}

# ==============================================================================
# 第 8 部分：诊断信息与运行记录
# ==============================================================================
# 本部分写出诊断信息与运行记录。无论运行成功或被阻断，这两个文件都会写出，用于审计与排查。
# 本程序只写本 analysis、本语言的运行记录，不写也不修改任何全局 manifest。

RUN_FINISHED_UTC <- format(Sys.time(), tz = "UTC", format = "%Y-%m-%dT%H:%M:%SZ")
COMPUTATIONAL_RISK <- if (identical(RUN_STATUS, "complete") && !any(FIT_ATTEMPTS$outcome != "success")) "Green" else if (identical(RUN_STATUS, "complete")) "Yellow" else "Red"
RISK_REASON <- if (identical(COMPUTATIONAL_RISK, "Green")) "主协方差结构一次成功，推断字段完整。" else if (identical(COMPUTATIONAL_RISK, "Yellow")) "使用了批准的 fallback 协方差结构或出现 warning，需人工复核。" else "模型或推断未完成，不得把本次结果当作正式 TFL 使用。"
DIAGNOSTIC_TABLE <- data.frame(
  study_id = STUDY_ID, analysis_id = ANALYSIS_ID, tfl_id = TFL_ID, title = TFL_TITLE,
  profile_version = PROFILE_VERSION, programming_language = "R",
  plan_sha256 = PLAN_SHA256, approval_payload_sha256 = APPROVAL_PAYLOAD_SHA256, contract_sha256 = CONTRACT_SHA256,
  dataset_binding_mode = DATASET_BINDING_MODE, dataset_file = DATASET_FILE, dataset_format = DATASET_FORMAT,
  expected_input_sha256 = toupper(EXPECTED_INPUT_SHA256), actual_input_sha256 = ACTUAL_INPUT_SHA256,
  covariance_path = COVARIANCE_PATH, selected_covariance = SELECTED_COVARIANCE,
  convergence_status = if (isTRUE(MODEL_SUCCESS)) "converged" else "not_converged",
  inference_complete = if (isTRUE(INFERENCE_COMPLETE)) "yes" else "no",
  input_rows = PROCESSING_COUNTS$input_rows, population_filtered_rows = PROCESSING_COUNTS$population_filtered_rows,
  analysis_rows = PROCESSING_COUNTS$analysis_rows, missing_required_rows = PROCESSING_COUNTS$missing_required_rows,
  subject_count = PROCESSING_COUNTS$subject_count, visit_level_count = PROCESSING_COUNTS$visit_level_count,
  treatment_level_count = PROCESSING_COUNTS$treatment_level_count,
  derivation_count = nrow(DERIVATION_COUNTS),
  run_status = RUN_STATUS, computational_risk = COMPUTATIONAL_RISK, risk_reason = RISK_REASON,
  run_started_utc = RUN_STARTED_UTC, run_finished_utc = RUN_FINISHED_UTC, stringsAsFactors = FALSE)
DIAGNOSTIC_OUTPUT_PATH <- file.path(RESOLVED_OUTPUT_DIR, DIAGNOSTIC_OUTPUT_FILE)
write_utf8_bom_csv(DIAGNOSTIC_TABLE, DIAGNOSTIC_OUTPUT_PATH)

RUN_RECORD_TABLE <- data.frame(
  study_id = STUDY_ID, analysis_id = ANALYSIS_ID, tfl_id = TFL_ID, programming_language = "R",
  profile_version = PROFILE_VERSION, plan_sha256 = PLAN_SHA256, approval_payload_sha256 = APPROVAL_PAYLOAD_SHA256,
  contract_sha256 = CONTRACT_SHA256, dataset_binding_mode = DATASET_BINDING_MODE,
  actual_input_sha256 = ACTUAL_INPUT_SHA256, execution_status = if (identical(RUN_STATUS, "complete")) "executed" else "failed",
  run_status = RUN_STATUS, computational_risk = COMPUTATIONAL_RISK,
  raw_output_file = if (nzchar(RAW_OUTPUT_PATH)) RAW_OUTPUT_FILE else "",
  final_output_file = if (nzchar(FINAL_OUTPUT_PATH)) FINAL_OUTPUT_FILE else "",
  diagnostic_file = DIAGNOSTIC_OUTPUT_FILE, run_record_file = RUN_RECORD_OUTPUT_FILE,
  run_started_utc = RUN_STARTED_UTC, run_finished_utc = RUN_FINISHED_UTC, stringsAsFactors = FALSE)
write_utf8_bom_csv(RUN_RECORD_TABLE, file.path(RESOLVED_OUTPUT_DIR, RUN_RECORD_OUTPUT_FILE))

cat("协方差尝试路径：", COVARIANCE_PATH, "\n", sep = "")
cat("运行状态=", RUN_STATUS, "；计算风险=", COMPUTATIONAL_RISK, "\n", sep = "")
if (!identical(RUN_STATUS, "complete")) stop("本次运行未产生完整的正式 TFL，运行状态=", RUN_STATUS, "。请阅读诊断文件后处理。")
