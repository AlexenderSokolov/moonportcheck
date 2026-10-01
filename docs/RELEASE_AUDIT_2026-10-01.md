# MoonPortCheck v0.2.0 发布审计

日期：2026-10-01。用户要求分析 DeepSeek harness 成果是否达到原始设想及验收要求，并正式发布。审计依据原始 `V02_PLAN.md`、实际源码、独立审查、重新运行的验收及远端精确 SHA 证据。

## 结论与原始成果评价

主线方向已实现：一次性名称检查发展为可配置范围、快照比较、历史问题基线及 CI 报告的交付检查工具。MoonBit 承担规则、匹配、快照、比较、基线与渲染，Node 承担 I/O；v1 库实现和接口保留。harness 的 M06–M16 是实质新增，提交历史及原 Draft PR 均保留。

但“所有测试通过”不足以支持原账本的“验收全部达成”：独立审查发现实际输入可触发遗漏，必须补齐后才发布。原 main `3cdc9d4980d2a7e9deb0139d67c7a591c9e2a119` 的 [CI 36820799686](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36820799686) 两系统通过，PR #1 已合并；本轮又在该实现上运行了完整 Windows 验收，证据 `acceptance-win32-2026-10-01T06-16-38-200Z/evidence.json` 为 passed。这说明旧测试集合通过，不证明下列缺口不存在。

## 独立发现与必要修复

| 问题 | 可复现影响 | 发布修复 |
| --- | --- | --- |
| 快照未继承 complete | `complete:false` 且 issues 空的快照被 check 判为完整并退出 0 | 显式继承完整性，四格式均不得豁免 |
| 快照路径唯一性/完整性矛盾 | 同一路径 file/directory 被解析；complete:true 附 IO 问题参与 diff 仍被当完整 | 拒绝同路径重复及矛盾输入 |
| diff 忽略 scope | 被排除的 tmp 文件变化仍触发差异退出 1 | 比较前复用范围过滤，保留结构非法路径诊断 |
| SARIF 产品入口/位置 | scan 无 SARIF CLI；非法相对路径被生成可导航 URI | scan/check 四格式接通，非法路径只保留属性证据 |
| 基线分类未输出 | 增量检查退出判定存在，但用户无法看到 new/existing/worsened/resolved | 保留全部诊断，附派生分类及迁移说明 |
| 未知字段未完全拒绝 | 详细报告及基线成员的未知字段被静默忽略 | 补白名单及各层反例测试 |
| 解包验收选旧包 | 当前 HEAD 3cdc9d4 实际验证旧 9149176 归档 | 按版本/平台/HEAD 精确选包，核对内部 SHA-256 和运行版本 |
| ZIP/文档/保留期 | DOS 日期非标准、包中 README 链接缺文档、最终验收日志仅保留 30 天 | 标准 ZIP 日期，包含使用文档/样例，最终证据保留 90 天 |

上述均是原计划的必要关联修复；没有扩展自动改名、压缩包内容检查、网页、内容哈希或 Unicode 等价等产品范围。归档中的 SHA-256 是发布校验，不是扫描用户文件内容。

独立审查分别覆盖 MoonBit 产品和 host/候选交付；修复有针对性双目标/CLI/归档回归。旧 v1 核心 model/audit/manifest/report/rules 实现与基线无产品行为差异。最终验证和发布身份见下面的追加记录，不能以本段代替最新 CI。

## 验收矩阵

| 原目标 | 具体证据入口 |
| --- | --- |
| 可解释规则/全量来源 | rules/explain、详细诊断成员与计数、示例上限及旧 API 消费 |
| 配置与范围 | scope/pattern 测试、真实目录剪枝、隐含目录、scan/check 一致、非法路径保留 |
| Snapshot/Diff | 往返与唯一排序、不完整状态继承、范围内变化、大小写一对一及 0/1/2/3 退出 |
| Baseline | 完整报告门禁、版本/范围绑定、四分类、增加成员/次数恶化、扫描失败优先 3 |
| CI 报告 | scan/check 四格式、diff 三格式、SARIF 位置安全、artifact 与摘要；不声明 Code Scanning 已接收 |
| 可安装交付 | 项目隔离工具链、精确版本下载哈希、双平台 CI、旧库消费、标准 reader 解包、无编译器 CLI 全命令 smoke |
| 规模与代码量 | code-stats 有效行口径、十万普通/冲突输入、深路径/长前缀/大组、耗时/RSS/报告体积 |

## 与十月官方要求对照

