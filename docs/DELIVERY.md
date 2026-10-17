# 文件交付计划与独立审计

当前源码版本为0.3.0。产品只对声明的逻辑命名空间进行规划与验证，不复制、改名、创建或删除磁盘上的输入文件；来源身份不是内容哈希，模型也不证明物理根目录没有别名。独立参考模型、测试专用文件重放及完整源码复现见[V03_ACCEPTANCE.md](V03_ACCEPTANCE.md)。

## 输入和运行

Spec格式为moonportcheck-delivery-spec，version=1。sources为只读根数组，target为一个可变目标根；每根包含id和snapshot。snapshot可以是已有snapshot对象，也可以是相对Spec文件所在目录的snapshot文件路径；Node只读取引用文件，交给纯MoonBit核心前展开。不同根由调用方声明互不重叠，同根操作统一使用target.id。

```json
{
  "format":"moonportcheck-delivery-spec", "version":1,
  "sources":[], "target":{"id":"target", "snapshot":"initial.json"},
  "mappings":[
    {"mode":"move","source":"target","from":"a","to":"b"},
    {"mode":"move","source":"target","from":"b","to":"a"}
  ]
}
```

```powershell
pwsh -File run_build.ps1
node bin/moonportcheck.mjs plan examples/delivery/swap/spec.json --format json > plan.json
node bin/moonportcheck.mjs audit-plan examples/delivery/swap/spec.json plan.json --format markdown
pwsh -File run_delivery.ps1
```

Bash对应入口为run_build.sh、run_delivery.sh。上述Windows命令在PowerShell 7（pwsh）中执行，以UTF-8保存stdout。plan与audit-plan支持json/text/markdown，退出0代表ready/valid，1代表语义阻塞或计划错误，2代表参数/文档错，3代表I/O或输入观测不完整。所有输入snapshot必须complete且scope=[]；不能把未观测范围当作空闲槽，target profile必须为portable-windows-v1，其他目标profile明确拒绝。

## 核心语义

每个初始文件获得(root,original_path)身份。来源按精确路径定位，Linux A/a可为不同身份；目标按ASCII折叠槽定位并校验现有Windows命名规则。Copy保留来源并增加副本；Move只来自目标初态，每个初始文件最多一个Move意图，但可有多个Copy。源路径必须为规范相对路径，不把反斜杠改作分隔符；当前不支持包含反斜杠的源名。

from指向目录时，Copy按初态展开所有后代，保留空目录；空from代表根，目录Copy的空to代表目标根。复制到自身子目录也只展开初态一次，不递归纳入新产物。目录整体Move不支持。

每步必须有正确源身份、空闲目标与目录父节点。已有占位文件只有在另一个Move会腾空时才可调度，否则阻塞。规划器通过slot订阅唤醒依赖，遇环把一个待移动身份腾至`.moonportcheck-stage-N`，随后继续；临时路径避开初态、终态和其他临时槽。文件大小写改名也用中转。

审计器自己展开意图、计算应有的最终身份和目录集合，然后按计划逐步重放。它不调用planner、不比较某个固定步骤顺序，也不信任计划自带的期望结果。无关文件不得移动，目录只能按交付所需创建，最终布局必须精确相符且无临时文件。外部计划可选择scratch等其他fresh合法临时名，也可采用其他正确顺序或多次中转。

## 新接口与输出

根库公开parse_delivery_spec、plan_delivery、audit_delivery_plan，另有parse_delivery_plan及plan/audit/spec渲染函数。模型为DeliverySpec、DeliveryPlan、DeliveryAudit等；cmd/delivery-demo只使用公共库API，在JS和wasm-gc输出相同6份文档。

Plan格式moonportcheck-delivery-plan/version1包含status、canonical basis、operations、temporary_paths和diagnostics。每个operation包含kind=mkdir/copy/move、source、from、to、origin={root,path}；mkdir的source/from/origin为空。basis是展开后规范Spec的JSON字符串，包含输入语义，不包含本机绝对路径。

Audit格式moonportcheck-delivery-audit/version1包含valid/status、first_failed_step、diagnostics、final_entries与trace。step从0开始，-1代表重放前或最终状态失败。trace逐步保存效果而非每步复制整个树，final_entries保存最终来源身份。CLI对planner的ready计划额外调用独立审计gate，通过后才输出可用计划。

## 验证与未提交开发

run_acceptance在既有checks/demo/benchmark/consumer/package/unpack之后加入delivery阶段：跨目标纯库比较、小状态参考枚举和一万规模、合成/真实案例。案例脚本只在artifacts创建自己的fixture及报告；首次缺少固定v0.2 CLI样本时从已发布URL下载并校验固定SHA-256。正式CI需完整Git历史以取得v0.2.0源码tag，workflow已配置fetch-depth=0。

本轮未获暂存或提交授权，生成的新公共接口因此与Git基线不同。本地完整验收可显式生成并使用指纹基准：

```powershell
. ./scripts/toolchain.ps1
moon info
node scripts/capture-local-api-baseline.mjs artifacts/v03-api-baseline.json
$env:MOONPORT_API_BASELINE = (Resolve-Path artifacts/v03-api-baseline.json).Path
pwsh -File run_acceptance.ps1
```

捕获时验证既有48个公共声明保持不变，检查时核对全部接口文件指纹；任何后续漂移仍失败。默认未设置该变量的Git/CI门禁不变。这里通过只代表明确基准的本地未提交实现，不冒称精确新SHA的公开CI或包发布。
