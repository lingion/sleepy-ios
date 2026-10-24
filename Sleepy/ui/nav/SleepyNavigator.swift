import Foundation

// SleepyNavigator — Android SleepyNavigator.kt → iOS 薄门面 (1:1 意图面).
//
// Android 侧: 官方 NavBackStack 的极薄封装, 栈意图封成命名方法, 不暴露栈内部形态:
//   push (连续同路由去重) / pop (size<=1 → false) / popToMain / 16 个 openXxx.
// iOS 侧导航态 = AppRootViewModel (currentTab + overlayScreen + 参数). 本 facade
// 保留同一命名意图面, push 单点委托 vm.navigate(to:) (SleepyNavHost.swift 尾扩展,
// 与生产路径同一真源), 仅在 vm.navigate 尚未收编的路由上做等价桥接 (见各 case 注释),
// 🚫不复制整张映射表。
//
// push 去重语义: iOS overlay 是单值 (同屏重复置位 = 无操作), 天然等价
// "连续同路由不二次 push".
//
// v1.0.61 差量 (F071 对齐):
//   • .addCourse(courseId, editing) 参数不再丢: editing=true 时先把课程绑定进
//     session (= VM.editingCourse, Android session.editingCourse 的等价存储),
//     课程解析失败 → 不 push (Android NavHost LaunchedEffect 无 session 即弹栈同义);
//     editing=false → 清残留, 保证空表单 (Android entry 只读 editing? session : null).
//   • .periodEdit 放行 + periodEditId/pendingNewPeriodTableId 绑定 (生产 onOpenPeriodEdit 同式)。
//   • .courseList / .periodTables 放行 (1.0.61 屏已落地, OverlayScreen 已有 case)。
//   • createPeriodTableAndEdit(newId) 修正: Android 体 = openPeriodEdit(newId, isNew=true)
//     (作息表编辑), 旧实现误调 createNewTableThenEdit (课程表) 且 newId 被吞。
//   • NavSession 不再是影子态: 直接 backing VM.editingCourse (单一存储),
//     editingCourse 对外只读 (Android `private set` 同义)。
//   • .periodHeaderSettings 放行 (1.0.61 屏已落地 + Appearance Section④ 入口接线,
//     与 .courseList/.periodTables 同式经 default 走 vm.navigate; OverlayScreen.case +
//     iosNavigation + navigate 映射 = 共享接线 needs_shared_wiring, 本 facade 只摘 blocked)。
//   • 仍未放行 (无根 overlay 承载, 待共享接线, 见下): .holiday / .widgetManagement /
//     .widgetEdit — holiday 内嵌 GeneralSettings sheet,
//     widgetManagement/widgetEdit 内嵌 GeneralSettings→WidgetManagement 链。

// 薄门面驱动 @MainActor VM 态 → 整个类 @MainActor (Android 侧同为主线程).
@MainActor
final class SleepyNavigator {
    private let vm: AppRootViewModel
    let session: NavSession

    init(viewModel: AppRootViewModel) {
        self.vm = viewModel
        self.session = NavSession(viewModel: viewModel)
    }

    func push(route: SleepyRoute) {
        switch route {
        case .addCourse(let courseId, let editing):
            // ← Android entry: editing=true 时表单数据源 = session.editingCourse
            //   (调用方 beginEditCourse 先行, MainActivity.kt:330/333 同式);
            //   session 空则按 courseId 解析 (Android 深链 LaunchedEffect:
            //   beginEditCourse(course) → openAddCourse(course.id, editing: true) 等价).
            if editing {
                if session.editingCourse?.id != courseId {
                    let repo = ScheduleRepository(AppDatabase.getShared())
                    if let course = try? repo.getCourse(courseId) {
                        session.beginEditCourse(course)
                    } else {
                        // 解析失败 → 不保留上一段编辑的陈旧课程 (否则编辑错课)
                        session.clearEditCourse()
                    }
                }
                // Android LaunchedEffect: editing && session 空 && 无深链 → 立即 pop.
                // 等价 = 不进路由 (否则空编辑表单冒充编辑态)。
                guard session.editingCourse != nil else { return }
            } else {
                // 手动新增 = 空表单: 丢弃任何残留编辑态
                // (Android entry: editing=false 恒传 null 给 AddCourseScreen)。
                session.clearEditCourse()
            }
            vm.navigate(to: route)
        case .periodEdit(let periodId, let isNew):
            // 1.0.61 放行: 绑定 = 生产 onOpenPeriodEdit 同式 (SleepyApp PresentOverlay 接线)。
            // vm.navigate 收编该路由 (共享接线) 后本桥接可删。
            if !vm.navigate(to: route) {
                vm.periodEditId = periodId
                vm.pendingNewPeriodTableId = isNew ? periodId : nil
                vm.overlayScreen = .periodEdit
            }
        case .courseList:
            // 1.0.61 放行: CourseListScreen 已落地且 OverlayScreen 已有 case。
            if !vm.navigate(to: route) { vm.overlayScreen = .courseList }
        case .periodTables:
            // 1.0.61 放行: PeriodTablesScreen 已落地且 OverlayScreen 已有 case。
            if !vm.navigate(to: route) { vm.overlayScreen = .periodTables }
        case .holiday, .widgetManagement, .widgetEdit:
            // 屏已落地但无根 overlay 承载 (sheet/内嵌链), 路由级放行待共享接线:
            // SleepyRoutes.isIOSPorted + vm.navigate 映射 (见交付报告 needs_shared_wiring)。
            // 🚫silent skip 原则 → 显式留痕, 不伪造跳转。
            // (.periodHeaderSettings 已放行: 经 default → vm.navigate, 屏 + Appearance
            //  Section④ 入口已落地, OverlayScreen.case/iosNavigation/navigate 映射为共享接线。)
            break
        default:
            // .main / .allTables / .editTable / .appearance / .general / .export /
            // .reminder / .about / .license / .periodHeaderSettings — 单点走 VM 路由,
            // 不复制映射 (.periodHeaderSettings 放行依赖 iosNavigation + navigate 映射
            // 共享接线落地; 未落地前 vm.navigate 返回 false = 不跳转, 无伪造导航)。
            vm.navigate(to: route)
        }
    }

