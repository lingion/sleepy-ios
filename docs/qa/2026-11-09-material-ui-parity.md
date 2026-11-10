# Android 1.0.63 Material UI 对照审计（2026-11-09）

> **2026-11-10更正**：本文149/150/158pt小号切脸及窄small全周结论已由[最小小组件复核](2026-11-10-widget-minimum-size-parity.md)取代。当前systemSmall的周列表/周视图使用三天窗口，周网格使用Today脸；补三天调休与定日课取课修复，完整单测2274项零失败。以下先前批次保留为历史证据。

本记录覆盖主要页面的视觉结构。build30的SE8已确认完整2256项unit零失败及Device occurrence、RangeSlider、Sheet occurrence三项UI通过；build31的iPad3和SE9单次编辑分别通过；build32的iPad4增强导入与rail两项通过，输入及预览截图已由中央确认完整可见。build33全目标test build成功，SE10完整2259项unit零失败，包含五语示例解码新增3项回归。本记录保留各历史失败，不将定向补测合并为全App通过；SE10最终UI、后续复测、截图与GitHub发布状态统一见 `2026-11-09-android-1063-parity.md` 的“最终验收统一区”。

## 基线与证据

- Android 固定标签：`v1.0.63`，提交 `b16aa84d11c250acdf644cd8b7812ab27d03dc6a`。全部参照通过 `git show v1.0.63:<路径>` 读取，不使用 Android 工作区未提交内容。
- Android 文件根：`app/src/main/java/com/lingion/sleepy/`。下表 Android 路径均相对该目录；iOS 路径相对仓库根目录。
- `gradle/libs.versions.toml:5–6` 固定 Compose BOM `2026.09.00`、Material3 `1.5.0-beta02`；Material3 有显式版本，不能用当前网络文档的默认值替代该版本行为。
- 本次直接检查本地 `material3-android/1.5.0-beta02/material3.aar` 的 `classes.jar`：AAR SHA256 为 `937daaf7b67833e9efceb297a3a89f957ccd993f7d736e1ac96ef7ff5081e5db`。`javap -p -c` 显示普通 `CardKt.Card` 的默认参数调用 `CardDefaults.getShape` 和 `CardDefaults.cardColors`；前者取 `CornerMedium`，后者取 `SurfaceContainerHighest`。`FilledCardTokens` 的对应 getter 给出相同 token。Android `ui/theme/Theme.kt:332–337` 将 medium 定义为 12dp。
- `material-3` 技能用于检查颜色角色、形状、排版及交互结构；涉及本项目取值时，以以上固定标签和确切依赖为准。

## 本次修正

