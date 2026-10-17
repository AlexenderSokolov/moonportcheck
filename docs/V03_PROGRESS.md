# v0.3 实施账本

## 2026-10-17 验收补强

**最终状态：已完成并正式发布0.3.0。** 发布源码7932269cc3db20074c8388a4d76bf5dab0b5d37c，tag v0.3.0解引用一致；公开CI39007654147双平台成功。Windows干净克隆默认门禁及Linux独立克隆完整验收通过，源码前后未变；Linux真实A/a来源案例通过。下载CI两平台包各运行9个无编译器命令，147份源码清单逐文件对应提交（允许Git行尾转换）。GitHub正式Release及Mooncakes manifest成功，独立注册表消费者JS/wasm-gc通过。实际Release下载的两个ZIP和源码tar哈希一致。完整链接、校验值和限制见[发布审计](RELEASE_AUDIT_2026-10-17.md)。以下保留本轮实施过程，未重新报名。

来源为本会话已批准的《v0.3验收补强与重新申报方案》；随后用户明确授权提交、推送、发布，报名未授权。下方10-16记录保留为历史结果。

- A已实现：第三种测试模型直接推导完整布局并重放实际operations；保留838个BFS可行性请求，496个可行计划全部重放；8项独立模型测试、定向交叉与8种错误计划对照通过。
- B已实现并定向验证：Windows8个隔离文件场景通过（含1个阻塞场景）；负向字节/临时残留检查通过。真实发布fixture前缀案例加入相同文件重放适配器；Linux真实A/a来源待完整验证。
- C已实现并定向验证：新增API由独立模块在JS/wasm-gc消费，错误身份计划被拒；源码清单统一，工作树tested_sha=null及候选身份可区分，16项证据/ZIP测试通过。干净提交克隆复现入口已加入，待实际新提交运行。
- D验收说明及一页申报书正在更新；完整验收、最终review、精确SHA公开CI和发布结果将在实际运行后追加。
- 复核结果：没有新增核心语义高影响问题；发现并修复候选包只自校验身份、验收只采集末态源码两项证据绑定缺口。包执行前核对完整提交/状态/快照，验收前后源码一致才可passed。定向同版本错包对照通过。
- 第一次完整验证发现SARIF仍内嵌0.3.0-dev，与正式版本元数据不同；同步0.3.0后5项release回归通过，随后Windows完整本地验收passed（acceptance-win32-2026-10-17T05-41-38-943Z）。最终证据绑定修复后的完整验证继续执行。
- 一页申报书DOCX/PDF已生成并经Word与PDF单页及PNG视觉核验，旧稿保留。真实fixture物理验证：136步骤、118文件（含1个无关目标）、1378688字节对比，来源未变且临时清空。
- 最终Windows工作树验收：acceptance-win32-2026-10-17T05-45-28-930Z/evidence.json，passed=true、source_unchanged=true；147个源码文件。核心JS/wasm-gc各135/135，产品57通过2POSIX跳过，工程37通过1POSIX跳过。8个完整阶段通过，新API外部双目标消费、正确/错误计划、字节验证、打包及无编译器9命令均实际执行。
- 独立review的两项证据绑定修复已定向复核通过，无剩余具体阻塞项。最终发布前将以真实新提交运行默认门禁及干净克隆，工作树基准结果不充作公开SHA结果。

Ruling: 本次继续复用已实现核心，新增测试专用文件重放而不增加生产执行器；只有定向测试发现实际语义缺陷时才修改核心。
Ruling: 用户新增Git及发布授权后，干净复现采用真实新提交的独立克隆，仍保留未提交源码身份修正，避免旧HEAD冒充被测实现。

计划：V03_PLAN.md，授权为本地实现和验证。基线main a2ab113，分支codex/v0.3-delivery；不提交/推送/发布/报名。

- 模型/解析：已实现，codec双目标5/5。
- 规划器/独立审计器：已实现，planner双目标14/14，auditor双目标14/14；分别推导，不共享最终态算法。
- CLI与案例、参考枚举/规模：已实现；CLI6组、BFS590（324可行/266阻塞）、10000 Copy/chain/rings均通过；3合成反例及真实v0.2源码105项/CLI29项案例通过。
- Windows完整本地预验收：passed，artifacts/acceptance-win32-2026-10-16T10-01-41-436Z/evidence.json。新旧核心134项/目标；Node58项（56通过2POSIX跳过），工程26项（25通过1POSIX跳过）。
- 独立最终review：未发现身份/调度/重放高影响问题；确认外部fresh临时名可不同于planner默认名，契约已明确。
- 最终双平台验证、申报材料和复用说明：完成本地交付，见以下最终记录；未提交/发布/报名。

Ruling: 输入重排测试发现swap选择的临时中转身份不同；补RED回归后对roots/mappings/intents排序，590枚举及逆序检查GREEN。
Ruling: 本地未获Git暂存/提交授权，采用显式API指纹基准验证新增接口，保留旧48个公共声明；默认Git/CI门禁不变，不冒称公开CI已通过。

本文件只记录实际结果，历史v0.2验收不充作新验证。

## 最终本地验证 2026-10-16

- Windows：artifacts/acceptance-win32-2026-10-16T10-29-52-495Z/evidence.json，passed=true。
- 本机Ubuntu WSL：artifacts/acceptance-linux-2026-10-16T10-33-08-508Z/evidence.json，passed=true。没有远程执行。
- 每个平台核心JS/wasm-gc各135/135；Windows产品59项中57通过2POSIX专用跳过、工程26项中25通过1跳过；Linux产品59/59、工程26/26。原v1消费者、旧CLI回归、默认格式及跨目标序列化一致性通过。
- 新纯库demo两目标6份JSON逐字节一致；新CLI7组通过（包含固定target profile的独立拒绝）；独立参考590+248组共838请求全部一致；10000 Copy、10000链、2500四环通过。
- 真实v0.2源码105项与CLI29项平铺阻塞、前缀分开后ready/valid；源码按固定b7cda70完整SHA归档、CLI校验固定已发布hash，不使用当前开发树冒充。三个合成反例正确计划退出0，删步错误计划退出1。
- 完整验收8步checks/demo/benchmark/consumer/package/unpack/delivery/toolchain全部退出0；候选ZIP无编译器解包验证实际运行9个公开命令（含plan/audit-plan）。Nested examples已纳入打包。
- 有效产品/测试共9341行：MoonBit产品5432、Node产品366、MoonBit测试2493、Node测试1050。相对v0.2发布基线增加2848有效行；工程脚本、文档、生成物和示例数据不计入。数量不作为赛事通过保证。
- 最终独立review未发现高影响身份、调度和重放问题；临时命名前缀契约已明确。另对target profile漏洞先观察CLI及MoonBit实际RED，再补两侧guard并观察双目标与CLI GREEN，独立补充review确认incomplete优先级和source profile边界正确。
- 一页Word申报书保存在上级参赛要求目录的MoonPortCheck项目申报书_v0.3.docx；旧稿保留。Windows缺LibreOffice，采用已安装Word导出PDF并逐页PNG检查，正文中的新数据与本地结果对应。
- Git HEAD仍为a2ab113（v0.2后续文档基线），工作树modified；这是明确本地API指纹基准下的未提交实现，真实源码由各验收source-manifest固定。没有暂存、commit、push、PR、公开CI、包发布或重新报名。后续提交公开审查与发布须单独授权。
