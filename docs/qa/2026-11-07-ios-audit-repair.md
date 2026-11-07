# Sleepy iOS 排查与修复记录（2026-11-07）

**状态：代码修复已落入独立工作树；未通过运行验收，不是可发布结论。**

基线为 `lingion/sleepy-ios` 的 `master@9f0cf9f`。实现快照由 `fix/ios-audit-repair-20261107` 冻结交接，接入独立发布分支 `fix/ios-audit-repair-publish-20261107` 并拆分为可独立回滚的提交。主目录的既有未提交文件没有被本发布工作覆盖；本机安装整合另行处理，不等于远端代码已同步到用户原 checkout。

## 核查范围与证据边界

排查了提醒/实况活动完整入口和生命周期、小组件引导、课表几何与手势桥、导入事务和撤销、绑定作息导出、iPhone/watch 快照通路、后台任务配置。生产源码追踪是主要证据；补充使用既有 CI 失败日志和 Apple 官方文档。

- 平台：原生 SwiftUI 主 App、WidgetKit 扩展、watchOS App/扩展；XcodeGen 生成工程，GRDB 存储。
- 按要求没有运行本地测试、模拟器或完整构建；Swift parse 只是语法检查，不是类型检查，更不证明真机行为。
- 没有登录真实学校系统、使用真实账号、变更数据库 schema、删除本机用户数据或修改签名证书。
- 不是全仓每个解析器/学校/设备的认证。外部依赖漏洞数据库、供应链和所有输入边界的独立安全审计未覆盖，不能给出“整个 iOS 全绿/无漏洞”结论。

## 已修正的代码路径

### 实况活动

- `ReminderScreen` 原来没有实况模式入口，普通用户无法开启。增加 iOS 16.1+ 入口和独立系统权限提示；沿用现有 banner/fluid 互斥存储契约。
- 管理器现在同时检查提醒总开关、课前开关、各课表提醒、节假日策略及提前分钟数，读取绑定作息的有效时间并使用真实日期筛选课程。
- 不再以“开始时间数组没变”跳过教室、课名、结束时间等更新。刷新串行合并，清理重复/旧活动，加入前台时间边界与数据/设置变更接线。
- 下一门课排除已结束的重叠课；节假日周末/年份判断统一使用课程民事日时区。异步加载后重新读取当前时间，跨午夜则重新加载当天课程。
- 前台依次处理课前、上课、课后；后台不承诺自启动、自动切课或准时移除。计时器使用稳定区间，进度使用系统时间视图，最小展示不再冻结一个手算分钟数。
- 载荷只包含当前和下一门课，字段按 UTF-8 大小截断，兼顾 JSON 转义后的 4KB 上限；iOS 16.2+设置过期时间，16.1保留旧API兼容。
- 修正“4小时无更新腐坏”“本地载荷不受4KB限制”等旧说明。官方限制是活动最多8小时，结束后锁屏还可能保留最多4小时；不是4小时不更新即失效。

### 小组件与无障碍标识

- CI 的 accessibility tree 表明引导 sheet 已打开，不是按钮没反应。根 VStack 的 identifier 覆盖了子标题/关闭标识；现在标题直接设置 `widget_guide_title`，移除父级传播标识，关闭按钮保留 `topbar_close`。
- 复制内容改成应用搜索词 `Sleepy`，保留组件名称供选择。步骤改为当前 iOS 的“编辑 → 添加小组件 → 选应用/尺寸 → 添加 → 完成”，兼容旧系统的＋入口。五语言同步。

### 导入与导出

- 替换导入以前先写名字/日期，再写作息，最后插课程，各步 `try?` 吞错。现在元数据、有效作息、课程在同一事务内提交；失败回滚，保留预览，不提示成功。
- 替换同时更新学期周数；导入行重置外部 id 和目标 tableId。追加导入把作息扩展和课程插入放到同一事务。
- 新建导入的撤销快照在 COMMIT 后发布，回滚不再清空既有 redo。
- JSON/ICS/分享文本读取水合后的作息；分享文本携带绑定作息信息。原生文件继续保留其兼容列及P区块契约。

### 同步

- 手表回执只更新已送达时间，不再排下一份带新 sentAt 的全量快照，切断确认反馈循环。
- 全量快照对当前表缺失的调休键按删除处理，新发送的快照也明确携带空映射。
- 手表激活时读取 `receivedApplicationContext`，不再误读自己发出的 `applicationContext` 回执。
- 未新增手表编辑能力，也未修改跨端产品定位。

