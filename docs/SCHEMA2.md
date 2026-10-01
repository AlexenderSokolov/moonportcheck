# Schema 2：详细报告与消费迁移

本文对应 `0.2.0-dev` 的 M04/M06/M07/M08/M09/M10/M11 详细诊断接口。源码处于开发阶段，尚未正式发布。M04 增加来源证据与独立扫描问题；M06 增加配置化排除与目录剪枝，并接入 `scope`、`excluded_entries`、`pruned_directories` 字段；M07 增加快照模型、解析与序列化（独立文档格式见下文「快照文档」）；M08 增加 `snapshot` 命令并使 `check` 接受快照；M09 增加快照差异核心与报告；M10 增加 `diff` 命令与退出语义；M11 增加基线模型与分类核心（独立文档格式见下）。SARIF 和 Markdown 报告与 `baseline`/`scan --baseline` 命令属于后续里程碑，不能由本文推断它们已经可用。

## 选择需要的接口

| 消费入口 | 当前输出 | 迁移要求 |
| --- | --- | --- |
| 原库 `audit` → `render_json` / `render_text` | 原 `Report`，JSON 保持 schema 1 | 无需修改已有代码 |
| 新库 `audit_with_options` → `render_detailed_json` / `render_detailed_text` | `DetailedReport`，JSON 为 schema 2 | 显式选择新接口 |
| CLI `scan` / `check` | schema 2 审计报告 | 按本文迁移报告读取逻辑 |
| CLI 参数、输入或 I/O 错误 | schema 2 错误响应 | 先识别 `error`，不作为审计报告读取 |
| CLI `rules` / `explain` 成功查询 | 原有规则 JSON 数组 | 不增加报告外壳或 `schema_version` |

`PathEntry`、`Report`、`parse_manifest`、`audit`、`render_json` 和 `render_text` 保持 v1 接口与行为。`parse_manifest` 仍读取原来的 JSON 条目数组，不因本次更新接受其他输入格式。

CLI 没有 `--schema 1` 切换参数。机器消费者应显式检查 `schema_version` 并选择对应解析逻辑，拒绝不支持的版本；需要继续生成 schema 1 时调用原库接口。不要仅凭出现 `diagnostics` 就把任意版本当作同一种报告。

新增库入口：

| API | 用途 |
| --- | --- |
| `AuditOptions` | 不透明设置类型，调用方不能直接构造内部字段 |
| `default_audit_options()` | 创建当前默认设置 |
| `audit_with_options(entries, options)` | 生成详细审计报告 |
| `DetailedReport` / `DetailedDiagnostic` / `SourceMember` | 详细报告、诊断组与原始来源成员 |
| `ScanIssue` | `code`、`path`、`message` 组成的扫描问题 |
| `with_scan_issues(report, issues)` | 将扫描问题附入详细报告，标记扫描来源和完整性 |
| `render_detailed_json(report)` / `render_detailed_text(report)` | 渲染详细报告 |

这些库函数仍不访问文件系统。文件系统适配层提供条目和扫描问题，MoonBit 汇总最终报告与结论。

## 报告外层保持平面结构

schema 2 保留 `profile`、`source`、`complete`、`summary`、`diagnostics` 和 `limitations` 等原字段，不把原报告嵌套到 `report` 或 `data` 中。

| 字段 | 类型与语义 | M04 当前值或行为 |
| --- | --- | --- |
| `schema_version` | 整数，报告协议版本 | `2` |
| `profile` | 规则配置身份 | `portable-windows-v1` |
| `source` | `manifest` 或 `scan` | 按输入来源设置 |
| `complete` | 本次所声明范围内的检查是否完整 | 扫描问题导致 `false` |
| `summary.entries/files/directories` | 接受检查的输入条目统计 | 保留原条目计数语义 |
| `summary.diagnostic_groups` | 路径规则诊断组数量 | 只计 `diagnostics` |
| `summary.scan_issues` | 扫描问题数量 | 只计外层 `scan_issues` |
| `diagnostics` | `DetailedDiagnostic` 数组 | 只包含路径规则问题 |
| `scan_issues` | `{code, path, message}` 数组 | 扫描完整性问题独立存放，清单检查为 `[]` |
| `scope` | 规范化后的有效排除模式数组 | M06：配置与命令行排除的并集，去重后按 ordinal 排序 |
| `excluded_entries` | 已知被排除的条目数 | M06：只统计已知输入中实际被排除的条目 |
| `pruned_directories` | 实际剪枝的相对目录路径数组 | M06：被整棵排除的最顶层目录，按 ordinal 排序 |
| `limitations` | 覆盖限制字符串数组 | 保留覆盖边界说明 |

