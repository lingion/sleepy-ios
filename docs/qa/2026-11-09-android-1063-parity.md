# Android 1.0.63 对齐核查（2026-11-09）

> **2026-11-10更正**：本文149/150/158pt小号切脸及窄small全周结论已由[最小小组件复核](2026-11-10-widget-minimum-size-parity.md)取代。当前systemSmall的周列表/周视图使用三天窗口，周网格使用Today脸；补三天调休与定日课取课修复，完整单测2274项零失败。以下先前批次保留为历史证据。

## 精确基准与证据边界

- Android：`v1.0.63` annotated tag `a821c6ace1e3e5dbfd02c7fbd738bf2ca1c8a223`，解引用提交 **`b16aa84d11c250acdf644cd8b7812ab27d03dc6a`**（2026-11-02 00:56:13 +0800）。`git ls-remote upstream refs/tags/v1.0.63 refs/tags/v1.0.63^{}` 与本地一致。
- 前版：`v1.0.62` → `10adc2475023e6b32493f8a14a1d7104f38d0852`。以下 Android 路径、行号均来自 `git show v1.0.63:<path>`，不是当前 Android 工作目录。当前 Android HEAD `373bfedb` 及未提交的拖课/控制台/性能工作不属于本基准。
- iOS 初始快照：`91f128e`，`local-device-test-20261107`；本轮修复在独立工作树分支 `fix/ios-android-1063-alignment`。旧矩阵与 README 只提供检索线索，结论根据生产调用链重新核对。
- 当前完整单测为build33 SE10 **2259项、0失败**；最后UI增量为build34 SE11导入旋转和长文本导入2/2、iPad5增强导入1/1通过。build30 SE8的3项关键UI及build31两端Sheet也已通过。历史失败保留；各批次范围、截图与发布目标统一见末节“最终验收统一区”，不将定向补测合并为一次全套通过。原Android和iOS未提交工作目录保持原状。

路径缩写：A=`app/src/main/java/com/lingion/sleepy/`（Android 标签树），I=`Sleepy/`（iOS）。

## 页面、设置和响应式矩阵

| 范围 | Android 1.0.63 证据 | iOS 实际入口/消费者 | 核查结论和验收点 |
| --- | --- | --- | --- |
| 四个根标签 | `A/ui/nav/SleepyNavHost.kt` MainRoute：Schedule/Today/Manage/Mine | `I/SleepyApp.swift` mainContent、tabContent、nativeTabs、railTabs | 四页均有生产入口；默认课表视图取 AppPrefs，不把用户临时切换写成启动偏好。 |
| 手机底栏 | `PillNavigationBar.kt`、MainRoute compact 分支 | `PillNavigationBar.swift`、`util/NavStyleResolver.swift:65–77` | 贴底/悬浮两项已接。iOS 26 悬浮由系统 TabView 承接玻璃；较早版本为自绘 material 胶囊，没有 Android AGSL 物理透镜。这是明确平台视觉差异，须截图验收。 |
| iPad 横屏双栏 | `SleepyNavHost.kt:477–648`：非Compact且宽≥高，左课表固定、右Today/Manage/Mine，80宽rail、12沟槽 | `NavStyleResolver.swift`、`SleepyApp.railTabs`、`NavigationRailBar.swift` | 宽≥600且宽≥高时使用rail；另按实际可用内容宽预算双栏：扣除80pt rail、32pt外距和44pt总栏间距后，每栏至少360pt，即有效宽≥876pt。600–875pt使用四个rail入口切换单页；双栏使用三槽合并Schedule+当前右页。窗口依据所属UIWindow.bounds探针，不依赖设备方向枚举。 |
| iPad 竖屏/窄分屏 | `SleepyNavHost.kt:482–487` PR#235几何闸 | `NavStyleResolver.swift`、`WindowGeometryProbe.swift` | 已回落手机单栏。已有断点/几何/窗口探针单测；`ipad-final-1`的竖屏原生导航与rail旋转选择保持通过。窄/宽Split View及Stage Manager窗口变化仍需实际验收。 |
| 课表周/网格/今日 | `ScheduleScreen.kt`、`CourseTableView.kt`、`TodayScreen.kt` | 同名Swift页、`DailyAgendaScreen.swift` | 网格/周切换、周选择、详情、冲突、日期与别名均有消费者；不以同名文件证明所有像素相同。 |
| 课程编辑/单次课程 | `AddCourseScreen.kt`、`OccurrenceEditor.kt`、`SingleOccurrenceCourseForm.kt` | `AddCourseScreen.swift`、`CourseEditorContext.swift`、`CourseOccurrenceEditor.swift`、repository.saveOccurrence | 单次/全组、定日和保存链存在；**本轮补固定编辑owner**，读取、保存、删组、组色和作息均跟随课程所属表或显式加课目标。生产现为Material ScrollView、日期卡、复选框和描边时间输入，并以FocusState/ScrollViewReader处理键盘/viewport变化、显式app locale。旧Form的SE通过保留为历史；Material版Pro13 Device、Pro14 Sheet分别通过，SE7两项失败的执行查询与当前源码不匹配，build30结果见最终验收统一区；最终改版验收见末节。 |
| 空格快速加课 | `QuickAddCourse.kt`、ScheduleScreen.openAddCourseAt | `QuickAddCourse.swift`、`SleepyRoutes.swift`、ScheduleScreen.onAddAt | 预填星期、节次跨度、双把手、外点消费、保存链已接；SE两个Quick Add用例已验证精确预填、保存持久化和外点取消。iPad手势尚未最终验收。 |
| 管理页 | `ManagementPage.kt:89–150`：当前摘要可编辑、全部课表、新建课表/添加课程/作息/导出四卡 | `ManagementPage.swift`、`AppRootViewModel.requestAddCourses`、ImportSheet | 初始四卡中的加课仍直接进手动编辑，不能据入口外观判完整对齐。**本轮改为固定targetTableId的加课来源页**；手动是其中一项。新建课表保留独立方法页，解析后直接新建配置，不能替换当前表。 |
| 添加课程批量流程 | `ImportSheet.kt:138–175,299–305,635–706,1019–1037`、`CourseSelectionSheet.kt:56–60,92–133` | `imports/AddCoursesImport.swift`、CourseSelectionSheet、ImportPreviewDialog、CourseImportPolicy、repository.appendImportedCoursesWithBackup | **本轮补齐**已有课表、教务/草稿、WakeUP、文本、文件、外部文本及手动来源；批量先逐组勾选，再按默认备份/跳过冲突追加。来源与手动入口已通过；选组→追加→冷启动→原表备份在se-final-6通过。JW生命周期、呈现闸、投递及分组回归均已进入build14的2239项通过套件，真实账号和各来源完整UI仍有独立边界。 |
| 我的页 | `MineScreen.kt:89–100,153–158`三统计为表/课/作息且全可点；113–129七导航项 | `MineScreen.swift`统计及导航消费者 | **本轮已修正**初始第三项当前周统计为作息统计，并补对应导航、移除多余导出行；导出仍从管理页进入。原生我的页指定路径在Pro和iPad通过。 |
| 全部课表/课程清单 | `AllTablesScreen.kt`、`CourseListScreen.kt` | 对应Swift页和root路由 | 入口及独立列表存在；复制/删除/默认表、分组详情须统一回归。 |
| 编辑课表手动作息 | `EditTableScreen.kt:302–305`唯一`reorderEnabled=true`调用；`TimeSlotEditor.kt:397–552`长按排序 | `TimeSlotEditor.swift`初始只有编辑/增删，`EditTableScreen.swift:200`未传重排参数 | **本轮修复包**：长按行拖动、合法时间序/连续性、反馈、编号重排，经既有onRowsChange→草稿→保存链落库。 |
| 独立作息编辑/绑定 | `PeriodTableEditScreen.kt:263`未开启重排；PeriodTableBindTab与删除冻结 | `PeriodTableEditScreen.swift`、TimeSlotEditor绑定页、repository.deletePeriodTable | 不扩大重排入口；绑定/解绑、共享内容冲突策略和删除冻结沿用现有链路。 |
| 外观/主题 | `AppearanceScreen.kt`、`CustomThemeEditorScreen.kt`、`Theme.kt` | 对应Swift页、ThemeColorVector、SystemColorScheme | 自定义主题、课程配色、系统取色和色槽动画已接；iOS公开tint派生不能宣称读取壁纸RGB。 |
| 显示/节次头 | `ScheduleDisplayScreen.kt`六基线滑杆；`PeriodHeaderSettingsScreen.kt:174–190`dash/center | `ScheduleDisplayScreen.swift`、NativeBaselineSlider、PeriodHeaderSettingsScreen、PeriodHeaderFormatter | 六基线、布局/悬挂量、隐藏时间、时间对齐已有真实消费者；需要字号、紧凑列及RTL实际截图。 |
| 通用/实验室 | `GeneralSettingsScreen.kt:286–850`显示、导航、语言、实验室、迁移；undo默认5/0关/负数不限 | `GeneralSettingsScreen.swift`、AppPrefs、UndoDepthSettingsRow、UndoManager | 显示模式、子信息、双列/平衡、隐藏空日、别名、日期、可见日、行高/捏合/晚间/分隔/长间隔、撤回深度和迁移均已接；高刷新率为平台调度差异。 |
| 提醒/调休 | `ReminderScreen.kt`、TableReminderScreen、HolidaySettingsScreen、CalendarImportDialog | 对应Swift页、ReminderRescheduler、ClassDayActivityCore、SystemCalendarManager | 通知权限、表级提醒、今日/明日/课前、调休与日历已有链路；厂商原子岛/勿扰不机械移植，ActivityKit需系统与真机验收。 |
| 导入/导出/备份 | ImportSheet、SchoolSelectScreen、ScheduleParser/Exporter、MigrationExecutor | 对应Swift入口与repository导入事务 | WakeUP/文本/ICS/原生/迁移基础路径存在；**加课组选择/ImportDecision备份追加、JW选中作息原子绑定为本轮补齐**，不混记为初始已接。WakeUP本标签只在线读取分享码，没有在线创建分享码。 |
| 学校目录 | `assets/schools.json` 4140条；catalogId唯一 | `resources/schools.json`同4140条，ID集合完全相同 | 4137条逐字段相同；3条状态差异见下，不可把候选目录数视为真实登录成功数。 |
| 小组件 | WidgetManagement/Gallery/Edit、AppWidget providers | WidgetKit管理/引导/编辑、五类widget | 平台组件生命周期不同；强制滚动无消费者开关已删。本轮画廊改为固定样例课程复用五个生产EntryView，并移除外包裹、统一同行预览框；最后审计另补本地午夜reload及WeekGrid小号今日课结束边界，详见下节。 |
| 关于/开源 | AboutScreen/LicenseScreen/UpdateChangelogDialog | AboutScreen/LicenseScreen | 版本/作者/许可存在；iOS已按分发策略移除应用内GitHub安装更新，不能恢复Android APK更新路径。 |
| 动效/控制台 | PR#255、#265、#267；SleepyMotion、loopback console | SleepyMotionPolicy、SleepyMaterialTransition、NativeCourseDrag、DEBUG console | 大部分此前增量已接，不能再按旧审阅表统一记为全缺；Android任意坐标/系统键/Fluid Cloud控制能力无iOS对等实现，能力标志已有明确unsupported。 |

