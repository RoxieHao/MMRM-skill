# Generated Standard MMRM Profile v1 collector. It validates and collects; it never fits models directly.
options(encoding = "UTF-8")
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
if (length(script_arg) != 1L) stop("Run this file with Rscript.")
script_file <- normalizePath(sub("^--file=", "", script_arg), winslash = "/", mustWork = TRUE)
find_project_dir <- function(path) { current <- dirname(path); repeat { if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "standard_artifacts.R"))) return(normalizePath(current, winslash = "/", mustWork = TRUE)); parent <- dirname(current); if (identical(parent, current)) stop("Cannot locate project root."); current <- parent } }
get_arg <- function(name, default = NULL) { prefix <- paste0("--", name, "="); matches <- commandArgs(trailingOnly = TRUE)[startsWith(commandArgs(trailingOnly = TRUE), prefix)]; if (!length(matches)) return(default); if (length(matches) != 1L) stop("Argument may appear once: --", name); substring(matches, nchar(prefix) + 1L) }
parse_bool <- function(value, name) { normalized <- tolower(trimws(value)); if (normalized %in% c("true", "yes", "y", "1")) return(TRUE); if (normalized %in% c("false", "no", "n", "0")) return(FALSE); stop("--", name, " must be true/false.") }
project_dir <- find_project_dir(script_file); helper_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
for (helper in c("study_paths.R", "io.R", "specification.R", "canonical_hash.R", "standard_contract.R", "standard_analysis_definition.R", "analysis_plan.R", "analysis_contract_generation.R", "analysis_approval.R", "standard_engine.R", "standard_artifacts.R")) source(file.path(helper_dir, helper), encoding = "UTF-8")
approval_payload_sha256 <- "<APPROVAL_PAYLOAD_SHA256>"; contract_sha256 <- "<CONTRACT_SHA256>"
if (any(grepl("^<.+>$", c(approval_payload_sha256, contract_sha256)))) stop("Collector generation is incomplete.")
mode <- get_arg("mode", "run-and-collect"); fail_fast_arg <- get_arg("fail-fast", NULL); fail_fast <- if (is.null(fail_fast_arg)) NULL else parse_bool(fail_fast_arg, "fail-fast")
if (isTRUE(fail_fast)) stop("Standard MMRM collector requires fail_fast=false.")
run_standard_mmrm_collector(script_file, approval_payload_sha256, contract_sha256, mode = mode, fail_fast = fail_fast)
