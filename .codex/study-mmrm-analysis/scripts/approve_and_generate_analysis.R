options(encoding = "UTF-8")
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(name) { prefix <- paste0("--", name, "="); values <- args[startsWith(args, prefix)]; if (length(values) != 1L) stop("Exactly one --", name, "=<value> is required."); substring(values, nchar(prefix) + 1L) }
find_project_root <- function(path) { current <- normalizePath(path, winslash = "/", mustWork = TRUE); repeat { if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "analysis_approval.R"))) return(current); parent <- dirname(current); if (identical(parent, current)) stop("Cannot locate project root."); current <- parent } }
study_dir <- normalizePath(get_arg("study-dir"), winslash = "/", mustWork = TRUE); reviewer <- trimws(get_arg("reviewer")); project_dir <- find_project_root(study_dir); helper_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
for (helper in c("dependencies.R", "io.R", "specification.R", "canonical_hash.R", "standard_contract.R", "standard_analysis_definition.R", "analysis_plan.R", "analysis_contract_generation.R", "standard_sas.R", "analysis_approval.R")) source(file.path(helper_dir, helper), encoding = "UTF-8")
ensure_skill_packages(); chain <- approve_and_generate_analysis(study_dir, project_dir, reviewer)
cat("Approved and generated analysis set. approval_payload_sha256=", chain$approval_payload_sha256, "; contract_sha256=", chain$contract_sha256, "\n", sep = "")