## 1.0.62 → 1.0.63 用户可感知增量逐项

源证据：`docs/release-notes-v1.0.63.md` 与 `git log v1.0.62..v1.0.63`；不是当前主干变化。

| 提交/PR | 增量 | iOS现状和检查文件 |
| --- | --- | --- |
| `c2490785` #266、`e4f38f45` #272 | 超椭圆玻璃底栏、1.25透镜、主题色共存 | iOS26系统TabView；旧系统FloatingBar material兜底，平台视觉差异如上。 |
| `6e5961ee` #260 | 拖课停边每500ms连续翻周、源周/目标周区分、磁吸 | NativeCourseDrag、CourseDragPolicy、CourseOccurrenceIdentity已接；Pro首批7项中6项通过，涵盖实际移动、持久化、撤回和左边缘连续翻周。右边缘首次失败，build14同用例保留原断言复测通过；详见末节，不将其改写为首次整批全绿。不要将1.0.63之后Android边缘修复混入基准。 |
| `daeb3aad` #225 | 单次课程编辑、快速加课 | CourseOccurrenceEditor、QuickAddCourse与保存事务已接。 |
| `11b03ff5` #244、`d864c6fc` #253、`93bca96e` #261 | 双头节次/周次滑杆、九处幽灵基线 | **更正原结论**：初始已有若干单值基线消费者，但AddCourse全局周次、block节次/block周次及Occurrence节次仍为数字步进。本轮新增IntRangeSlider并接这四处，捕获打开时基线；7项XCTest已有通过证据。SE双端点拖动、Apply、保存和无seed重启在se-final-5的旧手势实现通过；共享控件改用UIKit后，SE7横向拖动未达预期端点，最新原始touch-down位移修正build30结果见最终验收统一区。 |
| `baa310d9` #240 | 多步undo/redo、实验室深度 | UndoManager双栈、repository.writeWithUndo和设置已接，失败事务不发布历史的修复已在初始快照中。 |
| `2acceb74` #255 | shared-axis/container、popup/按压/展开/主题色动效 | SleepyMotionPolicy、SleepyMaterialTransition、主题色向量已接；本轮作息拖行补settle/取消与合法落点反馈。 |
| `0840b76b` #259 | 节次起止时间dash/center对齐 | PeriodHeaderSettingsScreen/Formatter已有设置与渲染消费者。 |
| `7c077f80` #235 | 平板竖屏回单栏 | NavStyleResolver双闸+WindowGeometryProbe已有实现。 |
| `4371ae5f` #161 | 管理/导入入口整合 | 初始四卡和方法页只覆盖部分入口；本轮把直接手动加课改为指定表来源选择，并补逐组勾选、两项ImportDecision和原子备份追加。我的页遗留差异单列修复。 |
| `85683759` #248 | WakeUP v6.1.70在线分享码读取 | data/share三文件、WakeUpShareImportSheet、粘贴/文件/外部路由已有实现；边界溢出防护已有新增测试。 |
| `2b896ffd` #254、`26c1adbb` #251、`ef60b35c` #247 | WakeUP目录、264拾光校、282脚本、43协议路由 | 目录ID全集一致，拾光资源/桥接已有实现；目录候选仍须保留未验证状态。 |
| `9d5439a7` #243、`8c9c34c3` #232、`e4f38f45` #272 | 南开TypeB、NBCC UA、Kingo导轨/无教室/周末修复及佳木斯转正 | ClassicEams、WebViewConfigBuilder、JwKingoZxParser与HTMLRegressionTests存在；三校目录开关与Android不同。 |
| `e4f38f45` #272 | 选校取消返回方法页；移除列表未实测后缀 | JwImportReturnState/SchoolSelectScreen/ImportSheet已有实现。 |
| `f63131e1` #231、`0e999872` #245 | 组件画廊行等高、去包裹高亮 | 本轮按同行最大面积family取共同框比例；实际脸按自身比例Fit居中，去除padding10/background/Card外包裹。 |
| `86e76292` #238、`763b29f9` #237 | monochrome启动图标/55%×60%几何 | Android平台图标与iOS资产不同，须按iOS图标验收，不添加Android资源格式。 |
| `654ec913` #234、`8b0729cf` #226 | vivo组件声明移除、原子岛协议隔离 | Android专有；iOS WidgetKit/ActivityKit单独验收。 |
| `f0eb85f2` #265、`4e82a1a3` #267 | 本机loopback调试台及内存治理 | iOS DEBUG控制台已有接线；不计入公开用户功能或生产远程控制。 |