### 课表、缩放与旋转

- 常规多节课程按真实节次找结束行，占位行只参与几何、不占用课程 step；普通卡和冲突卡共享这一规则。
- 自定义短课在午休薄带前结束时，先扣额外薄带再应用最小高度，避免负高度；拖动投影复用同一算法。
- 双指手势清理只恢复自己禁用过的滚动，避免把原本不可滚的宿主误开启；增加拆卸清理和可检查的识别器标识，未降低8pt阈值。
- CI触点在0.1秒时纵距约10pt、结束时约16.47pt；如果识别在0.1秒才开始，后续位移只有6.47pt，低于8pt。记录没有began时刻，因此既不能据此证明挂载失效，也不能认定阈值是唯一根因。UI测试改为更大幅度合成手势，并断言实际卡高变化、提交后重启保持；不再只看两个相同初始值导致必然消失的✓。
- 窗口模式改读所属 UIWindow 的真实 bounds，避免把子内容尺寸当窗口尺寸；补充“子视图仍宽但窗口已竖屏”的回归测试。实际旋转仍须真机确认。
- `ClassDayActivityCore` 保留完整分段函数；运行选择明确返回未结束的后缀。原605/590测试仍严格要求600，不改成宽松非空断言；新增真正生产选择的绝对日期、提前窗口、开关和载荷测试。

### 后台配置

- 注册了 `sleepy.alarm.daily.resync` 却缺少 Info.plist permitted identifier 和 fetch mode；现已通过 `project.yml` 补齐并重新生成工程。
- 使用注册API返回的 Bool 记录是否成功；后台任务取消时不再报成功。
- ActivityKit 管理器仅进入主 App target，不进入 Widget 扩展；watch targets仍排除 ActivityKit。

## 本轮验证

- `xcodegen generate --spec project.yml`：成功。
- 逐文件 `swiftc -frontend -parse`：35个新增/修改Swift文件，0语法失败；生成工程对这些文件无缺失引用，**没有进行类型检查**。
- 主 App/Widget/watch plist 与五语言 `.strings`：`plutil -lint` 通过。
- `git diff --check`：通过。
- 新增回归测试源码：`LiveActivitySelectionTests`、`ImportAtomicityAuditTests`、`CourseGeometryAuditTests`、`GridPinchAttachmentTests`、`WatchTransferDeletionTests`、`WindowGeometryProbeTests`、`HolidayCivilDayAuditTests`；均未执行。
- 已有 CI run `42364991831` 的三项失败只用于定位基线，不算修复后验证。

## 仍未证明的行为

1. 双指手势在用户真机上是否可靠、旋转后是否即时回单栏，须验收。新的较大幅度合成手势也尚未执行。
2. 用户报告的“拖课后原位置和新位置同时有课”未在本轮安全环境复现。现有持久化实现会拆分其它周课程，静态路径和已有严格单测不能证明真机展示已正确。保留原始验收项，不做猜测性持久化改写。
3. CI 明确跳过5个真实拖动移动用例；本轮未修改或扩大跳过范围，也不把它当绿灯。
4. 实况系统权限、8小时生命周期、锁屏/灵动岛渲染、通知投递、配对手表性能及同步收敛，须真机确认。
5. 本记录形成时，修复后的全量编译/单测/UI验收尚未执行，不能作为发版依据；由 PR 的 GitHub 托管 CI 验证。打开 Xcode 前须核对实际 checkout 的分支和提交，不应把远端合并视为本机工程已经同步。

## 当前验收清单

[逐项真机验收](2026-11-06-ios-1064-device-checklist.md)。旧设计与计划已标记为历史草案，不能继续按其中未经证实的API/后台承诺实现。

## 官方依据

- [Apple：Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) — WidgetKit承载、4KB合计、8小时活动及4小时锁屏尾留、生命周期。
- [Apple：How to add and edit widgets](https://support.apple.com/en-us/118610) — 主屏幕添加顺序。
- WatchConnectivity 本机公开SDK `WCSession.h:107–112`：`applicationContext`是本端发送值，`receivedApplicationContext`是从对端收到的最新值。
- GRDB事务与after-commit写法沿用仓库 `ScheduleRepository.writeWithUndo`；新增故障注入用例锁住失败时不发布历史。
