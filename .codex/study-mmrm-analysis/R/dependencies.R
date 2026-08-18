# Skill 依赖声明与检查/安装。
# 在 skill 的入口处调用 ensure_skill_packages()：检查全部运行期所需 R package，
# 缺失则自动安装（可用环境变量 MMRM_SKILL_NO_INSTALL=1 关闭自动安装，仅报错）。

# 运行期需要的全部 R package（xml2 由 officer 依赖自动带入）。
skill_runtime_packages <- function() {
  c(
    "digest",    # 文件与内容 SHA-256
    "yaml",      # specification / contract / case summary
    "haven",     # 读取 ADaM sas7bdat
    "mmrm",      # 正式 MMRM 拟合
    "emmeans",   # LSMeans / 估计量
    "callr",     # 隔离拟合与 RDS 校验
    "pdftools",  # 文本型 PDF 抽取
    "officer",   # DOCX 段落/表格抽取
    "readxl"     # XLSX sheet/cell 抽取
  )
}

# 仅自检/测试需要的 package，不参与运行期强制安装。
skill_test_packages <- function() {
  c("writexl", "testthat")
}

skill_missing_packages <- function(packages) {
  packages[!vapply(packages, function(p) requireNamespace(p, quietly = TRUE), logical(1))]
}

skill_default_repos <- function() {
  repos <- getOption("repos")
  first <- if (is.null(repos) || !length(repos)) "" else unname(repos[[1]])
  if (!nzchar(first) || identical(first, "@CRAN@")) return("https://cloud.r-project.org")
  repos
}

# 检查（并按需安装）指定 package 集合。返回本次安装的 package 向量。
ensure_skill_packages <- function(packages = skill_runtime_packages(), install = TRUE, repos = NULL, quiet = FALSE) {
  missing <- skill_missing_packages(packages)
  if (!length(missing)) {
    if (!quiet) message("Skill 依赖检查通过：", length(packages), " 个 package 全部就绪。")
    return(invisible(character()))
  }

  no_install <- tolower(trimws(Sys.getenv("MMRM_SKILL_NO_INSTALL")))
  auto_install <- isTRUE(install) && !(no_install %in% c("1", "true", "yes"))
  if (!auto_install) {
    stop(
      "缺少以下 R package 且未启用自动安装：", paste(missing, collapse = ", "),
      "。请手工安装，或取消 MMRM_SKILL_NO_INSTALL 后重跑。"
    )
  }

  if (is.null(repos) || !length(repos)) repos <- skill_default_repos()
  if (!quiet) message("检测到缺失 package，开始安装：", paste(missing, collapse = ", "))
  utils::install.packages(missing, repos = repos)

  still_missing <- skill_missing_packages(missing)
  if (length(still_missing)) {
    stop(
      "以下 package 安装后仍不可用：", paste(still_missing, collapse = ", "),
      "。请检查网络连接或手工安装后重跑。"
    )
  }
  if (!quiet) message("依赖安装完成：", paste(missing, collapse = ", "))
  invisible(missing)
}
