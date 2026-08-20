# 本地 R 顶级阶段隔离兼容设计

## 目标

让 `study-mmrm-analysis` 在本机 `D:\R-4.6.0\bin\Rscript.exe` 下避免已确认的 namespace/原生运行时崩溃，同时保留缺包自动安装、正式 `mmrm` 拟合、统计审批 gate、typed contract、模型定义、诊断和 artifact 契约。

已确认的最小问题是：`haven` 间接加载 `vctrs` 后，再加载 `mmrm` 间接依赖的 `Matrix`，R 4.6.0 进程会异常终止。进一步验证表明，即使 `haven` 和 `mmrm` 分别由子进程成功加载，同一父 R 进程顺序创建这些子进程时仍可能直接终止。因此，逐包顺序健康检查和 wrapper 内部 `callr` 隔离都不足以构成可靠边界；两个 package 栈必须位于先后执行且生命周期不重叠的顶级 `Rscript` 进程中。

## 范围

生产修改集中在：

- `.codex/study-mmrm-analysis/R/dependencies.R`：仅负责安装元数据检查和自动安装，不执行全量 namespace 健康检查；
- `.codex/study-mmrm-analysis/R/standard_engine.R`：把现有分析流程拆成数据准备、拟合/产物生成两个可独立运行的阶段，并保留现有业务函数；
- 必要的顶级阶段 runner 或现有生成模板：负责启动阶段进程、传递受控临时路径、检查退出状态并清理临时文件。

可扩展现有 check script 验证阶段边界。不得改变 study-specific specification、approved contract、统计模型、covariance fallback、collector 输入输出、TFL schema、diagnostics schema 或正式 manifest。

## 依赖管理

### 安装检测

`skill_missing_packages()` 使用 `installed.packages()` 或等价安装元数据判断 package 是否存在，不在调用进程中依次执行 `requireNamespace()`。这样 dependency check 不累计加载 `haven/vctrs` 与 `mmrm/Matrix`。

### 自动安装

保留当前默认自动安装行为：

1. 从安装元数据找出缺失 package；
2. 使用现有 repository 配置调用 `install.packages()`；
3. 安装完成后重新读取安装元数据；
4. 若仍有缺包，报告 package 名并失败；
5. 不在一次 dependency check 中逐包启动运行期健康检查。

`MMRM_SKILL_NO_INSTALL=1` 继续禁用自动安装。package 的运行期可用性由真正需要它的阶段在自己的干净顶级进程中验证，因此安装问题可归属到明确阶段，又不会为了预检制造冲突进程序列。

### R 可执行文件

所有阶段必须使用当前运行中 R 对应的 `Rscript`，由 `R.home("bin")` 解析 Windows `Rscript.exe`，并继承当前 `.libPaths()`。不得依赖 PATH，也不得在 skill 中硬编码 `D:\R-4.6.0`；从该本地 R 启动时，后续阶段自然使用同一安装。

## 顶级阶段架构

### Orchestrator

现有外部入口仍接收相同的 approved specification、contract、study 路径和输出路径。orchestrator 本身不加载 `haven`、`mmrm`、`vctrs`、`Matrix` 或 `emmeans`，只负责：

1. 建立单次运行专属的临时工作目录；
2. 启动数据准备 `Rscript --vanilla`；
3. 等待该进程完全退出，并校验退出码与完成 marker；
4. 成功后启动拟合/产物 `Rscript --vanilla`；
5. 等待退出并校验结果；
6. 无论成功或失败都清理中间 RDS、marker 和阶段日志，正式审计日志除外。

两个阶段不得并发，也不得由仍加载 `haven` 的 R 父会话通过 `callr` 启动拟合。隔离边界是操作系统级、生命周期不重叠的顶级 Rscript 进程。

### 阶段一：数据准备

数据准备进程只加载读取和准备数据所需的 package，包括 `haven`；不得加载 `mmrm`、`emmeans` 或显式加载 `Matrix`。它继续执行现有逻辑：

- approved specification/contract 与 linked source path/SHA 验证；
- SAS7BDAT 读取；
- adapter、filter、mapping、factor 和数据 QC；
- 生成拟合需要的普通 R 对象。

阶段输出写入运行专属临时 RDS，并附带最小完成 marker。RDS 只包含拟合所需数据和已验证的运行参数，不是正式 artifact，不加入 manifest，也不作为跨运行缓存。

### 阶段二：拟合与正式产物

阶段一进程完全退出后，orchestrator 启动新的 Rscript。该进程加载 `mmrm` 和 `emmeans`，不得加载 `haven`。它读取临时 RDS，并复用现有 approved covariance/fallback、推断、模型 RDS、diagnostics、raw/final TFL、log 和 run record 逻辑。

