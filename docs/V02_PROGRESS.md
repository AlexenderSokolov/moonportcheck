# MoonPortCheck v0.2 执行账本

## 计划身份与当前授权

- 计划：`moonportcheck-v0.2-16-milestones`，完整保存于 [V02_PLAN.md](V02_PLAN.md)。
- 来源：用户于 2026-09-26 明确发送 `PLEASE IMPLEMENT THIS PLAN` 的 v0.2 计划；用户原始消息是执行范围和语义的最终依据。
- 当前授权：创建公开仓库 `AlexenderSokolov/moonportcheck`、逐次 commit/push、建立并持续更新 Draft PR，以及最终独立审查通过后以 merge commit 保留全部提交合并。
- 尚未授权：正式发布、Mooncakes 上传和赛事报名。公开开发授权不等于这些操作获准。
- 执行边界：只实施本项目计划，保留已有改动；不删除文件，不重写历史，不倒拆提交，不改开发日期，不 force-push，不 squash。
- 兼容原则：保持 v1 库接口和行为，CLI v0.2 审计 JSON 显式采用 schema 2；规则、退出码和完整性语义按计划验收。
- 历史说明：v0.1 文档中的“未授权提交／远端”描述当时状态；本轮明确授权以上述用户消息为准。

M01 已保存并推送真实 v0.1 基线。首次公开 CI 的 Windows 验收通过，Linux 因官方归档缺少 ELF 执行权限而失败；按批准计划先推进 M02 修复。该历史失败保留，不能改记为双平台通过。

## 执行协议

每个里程碑按“实现及对应测试 → 本地检查 → 审查差异 → commit → 立即 push → 核对该 SHA 的 Windows/Linux CI → 下一里程碑”推进。

第 1 次提交保存真实 v0.1，建立 `main`；第 2–16 次提交进入 `codex/october-v0.2` 的同一个持续 Draft PR。执行创建前重新核实目标账号、仓库存在性与来源，不能覆盖后来出现的仓库。

CI 失败先修复，再增加功能；必要修复另记提交，因此实际提交数可以超过 16。首次基线 CI 如暴露已知工具链问题，下一步只推进修复。每个提交记录实际 SHA 与对应 CI 链接，不把另一 SHA 或仅本地通过的结果当作该提交的公开验收。合并前独立审查，合并后再核验主分支 CI。

当前提交自身的 SHA 只能在提交后取得：可以记录在随后账本更新或 GitHub 记录中，不为补写 SHA 而修改已公开历史。

## 里程碑状态

状态只使用 `pending`、`in_progress`、`blocked`、`complete`。`complete` 需要对应本地检查、推送和精确 SHA 的 CI 证据；M01 适用用户批准的首次基线安装失败例外，其失败明确保留且已由 M02 的双平台成功解除阻塞。后续里程碑必须 CI 通过再继续；阻塞时记录原因与可继续事项。

