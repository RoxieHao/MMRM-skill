read_utf8_bom_csv <- function(path) {
  read.csv(
    path,
    stringsAsFactors = FALSE,
    fileEncoding = "UTF-8-BOM",
    check.names = FALSE
  )
}

write_utf8_bom_csv <- function(data, path) {
  binary_con <- file(path, open = "wb")
  on.exit(try(close(binary_con), silent = TRUE), add = TRUE)
  writeBin(as.raw(c(0xEF, 0xBB, 0xBF)), binary_con)
  close(binary_con)

  text_con <- file(path, open = "at", encoding = "UTF-8")
  on.exit(try(close(text_con), silent = TRUE), add = TRUE)
  write.csv(data, text_con, row.names = FALSE, na = "")
}

open_utf8_log <- function(path) {
  tryCatch(
    file(path, open = "wt", encoding = "UTF-8"),
    error = function(e) {
      fallback <- file.path(
        dirname(path),
        paste0(tools::file_path_sans_ext(basename(path)), "_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".log")
      )
      file(fallback, open = "wt", encoding = "UTF-8")
    }
  )
}

with_sink_cleanup <- function(connection) {
  on.exit({
    sink()
    close(connection)
  }, add = TRUE)
}

