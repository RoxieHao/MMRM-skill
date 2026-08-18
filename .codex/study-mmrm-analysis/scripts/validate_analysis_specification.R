options(encoding = "UTF-8")

args <- commandArgs(TRUE)
value_arg <- function(name, required = TRUE) {
  prefix <- paste0("--", name, "=")
  match <- args[startsWith(args, prefix)]
  if (length(match) == 0) {
    if (required) stop("\u7f3a\u5c11\u53c2\u6570 --", name, "=<value>")
    return(NULL)
  }
  if (length(match) != 1) stop("\u53c2\u6570\u53ea\u80fd\u51fa\u73b0\u4e00\u6b21\uff1a--", name)
  sub(paste0("^", prefix), "", match)
}

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_file <- normalizePath(sub("^--file=", "", script_arg), winslash = "/", mustWork = TRUE)
skill_dir <- normalizePath(file.path(dirname(script_file), ".."), winslash = "/", mustWork = TRUE)
source(file.path(skill_dir, "R", "specification.R"), encoding = "UTF-8")

spec_path <- value_arg("spec")
project_root <- value_arg("project-root")
report_path <- value_arg("report")
checks <- validate_analysis_specification(spec_path, project_root = project_root)
write_analysis_specification_validation(checks, report_path)
print(checks, row.names = FALSE)
if (!analysis_specification_is_valid(checks)) quit(status = 1)
cat("Analysis specification validation passed.\n")
