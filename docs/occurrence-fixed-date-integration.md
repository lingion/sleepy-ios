# 定日课程子代理交接（可交 CI 的静态快照）

## 共享接线约定

- 本代理维护 `CourseEntity.fixedDate: String?`（ISO 日期，默认 nil）、v13 migration、parser/export、`CourseOccurrences`、`saveOccurrence` 与 `CourseOccurrenceEditor`。
- 已按追加授权接入 `HolidayReminderPolicy.swift` 的 `HolidayTransferOps.coursesForDate`：委托 `CourseOccurrences.coursesForDate`。新函数不回调该方法，无递归；主页/小组件/日历共同获得定日优先语义。
- 已在 `RowKey` 身份键加入 `fixedDate`，避免组编辑/同步导入将两个不同定日行误认成同一行。
- 顶栏 `ShareScheduleSheet` 已传调休数组，`ScheduleScreen` 传水合课表。另一路 `ExportScreen` 由 WakeUp 代理负责，静态核对已见其传入 `transfers:`。
- 原生拖课 lift/hover/candidate 已接课程感知身份与目标解析；定日直接使用自然日，普通循环课反查调休源日。移动旧签名保持兼容。
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
9. 首页/今日页详情接入 `CourseOccurrenceActions`。首页捕获点击页周和投影星期生成日期；今日页捕获点击当天；保存后刷新小组件和周视图，组编辑仍按 id 找回存储行。
10. `CourseTableView` 日期表头/今日高亮、共享周渲染、详情聚簇与拖动身份使用 `CourseOccurrences` 民事日辅助方法，统一 Asia/Shanghai。
11. `NativeCourseDrag` 源身份与悬停判定、`CourseDragPolicy` 候选投影支持定日移动；定日更新日期且不残留拆分副本。`RowKey.fixedDate` 区分行身份。
12. `NotificationScheduler` 先按自然日收集定日课，再追加调休源日循环课；定日不重复、不被挪到补班日，仍遵守提醒策略。自定义时间同时识别 `ownTime` / `isIrregularTime`。
13. 系统日历定日事件使用自然周/星期且不标注调休；迭代、日期范围统一民事日。范围结束取 `max(semesterEnd, latestTarget + 1)`，防止学期中途补班截断剩余课程。

## 主会话仍须接入的共享路径（不能遗漏）

### 1. 工程登记

新增生产文件：

- `Sleepy/data/repository/CourseOccurrences.swift`：加入所有编译 `HolidayReminderPolicy.swift` / `ScheduleExporter.swift` 的 target（至少 App；若 Widget/Watch 含这些共享源，也须加入）。
- `Sleepy/ui/screen/edit/FixedDateCourseField.swift`：App。
- `Sleepy/ui/screen/edit/CourseOccurrenceEditor.swift`：App。

新增 XCTest：`FixedDateCourseTests`（8）、`FixedDateImportExportTests`（7）、`CourseOccurrenceEditTests`（7）、`FixedDateProductionWiringTests`（9），共31个。没有改既有测试。第四个文件覆盖渲染、原生起拖、候选投影、行身份、日历元数据/范围与提醒；依赖同 target 的 `NotificationSchedulerTests.FakeEnv` / `FakeAlarmPort`。CI 同时保留 `CourseOccurrenceMoveTests`、`CourseOccurrenceIdentityTests`、`CourseDragViewModelTests`、`SleepyNative*`、`ScheduleExporterTests`、`RowKeyDifferTests`、迁移测试及 undo 代理的4个故障注入用例。

### 2. 跨代理接线复核

首页/详情、原生拖课、行级身份、提醒、系统日历已按追加授权完成源码接线，不再是待实现项。`CourseTableView` 的公开点击回调仍为 `(CourseEntity) -> Void`；私有 `WeekPager` 内部回调才附带点击页周。

`ExportScreen`（WakeUp 代理所有）静态核对已使用：

```swift
ScheduleExporter.exportIcsOrThrow(table, courses,
    transfers: AppPrefs.shared.getHolidayTransfers(table.id))
```

两 API 旧两参调用保持兼容；主会话合并时请保留此参数及有效作息水合。最终 target 注册与 GitHub CI 仍归主会话。

## CI/原生验收检查点

- v12已有课升级后字段为NULL，写 fixedDate 重开库仍在。
- 同一放假日有循环课和定日课：循环课去补班日，定日留原日且不重复。
- 调休目标日打开单次编辑，时间-only 编辑保留 sourceDate；删除只删源周，隔周余课保持。
- 冲突确认期间改库/作息/调休，点击继续返回过期错误；SQLite 插入失败回滚且不增 undo。
- fixedDate ↔ native text / WakeUp JSON / Migration 包往返；空 alias 第11列占位。
- ICS调休每次一个 VEVENT，UID含实际日期，无RRULE；学期外补班日期不漏。
- 两步编辑/删除后 undo、redo 各两次，定日、组色/别名、课程区间均恢复。

- 日历范围：学期内补班不截断学期尾部，学期外补班目标日延长到目标次日；CI 应同时验证非上海系统时区下日期键与触发时间。

当前仅完成源码静态核对，31个新增测试均未执行，编译及原生运行未验证。本代理未提交或推送；共享 worktree 的主会话可能已收录部分早期改动，最终以主会话冻结快照为准。
