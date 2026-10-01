# MoonPortCheck

用 MoonBit 编写的跨平台路径预检库与离线 CLI。在把代码、数据或实验成果交给 Windows 用户前，检查文件名称、隐含目录及集合冲突。

**当前源码版本：`0.2.0`。** 固定配置为 `portable-windows-v1`。提供可解释的规则查询、详细来源报告、配置化排除、目录快照与差异、历史问题基线及增量 CI 判定；`scan/check` 支持 text、JSON、Markdown、SARIF 2.1.0。完整开发与 CI 记录见 [执行账本](docs/V02_PROGRESS.md)，原始范围见 [v0.2 计划](docs/V02_PLAN.md)，发布前独立核验见 [发布审计](docs/RELEASE_AUDIT_2026-10-01.md)。

CLI ZIP 下载入口：[GitHub v0.2.0 Release](https://github.com/AlexenderSokolov/moonportcheck/releases/tag/v0.2.0)。解包后以 `node bin/moonportcheck.mjs --help` 运行，需 Node.js 24，无需 MoonBit 编译器。归档附带 LICENSE、使用文档、样例与文件校验和；库发布入口为 [Mooncakes](https://mooncakes.io/docs/AlexenderSokolov/moonportcheck)。发布验证状态以发布审计和远端实际记录为准。

```text
results/A.csv + results/a.csv  → PATH_CASE_COLLISION
assets/CON.txt                 → NAME_RESERVED
notes/report.md.               → NAME_TRAILING_DOT_SPACE
```

核心检查、JSON 解析、冲突分组和报告渲染均由纯 MoonBit 完成，仅依赖标准库。Node.js 适配层读取文件名、文件类型及 UTF-8 清单，不读取被扫描文件的内容，不修改输入目录。

## 从源码运行

要求 **Node.js 24**，MoonBit 使用项目隔离的 **`v0.10.14`**。不需要 `npm install`，也不要求修改全局 MoonBit。Windows 命令从本项目目录运行：

```powershell
pwsh -File scripts/toolchain.ps1 -Install
pwsh -File run_build.ps1
node bin/moonportcheck.mjs --version
node bin/moonportcheck.mjs check examples/windows-problems.json --format text
```

Linux 的等价入口：

```bash
bash scripts/toolchain.sh install
bash run_build.sh
node bin/moonportcheck.mjs --version
node bin/moonportcheck.mjs check examples/windows-problems.json --format text
```

最后一个命令发现问题时退出 `1`，这是预期行为。首次安装访问官方完整版本 `0.10.14%2B7d59c7ec9` 的固定归档地址，并核对 `scripts/toolchain.lock.json` 中的 SHA-256；下载或校验失败会停止，不回退 `latest`。安装器在 Linux 上恢复经过校验的原生 ELF 工具的执行权限。保留 `.toolchains` 缓存可用于离线恢复；构建和检查入口不自动联网安装。完整版本、归档来源与校验值以锁文件及安装器输出为准。

`node scripts/cold-install.mjs` 使用新的临时安装目录和空下载缓存验证冷安装，保存下载哈希、完整版本及 core 构建证据。`MOONPORT_TOOLCHAIN_HOME` 和 `MOONPORT_TOOLCHAIN_CACHE` 可显式选择隔离目录；CI 直接复用其冷安装结果。CI 检查精确 PR 提交，只对 `main` push 和 PR 更新运行，常规证据保留 30 天。

## 检查目录或清单

```text
moonportcheck scan ROOT [--config FILE] [--exclude PATTERN]... [--baseline FILE] [--fail-on new] [--format text|json|markdown|sarif]
moonportcheck snapshot ROOT [--config FILE] [--exclude PATTERN]...
moonportcheck check MANIFEST [--config FILE] [--exclude PATTERN]... [--format text|json|markdown|sarif]
moonportcheck diff BEFORE.json AFTER.json [--format text|json|markdown]
moonportcheck baseline create REPORT.json
moonportcheck rules [--format text|json]
moonportcheck explain CODE [--format text|json]
moonportcheck --help
moonportcheck --version
```

源码环境用 `node bin/moonportcheck.mjs` 代替 `moonportcheck`；打包后的 bin 入口同名。

`snapshot ROOT` 把真实目录导出为固定 JSON 快照文档（`{"format":"moonportcheck-snapshot","version":1,...}`，不接受 `--format`）：完整导出退出 `0`、扫描不完整退出 `3`。`check MANIFEST` 同时接受原数组清单与该快照文档：检查快照时继承其排除范围，`--config`/`--exclude` 的额外排除只能缩小范围，不完整快照始终保持不完整（退出 `3`），报告 `source` 为 `"snapshot"`。`diff BEFORE.json AFTER.json` 比较两份快照：退出 `0`=无变化、`1`=有变化、`2`=文档损坏或范围不同、`3`=任一输入不完整，绝不推测重命名或内容变化。

```powershell
# 实际目录：包含隐藏项，输出相对于根目录的路径。
node bin/moonportcheck.mjs scan ./delivery --format text

# 清单：可在 Windows 上预检本机无法创建的 Linux 文件名。
node bin/moonportcheck.mjs check examples/windows-problems.json --format json
```

清单是 UTF-8 JSON 数组；`path` 为使用 `/` 分隔的相对路径，`kind` 为 `file` 或 `directory`。目录名不附加尾部 `/`。

```json
[
  { "path": "README.md", "kind": "file" },
  { "path": "results/实验记录.csv", "kind": "file" }
]
```

中间目录不必显式列出。反斜杠不会被转换为分隔符。合法清单里的非法路径属于规则发现；损坏 JSON 或字段类型错误属于输入错误。

可以用 `--exclude PATTERN`（可重复）或 `--config FILE` 缩小检查范围，两者取并集；模式语法与含义见 [PATTERNS.md](docs/PATTERNS.md)。配置文件是带版本号的 JSON，`schema_version` 必须为 `1`：

```json
{ "schema_version": 1, "exclude": ["**/cache", "*.tmp"] }
```

被排除条目不进入审计，也不产生诊断；被整棵排除的目录不再枚举其子树（扫描）。任何人不得隐式读取 `.gitignore`。配置结构错误退出 `2`，无法读取或非法 UTF-8 分别退出 `3` 与 `2`。

| 退出码 | 含义 |
| --- | --- |
| `0` | 检查完整，已覆盖规则未发现问题 |
| `1` | 检查完整，存在路径或冲突问题 |
| `2` | 参数、编码或清单结构错误 |
| `3` | I/O 失败或扫描不完整，优先于 `1` |

报告写入标准输出。v0.2 CLI 的审计和错误 JSON 明确使用 **schema 2**。审计报告保留原有平面字段，详细诊断增加原始来源、成员计数和稳定组身份；扫描问题独立放在 `scan_issues`，不再混入 `diagnostics`。`scope`、`excluded_entries`、`pruned_directories` 在 M06 起反映实际排除范围：`scope` 为去重排序后的有效模式，`excluded_entries` 只统计已知输入中实际被排除的条目，`pruned_directories` 列出最顶层被剪枝目录。诊断分组与排序固定，不附时间戳。错误使用独立错误响应，不输出误导性的空成功报告。字段与消费迁移见 [SCHEMA2.md](docs/SCHEMA2.md)。

## 作为 MoonBit 库使用

模块名称为 `AlexenderSokolov/moonportcheck`，根包提供以下公共接口。正式包发布后使用 `moon add AlexenderSokolov/moonportcheck@0.2.0`；也可通过 `moon.work` 引用本地模块。验收脚本创建独立模块、包和工作区验证原 v1 公共接口，公共注册表安装验证单独记录。

| 接口 | 用途 |
| --- | --- |
| `EntryKind`：`File` / `Directory` | 路径条目类型 |
| `PathEntry`：`path`、`kind` | 输入条目 |
| `parse_manifest(String)` | 返回 `Result[Array[PathEntry], InputError]` |
| `audit(Array[PathEntry])` | 返回结构化 `Report` |
| `render_json(Report)` | 生成 JSON 报告 |
| `render_text(Report)` | 生成可读文本报告 |

这些原接口及 `Report` 保持 v1 行为，`render_json` 仍输出 schema 1，已有库消费者无需修改。需要详细报告时，使用不透明的 `AuditOptions` 及 `default_audit_options()`，调用 `audit_with_options(entries, options)` 返回 `DetailedReport`，再用 `render_detailed_json` / `render_detailed_text` 渲染。`ScanIssue` 与 `with_scan_issues` 用于附入扫描完整性问题。

详细诊断的 `members` 保留全量原始 `(path, kind, count)`，`source_examples` 最多展示 5 条，不能代替完整成员或组身份；`occurrences` 保留旧含义。纯库只检查传入集合，不访问文件系统。CLI 使用详细接口汇总来源与扫描完整性。核心库的 JS 与 wasm-gc 行为通过同一组测试和报告比对；新旧接口选择及字段说明见 [schema 2 迁移说明](docs/SCHEMA2.md)。

## 演示与验证

Windows：

```powershell
pwsh -File run_demo.ps1
pwsh -File run_check.ps1
pwsh -File run_acceptance.ps1
```

Linux：

```bash
bash run_demo.sh
bash run_check.sh
bash run_acceptance.sh
```

演示会重新构建，再调用真实 CLI 并断言退出码、完整性与诊断编号；不是预先写好的终端截图。

| 演示文件 | 展示内容 | 预期退出码 |
| --- | --- | --- |
| [portable.json](examples/portable.json) | 中文、空格、点开头名称正常通过 | `0` |
| [windows-problems.json](examples/windows-problems.json) | 大小写冲突、设备保留名、尾点 | `1` |
| [hierarchy-conflicts.json](examples/hierarchy-conflicts.json) | 三次重复、隐含目录大小写冲突、文件与目录冲突 | `1` |

`run_check` 汇总工具链检查、格式检查、构建、双目标核心测试、Node CLI 测试和跨目标报告比对。`run_acceptance` 包含这些检查，并依次运行演示、十万条路径规模测试、独立库消费及不带编译器的 CLI 运行验证；日志、工具链身份和源码文件哈希保存在 `artifacts/acceptance-<平台>-<时间>/`。规模测试也可单独运行 `node scripts/bench.mjs`；时间与内存以当次输出为准。v0.1 本地结果及验证边界见 [ACCEPTANCE.md](docs/ACCEPTANCE.md)，v0.2 各提交的实际检查和公开 CI 见 [执行账本](docs/V02_PROGRESS.md)。Mooncakes 发布和十月活动验收仍需后续授权与实际结果。

## 覆盖范围

完整规则见 [RULES.md](docs/RULES.md)。当前覆盖 Windows 常见非法名称、设备名、尾点或尾空格、路径结构、重复、ASCII 大小写及文件／目录冲突。

符号链接和 junction 不跟随；跳过链接、不支持的类型、无法无损解码的名称或读目录失败会使扫描不完整。中文名称原样保留，完整 Unicode 大小写等价、规范化、长路径、8.3 别名及特定文件系统限制不在首版范围内。工具不执行改名，不解析压缩包，也不判断文件内容。

`complete=true` 表示本次输入在已覆盖规则内检查完整；清单检查不证明实际目录与清单一致，退出 `0` 不保证所有 Windows 环境都能成功复制或打开。

设计与长期维护约定见 [PROJECT.md](PROJECT.md)，申报草稿见 [APPLICATION.md](docs/APPLICATION.md)，版本变更见 [CHANGELOG.md](CHANGELOG.md)。许可证为 [Apache-2.0](LICENSE)。

## 查询规则原因与建议

```text
moonportcheck rules --format json
moonportcheck explain NAME_RESERVED
```

`rules` 列出 11 个审计规则和 4 个扫描完整性问题；`explain CODE` 精确匹配编号并显示原因、触发例子和整改建议。两者支持 text/JSON，JSON 为稳定排序的规则数组，查询单条时数组长度为 1。未知编号退出 `2`，已知规则查询退出 `0`；这不表示执行了目录检查。

库还提供 `parse_pattern` 与 `pattern_matches` 进行纯路径范围匹配，M06 再以 `parse_scope` / `entry_excluded` / `audit_with_exclusions` 接入配置与 CLI 排除，完整语义见 [PATTERNS.md](docs/PATTERNS.md)。M07 增加快照模型 `Snapshot` 与 `build_snapshot` / `parse_snapshot` / `render_snapshot_json`，把唯一排序条目、范围、完整性与扫描问题持久化为可往返的独立 JSON 文档（不含内容、时间戳或主机绝对路径），供后续快照命令与差异比较使用。
