# MMRM Intake 多格式抽取与 Manifest 审计设计

日期：2026-08-17
状态：已确认，进入实现

## 背景与问题

`.codex/study-mmrm-analysis` 的 intake 扫描只识别 `input/` 下已在 `backup-trace/input-manifest.csv`
登记且扩展名为 `txt`/`md` 的文件，用于发现 MMRM TFL 候选。实际 study 的主要材料是
PDF（SAP、CSR）、DOCX（shell 模板）和 XLSX（ADaM specification），这些既不会被文本扫描，
也没有可追溯的抽取证据。

对比同一 study 的两次运行发现，真正导致 Kimi 版本“扫不出 TFL”的直接原因并非模型能力，
而是 `input-manifest.csv` 只登记了 `statistician-analysis-input.md`，而实际已复制进 `input/`
的 `shell/fcn_table_template.txt` 从未进入 manifest：

- GPT-5.4 v5：manifest 登记约 30 个文件，scan 选中 2 个文本材料（TXT+MD），识别 5 个 TFL；
  全部 5 个 TFL 来自 `input/shell/fcn_table_template.txt`，并非 PDF/DOCX/XLSX。
- Kimi v6：manifest 仅 1 行（Markdown briefing），scan 只读该 Markdown，识别 0 个 TFL。

根因是 `intake_auto_register_inputs_if_needed()`：只要 manifest 中已存在任意一条
`registered_input`，就直接返回，不再补登记后续放入 `input/` 的文件。

## 目标

1. 修复 manifest 同步：intake 运行时自动登记 `input/` 中当前全部文件；已登记文件被修改、
   删除或 SHA-256 不一致时 fail closed，要求人工确认，不静默改动已用于 review 的输入证据。
2. 新增文本型 PDF、DOCX、XLSX 的抽取层，产出标准化 UTF-8 文本与原始定位映射，供既有
   TFL 发现逻辑复用。
3. 将抽取结果与来源关系纳入 `backup-trace/input-manifest.csv` 审计，并在 review /
   scan trace 中保留原始文件定位（页码、段落、sheet/cell）。
4. 不改变人工审阅与签核流程，不引入 runtime fallback，不从历史 study/代码/结果补规则。

范围限定：第一版支持 TXT、MD、文本型 PDF、DOCX、XLSX。扫描型（图片）PDF 不做 OCR，
生成明确的 `ocr_required` 审计记录并阻止其被静默忽略。

## 依赖

本机 R 4.6.0 已安装：`digest`、`haven`、`readxl`（XLSX）、`officer`+`xml2`（DOCX）、
`pdftools`（PDF）、`testthat`。全部抽取包按需 `requireNamespace()` 检查并命名空间限定调用；
缺包时对应文件记 `blocked_missing_package`，不中断其它文件。

## 架构

新增独立模块 `R/intake_extraction.R`，在 `intake_review.R` 的发现流程之前运行。

### 1. 原始 manifest 同步（`intake_sync_input_manifest`）

- 递归枚举 `input/` 下全部常规文件。
- 对每个文件计算 SHA-256、大小、UTC mtime。
- 新文件：追加为 `registered_input`，`input_type=source_material`
  （`statistician-analysis-input.md` 记 `statistician_briefing`）。
- 已登记文件且 hash 一致：保留原行。
- 已登记文件 hash 变化、大小变化、或文件缺失：fail closed，报告 `relative_path`
  与期望/实际 hash，提示人工确认后重登记。
- 非 `input/` 目录下的既有 manifest 行（如 `linked_source`）原样保留，不被覆盖。
- 移除“已有任意 registered_input 即跳过”的旧短路逻辑。

### 2. 抽取层（`intake_extract_source`）

每个受支持格式的已登记原始文件抽取为：

- `text`：标准化 UTF-8 文本行向量；
- `locators`：与 `text` 等长的原始定位字符串向量。

定位约定：

| 格式 | 原始定位 |
|---|---|
| TXT / MD | 原文件直接扫描，沿用 `文件:L起始-L结束`（无派生） |
| 文本型 PDF | `p<页码>` |
| DOCX | `paragraph=<doc_index>` 或 `table=<tid>,row=<rid>,cell=<cid>` |
| XLSX | `sheet=<名称>,row=<行号>` |

