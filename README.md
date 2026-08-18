# MMRM 项目说明

这个项目用于维护一套受控的 MMRM 工作流。当前主线是把通用 `study-mmrm-analysis` skill 写稳定，再用 study 数据作为测试集验证它。

核心原则：AI 不能发明统计规则。如果 SAP、shell、ADaM specification 或统计师输入里没有明确定义，就必须留给统计师确认，不能默认补全。

## 关键文档

1. `docs/mmrm/guides/MMRM_data_preparation_guide_CN.md`  
   MMRM 数据准备方法总览。

2. `docs/mmrm/guides/study_workflow_CN.md`  
   每个新 study 的标准工作流说明。

3. `.codex/study-mmrm-analysis/`  
   当前通用 skill 定义、脚本、R helper、模板和参考文档。

## 本机工具入口

- Python 快捷方式：`C:\Users\haoruoxi\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Python\Python 3.14\Python 3.14.lnk`
- Python 可执行文件：`C:\Users\haoruoxi\AppData\Local\Python\pythoncore-3.14-64\python.exe`
- R 快捷方式：`C:\ProgramData\Microsoft\Windows\Start Menu\Programs\R\R 4.6.0.lnk`
- R 可执行文件：`D:\R-4.6.0\bin\x64\Rscript.exe`

项目约定：调用 Python 或 R 时，优先使用这里写明的入口，不依赖 `PATH` 猜测。

## 项目目录

- `docs/mmrm/guides/`：跨 study 可复用的方法文档。
- `docs/mmrm/templates/`：可复用的辅助模板文档。
- `.codex/study-mmrm-analysis/`：项目 skill 定义、入口脚本、R helper 和参考文档。
- `.codex/study-mmrm-analysis/R/tests/`：通用 skill 的集成测试。
- `studies/<study_id>/input/`：SAP、shell、ADaM、ADaM spec、TFL spec 或统计师自写输入。
- `studies/<study_id>/backup-trace/`：输入 manifest、hash、AI 提取记录和历史版本。
- `studies/<study_id>/statistician-review/`：`statistical-review.md` 和批准后的 `analysis-specification.md`。
- `studies/<study_id>/analysis/r/`：独立 R analysis 程序和 collector runner。
- `studies/<study_id>/analysis/sas/`：只读 SAS template。
- `studies/<study_id>/output/`：由 validated execution/collector 生成的正式输出、中文 diagnostics、logs、RDS 和唯一 `tfl-output-manifest.csv`。

## 主工作流

当前推荐流程是：

`input registration -> statistical-review.md -> analysis-specification.md gate -> independent R/SAS programs -> mmrm run -> analysis-scoped diagnostics -> single formal manifest`

也就是：不再用 workbook gate。人工签核落在 Markdown review/specification gate；QC 人读解释落在中文 diagnostics；正式交付清单只有一个 manifest；每个 analysis 的证据链都在自己的 output 子目录中。

详细步骤见：

- `docs/mmrm/guides/study_workflow_CN.md`

## 项目验证

在项目根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate_project.ps1
```

该检查只验证 general skill：Skill 格式、通用 R 语法、受控工作流模板、中文人读 diagnostics、单一 manifest、analysis-scoped artifacts、PNG-only figure、审批门禁和强制 `mmrm` engine。它不读取或修改旧 study/output fixture。

大型 source datasets、生成输出和临时提取文件通过 `.gitignore` 排除；本地历史文件不会被自动删除。

## 当前建设优先级

1. 使用通用 skill 初始化正式 study 的受控目录和审阅模板。
2. 先完成 `statistical-review.md` 和 `analysis-specification.md` gate，再生成正式 R/SAS 程序。
3. `tests/` 只作为 skill 开发期 fixture，不参与正式 study 执行。

## Population Flag 总原则

像 `ITT`、`FAS`、`PPS`、`SS` 这样的分析人群标志，应先从 SAP 中找正式定义，再映射到 raw dataset 和 source variable。不要一开始就直接从 raw dataset 猜。

## Scan Summary 总原则

对于真实 study 的 scan summary，必须把 SAP 中写出的全部 analysis population rules 明确展开。尤其是 `PPS`，如果 SAP 里写了逐条标准、例外条件或重归类规则，scan summary 里也必须完整保留。
