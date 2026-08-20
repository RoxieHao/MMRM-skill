# Generated Standard MMRM Profile v1 wrapper. Do not edit.
options(encoding = "UTF-8")
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
if (length(script_arg) != 1L) stop("Run this file with Rscript.")
script_file <- normalizePath(sub("^--file=", "", script_arg), winslash = "/", mustWork = TRUE)
find_project_dir <- function(path) { current <- dirname(path); repeat { if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "standard_engine.R"))) return(normalizePath(current, winslash = "/", mustWork = TRUE)); parent <- dirname(current); if (identical(parent, current)) stop("Cannot locate project root."); current <- parent } }
project_dir <- find_project_dir(script_file); helper_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
for (helper in c("study_paths.R", "io.R", "specification.R", "canonical_hash.R", "standard_contract.R", "standard_analysis_definition.R", "analysis_plan.R", "analysis_contract_generation.R", "analysis_approval.R", "standard_engine.R")) source(file.path(helper_dir, helper), encoding = "UTF-8")
analysis_id <- "<ANALYSIS_ID>"
approval_payload_sha256 <- "<APPROVAL_PAYLOAD_SHA256>"
contract_sha256 <- "<CONTRACT_SHA256>"
if (any(grepl("^<.+>$", c(analysis_id, approval_payload_sha256, contract_sha256)))) stop("Wrapper generation is incomplete.")
run_standard_mmrm_analysis(script_file, analysis_id, approval_payload_sha256, contract_sha256)
