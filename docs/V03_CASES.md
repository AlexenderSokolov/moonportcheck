# v0.3 案例与初审反馈回应

初审要求扣除MoonBagIt路径检查及现有glob后说明独立语义。v0.3的贡献是初态来源身份、操作依赖/中转与独立计划重放；不是新增Windows规则或改一种报告格式。

对照MoonBagIt提交c5e9e21eae2f8d374c093fbb4597e5cc2865c388：portability.mbt已有路径lint；profiles.mbt已有接收规则/匹配；upgrade.mbt的plan_upgrade为BagIt摘要清单升级。上述能力如实承认为既有生态基础，不列作本次新增。参考：https://github.com/zbhzs1/moonbagit/tree/c5e9e21eae2f8d374c093fbb4597e5cc2865c388

| 扣除基础后 | 实际新增语义 | 证据 |
|---|---|---|
| 路径合法性与glob | 来源身份跨Copy/Move仍绑定初态，来源精确而目标折叠 | 交换与初始b复制案例 |
| 索引和静态集合diff | 中间态占用/父节点前置条件、依赖调度、交换环和含Mkdir环 | file腾空再建目录及mixedcycle测试 |
| 格式、CI、包装 | 独立审计任意外部计划，验证来源、无关对象和临时清空 | 手写非法plan、不同正确顺序、两temp用例 |

## 可直接运行的三个语义案例

examples/delivery下保存来自实际运行的spec、plan、audit、broken-plan和broken-audit。

1. **swap**：目标a=X、b=Y、默认临时槽已被Z占据。最终路径集合不变，但必须得到a=Y、b=X，并保留Z。删除首个中转步骤的错误plan被独立审计拒绝。
2. **read-before-move**：a→b、b→c，同时复制初始b到archive/y。最终b=X、c=Y、archive/y=Y。审计从实际所在位置核对身份，不能在b变为X后错误复制X。
3. **vacate-before-directory**：report文件先移到old/report，再建report目录并放入来自one/two的两个x文件。删去腾空意图会被阻塞；两个来源不能混为同一身份。

```text
node bin/moonportcheck.mjs audit-plan examples/delivery/swap/spec.json examples/delivery/swap/plan.json --format markdown
node bin/moonportcheck.mjs audit-plan examples/delivery/swap/spec.json examples/delivery/swap/broken-plan.json --format json
```

第一条退出0，第二条退出1并指出失败步骤。其余案例替换目录名即可。这些是明确标注的合成反例，不冒充外部用户案例。

## 真实工程输入

scripts/delivery-cases.mjs以发布tag v0.2.0（b7cda70b8da20dab525cba7317d54881e53e4262）的源码树和已发布CLI ZIP作为输入。CLI固定SHA-256为a48feee19bf481d72de1ed691c5ab83294f98c07c7feb5a08a35f96d5af361d7。源码105项、CLI29项，包括目录。

将两份输入都平铺到目标根会因README、LICENSE等占位冲突退出1；分别映射到source/和cli/后，计划生成与审计退出0。运行命令是run_delivery.ps1或run_delivery.sh，实际spec、plan、审计和Markdown报告保留于artifacts/delivery-cases-*。2026-10-17增加测试专用文件重放：复制到自己新建的测试根，实际执行计划并比较初始字节与目录集合，保留无关目标及只读来源。真实案例与合成反例分开记录，产品仍不执行磁盘交付。

## 验证口径

独立BFS参考模型枚举1–4个文件的590个移动状态请求，324可行/266阻塞与实现一致；另一个允许来源副本的槽位BFS验证248个Copy/Move组合，172可行/76阻塞同样一致。可行计划均核对来源身份，映射逆序输出不变。规模覆盖一万Copy、一万Move链和2500个四环；操作数分别10001、10000、12500，临时数0、0、2500。实际耗时和内存记录在artifacts/delivery-verification.json；进程peak包含此前案例，不能当作隔离单例峰值，也不构成性能承诺。

2026-10-17补强将独立模型直接用于实际operations，覆盖所有496个可行枚举请求及定向交叉案例；正确终态不再只由产品审计器提供。证据层次和干净源码复现见V03_ACCEPTANCE.md。当前提交与发布进度以V03_PROGRESS.md及远端实际记录为准，未重新报名；工程证据不保证赛事主观审核通过。
