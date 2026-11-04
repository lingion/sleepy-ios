# UIKit 拖课接入逐日调休模型

## 2026-11-04：第 8 轮证据与待 CI 补丁

以下为本次后续修复记录；下文 2026-11-03 的本地运行记录仅是历史，不代表此次验证。

### 第 8 轮实际失败点

- `parity-native-drag-8.log:1882`：同页立即松手后没有移动卡片。
- 从既有 xcresult 导出诊断，App 日志记录 16:09:04.809 捕获源身份、16:09:09.710 才收到 `sessionWillBegin`，16:09:09.756 以 operation=0 结束；没有 `canHandle` / `performDrop`。
- 同一份 system.logarchive：16:09:07.265 `druid` 已观察到 touch-up，下一毫秒报 `last touch up occured without any valid destinations`；随后 destination 连接因 session 已取消而失败。**5 秒起拖仍未让本轮模拟器在松手前完成 destination 握手，不能把这次失败归因于落点计算。** 保留用户授权的 5 秒起拖和立即松手的零停留，不添加重试或拖动结束补写。
- 右边缘用例在 `UITestLaunch.swift:21` 失败（App 无 process ID），没有执行拖动。因此本轮没有验证上一轮的禁动画和触点来源修复。
- 导出的诊断目录：`$TMPDIR/opencode/parity-native-drag-8-diagnostics/`。此次只读取/导出既有数据，没有启动 App、模拟器、编译或测试。

### 此次补丁

1. `CourseDragPolicy.swift`：当前目标周的实测网格 X 对齐 pager viewport 的水平中心，保留该周实测 Y、行高和候选布局。依据是 `CardsGridView` 的对称 `boxPad`（`availableW = geo.size.width - 2 * boxPad`）；不复用源周行高。这样第 6 轮已经出现的动画中 x=398/旧页 x=-4 不再直接参与命中。
2. 左右外侧 10pt 驻留区映射首/末个**可见星期列**。此前左边缘在时间轴左侧，`target` 必然为 nil。只映射 X；时间轴中部、viewport 外、网格上下方和多节溢出仍拒绝。
3. `NativeCourseDrag.swift`：进入 destination 时即校验本地 token 并计算落点；`performDrop` 显式使用本次回调 session，关闭翻页后重新计算最终落点；停止追踪清空自定义开始时间。新增翻周和 VM 写入结果日志。预览、抓取偏移、原始 occurrence 身份与仓库写入路径保持原契约。
4. `CourseDragUITests.swift`：新增左侧静止连续 3→2→1 周，精确验证第 3 周单次被移动、第 1–2 周和第 4–20 周保留、undo/redo、重启落库。取消用例增加重启后无改动验证；既有断言全部保留。
5. 新增 `SleepyTests/CourseDragViewportTests.swift`：6 个确定性用例覆盖动画横坐标、非零 viewport 原点、左侧首可见列、时间轴拒绝、越界拒绝与左侧连续驻留。**未修改工程；主会话需将此新文件加入 SleepyTests target 后由 CI 执行。**

此次没有编辑 `ScheduleScreen.swift`；保留已存在的 `Transaction.disablesAnimations = true`。

### 主会话 CI 验收

先执行新增 `CourseDragViewportTests` 及现有 policy / geometry / VM / occurrence-move 回归，再跑完整 `CourseDragUITests`（7 个）：

- `testNativeDragWithinGridPersistsAndUndoRestores`：5 秒起拖，目标处零停留；单次移动、精确位置、相邻周、undo/redo 和重启。
- `testNativeDragAcceptsHoveredDestination`：hover 对照组。
- `testStationaryRightEdgeContinuesPagingAndMovingOccurrence`：1→2→3 连续右翻及持久化。
- `testStationaryLeftEdgeContinuesPagingAndMovingOnlySourceOccurrence`：3→2→1 连续左翻、两侧剩余区间及持久化。
- `testMultiPeriodCenterLiftAndDropInPlaceDoesNotMoveOrCreateUndo`：原地 no-op。
- `testMultiPeriodCenterHorizontalDragPreservesPeriods`：纯横移保留抓取偏移/两节时长。
- `testDropOutsideGridLeavesOriginalAndWeekUnchanged`：取消及重启后无写入。

CI 失败时需同时保留 App `CourseDrag` 日志和系统 drag 日志：先区分“尚无 destination 握手”“目标周网格未发布”“目标拒绝”“onMove 返回 false”。本补丁尚未编译或执行测试，不能宣称 UI 通过；若下一页网格尚未发布时用户已松手，当前仍拒绝写入，不能用旧周几何兜底并声称已通过。

## 状态与范围

目标：`/Users/kerrylee/sleepy-ios/.worktrees/integration-parity-v1063`。
来源：同级 `parity-v1063` 未提交 UIKit drag WIP。

