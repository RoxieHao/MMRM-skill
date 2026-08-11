suppressPackageStartupMessages({
  library(writexl)
})

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
if (length(script_arg) != 1) stop("Run this file with Rscript.")
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg), winslash = "/"))
study_dir <- dirname(script_dir)
table_dir <- file.path(study_dir, "model-run", "output", "tables")
out_file <- file.path(table_dir, "fcn_159_002_mmrm_tables.xlsx")
if (file.exists(out_file)) {
  probe <- try(file(out_file, open = "a+b"), silent = TRUE)
  if (inherits(probe, "try-error")) {
    out_file <- file.path(
      table_dir,
      paste0("fcn_159_002_mmrm_tables_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".xlsx")
    )
  } else {
    close(probe)
  }
}

read_table <- function(file_name) {
  read.csv(
    file.path(table_dir, file_name),
    stringsAsFactors = FALSE,
    fileEncoding = "UTF-8-BOM"
  )
}

sheets <- list(
  manifest = read_table("table_output_manifest.csv"),
  table_14_2_10_1_2 = read_table("table_14_2_10_1_2_mmrm.csv"),
  table_14_2_11_2 = read_table("table_14_2_11_2_mmrm.csv"),
  table_14_2_12_1_2 = read_table("table_14_2_12_1_2_mmrm.csv"),
  table_14_2_13_1_2 = read_table("table_14_2_13_1_2_mmrm.csv"),
  table_14_2_14_1_2 = read_table("table_14_2_14_1_2_mmrm.csv")
)

write_xlsx(sheets, path = out_file)

message("Workbook created: ", out_file)
