# 定日课程子代理交接（可交 CI 的静态快照）

## 共享接线约定

- 本代理维护 `CourseEntity.fixedDate: String?`（ISO 日期，默认 nil）、v13 migration、parser/export、`CourseOccurrences`、`saveOccurrence` 与 `CourseOccurrenceEditor`。
- 已按追加授权接入 `HolidayReminderPolicy.swift` 的 `HolidayTransferOps.coursesForDate`：委托 `CourseOccurrences.coursesForDate`。新函数不回调该方法，无递归；主页/小组件/日历共同获得定日优先语义。
- 主会话请在 `RowKey` 身份键加入 `fixedDate`，避免组编辑/同步导入将两个不同定日行误认成同一行。
- ICS 真实分享入口应传 `transfers: AppPrefs.shared.getHolidayTransfers(table.id)` 给 `ScheduleExporter.exportIcsOrThrow` / `exportIcs`；默认空数组保留旧调用兼容。
- 拖课代理：固定日期来源不能用只接收展示周/天的 `CourseOccurrenceIdentity.resolve`；将增加接收 `course:` 的重载，固定日直接解析真实日，不套调休映射。移动旧签名保持兼容。
- 已按主会话追加授权合入 `undo-v1063-integration.md` 两段 restore/redo：先 snapshotCurrent，再出栈，事务失败回填原栈，成功才写对栈。本次 occurrence 写入沿用事务成功后 capture 的现有模式。

## 验证约束

本机不编译、不运行测试/模拟器；新增 XCTest 由主会话注册工程并在 GitHub CI 执行。已对本切片跟踪文件运行 `git diff --check`（退出0、无输出）；新增文件逐个 `git diff --no-index --check /dev/null 文件` 无空白错误输出（新增差异的退出1仅表示有diff）。

## 本切片已落地

1. `CourseEntity.fixedDate` 可空字段、GRDB 持久化、合成 Codable 向前兼容；`v13.addFixedDate` 非破坏迁移。
2. `CourseOccurrences.swift`：严格民事日解析、定日优先显示、源/展示日身份、单双周精确拆分、精确周集合合并（不去除重复上课）、调休日期枚举、同日期时间冲突报告。
3. `ScheduleRepository.saveOccurrence`：事务内复核原行/全表课程/水合作息/调休；编辑或删除仅一次；保存后同组精确合并；共享边缘节次回收；提交后才发布一次 undo/数据通知。旧移动签名保留，定日移动同步更新 fixedDate 且不拆出伪重复行。
4. `ScheduleViewModel` 的拖动目标对定日使用自然日；新增 `occurrenceRepository` 与 `occurrenceSaved()` 给详情入口接线。
5. `CourseOccurrenceEditor.swift` 原生表单：日期、起止节次、自定义时间、固定日开关、删除确认、调休目的地选择/覆盖提醒、冲突二次确认、过期预览拒绝。包含 `CourseOccurrenceActions` 可直接嵌入详情。
6. `AddCourseScreen` + `FixedDateCourseField`：组编辑回填/分组/保存保留定日字段，日期控件同步单周和星期；定日/调休冲突检查走真实日期。
7. sleepy-v1 第12列 + 空别名第11列占位；WakeUp JSON/本地分享 JSON 保留 fixedDate；MigrationDatabaseCodec 导入、导出、合并拷贝保留 fixedDate。
8. ICS：空 transfers 保持旧重复课程 RRULE；定日无 RRULE；非空 transfers 将真实发生日逐次展开，UID 带 yyyy-MM-dd，包含学期外补班目标日。

## 主会话仍须接入的共享路径（不能遗漏）

### 1. 工程登记

新增生产文件：

- `Sleepy/data/repository/CourseOccurrences.swift`：加入所有编译 `HolidayReminderPolicy.swift` / `ScheduleExporter.swift` 的 target（至少 App；若 Widget/Watch 含这些共享源，也须加入）。
- `Sleepy/ui/screen/edit/FixedDateCourseField.swift`：App。
- `Sleepy/ui/screen/edit/CourseOccurrenceEditor.swift`：App。

新增 XCTest：`FixedDateCourseTests`（8）、`FixedDateImportExportTests`（7）、`CourseOccurrenceEditTests`（7），共22个。没有改既有测试。CI 同时保留 `CourseOccurrenceMoveTests`、`CourseOccurrenceIdentityTests`、`CourseDragViewModelTests`、`SleepyNative*`、`ScheduleExporterTests`、`RowKeyDifferTests`、迁移测试及 undo 代理的4个故障注入用例。

