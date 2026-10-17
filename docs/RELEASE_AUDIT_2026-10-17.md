# MoonPortCheck v0.3.0 发布审计

日期：2026-10-17。用户批准《v0.3验收补强与重新申报方案》，随后明确授权提交、推送和正式发布。本记录在实际验证和发布后整理；官方报名与验收未代办。

## 交付与独立语义

v0.3从路径与静态集合检查扩展为基于初态来源身份的交付计划编译与验证库。MoonBit实现多根来源、目录Copy初态展开、文件Copy/Move、Mkdir前置条件、依赖环与中转，并独立审计任意外部计划。Node仅处理I/O与工程适配。既有路径lint、glob、索引、静态diff及报告明确列作复用基础，不计为新增核心。

本轮补强没有重写核心算法，也没有增加产品执行器。新增第三种测试模型直接推导完整终态并重放实际步骤；保留838个有限域可行性请求，对496个可行计划逐步验证。8项模型测试、定向目录/多来源/大小写交叉案例，以及8类错误计划验证身份、顺序、遗漏、占用、临时残留、过期依据和无关变更；有效异序和替代中转名仍接受。

测试专用文件适配器仅操作自己新建的fixture根。Windows8个场景、Linux9个场景（均含1个阻塞场景）实际运行；Linux真实构造A/a两个来源。固定v0.2.0源码与CLI发行包的前缀合并执行136步，比较118个文件、1378688字节，保留1个无关目标，来源未改且临时清空。源码原fixture与合成案例分开标注。

独立review未发现新增核心语义阻塞项；发现并修复了候选身份仅自洽、验收只记录末态源码两处证据绑定问题。现在包执行前核对当前完整提交/状态/源码摘要，验收前后源码一致才可passed。发布版本同步修正SARIF内嵌版本号。相关定向回归与修复复核通过。

## 精确源码验证

- 发布提交：`7932269cc3db20074c8388a4d76bf5dab0b5d37c`；`v0.3.0`解引用到同一提交。后续本文件属于文档收尾，不改变该tag或发行物。
- [公开CI39007654147](https://github.com/AlexenderSokolov/moonportcheck/actions/runs/39007654147)：Windows与Ubuntu全部成功；验收均passed、source_unchanged、committed_clean，tested_sha为上述完整提交。
- 核心JS/wasm-gc各135/135。Windows产品57通过、2POSIX跳过，工程37通过、1POSIX跳过；Linux产品59/59、工程38/38。
- Windows `scripts/reproduce.mjs`从干净提交克隆、空构建与案例缓存开始，实际下载固定旧发行fixture；默认接口门禁通过，源码前后未改。Linux使用Linux文件系统中的独立克隆运行默认完整验收。
- 下载CI实际候选包：两平台均在各自系统解包，在仅有Node且无MoonBit的运行PATH执行9个公开命令，包含plan/audit-plan。Windows ZIP另经.NET标准读取器读取48个条目。
- 两平台各147项源码清单与发布提交逐文件核对，允许Git的LF/CRLF转换。工作树候选tested_sha=null并使用摘要命名；它们不充作本次正式发行物。
- 一万Copy、一万Move链及2500个四环继续通过，操作数10001/10000/12500，临时槽0/0/2500。计时不含扫描；plan计时含审计gate，进程peak为累计峰值，不是单例独立内存保证。

## 正式发布验证

[GitHub Release](https://github.com/AlexenderSokolov/moonportcheck/releases/tag/v0.3.0)为正式非草稿、非预发布版本，包含两个平台CLI ZIP、完整源码tar、两平台验收元数据/源码清单/文件重放记录和SHA256SUMS。实际下载的两个ZIP及源码tar与校验文件一致，GitHub资产digest也一致。

| 发行物 | SHA-256 |
|---|---|
| moonportcheck-0.3.0-win32-7932269.zip | `88dfa36a5e6ce58745bf99ffc4fc3a683b2caba84a1fa153d71ea7079457463e` |
| moonportcheck-0.3.0-linux-7932269.zip | `761bedbb5686706b7ecf1e90e951e21891c604584e9dd817a91798cb0a1ea852` |
| moonportcheck-0.3.0-source-7932269.tar | `7333416e17a3b89c4782a2921c54ed1eb06d41bb180a05abadac221244babc5d` |

[Mooncakes](https://mooncakes.io/docs/AlexenderSokolov/moonportcheck)正式上传返回200、CLI退出0；[manifest](https://mooncakes.io/api/v0/manifest/AlexenderSokolov/moonportcheck)确认version/latest_version=0.3.0、build_status=success、has_package=true、yanked=false。

新建独立消费者workspace仅包含`.`，按0.3.0版本从注册表解析，无本地库成员；moon update及两个目标的check/build/run成功。实际调用旧API与新增parse→plan→serialize→parse→audit，检查交换身份及第0步拒绝错误来源，两目标输出一致。该验证复用固定工具链，不声称重新冷安装工具链或清空全部注册表全局缓存。

一页申报书另存DOCX/PDF，保留旧稿并通过Word/PDF单页及PNG视觉检查。材料突出身份交换反例、独立语义、真实字节与外部消费证据；发布并不代表赛事资格或主观验收已通过。

## 本地证据入口与限制

本机artifacts/reproduction-latest.json、v03-local-linux-evidence.json、v03-release-verification.json、v03-public-linux-unpack.json及consumer-smoke-v0sZFR/evidence.json记录实际运行。公开验收文件随Release提供。

Linux CI完整artifact包含真实A/a fixture，不能在普通Windows文件系统完整展开；使用标准ZIP读取器直接读取选定元数据与包，并在Linux验证实际发行ZIP。产品身份是逻辑来源，仍由调用方保证命名空间对应不同物理根；没有任意用户目录执行、覆盖、删除、目录整体Move、完整Unicode、并发或崩溃恢复保证。
