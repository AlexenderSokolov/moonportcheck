# Changelog

## 0.2.0-dev — 开发中，未正式发布

- 增加规则目录与 `rules` / `explain CODE` 查询，成功查询的 JSON 保持规则数组。
- 增加 `AuditOptions`、详细报告、原始来源成员与计数、稳定分组身份，以及最多 5 个展示样例。
- CLI 审计报告和错误 JSON 升级为 schema 2；扫描问题与路径诊断分开，扫描不完整仍优先退出 `3`。
- 原 `PathEntry`、`Report`、`parse_manifest`、`audit`、文本／JSON 渲染接口保持 v1 行为与 schema 1；迁移说明见 [SCHEMA2.md](docs/SCHEMA2.md)。
- M05 增加纯 MoonBit 排除模式匹配器 `parse_pattern` / `pattern_matches`，语义见 [PATTERNS.md](docs/PATTERNS.md)。
- M06 增加 `parse_scope` / `entry_excluded` / `effective_scope_patterns` / `audit_with_exclusions`，以及 `check`/`scan` 的 `--exclude` 与版本化 `--config`；报告 `scope`、`excluded_entries`、`pruned_directories` 现在反映实际排除范围，不隐式读取 `.gitignore`。
- M07 增加快照模型 `Snapshot` 与 `build_snapshot` / `parse_snapshot` / `render_snapshot_json`：持久化唯一排序条目、范围、完整性与扫描问题（不含内容/时间戳/绝对路径），往返一致、排序稳定、损坏或非规范输入拒绝。`check` 快照支持与 `snapshot` 命令在 M08 提供。
- M08 增加 `snapshot ROOT` 命令（导出固定 JSON 快照文档，完整退出 0、不完整退出 3）与 `audit_snapshot`：`check` 现在接受原数组清单或快照文档，检查快照时继承其范围、额外排除只能缩小、不完整快照始终不完整，报告 `source` 记为 `"snapshot"`；profile 不匹配的快照拒绝。
- M09 增加快照差异核心 `DiffKind` / `SnapshotChange` / `SnapshotDiff` / `diff_snapshots` 与 `render_snapshot_diff_json`：先精确路径匹配、再 ASCII 折叠，仅一对一且类型相同的折叠记为大小写变化，报告新增/移除/类型/大小写四类变化并按固定顺序排序；两份快照范围不同拒绝（`INPUT_SCHEMA`），`complete` 取两份输入的完整度。`diff` 命令在 M10 提供。
- M10 增加 `diff` 命令与文本渲染 `render_snapshot_diff_text`：`moonportcheck diff BEFORE.json AFTER.json [--format text|json]`，退出码 0=无变化、1=有变化、2=文档损坏或范围不同、3=任一输入不完整（text 输出标注 `INCOMPLETE`）。
- M11 增加基线模型与分类核心 `BaselineStatus` / `Baseline` / `build_baseline` / `diff_with_baseline` 与渲染：基线只允许从完整 schema 2 报告创建（绑定 profile、规则版本与有效检查范围）；按「规则编号＋稳定路径锚点」关联同组，新增成员或次数上升为 `worsened`、整组消失为 `resolved`、同组减少仍为 `existing`、无基线组为 `new`；`moonportcheck-baseline` 与 `moonportcheck-baseline-diff` 固定文档。`baseline` 命令与 `scan --baseline --fail-on` 在 M12 提供。
- 快照、差异、基线和新的报告格式尚待对应里程碑实现。

各里程碑的完成情况、提交与公开 CI 以 [V02_PROGRESS.md](docs/V02_PROGRESS.md) 为准；开发版本号不表示正式包发布或赛事验收。

## 0.1.0 — 本地候选，未发布

- 增加 `portable-windows-v1` 纯 MoonBit 路径检查库与 UTF-8 JSON 清单接口。
- 检查 Windows 常见非法名称、保留设备名、尾点／空格和路径结构问题。
- 使用层级索引检查重复路径、ASCII 大小写冲突与文件／目录冲突，包含隐含中间目录。
- 提供 `scan` / `check` 离线 CLI、文本／JSON 报告及明确的完整性与退出码。
- 增加项目隔离工具链、跨目标测试入口、三组可复现演示和十月活动申报草稿。

本节记录 v0.1 本地候选阶段的交付，当时尚未声明公开 CI、Mooncakes 发布或十月活动验收完成；后续公开开发与 CI 结果见 v0.2 执行账本。