## 目录三个精确差异

按catalogId匹配，忽略数组排序后比较所有字段：

| catalogId | Android v1.0.63 | iOS初始快照 | 行动 |
| --- | --- | --- | --- |
| `moe:4123010222` 佳木斯大学 | `kingo_new`、status缺省（归一supported）、enableFetch缺省（默认false） | status=`unverified`、enableFetch=`false` | 保留有意证据边界；Kingo修复已迁入，canImport允许用户确认后尝试，无false开关阻断。 |
| `moe:4133012645` 宁波城市职业技术学院 | status=`supported`、enableFetch=`true` | status=`unverified`、enableFetch=`false` | 保留状态；classic_eams专用抓取已接，exact host触发初次加载桌面UA，不依赖enableFetch。 |
| `N_南开大学` | enableFetch=`true` | enableFetch=`false` | 保留false；classic_eams按type直接派发抓取，不读enableFetch；其余字段一致。 |

上述三校差异由 `fddb4671d3fc495796b6666b790132892c7e9c3c`（2026-11-04）有意保留，见 `docs/catalog-v1063-protocol-migration.md:35–37` 与 `docs/catalog-v1063-shared-wiring.md:52–54`。`JwSchoolInfo.canImport`原已表达准入条件，但生产选校和登录草稿恢复漏用完整门控。本轮以共享 `JwImportEntryRoute` 补齐：unverified或不可导入学校先提示，确认后仅 `unverified && canImport` 可尝试，supported正常进入；已解析草稿沿用配置/预览路径。Android依据为 `JwImportActivity.kt:505–510,791–798,925–942`。新增7项路由随build17通过，build18 JW12项再次全过（`pro-final-6.log:68–98`）；未验证提示/关闭返回选校UI在Pro6及设置背景AX hidden后的Pro7均通过（`pro-final-7.log:950`，19.218s），不替代真实账号验收。

`JwWebViewLoginScreen.swift` 对classic_eams直接派发，初始UA通过 `JwClassicEamsFetch.initialDesktopUa` 在首次load前应用。`enableFetch` 只被部分强智策略读取，并非全局禁抓取位。现有 `JwCatalogMigrationTests`、`JwClassicEamsRegressionTests` 与 `JwKingoHTMLRegressionTests` 已锁定目录边界与解析样例；这些不替代iOS真实账号验证，因此本轮不提升三校状态。

## 组件画廊基准与本轮修复

- Android `WidgetGalleryScreen.kt:143–151` 通过 `painterResource(previewImageRes)` 读取静态PNG；`tools/gen_widget_previews.py` 使用高等数学、英文阅读、A305等固定样例，布局参照真实renderer，并不读当前用户课表。iOS也可以用固定样例，无需为此引入数据库读取。
- Android `WidgetGalleryData.kt:23–34` 每排以声明面积最大变体的宽高比统一预览框，其他预览通过Fit居中；本轮 `Sleepy/widget/WidgetGalleryData.swift` 新增canonical iOS family尺寸和同行最大面积策略，处理混排和最后不满一行。GalleryCard保持顶对齐并使用共同框比例，脸按原始比例缩放。
- Android #245 的最终GalleryCard是裸Column，无外层背景/内边距；本轮移除iOS `.padding(10)`、surfaceContainer背景和medium圆角，只保留实际widget脸自身的圆角与背景。
- 新增 `WidgetGalleryPreview.swift`：固定2026-10-19到25日、15门样例课，今天面为20日周二、两天面为20/21日，使用本地化课程名、真实节次时间和教室。直接复用五个生产EntryView，不调用Provider、loader或repository。预览专用可选family/date环境同时支持普通app背景；未注入时保留WidgetKit原行为。示例课程固定，渲染沿用组件现有外观偏好。
- `WidgetGalleryParityTests.swift` 共4个测试已在build14通过（`pro-final-2.log:5082–5097`），覆盖混排/不满行/单列比例、注册表完整映射、15课样例日期时间一致性，以及**五个生产预览脸**的共同行框离屏渲染。五张PNG并不是五个独立测试；输出日志为`:5084–5088`，核查副本位于 `/Users/kerrylee/Documents/Codex/2026-11-09/g/work/widget-parity-1063/ios-after/`：`WeekGridWidgetV19.png`、`TodayWidgetRV.png`、`WeekListWidgetRV.png`、`WeekViewWidgetRV.png`、`TwoDayWidgetRV.png`，五张PNG均已由中央逐张目检。该目检限于固定样例及对应离屏family布局。
- `WidgetFaceGeometryTests.swift` 另5项已通过（`pro-final-2.log:5068–5081`）：Canvas真实文字墨迹基线偏移、七天样例及标签版本课程色、跨周同星期不误高亮、教室文字预留区、双日footer按实际列宽预算。这些证明列出的几何/图像性质；不替代主屏幕WidgetKit添加、时间线刷新、所有family及偏好组合验收。五个WidgetKit kind和iOS添加引导保留平台行为。
- 后续窄尺寸审计补齐三处生产差异：`WeekGridWidgetLayout.usesTodayFace`仅在`systemSmall && width < 150pt`使用Today脸，150/158pt小号及medium/large保留网格，provider同步采用`context.displaySize.width`；`WidgetMetaLine`在时间或教室仅有一侧时不附加分隔符；网格星期与日期不再按窄列省略文字。最后一项由生产`WeekGridDayHeader`仅对两行文字启用`WidgetBaselineText.allowsHorizontalOverflow`（默认false），在文本frame前取自然宽度，并用`RoundedRectangle(cornerRadius: 14).fill(...)`作为背景，避免表头圆角裁字；Widget外层18pt圆角裁切保留，对齐Android Canvas完整`drawText`语义。
- 上述范围新增共4个回归：实际小号生产脸149/150/158pt像素对照、单侧metadata实际渲染、完整网格不生成Today课程边界，以及窄列中英文星期/日期完整墨迹与不裁切的生产表头像素对照。前三项随build29的Pro14完整2255项unit通过（`pro-final-14.log:5045–5059,5200–5201,5365–5368`），并输出4张尺寸/无教室PNG；第4项随build30的SE8完整2256项单测通过；8张新增尺寸、无教室和中英文表头PNG已逐张目检，仍不代表主屏幕WidgetKit验收。