正式产物路径、内容、identity/hash 规则和 collector 协议保持不变。内部是否继续对 group 使用 worker 函数属于实现细节，但不能重新引入 `haven` package 栈，也不能改变统计结果。

## 临时交换契约

临时 RDS 必须满足：

- 位于单次运行专属临时目录；
- 由 orchestrator 生成不可复用的路径并显式传给两个阶段；
- 包含 schema/version 字段、run identity、validated contract identity、准备后的 group data 和阶段二所需参数；
- 阶段二在拟合前校验 schema/version 与 identity；
- 仅在阶段一完整写入后创建完成 marker，避免读取半写文件；
- 成功、失败或中断后的正常错误路径均尝试清理；
- 不进入正式 output manifest、backup trace 或审计输入。

## Intake 路径

intake 使用同一 metadata-only dependency helper，但只在实际需要时加载 `haven/readxl/pdftools/officer` 等 intake package。它不应因 skill 的全量 package 列表而加载 `mmrm/emmeans/Matrix`。

目标 study intake 成功后只生成 pending statistical review、endpoint mapping、input manifest/scan trace 等待审阅的产物，并停在人工统计审阅 gate；不得自动批准 specification、contract 或执行正式模型。

## 错误处理

- **缺包**：沿用自动安装；禁用安装或安装后仍缺失时，列出 package 并失败。
- **阶段一 package/数据错误**：标识为 data-preparation stage failure，记录退出码和可操作日志，不启动阶段二。
- **临时交换错误**：缺少 marker、RDS schema/version 或 identity 不匹配时阻断拟合。
- **阶段二 package/模型错误**：标识为 fit/artifact stage failure，保留现有模型失败诊断语义，不宣告运行成功。
- **原生异常终止**：缺少完成 marker 即视为阶段失败，即使没有可解析的 R condition。
- **清理失败**：不得覆盖主要失败；应报告残留临时路径，供人工安全删除。
- 不通过调换 package 加载顺序、吞掉非零退出或复用旧临时 RDS 规避错误。

## 验证

按以下顺序验证：

1. 静态解析所有修改或新增的 R 文件；
2. 使用 `D:\R-4.6.0\bin\Rscript.exe` 运行 metadata-only dependency check；
3. 验证 dependency check 后当前进程未加载 `haven/mmrm/vctrs/Matrix/emmeans`；
4. 运行目标 study intake，确认真实 SAS7BDAT、PDF、DOCX 和 XLSX 抽取成功；
5. 核对 pending review、endpoint mapping、input manifest 和 scan trace，并确认停在人工审阅 gate；
6. 使用受控测试输入运行阶段一，确认其进程中未加载 `mmrm/emmeans/Matrix`，且退出后产生有效临时交换；
7. 在阶段一完全退出后运行阶段二，确认其未加载 `haven/vctrs`，并仍使用正式 `mmrm` engine；
8. 运行现有 Standard Profile check，比较模型、RDS identity、raw/final TFL、diagnostics、collector 和 collect-only 行为；
9. 验证成功和故意失败路径都不会把临时交换文件加入正式 manifest，并会执行清理。

## 成功标准

- 本地 R 4.6.0 下 dependency check 和目标 study intake 不再因 `haven -> mmrm` 组合终止。
- 缺包仍可自动安装；运行期 package 验证发生在实际使用它的隔离阶段。
- `haven/vctrs` 与 `mmrm/Matrix/emmeans` 不存在于生命周期重叠的分析进程中。
- 两个正式分析阶段只能通过校验过的单次运行临时 RDS 交换数据。
- 现有审批、hash、contract、模型、fallback、diagnostics、collector、manifest 和输出契约保持不变。
- intake 在统计师批准前停止，不执行正式拟合。
- 正式阶段完成后不保留临时分析数据或辅助 marker。

## 非目标与剩余风险

- 不修补或替换 R 4.6.0 本身，也不声称消除该运行时的其他原生缺陷。
- 不更换 `mmrm` engine。
- 不自动批准统计规则。
- 不从旧 study、旧程序或结果补充 endpoint/model 规则。
- 不更改正式 TFL、manifest 或 diagnostics schema。
- 如果顶级、非重叠 Rscript 阶段仍发生原生终止，则本地混版 package 库不能被 skill 可靠规避；届时必须在 R 4.6.0 下重建一致的 package 库，或升级 R 后重装依赖，不能继续增加进程嵌套作为补丁。