| 文件与位置 | 已确认问题 | 修正与 Android 依据 |
| --- | --- | --- |
| `Sleepy/ui/screen/manage/ManagementPage.swift:22` | 管理页标题使用 medium，摘要卡将同一 16pt 内边距施加到左侧内容和右侧独立按钮；管理操作行末的额外 Spacer 还占用一段行间距。 | 标题改 28pt bold；摘要只给左侧列 16pt，右侧 TextButton 独立 top 4/end 8；行内文本占剩余宽度。对应 `ui/screen/manage/ManagementPage.kt:70–120` 和 `:159–190`。右侧动作继续有至少 48pt 高的命中区。 |
| `Sleepy/ui/component/SegmentedSwitcher.swift:43` | 外层已经 padding 4，thumb 又偏移 4；按钮使用外层高度再套 padding，导致轨道、按钮和选中色块坐标不一致，窄分段标签拥挤。 | 轨道宽为外宽减 8、高为外高减 8；thumb 与按钮都使用轨道尺寸，thumb 只按段号水平位移。对应 `ui/component/SegmentedSwitcher.kt` 中 `.height(42.dp).padding(4.dp)` 后的 Layout 测量、点击段和 thumb 放置。42pt 默认高度及设置页 36pt 调用高度保留。 |
| `Sleepy/ui/screen/widget/WidgetManagementScreen.swift:131` | 已放置小组件行把默认 Card 错映射为 surfaceContainer 和 large(16)。 | 改为 surfaceContainerHighest 和 medium(12)，保留 12pt padding、16/14pt 两行文字与 0 行间距。对应 `ui/screen/widget/WidgetManagementScreen.kt:136–164` 的未覆写默认 Card，以及上节确切 Material3 字节码证据。 |
| `Sleepy/ui/screen/edit/CourseOccurrenceEditor.swift` | 单次编辑原以原生Form/Section、系统开关和内嵌日期控件呈现，与Android `OccurrenceEditor.kt` 的Material结构不同。 | 生产页改为主题ScrollView，20pt页面padding、标题22/副标题16、描边日期卡及单独日期确认sheet、固定/自定时间复选框、标准节次IntRangeSlider、56pt描边时间输入及48pt主色保存/错误容器删除动作。保存、冲突提示及删除事务沿用原链路。Pro6后的实际截图显示旋转键盘遮住描边字段下沿；build19新增FocusState+ScrollViewReader，在键盘/viewport resize后将聚焦字段重居中，并为日期formatter与DatePicker显式指定app locale。设备结论不从旧Form或源码改动外推。 |
| `Sleepy/widget/WidgetCourseCard.swift`、`WeekGridWidgetView.swift` | WeekGrid小号未按150pt宽度切换完整网格；空教室metadata残留分隔符；窄列表头的星期/日期被省略且被圆角mask裁字。 | `systemSmall && width < 150pt`才用Today脸，150/158pt小号及medium/large保留网格，provider使用相同宽度闸；单侧metadata只画实际值。生产`WeekGridDayHeader`仅对两行文本启用默认false的水平溢出开关，在frame前取自然宽度，背景改为`RoundedRectangle(cornerRadius: 14).fill(...)`，保留Widget外层裁切，按Android Canvas完整`drawText`语义绘制。新增4项实际渲染/时间线回归，前三项随build29通过，最后表头回归已随build30通过。 |
| 五语`Localizable.strings`、`ImportSheet.swift`的`ImportFormatKey.exampleText` | Android资源迁移残留使普通文案显示实体/反斜杠，WakeUP百分号经过格式化存在语义问题；串联替换还会把ICS DESCRIPTION的字面`\n`误解成换行。 | 共修56个资源值：6个实体、5个WakeUP示例格式化百分号及45个普通转义残留；45个中仅19个已确认有当前Swift消费者，不把资源修正全部算作可见页面验收。示例采用单次扫描，仅解开Android资源转义层，保留ICS自身的反斜杠转义、未知转义和末尾反斜杠；新增3项生产消费路径回归随SE10单测通过。AI提示协议文本未纳入该解码修正。 |

前三个生产文件在原审计中均通过 `swiftc -parse` 与 `git diff --check`，并纳入build14成功test build。单次编辑Material及后续键盘聚焦/本地化修正已纳入成功构建；构建与设备结论分别列于末节。本并行文档更新进程未启动Xcode构建或模拟器。

## 逐页静态核对范围