## 组件时间线边界修正

- 最后审计发现WeekGrid/WeekList/WeekView原用单条entry及固定6小时reload，可能将午夜前的周/窗口数据带到下一日。`WidgetBoundaryScheduler.swift`现使用Calendar本地民用日，reload取“当前时间+6小时”和“下一本地午夜”的较早者；三类provider均消费该策略。Android依据为 `WidgetUpdater.kt:34–37,50–70` 的下一本地午夜更新。
- WeekGrid原先让全部systemSmall展示今日脸，且未包含课程结束后1分钟的边界entry，脸用渲染时Date判断时间。当前只有`systemSmall && width < 150pt`的今日场景生成reload前的end+1边界，显示日期/分钟跟随entry；宽150/158pt的完整网格、其他family与非今日场景不额外生成。Android `WeekGridWidgetProvider.kt:129–139` 使用Today管线，`WidgetBoundaryScheduler.kt:40–47` 将WeekGridSmall纳入边界族，宽度闸同时服从标签版本的完整网格选择。
- 新增6项 `WidgetSemanticsTests` 覆盖跨周午夜、6小时上限、DST、课程结束边界、family/非今日闸及午夜不延用旧数据。这6项已在build17完整2252项unit中通过，所属 `WidgetSemanticsTests` 通过证据为 `pro-final-5.log:5169–5267`。provider逻辑测试和离屏图目检均不等于主屏幕WidgetKit实测通过。

## 今日页调休日期与 Material 修正

- Android `TodayScreen.kt` 及紧凑 Today pane 用 `courseDateFor(today) ?: today` 计算周次和学期状态；iOS初始直接使用自然今天。本轮新增 `TodayDisplayContext`，日期标题继续显示真实今天，周次和学期前/后状态跟随补课源日期，避免跨周或学期外补课显示错误空态。
- `ScheduleRenderingB5Tests` 新增5项TodayContext回归已在build14通过（`pro-final-2.log:4128–4138`）：学期开始前/结束后的有效学期内源日期、普通节假日及未映射自然日、跨周补课源周、无当前课表回退。全套该类15项通过；5项新增回归不能写成5个UI渲染场景。
- 管理页28pt粗体标题、摘要独立按钮布局、分段轨道重复偏移及小组件管理默认Card颜色/12pt圆角均已修正并纳入build14。确切Android Material3 `1.5.0-beta02` AAR证据、逐页静态范围和平台边界记录于 `docs/qa/2026-11-09-material-ui-parity.md`。Pro管理/今日浅深两色4个UI入口与截图用例在 `pro-final-3.log:3304,3337,3370,3403` 再次通过，截图前等待0.8秒使过渡完成；附件为 `pro-final-3-attachments/audit-{manage,today}-{light,dark}/`。四张图均已逐张目检，浅深色页面稳定，未见旧图的Schedule过渡叠影；该结论不扩大至所有内容和字体组合。
- 单次课程生产编辑器 `CourseOccurrenceEditor.swift` 已从原生 `Form/Section` 改为主题 `ScrollView`：标题22/副标题16、20pt页面边距、描边日期卡与独立日期确认sheet、固定/自定时间复选框、节次范围滑杆、56pt描边时间输入、48pt主色保存/错误容器删除动作。原保存、冲突提示与删除事务沿用原链路。Pro6后的实际截图又显示旋转键盘遮住描边时间字段下沿，build19生产增加FocusState与ScrollViewReader，在键盘/viewport resize后将聚焦字段重新居中，并为日期formatter及DatePicker显式指定app locale。源码修正与设备通过分别记录，最终结论见统一回填区。

## 作息重排实现约束

- Android生产唯一开启入口是编辑课表 `EditTableScreen.kt:304`；独立作息编辑、导入确认均保持默认关闭。
- 标准行移动后按1…N重新编号，保留start/end；before/after及0/负node保持原节点和物理位置，不能作为拖动源或目标，并有可见提示。原版本全部行重编号会删除before节点语义，iOS的保存映射对负/0课程又保留原node，故不照搬此数据丢失行为。
- 既有表单onRowsChange负责智慧配置重播种、作息草稿和保存策略；手势不直接写库。课程来自当前编辑的tableId，即使它不是主界面选中课表；读取失败关闭拖动。
- 落点要求每个非空白行严格可解析且start<end，标准行start非降序；完全空白行豁免。edge通过insertEdgeNode追加在数组末尾，不能按数组位置与标准行比较时间。正常课程跨度不得因旧节点到新节点置换被拆散；ownTime和单节课豁免。
- Android测试注释声称仅尾行可拖，但实际生产函数/手势未限制尾行；iOS依据生产代码，不增加未存在的尾行限制。Android置换代码把新→旧索引误当旧→新，iOS保护课程连续性时使用正确映射；差异有独立回归说明。
- 本轮新增 `TimeSlotReorderParityTests.swift` 共14个测试，包含反向置换、当前编辑表课程、真实仓库保存重映射、before0/-1尾部追加后的保存/重开/undo/redo；build14已全部通过（`pro-final-2.log:4659–4660`）。SE三项真实作息编辑UI通过：合法重排保存并重开、非法倒序拒绝、独立作息按钮路径（`se-final-ui-3.log:3743,:3849,:3948–3950`）。
- `ScheduleEditSessionTargetTests.swift` 共2个测试：真实双表分别绑定不同作息，先等主界面选中表及其作息加载，再走编辑页同一生产入口建立非选中表会话；验证初始草稿、改动判定、策略取消恢复均使用编辑目标作息，主界面和两表绑定不被改动。build14两项通过（`pro-final-2.log:4032–4033`）。未绑定或不存在的显式目标也不能继承旧快照；会话初始化失败时禁用保存及拖动。