| 里程碑 | 状态 | 交付内容 | 提交 SHA | Windows/Linux CI | 验证记录 |
| --- | --- | --- | --- | --- | --- |
| M01 | complete | 真实 v0.1 基线与公开仓库 | `34ab2b42587addb0f0d921e00ed576d85bc6ba13` | [36214029069](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36214029069)：Windows 通过，Linux EACCES | 双平台本地通过；按计划由 M02 修复公开 CI 安装问题 |
| M02 | complete | 固定下载、验收元数据、接口与统计门禁 | `6b9b65d9e69e36d0449780bb4188d37c898fa932` | [36214982370](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36214982370)：两系统通过 | 双系统空缓存冷安装、完整验收与工程回归通过，修复 M01 Linux 安装阻塞 |
| M03 | complete | 规则目录与 `rules/explain` | `0880a08de9db501e756a2e1fe32b52b420938b96` | [36215499117](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36215499117)：两系统通过 | 27项核心测试/目标、全规则查询、未知编号失败、25份跨目标比对及旧消费者 |
| M04 | complete | 详细诊断、来源证据、schema 2 | `10a65668d83e431bbd9c3eff14cb84276612371f` | [36216177182](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36216177182)：两系统通过 | 38项核心/目标，49份跨目标输出，旧消费者及十万规模通过 |
| M05 | complete | MoonBit 路径匹配器 | `7c2adb21c5a0e0077f1287a06e7d466bd7f17ed2` | [36216679371](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36216679371)：Windows/Linux 均通过（2026-10-01 联网核对该 SHA 的两个 job 均为 success） | 核心测试 JS/wasm-gc 各 51/51，Windows 全套检查通过，61 份新旧输出逐字节一致（含 12 组匹配），独立递归解释器核对，深路径/长前缀/重复星号通过 |
| M06 | complete | 配置、排除与扫描剪枝 | `5c6f674d61188715f7b024b803021dd10315df43` | [36804146762](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36804146762)：Windows/Linux 均通过（2026-10-01 联网核对该 SHA 的两个 job 均为 success） | scan/check 范围一致、排除计数可信；双平台自动验收通过，获用户授权后 commit+push 并核验 CI |
| M07 | complete | Snapshot 模型、解析和序列化 | `7d4566b31d76a8a2dbf7f734e850006660d78249` | [36810508887](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36810508887)：Windows/Linux 均通过（2026-10-01 联网核对该 SHA 的两个 job 均为 success） | 往返一致、排序稳定、损坏输入拒绝；获用户授权后 commit+push 并核验 CI |
| M08 | complete | Snapshot 命令与 check 快照支持 | `fbbd44adc62ad27a4247d9c83d84a936fe01381a` | [36811966576](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36811966576)：Windows/Linux 均通过（2026-10-01 联网核对该 SHA 的两个 job 均为 success） | 固定 JSON 快照文档；check 继承范围、额外排除只能缩小、不完整始终不完整；获用户授权后 commit+push 并核验 CI |
| M09 | complete | SnapshotDiff 核心与报告 | `ea6ee3ded486e75567c8f2c86169116783974ff4` | [36812671506](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36812671506)：Windows/Linux 均通过（2026-10-01 联网核对该 SHA 的两个 job 均为 success） | 新增/移除/类型/大小写；先精确匹配再 ASCII 折叠、一对一且类型相同才标大小写；范围不同拒绝；用户已全局授权后 commit+push 并核验 CI |
| M10 | complete | `diff` 命令与退出语义 | `442905a2eebb25269fdfd455d87113af87a103e0` | [36813476583](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36813476583)：Windows/Linux 均通过（2026-10-01 联网核对该 SHA 的两个 job 均为 success） | 退出 0/1/2/3；范围不同与文档损坏 2、不完整输入 3、无变化 0、有变化 1；text/json；用户已全局授权后 commit+push 并核验 CI |
| M11 | complete | Baseline 模型及分类核心 | `e6bac9fb8d994a93c933df6b3773fa71ba542aeb` | [36814438312](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36814438312)：Windows/Linux 均通过（2026-10-01 联网核对该 SHA 的两个 job 均为 success） | 只从完整 schema2 报告建基线；new/existing/worsened/resolved；成员与次数多重集比较；用户已全局授权后 commit+push 并核验 CI |
| M07 | pending | Snapshot 模型与序列化 | — | — | 往返、稳定排序、损坏输入 |
| M08 | pending | snapshot CLI 与快照检查 | — | — | 真实导出、完整性继承 |
| M09 | pending | SnapshotDiff 核心与报告 | — | — | 新增、移除、类型、大小写变化 |
| M10 | pending | diff CLI 与退出语义 | — | — | 范围拒绝、不完整退出 3、中期 LOC |
| M11 | pending | Baseline 模型与分类核心 | — | — | 身份、新成员、次数增加 |
| M12 | pending | 基线创建与增量判定 | — | — | 旧问题可见、新增或恶化失败 |
| M13 | pending | SARIF 与 Markdown 渲染 | — | — | 格式、路径编码、完整性 |
| M14 | pending | 新格式 CLI 与 Actions 摘要 | — | — | 格式结论一致、报告可获取 |
| M15 | pending | 交叉／性质测试与规模验收 | — | — | 双目标、深路径、大组、LOC 门禁 |
| M16 | pending | v0.2 候选包、文档与完整验收 | — | — | 双系统解包、独立消费、精确 SHA CI |

## 代码量与证据口径

最终门禁为产品源码加有效测试超过 3,000 行，预计约 3,200–4,000 行。排除空行、纯注释、文档、配置、工程脚本、生成文件、依赖及展开的测试数据；MoonBit 产品代码、Node 产品代码和测试分别统计。M10 记录中期统计，M15 建立最终门禁，禁止通过拆行、重复数据或无意义测试充数。

