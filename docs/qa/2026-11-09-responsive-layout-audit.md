# 手机与平板布局审计（2026-11-09）

> **2026-11-10更正**：本文149/150/158pt小号切脸及窄small全周结论已由[最小小组件复核](2026-11-10-widget-minimum-size-parity.md)取代。当前systemSmall的周列表/周视图使用三天窗口，周网格使用Today脸；补三天调休与定日课取课修复，完整单测2274项零失败。以下先前批次保留为历史证据。

基线：iOS `91f128e`，对照本地 Android 1.0.63 的 `SleepyNavHost`。本记录只说明本次响应式布局切片，不是全量功能或真机验收结论。

## 已定位并修复

| 场景 | 基线根因 | 本次行为 |
| --- | --- | --- |
| 600–875pt 横屏窗口、较窄分屏 | `NavStyleResolver` 只用 600pt 和横屏判定双栏。扣除 80pt rail、32pt 外距、44pt 沟槽后，600pt 窗口每栏仅 222pt；`CourseTableView` 七天列宽下限 28pt 且只允许纵向滚动，会被面板裁切。 | 保留 600pt 侧栏断点；另按实际内容宽保证每栏至少 360pt。空间不足时四个侧栏入口切换单页，足够时保留三槽与固定课表双栏。 |
| 刘海手机横屏 | UIWindow 的完整宽度包含左右安全区，直接用完整宽度预算双栏仍可能高估空间。 | 双栏策略可接收左右安全区总宽，或由调用方直接传可用内容宽。 |
| 小屏、平板窄栏，存在撤销或缩放确认按钮 | `ScheduleTopBar` 中央周导航、左侧操作、右侧加课与分享使用 ZStack 叠放；Undo 最小缩放为 0.65，剩余空间不足时仍保持重叠。全局原点还包含窗口或栏内偏移，可能高估局部剩余空间。 | 在同一局部空间分别测量整栏与中央三件套宽度，按左右完整操作区宽度和8pt间隔判断；拥挤时将操作放到独立第二行，保留各项操作和标识。 |
| 52周长学期、短横屏窗口 | `WeekJumpMenu` 无高度上限或滚动；调用处与内部各加 56pt 顶距，面板还按 ZStack 默认居中摆放。 | 使用实际窗口高度限制可滚网格，顶部只锚定一次；窄窗可减少列数；打开时滚到当前周。 |
| SE等小屏的分享格式选择、大字 | `ShareScheduleSheet` 的四行每行至少 76pt，加标题、分隔和底距约 372pt，只允许 medium，且没有滚动。 | 保留四种格式，增加滚动与 large 展开；标题、副标题采用 Dynamic Type 缩放并允许完整换行。 |
| iOS15半屏、短横屏日期/时间弹层 | `SheetDetentsCompat.preferredHeight` 将 `.medium` 错误转换为固定400pt全高内容框；自定义400/420pt档也直接固定内容高度。 | iOS15使用真实medium/large档，高度档退large且不固定内容frame；日期/时间内容可滚动，iOS16以上同时提供large展开。 |
| 节假日编辑时弹出键盘、短横屏补班日期 | 编辑器与日期滚轮均为不可滚VStack；编辑器保存动作可能落到缩小后的视口之外。 | 两个弹层均可滚动；编辑器滚动会收键盘；原日期有效性、确认与取消逻辑不变。 |
| 英文/西文通用设置 | `SettingsFlatCard` 同行标题加固定宽分段控件；两项长标签的实测宽度就可能超过整张窄卡。 | 实测卡片宽度；空间不足时标题和分段上下排列，分段宽度服从卡片，内部真实高度设为36pt。 |
| iPad独立单次编辑、格式帮助和导入预览弹层 | 三个只含单页内容的 `NavigationView` 未指定样式，可能随 regular 宽度采用分栏。 | 显式使用 `.stack`，与仓内原生颜色选择器、日历导入、通用设置的单栏导航策略一致。全仓六个实际 `NavigationView` 均已显式设置该样式。 |
| 作息表列表页及编辑页复制命名、短横屏键盘 | 两处 `copyDialog` 使用不可滚VStack，输入键盘缩小可用高度后动作可能越出视口。 | 整个弹层可滚动，并使用现有iOS15/16兼容的滚动收键盘修饰符；原查重、复制确认与取消闭包不变。 |
| 导入输入、分享、详情内单次编辑时 native↔rail 切换 | 页面局部 sheet 随 `ScheduleScreen` / `ManagementPage` 布局分支替换而销毁，可能丢失当前呈现及草稿。 | 导入由 `AppRoot` 持有窗口级呈现状态；分享和详情由根 ViewModel 持有请求。详情请求固定课程、同周投影课程、展示日期和水合作息表快照，单次编辑继续由该稳定详情承载。 |
| 侧滑关闭动画尚未完成时打开新路由、同枚举新记录或深链 | 延迟完成闭包仍可能执行旧 `handleBack`，清掉新路由，甚至误丢弃新建表。课程深链只设置编辑课程时，也会被仍非空的旧 overlay 路由挡住。 | 根导航属性同步使旧关闭票据失效，再递增展示版本；延迟闭包仅消费当前票据，先消费再回调。课程深链在 VM 内确认真实记录后，按原返回语义清理旧未保存表，再显式进入课程编辑；无效ID保留原路由。 |
| 从非当前课表进入课程编辑或显式目标的手动新增 | 编辑器按主课表选择读写，可能把B表课程或新增课程写到当前A表。 | `CourseEditorContext` 固定记录所属表或显式目标，读取该表及水合作息；保存沿用同一目标，不切主界面选择。显式目标失效时禁止保存，不退回当前表。 |
| 单次编辑滑杆行的纵向滚动与小屏周次横拖 | SwiftUI高优先级drag会截获父滚动；历史simultaneous/方向锁方案在Pro12真实纵向滚动回归仍失败。UIKit改版后SE7横拖又未达到预期端点。 | 当前使用UIKit横向pan，识别前拒绝竖向，交还父ScrollView；横向位移改为从原始touch-down记录，结束/取消/失败清理状态。build30 SE8完整RangeSlider及两项occurrence均通过；build31另确认iPad全部控件已完整可见时拖动仍可用，SE保留严格滚动和值断言通过。 |
| 150/158pt WeekGrid及其窄列表头 | 原systemSmall统一使用Today脸；网格星期/日期被列宽省略并被圆角mask裁字。 | 仅`systemSmall && width < 150pt`使用Today脸；完整网格表头两行按自然文字宽度绘制，圆角仅作背景，保留Widget外层裁切。宽度闸已随build29通过，最后表头生产渲染回归已随build30通过。 |
| 五语普通文案与导入帮助示例 | 迁移资源残留实体/Android转义；WakeUP百分号需经过格式化保持，ICS示例串联替换破坏DESCRIPTION内部字面转义。 | 修56个资源值；示例改为只扫描输入一次，解开资源层而保留ICS转义。新增3项生产消费路径回归已随build33 SE10单测通过；该修正不等于五语所有页面的视觉通过。 |