实现：PDF 用 `pdftools::pdf_text` 按页分行；DOCX 用 `officer::read_docx` +
`officer::docx_summary` 遍历段落与表格单元；XLSX 用 `readxl::excel_sheets` +
`readxl::read_excel(col_names=FALSE)` 按行拼接单元格。

### 3. 运行期临时抽取文件

PDF、DOCX、XLSX 的标准化文本与 `extracted_line,source_locator` 定位映射仅写入系统临时目录，
仅供本次扫描在内存中反查原始位置。扫描、review 与 trace 写完后立即删除；不得写入 study
目录、`backup-trace/`、manifest 或正式交付物。

### 4. Manifest 审计字段

保持 `input-manifest.csv` 为唯一审计入口，原始文件仍是一行，新增描述最近一次抽取的列：

```
extraction_status        # not_required | succeeded | ocr_required | blocked_missing_package | failed
extraction_format        # txt|md|pdf|docx|xlsx
extractor_id             # pdftools|officer|readxl|native
extractor_version        # 包版本
extracted_at_utc
extraction_note          # 中文说明或错误摘要
```

为向后兼容，读取端对缺列的旧 manifest 容错（`intake_manifest_for_review` 仅强制
`relative_path/sha256/status`）。写入端补齐所有列。

不存在“看似成功但无文本”的静默路径：二进制抽取失败/无文本层的文件保留在 manifest 和
scan trace，但不喂给 TFL 识别器；review 明确提示统计师补充可读材料或确认不适用。

### 5. 发现流程衔接

`intake_text_sources()` 升级为 `intake_scannable_sources()`：

- TXT/MD：返回原文件，无 locator 映射（沿用 `:Lx-Ly`）。
- PDF/DOCX/XLSX：返回运行期临时 `extracted-text.txt`，在本次扫描中以临时 location map
  反查原始 `relative_path` 的定位；扫描结束立即删除二者。

发现逻辑（briefing parser 与中文表标题/MMRM 正则）不变，只替换输入来源与证据引用。
在抽取文本命中区间 `[start,end]` 时，经临时 location map 反查原始定位，source reference 为：

```
<原始relative_path>:<原始定位聚合>
```

TXT/MD 行为完全不变。

## 错误处理

- 缺抽取包：该文件 `blocked_missing_package`，继续处理其它文件；review 提示安装依赖。
- PDF 无文本层（`pdf_text` 全空白）：`ocr_required`。
- 文件损坏/加密/读取异常：`failed`，记录中文错误摘要。
- 已登记文件变更/删除：整个 intake fail closed（数据完整性优先于产出）。
- XLSX 单元格公式/前导 `=`/`+`/`-`/`@`：作为纯文本读取，抽取文本中对危险前缀加空格前置，
  防止下游 Excel 打开派生 CSV 时的公式注入。

## 测试

新增 `scripts/check_intake_extraction.R`（tinytest 未装，使用 `stopifnot` 风格，
与既有 `check_intake_enrichment.R` 一致）：

1. 合成含中文 MMRM 表标题的 DOCX、XLSX，以及文本型 PDF（用 pdftools 可读的最小 PDF），
   放入临时 study 的 `input/`；不预写 manifest。
2. 运行同步，断言 manifest 自动登记全部文件并含抽取审计列。
3. 断言临时抽取文本/定位映射在扫描期间可用、扫描返回后已删除，且 manifest 不记录其路径或 hash。
4. 断言 review/scan trace 识别到 MMRM TFL，且 source_ref 只含原始定位（`p`、`paragraph=`、
   `sheet=`）。
5. 变更/删除已登记文件后重跑，断言 fail closed。
6. 移除某抽取包场景（模拟 `requireNamespace` 失败）断言 `blocked_missing_package` 且不崩溃。
7. 清理临时产物。

同时扩展 `R/tests/check_standard_profile.R` 的 intake smoke，保持 TXT 路径回归通过。

## 非目标

- 不实现 OCR。
- 不改变 approved specification / contract / adapter 的 SHA 绑定与 gate。
- 不将 source documents 作为 runtime fallback。
- 不自动确认任何统计语义 mapping。
