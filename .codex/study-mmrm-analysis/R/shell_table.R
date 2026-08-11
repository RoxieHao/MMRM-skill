fmt_num <- function(x, digits = 2) {
  ifelse(is.na(x), "", formatC(x, digits = digits, format = "f"))
}

fmt_p <- function(x) {
  ifelse(is.na(x), "", ifelse(x < 0.0001, "<0.0001", formatC(x, digits = 4, format = "f")))
}

fmt_mean_sd <- function(mean, sd, n, digits = 2) {
  ifelse(
    is.na(n) | n == 0,
    "",
    paste0(fmt_num(mean, digits), " (", fmt_num(sd, digits), ")")
  )
}

fmt_mean_se <- function(mean, se, digits = 1) {
  ifelse(is.na(mean) | is.na(se), "", paste0(fmt_num(mean, digits), " (", fmt_num(se, digits), ")"))
}

fmt_ci <- function(lower, upper, digits = 1) {
  ifelse(is.na(lower) | is.na(upper), "", paste0("(", fmt_num(lower, digits), ", ", fmt_num(upper, digits), ")"))
}

fmt_min_max <- function(min, max, n, digits = 2) {
  ifelse(
    is.na(n) | n == 0,
    "",
    paste0(fmt_num(min, digits), ", ", fmt_num(max, digits))
  )
}

summarise_value <- function(x) {
  n <- sum(!is.na(x))
  tibble(
    n = n,
    mean = ifelse(n > 0, mean(x, na.rm = TRUE), NA_real_),
    sd = ifelse(n > 1, sd(x, na.rm = TRUE), NA_real_),
    median = ifelse(n > 0, median(x, na.rm = TRUE), NA_real_),
    min = ifelse(n > 0, min(x, na.rm = TRUE), NA_real_),
    max = ifelse(n > 0, max(x, na.rm = TRUE), NA_real_)
  )
}

shell_value <- function(data, value_col, filter_col = NULL, filter_value = NULL) {
  if (!is.null(filter_col)) {
    data <- data[data[[filter_col]] == filter_value, , drop = FALSE]
  }
  value <- unique(data[[value_col]][!is.na(data[[value_col]])])
  if (length(value) == 0) return("")
  if (length(value) > 1) stop("Expected one shell value, found ", length(value), ".")
  as.character(value[[1]])
}