## 生产文件与接口

- `NavStyleResolver.usesSideBySidePanes(windowSize:horizontalInsets:)`：独立于 rail 导航形态的双栏预算；当前布局开销为 156pt，每栏最低 360pt。
- `NavigationRailBar.scheduleIsPinned`：默认 `true`，保持原三槽组合项；`false` 时使用调用方提供的四个普通项。
- 根层消费在 `SleepyApp.railTabs` / `railContent(sideBySide:)`，用实际内容几何选择四入口单页或固定课表双栏。
- 其余修改位于 `ScheduleScreen`、`ShareScheduleSheet`。
- 第二轮追加 `SheetDetentsCompat`、`DateTimePickers`、`ReminderScreen`、`HolidaySettingsScreen`、`SettingsCards`。
- 第三轮追加 `CourseOccurrenceEditor`、`ImportSheet`、`PeriodTableEditScreen`、`PeriodTablesScreen` 的平台导航样式与复制弹层滚动。
- 窗口呈现追加 `ScheduleShareRequest`、`ScheduleCourseDetailRequest`，两处课表工厂均传入详情请求和呈现标志；详情期间禁用课表拖动。独立 `ScheduleScreen` 仍保留原局部详情后备入口。
- `OverlayDismissalState` 是无 UI / 计时器依赖的票据状态；根 `overlayScreen` / `editingCourse` 的每次赋值同步取消旧票据，`overlayNavigationRevision` 也覆盖同枚举换记录。`handleDeepLinkCourse` 直接使用注入仓库解析并完成导航。
- 管理页添加课程使用 `requestAddCourses(targetTableId:)` 捕获目标；`AppRoot` 在此次导入窗口内保存该目标，手动分支先关闭窗口，再进入显式目标编辑器。顶部加号仍直接手动新增。`CourseEditorIdentity` 包含显式目标，避免同路由切换目标时沿用旧表单状态。
- `IntRangeSliderTouchSurface` 使用UIKit横向pan，方向判定和位移均依据原始touch-down；`WeekGridDayHeader`复用生产基线文字，只有星期/日期两处启用默认false的水平溢出开关，以圆角形状作背景而不裁文字。`WeekGridWidgetLayout.usesTodayFace`同时控制view和provider的150pt宽度闸。