| 页面/组件 | Android 参照 | iOS 对应 | 已核对的主要视觉角色与几何 |
| --- | --- | --- | --- |
| 主导航与课表页头 | `ui/component/PillNavigationBar.kt`；课表顶部操作布局 | `Sleepy/ui/component/PillNavigationBar.swift`；`Sleepy/ui/screen/schedule/ScheduleScreen.swift` | 贴底 Row 76、top 6/bottom 8、thumb 64×32；悬浮高度 64、seat 56、间距 4、inset 8、thumb 56×52、横边距 16、底距 12；标题及操作颜色角色。页头拥挤时分两行属于 iOS 窗口适配，详见响应式审计。 |
| 管理 | `ui/screen/manage/ManagementPage.kt` | `Sleepy/ui/screen/manage/ManagementPage.swift` | 页面 16pt 边距、16/12pt 组间距；摘要层级、操作卡 44pt 图标容器和 14pt 文本间距；本节列出的标题和独立 TextButton 修正。 |
| 我的 | `ui/screen/mine/MineScreen.kt` | `Sleepy/ui/screen/mine/MineScreen.swift` | 标题 28 bold/副标题 14；统计 28 bold/标签 11 medium、18pt 纵/8pt 横 padding；设置行图标容器 40/图标 20、文字 16、16pt 横/14pt 纵 padding；分隔缩进。 |
| 今日 | `ui/screen/today/TodayScreen.kt` | `Sleepy/ui/screen/today/TodayScreen.swift` | 顶部标签 12、日期 28、星期 16；卡片 16pt padding/圆角；空态时钟 48、padding 32、间距 12、标题 16/正文 14；课程节次 16 bold、时间 11 medium/宽 76、标题 16 semibold、正文 12、padding 12。日期映射数据逻辑属于功能切片，不能仅由外观核对判定正确。 |
| 课程详情 | `ui/component/CourseDetailSheet.kt` | `Sleepy/ui/component/CourseDetailSheet.swift` | 标题 22 regular、横 20/top 16/bottom 12；信息行 14、标签宽 54、间距 12；时间 Chip 12 medium、横 12/纵 6、圆角 12；编辑动作 14 medium、视觉高 40。 |
| 添加/编辑课程 | `ui/screen/edit/AddCourseScreen.kt` | `Sleepy/ui/screen/edit/AddCourseScreen.swift` | 常规动作 48/主 CTA 56、形状 16、分组标题 16 semibold/提示 12、卡片 16/28 形状；周次类型分段使用此次修正的公共控件。滑块手势、键盘和保存路径需设备验收。 |
| 单次课程编辑 | `ui/screen/edit/OccurrenceEditor.kt`；`ui/screen/edit/SingleOccurrenceCourseForm.kt` | `Sleepy/ui/screen/edit/CourseOccurrenceEditor.swift` | 生产Form已替换为上节Material结构，主题surface/onSurface、outline、primary/onPrimary及errorContainer/onErrorContainer均有实际消费者；原生导航取消及独立日期弹层保留iOS行为。设备结果需与生产改版对应，不将测试helper根因定位算为视觉通过。 |
| 外观 | `ui/screen/mine/AppearanceScreen.kt` | `Sleepy/ui/screen/mine/AppearanceScreen.swift` | 页面 padding 16、间距 12、双列主题网格 gap 12；色板 28/圆角 8，系统预览 56/图标 28；选中 primaryContainer、普通 surfaceContainer；新建主题虚线圆 40、行高 96。 |
| 共享设置卡与通用 | `ui/component/SettingsCards.kt`；`ui/screen/mine/GeneralSettingsScreen.kt` | `Sleepy/ui/component/SettingsCards.swift`；`Sleepy/ui/screen/mine/GeneralSettingsScreen.swift` | 分组 14 semibold/提示 12；卡片 padding 16/圆角 16；折叠箭头 20；flat 卡横 16/纵 14、分段 36。窄卡及长语言标签改纵向布局属于响应式切片。未遍历每个设置的动态组合状态。 |
| 提醒 | `ui/screen/mine/ReminderScreen.kt` | `Sleepy/ui/screen/mine/ReminderScreen.swift` | 主开关标题 16 semibold/提示 12；卡片 padding 16/圆角 16；IconBox 36/圆角 8/图标 20；子分隔 leading 52；时间与子项正文 14。权限、通知与实时活动由 iOS 原生能力实现，样式核对不证明后台投递。 |
| 小组件设置及管理 | `ui/screen/mine/WidgetSettingsScreen.kt`；`ui/screen/widget/WidgetManagementScreen.kt` | `Sleepy/ui/screen/mine/WidgetSettingsScreen.swift`；`Sleepy/ui/screen/widget/WidgetManagementScreen.swift` | 入口标题 14 medium、卡片横 16/纵 14/圆角 16；刷新动作 48；已放置列表按确切默认 Card 修正。真实小组件尺寸和画廊渲染另由功能切片记录。 |
| 添加小组件引导 | Android 系统 pin/管理入口行为 | `Sleepy/ui/screen/widget/WidgetAddGuideSheet.swift` | iOS 桌面长按、编辑、添加 Widget 的步骤使用独立原生引导；WidgetKit 无 Android pin API，不能仅复制 Android 按钮文案或把预览点击当成已添加。需在 iOS 主屏幕验收添加与刷新。 |

## 渲染与平台边界

