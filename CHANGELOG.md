# Changelog

## 0.2.0 — 2026-10-01

- 发布前独立审查修复快照完整性继承、重复路径与矛盾完整性输入、差异范围过滤、SARIF 非法路径导航和 schema 2/基线未知字段校验。
- `scan/check --format sarif` 完整接通（保留 `--report sarif`）；基线扫描输出 `new/existing/worsened/resolved` 派生分类，旧问题继续可见。
- 解包验收绑定当前版本、平台和 HEAD，不再按文件名字典序选旧包；校验归档内部哈希和运行版本，使用标准 ZIP 日期，并包含 README 引用的使用文档和样例。
- 最终验收证据与候选归档均保留 90 天。GitHub 与 Mooncakes 的实际发布状态见发布审计。

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
- M11 增加基线模型与分类核心 `BaselineStatus` / `Baseline` / `build_baseline` / `diff_with_baseline` 与渲染：基线只允许从完整 schema 2 报告创建（绑定 profile、规则版本与有效检查范围）；按「规则编号＋稳定路径锚点」关联同组，新增成员或次数上升为 `worsened`、整组消失为 `resolved`、同组减少仍为 `existing`、无基线组为 `new`；`moonportcheck-baseline` 与 `moonportcheck-baseline-diff` 固定文档。
- M12 增加 `baseline create REPORT.json` 与 `scan ROOT --baseline BASELINE.json [--fail-on new]`：根包新增 `parse_baseline` 与 `parse_detailed_report`（schema 2 报告全量回读，strict 字段/整数/布尔校验）；`scan --baseline` 校验 profile/规则版本/有效 scope 后按基线分类，`--fail-on new` 仅对 `new`/`worsened` 退出 `1`，默认按全部诊断判定，扫描不完整始终退出 `3` 且不被基线豁免；发布版保留当前报告并附加派生分类。
- M13 增加 Markdown 差异表与 SARIF 2.1.0 报告：`diff --format markdown` 输出 `# MoonPortCheck diff` 表格（管道符/换行已转义，不完整输入用 `> INCOMPLETE` 块引用标注）；`check --report sarif` 输出合法 SARIF 2.1.0 文档，位置仅含 artifact URI ——模型没有源码行号，绝不虚构 region/源码行，扫描问题映射为 `note` 级结果，`invocations[0].executionSuccessful` 反映扫描完整度。路径 URI 按 UTF-8 百分号编码，驱动器 `MoonPortCheck`、`PRODUCT_VERSION` 0.2.0。
- M14 增加 `scan`/`check` 的 Markdown 报告渲染 `render_detailed_markdown` ：`--format markdown` 输出 `# MoonPortCheck report`（状态/范围/诊断/扫描问题表格，路径与消息经 `md_cell` 转义，退出码与文本/JSON/SARIF 完全一致），`rules`/`explain` 仍仅 text/json；新增 `scripts/format-matrix.mjs` 格式一致性门禁（同输入四格式退出码一致、Markdown/SARIF 与 JSON 诊断码集合相等）；新增 `scripts/ci-report.mjs` 在 CI 生成全格式报告产物 `artifacts/reports/` 上传 artifact 并写入 `$GITHUB_STEP_SUMMARY` 摘要示例（不声明 GitHub Code Scanning 接收成功）。
- M15 增加性质测试与规模验收：`scripts/property.mjs`（确定性种子 0xC0FFEE，60 轮随机清单）：输入重排不改变渲染报告、扩大排除范围不新增 findings 且 excluded_entries 不降、报告与基线解析往返一致、同一清单建的基线再扫描无 new 组并纳入 run_check（ps1/sh）；`scripts/bench.mjs` 扩展为 5 个规模案例（普通 10 万、分组冲突 10 万=300 组、40 层深路径 2000、1500 字符共前缀 2000、单组重复 10 万次）并记录耗时/峰值内存/报告体积到 `artifacts/benchmark.json`；run_check 的 LOC 门禁改为硬性 `code-stats --min 3000`。
- M16 增加发布候选包：`scripts/package.mjs` 生成逐字节确定的 ZIP（stored 条目、固定时间戳、纯 Node 手写 CRC32/中央目录，含 `bin/moonportcheck.mjs`、`lib/host.mjs`、`dist/bridge.js`、`package.json`、`LICENSE`、`README.md` 与每文件 `CHECKSUMS.txt`，外层 `SHA256SUMS.txt` 含归档哈希）；`scripts/unpack.mjs` 用同一纯 Node 读取器解包并在仅含 Node 目录的 PATH（无 `MOON_HOME`）下运行解出的 CLI 自证自洽；二者接入 acceptance 场景，CI 以 90 天保留上传 `candidate-*` artifact（常规证据 30 天，最终候选验收证据 90 天）。
- 上述 M01–M16 的产品功能已实现；原始开发记录与发布前修复分开保留。

各里程碑的完成情况、提交与公开 CI 以 [V02_PROGRESS.md](docs/V02_PROGRESS.md) 为准；开发版本号不表示正式包发布或赛事验收。

## 0.1.0 — 本地候选，未发布

- 增加 `portable-windows-v1` 纯 MoonBit 路径检查库与 UTF-8 JSON 清单接口。
- 检查 Windows 常见非法名称、保留设备名、尾点／空格和路径结构问题。
- 使用层级索引检查重复路径、ASCII 大小写冲突与文件／目录冲突，包含隐含中间目录。
- 提供 `scan` / `check` 离线 CLI、文本／JSON 报告及明确的完整性与退出码。
- 增加项目隔离工具链、跨目标测试入口、三组可复现演示和十月活动申报草稿。

本节记录 v0.1 本地候选阶段的交付，当时尚未声明公开 CI、Mooncakes 发布或十月活动验收完成；后续公开开发与 CI 结果见 v0.2 执行账本。