本地验收、公开 CI、候选包生成、正式发布、Mooncakes 验证和赛事验收分别记录，不能相互替代。常规 CI 证据保留 30 天，最终候选证据保留 90 天。最终记录基线到候选版的新增功能、代码量、实际工具链、提交 SHA、Actions run URL、独立审查结论和剩余限制。

## 追加记录

### 2026-09-26：建立计划与执行账本

- 用户已批准完整 v0.2 实施计划；创建本计划文件和执行账本，作为真实 v0.1 基线提交中的后续开发计划。
- 当前阶段为 M01 准备；M02–M16 尚未开始。
- M01 新的 Windows 本地验收通过，保留记录为 `artifacts/acceptance-win32-2026-09-26T03-05-52-852Z`；Linux 本地验收通过，保留记录为 `artifacts/acceptance-linux-2026-09-26T03-06-59-008Z`。
- 目标公开仓库已创建：<https://github.com/AlexenderSokolov/moonportcheck>。首次 commit/push 和公开 CI 仍为 pending，M01 不得记为 complete。
- 本条记录不声明新增 v0.2 产品功能或公开 CI 已完成。
- 后续每条记录说明里程碑、实际改动、本地验证、提交／推送结果、精确 SHA 的双系统 CI、问题与处理。若发生计划偏差，应保留原决策并说明依据，不能静默扩大范围。

### 2026-09-26：M01 公开基线与 M02 安装修复

- M01 实际提交并推送 `34ab2b42587addb0f0d921e00ed576d85bc6ba13`；首次公开 CI [36214029069](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36214029069) 中 Windows 通过，Linux 在 `moonc` 处报 `EACCES`。官方 Linux tar 将原生工具存为 `0664`，WSL 的 Windows 挂载权限仿真掩盖了旧本地验收中的问题。
- M02 保留原 SHA，将下载地址固定到完整版本；校验两份归档后，只对安装目录 `bin` 中普通 ELF 文件恢复执行权限，不跟随链接。
- 双系统全新 home/cache 冷安装成功：`artifacts/cold-install-windows-x86_64-OSum1q/evidence.json`、`artifacts/cold-install-linux-x86_64-sj4p4B/evidence.json`。4 份归档 hash 一致，Node `24.15.0`，`moonc v0.10.14+7d59c7ec9`，三个 core 目标均构建成功。
- 工程回归包括错误 binary/core hash 拒绝、显式安装路径、原生 Linux 执行权限、动态版本/执行身份、代码统计。独立审查发现并修复消费测试的相对工具链路径，代码统计的正则字面量回归同步处理。
- API 漂移检查纳入每次检查；统计排除生成文件、工程脚本、文档、配置和展开数据。M02 产品与有效测试基准为 1,202 行（MoonBit 产品 553、Node 产品 167、MoonBit 测试 208、Node 测试 274）；工程回归本身不计入产品规模。
- M02 完整本地验收通过：Windows `artifacts/acceptance-win32-2026-09-26T03-25-50-745Z/evidence.json`，Linux `artifacts/acceptance-linux-2026-09-26T03-28-25-827Z/evidence.json`；均使用前述冷安装 home。工程测试、21 项核心测试（双目标）、Node CLI/host、23 组报告逐字节比对、三组演示、十万规模和独立消费均通过。Windows 跳过 POSIX 专用项；Linux 全部执行。修复后的统计回归 7/7 通过。

### 2026-09-26：M02 精确提交公开验收通过，开始 M03