1. SwiftUI `.system(size:)` 和 Android `SleepyTypography` 可以核对字号、字重、语义颜色；SF 与 Android 默认字形、显式行高、letterSpacing 和基线不同。表格不宣称文本行框或长文换行逐像素相同。多数页面仍用固定字号；本次不是全 App 最大辅助功能字号验收。
2. SF Symbols、其他页面的系统Switch、日期/时间选择、关闭按钮、sheet detent、NativeTabView和侧栏仍有iOS平台组件消费者；单次编辑的固定/自定时间现已使用Material复选框。平台组件需实测命中区、弹层收起、返回、键盘遮挡和旋转后的可达性。
3. Android「跟随系统」可读取壁纸动态色；iOS 使用可取得的系统/window tint 派生，外观页必须如实解释该差异。不能以假壁纸取色表示行为完全相同。
4. 已确认结果限于末节列明的模拟器批次及具体用例。iPad1为9/12，iPad2为7/8且整批失败；随后iPad3单次编辑通过，iPad4增强导入与rail两项通过。旧iPad2导入只证明草稿保持，完整输入及预览可见性由build32增强用例和中央截图核查补足。真机、最低iOS15.6兼容分支、iPad真实窄/宽Split View、Stage Manager以及未列出的语言/外观/动态状态没有本记录的通过结论。静态源码、离屏Widget图、UI自动化通过分别证明不同范围，不能相互替代。

## 中央设备验收挂接

验收产物根目录为 `/Users/kerrylee/Documents/Codex/2026-11-09/g/work/verification/`，下表日志和同名 `.xcresult` 均位于该目录。中央流程提供批次结论，本切片只读核对了以下日志的明确结果；没有将正在运行的整套测试记为通过。

