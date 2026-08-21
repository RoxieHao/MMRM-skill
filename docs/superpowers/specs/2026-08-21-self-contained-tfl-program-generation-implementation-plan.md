# 逐 TFL 自包含 R/SAS 程序生成实施计划

**设计：** `docs/superpowers/specs/2026-08-21-self-contained-tfl-program-generation-design.md`
**前置设计：** `docs/superpowers/specs/2026-08-19-mmrm-approved-analysis-plan-design.md`
**状态：** 待实施

## 1. 实施目标

把当前“每个 TFL 一个 R 薄 wrapper + 一个不完整 SAS template”替换为：

```text
已批准 analysis-plan.yaml
          ↓ 确定性编译
standard-mmrm-contract.yaml
          ↓ 逐 analysis/TFL 确定性渲染
analysis/r/<analysis_id>.R       完整、中文注释、自包含、可独立运行
analysis/sas/<analysis_id>.sas   完整、中文注释、自包含、可独立运行
```

完成后，每个 table TFL 必须恰好对应一个 R 文件和一个 SAS 文件。没有 ADaM 实体文件时，生成完整 code-only 程序，但 R、SAS 和 collector 均不可执行模型或生成结果。

## 2. 全程约束

1. 保留用户已有未提交改动；每阶段只修改列出的文件。
2. 不读取或迁移 `endpoint-mapping.yaml` 中的值，不从旧 specification、历史程序或 Markdown 猜测统计语义。
3. 不在渲染器中设置统计默认值；统计值只能来自已批准 plan/contract。
4. 每个阶段完成后先运行该阶段定向 self-check，再进入下一阶段。
5. 不先迁移真实 study；先用固定 fixture 证明 schema、renderer、gate 和事务发布正确。
6. R/SAS 任一语言不能表达批准语义时，整套程序不发布。
7. 不创建 git commit，除非用户另外明确要求。
8. 不静默安装 R package；依赖缺失时报告环境问题。
9. 新代码中的错误使用稳定前缀，错误文本说明 analysis ID、字段和修复动作。
10. 所有生成程序采用 UTF-8；生成的 CSV 采用 UTF-8 BOM。

## 3. Phase 0 — 建立基线并解析 R

### 修改文件

无。

### 操作

1. 运行 `git status --short` 并记录已有修改和未跟踪文件。
2. 通过 Windows Start Menu shortcut 解析 R，不假定安装目录：

```powershell
$shortcut = Get-ChildItem "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\R" -Filter "*.lnk" -Recurse | Select-Object -First 1
if (-not $shortcut) { throw "未找到 R Start Menu shortcut。" }
$ws = New-Object -ComObject WScript.Shell
$rTarget = $ws.CreateShortcut($shortcut.FullName).TargetPath
$rscript = Join-Path (Split-Path $rTarget) "Rscript.exe"
if (-not (Test-Path $rscript)) { throw "无法从 R shortcut 解析 Rscript.exe。" }
& $rscript --version
```

3. 运行现有批准链与 standard profile self-check，保存基线结果：

```powershell
$env:MMRM_SKILL_NO_INSTALL = "1"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan_finalization.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_approval_generation.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/R/tests/check_standard_profile.R"
```

### 完成条件

- Rscript 路径已按本机规则解析。
- 已区分既有代码失败与环境依赖失败。
- 没有修改任何文件。

## 4. Phase 1 — 升级 analysis-plan 与 contract dataset schema

### 修改文件

- `.codex/study-mmrm-analysis/R/standard_analysis_definition.R`
- `.codex/study-mmrm-analysis/R/analysis_plan.R`
- `.codex/study-mmrm-analysis/R/analysis_contract_generation.R`
- `.codex/study-mmrm-analysis/R/standard_contract.R`
- `.codex/study-mmrm-analysis/R/runtime_dataset_binding.R`
- `.codex/study-mmrm-analysis/R/review_finalization.R`
- `.codex/study-mmrm-analysis/assets/study-control/analysis-plan-template.yaml`
- `.codex/study-mmrm-analysis/assets/study-control/standard-mmrm-contract-template.yaml`
- `.codex/study-mmrm-analysis/scripts/check_analysis_plan.R`
- `.codex/study-mmrm-analysis/scripts/check_analysis_plan_finalization.R`
- `.codex/study-mmrm-analysis/scripts/check_runtime_dataset_binding.R`