## 核验

以下为中央在2026-11-09至2026-11-10完成的实际批次，设备均运行iOS26.5模拟器。定向补测只证明列出的用例，不将不同构建合并成一次全套通过。Material版build30 SE8已确认2256项单测零失败及3项UI通过；build31 iPad3/SE9单次编辑、build32 iPad4增强导入及rail均通过。build33全目标test build和SE10完整2259项单测已确认；SE10最终UI、后续复测与发布核验统一见主文“最终验收统一区”。

| 设备与结果包 | 实际范围 | 已确认结果 |
| --- | --- | --- |
| iPhone SE，`se-final-ui-3` | 21个UI | 16/21通过；其中TableEdit 3/3、Quick Add 2/2、设备适配6/7、Sheet 3/5。后续仅对失败路径定向复测。 |
| iPhone SE，`se-final-5` | 2229单测、13个定向UI | 单测2229/2229；UI 9/13。已通过旧Form的单次草稿双向旋转、单次时间校验/删除取消、列表复制，以及双头周次滑杆和横向拖课。4个失败为追加导入、删除后退出及2条导入深链。 |
| iPhone SE，`se-final-6` | 上述失败路径及完整DeepLink套件 | 6/6通过：追加分组并持久化/备份、课程删除后回主界面、4条课程及导入深链。未重跑整个`se-final-5`套件。 |
| iPhone 17 Pro，build14 `pro-final-2` | 2239单测、19个UI | 单测2239/2239；UI 14/19。五个滚动或入口失败的后续定向结果见下一行。 |
| iPhone 17 Pro，build15 `pro-final-3` | 单次草稿1个、Sheet 5个、Material审计4个 | UI 8/10。Sheet 4/5通过（格式帮助、新表确认与两处复制）；Material 4/4通过。草稿用例在课程详情入口失败，Sheet单次编辑在保存动作可见性检查失败，均不能记为旋转丢草稿或保存逻辑失败。 |
| iPad mini（A17 Pro），`ipad-final-1`，2026-11-10 00:01结束 | 设备适配7个、Sheet 5个 | UI 9/12。设备适配5/7；导入草稿在输入前无键盘焦点、单次草稿在进入编辑前失败。Sheet 4/5通过；单次编辑未能完整显示custom控件。 |
| iPhone 17 Pro，build17 `pro-final-5` | 2252单测、6个定向UI | 单测2252/2252；UI2/6，整批失败。Export与AddCourse返回通过；Device occurrence、ImportAudit、未验证学校提示及Sheet occurrence失败。Device曾选到AX虚拟Switch子节点，后改为标识对应的整行checkbox；ImportAudit返回标识修正为`period_tables_back`。 |
| iPhone 17 Pro，build18 `pro-final-6` | JW生命周期/准入12项；4个定向UI | JW12/12通过；UI2/4，整批 `TEST EXECUTE FAILED`。ImportAudit通过12.437s、未验证学校提示通过18.593s；Device occurrence失败106.923s、Sheet occurrence失败107.786s，均停在reveal customRow。日志为 `pro-final-6.log:93–98,868–875,923,1009,2231–2256`。 |
| build19–25 | 全目标test build | 七次均成功（各构建日志`:408,:235,:231,:235,:365,:409,:222`），不等于设备验收通过。 |
| iPhone 17 Pro，build19 `pro-final-7` | 3个UI | 1/3通过：未验证学校提示19.218s；Device103.288s、Sheet120.616s失败。`pro-final-7.log:865,950,2252–2270`。 |
| iPhone 17 Pro，build21 `pro-final-8` | 2个occurrence UI | 0/2通过，总计236.145s，整批失败（`pro-final-8.log:2194–2208`）；提高最小pan距离仍未解决customRow完整可见性。 |
| iPhone 17 Pro，`pro-final-9` / `pro-final-10` | 各2个occurrence UI | 两批均0/2通过并 `TEST EXECUTE FAILED`。Pro9于`occurrence_start_time`的TextField快照查询失败，总计320.091s（`pro-final-9.log:1218–1227,2656–2681`）；Pro10于完整控件可见性断言失败，Device68.858s、Sheet76.258s，总计145.115s（`pro-final-10.log:618–625,1402–1427`）。最终验收见主对齐文档统一区。 |
| build26–29 | 全目标test build | 四次均成功：`final-package-build-26.log:352`、`-27.log:1587`、`-28.log:1538`、`-29.log:2150`；不等于设备验收通过。 |
| iPhone 17 Pro，`pro-final-11` / `pro-final-12` | 各2个occurrence UI | 两批均0/2通过，整批失败。Pro11 Device151.695s、Sheet158.907s完整可视区失败（`pro-final-11.log:960–967,2343–2368`）；Pro12 Device137.213s失败，Sheet63.051s在“滑杆行竖向拖动应滚动编辑器”的真实回归断言失败（`pro-final-12.log:1056–1063,1481–1506`）。 |
| iPhone 17 Pro，build28 `pro-final-13` | 2252单测、2个occurrence UI | 单测2252/2252；UI1/2，整批失败。Material Device75.950s通过；Sheet135.965s仅在取消删除后最后`detail_close`可视区失败，helper误将详情页头按编辑器滚动viewport排除（`pro-final-13.log:5357–5360,5789,6987–7011`）。 |
| iPhone 17 Pro，build29 `pro-final-14` | 2255单测、1个Sheet occurrence UI | 单测2255/2255，Sheet166.019s通过，整批 `TEST EXECUTE SUCCEEDED`（`pro-final-14.log:5365–5368,6670–6684`）。未重跑Device或RangeSlider；新增前三项Widget回归在本批通过，后加表头回归本批未包含，后由build30 SE8通过。 |
| iPhone SE，build29 `se-final-7` | Device、RangeSlider、Sheet三个定向UI | 0/3通过，整批失败：Device34.716s、RangeSlider51.234s、Sheet26.188s（`se-final-7.log:123–128,269–272,439–465`）。两项occurrence仍查旧Switch子节点，日志query/行号与当前源码不匹配，原因未证实；RangeSlider横拖28.133pt、pitch14.0667pt时起点只到2而非3，修正后的build30 SE8结果见下行。 |
| iPhone SE，build30 `se-final-8` | 全目标test build；2256单测、3个UI | 构建成功（`final-package-build-30.log:1781`）；单测2256/2256，26.784s；Device occurrence82.358s、RangeSlider131.005s、Sheet occurrence141.812s均通过，整批 `TEST EXECUTE SUCCEEDED`（`se-final-8.log:5371–5373,5882,6283,7504,7518`）。 |
| iPad mini，build30 `ipad-final-2` | 设备适配3个、Sheet1个、页面截图4个 | UI7/8通过，整批失败（`ipad-final-2.log:1088–1101`）。导入草稿30.883s、rail17.053s、Device occurrence69.337s及4张截图通过（`:116,220,651`）；Sheet47.931s在表单已全可见、没有滚动余量时仍要求20pt移动而失败（`:929–937`）。旧导入只验证草稿，没有完整可见性断言。 |
| iPad mini / iPhone SE，build31 `ipad-final-3` / `se-final-9` | 全目标test build；两端各1个Sheet occurrence | 构建成功（`final-package-build-31.log:286`）；iPad136.142s、SE178.177s均通过，两批均 `TEST EXECUTE SUCCEEDED`（`ipad-final-3.log:1149–1163`、`se-final-9.log:1425–1439`）。仅全部控件已完整可见时使用all-fit分支，其余情况保留至少20pt滚动，两支均保留节次值不变断言。 |
| iPad mini，build32 `ipad-final-4` | 全目标test build；增强导入及rail共2个UI | 构建成功（`final-package-build-32.log:702`）；导入36.673s、rail15.111s，2/2通过，整批 `TEST EXECUTE SUCCEEDED`（`ipad-final-4.log:146,248–262`）。增强导入断言输入和预览完整可见，中央逐张截图核查确认；旧iPad2结果不证明这一点。 |
| iPhone SE，build33 `se-final-10`单元测试 | 全目标test build；完整2259单测 | 构建成功（`final-package-build-33.log:587`）；2259项零失败，30.358s（`se-final-10.log:5377–5380`），含新增3项资源单次解码、五语ICS解析与WakeUP示例回归（`:3316–3325`）。本行只确认单测，不宣称整批UI通过；SE10 UI与后续复测由主文最终区记录。 |