| 批次/范围 | 已确认状态 | 具体来源与解释 |
| --- | --- | --- |
| build14 | test build 成功，包含本记录三处 Material 修正。 | `final-package-build-14.log:1951` 的 `TEST BUILD SUCCEEDED`。构建成功不表示全量 UI 或真实设备验收。 |
| build14，Pro，`pro-final-2` 单元测试 | 2239 个测试，0 失败。 | `pro-final-2.log:5367–5370`。这是单元测试结果，不计作 2239 个视觉场景。 |
| Pro 拖动回归 | `pro-drag-final-1` 首次 7 个中通过 6 个；右边缘驻留路径首次未到预期 Week 3，中央观察为 Week 4。build14 同一右边缘用例保留全部原断言，随后通过，用时 132.945s。 | 首次 `pro-drag-final-1.log:1651–1718`；复测 `pro-final-2.log:5953`，用例 `CourseDragUITests.testStationaryRightEdgeContinuesPagingAndMovingOccurrence`。不能把首次整批写为 7/7，也不据一次复测宣称所有拖动时序均已覆盖。 |
| SE，`se-final-5` 指定 UI 路径 | RangeSlider 全流程、单次课程编辑旋转草稿保持、横屏校验及删除取消、作息表列表键盘后复制均通过。 | `se-final-5.log:6660`、`:7061`、`:8312`、`:9075`。对应 `DeviceAdaptationUITests.testOccurrenceDraftSurvivesNativeAndRailRotation`、`RangeSliderUITests.testBothWeekThumbsSynchronizeFieldsAndPersistAppliedRange` 及两个 `SheetPlatformUITests`。本批次原 13 个 UI 中仍有 4 个失败；下行列出后续复测结果。 |
| SE，`se-final-6` | 6 个 UI，0 失败：现有课表课程组追加、持久化与原表备份，编辑删除，以及 4 个课程/导入深链用例。 | `se-final-6.log:195`、`:352`、`:382–498`。覆盖上一批次的追加、删除和导入深链失败；不能据此把其他未运行用例也记为通过。 |
| build14，五类生产 Widget 渲染图 | 中央已逐张目检本轮ImageRenderer使用实际生产EntryView生成的五张PNG。 | `pro-final-2.log:5084–5088` 的 `WIDGET_GALLERY_PREVIEW_WRITTEN` 对应 `WeekGridWidgetV19.png`、`TodayWidgetRV.png`、`WeekListWidgetRV.png`、`WeekViewWidgetRV.png`、`TwoDayWidgetRV.png`；核查副本位于 `/Users/kerrylee/Documents/Codex/2026-11-09/g/work/widget-parity-1063/ios-after/`。目检限于固定样例及对应离屏family，不能证明WidgetKit主屏幕添加、时间线刷新或所有偏好组合；结果包attachment manifest由中央统一挂接。 |
| 独立代码复核与后续审计 | 早期 `final_code_review` 未报告P1/P2；最后专项审计另发现JW两条入口漏准入门控与Widget午夜/课程结束边界缺口，均已有源码修复。 | JW新增7项路由、Widget新增6项边界回归均随build17完整2252项unit通过；build18另将JW生命周期/准入12项定向复测全过。早期审查无发现不能视为后续发现不存在，也不能替代字体、触摸或真机验收。 |
| build14，Pro，DeviceAdaptation | 7个中6个通过；单次课程编辑旋转草稿路径失败。 | `pro-final-2.log:6005–7031`；失败断言见`:6903`。其余分享、导入草稿、日期确认取消、rail旋转、原生我的页及最大辅助字号分享用例通过。后续失败位置与已定位的测试根因见下方build16行。 |
| build14，Pro，Mine Gallery/Appearance | 2 个用例均通过：外观模式分段、管理入口加号进入画廊。 | `pro-final-2.log:7102`、`:7189–7190`。证明这两个具体交互路径通过，不代表所有主题、文字长度、Widget family 与颜色组合均已检查。 |
| build14，Pro，SheetPlatform | 最终5项中1项通过、4项失败；ListCopy通过，EditorCopy、FormatHelp、NewTableConfirmation及Occurrence可视区失败。 | `pro-final-2.log:11759–11762`及主对齐文档所列完整失败位置。这是历史批次，其中三项非occurrence失败的Pro3/iPad1通过结果见下行。 |
| build15，Pro，`pro-final-3` | 最终10项中8项通过、2项失败；Sheet4/5及Manage/Today浅深截图4/4通过。Device与Sheet两个occurrence仍失败，整批 `TEST EXECUTE FAILED`。 | Sheet通过：`:897,:1068,:1523,:3268`；截图通过：`:3304,:3337,:3370,:3403`；总计`:3407–3421`。4个Sheet为EditorCopy、FormatHelp、NewTable配置返回保稿及ListCopy。截图前等待0.8秒，附件位于 `pro-final-3-attachments/audit-{manage,today}-{light,dark}/`；用例通过不等于全部像素验收。 |
| iPad，`ipad-final-1` | 最终12项中9项通过、3项失败；Device5/7、Sheet4/5，整批 `TEST EXECUTE FAILED`。 | `:1255,:3945,:3947–3962`。分享四格式/最大字号、日期确认取消、rail旋转、竖屏原生导航和与Pro相同4项Sheet通过。导入在typeText前没有keyboard focus（`:683`），尚未进入草稿旋转；另两项occurrence分别在入口等待及完整可视区断言失败。 |
| build16，Pro，`pro-final-4` 根因证据 | 两项occurrence复测均失败，已定位测试可视区/手势问题，不能记为产品通过。 | `:168–175,:733–758`。Device已进入editor并开启custom，但helper把右界874当可视，start字段825.7…847.7实际在竖滚动条所示812右界之外，tap未聚焦。Sheet与iPad1录屏显示drag起点落在滑杆行，其高优先级minimumDistance0手势接收drag。helpers已改竖bar viewport与cell左侧gutter，并保持完整可见性/键盘断言；生产另改为Material ScrollView。 |
| build17，Pro，`pro-final-5` | test build成功；unit2252项全过，UI6项中2通过、4失败，整批 `TEST EXECUTE FAILED`。 | unit `pro-final-5.log:5364–5366`、UI`:7445–7461`。Export与AddCourse返回通过；Device occurrence、ImportAudit、未验证学校提示及Sheet occurrence失败。Pro5虚拟Switch子节点选择后改为整行checkbox，仍保留完整视口、hittable、值及取消断言。 |
| build18，Pro，`pro-final-6` | JW生命周期/准入12项全过；UI4项中2通过、2失败，整批 `TEST EXECUTE FAILED`。 | `:93–98,:2242–2256`。ImportAudit通过12.437s（`:923`），未验证学校提示通过18.593s（`:1009`）；Device occurrence失败106.923s（`:868–875`），Sheet occurrence失败107.786s（`:2231–2238`），均停在reveal customRow。 |
| build19–25 | 七次全目标test build均成功。 | `final-package-build-19.log:408`、`-20.log:235`、`-21.log:231`、`-22.log:235`、`-23.log:365`、`-24.log:409`、`-25.log:222`；不等于UI通过。 |
| build19 Pro7 / build21 Pro8 | Pro7 UI1/3通过，Pro8 occurrence0/2通过，两批均 `TEST EXECUTE FAILED`。 | Pro7未验证学校提示19.218s通过，Device103.288s、Sheet120.616s失败（`pro-final-7.log:865,950,2252–2270`）；Pro8两个失败总计236.145s（`pro-final-8.log:2194–2208`）。 |
| Pro9 / Pro10 | 两批各0/2通过，均 `TEST EXECUTE FAILED`。 | Pro9于`occurrence_start_time`的TextField快照查询失败，总计320.091s（`pro-final-9.log:1218–1227,2656–2681`）；Pro10于完整控件可见性断言失败，Device68.858s、Sheet76.258s，总计145.115s（`pro-final-10.log:618–625,1402–1427`）。 |
| build26–29 | 四次全目标test build均成功。 | `final-package-build-26.log:352`、`-27.log:1587`、`-28.log:1538`、`-29.log:2150`；不等于UI通过。 |
| Pro11 / Pro12 | 两批各0/2通过，均 `TEST EXECUTE FAILED`。 | Pro11 Device151.695s、Sheet158.907s完整控件可见性失败（`pro-final-11.log:960–967,2343–2368`）；Pro12 Device137.213s失败，Sheet63.051s在滑杆行竖向拖动应滚动编辑器的真实回归断言失败（`pro-final-12.log:1056–1063,1481–1506`）。 |
| build28，Pro13 | 完整unit2252项零失败；UI1/2通过，整批失败。 | `pro-final-13.log:5357–5360,5789,6987–7011`。Material Device occurrence75.950s通过；Sheet135.965s只在取消删除后最后`detail_close`被helper误排在滚动viewport之外失败。 |
| build29，Pro14 | 完整unit2255项零失败；定向Sheet occurrence166.019s通过，整批 `TEST EXECUTE SUCCEEDED`。 | `pro-final-14.log:5365–5368,6670–6684`。只运行Sheet UI，未重跑Device或RangeSlider。Widget小号宽度切脸、单侧metadata和完整网格不生成Today边界三项回归包含在本批unit中；后加表头回归本批未包含，后由build30 SE8通过。 |
| build29，SE7 | Device34.716s、RangeSlider51.234s、Sheet26.188s均失败，整批 `TEST EXECUTE FAILED`。 | `se-final-7.log:123–128,269–272,439–465`。两项occurrence仍查旧Switch子节点，日志执行query/行号与当前源码不匹配，原因未证实。RangeSlider横拖28.133pt、pitch14.0667pt时起点落在2而非3；原始touch-down位移修正后的build30 SE8结果见下行。 |
| build30，SE8 | 全目标test build成功；完整unit2256项零失败，UI3/3通过，整批 `TEST EXECUTE SUCCEEDED`。 | 构建`final-package-build-30.log:1781`；`se-final-8.log:5371–5373,5882,6283,7504,7518`。unit26.784s；Device occurrence82.358s、RangeSlider131.005s、Sheet occurrence141.812s。包含第4项Widget表头回归。 |
| build30，iPad2 | UI7/8通过，整批 `TEST EXECUTE FAILED`。 | `ipad-final-2.log:116,220,651,929–937,1088–1101`。导入草稿30.883s、rail17.053s、Device occurrence69.337s和4张页面截图通过；Sheet47.931s失败于竖拖必须移动20pt的断言，当时整张表单已可见且没有滚动余量。旧导入用例未断言输入及预览完整可见。 |
| build31，iPad3 / SE9 | 全目标test build成功；两端各1项Sheet occurrence通过，两批均 `TEST EXECUTE SUCCEEDED`。 | 构建`final-package-build-31.log:286`；iPad136.142s（`ipad-final-3.log:1149–1163`）、SE178.177s（`se-final-9.log:1425–1439`）。仅表单全部控件已完整可见时验证拖动后仍完整可见；否则保留至少20pt滚动断言，两支均保留节次值不变断言。 |
| build32，iPad4 | 全目标test build成功；增强导入36.673s与rail15.111s，UI2/2通过，整批 `TEST EXECUTE SUCCEEDED`。 | 构建`final-package-build-32.log:702`；`ipad-final-4.log:146,248–262`。增强用例新增输入及预览完整可见断言，中央逐张核查截图确认；不把旧iPad2草稿通过视为该可见性证据。 |
| build33，SE10单元测试 | 全目标test build成功；完整unit2259项零失败，30.358s。 | 构建`final-package-build-33.log:587`；`se-final-10.log:3316–3325,5377–5380`。新增3项覆盖单次资源解码、五语ICS教师解析及WakeUP百分号/换行。该行只确认单元测试；SE10 UI与后续复测由主文最终验收区记录，不宣称本批整体通过。 |