已接入起拖捕获、候选布局、分页容器和 VM 写入调用，并验证独立逻辑。**尚未通过 iOS 工程编译或 UIKit 拖放 UI 验收，不能据此宣称拖课可用。** 本轮未运行 xcodebuild、模拟器，也未 commit/push。

本轮没有编辑 `ScheduleRepository.swift`、AppPrefs、Appearance/Header/Hue 文件、资源、parser 或 pbxproj。共享工作树内这些文件有其他 agent 的改动，不属于本轮交付。`CourseTableView.swift` 保留 header agent 的 alignment/hide-time AppStorage、列宽计算和轴位置参数。

## 本轮文件清单

新增/迁入生产文件：

- `Sleepy/ui/component/NativeCourseDrag.swift`：迁入 UIKit interaction、触点捕获、投影、边缘翻页和取消路径；改为真实 occurrence 捕获。
- `Sleepy/ui/component/CourseDragPolicy.swift`：迁入命中/驻留/共享行高，重写候选数据模拟以匹配逐日渲染。
- `Sleepy/data/repository/CourseOccurrenceDestination.swift`：迁入标准节次、自定义时长、显式起始时刻及边界解析。

窄改生产文件：

- `Sleepy/ui/screen/schedule/ScheduleScreen.swift`：WeekPager 持有会话、传递展示周和原始课程/调休/水合表，安装 drop target/projection；离页、后台、切表、切模式或弹层禁用时取消。
- `Sleepy/ui/screen/schedule/ScheduleViewModel.swift`：新增 `moveDraggedOccurrence`，回查原始行，解析目标真实身份后调用仓库。
- `Sleepy/ui/component/CourseTableView.swift`：共享行高/候选几何、发布实测网格、注册单卡拖动，统一两个自定义时间标志。
- `Sleepy/ui/component/ConflictCard.swift`：注册可见冲突卡；内部分钟比例分支也识别 `isIrregularTime || ownTime`，与簇锚点保持一致。
- `Sleepy/data/entity/CourseEntity.swift`：`normalizeNode` 识别两个自定义时间标志。
- `Sleepy/util/TimetableViewportPolicy.swift`：晚间槽位裁剪识别两个自定义时间标志。

新增/迁入测试与脚本：

- `SleepyTests/CourseDragPolicyTests.swift`
- `SleepyTests/CourseDragViewModelTests.swift`
- `SleepyTests/CourseDropCandidateGeometryTests.swift`
- `SleepyTests/CourseCustomTimeContractTests.swift`（与来源逐字一致）
- `SleepyUITests/CourseDragUITests.swift`（与来源逐字一致）
- `scripts/tests/test_course_drop_candidate_geometry.py`
- 本文 `docs/native-drag-integration.md`

前一阶段已有的 `CourseOccurrenceIdentity.swift`、`CourseOccurrenceIdentityTests.swift` 和 `test_course_occurrence_identity.py` 本轮未改，再次运行身份验证。

## 身份与写入契约

`CourseDragContext.Source` 的不可变字段包括：

- `course`：以原始 `id/tableId` 从原始课程集合匹配的库行，保留原 step、day、时间和周范围。
- `renderedCourse`：渲染副本，仅用于几何，例如横移是否仍处于源分数行所在节次。
- `displayWeek/displayDay`：lift 所在展示坐标。
- `occurrence: CourseOccurrenceIdentity`：lift 时解析的真实 `week/day`。
- 原有 `origin/grabOffsetY/snapOffsetY`。

起拖解析共用已验证的 `dateOfWeek → courseDateForDate → semesterStatus → currentWeek + weekday`，同时校验表 ID、原始行 ID、真实 day 与 `inWeek`。翻页、源页销毁后不重算源身份。取消动画匹配展示周、展示列和原始 ID/table，避免同一行不同 occurrence 指向错误卡片。

目标列同样经 `CourseOccurrenceIdentity.resolve`。被挪走的放假空列返回 nil；扩展展示周可映射回真实学期内。UIKit 更新落点和 VM 写入都会验证目标。原有 `renderCoursesForWeek`、`displayMaxWeek` 和编辑详情的原始 ID 回查保持。

VM 先检查当前表，再通过 `repo.getCourse` 回查原始 ID/table/day/inWeek。调用接口：

```swift
repo.moveCourseOccurrence(
    courseId: original.id,
    sourceWeek: source.occurrence.week,
    targetWeek: target.week,
    targetDay: target.day,
    targetNode: targetNode,
    targetStartTime: targetStartTime
)
```

仓库 `false` 表示合法 no-op：VM 返回成功但不请求 Widget reload；只有实际 changed 才 reload，异常返回失败。没有恢复旧 `effectiveDayOfWeek` 逆映射，也没有按展示坐标提前绕过原始行检查。标准课保留原 step；自定义时间横移传原 startTime，避免把 08:35 吸附成 08:00。

## 候选数据与几何