`scope`、`excluded_entries`、`pruned_directories` 从 schema 2 起始终存在，使报告能够完整表达检查范围。空范围表示没有配置排除，不表示默认忽略 `.git` 或隐藏目录。`excluded_entries` 只统计已知输入中实际匹配排除的条目：当整棵目录在扫描时被剪枝、未枚举其内部条目时，该数少于清单等价输入下的值，这是文档规定的「不估算未遍历子树」定义，不能据此推断文件数。`pruned_directories` 只报告**最顶层**被剪枝目录（其祖先未被整棵排除），保证扫描与等价清单在相同排除下得到相同结论。

扫描问题不再混入 `diagnostics`。例如跳过链接会出现在 `scan_issues` 中，令 `complete=false`；即使没有任何路径诊断，CLI 也必须退出 `3`。同时存在路径问题和扫描问题时，两者均保留，`3` 优先于 `1`。

## 排除配置与剪枝（M06）

`check` 与 `scan` 接受 `--exclude PATTERN`（可重复）与可选 `--config FILE`。配置文件是版本化 JSON：`{"schema_version":1,"exclude":["模式", ...]}`，`schema_version` 必填且必须为 `1`，`exclude` 可选、缺省为 `[]`。配置与命令行排除取并集，按原始拼写去重后按 ordinal 排序，即报告中的 `scope`。未指定任何排除时 `scope` 为 `[]`，与 M04 的默认报告一致。**绝不**隐式读取 `.gitignore` 或任何其他文件。

排除模式语法沿用 PATTERNS 文档（M05 匹配器）。排除语义：

- 被排除条目不进入审计、不产生诊断，也不计入 `summary.entries`，但计入 `excluded_entries`。
- 匹配真实或隐含目录的排除会排除整个子树；`pruned_directories` 只列出**最顶层**被剪枝目录（祖先未被整棵排除者），因此扫描与等价清单在相同排除下得到相同的 `scope`、诊断、`summary` 与 `pruned_directories`。
- 结构非法的路径永远不会被排除（匹配器对路径做结构校验），相关诊断仍产生。
- 排除只影响条目范围，不豁免扫描完整性问题：扫描不完整时 `complete=false` 且退出 `3`。

配置错误按输入错误退出 `2`：非法 JSON、非对象、缺少或错误的 `schema_version`、未知字段统一为 `INPUT_CONFIG`；配置/命令行中的非法模式报 `PATTERN_INVALID` 并指出具体问题（可能由同一个错误响应携带）。配置文件无法读取或不是有效 UTF-8 时分别报 `INPUT_IO_ERROR`（退出 `3`）与 `INPUT_ENCODING`（退出 `2`），与清单文件的处理一致，错误消息不包含主机绝对路径。

## 详细诊断与来源计数

每组详细诊断保留 v1 的 `code`、`severity`、`paths`、`occurrences`、`message`，并增加：

| 字段 | 语义 |
| --- | --- |
| `anchor` | 诊断组定位路径；大小写／类型冲突采用 ASCII 折叠后的路径前缀，其他规则采用原始路径 |
| `group_key` | 对 `[code, anchor]` 做 JSON 序列化后得到的**字符串** |
| `members` | 所有实际输入来源，按原始 `(path, kind)` 分组，每项为 `{path, kind, count}` |
| `source_examples` | 最多 5 个来源成员；冲突组优先展示两侧证据 |
| `source_total` | 不同来源成员的数量，即 `members.length` |
| `sources_truncated` | 是否存在未出现在 `source_examples` 中的来源成员 |

成员的 `kind` 是实际输入的 `file` 或 `directory`，`count` 是该路径与类型在输入中的次数。隐含目录参与判断，但不会被伪造成来源成员。例如输入文件 `artifact` 和 `artifact/report.txt` 产生类型冲突时，两个成员的类型都为 `file`；第二个实际文件说明 `artifact` 同时必须是目录。

`occurrences` **保持 v1 含义**，不能改读为原始来源总数。它与 `members.length`、所有 `count` 的总和可能不同。例如输入为文件 `artifact` 一次、文件 `artifact/report.txt` 两次，其类型冲突诊断组如下；这是字段含义示例，不是验收结果记录：

```json
{
  "code": "PATH_KIND_CONFLICT",
  "severity": "error",
  "paths": ["artifact"],
  "occurrences": 1,
  "message": "A folded path denotes both a file and a directory.",
  "anchor": "artifact",
  "group_key": "[\"PATH_KIND_CONFLICT\",\"artifact\"]",
  "members": [
    { "path": "artifact", "kind": "file", "count": 1 },
    { "path": "artifact/report.txt", "kind": "file", "count": 2 }
  ],
  "source_examples": [
    { "path": "artifact", "kind": "file", "count": 1 },
    { "path": "artifact/report.txt", "kind": "file", "count": 2 }
  ],
  "source_total": 2,
  "sources_truncated": false
}
```