## 添加课程：本轮补齐范围

Android精确来源为 `A/ui/screen/imports/ImportSheet.kt` 的 `AddTableScreen(addingCourses,targetTableId)`、`CourseSelectionSheet.kt` 和 `ImportDecision`，以及管理页 `ManagementPage.kt:125–150`。以下是本轮新增或修正的调用链，不是对初始快照的已实现声明。

- **入口与来源**：`ManagementPage.onAddCourses` → `AppRootViewModel.requestAddCourses(targetTableId:)` 在开页时固定目标。`ImportSheet(targetTableId:)` 提供已有课表、教务导入及草稿、WakeUP分享、粘贴文本、文件、外部文本投递和手动录入。已有表来源排除目标自身，读取源表绑定后的有效作息，并保留权威groupId；没有其他表时显示空状态。手动先关方法sheet，再把同一目标交给课程编辑页。空课程和纯作息数据不能进入加课流程。
- **逐组选择**：所有批量来源先进入共享 `CourseSelectionSheet`，默认全选，可全选/全不选，空选择禁止确认。非空groupId为权威分组键；否则用trim后的课程名和教师兜底。选中一组会保留其全部上课安排；过滤同时保留作息、学期、警告和权威分组标记等ParseResult元数据。新解析投递及预览UUID闸防止旧异步操作误提交。
- **追加决策**：共享 `CourseImportDecision` 默认 `backupOriginal=true`、`appendConflicts=false`，只表达备份与是否追加冲突课，不向加课用户暴露新建/替换五模式。预览和提交都使用固定目标。`CourseImportPolicy`保留目标已有时间槽及边缘槽，只补缺失节点；按真实共同教学周、单双周及ownTime/非常规时间判重叠，端点相接不算冲突。冲突筛选仅比较incoming与目标原课程，不额外过滤incoming之间的安排。
- **一个事务**：`ScheduleRepository.appendImportedCoursesWithBackup`在`writeWithUndo`中重新读取目标、有效作息和当前课程，重新筛选后才建备份并追加。备份使用全局唯一名，冻结水合后的作息、脱离共享作息绑定、关闭提醒且不设默认；导入组重新分配UUID，不能并入目标原组。来源分区另统一为提交与选择相同的非空groupId或trim后课程名+教师键，避免同名不同教师被合并、blank groupId的多次安排被拆散；含新增2项回归的 `CourseImportBackupTests` 8项已在build14通过。成功后目标成为默认、maxWeek按接受课程增长；一次undo/redo覆盖备份、追加及默认表变化。全冲突返回0，不建备份、不发布历史或变更钩子，仍留在预览；后续插入失败整笔回滚并保留原redo。
- **新建分流**：管理页“新建课表”没有加课target，解析后直接新表配置；JW的newTableOnly同样不能返回五模式替换当前表。新表确认配置须在首次呈现前准备，中央build11另含该确认初始化时序修复。

对应数据测试 `AddCoursesImportTests` 7项、`CourseImportPolicyTests` 5项及 `CourseImportBackupTests` 8项均在build14通过（`pro-final-2.log:164–165,:871–885`）。`AddCoursesEntryUITests`的来源入口、手动路由两项已通过；第三项曾在文本预览按钮可视区前置失败，后续 `se-final-6.log:195` 明确通过“选组→保存→冷启动→原表备份”完整路径，不再记为尚未验收。各来源尤其真实JW账号仍需各自运行证据。

## 跨表课程owner与JW生命周期

- `CourseEditorContext.load`按编辑课程的tableId、显式targetTableId、Quick Add槽位tableId、最后才主界面selectedTableId确定owner；显式目标缺失、绑定作息缺失或编辑源不存在时报错，不能回退另一表。整组读取、有效作息、保存、删组和组色更新都在同一owner下进行，仓库提交再次验证源课程/组归属。首次无表手动录入仍可在保存时建表。`CourseEditorTargetTests` 10项已在build10实际通过，包括非选中表编辑、主界面切表后的显式加课/Quick Add、陈旧删除源与组色/删除隔离。
- JW选择既有作息的新表导入现通过 `JwImportViewModel.importAsNewTable(bindPeriodTableId:)` → `ScheduleRepository.importNewTable`，同一事务验证作息、建表、绑定、插课及发布undo；移除“先建课表，再try?绑定”的部分成功路径。`JwImportBindingAtomicityTests` 3项已在build10通过：所选作息消失不建表且保留redo、绑定与课程一个undo单元、课程插入失败全部回滚。
- **取消与恢复修正**：JW加课选择页和冲突确认仍留在 `JwImportFlow` 内，Cancel统一走`requestExit`；新加课解析不自动创建草稿，取消直退。恢复草稿保留原ID，并保留继续/保留/删除三选；Keep更新同一草稿。全冲突/提交失败留预览及草稿；取消返回父方法页保留输入，成功才关闭父页。该生产链已构建并只读复核；数据测试通过不等于真实JW账号、取消及恢复草稿UI已验收。
- **生命周期与外部投递**：成功落库即删除草稿，未验证学校的成功报告显示期间向宿主保持dismiss保护；parse epoch阻止UCAS补全、恢复及autosave在退出后回流。延迟完成且未被采纳的autosave有实际删除补偿；Keep保存的ID不被误删，显式Keep写入失败时保留在途autosave兜底。`JwImportLifecycleTests`5项已在build14通过（`pro-final-2.log:2330–2331`）。根部导入入参快照、呈现in-flight/UUID闸对应 `ImportPresentationLifecycleTests`3项（`:1707–1708`），`PendingImportDeliveryTests`3项（`:3723–3724`）同样全部通过。

## 双头范围滑杆：本轮补齐四处消费者

Android `AddCourseScreen.kt:627,1193,1232` 与 `OccurrenceEditor.kt:154` 均实际调用 `IntRangeSlider`；`IntRangeSlider.kt:61–96,254–270`要求打开时初值作为幽灵范围，并与显示使用相同夹取规则。此前矩阵把单值 `NativeBaselineSlider` 的存在误当成这些双头消费者已接；实际初始页面仍用数字步进。

本轮新增 `I/ui/component/IntRangeSlider.swift`，提供两个可独立拖动且不可交叉的端点、RTL映射、44pt命中区和两个AX adjustable端点。原数字输入及无障碍入口保留。四处接线如下：

| iOS消费者 | 范围与原值 |
| --- | --- |
| `AddCourseScreen.swift:429` 全局周次 | 1…max(1,min(30,table.maxWeek))，编辑源的打开时周范围为基线；仍按Apply才下发到各block。 |
| `AddCourseScreen.swift:1185` 每block标准节次 | 1…effectiveTimeJson的maxStandardNode；基线为打开时initialStartNode/initialStep。 |
| `AddCourseScreen.swift:1213` 每block周次 | 同全局周次域；基线为打开时initialStartWeek/initialEndWeek。 |
| `CourseOccurrenceEditor.swift` 单次标准节次 | 有效标准节次域，使用原course的起点/跨度作为基线。 |

