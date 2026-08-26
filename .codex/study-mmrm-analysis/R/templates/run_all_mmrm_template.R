# Generated Standard MMRM Profile v1 collector（Phase 6）。
# 本 collector 只做调度与登记：它按规范化 R 程序文件名升序处理已批准的一一对应程序集合，
# 逐 analysis 判定 binding mode（planned 只登记 code-only 状态且绝不调用 R；linked 才用
# Rscript 子进程运行对应 .R），只通过固定路径接口 --input-dir/--output-dir 传递路径，
# 不重写任何程序正文、不传递任何统计语义，然后导入 language-specific run record 并构建
# 全局 tfl-output-manifest.csv。
#
# 本 collector 不依赖共享 engine：它既不载入共享建模文件，也不调用任何共享建模函数。
# 本流水线从不执行 SAS：SAS 程序只是代码交付物。统计师在自己的 SAS 环境中运行后，
# 用 --mode=collect-only 让 collector 校验并导入其 run record。
options(encoding = "UTF-8")
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
if (length(script_arg) != 1L) stop("Run this file with Rscript.")
script_file <- normalizePath(sub("^--file=", "", script_arg), winslash = "/", mustWork = TRUE)
find_project_dir <- function(path) { current <- dirname(path); repeat { if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "standard_artifacts.R"))) return(normalizePath(current, winslash = "/", mustWork = TRUE)); parent <- dirname(current); if (identical(parent, current)) stop("Cannot locate project root."); current <- parent } }
collector_args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(name, default = NULL) { prefix <- paste0("--", name, "="); matches <- collector_args[startsWith(collector_args, prefix)]; if (!length(matches)) return(default); if (length(matches) != 1L) stop("Argument may appear once: --", name); substring(matches, nchar(prefix) + 1L) }
unknown <- collector_args[!startsWith(collector_args, "--mode=")]
if (length(unknown)) stop("拒绝未知命令行参数：", paste(unknown, collapse = " "), "。本 collector 只接受 --mode=run-and-collect 或 --mode=collect-only。")
project_dir <- find_project_dir(script_file); helper_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
for (helper in c("study_paths.R", "io.R", "specification.R", "canonical_hash.R", "standard_contract.R", "standard_analysis_definition.R", "analysis_plan.R", "analysis_contract_generation.R", "analysis_approval.R", "program_generation_ir.R", "program_conformance.R", "standard_artifacts.R")) source(file.path(helper_dir, helper), encoding = "UTF-8")
# 这两个 pinned 指纹是生成时钉住的批准身份。变量名必须与 helper 中的同名函数区分开，
# 否则会在 globalenv 里覆盖 approval_payload_sha256() 等函数定义。
pinned_approval_payload_sha256 <- "<APPROVAL_PAYLOAD_SHA256>"; pinned_contract_sha256 <- "<CONTRACT_SHA256>"
if (any(grepl("^<.+>$", c(pinned_approval_payload_sha256, pinned_contract_sha256)))) stop("Collector generation is incomplete.")
mode <- get_arg("mode", "run-and-collect")
run_self_contained_mmrm_collector(script_file, pinned_approval_payload_sha256, pinned_contract_sha256, mode = mode)