上例只有两个不同成员，但代表三次原始输入；类型冲突的 `occurrences` 仍是 `1`。同一批输入还会产生另一个 `PATH_DUPLICATE` 组，其重复次数按照旧规则计算。

`source_examples` 为阅读服务，不能充当诊断身份或完整证据。即使样例被截断，`members` 仍全量保留。后续基线功能会使用组身份和完整成员计数；M04 本身尚未提供基线创建或比较命令。

## 快照文档（M07）

快照是持久化的扫描状态，供后续 `check` 快照支持（M08）与 `diff`（M09）使用；`parse_manifest` 保持只解析原数组清单。快照是独立文档，不是审计报告：固定外层 `{"format":"moonportcheck-snapshot","version":1,...}`，字段顺序固定：

```json
{
  "format": "moonportcheck-snapshot",
  "version": 1,
  "profile": "portable-windows-v1",
  "complete": true,
  "scope": [],
  "entries": [
    { "path": "目录/a.txt", "kind": "file" },
    { "path": "数据", "kind": "directory" }
  ],
  "scan_issues": []
}
```

- `entries` 为按 `(path, kind)` 排序且路径唯一的条目；`kind` 只能是 `file` 或 `directory`。快照绝不保存文件内容、时间戳或主机绝对路径。
- `scope` 为规范化后的有效排除模式（ordinal 排序、去重）。`complete` 表示来源扫描是否完整（有 `scan_issues` 即不完整）。`scan_issues` 为 `{code, path, message}` 数组。
- `build_snapshot(entries, scan_issues, scope)` 构建并规范化：重复相同条目折叠、同一路径出现 `file` 与 `directory` 两种类型时报 `INPUT_SCHEMA`、非法排除模式报 `PATTERN_INVALID`、无扫描问题时 `complete=true`。
- `parse_snapshot(text)` 只接受规范文档：`format`/`version` 必须匹配、仅允许已知字段、`entries` 必须严格递增且唯一、`scope` 必须是字符串数组、`scan_issues` 必须结构正确。损坏或非规范输入一律拒绝（`INPUT_SCHEMA` / `PATTERN_INVALID`）。
- `render_snapshot_json(snapshot)` 以固定字段顺序确定性输出；`render_snapshot_json(parse_snapshot(render_snapshot_json(s)))` 与输入逐字节一致（往返一致、排序稳定）。
- 快照命令与 `check` 快照支持在 M08 交付；本里程碑只提供模型、解析与序列化。

## 快照命令与快照检查（M08）

`moonportcheck snapshot ROOT [--config FILE] [--exclude PATTERN]...` 扫描真实目录并把 `build_snapshot` 的结果以快照文档形式写到 stdout（固定 JSON，不接受 `--format`）：完整快照导出退出 `0`，扫描不完整退出 `3`，输入/模式错误退出 `2`。快照保存被枚举到的全部条目（含被排除文件；被整棵剪枝目录只保存目录本身）；检查快照时才应用排除。

`moonportcheck check MANIFEST` 现在同时接受原数组清单与快照文档，按顶层 JSON 值分类：数组走原 `parse_manifest` 路径；对象解析为快照后经 `audit_snapshot` 检查。检查快照时：

- 报告 `source` 为 `"snapshot"`，`scope` 继承快照范围；`--config`/`--exclude` 的额外排除只能**缩小**被检查集合（并集去重后按 ordinal 排序）。
- 快照存储的 `scan_issues` 原样带入，因此**不完整快照始终不完整**（`complete=false`，退出 `3`）；`summary.scan_issues` 与 `scan_issues` 据此取值。
- `complete`/`source` 之外的字段（`schema_version`、`profile`、`summary`、`diagnostics`、`excluded_entries`、`pruned_directories`）语义与其他来源一致。
- `profile` 与当前激活配置不一致的快照被拒绝（`INPUT_SCHEMA`，退出 `2`）。

## 快照差异文档（M09）

`diff_snapshots` 比较两份范围完全相同的快照，输出固定文档：

```json
{
  "format": "moonportcheck-diff",
  "version": 1,
  "complete": true,
  "changes": [
    { "kind": "added",  "path": "new.tmp", "paired_with": "", "before_kind": "", "after_kind": "file" },
    { "kind": "kind",   "path": "C.txt",   "paired_with": "", "before_kind": "file", "after_kind": "directory" },
    { "kind": "case",   "path": "A.txt",   "paired_with": "a.txt", "before_kind": "file", "after_kind": "file" }
  ]
}
```

