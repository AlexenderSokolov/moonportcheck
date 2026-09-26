# Schema 2：详细报告与消费迁移

本文对应 `0.2.0-dev` 的 M04 详细诊断接口。源码处于开发阶段，尚未正式发布。M04 增加来源证据与独立扫描问题；配置排除、快照、差异、基线、SARIF 和 Markdown 报告属于后续里程碑，不能由本文中的预留字段推断它们已经可用。

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
| `scope` | 规范化后的有效排除模式数组 | `[]`，当前没有排除功能 |
| `excluded_entries` | 已知被排除的条目数 | `0` |
| `pruned_directories` | 实际剪枝的相对目录路径数组 | `[]` |
| `limitations` | 覆盖限制字符串数组 | 保留覆盖边界说明 |

`scope`、`excluded_entries`、`pruned_directories` 从 schema 2 起始终存在，使报告能够完整表达检查范围。M04 尚未接入排除或剪枝；后续实现也只能统计已知排除项，不能估算未遍历子树的文件数。空范围表示没有配置排除，不表示默认忽略 `.git` 或隐藏目录。

扫描问题不再混入 `diagnostics`。例如跳过链接会出现在 `scan_issues` 中，令 `complete=false`；即使没有任何路径诊断，CLI 也必须退出 `3`。同时存在路径问题和扫描问题时，两者均保留，`3` 优先于 `1`。

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

## 机器消费者迁移步骤

1. 对审计／错误对象先验证 `schema_version === 2`，再区分 `error` 与审计报告；规则查询仍按数组读取。
2. 将原来在 `diagnostics` 中筛选 `SCAN_*` 的代码移到外层 `scan_issues`。统计路径问题时使用 `summary.diagnostic_groups`，统计扫描问题时使用 `summary.scan_issues`。
3. 保留旧 `paths` 与 `occurrences` 的解释。需要定位实际文件时读取 `members`；需要全部出现次数时显式汇总成员 `count`，不要使用 `source_total` 代替。
4. 对诊断组采用 `group_key` 和 `anchor` 定位；机器分析保留完整 `members`。不要以最多 5 条的 `source_examples` 判断问题新增、消失或成员变化。
5. 同时处理 `complete` 与进程退出码。无路径问题但扫描不完整仍失败；错误响应没有可用的审计 `summary`。

参数／输入失败仍退出 `2`，I/O 失败或扫描不完整仍退出 `3`。CLI 错误 JSON 为独立对象，例如 `{"schema_version":2,"profile":"portable-windows-v1","complete":false,"error":{"code":"INPUT_JSON","message":"..."}}`，不是填充空数组的审计报告。

报告不包含时间戳或扫描根目录的绝对路径。schema 2 诊断组按 `code`、`anchor` 的 UTF-16 ordinal 顺序排列；v1 保持原来的 `code`、`paths` 排序。两者各自稳定，不保证新旧诊断数组的位置一一对应，跨版本核对时应按组定位。成员、样例和扫描问题同样保持确定性，输入重排不改变内容。名称中的控制字符在 JSON 中转义，文本来源展示同样安全引用，例如换行名称显示为 `"bad\nname"`，不会把名称中的换行当作报告排版。