编辑时段的四个initial字段在回填时捕获且不随草稿修改；新建、Quick Add和新增block的基线为nil。幽灵与当前范围同口径夹取，返回原范围即隐藏，缺任一原值不显示。`IntRangeSliderTests`7项在build14持续通过（`pro-final-2.log:1783–1784`）。`RangeSliderUITests.testBothWeekThumbsSynchronizeFieldsAndPersistAppliedRange`在SE旧手势实现通过（`se-final-5.log:7061`，128.808s），覆盖真实双端点拖动、数字输入、Apply下发、保存及无seed重启后的周范围。build29的SE7同用例失败51.234s：横拖28.133pt、端点pitch14.0667pt时起点只变为2，未到预期3。当前UIKit横向pan已从原始touch-down记录位移，避免只使用识别后的translation；该修正build30结果见最终验收统一区，不能沿用旧实现的E2E通过结论。幽灵视觉、四处全部消费者的手势/渲染和屏幕阅读器读数仍不能仅由unit数量外推。

## 中央验证快照与后续边界

中央产物根目录为 `/Users/kerrylee/Documents/Codex/2026-11-09/g/work/verification/`；下表日志及同名 `.xcresult` 均在该目录。早期结果保留历史，后续复测只更新实际覆盖的路径。

| 批次 | 已确认结果 | 证据及范围 |
| --- | --- | --- |
| SE早期基线 | build10单测2210项0失败；build11单测2217项0失败。build11 UI18项6失败。 | `se-final-core-2.log:5285–5288`；`se-final-4.log:5300–5303,:7705–7724`。早期drag/追加/删除失败不抹除，也不在已有后续复测通过后继续写为“完全未证明”。 |
| SE已完成基础UI | 文本导入保存及无seed重启、英文和中文长文案TopBar、AddCourses来源入口/手动路由通过；Quick Add2项与TableEdit3项通过。 | `se-final-4.log:5361,:5410,:6647,:7585,:7702`；`se-final-ui-3.log:1262,:1382,:3743,:3849,:3948`。分别证明所列入口、精确快捷加课、外点取消及作息重排路径。 |
| SE，`se-final-5` | 单测2229项0失败；UI13项9通过、4失败。已通过真实RangeSlider E2E、occurrence旋转草稿保持、横屏校验/删除取消、作息列表键盘后复制。 | `se-final-5.log:5309–5311,:6660,:7061,:8312,:9075,:9079–9081`。本批次追加预览、编辑删除及两个导入深链失败，后续复测见下行；本批整条命令仍失败。 |
| SE，`se-final-6` | **6项UI全部通过**：选组追加/持久化/原表备份、编辑课程删除、有效与无效课程深链、有效导入及空导入深链。 | `se-final-6.log:195,:352,:382,:419,:456,:492,:496–506`，`TEST EXECUTE SUCCEEDED`。关闭了上行四个失败路径的复测，不代表所有SE UI状态均已遍历。 |
| Pro，`pro-drag-final-1` | 7项drag中**6通过、1失败**：网格外放下、整跨度横移、原处放下无undo、hover目标、网格内移动/持久化/undo、左边缘驻留连续翻周通过；右边缘预期Week3却观察到Week4。 | `pro-drag-final-1.log:168,:369,:451,:542,:941,:1650,:1709–1729`。首次整批仍为失败；右边缘后续用同一完整断言复测。 |
| build14 | 全目标测试包构建成功。 | `final-package-build-14.log:1951`，`TEST BUILD SUCCEEDED`。此项仅为构建结论。 |
| build14，Pro，`pro-final-2`单测 | **2239项、0失败**。包含JW lifecycle5、导入呈现闸3、Pending投递3、来源分组新增2、TodayContext新增5、Widget geometry5及生产脸渲染等本轮回归。 | `pro-final-2.log:5367–5370`；相关细分证据已在上文各节列明。五张Widget生产脸输出并经中央只读查看，不增加单测项数。 |
| build14，Pro，`pro-final-2` UI | **19项、14通过、5失败**，整批 `TEST EXECUTE FAILED`。右边缘drag保持全部原断言通过（132.945s）；Device6/7、Mine2/2、Sheet1/5、Manage/Today浅深截图4/4。 | `pro-final-2.log:5953,:7031–7032,:7190–7191,:11759–11762,:11894–11915`。通过项包括分享四格式及最大字号、导入草稿旋转、日期确认取消、rail旋转、原生我的页、外观分段、画廊入口、作息列表复制及管理/今日四个截图路径。5项失败完整名单如下。 |
| build15，Pro，`pro-final-3` UI | **10项、8通过、2失败**，整批 `TEST EXECUTE FAILED`。Sheet4/5通过，管理/今日浅深截图4/4通过；Device occurrence与Sheet occurrence仍失败。 | `pro-final-3.log:108,:897,:1068,:1523,:2599,:3268,:3304,:3337,:3370,:3403,:3407–3421`。EditorCopy、FormatHelp、NewTable配置返回保稿及ListCopy均通过；未将单次课程两个失败写为关闭。 |
| iPad，`ipad-final-1` UI | **12项、9通过、3失败**，整批 `TEST EXECUTE FAILED`。Device5/7、Sheet4/5通过。 | `ipad-final-1.log:1255,:3945,:3947–3962`。通过分享四格式/最大字号、日期确认取消、rail旋转选择保持、竖屏原生导航，以及与Pro相同的4项Sheet。导入输入未聚焦、Device occurrence入口、Sheet occurrence可视区为3个失败。 |
| build16，Pro，`pro-final-4` UI | **2项、0通过、2失败**，用于对剩余occurrence失败继续定位，整批 `TEST EXECUTE FAILED`。 | `pro-final-4.log:168–175,:733–758`。Device此次已进入编辑器并开启custom，失败于键盘focus断言；Sheet仍未将完整控件滚入前台可视区。不能由根因定位推导产品通过。 |
| build17，Pro，`pro-final-5` | 全目标测试包构建成功；完整unit **2252项、0失败**；UI **6项、2通过、4失败**，整批 `TEST EXECUTE FAILED`。 | 构建 `final-package-build-17.log:2891`；unit `pro-final-5.log:5364–5366`；UI总计`:7445–7461`。Export页与AddCourse返回通过；Device occurrence、ImportAudit、未验证学校提示与Sheet occurrence失败。 |
| build18，Pro，`pro-final-6` | 定向 `JwImportLifecycleTests` **12项全过**；UI **4项、2通过、2失败**，整批 `TEST EXECUTE FAILED`。 | `pro-final-6.log:93–98,:2242–2256`。ImportAudit通过12.437s（`:923`），未验证学校提示通过18.593s（`:1009`）；Device occurrence失败106.923s（`:868–875`），Sheet occurrence失败107.786s（`:2231–2238`），均停在reveal customRow。 |
| build19–25 | 七次全目标test build均成功；构建成功不表示UI通过。 | `final-package-build-19.log:408`、`-20.log:235`、`-21.log:231`、`-22.log:235`、`-23.log:365`、`-24.log:409`、`-25.log:222`。 |
| build19，Pro，`pro-final-7` | UI **3项、1通过、2失败**，整批 `TEST EXECUTE FAILED`。 | 未验证学校提示通过19.218s（`:950`）；Device失败103.288s（`:865`）、Sheet失败120.616s（`:2252`）；总计`:2256–2270`。 |
| build21，Pro，`pro-final-8` | 两个occurrence **均失败**，总计236.145s，整批 `TEST EXECUTE FAILED`。 | `pro-final-8.log:888,:2190,:2194–2208`。增加最小pan距离仍未解决完整customRow可见性。 |
| Pro，`pro-final-9` / `pro-final-10` | 两批各 **2项、0通过、2失败**，均 `TEST EXECUTE FAILED`。 | Pro9于`occurrence_start_time`的TextField快照查询失败，总计320.091s（`:1218–1227,:2656–2681`）；Pro10于完整控件可见性断言失败，Device68.858s、Sheet76.258s，总计145.115s（`:618–625,:1402–1427`）。两者均保留历史失败，不能据诊断关闭。 |
| build26–29 | 四次全目标test build均成功；不等于UI通过。 | `final-package-build-26.log:352`、`-27.log:1587`、`-28.log:1538`、`-29.log:2150`，均为`TEST BUILD SUCCEEDED`。 |
| Pro，`pro-final-11` / `pro-final-12` | 两批各 **2项、0通过、2失败**，均 `TEST EXECUTE FAILED`。 | Pro11 Device151.695s、Sheet158.907s均在完整控件可见性断言失败（`pro-final-11.log:960–967,2343–2368`）；Pro12 Device137.213s失败，Sheet63.051s明确在“滑杆行竖向拖动应滚动编辑器”回归断言失败（`pro-final-12.log:1056–1063,1481–1506`），不能将此项归为纯查询问题。 |
| build28，Pro，`pro-final-13` | 完整unit **2252项、0失败**；UI **2项、1通过、1失败**，整批 `TEST EXECUTE FAILED`。 | unit`:5357–5360`；Device occurrence75.950s通过（`:5789`）；Sheet135.965s仅在取消删除后最后`detail_close`可视区断言失败（`:6987–7011`），helper将详情页头误按编辑器滚动viewport排除。 |
| build29，Pro，`pro-final-14` | 完整unit **2255项、0失败**；定向Sheet occurrence **1/1通过**，166.019s；整批 `TEST EXECUTE SUCCEEDED`。 | `pro-final-14.log:5365–5368,6670–6684`。该命令只重跑Sheet UI，未重跑Device或RangeSlider；首次三项Widget尺寸/单侧metadata/完整网格时间线回归包含在本批unit中，后加表头回归不在本包。 |
| build29，SE，`se-final-7` | 定向UI **3项、0通过、3失败**；整批 `TEST EXECUTE FAILED`。 | Device34.716s、RangeSlider51.234s、Sheet26.188s（`se-final-7.log:123–128,269–272,439–465`）。两项occurrence仍查旧Switch子节点，执行查询与当前源码query/行号不匹配，原因尚未证实。RangeSlider起点落在2而非3，已改原始touch-down位移，build30结果见最终验收统一区。 |