- 先按原始路径精确匹配：同一路径类型改变记为 `kind`；未被精确匹配的条目再按 ASCII 折叠比较，只有**一对一且类型相同**的折叠才记为 `case`（`paired_with` 记录折叠前的路径），不推测一般重命名或内容变化。
- 变化排序固定：`added`、`removed`、`kind`、`case`，同组内按路径 ordinal。
- 两份快照范围必须逐项相同，否则 `INPUT_SCHEMA`（CLI 侧退出 `2`）。`complete` 为两份输入的完整度取与；`diff` 命令在不完整输入时退出 `3`。M09 提供核心与渲染；M10 提供 `diff` 桥接模式与 CLI `moonportcheck diff BEFORE.json AFTER.json [--format text|json]`。

`diff` 的退出码：范围不同或文档损坏退出 `2`、任一输入不完整退出 `3`、有变化退出 `1`、无变化退出 `0`。text 输出在前一行标注 `INCOMPLETE` 提示（不完整时），每行形如 `+ new.tmp (added, file)` / `- old.txt (removed, file)` / `~ C.txt (kind, file -> directory)` / `~ A.txt (case, a.txt -> A.txt)`。

## 基线文档与分类（M11）

`baseline`（M12 提供 CLI）从完整的 schema 2 审计报告创建固定 JSON 文档，绑定 profile、规则版本与有效检查范围：

```json
{
  "format": "moonportcheck-baseline",
  "schema_version": 1,
  "profile": "portable-windows-v1",
  "rules_version": "1",
  "scope": ["*.tmp"],
  "groups": [
    { "code": "NAME_RESERVED", "anchor": "a/CON.txt", "members": [{ "path": "a/CON.txt", "kind": "file", "count": 1 }], "source_total": 1 }
  ]
}
```

分类以「规则编号＋稳定路径锚点」关联同一组，成员与次数按多重集比较，输出 `moonportcheck-baseline-diff`：

```json
{ "format": "moonportcheck-baseline-diff", "schema_version": 1,
  "changes": [{ "code": "...", "anchor": "...", "status": "new|existing|worsened|resolved", "members": [...], "source_total": 0 }] }
```

- `resolved`：基线中有、对比报告中整组消失（`members` 为空、`source_total` 为 0）。
- `existing`：同组仍在且没有任何成员计数上升（含成员减少的情况）。
- `worsened`：同组新增成员路径/类型，或任一成员次数上升。
- `new`：报告中有、基线中没有的组。
- 变化列表按状态序 `new`、`worsened`、`existing`、`resolved` 再按 code/anchor 排序。
- 非完整报告或非 schema 2 报告不能建基线（退出 `2`，代码 `INPUT_INCOMPLETE`/`INPUT_SCHEMA`）；`--baseline` 不匹配、扫描失败等 CLI 语义在 M12 交付。

## 机器消费者迁移步骤1. 对审计／错误对象先验证 `schema_version === 2`，再区分 `error` 与审计报告；规则查询仍按数组读取。
2. 将原来在 `diagnostics` 中筛选 `SCAN_*` 的代码移到外层 `scan_issues`。统计路径问题时使用 `summary.diagnostic_groups`，统计扫描问题时使用 `summary.scan_issues`。
3. 保留旧 `paths` 与 `occurrences` 的解释。需要定位实际文件时读取 `members`；需要全部出现次数时显式汇总成员 `count`，不要使用 `source_total` 代替。
4. 对诊断组采用 `group_key` 和 `anchor` 定位；机器分析保留完整 `members`。不要以最多 5 条的 `source_examples` 判断问题新增、消失或成员变化。
5. 同时处理 `complete` 与进程退出码。无路径问题但扫描不完整仍失败；错误响应没有可用的审计 `summary`。

参数／输入失败仍退出 `2`，I/O 失败或扫描不完整仍退出 `3`。CLI 错误 JSON 为独立对象，例如 `{"schema_version":2,"profile":"portable-windows-v1","complete":false,"error":{"code":"INPUT_JSON","message":"..."}}`，不是填充空数组的审计报告。

报告不包含时间戳或扫描根目录的绝对路径。schema 2 诊断组按 `code`、`anchor` 的 UTF-16 ordinal 顺序排列；v1 保持原来的 `code`、`paths` 排序。两者各自稳定，不保证新旧诊断数组的位置一一对应，跨版本核对时应按组定位。成员、样例和扫描问题同样保持确定性，输入重排不改变内容。名称中的控制字符在 JSON 中转义，文本来源展示同样安全引用，例如换行名称显示为 `"bad\nname"`，不会把名称中的换行当作报告排版。
