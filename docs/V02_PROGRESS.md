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

状态只使用 `pending`、`in_progress`、`blocked`、`complete`。`complete` 需要对应本地检查、推送和精确 SHA 的 CI 证据；阻塞时记录实际原因与可继续事项。

| 里程碑 | 状态 | 交付内容 | 提交 SHA | Windows/Linux CI | 验证记录 |
| --- | --- | --- | --- | --- | --- |
| M01 | blocked | 真实 v0.1 基线与公开仓库 | `34ab2b42587addb0f0d921e00ed576d85bc6ba13` | [36214029069](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/36214029069)：Windows 通过，Linux EACCES | 双平台本地通过；按计划由 M02 修复公开 CI 安装问题 |
| M02 | in_progress | 固定下载、验收元数据、接口与统计门禁 | 待提交 | 待推送 | 双系统冷安装通过；错误哈希拒绝、版本一致性测试通过；完整验收进行中 |
| M03 | pending | 规则目录与 `rules/explain` | — | — | 全规则查询与未知编号失败 |
| M04 | pending | 详细诊断、来源证据、schema 2 | — | — | 隐含目录追溯、稳定分组、旧 API |
| M05 | pending | MoonBit 路径匹配器 | — | — | 通配符、Unicode、无效模式 |
| M06 | pending | 配置、排除与扫描剪枝 | — | — | scan/check 范围一致、排除计数 |
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