build14的五项失败及实际后续结果如下；历史失败不抹除，后续仅关闭实际通过的路径：

| 用例 | `pro-final-2.log` 失败位置 | 已完成后续结果 |
| --- | --- | --- |
| `DeviceAdaptationUITests.testOccurrenceDraftSurvivesNativeAndRailRotation` | `:6903–6910` | Pro3/iPad1入口、Pro4 focus及后续customRow可见性失败均保留；Material版Pro13已通过75.950s。SE7仍以旧Switch查询失败，执行与当前源码不匹配尚待确认；最终结果见统一区。 |
| `SheetPlatformUITests.testEditorCopyAllowsCancelAndSaveAfterLandscapeKeyboardInput` | `:8705–8712` | Pro3 `:897`通过；iPad1 `:2052`通过。 |
| `SheetPlatformUITests.testLandscapeFormatHelpShowsContentAndCloses` | `:9358–9365` | Pro3 `:1068`通过；iPad1 `:2202`通过。 |
| `SheetPlatformUITests.testLandscapeNewTableConfirmationShowsActionsAndBackRetainsDraft` | `:10519–10526` | Pro3 `:1523`通过；iPad1 `:2600`通过。 |
| `SheetPlatformUITests.testLandscapeOccurrenceEditorValidatesSaveAndCancelsDelete` | `:11083–11090` | 早期可视区及Pro12滑杆竖向滚动失败保留；Pro13只剩最后`detail_close`误排页头，build29 Pro14完整路径166.019s通过。SE7旧Switch查询失败尚待确认，最终结果见统一区。 |

诊断与当前验证方式：

- 旧Form阶段已定位viewport误计、刘海起手和slider高优先级drag拦截；iPad导入失败发生在输入前无focus，不能记为旋转丢草稿。后续保留严格可视区/键盘/草稿/保存/删除断言，并以整行checkbox替代虚拟Switch子节点。
- Pro7/Pro8的customRow为y=295.667…343.667，viewport为y=78…340。先按pan距离不足10pt推测将最小拖距升至32pt，Pro8仍失败，该推测没有获得解决问题的证据。
- build22 helper改从target、日期卡、fixed/custom或summary与viewport的可见交集中选择非slider实体内容起手，避免透明padding；旋转后不先手动滚动，直接检查键盘及完整56pt描边输入框的自动reveal。build24的simultaneous gesture、方向锁和后加GestureState取消重置均属历史方案，Pro12真实竖向滚动回归仍失败。当前共享IntRangeSlider使用UIKit横向pan，在识别前拒绝竖向手势交给父ScrollView，结束/取消/失败清理状态；最新修正以原始touch-down位置计算位移，build30结果见最终验收统一区。Pro10后的fixed/custom查询已改为descendants(any)，完整可视区、键盘、保存、取消及持久化断言保留；SE7日志仍查询旧Switch且行号不符，不能据此预先认定失败原因。Pro13 Device与Pro14 Sheet通过只关闭各批实际覆盖的路径，最终结论统一见下方。

## 最终验收统一区

最终生产代码候选为`841de01`，版本1.0.63/build63，最低iOS15.6。build33完成最新完整单测；build34仅追加导入显露/整卡聚焦修正及其UI回归。下列是独立批次，不合并成一次全套通过。

