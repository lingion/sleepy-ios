# Sleepy iOS ↔ original 1.0.52 对齐矩阵 (2026-09-09)

基准: 原 commit **fe389b4** (1.0.52, 无 tag)。Android HEAD bc974b3b 超 fe389b4
3 commits (issue#23 §4/§7 UI 消费层) — 超出 1.0.52, 不在本次对齐范围。
iOS 仓库 `~/Desktop/sleepy-ios`, 基线 5f751f7b → fe389b4 共 53 文件 delta, 全部落账如下。

## Commits

| commit | 内容 |
|---|---|
| 4ec118c | 数据层 colorMode (CourseEntity.colorMode + GROUP/AUTO/CUSTOM 语义注释) |
| 9fa1de2 | 网格 + 冲突簇 (CourseTableView/ConflictCard slotIndexOf + groupRows) |
| 6f84b1d | ImportSheet multiLocationWarnings + 5 locale 文案同步 |
| d5ebb4a | TodayScreen + widget 渲染 groupRows 取色 |
| 0c0ebf8 | issue#22 行级 diff/patch 数据层 (RowKeyDiffer/CourseDao/ScheduleRepository) |
| 3a667d9 | UCAS + qz_ieas 教务协议层 + schools.json 161 校 |

## 1:1 翻译 (Android 文件 → iOS 文件)

| Android (fe389b4) | iOS | 备注 |
|---|---|---|
| data/diff/RowKey.kt + RowKeyDiffer.kt + DiffResult.kt | `Sleepy/data/diff/RowKeyDiffer.swift` | 三文件合一; GRDB IN 展开 + Keys 去重两轮 for-in 适配 |
| data/entity/CourseEntity.kt colorMode | `CourseEntity.swift` +47 | colorMode Int + 字段语义注释 1:1 |
| data/AppDatabase.kt + Migrations.kt MIGRATION_3_4 | `AppDatabase.swift` v4.addColorMode | ALTER TABLE courses ADD colorMode DEFAULT 0; GRDB migrator 旧库升级 ✓ |
| data/dao/CourseDao.kt updateAll/deleteByIds | `CourseDao.swift` | updateAll 循环 update(db); deleteByIds 手工 IN 展开 + StatementArguments |
| data/repository/ScheduleRepository.kt applyDiff | `ScheduleRepository.swift` | captureForUndo 内部化 (Android 调用方捕获, 注释注明分叉) |
| data/jw/JwUcasParser.kt | `Sleepy/data/jw/JwUcasParser.swift` | JSON 位图 (courseWeek/courseTime) + HTML 表格回退 + 相邻节次合并 |
| data/jw/JwQzIeasParser.kt | `Sleepy/data/jw/JwQzIeasParser.swift` | table#queryGrkb + data-* 优先五列回退 + 单双周三元组 |
| data/jw/JwProtocol.kt | `JwProtocol.swift` | +TYPE_QZ_IEAS/TYPE_UCAS + displayName/category |
| data/jw/JwImportViewModel.kt | `JwImportViewModel.swift` | parser 工厂/tryAllParsers 候选/URL 锚点 (QZ_IEAS 先于 /kbcx/) |
| assets/schools.json | `Sleepy/resources/schools.json` | 159→161 校, Android 同位插入, 零格式扰动 (+23/−1) |
| util/CourseColorUtil.kt *WithGroupRows | `CourseColorUtil.swift` | 三态入口 (CUSTOM/AUTO/GROUP) + golden angle 按行序 |
| util/TimeTableUtils.kt edge-node 段 | `TimeTableUtils.swift` | EdgeClass/maxContiguousFromOne/insertEdgeNode/removeEdgeNodeIfUnused/edgeNodesOf 全 6 函数 |
| ui/component/CourseTableView.kt | `CourseTableView.swift` | slotIndexOf 双路径 + gridH=rowH×timeSlots + steps 按剩余行数 + groupRows (overlay/lesson/detail 三处) |
| ui/component/ConflictCard.kt | `ConflictCard.swift` | timeSlots 参数 + slotIndexOfCached + clampedSteps 边缘公式 + groupRowsForCard |
| ui/screen/today/TodayScreen.kt | `TodayScreen.swift` | TodayCourseCard +groupRows 取色 |
| ui/screen/imports/ImportSheet.kt | `ImportSheet.swift` | multiLocationWarnings 面板 (take(5) + more_unexpanded) |
| ui/screen/mine/GeneralSettingsScreen.kt | `GeneralSettingsScreen.swift` | widget_manage_entry 行 + showManage cover |
| ui/screen/mine/LicenseScreen.kt | `LicenseScreen.swift` | school-ucas 条目 (4 上游致谢) |
| MainActivity.kt OverlayScreen | `GeneralSettingsScreen.swift` cover 链 | Android GeneralSettings→WidgetManagement→WidgetEdit = iOS 同链路 |
| ui/screen/widget/WidgetEditScreen/Section/ScheduleSection.kt | `WidgetEditScreen.swift` | 三文件合一; sealed interface 扩展点 → 文件内同级 section struct (注释保留) |
| ui/screen/widget/WidgetManagementScreen.kt | `WidgetManagementScreen.swift` | PlacedWidgetItem (widgetId→kind+family, 粒度差异注释) |
| widget/WidgetBindingCore.kt + WidgetBindingStore.kt | `WidgetBindingStore.swift` | 键 appWidgetId→kind (平台差异表#8); 惰性失效语义保留 |
| widget/WidgetEditCore.kt + WidgetEditViewModel.kt | `WidgetEditScreen.swift` 顶层函数 | filterAvailableTables/initialBinding/applyBindingChange 序列 |
| widget/WidgetManagementViewModel.kt | `WidgetManagementScreen.swift` loadPlacedWidgets | AppWidgetManager 枚举 → WidgetCenter.getCurrentConfigurations |
| widget/WidgetVariantInfo.kt | `WidgetManagementScreen.swift` displayName | 10 receiver 变体 → 5 kind 标签键映射 |
| widget/WidgetTableResolver.kt resolveBoundTable | `WidgetBindingStore.resolveBoundTable` | 惰性失效 + 不回写 |
| widget/Today/TwoDay/WeekList/WeekView/WeekGrid*.kt loadDataSync(+appWidgetId) | `WidgetDataLoaders.swift` WidgetLoader.tableFor(kind:) | resolveBoundTable ?: resolveCurrentTable, 5 loader 全接 |
| widget/WidgetBitmapRenderers.kt drawCourse groupRows | `WidgetCourseCard.swift` + 5 个 *WidgetView.swift | issue#22 取色: WeekGrid=allCourses / Today/TwoDay=data.courses / WeekList=day.courses 过滤同 groupId |
| widget/WeekGridWidgetProvider.kt issue#22 | `WeekGridWidgetView.swift` | pickCourseColorSwiftUIWithGroupRows(allCourses.filter{groupId}) |

## 平台 N/A (Android RemoteViews/Room/JVM-only, iOS 无对应路径)

- `onDeleted` → `WidgetBindingStore.remove`: WidgetKit 无 widget 移除回调 —
  iOS 绑定残留由惰性失效兜底 (绑定表被删时 resolveBoundTable 返回 nil 回退默认表)。
- `ScrollStripService` / `WidgetRenderActivity` / `WidgetBitmapRenderers` Canvas 渲染:
  iOS widget = WidgetKit SwiftUI 原生视图, 无 bitmap 通道; 取色逻辑已映射到
  SwiftUI 视图层 (见上表)。
- `todayCompactKeys` take(1)→全量 / `twoDayCompactKeys` first()→flatMap:
  Android SMALL 变体 RemoteViews 无障碍标签; iOS WidgetKit 可访问性由渲染文本自动暴露, N/A。
- `WidgetUpdater.remoteViewsReceiverClasses` ← ALL_WIDGET_VARIANTS:
  iOS `WidgetCenter.reloadAllTimelines` 等价, 无 receiver 类表。
- `JwParserRegistry` (priority 140/142/145): iOS 检测层 = JwImportViewModel URL 锚点
  + tryAllParsers 候选序, 等价语义已落 (见 3a667d9)。
- `JwFetchProtocol.FetchKind.QZ_IEAS`: iOS 无 HTTP 抓取层 (WebView 抓 HTML 架构),
  fetch-kind 枚举 N/A。
- `JwClassicEamsParser` cleanCourseName 移除 (课程名整体入库): iOS 无 classic-eams
  parser 文件, 无需移植。

## 工作区遗留 (不代提交)

`Sleepy/ui/screen/edit/AddCourseScreen.swift` — 用户未提交的 1.0.51 工作 (冲突明细弹窗/
每时段周次/单双周/clamp/apply_to_all_slots/maxNode) 与本次 issue#22 hunks (G1-G9:
MeetingBlockDraft 四字段/colorMode 三态/basicInfoCard 收窄/buildCourseEntity 新形态/
RowKeyDiffer.diff→applyDiff 编辑分支/ColorSection 三态取色) 语义纠缠, 无法拆开提交
(拆任何一个都编译不过)。已 BUILD SUCCEEDED 验证, 等用户先提交其工作后 `git add` 一并入库。
详见 `sleepy-ios-ui-1.0.52-slice-issue22-editor.md`。

## 验证记录

- xcodebuild -scheme Sleepy -destination 'generic/platform=iOS' build → **BUILD SUCCEEDED**
- `git diff --check` 干净
- L10n: original 1.0.52 strings 33 个新增/变更键 × iOS 5 locale (zh-Hans/zh-Hant/en/ja/es)
  全部在场 (0 missing), 抽查 course_color/color_use_different/color_follow_group/
  widget_edit_title/widget_manage_empty 五键值均为真实译文非键名泄漏
- rg marker/TODO/FIXME/placeholder 生成残渣扫描 (4 个 jw 文件) = 0 命中
- schools.json python json.load = 161 entries 有效
