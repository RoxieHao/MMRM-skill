# Inputs

Study test case: `fcn_159_002`

## Source Materials

- SAP: `source/FCN-159-002-统计分析计划-V1.0-20240112-Clean-已签字.pdf`
- CSR: `source/FCN-159-I型神经纤维瘤-II期 儿童队列-CSR-clean-final-20240408-（含PI和申办方签字）.pdf`
- TFL shell: `source/FCN-159-002 表格列表图表模板 （ II期 儿童)-V1.1-20240124.docx`
- Extracted shell text: `source/fcn_table_template.txt`
- ADaM specification: `source/FCN159-002 ADaM Specification v0.1.xlsx`
- Corrected ADaM datasets: `source/adam/*.sas7bdat`

## Corrected Data Inventory

`source/adam` contains 26 ADaM datasets:

`adae`, `adaw`, `adcm`, `adcv`, `addv`, `adeff`, `adeg`, `adex`, `adexsum`, `adft`, `adlb`, `admh`, `admk`, `admo`, `adoe`, `adpc`, `adpe`, `adpr`, `adqs`, `adqssum`, `adre`, `adrs`, `adsl`, `adtr`, `adtte`, `advs`.

Primary datasets for this MMRM test:

- Subject-level population source: `adsl.sas7bdat`
- COA endpoint source: `adqssum.sas7bdat`