### 4.1 Schema 版本

1. 将 `analysis_plan_schema_version` 从 `2.0` 升至 `2.1`。
2. `execution_context` 增加 required closed field `sas_execution_profile`；首个允许值为 `sas-9.4m5-self-contained/v1`，其 qualification registry 明确最低版本、编码、FCMP/位运算/SHA 和 CSV writer 能力。该值是批准的目标执行环境，不由 renderer 探测或默认。
3. `read_analysis_plan()` 明确拒绝 2.0，并给出迁移消息，不做兼容补值。
4. contract schema 同步升版；plan-contract parity 包含 `dataset.binding_mode` 和 `sas_execution_profile`。

### 4.2 Dataset 校验

把 `standard_validate_dataset()` 改为接收 execution context，并只允许两个 closed shape。

**linked：**

```yaml
binding_mode: linked
file: <nonempty basename>
format: sas7bdat|csv
relative_path: <safe project-relative path>
sha256: <64 hex>
```

校验：

- context 必须 `data_availability: available`；
- basename、extension 和 format 一致；
- path 安全且 basename 与 file 一致；
- SHA 为 64 hex；
- finalization/runtime binding 继续核对 manifest 和实体文件。

**planned：**

```yaml
binding_mode: planned
file: <nonempty basename>
format: sas7bdat|csv
relative_path: null
sha256: null
```

校验：

- context 必须严格为 `none + none + code_generation`；
- basename、extension 和 format 一致；
- relative_path、sha256 必须为 null；
- dataset file/format 仍需要有效 trace；
- planned completeness 使用 closed list：mappings、derivations、filters、groups、endpoint definitions、fixed effects、REML、DF method、covariance primary/fallback、estimands，以及适用时的 reference、comparator、direction、confidence level、multiplicity adjustment 均须完整并有批准 trace；任一缺失都保持 unresolved，不得由 renderer 设置默认值；
- `rds` 以 `PLAN-SCHEMA-DATASET-FORMAT-CROSS-LANGUAGE` 阻断，因为当前 profile 没有自包含 SAS reader。

禁止的组合都使用 `PLAN-SCHEMA-DATASET-BINDING-*` 错误。

### 4.3 Contract 编译与 output schema

1. `compile_analysis_plan_contract()` 逐字复制 dataset 四个值和 `binding_mode`。
2. planned contract 不制造 path 或 hash。
3. parity comparison 必须区分 null 与空字符串。
4. contract catalog 可显示 planned 数据集，但 runtime reader 不得读取它。
5. 在进入 Phase 2 前，每个 analysis 的 `output` 必须已包含并通过 schema/parity 校验：
   - `r_raw_file`、`r_final_file`、`r_diagnostic_file`、`r_run_record_file`；
   - `sas_raw_file`、`sas_final_file`、`sas_diagnostic_file`、`sas_run_record_file`。
6. 八个文件名由 compiler 从安全化 TFL identity 机械生成且两两不覆盖；IR/renderer 只能逐字复制，禁止自行拼接、兼容旧 output shape 或设置 fallback 文件名。
7. approval publication 前执行全局 identity uniqueness gate，分别验证 analysis ID、TFL ID、安全化 program filename、八类 output filename 和 output-directory identity；报告全部冲突并阻断批准。

### 4.4 Runtime 与 finalization gate

1. `runtime_dataset_promote_binding()` 只处理 linked，不把 planned 自动升级。
2. `assert_analysis_execution_allowed()` 在 planned 或 `data_availability:none` 时稳定失败。
3. finalization 允许语义完整的 planned plan 进入审批。
4. 缺 dataset file/format 或变量映射时仍产生 unresolved issue。

### 4.5 Self-check cases

在现有检查脚本中加入：

- valid linked；
- valid planned；
- planned 带假 path/hash；
- linked 缺 path/hash；
- planned + available；
- linked + none；
- 2.0 plan 被明确拒绝；
- planned contract parity；
- planned runtime execution 被阻断；
- `rds` 被跨语言 profile 明确拒绝；
- planned 分别缺 mapping、derivation source、endpoint definition、fixed effect、DF method、covariance、estimand/contrast 参数时都不能 finalize；
- 三类 identity 和八类 output filename 冲突均在 publication 前阻断。

