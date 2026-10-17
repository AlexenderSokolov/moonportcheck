# v0.3 验收与复现

项目新增核心是初态身份、操作前置条件与依赖调度、独立外部计划审计。路径lint、glob、索引、静态diff及原报告设施列作复用基础。初审反馈与固定版本生态对照见V03_CASES.md。本页说明如何复现，实际提交、平台及发布结果见实施账本和Release；不将本地测试等同官方验收。

## 从交换案例开始

解包CLI发行包后，使用Node.js 24，无需MoonBit编译器：

```text
node bin/moonportcheck.mjs plan examples/delivery/swap/spec.json --format json
node bin/moonportcheck.mjs audit-plan examples/delivery/swap/spec.json examples/delivery/swap/plan.json --format markdown
node bin/moonportcheck.mjs audit-plan examples/delivery/swap/spec.json examples/delivery/swap/broken-plan.json --format json
```

前两条退出0，最后一条退出1。初态a=X、b=Y，默认中转槽被Z占用；正确交付必须得到a=Y、b=X并保留Z。路径集合相同无法判定交付正确。目录read-before-move、vacate-before-directory提供另外两组输入、正确计划和损坏计划。

## 完整源码运行

取得Release对应的完整Git提交（保留历史），按PROJECT.md安装固定工具链，然后运行：

```powershell
pwsh -File run_acceptance.ps1
node scripts/reproduce.mjs
```

Linux对应第一条为`bash run_acceptance.sh`。reproduce要求干净的项目仓库，独立克隆当前提交，使用全新构建与fixture缓存，复用已校验工具链，运行默认完整门禁并输出源码tar及清单。它不会暂存或提交工作树，也不会把父仓库HEAD借作项目身份。固定旧CLI fixture在新缓存中实际下载并校验。

快速检查交付语义使用`pwsh -File run_delivery.ps1`或`bash run_delivery.sh`。独立模块消费由`node scripts/consumer-smoke.mjs`验证；设置`MOONPORT_CONSUMER_REGISTRY=1`可在发布后改为版本化注册表依赖，workspace不包含本地库。

## 三层证据

| 层次 | 标准答案来自哪里 | 产物 |
|---|---|---|
| 产品 | MoonBit审计器独立从Spec计算预期，逐步重放外部计划 | plan/audit CLI、核心测试 |
| 第三种模型 | 测试专用Node模型从初态及意图推导完整布局，直接解释实际operations；不导入产品内部函数 | delivery-verification.json、reference测试 |
| 实际文件 | 测试根的初始字节及目录清单；操作后直接比较目标与只读来源 | delivery-fs-latest.json、逐步physical-trace及expected-layout |

独立BFS保留590组Move与248组混合请求，496个可行计划直接接受独立步骤重放。枚举范围是平面有限域；目录、多根、大小写和空目录由定向交叉案例补充，不声称全域穷举。负向对照包括路径合法但身份错误、临时占用、错误顺序、遗漏、临时残留、过期basis及无关变更；合法替代顺序与临时名仍接受。

文件系统测试仅修改自己在artifacts中新建的测试根。真实案例从固定v0.2.0源码与发行ZIP采集，平铺合并阻塞，source/cli前缀合并后实际比较文件字节和空目录。原fixture只读保留。Linux独有A/a来源案例在Linux真实运行，Windows明确记录跳过；纯模型对应案例两平台均运行。测试工具不提供用户目录执行命令，也不扩大产品对并发、崩溃或物理别名的保证。

## 源码与交付身份

干净提交记录tested_sha并沿用SHA候选名称；修改工作树记录tested_sha=null，使用worktree加源码清单摘要命名。每个CLI包含SOURCE.json，受CHECKSUMS校验。source_commit在工作树状态仅表示基线，不能证明该提交包含新代码。源码tar、公开Git提交与CLI包是不同交付物，需按同一验证结果对应。

规模结果记录一万Copy、长Move链及多个交换环的耗时、操作数和内存。现有进程peak为累计峰值，不能当作每例隔离峰值，不构成性能承诺。提交、CI、GitHub Release、Mooncakes及赛事报名分别记录。