Pro7/Pro8诊断的customRow为y=295.667…343.667，viewport为y=78…340；至少32pt pan未解决。build22改用可见非slider实体内容起手，并直接检查旋转后键盘及完整56pt描边框自动reveal。build24的simultaneous gesture、方向锁及后加GestureState取消重置均为历史方案，Pro12滑杆行竖向滚动回归仍失败。当前共享IntRangeSlider使用UIKit横向pan，识别前拒绝竖向手势，结束/取消/失败清理状态；原始touch-down位移实现已由build30 SE8的RangeSlider完整流程及两项occurrence通过确认。Pro10后fixed/custom查询已改为descendants(any)；SE7仍执行旧Switch查询且行号不符，其底层原因未证实，后续通过不倒推其根因。build31仅在全部编辑控件完整位于前景可视区时采用all-fit分支，执行同一竖拖后再次确认全部可见；其余情况仍要求custom至少上移20pt，且两支均要求节次起止仍为1/2。SE9验证了保留严格滚动要求的手机路径。最终发布结果见主文“最终验收统一区”；响应式范围另见 `docs/qa/2026-11-09-responsive-layout-audit.md`。

Widget后续新增共4个回归：149/150/158pt小号生产脸像素对照、单侧metadata像素对照、完整网格不生成Today边界、窄列中英文星期/日期完整墨迹且不裁切的生产表头像素对照。前三项在build29通过并输出4张尺寸/无教室PNG（`pro-final-14.log:5045–5059,5200–5201`）；最后表头回归随build30的SE8完整2256项单测通过，8张新增生产PNG已逐张目检；主屏幕WidgetKit仍需独立验收。

