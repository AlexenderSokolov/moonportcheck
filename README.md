# MoonPortCheck

用 MoonBit 编写的跨平台路径预检库与离线 CLI。在把代码、数据或实验成果交给 Windows 用户前，检查文件名称、隐含目录及集合冲突。

**当前版本：`0.1.0` 本地候选版。** 检查配置固定为 `portable-windows-v1`。项目尚未对外发布；这里不将本地测试等同于公开 CI、Mooncakes 安装或赛事验收通过。

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
moonportcheck scan ROOT [--format text|json]
moonportcheck check MANIFEST [--format text|json]
moonportcheck --help
moonportcheck --version
```

源码环境用 `node bin/moonportcheck.mjs` 代替 `moonportcheck`；打包后的 bin 入口同名。

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

| 退出码 | 含义 |
| --- | --- |
| `0` | 检查完整，已覆盖规则未发现问题 |
| `1` | 检查完整，存在路径或冲突问题 |
| `2` | 参数、编码或清单结构错误 |
| `3` | I/O 失败或扫描不完整，优先于 `1` |

报告写入标准输出。JSON 报告具有 `schema_version`、`profile`、`source`、`complete`、`summary`、`diagnostics` 和 `limitations`；每组诊断含 `code`、`severity`、`paths`、`occurrences`、`message`。诊断分组与排序固定，不附时间戳。错误使用独立错误响应，不输出误导性的空成功报告。

## 作为 MoonBit 库使用

模块名称为 `AlexenderSokolov/moonportcheck`，根包提供以下公共接口。发布前可通过 `moon.work` 引用本地模块；验收脚本会创建具有独立模块、包和工作区配置的消费项目，不能先假定 Mooncakes 已提供此版本。

| 接口 | 用途 |
| --- | --- |
| `EntryKind`：`File` / `Directory` | 路径条目类型 |
| `PathEntry`：`path`、`kind` | 输入条目 |
| `parse_manifest(String)` | 返回 `Result[Array[PathEntry], InputError]` |
| `audit(Array[PathEntry])` | 返回结构化 `Report` |
| `render_json(Report)` | 生成 JSON 报告 |
| `render_text(Report)` | 生成可读文本报告 |

纯库只检查传入集合，不访问文件系统。CLI 负责在报告中补充来源与扫描完整性。核心库的 JS 与 wasm-gc 行为应通过同一组测试和报告比对。

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

`run_check` 汇总工具链检查、格式检查、构建、双目标核心测试、Node CLI 测试和跨目标报告比对。`run_acceptance` 包含这些检查，并依次运行演示、十万条路径规模测试、独立库消费及不带编译器的 CLI 运行验证；日志、工具链身份和源码文件哈希保存在 `artifacts/acceptance-<平台>-<时间>/`。规模测试也可单独运行 `node scripts/bench.mjs`；时间与内存以当次输出为准。实际结果及验证边界见 [ACCEPTANCE.md](docs/ACCEPTANCE.md)。公开 CI、Mooncakes 发布和十月活动验收需要后续发布步骤与实际结果。

## 覆盖范围

完整规则见 [RULES.md](docs/RULES.md)。当前覆盖 Windows 常见非法名称、设备名、尾点或尾空格、路径结构、重复、ASCII 大小写及文件／目录冲突。

符号链接和 junction 不跟随；跳过链接、不支持的类型、无法无损解码的名称或读目录失败会使扫描不完整。中文名称原样保留，完整 Unicode 大小写等价、规范化、长路径、8.3 别名及特定文件系统限制不在首版范围内。工具不执行改名，不解析压缩包，也不判断文件内容。

`complete=true` 表示本次输入在已覆盖规则内检查完整；清单检查不证明实际目录与清单一致，退出 `0` 不保证所有 Windows 环境都能成功复制或打开。

设计与长期维护约定见 [PROJECT.md](PROJECT.md)，申报草稿见 [APPLICATION.md](docs/APPLICATION.md)，版本变更见 [CHANGELOG.md](CHANGELOG.md)。许可证为 [Apache-2.0](LICENSE)。