2026-10-01 实时核对 [官方十月页面](https://moonbitlang.github.io/Hackathon2026/)：MoonBit 为主要实现语言；公开可追溯开发；可运行说明/示例/测试；已有项目需本期实质新增；开源许可证；参赛者能够解释 AI 辅助成果。十月报名与验收截止为 10 月 31 日。

当前成果具备相应技术材料及十月实质新增提交；本文与发布记录可以支持申报。官方资格审核、报名提交、入群/队伍信息和最终验收由赛事组织者处理，不能由自动测试或发布动作替代。本轮只获正式发布授权，没有自动提交报名。

## 实际限制

固定 portable-windows-v1 和 ASCII 大小写范围；不承诺完整 Unicode 等价、长路径及全部文件系统兼容。目录扫描非原子快照，不跟随链接，不读取被扫描文件内容。性能数字是具体机器观测；本项目不是实时 Windows 文件操作成功保证，也不是自动改名工具。

## 发布验证记录

正式版本为 0.2.0，版本号在 moon.mod、package.json 和 SARIF 元数据中保持一致。发布分支 `codex/release-v0.2.0` 已经由 PR #2 保留提交合并；正式发行、Mooncakes 构建和注册表消费均已验证，具体身份与结果见下面的最终记录。

### 本地发布验收

- `pwsh -File run_acceptance.ps1` 完整成功，证据为 `artifacts/acceptance-win32-2026-10-01T06-30-29-606Z/evidence.json`。checks/demo/benchmark/consumer/package/unpack/toolchain 全部退出 0。该验收在提交前工作树运行，`source_commit` 仍为原 main，修改身份由同目录 source-manifest 哈希清单固定；最终公开 CI 将绑定实际发布 SHA。
- MoonBit JS/wasm-gc 各 101/101；Node 产品测试 52 项（Windows 50 通过、2 POSIX 专用跳过），工程测试 25 项（24 通过、1 POSIX 专用跳过）。独立 v1 库消费者通过；跨目标序列化输出逐字节相同，性质测试 60 轮（其中基线稳定性 20 轮），五个规模案例均通过。
- 有效代码 6,493 行（MoonBit 产品 3,570、Node 产品 321、MoonBit 测试 1,640、Node 测试 962），排除工程脚本/文档/生成文件/展开数据，超过内部计划 3,000 行门槛。大型单组重复案例为 10,000 条，原账本部分“10 万次单组”文字不准确；另有普通与分组冲突两种 100,000 条案例。
- 归档经标准 .NET ZIP reader 实际读取；默认解包严格选择当前身份、核验内部校验和，并在无编译器 PATH 下运行全部公开 CLI 命令。发布后还需从远端下载实际发行物再验证。
- Mooncakes dry-run 已校验打包源码及解包后的 `moon check`，服务器明确返回 202 和“未更改、dry-run 成功”；当前 moon CLI 却以非零退出并打印 failed，故只记录服务器验证结果，不把此非零码当作正式发布成功。正式发布以注册表 manifest 与全新消费项目安装结果为准。
- 最终独立 reviewer 已确认产品修改无阻塞；文档中两处过期说明已修正。原始阶段历史保留，当前说明不伪造早期审查或测试结果。

### 最终公开发布结果

**已正式发布 MoonPortCheck v0.2.0。** 此追加记录发生在发布后，只补文档，不改变 tag、发行物或产品代码。

- 发布源码 SHA：`b7cda70b8da20dab525cba7317d54881e53e4262`；修复提交 `2cd633e375c6d439c1636990b221ffb1da046718`。
- [PR #2](https://github.com/AlexenderSokolov/moonportcheck/pull/2) 已 merge；[发布分支 CI 36825431382](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36825431382) 与 [合并提交 CI 36825672273](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36825672273) 的 Windows/Linux job 均成功。`v0.2.0` 的解引用 tag SHA 与上述发布源码一致。
- CI 下载回来的两平台验收 evidence 均 `passed:true`；93 份源码哈希与发布 SHA 匹配，允许 LF/CRLF 差异。Windows 元数据的 `source_state=modified_worktree` 来自检查过程产生的行尾状态，并不是另一个实现；逐文件源码核验已排除内容漂移，Linux 为 committed_clean。
- [GitHub 正式 Release](https://github.com/AlexenderSokolov/moonportcheck/releases/tag/v0.2.0)：`isDraft=false`、`isPrerelease=false`；提供两个平台 CLI ZIP、SHA256SUMS 及 Windows/Linux 验收元数据。下载自最终 CI 的实际归档通过内部 SHA-256、标准 .NET ZIP reader（24 个条目）和无编译器 CLI 全公开命令 smoke；上传后 GitHub 资产 digest 与本地文件哈希一致。
- [Mooncakes](https://mooncakes.io/docs/AlexenderSokolov/moonportcheck) 正式上传返回 200、CLI 退出 0；[manifest](https://mooncakes.io/api/v0/manifest/AlexenderSokolov/moonportcheck) 确认 `version=latest_version=0.2.0`、`build_status=success`、`has_package=true`、`yanked=false`。
- 新消费项目通过 `moon add AlexenderSokolov/moonportcheck@0.2.0` 从公共注册表下载，自己的 `moon.work` 仅包含 `.`，不引用本地源仓库；`moon check` / `moon run` 实际调用原 schema 1、新 schema 2 及 baseline API 均通过。证据 `artifacts/registry-consumer-knicV7/evidence.json`，消费者与验证命令保留在本机，未上传私密本地路径。

| 正式 CLI 归档 | SHA-256 |
| --- | --- |
| moonportcheck-0.2.0-win32-b7cda70.zip | `a48feee19bf481d72de1ed691c5ab83294f98c07c7feb5a08a35f96d5af361d7` |
| moonportcheck-0.2.0-linux-b7cda70.zip | `5df78a2daeed323053a3826e0abead98c55a7f4a173a1c43821040aebb28cc93` |

达到本轮既定功能与工程发布门槛；具备官方十月要求的技术材料。官方报名、资格审核、个人对成果的理解说明与最终赛事验收未代办，也未宣称已通过。