- M02 提交 `6b9b65d9e69e36d0449780bb4188d37c898fa932` 已立即推送；[Draft PR #1](https://github.com/AlexenderSokolov/moonportcheck/pull/1) 建立并关联本任务。
- 对应 [CI 36214982370](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36214982370) 双系统通过：Linux 32 秒，Windows 51 秒。每个 runner 均执行空缓存冷安装、完整验收并上传证据。
- M01 的原始 Linux CI 失败记录保留；阻塞由 M02 修复，不将旧 SHA 的结果改写为成功。
- M03 新增 MoonBit 规则目录与 rules/explain CLI；先运行 CLI 回归确认两个功能用例失败，再接入实现。检查规则和 v1 报告行为保持原样。
- M03 本地验证：核心 JS/wasm-gc 各 27/27；完整 Windows run_check 通过，Node 20 通过/2 POSIX 跳过；25 份报告/规则输出跨目标逐字节一致。旧公共接口消费者继续通过。API 门禁已实际拒绝未记录的新 RuleInfo 接口，审查并暂存接口后通过。证据日志 `artifacts/m03-check-windows.log` 与 `artifacts/m03-consumer.json`。公开 CI 待本次提交推送后核对。

### 2026-09-26：M03 公开验收通过，开始 M04

- M03 `0880a08de9db501e756a2e1fe32b52b420938b96` 对应 [CI 36215499117](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36215499117) 的 Windows/Linux 均通过，方进入 M04。
- M04 设计经独立审查：单路径身份使用原始路径，集合冲突身份使用折叠后的完整前缀；来源关联原始 `(path,kind)` 及次数，不虚构隐含目录输入。样例优先覆盖冲突两侧，再补足最多5条；完整机器成员不截断。
- 复杂度按实际输入与输出规模解释：完整来源可随冲突前缀数增长，样例限制不代表机器报告体积被限制。实现按索引补证据，避免逐诊断重新全扫输入。
- CLI schema2 回归先确认旧实现失败（schema1 != 2），随后实施桥接迁移。旧库 API 仍输出 schema1，独立消费者继续验证。
- M04 完整验收通过：`artifacts/acceptance-win32-2026-09-26T03-52-05-617Z/evidence.json`。38项核心测试/目标，23项Node测试（Windows21通过/2 POSIX跳过），49份输出跨目标一致，十万正常/冲突输入、三组演示及旧库消费者通过；独立只读审查无阻塞项。元数据升为0.2.0-dev，尚未正式发布。新增接口均经过生成差异审查，原v1公共声明无变更。

### 2026-09-26：M04 公开验收通过，开始 M05

- M04 `10a65668d83e431bbd9c3eff14cb84276612371f` 的 [CI 36216177182](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36216177182) 两系统成功。
- M05 实现纯 MoonBit 排除模式匹配器，固定大小写、Unicode字符、整段双星与目录子树语义；结构非法路径不可通过排除隐藏。另以独立递归解释器核对84个短路径与15种模式组合，生产实现采用迭代状态推进。
- M05 有效RED后，JS/wasm-gc 各51/51核心测试通过；Windows整套run_check通过，61份新旧输出逐字节一致（含12组匹配输出）。独立只读审查未发现缺陷。5,000段深路径、512字符共同前缀、128个重复星号片段通过。记录 `artifacts/m05-check-windows.log`。
- 模式 AST 字段显式私有；同时将 AuditOptions 的 sample_limit 标为私有，落实 M04 已约定的不透明接口，旧v1接口未动。

### 2026-10-01：M06 完成——配置化排除与扫描剪枝（远端 CI 已核验）

- M06 交付「配置化排除与扫描剪枝」。纯 MoonBit 新增 `parse_scope` / `entry_excluded` / `effective_scope_patterns` / `audit_with_exclusions`（scope.mbt），桥接新增 `scope`、`excluded` 两个模式并为 `check`/`scan` 接入 `exclude_patterns`，Node host 新增 `--config`/`--exclude` 参数、`readConfig` 与扫描剪枝谓词，CLI 接线并在报告带上范围。
- 明确语义：配置 `exclude` 与重复 `--exclude` 取并集，按精确拼写去重并按 ordinal 排序为 `scope`；`excluded_entries` 只统计已知输入中实际匹配的条目，不估算未遍历子树；`pruned_directories` 只报告**最顶层**被剪枝目录（祖先已被整棵排除者不再列出），因此扫描与等价清单在相同排除下得到相同 `scope`/诊断/`summary`/`pruned_directories`；绝不隐式读取 `.gitignore`；结构非法路径永远不会被排除。
- 错误语义：配置结构错误（非法 JSON、非对象、`schema_version`≠1、未知字段）→ `INPUT_CONFIG` 退出 `2`；配置/命令行非法模式 → `PATTERN_INVALID` 退出 `2`；配置无法读取 → `INPUT_IO_ERROR` 退出 `3`；非法 UTF-8 → `INPUT_ENCODING` 退出 `2`；扫描不完整仍退出 `3`，不被排除豁免。
- 本地验证（Windows，2026-10-01）：核心测试 JS/wasm-gc 各 66/66；完整 run_check 通过（工具链 moon 0.1.20260920 / moonc v0.10.14+7d59c7ec9 / node v24.15.0，API 门禁通过，Node 测试 30 通过/2 POSIX 跳过，65 份跨目标输出逐字节一致，含 4 份排除报告）。代码量 total 3237 行（moonbit 1595、node 231、tests_moonbit 909、tests_node 502）。完整验收 `artifacts/acceptance-win32-2026-10-01T01-33-22-451Z/evidence.json` 为 `passed: true`；本机无 pwsh(PowerShell 7)，验收以 `powershell.exe` 等价调用 run_check 的临时方式运行并已还原脚本，验收脚本因而不在本次差异中。
- 独立只读审查（2026-10-01，独立子代理）：结论 **APPROVED-WITH-NOTES，无必改项**。核验约束全部满足：HEAD 仍为 M05 无 M06 提交、仅 `pkg.generated.mbti` 暂存、无删除/改史/强制操作；排除/剪枝/错误码/桥接/端口/文档语义与代码一致，M06 保持 in_progress 且未作任何远端 CI 断言。两条低危提示已修复并补测：N1 `explain` 模式同样拒绝 `--config`/`--exclude`；N2 scope 预检遵循 `--format`（text 模式下配置/stderr 错误以文本输出）。
- **远端验收已完成**：获用户明确授权后，M06 以 `5c6f674d61188715f7b024b803021dd10315df43` 提交并推送至 `codex/october-v0.2`（Draft PR #1）；公开 CI [36804146762](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36804146762) 的 windows-latest 与 ubuntu-24.04 两个 job 均 success（各自 Acceptance 步骤通过）。M06 由此记为 `complete`，可进入 M07。

### 2026-10-01：M07 完成——Snapshot 模型、解析和序列化（远端 CI 已核验）

- M07 交付「快照模型、解析和序列化」。新增 snapshot.mbt：`Snapshot`（profile/complete/scope/entries/scan_issues）、`build_snapshot`（重复折叠、冲突类型拒绝、范围规范化、无扫描问题则 complete）、`parse_snapshot`（只接受规范文档：格式/版本匹配、仅已知字段、entries 严格递增且唯一、损坏/非规范一律拒绝）、`render_snapshot_json`（固定字段顺序确定性输出，往返一致）。快照绝不保存内容、时间戳或主机绝对路径；`parse_manifest` 依旧只解析数组清单。
- 验证（Windows，2026-10-01）：核心测试增加到 JS/wasm-gc 各 **73/73**（新增 7 项快照测试：规范化、扫描问题排序与完整度、冲突类型/非法模式、往返一致、空快照、Unicode/大小写、损坏与非规范输入表）；完整 run_check 通过（API 门禁通过、node 测试通过、parity **67** 份跨目标逐字节一致含 2 份快照 fixture、代码量 total **3688** 行 >3000）。记录 `artifacts/m07-runcheck.out`。
- **远端验收已完成**：获用户明确授权后，M07 以 `7d4566b31d76a8a2dbf7f734e850006660d78249` 提交并推送至 `codex/october-v0.2`（Draft PR #1）；公开 CI [36810508887](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36810508887) 的 windows-latest 与 ubuntu-24.04 两个 job 均 success（各自 Acceptance 步骤通过）。M07 由此记为 `complete`，可进入 M08。

### 2026-10-01：M08 完成——Snapshot 命令与 check 快照支持（远端 CI 已核验）

- M08 交付「Snapshot 命令与 check 快照支持」。新增根包 `audit_snapshot(snapshot, extra_scope)`：继承快照范围、额外排除只缩小、快照 scan_issues 原样带入（不完整始终不完整）、`source="snapshot"`、profile 不匹配拒绝；桥接新增 `snapshot` 模式（完整导出退出 0、不完整退出 3），`check` 模式按顶层 JSON 值分类（数组=原清单、对象=快照经 audit_snapshot、其他=INPUT_SCHEMA）；host 参数解析接受 `snapshot`（target 必填、拒绝 `--format`、允许 config/exclude），bin 提供 `moonportcheck snapshot ROOT`。
- 验证（Windows，2026-10-01）：核心测试增加到 JS/wasm-gc 各 **75/75**（新增 2 项 audit_snapshot 单测）；新增 bridge 测试（snapshot 模式、check 继承/收缩/报告/坏 profile）与 CLI 端到端测试（导出→再检入、不完整快照 exit 3、`--format` 拒绝）；完整 run_check 通过（API 门禁通过、node 测试通过、parity **68** 份跨目标逐字节一致含 audit_snapshot fixture、代码量 total **3977** 行 >3000）。记录 `artifacts/m08-runcheck.out`。
- **远端验收已完成**：获用户明确授权后，M08 以 `fbbd44adc62ad27a4247d9c83d84a936fe01381a` 提交并推送至 `codex/october-v0.2`（Draft PR #1）；公开 CI [36811966576](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36811966576) 的 windows-latest 与 ubuntu-24.04 两个 job 均 success（各自 Acceptance 步骤通过）。M08 由此记为 `complete`，可进入 M09。

### 2026-10-01：M09 本地实现与验证（远端 CI 待核验）

- 自本里程碑起，用户已给予「提交代码明确授权，不再逐一询问」的全局授权（2026-10-01 记录于用户偏好），commit/push/CI 直接执行；仍禁 force-push/squash/改史/删文件，合并另行授权。
- M09 交付「SnapshotDiff 核心与报告」。新增 diff.mbt：`DiffKind`（added/removed/kind/case）、`SnapshotChange`、`SnapshotDiff`、`diff_snapshots`（范围逐项相同否则 INPUT_SCHEMA；先精确路径匹配，类型不同记 kind；剩余条目按 ASCII 折叠、仅一对一且类型相同记 case 且不推测重命名；按 kind 序+路径 ordinal 稳定排序）、`render_snapshot_diff_json`（固定 `{"format":"moonportcheck-diff","version":1,"complete":...,"changes":[...]}`，complete=两份输入的完整度取与）。
- 验证（Windows，2026-10-01）：核心测试增加到 JS/wasm-gc 各 **81/81**（新增 6 项 diff 测试：相同快照零变化、增删与类型变更排序、一对一大小写、类型不同/多义折叠不标 case、范围不一致拒绝+完整度继承、渲染字节稳定）；完整 run_check 通过（API 门禁通过、node 测试通过、parity **69** 份跨目标逐字节一致含 diff fixture、代码量 total **4287** 行 >3000）。记录 `artifacts/m09-runcheck.out`。
- **远端验证待核验**：M09 将提交并 push 至 `codex/october-v0.2`，随后核对该 SHA 的双平台 CI；通过后置 complete 进 M10。

### 2026-10-01：M09 完成——SnapshotDiff 核心与报告（远端 CI 已核验）

- M09 交付「SnapshotDiff 核心与报告」，实现同上条目。新增 diff.mbt 约 240 行、diff_test.mbt 6 项测试。
- 验证（Windows，2026-10-01）：核心测试 **81/81**×2 双目标；完整 run_check 通过（API 门禁、node 测试、parity **69** 份逐字节一致含 diff fixture、代码量 **4287** 行 >3000）；本机 acceptance `passed:true`（证据 acceptance-win32-2026-10-01T03-52-51-985Z/evidence.json）。
- **远端验收已完成**：基于用户的全局提交授权（2026-10-01），M09 以 `ea6ee3ded486e75567c8f2c86169116783974ff4` 提交并推送至 `codex/october-v0.2`（Draft PR #1）；公开 CI [36812671506](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36812671506) 的 windows-latest 与 ubuntu-24.04 两个 job 均 success（各自 Acceptance 步骤通过）。M09 由此记为 `complete`，可进入 M10。

### 2026-10-01：M10 本地实现与验证（远端 CI 待核验）

- M10 交付「diff 命令与退出语义」。新增根包 `render_snapshot_diff_text`（不完整输入首行标注 INCOMPLETE，变化行 `+/-/~` 符号）；桥接新增 `diff` 模式（解析两份快照→diff_snapshots→按 format 输出 json 文档或文本；退出码 2=损坏/范围不同、3=任一不完整、1=有变化、0=无变化）；host 参数解析接受 `diff`（恰好两个快照路径、拒绝 config/exclude、允许 text/json），bin 提供 `moonportcheck diff BEFORE.json AFTER.json`。
- 验证（Windows，2026-10-01）：核心测试增加到 JS/wasm-gc 各 **82/82**（+1 文本渲染）；新增 bridge 测试（diff 退出码 0/1/2/3、文本输出、损坏/数组输入拒绝）与 CLI 端到端测试（diff 全退出码、文本输出、坏参数）；完整 run_check 通过（API 门禁、node 测试、parity **69**、代码量 **4474** 行 >3000）；本机 acceptance `passed:true`（证据 acceptance-win32-2026-10-01T04-03-08-969Z/evidence.json）。记录 `artifacts/m10-runcheck.out`。
- **远端验证待核验**：M10 将提交并 push 至 `codex/october-v0.2`，随后核对该 SHA 的双平台 CI；通过后置 complete 进 M11。

### 2026-10-01：M10 完成——diff 命令与退出语义（远端 CI 已核验）

- M10 交付「diff 命令与退出语义」，实现同上条目。
- 验证（Windows，2026-10-01）：核心测试 **82/82**×2 双目标；完整 run_check 通过（API 门禁、node 测试、parity **69**、代码量 **4474** 行 >3000）；本机 acceptance `passed:true`（证据 acceptance-win32-2026-10-01T04-03-08-969Z/evidence.json）。
- **远端验收已完成**：基于用户的全局提交授权（2026-10-01），M10 以 `442905a2eebb25269fdfd455d87113af87a103e0` 提交并推送至 `codex/october-v0.2`（Draft PR #1）；公开 CI [36813476583](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36813476583) 的 windows-latest 与 ubuntu-24.04 两个 job 均 success（各自 Acceptance 步骤通过）。M10 由此记为 `complete`，可进入 M11。

### 2026-10-01：M11 本地实现与验证（远端 CI 待核验）

- M11 交付「Baseline 模型及分类核心」。新增 baseline.mbt：`BaselineStatus`/`BaselineGroup`/`Baseline`/`BaselineChange`/`BaselineDiff`、`rules_version()`、`build_baseline`（仅接受完整 schema 2 报告，否则 INPUT_SCHEMA/INPUT_INCOMPLETE；绑定 profile、规则版本与有效范围）、`diff_with_baseline`（按 code+anchor 关联同组，成员路径/类型与次数按多重集比较：整组消失→resolved、新增成员或次数上升→worsened、其余→existing、无基线组→new；按状态序+code/anchor 稳定排序）与 `render_baseline_json`/`render_baseline_diff_json`/`render_baseline_diff_text`。parity 增加基线 fixture 至 **71** 份。
- 验证（Windows，2026-10-01）：核心测试增加到 JS/wasm-gc 各 **87/87**（新增 5 项 baseline 测试：非完整/非 schema2 拒绝、profile/规则版本/范围绑定与组成员、existing/resolved 分类、worsened/new 分类、渲染字节稳定）；完整 run_check 通过（API 门禁、node 测试、parity **71** 逐字节一致、代码量 **4869** 行 >3000）；本机 acceptance `passed:true`（证据 acceptance-win32-2026-10-01T04-16-28-035Z/evidence.json）。记录 `artifacts/m11-runcheck.out`。
- **远端验证待核验**：M11 将提交并 push 至 `codex/october-v0.2`，随后核对该 SHA 的双平台 CI；通过后置 complete 进 M12（baseline create 命令与 scan --baseline --fail-on）。

### 2026-10-01：M11 完成——Baseline 模型及分类核心（远端 CI 已核验）

- M11 交付「Baseline 模型及分类核心」，实现同上条目。新增 baseline.mbt 约 330 行、baseline_test.mbt 5 项测试。
- 验证（Windows，2026-10-01）：核心测试 **87/87**×2 双目标；完整 run_check 通过（API 门禁、node 测试、parity **71** 逐字节一致含基线 fixture、代码量 **4869** 行 >3000）；本机 acceptance `passed:true`（证据 acceptance-win32-2026-10-01T04-16-28-035Z/evidence.json）。
- **远端验收已完成**：基于用户的全局提交授权（2026-10-01），M11 以 `e6bac9fb8d994a93c933df6b3773fa71ba542aeb` 提交并推送至 `codex/october-v0.2`（Draft PR #1）；公开 CI [36814438312](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36814438312) 的 windows-latest 与 ubuntu-24.04 两个 job 均 success（各自 Acceptance 步骤通过）。M11 由此记为 `complete`，可进入 M12。