SE的中英文Top Bar各1个用例另已通过。对应结果包与日志位于本任务`work/verification/`，以表内包名匹配；上述数字取最终`Executed`及用例结果，不以进度输出预记通过。

### 附件结论与本轮修正

- 旧Form附件已定位刘海起手、Form/滚动条viewport差异与slider高优先级drag拦截；Pro3其余四个Sheet已通过。最终Material页不能由旧Form通过或测试诊断外推。
- Material页已增加FocusState/ScrollViewReader处理截图所见旋转键盘遮住描边框下沿，日期显式app locale；checkbox使用整行标识并保留值、取消和持久化断言。Pro7/Pro8的customRow为y=295.667…343.667，viewport为y=78…340；将不足10pt pan推测改为32pt仍未解决。
- build22改从可见非slider实体内容起手，旋转后不先手滚，直接检查键盘及完整56pt输入框自动reveal。build24的simultaneous gesture、方向锁及后加GestureState取消重置均为历史方案，Pro12真实竖向滚动回归仍失败。当前共享IntRangeSlider以UIKit横向pan在识别前拒绝竖向手势，结束/取消/失败清理状态；原始touch-down完整位移实现已随build30 SE8的RangeSlider及两项occurrence通过。Pro10后fixed/custom查询已改为descendants(any)；SE7旧Switch query与源码行号不符的底层原因仍未证实，后续通过不能倒推根因。
- build31的all-fit条件逐一检查日期、固定日期、节次摘要、两端滑杆、custom、保存及删除控件是否完整处于前景可视区；仅当全部满足，才在同一竖拖后复查全部完整可见。否则仍要求custom至少上移20pt；两个分支都要求节次起止保持1/2。iPad3与SE9分别通过，手机严格滚动和值断言保留。build32另为导入增加输入和预览完整可见断言，截图由中央确认；iPad2旧导入通过只证明旋转后的草稿保持。
- `pro-final-3-attachments/audit-{manage,today}-{light,dark}/`的四张截图已逐张目检：截图前等待0.8秒后，Manage与Today的浅/深色状态干净，无旧图的Schedule过渡叠影。该结论仅覆盖这四个稳定页面截图，不扩展为全App视觉验收。
- 五张生产Widget脸PNG已逐张目检，范围限于固定样例及对应离屏family；不代表主屏幕WidgetKit添加、时间线刷新或全部偏好组合。build19另将JW背景设为AX hidden，相关最终验收范围统一写入主对齐文档。
- Widget后续新增共4个回归：149/150/158pt生产切脸、空教室/空时间单侧metadata、完整网格不生成Today课程边界，以及20pt窄列中英文星期/日期完整墨迹与不裁切的生产表头像素对照。前三项在build29通过并输出4张尺寸/无教室PNG（`pro-final-14.log:5045–5059,5200–5201`）；第4项随build30的SE8完整2256项单测通过；8张新增尺寸、无教室和中英文表头PNG已逐张目检，仍不代表主屏幕WidgetKit。

