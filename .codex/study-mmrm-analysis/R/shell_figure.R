save_mmrm_visit_figure <- function(
    data,
    png_path,
    title,
    y_label,
    x_label = "\u8bbf\u89c6",
    color_label = "\u6cbb\u7597\u7ec4") {
  stopifnot(requireNamespace("ggplot2", quietly = TRUE))

  plot_data <- data
  plot_data$AVISIT <- factor(plot_data$AVISIT, levels = unique(plot_data$AVISIT))

  figure <- ggplot2::ggplot(
    plot_data,
    ggplot2::aes(x = AVISIT, y = emmean, color = TRT01P, group = TRT01P)
  ) +
    ggplot2::geom_hline(yintercept = 0, linewidth = 0.3, color = "grey70") +
    ggplot2::geom_line(linewidth = 0.7) +
    ggplot2::geom_point(size = 1.8) +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = lower.CL, ymax = upper.CL),
      width = 0.15,
      linewidth = 0.4
    ) +
    ggplot2::labs(
      title = title,
      x = x_label,
      y = y_label,
      color = color_label
    ) +
    ggplot2::theme_bw(base_size = 10) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold"),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
      legend.position = "bottom"
    )

  ggplot2::ggsave(png_path, figure, width = 10, height = 5.5, dpi = 300)
  invisible(figure)
}