### 2. 首页/详情入口（CourseTableView / ScheduleScreen 由 QuickAdd 代理独占）

在持有当前课程与**实际展示日期**的详情 sheet 中加入：

```swift
CourseOccurrenceActions(
    courseId: course.id,
    displayDate: displayDate,
    table: effectiveTable,
    repository: viewModel.occurrenceRepository,
    onSaved: { viewModel.occurrenceSaved() }
)
```

`displayDate` 要按点开的页周和列计算，不能用 today，也不能用库内 source day。入口会再次按 id 取原始行，避免调休投影/normalize 副本被写回。表使用 `state.effectiveCurrentTable`。

### 3. 拖课源与悬停可投放判定

`NativeCourseDrag.swift:39` lift 源身份调用改为 `CourseOccurrenceIdentity.resolve(course: storedOrOriginalCourse, startDate:..., maxWeek:..., displayWeek:..., displayDay:..., transfers:...)`。定日源直接匹配展示日；旧重载仍为普通循环课服务。

`NativeCourseDrag.swift:403` 和 `CourseDragPolicy.swift:228` 目标判定：`source.course.fixedDate != nil` 时按自然 targetWeek/displayDay 校验学期范围，不套调休映射。否则放假日上的定日课仍会被 UI 拦截，尽管 Repository/ViewModel 已支持。这两文件本代理未编辑。

### 4. 行级导入同步身份

`Sleepy/data/diff/RowKeyDiffer.swift` 的 `RowKey` 增加 `var fixedDate: String? = nil`（放现有字段末尾以保留旧成员初始化调用）；`RowKey.of` 传 `fixedDate: c.fixedDate`。否则组编辑切换 fixedDate 或同步包含同时间不同定日的行时，会误判 unchanged/合并丢行。此文件本代理未编辑。

### 5. ExportScreen（WakeUp 代理独占）

其 ICS 调用使用：

```swift
ScheduleExporter.exportIcsOrThrow(table, courses,
    transfers: AppPrefs.shared.getHolidayTransfers(table.id))
```

若现路径用非 throwing `exportIcs` 同样加 `transfers:` 即可。两 API 旧两参调用保持兼容，但不传调休无法导出实际补班日期。

### 6. 提醒与系统日历元数据

- `NotificationScheduler.swift:592–603` 当前先 `guard sourceDate`，会漏掉放假日上的 fixedDate，并将 fixedDate 当普通周课。需先收集 `coursesForDay(tableId:, dayOfWeek:自然星期).filter { $0.fixedDate == HolidayTransferOps.dayKey(date) }`；通过 allowsReminder 后，sourceDate=nil/源日学期外返回 fixed；有 sourceDate 时追加源星期列表中 `fixedDate == nil && inWeek(week)`。这是独立于共享 `HolidayTransferOps.coursesForDate` 的数据源接口，因此不能只接中央方法就宣称提醒已齐。
- `SystemCalendarManager.swift:280–307` 真实日取课已通过中央入口支持 fixedDate；但 `week/classDay` 必须挪进 `for course in selected`，用 `course.fixedDate != nil ? day : (sourceDate ?? day)` 计算；`transferred` 还须加 `course.fixedDate == nil`，避免将定日事件错误标为调休源周。

## CI/原生验收检查点

- v12已有课升级后字段为NULL，写 fixedDate 重开库仍在。
- 同一放假日有循环课和定日课：循环课去补班日，定日留原日且不重复。
- 调休目标日打开单次编辑，时间-only 编辑保留 sourceDate；删除只删源周，隔周余课保持。
- 冲突确认期间改库/作息/调休，点击继续返回过期错误；SQLite 插入失败回滚且不增 undo。
- fixedDate ↔ native text / WakeUp JSON / Migration 包往返；空 alias 第11列占位。
- ICS调休每次一个 VEVENT，UID含实际日期，无RRULE；学期外补班日期不漏。
- 两步编辑/删除后 undo、redo 各两次，定日、组色/别名、课程区间均恢复。

当前仅完成源码静态核对，未声称编译/22测试/原生运行通过；以上共享入口接线是主会话合并前的明确检查项。
