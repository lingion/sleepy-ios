# 空格胶囊快速加课（已接线，待 CI）

## 最新接线状态

2026-11-04 主会话追加授权后，真实新增保存链已接线：

- `SleepyRoutes.swift` 定义 `CourseAddSlot(tableId/week/day/node/step)` 及编辑视图身份。保留原 `.addCourse(courseId, editing)` 路由签名，普通新增和已有编辑调用不变。
- `SleepyNavigator.openAddCourseAt` 校验当前表 ID、水合作息域、星期、正周次和节次跨度，走既有 `openAddCourse()` 后绑定本次临时槽位。
- `SleepyApp.swift` 手机与平板两个 ScheduleScreen 都已接 `onAddAt`；通过 PresentOverlay 传入 AddCourseScreen。overlay 退出／切换、编辑课程置位、普通新增都会清除预填。
- `AddCourseScreen.quickAddMeetingBlock` 初始化 day/node/step 与单周，真实边缘节点设置 `isIrregularNode/selectedEdgeNode`。水合时间表再次校验，防止默认周一第1节冒充失效槽位。
- 表单仍走原名称/时段/冲突校验及 `buildCourseEntity → repo.insertCourses`。保存前阻止切表后错投；课程写入失败显示错误且不调用 onSaved。
- 原 fixedDate 字段、编辑回填、日期选择与 buildCourseEntity 逻辑保留；QuickAdd 新草稿没有擅自覆盖固定日期语义。
- 本次未再修改 ScheduleScreen.swift、CourseTableView.swift、NativeCourseDrag.swift，留给真实日期与详情操作代理。

新增 `SleepyTests/QuickAddPrefillTests.swift`（6 个）：单周跨度、双侧边缘节点、失效槽位拒绝、真实仓库往返并保留其他课程、导航进入退出及普通新增/编辑清会话、普通默认草稿与 fixedDate 编辑隔离。**需主会话将该文件加入 SleepyTests target 并在线上 CI 执行。**

## 对照依据

读取 `/Users/kerrylee/sleepy/app/src/main/java/com/lingion/sleepy/`：

- `ui/component/QuickAddCourse.kt:31–94`：选择范围、外点按下消费、确认和上下把手。
- `ui/component/CourseTableView.kt:1015–1028,1205–1270`：透明空格在实体课程下层；占位行不可选；实测行边界吸附；连续标准节点和边缘节点单节限制。
- `ui/screen/schedule/ScheduleScreen.kt:144–145,452–454`：会话状态、切周/模式失效、`onAddAt(tableId, week, day, node, step)`。
- `ui/nav/SleepyNavigator.kt:47–48`、`ui/screen/edit/AddCourseScreen.kt:248–249,269–277`：预填 day/node/step 和单周；边缘节点启用 irregularNode。

## 本片实现

- 新组件 `Sleepy/ui/component/QuickAddCourse.swift`：纯范围策略、会话状态、透明空格按钮、胶囊、上下把手、外点透明命中面。
- `CourseTableView.swift`：空格层位于 `GridConflictLayer` 下方，胶囊位于其上方；使用真实 `renderSlots` 和 `CourseGridRowLayout`。初选单节，handle 连续拖动按边界就近吸附，对侧固定，不跨缺失标准节点。标准节不扩进边缘节，边缘节锁 step=1。
- `ScheduleScreen.swift`：持有 QuickAdd 状态。胶囊外按下先由顶层 UIKit view 接收，清除选择但保留该次触摸所有权，不把同一次点击交给下方课程/空格/顶栏。切周、切表、切模式、进入后台、弹层、课程/时间/网格布局变化时清除选择。
- 选择期间临时禁用 `NativeCourseDropTarget`；没有修改 `NativeCourseDrag.swift` 或 `CourseDragPolicy.swift`。已有禁动画、触点、预览和边缘翻周补丁保留。
- 点击胶囊先清状态，再调用 `onAddAt`，本片不创建课程、不写数据库、不产生 undo。
- 上下把手支持 VoiceOver adjustable action，胶囊提供取消 accessibility action；标签复用已有本地化键。

## 接线契约（已由本片完成）

ScheduleScreen 保留可选回调，实际手机／平板调用均已传入；独立预览或未传回调的调用仍不显示空格入口：

```swift
ScheduleScreen(
    // 原有参数……
    onAddAt: { tableId, week, day, node, step in
        root.navigator.openAddCourseAt(tableId: tableId, week: week, day: day, node: node, step: step)
    }
)
```

接线不变量：

1. AppRoot 所有 ScheduleScreen 实例传递 `onAddAt`；走现有新增课程入口。
2. 新增槽位预填会话应携带 `tableId/week/day/node/step`，表 ID 必须校验；普通加课与编辑不能读到上次 QuickAdd 的预填。
3. `AddCourseScreen` 首个 block：`days=[day]`、`startNode=node`、`step=step`、`startWeek=endWeek=week`、`weekType=0`。组级周范围也设同一单周。
4. 若 node 在标准节次外：`isIrregularNode=true`、`selectedEdgeNode=node`、`step=1`；不得静默钳制成标准第1节。
5. 周参数按上游是**展示周**，本片不自行转成 drag occurrence 或 fixedDate；跨调休/fixedDate 的写入规则由负责表单和仓库的代理统一处理。
6. 保存/取消/普通新增/转编辑时清掉预填会话；复用现有名称、节次、冲突及落库校验。
7. target membership：`QuickAddCourse.swift` → Sleepy；`QuickAddCourseTests.swift` 与 `QuickAddPrefillTests.swift` → SleepyTests；`QuickAddCourseUITests.swift` → SleepyUITests。工程、实体和仓库未由本片编辑。

## CI 清单与状态

未在本机执行编译、测试、脚本或模拟器，没有提交/推送。以下均为新增待 CI 用例，不是通过记录：

- `QuickAddCourseTests`（7 个）：实测加权边界、顶底独立与不可反转、标准/边缘隔离、缺号限制、确认恰好一次且先清状态、透明命中面的内外点分流。
- `QuickAddCourseUITests/testOutsidePressCancelsWithoutOpeningCourseOrReselectingCell`：点已有课程只取消；第二次才开详情；点另一个空格只取消；第二次才新选；点顶栏第一次不翻周，第二次才翻周；无 undo/redo。
- `QuickAddCourseUITests/testBothHandlesPrefillSingleWeekAndSavePersistsExactPlacement`：第3周周六第5节起选，上把手到4、下把手到6；断言真实胶囊边界；确认进入编辑、空名禁止保存、真实输入精确值；保存后断言位置与详情 `4-6 (Week 3-3)`；重启验证仅第3周出现，第1/2/4周都没有。
- 回归 `CourseDragUITests`、已有课程输入断言、冲突卡点击/轮换、表头布局与纵向滚动。

UI 用例覆盖真实 `onAddAt` 链路，接线退化时会明确失败，不允许删断言或改成点普通加课按钮。
