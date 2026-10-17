# MoonPortCheck 项目复用说明

## 已交付阶段与边界

v0.2.0于2026-10-01发布；2026-10-16本地完成交付核心；2026-10-17补齐独立步骤/字节验证、外部消费者、源码身份与复现后正式发布v0.3.0。源码7932269，公开双平台CI39007654147，GitHub及Mooncakes正式发行、独立注册表消费均已验证；未重新报名。详见docs/RELEASE_AUDIT_2026-10-17.md。本卡片不把工程发布等同赛事通过。最小阅读顺序：PROJECT.md→docs/DELIVERY.md→docs/V03_ACCEPTANCE.md→需要的delivery_*模块。

## 结构与数据流

Node读取Spec及显式snapshot文件→delivery_codec严格解析与canonical basis→delivery_planner按初态身份和目标槽调度→delivery_audit独立重放gate→JSON/text/Markdown。旧路径/glob/diff/baseline保持独立兼容。多个来源是调用方声明的逻辑命名空间；源码只读取输入，没有真实Copy/Move/Mkdir执行器。

| 模块 | 输入与输出 | 复用条件 |
|---|---|---|
| delivery_model/codec | 完整无排除snapshot及mapping→DeliverySpec、Plan、Audit | 独立version1，不改旧schema1/2；不携带主机路径 |
| delivery_planner | Spec→ready/blocked/incomplete Plan | 精确来源身份，ASCII目标槽，文件Move/Copy及目录Copy |
| delivery_audit | Spec+任意外部Plan→首失败步骤/最终身份/trace | 不调用planner，不信任expected结果；模型假设需成立 |
| lib/host+src/bridge | 文件引用→纯核心请求→CLI退出码 | Node仅I/O，0/1/2/3区分成功/阻塞/输入/不完整 |
| scripts/delivery-verification | 小状态BFS/10000规模→观测JSON | 参考模型独立，内存peak为同一进程累计，不是单例峰值 |

## 实际证据与教训

- 3种反例：集合不变的a/b交换；初始b读取依赖；file先腾空再Mkdir。外部错计划会被拒绝，合法异序及多个临时槽可接受。
- 独立BFS枚举590状态，324可行266阻塞；与实现及最终来源核对一致。输入逆序曾暴露确定性缺陷，已补回归修复。
- 补充槽位BFS验证248组Copy/Move（172可行/76阻塞）；固定target profile曾被忽略，现由planner/auditor分别拒绝，保留incomplete退出3优先级。
- JS/wasm-gc纯库demo6文档逐字节一致；10000复制/链/环分别10001/10000/12500步骤，0/0/2500临时槽。
- 真实案例固定已发布源码tag与CLI ZIP（固定hash）；平铺覆盖阻塞，source/cli前缀分开后通过。不会拿当前未发布树伪装真实既有输入。
- 旧路径和glob重复生态能力，不能靠工程行数证明独立性；核心贡献须用身份、前置条件和重放反例说明。
- 完整运行入口run_acceptance.ps1/sh；新语义快速入口run_delivery.ps1/sh；未提交接口需按DELIVERY.md显式捕获本地基准。当前公开CI和发布仍是待授权阶段，最终本地结果见V03_PROGRESS。
- 最终Windows和本机Ubuntu WSL的完整验收均passed；核心JS/wasm-gc各135/135，Windows产品57通过2POSIX跳过、工程25通过1POSIX跳过，Linux产品59/59及工程26/26。两平台候选ZIP解包后包含plan/audit-plan并实际运行；这不是新SHA的公开CI或注册表发布。

## 提示词来源

2026-10-17验收补强新增：scripts/delivery-reference.mjs独立推导并直接重放实际计划；scripts/delivery-fs.mjs仅在新建fixture根验证文件字节和完整目录；consumer-smoke使用新增公开API并提供注册表模式；source-snapshot统一快照身份，reproduce独立克隆干净提交。复现入口docs/V03_ACCEPTANCE.md。用户提供本轮完整方案并在执行中明确授权提交、推送、发布；仍不授权赛事报名。实际最终状态以V03_PROGRESS与发布记录为准，不以这里的模块存在代替运行结果。

原文来源：本Codex会话01a0f2f6-ba53-7141-abcf-4bc96bedbb85中2026-10-16的初审驳回反馈、两项范围选择及随后PLEASE IMPLEMENT THIS PLAN。用户原话与本地执行契约docs/V03_PLAN.md分开；该文件为整理后的契约，不冒充完整逐字原文。成功关联为本轮案例/参考模型/验收artifact。此前DeepSeek交接提示位于上级docs/DEEPSEEK_HARNESS_PROMPT_2026-09-30.zh.md，仅适用于v0.2历史续作，不能作为新核心已完成证据。

不适用：用户目录真实执行、物理别名/并发保证、内容相同判断、完整Unicode、目录整体Move。测试工具在隔离fixture中执行，不扩大产品边界。2026-10-17用户已授权Git提交、推送和发布；报名、Notion同步仍未授权。
