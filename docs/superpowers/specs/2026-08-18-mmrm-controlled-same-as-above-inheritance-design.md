# MMRM Statistical Review “同上表”受控继承设计

日期：2026-08-18  
状态：已获设计确认，待文档审阅后实现  
范围：`.codex/study-mmrm-analysis` 的 Section 3 statistical review finalization 预处理和相关合成检查；不自动修改任何 study 的统计规则或 endpoint mapping。

## 背景

当前 pending statistical review 的 Section 3 对每个 TFL 固定记录十类规则。统计师可在“统计师备注或修订值”填写 `同上表`，其语义是：该 TFL 的该规则类别与先前表格中已明确写出的规则一致。

现有 finalizer 要求每条规则为“采用”或“修改”且有非空、明确备注，并明确禁止“同上”或跨 TFL 继承。因此，即使统计师已用 `同上表` 表达确认意图，finalization 仍会失败。将 `同上表` 原样放入最终 review 也会让数据集绑定和人群 DSL 等机器消费字段不可执行。

## 目标与原则

1. 将统计师精确填写的 `同上表` 解释为受控、可追溯的跨 TFL 引用，而不是自由文本猜测。
2. 在 Section 3 的 TFL 顺序中，按**同一规则类别**向前回溯，直到找到最近一个明确备注；允许跳过中间的空值或 `同上表`。
3. 在最终定稿前将引用展开为明确文本，使最终 review 独立可解析、可审计。
4. 继承不削弱既有 finalization gate：每条规则仍必须选择“采用”或“修改”；数据集绑定、人口 DSL、endpoint mapping 和原子发布规则保持严格。
5. 不从 AI 候选、TFL 标题、endpoint mapping、统计语义或数据内容推测缺失规则；找不到明确来源时 fail closed。

## 受控回溯规则

### 触发条件

仅当“统计师备注或修订值”经 `trimws()` 后**完全等于** `同上表` 时启用继承。`同上`、`同上表。`、`同上表（确认）` 或任何其他自由文本均不是继承标记，继续按现有明确备注逻辑处理。

### 解析算法

对 Section 3 中每个 TFL、每个固定规则类别，按 review 中的表格顺序处理：

1. 读取当前行决定与备注。
2. 若备注不是精确 `同上表`，将其作为该类别可被后续表引用的明确值（前提是非空且本身不是继承标记）。
3. 若备注为 `同上表`，从当前 TFL 的前一张表开始向上遍历，始终匹配相同“规则类别”。
4. 跳过没有该类别明确备注、备注为空或备注仍为 `同上表` 的前表；不因其决定是“待确认”而停止回溯。
5. 找到最近明确备注时，用该备注替换当前 TFL 的工作副本备注，并记录其来源 TFL ID 和规则类别。
6. 回溯到最早表仍找不到明确备注时，为当前 TFL/规则类别产生 unresolved issue，要求填写可执行的明确规则；finalization 不发布。

回溯仅查找已经出现的表，因此不会形成循环。继承只复制统计师备注文本，不复制 AI 候选、决策、Profile 评估、endpoint mapping 行或运行期数据绑定对象。

### 决策与现有校验

无论备注是否通过继承获得，当前 TFL 每一行仍必须将“统计师决定”设置为 `采用` 或 `修改`。`待确认` 或 `拒绝` 仍为 finalization blocking issue。

继承解析在现有“决定有效、备注非空”检查之前运行。展开后继续沿用既有校验：

- “分析数据集”必须通过唯一 runtime dataset binding 解析；
- “分析人群”必须通过 population DSL 解析；
- 其他规则继续由既有 review 结构和后续 contract 流程消费；
- `endpoint-mapping.yaml` 继续要求每个 Section 3 TFL 有自己的显式、完整 mapping 覆盖。不会从前表自动复制 endpoint code、分组、endpoint variable 或行分配规则。

## 审计与最终文档

成功解析的继承将在该行“证据来源与识别状态”追加非机器消费的审计描述，例如：

```text
统计师确认：备注继承自 TFL 14.2.10.1.1 / 分析人群。
```

“统计师备注或修订值”保留纯粹的展开后规则文本，确保数据集和人口规则解析器不会读取审计附言。finalizer 重渲染 Section 3 后，最终文档不再含有 `同上表`；每个规则都成为独立的明确值。

Section 3 的引导语将改为：规则均须显式处置；`同上表` 只可引用前序 TFL 中同一规则类别的最近明确备注，且 finalization 会将其展开为明确值。

## 组件边界

| 组件 | 负责 | 不负责 |
|---|---|---|
| `review_finalization.R` | 解析精确继承标记、向前回溯、替换工作备注、生成继承缺失 issue、写入审计证据 | 推测临床/统计规则或生成 endpoint mapping |
| review Markdown parser | 保持既有固定表格 schema 与严格表格结构 | 容忍额外 Markdown 表或模糊继承语法 |
| runtime dataset binding | 验证展开后的数据集确认值 | 从前表候选或文件名猜测绑定 |
| population DSL | 验证展开后的人群规则 | 解释自然语言人群描述 |
| endpoint mapping validator | 继续验证每个 TFL 的显式 mapping | 继承或自动生成 mapping 行 |

## 错误处理

- 首张表使用 `同上表`：无前序明确值，产生 unresolved issue。
- 多张连续表使用 `同上表`：向前跨过所有中间引用，继承最近明确值；若无明确值则阻断。
- 找到的值无法通过数据集绑定或人口 DSL：继续由既有校验阻断，不回退到更早的不同值。
- 决定为“待确认”或“拒绝”：即使继承已解析，仍由既有决定校验阻断。
- 额外或格式损坏的 Markdown 表格：继续由既有严格 parser 拒绝；本设计不扩大 Markdown 语法。
- 无任何 unresolved issue 前，不写入 final review、manifest 或 mapping；继续使用原子发布/回滚逻辑。

## 验收与验证

扩展现有 `scripts/check_structured_endpoint_mapping.R` 的临时合成 study 检查：

1. 正例：第一张 TFL 对某类别填入明确值；第二张和第三张都填写 `同上表`。finalization 成功时，两者在输出中均展开为第一张的明确文本，并记录正确来源。
2. 链式回溯正例：第二张和第三张表的同一类别均填写 `同上表`，第三张仍找到第一张表的最近明确值。另验证中间表即使决定为“待确认”也不会中止第三张表的向前查找，但该中间表仍会因其自身未处置决定而由既有 gate 阻断发布。
3. 缺失来源：首张表或所有前表均无明确值时，生成有 scope、field、observed、requirement 和 resolution 的 unresolved issue；不得发布、不得更新 manifest。
4. 精确匹配：`同上`、`同上表。`、`同上表（确认）` 不触发继承。
5. 决策 gate：继承后的备注不允许绕过“采用/修改”要求。
6. 数据集和人口规则：继承后的数据集仍经过 binding 解析，继承后的人群仍经过 DSL 解析；无效值 fail closed。
7. mapping 不变：有效继承不放宽每个 TFL 的显式 endpoint mapping 覆盖、唯一性及原子发布断言。

验证仅使用临时合成 study，不运行或改写 `studies/fcn_159_002_kiro` 的 review、mapping、manifest 或任何数据文件。

## 非目标

- 不将“同上表”自动改写到用户当前 review 中。
- 不自动将“待确认”转换为“采用”或“修改”。
- 不从备注自动补全 `endpoint-mapping.yaml`。
- 不支持模糊同义表达或带注释的 `同上表`。
- 不运行、拟合或发布 MMRM 分析结果。