候选以原始 `allCourses` 为输入：按 ID/table 找原行，验证真实源周在学期内及行的实际上课周；只移除捕获的源周一次，将两侧剩余区间保留原单双周类型，再按解析出的真实目标 week/day 插入单周实例。随后调用实际 `renderCoursesForWeek`，而非按展示周或 ID 删除整页投影。

因此第 1 周实例投影到第 2 周周日时，移走它不会删掉该行第 2 周周一的另一实例。调休目标指向第 3 周周二时，模拟数据存第 3 周周二，展示仍落在用户释放列。

候选的晚间收起使用模拟后的整学期数据，行高/课间/占位行使用模拟后的真实页面投影。临时拆分值保留原 ID，只服务几何计算；不能把这些临时值直接用于持久化或 SwiftUI 的唯一 ID 列表。

## 迁移测试的语义调整

保留来源断言；仅适配新模型所需的输入、字段和旧假设：

- `Source.course` 的显示 day/node/step 断言改为检查 `renderedCourse`；新增原始字段及 occurrence 断言。
- 原“唯一逆映射”用跨周单条映射加强：第 8 展示周周日写入第 7 真实周周四，再用真实 renderer 验证落点。
- 旧“单条调休逆映射歧义”在新模型不存在：补班列唯一指向源日。该测试改验已挪空的源日列拒绝，完整保留数据库不变、零写入、先前 undo 不被覆盖的断言。
- 原跨周源测试加强为第 3 真实周投影到第 4 展示周；捕获后清空调休再翻到第 8 周，仍应移走第 3 周。
- 两个几何测试声称目标页为空，但来源夹具原行覆盖第 2 周。改为 `endWeek=1` 使夹具与空页一致；所有几何预期保留。另有专门测试保留跨周 recurring 实例。
- 新增被删除源在原位释放时拒绝且保留已有 undo 的 VM 回归。

与源文件比对：policy 7→8 个测试、35→49 个 XCTAssert；VM 8→9、108→116；geometry 7→11、28→49；custom-time 3/14、UI 6/25 均原样保留。目标已有测试未改删跳。

## 本轮实际验证（2026-11-03）

### 已通过

1. `python3 scripts/tests/test_course_drop_candidate_geometry.py`
   - `CourseDropCandidateGeometryTests`：11 个。
   - `CourseCustomTimeContractTests`：3 个。
   - `CourseDragPolicyTests`：8 个。
   - 单卡、簇锚点、簇内部跨度的 3 个实际 View 自定义时间分支检查。
   - 合计 22 个 XCTest、3 个分支检查通过。
2. `python3 scripts/tests/test_course_occurrence_identity.py`
   - 11 个 XCTest × Asia/Shanghai、UTC、America/Los_Angeles，共 33 次执行、0 失败。
3. `swiftc -frontend -parse`：本轮涉及的 15 个生产/测试 Swift 文件语法解析通过；冲突卡后续条件修改单独再解析通过。**这不是 iOS 类型检查或链接验证。**
4. 现有 header 脚本的 `test_column_width_and_axis_share_alignment_policy`、`test_hide_time_remains_label_only_and_width_aware`：2 个通过，验证窄改未丢 header 接线；不是像素验收。
5. `git diff --check` 通过；custom-time/UI 来源文件逐字比对一致。

几何脚本直接抽取生产行布局、实体方法、日期、调休、renderer、Source 捕获类和 timedProjection；实际执行 XCTest。仅去掉 GRDB 持久化协议、隔离本地化和基础 String 扩展，不替换日期投影或候选算法。不加载 SwiftUI View/UIDragInteraction delegate；View 检查只编译条件表达式。所有编译串行，`nice -n 15`、`swiftc -j 1 -num-threads 1`。

新增真实学期外源周回归先运行得到 `XCTAssertNil` 失败；补入候选源周边界后全绿。日志目录 `$TMPDIR/opencode/`：

- `course-geometry-red.log`：该回归的真实失败记录。
- `course-geometry.log`：最终 22 个 XCTest 与 3 个 View 条件检查通过。
- `course-identity-integration.log`：本轮 33 次身份验证。

### 未运行 / 主 agent 后续验收

- 本轮 **9 个 VM/GRDB 集成测试未运行**，不把独立 Source/geometry 通过当成 VM 数据库通过。
- **6 个 UIKit UI 测试未运行**；来源 WIP 的 UI 也因环境阻塞未通过。需验证真实 lift、点击/滚动共存、冲突卡、边缘连续翻周、取消、分数行横移和 undo/redo。
- iOS App、扩展 target 的完整类型检查/链接和 Widget 验收未运行。
- 最终只读检查发现共享工作树已有仓库移动接口、五种本地化的两个 drag key，以及新文件的 pbxproj 引用；这些由其他方补入。本轮没有编辑这些文件，主 agent 仍需确认各 target membership 与完整工程集成。
- 仓库持久化切片的另一方验证记录见 `docs/occurrence-move-integration.md`，不计入本轮实测数。
