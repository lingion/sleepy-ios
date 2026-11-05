# v1.0.63 剩余能力核对

核对日期：2026-11-04。依据上游 `v1.0.62..v1.0.63` 源代码和本集成工作树；这是能力与验收缺口记录，不是发布通过报告。后续编译与测试全部由 GitHub 托管 runner 执行。

| 能力 | 源代码证据 | 当前 iOS 证据 | 状态 / 下一步 |
| --- | --- | --- | --- |
| 原生拖课与连续翻周 | `FloatOccurrenceHandler.kt` 区分 sourceWeek/目标 week | `NativeCourseDrag.swift`、`CourseOccurrenceIdentity.swift`、Repository 移动接口 | 已接线；必须通过实际 UIKit 拖放、持续停边及落库验收 |
| 单次课程编辑、删除与定日课程 | `OccurrenceEditor.kt`、`SingleOccurrenceCourseForm.kt`、`CourseOccurrence.kt` 的 fixedDate/saveOccurrence | v13迁移、单次事务、显示、详情、同步、提醒与日历已接线 | 新增31项回归待云端，须覆盖完整入口与持久化 |
| 空格胶囊快速加课和跨度把手 | `QuickAddCourse.kt`：范围选择、外点消费、上下把手 | 原生胶囊、双把手、外点消费、手机平板预填及真实保存链路已接 | 策略与预填13项新回归、原生UI待云端 |
| 多步撤销/重做及深度设置 | `data/undo/UndoManager.kt`：两栈，默认 5、0 禁用、负值无限 | 双栈、偏好、实验室设置和恢复失败回填已集成 | 新增19项回归待云端，含读写失败保护 |
| 删除已绑定作息并冻结各课表当前作息 | `PeriodTableDeletion.kt` 在事务内 hydratedWith 后解绑，另有 onlyIfUnbound 草稿清理守卫 | 显式UI删除冻结所有绑定表；旧调用与草稿仍保留守卫 | 新增3项数据库回归待云端，含删除失败回滚 |
| 真实课程配色预览 | 首页 CUSTOM/AUTO/GROUP 优先级 | 新增 `CourseColorPreview` 保留同表完整组行并复用首页函数 | 修复已写入，新增 4 项 XCTest 等待运行 |
| 六滑杆基线标记 | 进页捕获、退出重置 | 改为同 frame/同 direction 的原生双滑杆，底层只显示半透明基线拇指 | 已接线、已注册；RTL 及实际显示仍需原生运行验证 |
| 导入取消返回方法页 | 上游 #272 保留添加入口 | 原生子 sheet 及 completed/cancelled 返回状态 | 静态/状态回归已有历史通过；运行时 sheet 时序待验 |
| 小组件强制滚动设置 | 原平台依赖 RemoteViews 滚动服务 | 确认 WidgetKit 渲染无消费者后，删除 WidgetEditScrollSection 及其调用 | 无效开关和对应厂商弹窗入口已移除；存量偏好兼容保留，等待集成编译 |
| 目录 1402 候选与三校增量 | 549 已登记协议、810 jw_home、43 sg_asset | 目录与284个拾光资源文件已迁入；WebView派发、首载UA和资源层级已接 | 保留未验证状态，新增fixture及目录回归待云端；不宣称账号登录验证 |
| Debug Console | 新增 listener/router/auth/clock/data/UI 等控制能力 | `1f7809c`已接DEBUG主App的loopback监听、鉴权、repository/UI控制、业务时钟、目录覆盖、Ucas回放及App生命周期 | 21项测试待云端；系统键/任意坐标、全WebView回放及FluidCloud不支持，能力标志明确，不能计为已实现 |
| WakeUP 在线分享口令读取及 v6.1.70 加密协议 | 三个分享协议文件及 `v1.0.62..v1.0.63` 实际diff | 原生加密与两段POST读取、取消和预览已接，覆盖粘贴/文件/外部导入路由 | 新增16项向量与HTTP fixture待云端；已确认此版本不含在线创建分享码。转换层极端数值溢出修复中 |
| BJTU / SCAU / Yethan parser 版本差异 | 三文件 diff 均仅 docs 路径移到 docs/history | 本轮未改变相应 parser | 此版本没有解析逻辑增量；不计成新增协议缺口，也不据此推断现有 parser 全部已实测 |
| 管理页入口重组 | 四入口、摘要编辑、独立全部课表、空态摘要及 manage_title | 原生入口和五语言已集成，新建并入添加方法页并等待dismiss完成才转编辑 | 用户批准旧UI测试补充方法页点击，原保存输入和断言保留；待云端验收 |
| 定日课程导入/导出及调休日历 | JSON fixedDate；native第12列；ICS逐次展开、日期UID、无RRULE | 解析、导出、顶栏分享和系统日历已接；ExportScreen按目标表传调休 | 往返、补班范围与日期回归待云端 |
| 系统动效 | 逐符号核对见 `undo-wakeup-motion-v1063-review.md` | 转场、按压、popup、作息行及根层消费者已接；30色槽插值与Reduce Motion已写入 | 策略、向量测试和真实逐帧表现待云端；不以常量定义代替实际验收 |
| iOS系统动态取色（用户新增核心需求） | Apple公开tint、深浅外观、对比度及Widget渲染模式 | `326cc8f`接窗口探针、版本化共享快照、HSV/M3派生及App/全彩Widget/课程锚点统一解析 | 18项新测试待云端；active-window用例缺前台scene时会明确跳过，此时仍有验收缺口。主屏幕/壁纸RGB无已核实公开读取契约，fallback显示来源 |

