# MoonPortCheck 项目背景与维护约定

## 目标与成功标准

为 2026 年十月 MoonBit 活动准备独立的 `0.1.0` 作品，解决代码、数据和实验成果交付给 Windows 用户前的名称兼容检查。目标是一个可运行、可解释、可复现的小工具：MoonBit 核心库、离线 CLI、测试、三组演示和申报材料。

工作目录为 `D:\Study_Works\MoonBit\moonportcheck`。本项目与上级目录已有作品独立，使用自己的模块、工作区和工具链配置。2026-09-26 用户已批准 [v0.2 计划](docs/V02_PLAN.md)，授权创建公开 GitHub 仓库、真实基线提交、持续 PR 的逐次提交／推送和保留提交合并。正式包发布、Mooncakes 上传和报名仍另行授权。执行状态见 [V02_PROGRESS.md](docs/V02_PROGRESS.md)。

固定配置为 `portable-windows-v1`。名称规则参照 [Microsoft 文件命名文档](https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file)，项目自身的集合与输入语义详见 [docs/RULES.md](docs/RULES.md)。十月赛事要求沿用现有活动规则规划，正式报名时必须再检查当月公告。

## 架构与边界

- **纯 MoonBit 根包**：输入模型、清单 JSON 解析、单条规则、层级索引、集合冲突分组、确定性报告与文本／JSON 渲染。只依赖标准库。
- **MoonBit JS bridge**：将 host 请求交给核心检查，汇总扫描完整性、错误响应和退出码。外部协议写在 [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md)。
- **Node.js host**：命令行参数、严格 UTF-8 解码、目录枚举、`lstat` 和标准输出。只读取扫描对象的元数据，不读取文件内容。
- **测试与脚本**：JS / wasm-gc 核心测试、Node CLI 端到端、跨目标报告比对、规模验证、独立消费与打包验证。

目录扫描包含隐藏项，根目录本身不计数；不跟随符号链接或 junction。部分扫描结果不得宣称完整通过。CLI 固定退出码 `0`/`1`/`2`/`3`，分别表示无发现、规则发现、输入错误、I/O 或扫描不完整；不完整优先于规则发现。

输入路径只使用 `/` 分段，不静默规范化反斜杠。结构无效的路径接受单条检查但不进入层级索引。中间目录隐含存在；冲突按组输出，重复条目保留准确次数，避免两两展开。排序稳定，不添加时间戳或绝对扫描根目录。

首版不处理自动改名、归档文件解析、网页界面、完整 Unicode 大小写／规范化、长路径或全部文件系统限制。通过结果只覆盖给定输入与固定配置，不是任意 Windows 文件操作的保证。

## 工具链与运行

使用项目本地 MoonBit `v0.10.14`，锁定的 `moonc` 为 `v0.10.14+7d59c7ec9`，`moon` 为 `0.1.20260920`。CI 使用 Node.js `24.15.0`。安装使用完整版本 URL 和 SHA-256 锁定，归档变化必须失败，不回退 `latest`。Linux 安装时恢复经校验归档中 ELF 工具的执行权限。`scripts/cold-install.mjs` 在全新 home/cache 中验证下载、版本和 core 构建；CI 后续步骤复用该结果，运行环境和精确提交身份由验收记录保存。

| 操作 | PowerShell | Bash |
| --- | --- | --- |
| 安装隔离工具链 | `pwsh -File scripts/toolchain.ps1 -Install` | `bash scripts/toolchain.sh install` |
| 构建 | `pwsh -File run_build.ps1` | `bash run_build.sh` |
| 核心与 CLI 检查 | `pwsh -File run_check.ps1` | `bash run_check.sh` |
| 三组演示 | `pwsh -File run_demo.ps1` | `bash run_demo.sh` |
| 完整本地验收 | `pwsh -File run_acceptance.ps1` | `bash run_acceptance.sh` |

构建后使用 `node bin/moonportcheck.mjs scan ROOT --format json` 或 `node bin/moonportcheck.mjs check MANIFEST --format text`。构建及检查不自动联网安装。运行方式改变时同步更新入口脚本及 README。

## 验收要求

1. 规则测试覆盖保留设备名与扩展名、上标数字、控制字符、尾点／空格、绝对路径／盘符／UNC、空段／点段，以及合法中文、空格和点开头名称。
2. 验证重复次数、隐含目录大小写冲突、文件／目录前缀冲突和输入顺序不影响报告。
3. 合法 JSON 的坏路径进入规则诊断；损坏 JSON、编码及结构错误获得正确错误响应。
4. 链接、读取失败、异常类型或名称编码问题令扫描不完整，退出 `3`；已经发现的规则问题仍可见。
5. JS 与 wasm-gc 核心结果一致；Windows / Linux 的 CLI 端到端验证。Linux 实际坏名称与 Windows 等价清单分别验证。
6. 十万条正常路径和大量冲突路径记录耗时及内存；不在实测前承诺性能数值。
7. 独立 MoonBit 消费项目可调用库，打包 CLI 在干净环境可运行；三组演示断言真实输出。
8. 交付保留工具链完整版本、来源校验、测试记录与源码身份。项目拥有独立 Git 仓库；首次提交前记录 `source_commit: null` 和源码文件 SHA-256 清单，不以其他作品的提交冒充本项目身份。

本地结果、配置好的 CI、已运行的公开 CI、包已发布及官方验收应分别记录。公开发布后才核验 Mooncakes 的构建与安装结果。

## 时间安排与长期决策

计划 10 月 1–3 日锁定规则与最小链路，4–10 日完成核心与清单，11–17 日完成真实扫描与跨平台检查，18–24 日完成审查和候选版本，25–31 日处理验收与发布缓冲。可提前实现，但不把提前完成的本地工作当作十月报名或验收已通过。

首版优先保留小而完整的覆盖范围。新增规则需要更新配置语义、规则文档与反例测试；可能改变结果的规则变更必须显式记录版本。内部接口细节可调整，但已记录的诊断编号、CLI 退出码与 JSON schema 不得无记录地变化。临时调试过程放进进度或验证记录，本文件只维护长期有用的决策。