| 范围 | 实测结果与限制 | 证据 |
| --- | --- | --- |
| 全目标构建 | build30–34均`TEST BUILD SUCCEEDED`，含App、Widget、Watch及测试目标。版本产物核验1.0.63/63，最低15.6。 | `final-package-build-{30,31,32,33,34}.log`。 |
| 最新完整单测 | build33 SE10 **2259项、0失败**，30.358s；含4项新增Widget及3项五语真实示例回归。 | `se-final-10.log:5378–5380`及同名结果包。该批UI失败，整批命令不能写成功。 |
| SE关键UI | build30 SE8 **3/3通过**：单次草稿旋转82.358s、双头周次3–8/Apply/保存/无seed重启131.005s、时间校验与删除取消141.812s；同期2256项单测零失败。 | `se-final-8.log:5882,6283,7504,7518`、`se-final-8-all/manifest.json`，`TEST EXECUTE SUCCEEDED`。 |
| Pro单次编辑 | Pro13 Device75.950s通过；Pro14 Sheet166.019s通过，Pro14另有2255项单测零失败。后续共享滑杆及表头增量由SE8证明。 | `pro-final-13.log:5789`、`pro-final-14.log:5365–5368,6670–6684`。 |
| iPad build30 | iPad2 **7/8通过、整批失败**：导入30.883s、rail17.053s、单次草稿69.337s及4个浅深截图通过；Sheet47.931s仅在20pt竖滚断言失败。导入旧断言只证明草稿，后经截图另发现输入被遮挡。 | `ipad-final-2.log:116,220,651,929–937,976–1101`，`ipad-final-2-all/manifest.json`。 |
| Sheet尺寸补测 | build31 iPad3 **1/1通过**136.142s；SE9 **1/1通过**178.177s。全部8个关键控件完整可见时竖拖后检查仍完整可用；有任一不fit仍严格要求≥20pt滚动，节次1/2不变及全部后续校验/取消流程保留。 | `ipad-final-3.log`、`se-final-9.log`，两批均`TEST EXECUTE SUCCEEDED`。未为平板改动生产源码。 |
| 导入首次修正与后续失败 | build32 iPad4增强导入36.673s、rail15.111s，2/2通过；build33 SE10导入旋转虽已可见并续输，但多次等动画结束而超180s；FullText旧偏移点击未聚焦，25.661s失败。 | `ipad-final-4.log`、`se-final-10.log`及各自附件。保留SE10整批`TEST EXECUTE FAILED`。 |
| 最后导入复测 | build34 SE11 **2/2通过**：双向旋转续输29.528s、整卡点按/完整长文档/预览/配置/保存/无seed重启43.014s。iPad5增强导入 **1/1通过**34.097s。显露请求可取消并合并，生产定位使用局部无动画事务；没有提高测试时限或关闭全局动画。 | `se-final-11.log`、`ipad-final-5.log`及`*-all/manifest.json`，两批均`TEST EXECUTE SUCCEEDED`。 |
| 文案与示例 | 五语56个资源值修复；ICS单次资源解码保留9个LF与2个字面反斜杠n，生产解析器仍得到教师；WakeUP保留2个LF及百分编码。新增3项回归随2259项通过。 | `LocaleAndL10nTests`；五语plutil与键集/占位符静态检查通过。AI协议提示保持基准。 |
| 图像检查 | 五种Widget代表family、8张新增Widget图、手机管理/今日浅深及单次编辑、SE导入/长文本、平板管理/今日浅深、rail/Mine、单次编辑与最后双向导入图已目检。 | 交付目录`phone/`、`tablet/`、`widgets/`；Widget为固定样例生产视图离屏渲染，非主屏添加/刷新实测。 |
| GitHub发布目标 | 用户授权普通推送`Kerry1020/sleepy-ios`的`master`；本节记录提交前验收，最终远端SHA由发布后的`ls-remote`与GitHub分支API核验并写入交付报告。 | 不创建tag或Release；`ios-build.yml`的master push不触发iOS构建，不能据推送宣称CI通过。 |

## 尚未覆盖与当前边界

1. **Occurrence以最终验收统一区为准**。Pro3已关闭EditorCopy、FormatHelp和NewTable三项失败，另保留ListCopy通过；Material版Pro13 Device、Pro14 Sheet分别通过。SE7两项occurrence旧Switch执行查询与当前源码不匹配，原因未证实；build30 SE8两项occurrence均通过，详见最终验收统一区。ImportAudit与未验证学校提示已有通过证据，不将历史或其他设备通过合并为最终Material编辑器全设备验收。
2. **iPad已有iPad1的9/12、iPad2的7/8及后续定向补测证据**，Sheet和增强导入已分别在iPad3、iPad5通过；不能把独立批次改记为一次全套通过。源码与单测的rail阈值为横屏窗口宽≥600pt，双栏另需有效内容宽≥876pt；600–875pt单页rail、876pt边界、更宽双栏各右页、窄/宽Split View及Stage Manager缩放未由这12项完全覆盖。
3. **硬件与系统版本**：本记录为指定iPhone与iPad模拟器结果，未完成真机、最低iOS15.6兼容分支、早期自绘底栏及其他系统版本的最终视觉验收。iOS26系统底栏与早期兜底差异、全部设置/语言/深浅色/长文本组合及全App最大辅助字号，不能从少数截图外推。
4. **已通过路径以外的交互**：作息重排合法保存/重开和非法倒序、Quick Add双把手保存/外点取消、指定跨周拖课/undo已有证据；RangeSlider周次Apply/保存/重启已由build30 SE8的原始touch-down实现复验通过（131.005s）。其他消费者的幽灵视觉、RTL/VoiceOver、完整手势组合、双指行高、冲突详情及其后的提醒/Widget刷新仍应按具体用例验收。
5. **系统与账号条件**：通知真实投递、ActivityKit锁屏/灵动岛、配对Watch同步、主屏幕WidgetKit添加/时间线刷新、三校真实教务抓取需要对应系统、硬件和账号。JW取消/草稿三选和所有导入来源的完整UI没有因生命周期unit通过而自动获得验收结论。

## build30补测补充

build30全目标test build成功。SE `se-final-8`完整SleepyTests **2256项、0失败**（26.784s），UI **3/3通过**：Device occurrence82.358s、RangeSlider131.005s、Sheet occurrence141.812s，整批 `TEST EXECUTE SUCCEEDED`。使用显式xctestrun且强制重新编译三个UI测试文件并重装测试runner；SE7旧query执行不匹配的底层原因仍未证实，不据此改写历史结果。新增4项Widget回归和8张生产PNG均已通过/输出并目检。iPad最终结果与发布核验统一见主文最终验收区。

窄至150/158pt且显示七天的网格沿用Android标签的20pt最小列宽及外层裁切，完整表头文字可越出单列，极窄尺寸会拥挤并裁掉右侧列。新增图片如实展示该基线行为，不宣称所有尺寸均无裁切或逐像素相同。