本切片已有`NavStyleResolverTests`、窗口呈现/深链及编辑器目标回归；相关源码语法和空白检查通过。所有Xcode构建、单测及UI运行由中央执行，审计进程未另启构建或模拟器。辅助滚动继续要求目标`isHittable`且完整frame位于所属滚动区域、窗口、导航栏及键盘外；输入前必须确认键盘焦点，复制确认后必须先等新记录出现。

主要测试锚点为`rail_schedule_<today/manage/mine>`、`rail_<schedule/today/manage/mine>`、`share_format_json/text/ics/native`、`date_picker_confirm/cancel`、`period_table_copy_name/confirm/cancel`、`period_table_save/preview_confirm/preview_cancel`、`occurrence_editor/cancel/fixed_date/custom_time/start_time/end_time/save/delete/error`及`format_help_close/when`。

## 尚未纳入此切片

- 普通设置页大多仍直接使用 `.system(size:)` 固定字号；本次只修分享弹层的动态字体。不能据此宣称全App已支持辅助功能最大字号。
- 最低部署版本为iOS15.6；兼容分支已有源码修正，但当前iOS26.5模拟器不等于iOS15.6真机验收，需单独确认系统detent与键盘交互。
- 当前 `WindowGeometryProbe` 已从所属 UIWindow 读取窗口边界，未重复修改已修复的旋转尺寸探针。
- iPad已有iPad1的12项、iPad2的8项实际结果及iPad3定向Sheet、iPad4增强导入/rail补测，具体通过与失败范围逐批列于上表；不把重复用例合并为新的全套通过数。真实窄/宽Split View、分屏键盘、Stage Manager及其他窗口尺寸尚未纳入本次运行。