## 验证证据与当前闸门

- 历史本机 `build-for-testing` 第9/10次成功；103项聚焦 XCTest 通过。此证据早于本次定日/撤销/目录等新代码，不能外推为当前快照通过。
- 用户已要求仅线上编译测试；本会话专用模拟器已关闭。
- 首轮云端运行 `41834689403` 确认 runner、依赖获取和产物归档可用，但构建在 destination 解析退出70：独立XcodeGen安装遗漏平台SettingPresets。
- 按用户要求改回仓库原有 `ios-build.yml` 和 Homebrew完整安装，新增自动验收、动态设备、单元/拖课/其余UI与xcresult归档；临时工作流已删除。后续结果待回填。
- 第二轮 `41840216592` 已进入Swift编译，两个宿主因 `JwImportReturnState` 合成初始化器为private而失败；`bcd4f85` 增加显式internal初始化器。
- 第三轮 `41842584935` 验收 `b2da02e`，越过生产编译后在 `JwSgAssetParserTests:19` 类型推断超时；`ff95e2d` 仅加类型并拆分等价布尔表达式，原fixture与断言不变。当前未有成功的托管单元或UI测试证据。
- 普通repository写失败消耗undo并清redo的修复已提交 `8e66868`；29项新故障回归待执行。WakeUP数值边界修复与5项新回归已提交 `76fc079`。
- `326cc8f`已推送，完整控制台/动态取色快照由托管运行 `41846696894` 验收；结果待回填。独立审阅另行核对多窗口及跨target链路。

## 历史集成编译发现（已解决）

- `WidgetWeekSource` 的无参 refresh 已接到 `refresh(mode:dao:)`。
- 手机无效 `CourseHueStore.start()` 已移除，保留已有显式首载与数据变更刷新。
- 手表入口和镜像应用改用 `invalidate(mode:dao:)`；课程行从所观察对象的 hueMap 取值。
- 第6次构建退出65：拆分 WeekPager 后将类型检查超时定位为 FullWeekView 缺失 showDate 参数。已补齐 FullWeekView → DetailPanel → DetailDayCard 的日期传递，日期按浏览周计算并尊重开关；后续第9/10次构建成功。