    /// Android pop(): size<=1 → false. iOS: 清 overlay + 走既有 handleBack
    /// (EditTable pendingNew 丢弃链). 无 overlay 可退 → false.
    @discardableResult
    func pop() -> Bool {
        guard vm.overlayScreen != nil else { return false }
        vm.handleBack()
        return true
    }

    /// Android popToMain(): 循环弹栈直到露出 Main, 全程**不碰 currentTab** —
    /// 底栏 tab 是 Main 内部状态(非栈元素), "回到 Main" 只意味着撤掉其上浮层。
    /// iOS 等价 = handleBack (丢弃链) + 清 overlay; currentTab 原样保留。
    func popToMain() {
        vm.handleBack()
        vm.overlayScreen = nil
    }

    // ── 16 个 openXxx 意图 (Android 命名 1:1) ──
    func openAddCourse(courseId: Int64 = NavSession.NO_ID, editing: Bool = false) {
        push(route: .addCourse(courseId: courseId, editing: editing))
    }
    func openAllTables() { push(route: .allTables) }
    func openCourseList() { push(route: .courseList) }
    func openAppearance() { push(route: .appearance) }
    func openPeriodHeaderSettings() { push(route: .periodHeaderSettings) }
    func openGeneral() { push(route: .general) }
    func openHoliday() { push(route: .holiday) }
    func openExport() { push(route: .export) }
    func openReminder() { push(route: .reminder) }
    func openAbout() { push(route: .about) }
    func openLicense() { push(route: .license) }
    func openWidgetManagement() { push(route: .widgetManagement) }
    func openPeriodTables() { push(route: .periodTables) }
    func openWidgetEdit(widgetId: Int) { push(route: .widgetEdit(widgetId: widgetId)) }
    func openPeriodEdit(periodId: Int64, isNew: Bool = false) { push(route: .periodEdit(periodId: periodId, isNew: isNew)) }
    func openEditTable(tableId: Int64 = NavSession.NO_ID, pendingNew: Int64 = NavSession.NO_ID, prevDefault: Int64 = NavSession.NO_ID) {
        push(route: .editTable(tableId: tableId, pendingNew: pendingNew, prevDefault: prevDefault))
    }
    /// Android createPeriodTableAndEdit(newId) = openPeriodEdit(newId, isNew = true)
    /// — 调用方 (PeriodTablesScreen 新建回调) 已完成插表拿到 newId, 门面只做
    /// 「进编辑路由 + 未保存新表丢弃链置位」(经 push(.periodEdit))。
    /// 旧实现误调 createNewTableThenEdit (课程表通道) 且吞掉 newId, 此处修正。
    func createPeriodTableAndEdit(newId: Int64) {
        openPeriodEdit(periodId: newId, isNew: true)
    }
}

/// Android NavSession 1:1: 会话态, 基线 §1.3 明确不纳入任何保存作用域
/// (旋转/进程恢复安全丢弃; 与栈序列化刻意隔离) → iOS 等价 = 普通属性,
/// 无 scene-phase 持久化.
/// v1.0.61: 不再是影子存储 — editingCourse 直接 backing AppRootViewModel.editingCourse
/// (生产 PresentOverlay / AddCourseScreen 读写的同一真源), 对外只读
/// (Android `private set` 同义), 仅 beginEditCourse/clearEditCourse 可写。
@MainActor
final class NavSession {
    private let vm: AppRootViewModel

    init(viewModel: AppRootViewModel) { self.vm = viewModel }

    var editingCourse: CourseEntity? { vm.editingCourse }
    func beginEditCourse(_ course: CourseEntity) { vm.editingCourse = course }
    func clearEditCourse() { vm.editingCourse = nil }
    static let NO_ID: Int64 = SleepyRoute.NO_ID
}