## build30–33补测与文案范围

build30 SE8使用显式xctestrun、强制重新编译三个UI测试文件并重装runner，完整SleepyTests **2256项、0失败**（26.784s），Device occurrence、RangeSlider及Sheet occurrence **3/3通过**。SE7旧query执行不匹配的底层原因仍未证实。新增4项Widget回归和8张生产PNG均已通过/输出并目检；build31与32的平板/手机补测范围见上表。

五语56个资源值修复包含6个实体、5个WakeUP示例格式化百分号和45个普通Android转义残留；45个中19个已确认有当前Swift消费者，其余26个只确认资源修正。五语各1200键、键集与格式占位符已作静态核对。示例单次扫描解码保留ICS的9个真实换行、DESCRIPTION内2个字面`\n`并验证生产解析器读到教师；WakeUP保留2个真实换行及原百分号编码，AI协议提示未纳入该解码路径。新增3项回归随build33 SE10完整**2259项、0失败**（30.358s）通过；不据此宣称所有语言整页无溢出。最终UI、后续复测与GitHub发布核验统一见主文最终验收区。

窄至150/158pt且显示七天的网格沿用Android标签的20pt最小列宽及外层裁切，完整表头文字可越出单列，极窄尺寸会拥挤并裁掉右侧列。新增图片如实展示该基线行为，不宣称所有尺寸均无裁切或逐像素相同。

## 最后导入UI增量（build34）

build33 SE10完整单测2259项零失败，但UI两项失败：旋转后可见性断言及续输已执行，多次等待动画结束导致180s超时；旧FullText偏移点击落在卡片空白处未聚焦（25.661s）。生产合并显露请求并取消旧任务、用局部无动画事务定位，整卡点按可聚焦。FullText回归直接验证完整文档值和键盘上方预览动作，保留配置/保存/无seed重启断言。build34 SE11导入旋转29.528s、完整文本导入43.014s，2/2通过；iPad5增强导入34.097s，1/1通过。两批均`TEST EXECUTE SUCCEEDED`，最新横竖屏截图已目检。无测试时限放宽或全局动画关闭；最终发布信息见主文验收区及交付报告。
