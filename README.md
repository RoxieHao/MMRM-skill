# MMRM 项目说明

这个项目用于支持一套受控的 MMRM 工作流。当前主线是先把通用 `study-mmrm-analysis` skill 写稳定，再用 study 数据作为测试集验证它。

重点是：

1. 从 SAP / shell 中提取明确规则。
2. 对未明确的统计规则保持留空，不自行补全。
3. 把待确认问题显式留给统计师。
4. 按 study-specific 脚本完成数据准备。
5. 真实运行脚本，并通过 engineering loop 提高代码正确率。
6. 留下可供统计师和程序员复核的日志与输出。

## 核心原则

AI 不能发明统计规则。

如果某条规则在 SAP / shell 中没有明确写出，就不要默认补上，而要标记为待统计师确认。

## 关键文档

1. `docs/mmrm/guides/MMRM_data_preparation_guide_CN.md`
   作用：MMRM 数据准备方法总纲。

2. `docs/mmrm/guides/study_workflow_CN.md`
   作用：每个新 study 的标准工作流说明。

3. `docs/mmrm/templates/programming_note_template.md`
   作用：程序实现约定模板。

4. `docs/mmrm/templates/mmrm_variable_review_template.md`
   作用：脚本成功运行后，给统计师审核关键 MMRM 变量来源与派生路径的精简模板。

## 本机工具入口

- Python 快捷方式：`C:\Users\haoruoxi\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Python\Python 3.14\Python 3.14.lnk`
- Python 可执行文件：`C:\Users\haoruoxi\AppData\Local\Python\pythoncore-3.14-64\python.exe`
- R 快捷方式：`C:\ProgramData\Microsoft\Windows\Start Menu\Programs\R\R 4.6.0.lnk`
- R 可执行文件：`D:\R-4.6.0\bin\x64\Rscript.exe`
- 项目约定：调用 Python 或 R 时，优先使用这里写明的入口，不依赖 PATH 猜测。

## 项目目录

- `docs/mmrm/guides/`：跨 study 可复用的方法文档。
- `docs/mmrm/templates/`：可复用的辅助模板文档。
- `.codex/study-mmrm-analysis/`：项目 skill 定义与入口文档。
- `.codex/study-mmrm-analysis/tests/`：skill 开发期 study 测试集；工程化后可迁移或删除。
- `studies/<study_id>/checks/`：如果后续生成 study test case，可放 scan summary、code plan、example check。
- `studies/<study_id>/analysis/`：如果后续生成 study test case，可放 study-specific 主脚本。
- `studies/<study_id>/output/`：如果后续生成 study test case，可放日志、`.rds` 和其他运行产物。

## 主工作流

当前项目最推荐的工作方式是：

`guide -> scan summary -> code plan -> study-specific R script -> engineering loop run -> output/log -> mmrm_variable_review`

详细步骤请看：

- `docs/mmrm/guides/study_workflow_CN.md`

## 项目验证

在项目根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate_project.ps1
```

该检查会验证 Skill 格式、R 语法、study fixture 必需文件、FCN 完整拟合状态和 manifest 相对路径。大型 source datasets、生成输出和临时提取文件通过 `.gitignore` 排除，但本地历史文件不会被删除。

## 当前建设优先级

1. 先完善 `.codex/study-mmrm-analysis/` 中的通用 skill、route、analysis definition checklist、输出约束和测试规则。
2. 再用 study 数据作为测试集，验证 skill 是否能稳定指导 scan、planning、coding、run、QC 和 review。
3. 所有 study 执行都先视为 skill 测试；测试稳定并准备工程化后，再决定是否保留或迁移测试资料。

## Population Flag 总原则

像 `ITT`、`FAS`、`PPS`、`SS` 这样的分析人群标志，应先从 SAP 中找正式定义，再映射到 raw dataset 和 source variable。

不要一开始就直接从 raw dataset 猜。

## Scan Summary 总原则

对于真实 study 的 scan summary，必须把 SAP 中写出的全部 analysis population rules 明确展开。

尤其是 `PPS`，如果 SAP 里写了逐条标准、例外条件或重归类规则，scan summary 里也必须完整保留。
