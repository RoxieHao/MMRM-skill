# Study MMRM 质量修复设计

## 目标与约束

修复已识别的 traceability、模型状态、运行复现和测试契约问题。保留现有 `.codex/study-mmrm-analysis/` 目录；不删除、移动或复制已有 study 数据、脚本和输出。

## 方案比较

1. 推荐：就地最小修复现有脚本和文档，增加一个统一运行入口及一个项目检查入口。改动小，现有产物继续可用。
2. 重写为通用 R 框架。可减少重复，但会扩大范围并引入未经多 study 验证的抽象。
3. 仅修文档、不改脚本。风险最低，但无法解决错误的 `fit` 状态和工作目录依赖。

采用方案 1。

## 实施内容

### FCN traceability

- 新增 `adam-parameter-mapping.md`，覆盖五个 MMRM TFL 的 dataset、PARAM/PARAMCD、filter、模型角色、source trace、QC 和确认状态。
- 新增 `model-run/output/mmrm_variable_review.md`，明确当前运行是部分完成，且不把稀疏、不可估计参数写成成功结果。

### 模型状态

- 只有模型拟合和所需 `emmeans` 字段均完整时才标记 `fit`。
- 模型已返回但 estimate、SE、df、CI 或 p-value 不完整时标记 `fit_incomplete`。
- manifest 将 `fit_incomplete` 计入失败或未完成参数。
- 保留原始模型消息和不完整的估计行用于追溯。

### 路径、日志和 manifest

- 所有 R 脚本从自身 `--file` 路径定位 study 目录，不依赖当前工作目录。
- FCN 新增一个 PowerShell pipeline runner，按顺序执行四个生产脚本，将命令、开始/结束时间、输出和退出码写入单一 UTF-8 日志，遇到非零退出码立即停止。
- manifest 保存 study 相对路径，不写本机绝对路径。

### Cross-study fixture

- 将空字段填写为明确的 `Not applicable` 或跨 study 方法比较结论。
- 新增 documentation-only `scan-summary.md`；不伪装为可运行模型测试。

### 项目治理与验证

- 初始化 Git，但不提交文件。
- 新增 `.gitignore`，忽略大型 source datasets、生成输出、临时提取目录和常见 R 临时文件；已有文件不受影响。
- 新增一个 PowerShell 验证入口，检查 Skill YAML、R 语法、fixture 必需文档以及 `fit` 输出完整性。

## 验证

- 从项目根目录和 study `model-run` 目录分别验证 R 脚本路径解析。
- 运行静态 R parse、Skill quick validation 和 fixture contract 检查。
- 运行 FCN pipeline，确认日志产生、manifest 为相对路径，且不完整结果不再标记为 `fit`。
- 不重跑约 12 分钟的 Triferic 模型；只做路径解析和语法检查，避免无必要地覆盖既有正式输出。

## 范围外

- 不处理 `.agents/skills` 发现路径。
- 不实现 Triferic MMRM prediction/imputation。
- 不删除旧嵌套失败日志或任何历史输出。
- 不对原始临床数据进行新的完整统计复核或真实性评分。
