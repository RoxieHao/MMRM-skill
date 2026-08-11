build_fcn_pedsql_tfl <- function(adqssum) {
  adqssum %>%
    filter(PARCAT1N == 11) %>%
    mutate(
      PARAMCD_ORIG = PARAMCD,
      PARAM_ORIG = PARAM,
      reporter = case_when(
        PARCAT2N %in% c(1, 2) ~ "受试者报告",
        PARCAT2N %in% c(3, 4, 5, 6) ~ "家长报告",
        TRUE ~ "未识别报告者"
      ),
      scale = case_when(
        grepl("^TS", PARAMCD_ORIG) ~ "总分",
        grepl("^PF", PARAMCD_ORIG) ~ "生理功能",
        grepl("^EF", PARAMCD_ORIG) ~ "情感功能",
        grepl("^SOF", PARAMCD_ORIG) ~ "社交功能",
        grepl("^SCF", PARAMCD_ORIG) ~ "学校表现",
        TRUE ~ PARAM_ORIG
      ),
      scale_code = case_when(
        grepl("^TS", PARAMCD_ORIG) ~ "TS",
        grepl("^PF", PARAMCD_ORIG) ~ "PF",
        grepl("^EF", PARAMCD_ORIG) ~ "EF",
        grepl("^SOF", PARAMCD_ORIG) ~ "SOF",
        grepl("^SCF", PARAMCD_ORIG) ~ "SCF",
        TRUE ~ PARAMCD_ORIG
      ),
      reporter_code = if_else(reporter == "受试者报告", "PAT", "PAR"),
      PARAMCD = paste0("PEDSQL_", reporter_code, "_", scale_code),
      PARAM = paste(reporter, scale, sep = " / ")
    )
}

build_fcn_tfl_specs <- function(adqssum, admk) {
  pedsql_tfl <- build_fcn_pedsql_tfl(adqssum)

  list(
    list(
      tfl_id = "14.2.10.1.2",
      title = "PedsQL生活质量量表观测值及相对基线变化-MMRM-汇总（COA分析集）",
      dataset = "ADQSSUM",
      data = pedsql_tfl,
      paramcd = c(
        "PEDSQL_PAT_TS", "PEDSQL_PAT_PF", "PEDSQL_PAT_EF",
        "PEDSQL_PAT_SOF", "PEDSQL_PAT_SCF",
        "PEDSQL_PAR_TS", "PEDSQL_PAR_PF", "PEDSQL_PAR_EF",
        "PEDSQL_PAR_SOF", "PEDSQL_PAR_SCF"
      )
    ),
    list(
      tfl_id = "14.2.11.2",
      title = "疼痛强度观测值及相对基线变化-MMRM-汇总（COA分析集）",
      dataset = "ADQSSUM",
      data = adqssum,
      paramcd = c("OVERPW", "OVERTPW", "PTOTW")
    ),
    list(
      tfl_id = "14.2.12.1.2",
      title = "疼痛干扰观测值及相对基线变化-MMRM-汇总（COA分析集）",
      dataset = "ADQSSUM",
      data = adqssum,
      paramcd = c("PAINTE", "PAINPR")
    ),
    list(
      tfl_id = "14.2.13.1.2",
      title = "肌力评估观测值及相对基线变化-MMRM-汇总（COA分析集）",
      dataset = "ADMK",
      data = admk,
      paramcd = admk %>%
        distinct(PARAMCD, PARCAT1, PARAMTYP) %>%
        filter(PARCAT1 == "肌力评估", PARAMTYP == "衍生") %>%
        pull(PARAMCD)
    ),
    list(
      tfl_id = "14.2.14.1.2",
      title = "关节活动范围评估观测值及相对基线变化-MMRM-汇总（COA分析集）",
      dataset = "ADMK",
      data = admk,
      paramcd = admk %>%
        distinct(PARAMCD, PARCAT1, PARAMTYP) %>%
        filter(PARCAT1 == "关节活动范围评估", PARAMTYP == "衍生") %>%
        pull(PARAMCD)
    )
  )
}