### 验证

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan_finalization.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_runtime_dataset_binding.R"
```

### 完成条件

- planned plan 可以合法批准和编译。
- planned 不含虚假 path/hash。
- linked 保留所有原有实体绑定安全检查。
- runtime 无法执行 planned analysis。

## 5. Phase 2 — 建立程序生成 IR、章节 builder 和 conformance checker

### 新增文件

- `.codex/study-mmrm-analysis/R/program_generation_ir.R`
- `.codex/study-mmrm-analysis/R/program_conformance.R`
- `.codex/study-mmrm-analysis/scripts/check_program_generation_ir.R`

### 修改文件

- `.codex/study-mmrm-analysis/R/standard_analysis_definition.R`

Phase 2–4 只新增纯 IR/renderer/conformance API 和定向 self-check，不改变正式 approval publication 路径。`analysis_approval.R` 的接线、旧 renderer 停用和 target cutover 全部延至 Phase 5；Phase 2–4 不向正式 study 目录发布任何单语言产物。

### 5.1 Normalized IR

实现纯函数：

```r
build_program_generation_ir(contract, analysis, identities)
```

返回 closed object，至少包含：

- study/analysis/TFL/title；
- profile/plan/approval/contract identity；
- execution context 和 dataset binding；
- normalized source-variable inventory；
- ordered derivations、filters、groups、endpoint definitions；
- mappings 和 treatment；
- fixed effects、covariance order、DF method、estimands；
- R/SAS 八个明确 output filenames；
- fixed `sas_execution_profile`（最低 SAS 版本、编码、FCMP/SHA capability 和 qualification status）；
- 固定路径启动接口：`--input-dir`/`--output-dir` > `MMRM_INPUT_DIR`/`MMRM_OUTPUT_DIR` > 文件配置；
- `code_generation_only` 布尔值。

规则：

1. IR 只接收已验证 contract analysis。
2. 保留所有语义序列顺序。
3. 复用 normalized recode/predicate，不重新解释 YAML。
4. 输出所有 string literal 前先通过对应语言 escape checker。
5. 外部 adapter 非 null 时立即失败：`PROGRAM-INLINE-ADAPTER-UNSUPPORTED:<analysis_id>`。
6. IR 不读文件、不执行代码、不写输出。
7. 实现 closed semantic registry：recode、filter、group allocation、baseline、visit、treatment reference、REML、UN/AR1/CS/TOEP、Kenward-Roger、Satterthwaite、LS means、pairwise contrast 各自具有固定 R/SAS implementation key；任一侧缺 key 时错误必须包含 analysis ID、contract 字段路径和缺失语言。
8. comment marker 只证明 coverage，不证明行为；每个 registry operation 后续必须有正向和 mutation/negative fixture。

### 5.2 固定章节 builder

实现：

```r
program_section_titles()
render_r_section_header(number, title)
render_sas_section_header(number, title)
```

`program_section_titles()` 返回固定八章，不接受调用方传入替代标题。

### 5.3 Conformance checker

实现：

```r
validate_generated_r_program(text, ir)
validate_generated_sas_program(text, ir)
validate_tfl_program_coverage(contract, rendered_files)
```

必须检查：

- 八个固定 header/delimiter 逐字匹配、各出现一次且顺序固定；
- UTF-8 可解码，且第 4 部分结尾包含固定数据处理/MMRM 边界注释；
- 每个生成 operation 具有中文 why-comment marker；
- identity 完整，程序 TFL ID 与 contract 精确相同；
- 无 `<...>`、TODO、TBD；
- 无 `.codex`、`source(`、`%include` 或另一个 analysis 文件引用；
- plan 中每项核心语义具有 machine marker；
- linked 包含 file/hash gate；planned 包含永久执行 gate；
- linked SAS input libname 包含 `access=readonly` 且没有写入 INPUT_DIR 的目标；
- linked R package gate 包含 `digest`，并按 format 检查 `haven`、`mmrm`、`emmeans`；
- 全部统计 marker 可追溯到 IR/contract，不存在 renderer fallback/default；
- R/SAS 包含 final CSV write marker；
- SAS 包含 ODS、fallback control 和 convergence gate marker；
- 文件集合严格 N R + N SAS，无遗漏或多余。

不要仅依赖中文文本搜索。renderer 为每项语义写稳定 marker，例如：

```text
PROGRAM-MARKER:DERIVATION:<id>
PROGRAM-MARKER:COVARIANCE:<value>
PROGRAM-MARKER:ESTIMAND:<name>
```

marker 放在注释中，不改变运行行为。

### 验证

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_program_generation_ir.R"
```

### 完成条件

- 同一 contract/analysis 每次产生相同 IR。
- unsupported adapter 在渲染前失败。
- 缺章节、缺 marker、外部依赖和未替换 placeholder 都能被 checker 捕获。

## 6. Phase 3 — 实现逐 TFL 自包含 R renderer

### 新增文件

- `.codex/study-mmrm-analysis/R/self_contained_r.R`
- `.codex/study-mmrm-analysis/scripts/check_self_contained_r_generation.R`

### 修改文件

- `.codex/study-mmrm-analysis/R/dependencies.R`（仅在明确需要记录 `digest` 时）

### 6.1 Renderer API

实现纯函数：

```r
render_self_contained_r_program(contract, analysis, identities)
```

返回一个 length-one UTF-8 string。禁止写文件、读取 ADaM 或调用模型。

### 6.2 八章内容

严格按设计生成：

1. 程序说明与唯一用户配置区；
2. code-only、package、path、output、SHA gate；
3. 单一 format 的数据读取；
4. 完整 derivation/filter/group/allocation/mapping/QC；
5. formula、REML、DF method、covariance fallback；
6. 仅批准 estimands 的 `emmeans`/contrast；
7. observed + inference 最终 table 与 UTF-8 BOM CSV；
8. diagnostics 和 run record。

### 6.3 独立运行要求

生成文本不得：

- `source()` 项目文件；
- 调用 `run_standard_mmrm_analysis()`；
- 调用 `.codex` helper；
- 读取 review、plan 或 contract；
- 不要求 collector 注入统计参数。

所有 helper function 必须内联到该 R 文件，并放入职责对应章节。路径配置采用 Phase 2 固定接口：可选 `--input-dir`/`--output-dir`，其次 `MMRM_INPUT_DIR`/`MMRM_OUTPUT_DIR`，最后第 1 部分 `INPUT_DIR`/`OUTPUT_DIR`；未知参数必须拒绝。standalone 与 collector 使用同一入口，所有其他值均为生成常量。

### 6.4 Planned gate

planned 程序同时包含：

```r
CODE_GENERATION_ONLY <- TRUE
DATA_AVAILABLE <- FALSE
```

第 2 部分首先检查 `CODE_GENERATION_ONLY` 并使用退出码 0 正常结束。程序正文仍完整存在，但不可通过只改 `DATA_AVAILABLE` 执行。

### 6.5 Linked SHA gate

1. `digest::digest(file=..., algo="sha256")`。
2. 以大写比较 expected/actual。
3. 失败消息包含文件、expected、actual。
4. SHA gate 在 `read_sas/read.csv` 之前。

### 6.6 R fixture checks

检查至少：

- randomized linked；
- single-arm linked；
- planned code-only；
- derivation + filter + multiple groups；
- primary + multiple fallback；
- pairwise enabled/disabled；
- unsupported adapter；
- malicious/特殊字符 literal escaping；
- 独立程序 parse：`parse(text=program)`；
- 在 synthetic CSV fixture 上最小独立执行，不接触 `.codex`；
- planned 程序运行后无 TFL/model 文件。

### 验证

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_self_contained_r_generation.R"
```

### 完成条件

- R 文件完整包含八章和所有运行逻辑。
- linked synthetic fixture 能独立生成该 TFL 的输出和诊断。
- planned fixture 正常停止且不生成结果。
- 程序不依赖共享 engine。

## 7. Phase 4 — 实现逐 TFL 自包含 SAS renderer

### 新增文件

- `.codex/study-mmrm-analysis/R/self_contained_sas.R`
- `.codex/study-mmrm-analysis/scripts/check_self_contained_sas_generation.R`
- `.codex/study-mmrm-analysis/assets/golden/self-contained-sas/` 下的确定性 golden files

### 修改文件

- `.codex/study-mmrm-analysis/R/standard_sas.R`（只增加可复用 rendering primitives；不改变正式发布入口）

### 7.1 Renderer API

实现：

```r
render_self_contained_sas_program(contract, analysis, identities)
```

`standard_sas.R` 保留 literal/predicate/recode 等可复用 rendering primitives。Phase 4 不删除、不停用旧 `render_standard_sas_template()`，也不改变正式 approval publication；这些 cutover 动作必须在 Phase 5 同一 transaction change 中完成。

### 7.2 八章与激活 gate

第 1 部分唯一配置：

```sas
%let EXECUTE_APPROVED_PROGRAM=NO;
%let INPUT_DIR=;
%let OUTPUT_DIR=;
```

第 2 部分按顺序检查：

1. 首先检查生成常量 `CODE_GENERATION_ONLY`；若为 YES，输出设计规定的中文说明，设置 `code_generation_only` 状态并通过正常结束路径终止，不使用 `%abort cancel`，不创建任何运行产物；
2. 仅 linked 程序继续检查 `EXECUTE_APPROVED_PROGRAM`；
3. 检查 INPUT/OUTPUT 配置；
4. 检查文件存在；
5. 检查 linked SHA-256；
6. linked 配置、文件或 SHA 安全失败才使用 `%abort cancel`。

planned 程序的 `CODE_GENERATION_ONLY=YES` 是生成常量，不放在用户配置区。fixture 必须分别断言 planned 正常结束和 linked 安全失败。

### 7.3 SAS execution profile 与自包含 SHA-256

1. 在 Phase 1/IR 中使用 closed `sas_execution_profile`，至少声明最低 SAS 版本、编码、FCMP/位运算/SHA 能力和 qualification status；renderer 不探测生成机并猜测目标环境。
2. 先为该 profile 完成独立 feasibility subtask，再实现 linked renderer。
3. 在生成 SAS 内联 `%verify_file_sha256` 和所需 FCMP/data-step helper。
4. 二进制分块读取文件；不得将整个 SAS7BDAT 读成字符。
5. 不依赖 XCMD、PowerShell、Python、外部脚本或站点宏。
6. NIST vectors、binary fixture 和实际文件 hash 必须在声明 profile 的 SAS runtime 上 compile-and-run，并比较 expected/actual；golden 文本只能证明 deterministic rendering。
7. 仓库环境没有 SAS executable 时，可以完成 planned renderer 和 linked 静态开发，但 linked profile 保持 unqualified，不得宣称设计中 SAS SHA、fallback 或 export 已验收。
8. profile 未 qualified 或目标能力不满足时，linked SAS generation 使用 `PROGRAM-SAS-CONFORMANCE-SHA256-UNSUPPORTED` 失败，不降级安全要求。

### 7.4 数据处理和 hard QC gate

内联：

- format-specific input；
- normalized recodes；
- filters；
- group/endpoint allocation；
- group overlap check；
- standardized variables；
- required missing count；
- duplicate subject/group/visit；
- baseline consistency；
- treatment levels。

每个 QC query 写入计数 macro variable。任一错误计数大于 0 时，在 `PROC MIXED` 前统一 `%abort cancel`。

### 7.5 可执行 covariance fallback

实现生成宏 `%run_mmrm_with_fallback`：

1. covariance list 只含批准顺序；
2. 每次运行前清理本次 ODS work datasets；
3. 用 ODS 捕获 `ConvergenceStatus`、LSMeans、Diffs、SolutionF；
4. 一次 attempt 只有在 convergence 成功、没有阻断 warning/error、全部启用 estimand 的 ODS dataset 存在、预期 group/visit/contrast key 完整且唯一、estimate/SE/df/CI/p-value 必需字段完整时才可选定；
5. 满足全部条件时复制 ODS 结果到选定结果集并停止循环；
6. 任一条件失败时记录稳定 failure reason 并尝试下一个批准 covariance；
7. 全部失败设置 `_MMRM_FIT_SUCCESS=0`，只允许写 diagnostic/run record，阻断 raw/final TFL export。

warning 处理使用 closed allow/block 规则表；不得让生成程序通过模糊自由文本自行判断任意日志。

### 7.6 SAS final TFL

1. 将 LSMeans/Diffs 映射成与 R 相同列语义。
2. observed summary 独立生成后合并。
3. 使用固定 decimal/p-value/CI 格式。
4. raw 和 final 文件名逐字来自 contract。
5. 使用规范化 SAS CSV writer 实际写 UTF-8 BOM CSV，明确 BOM bytes `EF BB BF`、delimiter、quote escaping、missing 和 line ending；不保留注释 stub。
6. diagnostics 和 run record 包含 identity、covariance path、QC counts 和状态。
7. 只有实际 SAS runtime fixture 以 binary 断言 BOM 并验证中文、逗号、双引号、换行 round-trip 后，才能把该 execution profile 的 final export 标记 qualified。

### 7.7 SAS validation

没有 SAS runtime 时执行 renderer/golden/conformance validation：

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_self_contained_sas_generation.R"
```

检查：

- 八章、marker、literal escaping；
- planned/linked gates；
- QC hard abort；
- ODS datasets；
- primary/fallback 顺序；
- success break/all-failed gate；
- final `PROC EXPORT` 或 data-step CSV writer；
- 不存在 `%include`、外部命令、template placeholder；
- golden output 完全匹配。

若可获得 SAS runtime，再增加 compile-only 与 synthetic execution，但不把本机不存在 SAS 视为 R renderer 失败。

### 完成条件

- SAS 是完整 `.sas`，不是 template。
- fallback 和 final export 是实际控制流。
- planned 不可执行。
- 无 SAS runtime 时明确标注仅完成静态/golden 验证。

## 8. Phase 5 — 接入 approval transaction 和 program 文件清理

### 修改文件

- `.codex/study-mmrm-analysis/R/analysis_contract_generation.R`
- `.codex/study-mmrm-analysis/R/standard_contract.R`
- `.codex/study-mmrm-analysis/R/analysis_approval.R`
- `.codex/study-mmrm-analysis/scripts/check_analysis_approval_generation.R`

### 8.1 Consume 已完成的 output contract

Phase 5 不再首次改变 output schema。它必须只消费 Phase 1 已验证的八字段 closed shape，并在接线前再次断言八个文件名存在、两两不覆盖且与安全化 TFL identity 一致。任何旧 output shape 直接阻断，不提供 compatibility fallback。

### 8.2 Rendered targets

`analysis_generated_targets()` 返回：

- `analysis/r/<analysis_id>.R`；
- `analysis/sas/<analysis_id>.sas`；
- `analysis/r/run_all_mmrm.R`（正式便利 collector，每次 generation 必须生成）。

不再把 `_template.sas` 作为 current target。

### 8.3 Transaction

`analysis_render_generated()` 对每个 analysis：

1. build IR；
2. render R；
3. validate R；
4. render SAS；
5. validate SAS；
6. 全部 analysis 后 coverage validation；
7. 才把文本交给现有 transaction publisher。

obsolete delete-set 只包括 generator 拥有的程序：

- 当前 analysis 的旧薄 wrapper（由新同名文件原子替换）；
- 所有 `<analysis_id>_template.sas`；
- 已移除 analysis 的 `.R`、`.sas` 和 `_template.sas`。

publisher 先 staging 完整 write-set/delete-set，再在同一 transaction commit；任一 write/delete 失败均恢复上一套完整 generation。approval publisher 不删除 raw/final/diagnostic/run-record/manifest 等 runtime artifacts；这些只能由单独、显式、具有保留策略的归档流程处理。Phase 5 同时停用旧正式 renderer，禁止审批链继续发布 template。

### 8.4 Transaction checks

加入：

- 第一个 renderer 失败；
- 中间 SAS renderer 失败；
- conformance 失败；
- coverage 缺一个文件；
- publication 第 N 个 target 失败；
- obsolete deletion 回滚；
- unsupported adapter 不留下 R-only 文件。

### 验证

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_approval_generation.R"
```

### 完成条件

- 发布永远是完整 N R + N SAS。
- 旧 SAS templates 被事务删除。
- 任意渲染/检查/写入失败都恢复上一套完整产物。

## 9. Phase 6 — 修改 collector、manifest 和内部 engine 文件名

### 修改文件

- `.codex/study-mmrm-analysis/R/templates/run_all_mmrm_template.R`
- `.codex/study-mmrm-analysis/R/standard_engine.R`
- `.codex/study-mmrm-analysis/R/standard_artifacts.R`
- `.codex/study-mmrm-analysis/assets/study-control/tfl-output-manifest.csv`
- `.codex/study-mmrm-analysis/scripts/run_standard_mmrm_stage.R`（若内部 engine 仍用于技术验证）
- `.codex/study-mmrm-analysis/R/tests/check_standard_profile.R`

### 9.1 Collector

生成的 `run_all_mmrm.R`：

1. 不依赖共享 engine；
2. 从 coverage 已验证的一一对应程序集合中，按规范化 R program filename 升序运行；fixture 必须故意让 contract analysis 顺序与文件名顺序不同并断言文件名顺序；
3. 使用 Phase 2/3 固定路径接口传递 INPUT_DIR/OUTPUT_DIR，不重写程序正文，不传统计语义；
4. 单独运行某个 R 文件与 collector 运行该文件得到相同 TFL 内容；
5. 按 analysis 判断 binding mode：planned 只登记 code-only 状态，linked 才调用 R；不得从任一 analysis 推导整个 study 的模式。

### 9.2 Manifest

`tfl-output-manifest.csv` 只有 collector/manifest builder 可以写。单个 R/SAS 程序只写 language-specific、analysis-specific run record，不 append 或修改全局 manifest。collector 提供 `run-and-collect` 与 `collect-only` 两种模式；导入 SAS run record 前必须验证 study/analysis/TFL ID、plan/approval/contract SHA、program SHA、实际 input SHA 和 artifact path。

manifest 增加：

- `programming_language`：`R` / `SAS`；
- `program_file` 和 `program_sha256`；
- `execution_status` closed set：`program_generated_not_executed`、`code_generation_only`、`executed`、`blocked`、`failed`；
- 对应 raw/final/diagnostic/run-record path；
- plan/approval/contract identity 和 actual input SHA。

planned analysis 登记 `code_generation_only`；linked 但尚未运行的 SAS 登记 `program_generated_not_executed`。结果路径只有在文件真实存在且 run-record identity 校验通过后才填写，否则为空。禁止 R/SAS 共享 artifact filename 或 append 同一文件。

### 9.3 Internal engine alignment

共享 `standard_engine.R` 可保留作技术验证，但输出命名必须与新 contract 的 R 字段一致。它不能重新成为生成程序依赖。

### 验证

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/R/tests/check_standard_profile.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_approval_generation.R"
```

### 完成条件

- standalone 与 collector 的单 TFL R 输出一致。
- R/SAS manifest 记录互不覆盖。
- planned collector 不执行分析。

## 10. Phase 7 — 增加端到端固定 fixtures

### 新增文件

- `.codex/study-mmrm-analysis/scripts/check_self_contained_program_generation.R`
- 必要的最小 fixture 放在现有检查脚本创建的临时 study 中；不要提交真实患者级数据。

### 必须覆盖四类主 fixture

#### A. linked

- synthetic CSV；
- randomized treatment；
- recode、filter、two groups；
- UN → AR1 → CS；
- treatment LS means 和 pairwise；
- 生成 N=1 的 R/SAS；
- R 独立执行并产生语言后缀结果；
- 篡改输入后 SHA gate 在读取前失败。

#### B. planned

- null path/hash；
- 其余统计语义完整；
- 批准和生成成功；
- R、SAS 和 collector 都保留完整代码但阻断运行；
- output 无 final/model 文件；
- manifest 为 `code_generation_only`。

#### C. unsupported adapter

- adapter binding 非 null；
- IR build 失败；
- R/SAS 均不发布；
- 上一套程序保持不变。

#### D. tampered input / transaction

- linked SHA 修改；
- contract/program identity 修改；
- 中间 target publication 注入失败；
- 每种情况都 fail closed 且 transaction rollback。

### 额外 fixture

- single-arm；
- no fallback；
- empty derivations/filters；
- character/numeric/logical recode；
- quote、Unicode 和 SAS special literal；
- duplicate safe filenames；
- removed TFL program obsolete cleanup（不得删除 runtime artifacts）；
- N>1 TFL coverage；
- semantic registry 每个 operation 的正向与 mutation/negative case；
- mixed planned/linked analyses 的逐 analysis collector 行为；
- linked SAS unqualified profile 必须阻断，不能被静态 golden 冒充 qualified。

### 验证

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_self_contained_program_generation.R"
```

### 完成条件

- 四类主 fixture 全部通过。
- 不需要真实 ADaM 或患者级数据。
- 失败用稳定错误码，不依赖模糊文本匹配。

## 11. Phase 8 — 更新 workflow 文档和模板

### 修改文件

- `.codex/study-mmrm-analysis/SKILL.md`
- `.codex/study-mmrm-analysis/references/workflow.md`
- `.codex/study-mmrm-analysis/references/rules.md`
- `.codex/study-mmrm-analysis/references/output-docs.md`
- `.codex/study-mmrm-analysis/references/analysis-plan-compilation.md`
- `.codex/study-mmrm-analysis/assets/study-control/analysis-plan-template.yaml`
- `docs/mmrm/guides/study_workflow_CN.md`
- `docs/mmrm/guides/MMRM_data_preparation_guide_CN.md`

### 文档必须明确

1. 一个 TFL 对应一个 R 和一个 SAS。
2. 每个程序八章固定结构。
3. planned 与 linked 的选择规则。
4. 没有 ADaM 时不得填写假 path/hash、不得执行。
5. 数据到达后必须重新编译 plan、finalize、approve-and-generate。
6. 统计师只修改程序第 1 部分用户配置区。
7. R/SAS 输出文件分开。
8. adapter 无法内联时如何回到 analysis plan 表达受支持转换。
9. 禁止从 endpoint mapping 或旧 specification 迁移值。
10. SAS 未在本机执行时，报告只能说“静态/golden 校验通过”。

### 完成条件

- 文档术语与代码字段逐字一致。
- 不再将 SAS 称为 template。
- 不再将薄 wrapper 描述为正式交付程序。

## 12. Phase 9 — 全量回归验证

### 定向检查

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan_finalization.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_runtime_dataset_binding.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_program_generation_ir.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_self_contained_r_generation.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_self_contained_sas_generation.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_approval_generation.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_self_contained_program_generation.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/R/tests/check_standard_profile.R"
```

### 静态检查

1. 对所有修改的 R 文件执行 parse-only。
2. 搜索生成代码中的 `.codex`、`TODO`、`TBD`、`_template.sas` 和 placeholder。
3. `git diff --check`。
4. 复核 `git status --short`，确认未修改用户既有无关文件。

### 成功标准

- 所有 R 定向检查通过；R parse、linked synthetic standalone execution、tampered SHA pre-read failure、planned no-artifact、coverage、identity collision 和 transaction fault injection 均为 release-blocking，不得归类为环境例外。
- 无 parser error、未替换 placeholder 或旧生成路径。
- 生成一张设计第 13 节十二项验收矩阵；每项列出 checker/fixture、运行环境、结果和未验证原因。
- SAS 静态/golden 只证明 deterministic rendering。SHA、QC abort、fallback、推断完整性和 UTF-8 BOM export 只有在声明的 SAS execution profile 上实际运行后才能标记 qualified；没有 SAS runtime 时必须明确记为未验证，不能写“全部验收通过”。

## 13. Phase 10 — 真实 study 迁移（单独批准后执行）

真实 study 迁移不与框架实现混在同一阶段。实施完成并通过 Phase 9 后，再选择 study 迁移。

对 `studies/fcn_159_002_kiro`：

1. 现有 `endpoint-mapping.yaml` 只作历史审计，不读取其值。
2. 从当前已登记 source evidence、统计师 review decisions 和 schema 2.1 null template 重新编译 `analysis-plan.yaml`。
3. 数据文件确实存在且 SHA 已登记时使用 linked；否则使用 planned。
4. unresolved 字段由统计师确认，不由 agent 猜测。
5. 重新 finalization。
6. 重新批准并事务生成每 TFL R/SAS。
7. 对每个 analysis 单独判断：linked 可执行 R，planned 只检查程序生成；同一 study 可混合两种 binding mode。
8. SAS 由统计师在 SAS 环境核对路径并显式激活。

### 迁移完成条件

- study 中每个已批准 TFL 有一份 `.R` 和一份 `.sas`。
- 不存在 current `_template.sas`。
- 每份程序八章完整且不引用 `.codex`。
- planned/linked 行为与该 study 的实际数据状态一致。

## 14. 最终交付清单

实施者结束前必须报告：

- 修改/新增文件清单；
- plan/contract schema 版本；
- 生成的 R/SAS 文件命名规则；
- linked/planned 行为；
- R self-check 结果；
- SAS 验证级别：实际运行或仅静态/golden；
- 未验证项；
- 真实 study 是否迁移；
- 工作区中保留的用户既有未提交改动。
