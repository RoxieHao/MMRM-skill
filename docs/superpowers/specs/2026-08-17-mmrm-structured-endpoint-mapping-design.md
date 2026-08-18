# MMRM 结构化 Endpoint Mapping 与事务化定稿设计

日期：2026-08-17  
状态：已确认，实施中  
范围：`.codex/study-mmrm-analysis` 初始化至 Section 4 的共享流程。不会自动迁移、运行或修改任何既有 study。

## 决策

`statistician-review/endpoint-mapping.yaml` 是每个 study 唯一机器可执行的 Section 4 来源。`statistical-review.md` 保持为统计师可读、可签核的审阅记录；其 Section 4 是 YAML 的只读渲染摘要，而非机器规则的解析来源。

统计师确认业务字段，不手工复制 SHA。finalizer 在验证全部通过后自动计算 mapping SHA-256，回填 review metadata，并由 specification/contract/runtime gate 验证。mapping 任何后续变动都会导致 SHA 不一致并阻断后续生成或运行。

## Mapping schema

YAML 为每个 mapping row 显式声明：

- `analysis_id`、`source_tfl_id`、`group_id`、`endpoint_label`；
- `endpoint_variable`、`selected_codes`、`selection_mode`；
- `dimensions`、`row_allocation_rule`、`source_ref`；
- `review_status`、`reviewer_note`。

共享 Skill 仅检查 schema、标识唯一性、Section 3/4 TFL 双向覆盖、运行数据 binding、contract parity 和 SHA；不再根据 TFL 编号、标题、PedsQL、PARAMCD 或其它 study 词汇推断 endpoint 规则。

## 受控工作流

```text
intake review + Section 3 候选
  -> 统计师确认 Section 3 binding 与 study-local endpoint-mapping.yaml
  -> finalizer 预校验（内存中）
  -> 合并 Section 3 与 mapping issues
  -> 全部通过时自动计算 YAML SHA，原子发布 manifest + YAML + review
  -> Section 4 Markdown 从 YAML 只读渲染
  -> specification / contract 绑定 mapping YAML 的 SHA
```

初始化将 route 写入 `backup-trace/study-control.yaml`。当 filled/formal review 共存时，finalizer 必须显式指定 `--source-review`；不再猜测。

## 失败、Issue 与无副作用要求

任何 unresolved issue 或 strict (`allow_unresolved=false`) finalization 失败时，finalizer 必须输出逐条报告，每项含：

- 稳定 issue ID 与 scope（TFL ID 或 mapping row identity）；
- 失败字段和来源位置；
- 检测到的值或状态；
- 验证规则、期望修复动作；
- 是否阻断发布。

报告以可读 console 文本和结构化结果返回。严格失败前不得修改 manifest、正式 review 或 mapping YAML；目标文件已存在时其内容和 SHA 也必须保持不变。只有所有 gate 通过时才一次性发布并把 manifest 已确认 binding 提升为 `linked_source`。

## Markdown 边界

所有仍需读取的受限 Markdown 表使用一个共享 codec：只支持单行 pipe table、正确处理 `\|`、拒绝未闭合转义、错误表头、分隔行或列数。自由文本和 Endpoint Mapping 业务语义不再由 Markdown parser 推断。

## 验收

仅使用创建后删除的合成 fixture：

1. escaped pipe 可以回读；歧义/格式错误表 fail closed；
2. 任意 TFL ID 可由显式 YAML mapping 使用，无共享前缀规则；
3. 缺 mapping、重复 identity、TFL 覆盖不全、SHA 改动和 schema 不符都产生详细 issue；
4. strict finalization 失败前后 manifest/review/mapping SHA 完全一致；
5. 成功时 mapping SHA 自动回填，Section 4 是 YAML 渲染，contract 使用已确认的精确 runtime binding；
6. 不读取、运行或修改 Kimi study。
