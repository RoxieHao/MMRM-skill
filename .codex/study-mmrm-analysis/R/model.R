required_inference_cols <- function() {
  c("emmean", "SE", "df", "lower.CL", "upper.CL", "p.value")
}

inference_complete <- function(data, required = required_inference_cols()) {
  nrow(data) > 0 &&
    all(required %in% names(data)) &&
    all(complete.cases(data[required]))
}

mmrm_control_for_covariance <- function(covariance) {
  if (covariance == "UN") {
    mmrm_control(
      method = "Kenward-Roger",
      vcov = "Kenward-Roger-Linear"
    )
  } else {
    mmrm_control(method = "Kenward-Roger")
  }
}

