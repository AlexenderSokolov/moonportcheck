# v0.3 已批准实施计划与接口约定

来源：2026-10-16 用户在本会话发送 PLEASE IMPLEMENT THIS PLAN，完整方案见会话；本文件保存实际实现契约。初审反馈要求扣除路径lint/glob后证明独立核心。目标是基于初态来源身份的文件交付规划和独立重放审计，不实际执行文件操作。

## 顺序与验收
1. 模型与严格解析，保留v1/schema1和既有CLI schema2。
2. 多源Copy、目标Copy/Move、目录前缀Copy展开、依赖调度和临时中转。
3. 独立审计任意外部计划：前置条件、身份、最终布局、无关条目、临时清空。
4. plan SPEC 与 audit-plan SPEC PLAN，json/text/markdown，0/1/2/3退出。
5. 三组身份/依赖/文件变目录案例，真实公开源码与CLI包交付案例，小状态参考枚举、双目标一致性、一万映射与链/环规模、旧消费者。
6. 独立审查、文档/重申报材料及本地复用说明。提交、推送、发布、报名不在本轮授权中。

## 固定数据契约
核心Spec文档为 `{format:"moonportcheck-delivery-spec",version:1,sources:[{id,snapshot}],target:{id,snapshot},mappings:[{mode,source,from,to}]}`。snapshot为现有snapshot文档。CLI也接受snapshot为文件路径字符串，按Spec文件所在目录读取，交给MoonBit前展开；序列化basis只包含规范化内容，不包含本机绝对路径。不同root是调用方声明的不重叠逻辑命名空间，模型不证明磁盘去别名。

核心类型见 delivery_model.mbt，字段只读公开；来源身份DeliveryOrigin(root,path)，目录使用空身份。Copy保留来源身份的副本，Move迁移身份。所有来源读取绑定初态，目标目录按ASCII折叠定位，来源精确定位。目标树必须结构及命名可表示；source仅要求相对路径结构有效，允许Linux源A/a或保留设备名。所有snapshot完整且scope空。目录整体Move不支持。

单个文件from与to为精确路径；目录Copy按from前缀展开成文件意图并保留空目录，空from表示根。Move只能来自target命名空间，每个初始文件最多一次。不能覆盖无腾空意图的已有文件。临时文件使用根下 `.moonportcheck-stage-N`，避开初态/最终目标/其他临时，目录只建立不移动或删除。

Ruling: 目录Copy的空to代表目标根，单文件空to仍非法；这是根平铺与真实多源案例需要的明确语义。临时前缀仅约束规划器默认命名；独立审计器接受外部计划自行选择的fresh合法根层临时名（包括scratch），按占用/身份/最终清空校验，不要求与规划器同名。

Plan独立format/version1，status为ready/blocked/incomplete，basis是规范化已展开Spec JSON字符串，operations按顺序，temporary_paths与diagnostics。Operation固定kind=mkdir/copy/move、source、from、to、origin={root,path}；mkdir源和身份为空。Audit独立format/version1，status/valid/first_failed_step/diagnostics/final_entries/trace；step为0起始，-1代表重放前或最终状态错误。审计不能调用planner或信任预期结果，必须从spec独立推导目标状态。

Ruling: 本地新分支隔离，但不提交或暂存改动；新接口验收通过显式记录的本地接口基准检查，保留原API门禁默认行为。