针对最初三处修改，截图判读范围包括管理摘要右侧按钮与长课表名换行、SE单双周三段与设置卡36pt分段的选中色块和文字居中，以及小组件管理列表浅深背景层级与12pt圆角。Pro3四张管理/今日稳定截图已逐张目检，浅深色状态稳定、未见旧Schedule过渡叠影；五张Widget生产脸PNG也已有目检。结论不扩大为分段、主屏幕WidgetKit或全部文案组合验收；最终Material编辑器验收统一见主对齐文档“最终验收统一区”。

## build30–33补测与文案范围

build30 SE8使用显式xctestrun、强制重新编译三个UI测试文件并重装runner，2256项单测与三项UI均通过；SE7旧query不匹配的底层原因仍未证实。新增4项Widget回归和8张生产PNG均已通过/输出并目检。build31 iPad/SE单次编辑、build32 iPad增强导入和rail的通过范围如上；不扩大为真实分屏或主屏幕WidgetKit验收。

五语56个资源值的修复已作语法、键集和格式占位符核对。示例生产路径的单次解码在五语ICS中保留9个真实换行及DESCRIPTION内2个字面`\n`，教师字段可由生产解析器读取；WakeUP示例保留2个真实换行及原百分号编码。新增3项回归已包含在build33 SE10的**2259项、0失败**（30.358s）中；资源静态核对不代替每种语言的整页视觉验收。最终UI及GitHub发布核验统一由主文最终验收区维护。

窄至150/158pt且显示七天的网格沿用Android标签的20pt最小列宽及外层裁切，完整表头文字可越出单列，极窄尺寸会拥挤并裁掉右侧列。新增图片如实展示该基线行为，不宣称所有尺寸均无裁切或逐像素相同。

## 最后导入UI增量（build34）

build33 SE10完整单测2259项零失败，但UI两项失败：旋转后可见性断言及续输已执行，多次等待动画结束导致180s超时；旧FullText偏移点击落在卡片空白处未聚焦（25.661s）。生产合并显露请求并取消旧任务、用局部无动画事务定位，整卡点按可聚焦。FullText回归直接验证完整文档值和键盘上方预览动作，保留配置/保存/无seed重启断言。build34 SE11导入旋转29.528s、完整文本导入43.014s，2/2通过；iPad5增强导入34.097s，1/1通过。两批均`TEST EXECUTE SUCCEEDED`，最新横竖屏截图已目检。无测试时限放宽或全局动画关闭；最终发布信息见主文验收区及交付报告。
