# MMRM 审批前 Runtime Dataset Binding 设计

日期：2026-08-17  
状态：已获设计确认，待文档审阅后实现  
范围：`.codex/study-mmrm-analysis` 的 intake、统计师 review、finalization、analysis contract 与运行期来源解析；不运行或修改任何既有 Kimi study。

## 背景

当前 contract generator 会将 review 中的逻辑数据集标识（例如 `ADQSSUM`）机械转换为 `ADQSSUM.csv`。真实运行输入可以是 `input/adam/adqssum.sas7bdat`，并且 manifest 仅将其登记为 `registered_input`。运行器要求 contract 文件名存在唯一 `linked_source` manifest 行，因此已批准 specification 无法安全运行。审批后补写 manifest 会改变 `source_input_sha256`，使批准失效。

## 目标与原则

1. 在批准前，从已审计的 `input/` 文件发现可运行的 `csv`、`sas7bdat`、`rds` 候选；不转换格式。
2. 统计师确认分析使用的精确候选，而不是手工编辑 manifest。
3. finalizer 仅在通过全部 review gate 后，将已选择的既有 manifest 行原地提升为 `linked_source`，并以实时 SHA-256 验证其未变。
4. contract 保留确认后的真实 `file_name`、format、relative path 与 SHA-256；运行期再次验证 contract、manifest 与实体文件三者一致。
5. 任意未确认、多个合理候选、重复 manifest 记录、文件缺失或 hash 不一致均 fail closed；AI 不自动选择来源。

同一个已确认 source 可服务多个 TFL；不因 TFL 数量复制 manifest 行。

## 受控数据流

```text
input/ 实体文件
  -> intake manifest（registered_input，实际路径/格式/SHA）
  -> runtime candidate catalog（schema/PARAMCD 仅作审阅证据）
  -> Section 3 候选行 + 统计师确认
  -> finalizer（重算 SHA、原地提升为 linked_source）
  -> approved specification source_input_sha256
  -> contract dataset binding（file/format/relative_path/sha256）
  -> runtime resolver（三方 SHA 与格式校验后读取）
```

### 1. 候选目录

新增 manifest-backed catalog。它只读取当前 `input/` 下已有、支持格式且状态为 `registered_input` 或已确认 `linked_source` 的唯一 manifest 行，输出：

- `file_name`（真实 basename，例如 `adqssum.sas7bdat`）；
- `format`（`csv`、`sas7bdat`、`rds`）；
- `relative_path` 与 SHA-256；
- 可读时的变量名、`PARAMCD` 值摘要和读取错误。

catalog 绝不通过 stem、最高分或 `which.max()` 静默选源。相同逻辑 dataset 名匹配到多个文件、同分候选或缺少可读 schema 时均显示为歧义/阻断。

### 2. Review 确认

Section 3 的“分析数据集”候选行展示完整绑定，例如：

```text
候选：adqssum.sas7bdat | format=sas7bdat | path=input/adam/adqssum.sas7bdat | sha256=<64位>
```

统计师可：

- 对唯一候选填写 `确认`；或
- 在有多个候选时填写完整精确 `file_name`，选择其中一个展示的候选。

不得接受裸逻辑名（如 `adqssum`）、猜测扩展名或自由文本路径。确认文本解析后保存完整 binding，而不是仅保存 dataset identity。候选未处理、确认无效或候选歧义均阻断 approval。

### 3. Finalizer 与 manifest 同步

finalizer 将确认的 binding 与 manifest 精确比对（relative path、basename、format、SHA），重新计算实体 SHA，并只将匹配的现有行 `status` 由 `registered_input` 改为 `linked_source`。它不新增重复行，不修改未选择行，也不接受缺失或变化的文件。

`intake_sync_input_manifest()` 必须保留 `input/` 内的已确认 `linked_source` 行，并对该行继续执行存在性和 hash 完整性检查；不得因同步重建出一条相同路径的 `registered_input` 行。每个 `relative_path` 仅允许一行。

提升在 finalizer 构造并签核 approved specification 之前发生，因此 manifest 的新 SHA 会被批准时的 `source_input_sha256` 正确锁定。批准后输入变更仍使校验失败，必须重新走 review 与批准。

### 4. Contract 与运行期

每个 contract `dataset` 改为包含：

```yaml
dataset:
  file: adqssum.sas7bdat
  format: sas7bdat
  relative_path: input/adam/adqssum.sas7bdat
  sha256: <64位小写十六进制>
```

contract generator 只消费 review-finalized binding，删除 `.csv` 拼接逻辑。schema 校验 file 扩展名、format 和 hash 语法及其一致性。

运行器以 `relative_path` 与 `file` 定位唯一 `linked_source`，核验 manifest SHA、重新计算实体 SHA、contract SHA 与 format/extension 一致后，使用既有对应读取器读取。旧 contract 缺少 binding 字段时 fail closed，不尝试通过逻辑名回退。

## 组件边界

| 组件 | 负责 | 不负责 |
|---|---|---|
| intake/manifest | 登记输入、维护唯一行、hash 完整性 | 选择分析数据集 |
| candidate catalog / enrichment | 展示真实格式与可读 schema 证据、报告歧义 | 自动确认来源 |
| review parser | 仅解析受限确认语法 | 写 manifest 或猜测文件 |
| finalizer | 验证并原地提升被确认行 | 批准未确认/歧义来源 |
| contract generator | 序列化已确认 binding | 从逻辑 dataset 名构造文件名 |
| runtime resolver | 校验三方 binding 并读取 | 修复或替换已批准来源 |

## 错误处理与审计

- 支持格式外、读取失败、文件缺失、SHA 变化、重复相对路径、找不到精确 source 或多个 `linked_source`：阻断并给出路径/字段原因。
- 同 stem 的 `.csv` 与 `.sas7bdat` 同时存在时，必须由统计师明确选择完整文件名。
- 统计师只在 review 表中工作；manifest 变更由 finalizer 可审计地完成。
- manifest 与 approved specification 为输入审计产物，保留；运行期临时 schema 扫描文件沿用既有临时清理规则，不进入 study 交付物。

## 验收与验证

仅创建并清理临时合成 study，绝不运行或修改 Kimi study：

1. 唯一 `sas7bdat` 候选在 `确认` 后被原地提升，contract 保留其真实文件名、格式、路径和 SHA。
2. 同 stem 多格式或等价候选时 finalizer 阻断；精确完整 `file_name` 确认后才可通过。
3. CSV 和 RDS 同样可形成受控 binding；unsupported 格式被拒绝。
4. 实体文件或 manifest 在确认后变更时，finalizer/运行期均拒绝。
5. 重复 manifest 行、缺失 linked source、contract/manifest format 不一致均拒绝。
6. 扩展现有 profile/self-check，仅检查临时夹具；验证结束删除其全部临时产物。

## 非目标

- 不自动把 SAS 数据转为 CSV。
- 不让 AI 代替统计师选择有歧义的运行数据。
- 不允许批准后补写或修复 linked source。
- 不运行、重新批准或更改用户的 Kimi study。
