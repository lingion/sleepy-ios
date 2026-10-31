// SleepyApp.swift — ← SleepyApp.kt + MainActivity.kt
// iOS App 壳: 全局依赖初始化 + 主题 Provider + 4 Tab 底栏 + overlay 导航 + 深链。
//
// 平台映射:
//   - SleepyApp.onCreate(通知调度/小组件刷新) → AppDelegate.init + didFinishLaunching
//   - MainActivity.setContent + AppRoot → WindowGroup { AppRoot }
//   - 深链 EXTRA_COURSE_ID → URL scheme sleepy://course/<id>(平台差异表#4)
//   - pendingImportText(外部 json 打开) → onOpenURL sleepy://import?text=
//
// MainActivity 职责 → iOS 承接表 (app-shell slice, 2026-10):
//   - 深链 EXTRA_COURSE_ID / onNewIntent    → onOpenURL (sleepy://course, sleepy://import)
//   - autoShowImportOnceState (一键导入引导) → 管理页 sheet 通道 (无跨进程一次性标记缺口)
//   - pendingImportText → EXTRA_DRAFT_ID 打开 import   → 外部打开走 URL; 草稿恢复待 data-migrations
//   - uiMode 监听 (dark 实时重算, configChanges 不重建) → iOS 系统 dark 自动驱动颜色资源, 无需信号
//   - splash 替换 (installSplashScreen)               → iOS 无公开 splash API, 记录 no-analog
//   - HighRefreshRate 120Hz 请求                        → 无公开 API (ProMotion 系统调度, 2026-09-10 已审计)
//   - 权限请求序 (runtime permission)                   → 通知权限在 NotificationScheduler 首次调度时按需请求, 无独立序

import Combine
import SwiftUI
import UIKit
import UserNotifications
import GRDB
import WidgetKit

@main
struct SleepyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environmentObject(appDelegate.rootViewModel)
        }
    }
}

// ← SleepyApp(Application): 全局依赖 + 通知调度 + 小组件刷新
class AppDelegate: NSObject, UIApplicationDelegate {
    let database: AppDatabase
    let repository: ScheduleRepository
    let notificationScheduler: NotificationScheduler
    let rootViewModel: AppRootViewModel

    override init() {
        database = AppDatabase.getShared()
        // UI 测试种子钩子: -SLEEPY_UI_TEST_SEED 1 → 清库+注入确定性测试数据
        // (XCUITest 无法直接触 DB;真实建表/导课走 UI 流程另有专项测试)
        if ProcessInfo.processInfo.arguments.contains("-SLEEPY_UI_TEST_SEED") {
            SleepyUITestSeeder.seed(database: AppDatabase.getShared())
        }
        repository = ScheduleRepository(database)
        notificationScheduler = NotificationScheduler.shared
        rootViewModel = AppRootViewModel(repository: repository)
        // 2026-10-29 App Store 截图自动化钩子(headless 模拟器, simctl launch 传参):
        //   -SLEEPY_SHOT_TAB=today|manage|mine 切初始 tab;-SLEEPY_SHOT_VIEW_GRID 切网格视图。
        //   只影响启动初始屏, 不改变任何交互逻辑; 与 -SLEEPY_UI_TEST_SEED 同性质。
        let shotArgs = ProcessInfo.processInfo.arguments
        if let t = shotArgs.first(where: { $0.hasPrefix("-SLEEPY_SHOT_TAB=") }) {
            switch String(t.dropFirst("-SLEEPY_SHOT_TAB=".count)) {
            case "today": rootViewModel.currentTab = .today
            case "manage": rootViewModel.currentTab = .manage
            case "mine": rootViewModel.currentTab = .mine
            default: break
            }
        }
        if let v = shotArgs.first(where: { $0.hasPrefix("-SLEEPY_SHOT_VIEW=") }) {
            rootViewModel.scheduleViewMode = String(v.dropFirst("-SLEEPY_SHOT_VIEW=".count)) == "cards" ? .cards : .full
        }
        super.init()
        // ← onCreate: 通知调度器接 repo;数据变更 → 刷 widget + 重排通知
        notificationScheduler.repositoryProvider = { [weak self] in self?.repository }
        repository.onDataChangedHook = { [weak self] in
            guard let self = self else { return }
            WidgetCenter.shared.reloadAllTimelines()
            self.notificationScheduler.scheduleAll()
            // ← 2026-10 watch 伴侶 App: 同一条 refresh 总线挂手表全量快照推送
            // (scheduleSync 只持 Coordinator 单例, [weak self] 模式與本 hook 其余行一致)
            WatchSyncCoordinator.shared.scheduleSync()
            // v1.0.62 B1: 資料變更 → 刷 course_colors 快照
            Task {
                await CourseHueStore.shared.refresh(
                    mode: AppPrefs.shared.getCourseColorMode(), dao: self.database.courseColorDao
                )
            }
        }
        WatchSyncCoordinator.shared.start()
        // ← Android SleepyApp.onCreate: classDndScheduler 注入 (F128 issue#2)
        ClassDndScheduler.shared.configure(repositoryProvider: { [weak self] in self?.repository })
        // ← Android ReminderRescheduler.init 块 (SleepyApp.kt:44-52) — 同时修复 init_ 从未被调用、
        //   全树 20+ 处 ReminderRescheduler.shared.request() 被静默丢弃的缺口。fluid-cloud 分支为
        //   platform-only 不移植:
        ReminderRescheduler.shared.init_(debounceMs: 300) {
            NotificationScheduler.shared.scheduleAll()
            ClassDndScheduler.shared.reconcileReminderRules()
        }
        // ← Android BootReceiver kt:808 冷启动无条件校准 (pref 关时 rebuildState 守卫 = 安全 no-op):
        ClassDndScheduler.shared.syncFromPrefs()
        // v1.0.62 B1: 冷启动刷 course_colors 快照
        Task {
            await CourseHueStore.shared.refresh(
                mode: AppPrefs.shared.getCourseColorMode(), dao: database.courseColorDao
            )
        }
        // ← Android ProcessLifecycleOwner onStart observer (SleepyApp.kt:63-72; iOS app-wide
        //   此前没有 didBecomeActive 调度观察者 — 只有 ReminderScreen 的局部快照刷新):
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard self != nil else { return }
            // Android 侧此处还有 reconcileActiveFluidCloud — vendor platform-only, iOS 无等价
            ClassDndScheduler.shared.syncFromPrefs()
            // watch 伴侣 App: 回前台兜底重推 (离线期间 onDataChanged 攒的改动追平)
            WatchSyncCoordinator.shared.syncNow()
        }
    }

    // ← BGTaskScheduler 注册窗口在启动完成前 (F129 issue: 注册调用此前零调用方,
    //   submit 因未注册静默失败)。willFinishLaunching 早于 didFinishLaunching。
    func application(_ application: UIApplication,
                     willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationScheduler.registerDailyResyncTask()
        return true
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // ← onCreate: 首启刷新小组件(WidgetUpdater.notifyDataChanged)
        WidgetCenter.shared.reloadAllTimelines()
        // 到货重查/00:05 载体/摘要刷新的 delegate 此前从未注册 = 死接线 (F128/F129 issue6)。
        UNUserNotificationCenter.current().delegate = SleepyNotificationDelegate.shared
        // 高刷新率:iOS 无公开刷率 API(原 HighRefreshRate 桩已删),ProMotion 上
        // 系统自动调度 120Hz,无需 app 侧动作(2026-09-10 原生化审计)。
        return true
    }
}

// ← AppRoot 状态机(overlay 导航 + 深链)
@MainActor
final class AppRootViewModel: ObservableObject {
    enum Tab: Hashable { case schedule, today, manage, mine }
    // ★ OverlayScreen: 根浮层容器(自绘 ZStack)驱动; 右滑转场 + 跟手侧滑返回
    //   一处适配所有页——新增 case 自动获得同一套手势/转场, 无需逐页挂 recognizer。
    //   GeneralSettingsScreen 内嵌 NavigationView 容纳 HolidaySettings 嵌套跳转,
    //   其原生 pop 识别器按 UIKit 独占规则优先于容器侧滑。
    enum OverlayScreen: String, Identifiable {
        case addCourse, allTables, editTable, theme, general, export, reminder, about, license
        // ← v1.0.60 新屏(Android SleepyNavHost push 路由的 overlay 等价物)
        case courseList              // CourseListScreen(我的页课程数卡入口)
        case periodTables            // PeriodTablesScreen(作息表管理, issue#40 §4.1)
        case periodEdit              // PeriodTableEditScreen(pendingNew 丢弃链见 handleBack)
        case periodHeaderSettings    // PeriodHeaderSettingsScreen(外观页 Section④ 节次表头入口)
        case scheduleDisplay         // ScheduleDisplayScreen(课表显示设置)
        // holiday 由 GeneralSettings 内部 sheet 呈现,不再出现在根 enum
        var id: String { rawValue }
    }

    @Published var currentTab: Tab = .schedule
    @Published var overlayScreen: OverlayScreen? = nil
    @Published var editingCourse: CourseEntity? = nil
    // ← Android b96c865b: 课表视图模式(周/网格)会话级真值, 与 currentTab 同级 —
    // tab 切换/overlay 都会整页移除 ScheduleScreen, 状态必须提层才存活; 初始化读启动默认
    @Published var scheduleViewMode: ViewMode = AppPrefs.shared.getStartView() == "cards" ? .cards : .full
    // ← rememberSaveable 导航参数(旋转恢复语义 — iOS 状态默认保留)
    @Published var editTableId: Int64? = nil
    // ← v1.0.60 作息表编辑路由参数(镜像 EditTable 的 pendingNew 丢弃链)
    @Published var periodEditId: Int64? = nil
    @Published var pendingNewPeriodTableId: Int64? = nil
    @Published var pendingNewTableId: Int64? = nil
    @Published var previousDefaultTableId: Int64? = nil
    // 深链课程
    @Published var deepLinkCourse: CourseEntity? = nil
    // 语言切换重建 token(← Activity.recreate): L10n.didChange → 递增 → AppRoot 全树重建
    @Published var languageReload = 0
    // ★ v1.0.45 底栏 dock 样式: false=贴底, true=悬浮药丸
    //   ← Android v1.0.45 b0f8280;状态由 AppPrefs 持有, 监听 .didChange 自动反向同步
    // ★ 2026-10-26 两项制(Kerry 定): 初值走 NavStyleResolver(未写入=缺省悬浮)
    @Published var navFloating: Bool = NavStyleResolver.effectiveFloating()
    // ★ 渲染模式快照(native/floating/docked 三态) — tabs 分流真源;
    //   navFloating 仅表达"悬浮语义"(原生=内容直通屏底+底部余量), 形态分流看这里。
    @Published var navMode: NavBarRenderMode = NavStyleResolver.effectiveMode()
    // ← Android MainActivity.kt:342-351 RightHalfContent: importDraftRepository.observeAll()
    //   经 JwImportDraftCodec 映射成 UI 行模型; iOS getAll() 是同步等价(无 Flow)
    @Published var importDrafts: [ImportDraftRowModel] = []
    // ← Android JwImportActivity.EXTRA_DRAFT_ID: 管理页「恢复草稿」置位,
    //   AppRoot 消费后带进 JwImportFlow(incomingDraftId:) 并清零
    @Published var pendingDraftId: String? = nil

    private var langObserver: NSObjectProtocol?
    private var prefsObserver: NSObjectProtocol?

    let scheduleViewModel: ScheduleViewModel
    private let draftRepository = ImportDraftRepository(AppDatabase.getShared())
    // ← Android MainActivity.kt:261 `rememberSleepyNavigator()`: 门面唯一实例。
    //   iOS 无 composition 生命周期, 挂在 VM 上 = 与 AppRoot 同寿(VM 由 AppDelegate
    //   永久持有, 与本懒加载实例互为 app-scoped 常驻对象, 不构成新增泄漏)。
    //   AppRoot 全部导航意图经它下发(push → vm.navigate 单一真源), 否则门面零消费方
    //   = F071 审计项 1 未闭环。
    lazy var navigator: SleepyNavigator = SleepyNavigator(viewModel: self)

    init(repository: ScheduleRepository) {
        scheduleViewModel = ScheduleViewModel(
            repo: repository,
            onWidgetsNeedReload: { WidgetCenter.shared.reloadAllTimelines() })
        langObserver = NotificationCenter.default.addObserver(
            forName: L10n.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.languageReload += 1
        }
        // ★ v1.0.45: 用户在设置页改 nav dock 偏好 → AppPrefs 写盘 → UserDefaults 发 .didChange →
        //   这里刷新 navFloating → PillNavigationBar 下一帧切 dockStyle 重建。
        prefsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main
        ) { [weak self] _ in
            // 2026-10-26 两项制: 生效值统一经 NavStyleResolver — 设置页写 prefs
            // (贴底/悬浮)后这里即重判; 悬浮档内部自动适配(原生可用→native,
            // 否则→自绘 floating 兜底)。
            self?.refreshNavMode()
        }
    }

    deinit {
        if let langObserver { NotificationCenter.default.removeObserver(langObserver) }
        if let prefsObserver { NotificationCenter.default.removeObserver(prefsObserver) }
    }

    /// 实时窗口尺寸上报(AppRoot background GeometryReader → preference)。
    /// rail 双栏判定首选此值(宽≥600pt 且 宽≥高): 旋转/Split View/Stage Manager
    /// 缩放皆即时覆盖; keyWindow 兜底只在冷启早期(回调未达)时保守按手机形态。
    /// ← Android 版本 PR#235 口径: 横屏判定用逐帧真实几何, 不用 orientation 枚举。
    private(set) var windowSize: CGSize? = nil

    func updateWindowSize(_ size: CGSize) {
        // 0 = PreferenceKey 初值/零 frame(极早期布局), 不参与判定(回退 keyWindow 兜底)
        guard size.width > 0, size.height > 0, windowSize != size else { return }
        windowSize = size
        refreshNavMode()
    }

    /// 底栏形态重判单一入口 — prefs 变更(设置页/清盘)、scenePhase.active
    /// (冷启兜底)与窗口尺寸变更都汇到这里;navMode 与 navFloating 同步,永不各说各话。
    /// floating 语义统一走 NavStyleResolver.floating(for:) — rail 水平占位、
    /// 底部零遮挡归 false(不能用 mode != .docked, 会把 rail 误判成悬浮)。
    func refreshNavMode() {
        let mode = NavStyleResolver.effectiveMode(windowSize: windowSize)
        let floating = NavStyleResolver.floating(for: mode)
        if navMode != mode { navMode = mode }
        if navFloating != floating { navFloating = floating }
    }

    // ← BackHandler: overlay 返回(pendingNewTable 丢弃链)
    func handleBack() {
        if let discardId = pendingNewTableId {
            let fallback = previousDefaultTableId
            pendingNewTableId = nil
            previousDefaultTableId = nil
            scheduleViewModel.discardNewTable(discardId, fallbackId: fallback)
            overlayScreen = nil
            editTableId = nil
        } else if let discardPeriodId = pendingNewPeriodTableId {
            // ← v1.0.60: 作息表编辑未保存返回 → 丢弃残留行(Android NavHost BackHandler 同语义)
            pendingNewPeriodTableId = nil
            scheduleViewModel.discardNewPeriodTable(id: discardPeriodId)
            overlayScreen = nil
            periodEditId = nil
        } else {
            overlayScreen = nil
            editingCourse = nil
            editTableId = nil
        }
    }

    // ← v1.0.60: 新建作息表 → 立即进编辑(编辑页按"未保存新表"处理,
    //   返回时 handleBack 丢弃残留行) ← Android createPeriodTableAndEdit
    func createPeriodTableThenEdit() {
        let newId = scheduleViewModel.insertPeriodTable(name: L10n.t("period_table_new"))
        if newId > 0 {
            pendingNewPeriodTableId = newId
            periodEditId = newId
            overlayScreen = .periodEdit
        }
    }

    // ← 新建空表(AllTables / Management 共用)
    func createNewTableThenEdit() {
        let previousId = scheduleViewModel.state.currentTable?.id
        // Select immediately so the editor has a synchronous currentTable while the
        // GRDB observation catches up; handleBack() still rolls it back if discarded.
        let newId = scheduleViewModel.createEmptyTable(commitSelection: true)
        previousDefaultTableId = previousId
        pendingNewTableId = newId
        editTableId = newId

        // A fullScreenCover(item:) cannot swap its active item in place. All Tables
        // is already presented when this callback fires, so close that cover first
        // and present the editor on the next run loop after its dismissal begins.
        if overlayScreen == .allTables {
            overlayScreen = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self, self.pendingNewTableId == newId else { return }
                self.overlayScreen = .editTable
            }
        } else {
            overlayScreen = .editTable
        }
    }

    // ← 深链: sleepy://course/<id>
    func handleDeepLinkCourse(_ id: Int64) {
        if deepLinkCourse?.id == id { return }
        let repo = ScheduleRepository(AppDatabase.getShared())
        if let course = try? repo.getCourse(id) {
            deepLinkCourse = course
        }
    }

    // ← Android MainActivity.kt:342-351 (observeAll + JwImportDraftCodec 映射)。
    //   getAll() = observeAll() 的同步等价; 解码失败的行直接跳过(Android mapNotNull 同义)。
    func refreshDrafts() {
        let entities = (try? draftRepository.getAll()) ?? []
        let importCoursesLabel = L10n.t("import_courses")
        importDrafts = entities.compactMap { entity in
            guard let snapshot = JwImportDraftCodec.fromJson(entity.payloadJson) else { return nil }
            return ImportDraftRowModel(
                id: entity.id,
                name: snapshot.tableName.isEmpty ? snapshot.school.name : snapshot.tableName,
                details: "\(snapshot.courses.count) \(importCoursesLabel)")
        }
    }

    // ← Android onRestoreDraft = startActivity(JwImportActivity + EXTRA_DRAFT_ID) (MainActivity.kt:359)
    func restoreImportDraft(_ id: String) {
        pendingDraftId = id
    }

    // ← Android onDeleteDraft = importDraftRepository.delete(id) (MainActivity.kt:362)
    func deleteDraft(_ id: String) {
        try? draftRepository.delete(id)
        refreshDrafts()
    }
}

// ← AppRoot composable
struct AppRoot: View {
    @EnvironmentObject var root: AppRootViewModel
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.localWakeUpColors) private var colors
    // ← themeMode/手动切主题联动
    @State private var themeMode: String = AppPrefs.shared.getThemeMode()
    @State private var themeKey: String = AppPrefs.shared.getThemeKey()
    // ← MainActivity.kt:171 CustomThemeStore.changes() 订阅: 同 id 就地改自定义主题时
    //   themeKey 不变, 只有这份文档串变化能让 SleepyThemeProvider 重跑并回读 getById。
    @State private var customThemesJson: String = ""
    // ★ 底栏形态冷启兜底刷新: 自适应只在"未显式设置"路径生效, 而该判定依赖
    //   keyWindow.safeAreaInsets — 冷启极早窗口未就绪时 resolver 保守按悬浮。
    //   回前台(active)必然有窗口 → 重判一次纠偏(悬浮↔贴底切换仅非全面屏设备可见)。
    @Environment(\.scenePhase) private var scenePhase
    @State private var jwImportActive = false
    // ★ iOS 16 sheet 冲突修复: ImportSheet 关闭动画中直接 present JwImportFlow
    //   会被 SwiftUI 丢弃(同一 runloop 两个 sheet 状态翻转)→ 延到 dismiss 完成。
    @State private var jwImportRequested = false
    // ← Android EXTRA_DRAFT_ID 入参: 恢复草稿时带进 JwImportFlow(普通导入为 nil)
    @State private var jwIncomingDraftId: String? = nil
    // ← issue#39: 流程内 activeImport 为真时封掉 sheet 下滑关闭, 否则绕过退出确认静默丢进度
    @State private var jwActiveImport = false

    var body: some View {
        // iOS 15 兼容(6s Plus 真机 = 15.8.8):此处仅作容器,无 NavigationLink 压栈,
        // 旧 API 行为等价(NavigationStack 是 iOS16+ API)。
        // ★ v7.10.17 6sp 空白修复 v2: NavigationView 即使 .navigationBarHidden(true)
        //   在 iOS 15.6 stack 风格仍预占约 88pt 透明 navbar 区域(.navigationBarHidden
        //   在 16+ 才稳定生效,15 上是 best-effort) → 所有页面顶栏上方 112pt 纯空白。
        //   AppRoot 没有 NavigationLink 需求 → 直接 root,不要 NavigationView 壳。
        //   JwImportFlow 内部仍保留 NavigationView(那里有真正的 nav stack 行为)。
        // ★ 键盘避让只在 tab 层忽略(旧 fullScreenCover 时代对整个 mainContent 忽略);
        //   浮层走自绘 ZStack 容器, 保留键盘避让 → AddCourse 输入框自动避开键盘。
        mainContent
        // ★ 实时尺寸通道(← Android 版本 Configuration.screenWidthDp/HeightDp 逐帧
        //   重算语义 + PR#235 几何闸口径): background GeometryReader 零布局侵入,
        //   变更回灌 VM → rail 双栏↔手机形态随旋转/分屏/Stage Manager 缩放即切。
        //   iPhone 恒竖屏, 回调值不变=空操作。
        .background(GeometryReader { proxy in
            Color.clear.preference(key: WindowSizePreferenceKey.self,
                                   value: proxy.size)
        })
        .onPreferenceChange(WindowSizePreferenceKey.self) { size in
            root.updateWindowSize(size)
        }
        // ← Activity.recreate(): 语言切换 → L10n.didChange → languageReload+1 → 全树重建
        .id(root.languageReload)
        .modifier(SleepyThemeProvider(darkTheme: isDark, themeKey: themeKey,
                                      customThemeVersion: customThemesJson))
        .preferredColorScheme(schemeOverride)
        // ← MainActivity.kt:171: 自定义主题文档变更 = 独立失效信号(同 id 就地编辑时
        //   themeKey 不变), 订阅后回写 token → provider 重跑 → 重读 CustomThemeStore.getById
        .onReceive(CustomThemeStore.changes()) { customThemesJson = $0 }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        // ★ Xcode14/iOS16.4 模拟器: XCUIApplication.open(_:) 丢 URL(只 launch 不投递,
        //   SpringBoard 收不到 with-url 请求)→ UI 测试改由 app 内自触发
        //   UIApplication.open 走真实系统路由。真实用户路径 onOpenURL 不变。
        .onAppear {
            if let raw = ProcessInfo.processInfo.environment["SLEEPY_UI_TEST_OPENURL"],
               let url = URL(string: raw) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    UIApplication.shared.open(url)
                }
            }
            // ← SleepyApp.onCreate: 预加载当年+明年节假日数据(磁盘/网络)
            Task { await HolidayManager.preload() }
            // ← Android observeAll() 常驻订阅的等价: 进入即读一次草稿列表
            root.refreshDrafts()
            // 冷启兜底: onAppear 时窗口已就位, 重判一次(inset 判定不再可能 nil)
            root.refreshNavMode()
        }
        // ★ 回前台重判底栏形态(仅"未显式设置"自适应路径有意义; 显式选择时
        //   resolver 设置优先, 重判结果不变)。
        .onChange(of: scenePhase) { phase in
            if phase == .active { root.refreshNavMode() }
        }
        // 深链课程 → 编辑(← LaunchedEffect(deepLinkCourse?.id))
        .onChange(of: root.deepLinkCourse?.id) { courseId in
            if courseId != nil {
                root.editingCourse = root.deepLinkCourse
                root.deepLinkCourse = nil
            }
        }
        // pendingImportText → 自动切 Manage + 弹导入(← LaunchedEffect(pendingImportText))
        .onChange(of: PendingImportText.value) { text in
            if text != nil {
                root.currentTab = .manage
            }
        }
        // 待恢复草稿 → 带进 JwImportFlow 入参并消费清零(← EXTRA_DRAFT_ID 一次性语义)
        .onChange(of: root.pendingDraftId) { id in
            guard let id = id else { return }
            jwIncomingDraftId = id
            root.pendingDraftId = nil
            jwImportRequested = true
        }
        .sheet(isPresented: $jwImportActive, onDismiss: {
            // 下滑关闭与流程内关闭两条路径都收敛到这里: 入参带完即清, 草稿列表随流程结束刷新
            jwIncomingDraftId = nil
            jwActiveImport = false
            root.refreshDrafts()
        }) {
            JwImportFlow(onFinish: {
                jwImportActive = false
            }, incomingDraftId: jwIncomingDraftId,
               onActiveImportChanged: { jwActiveImport = $0 })
            // Sheet 是独立 presentation tree；显式注入主题，避免自定义颜色环境回落到 lightScheme。
            .modifier(SleepyThemeProvider(darkTheme: isDark, themeKey: themeKey,
                                          customThemeVersion: customThemesJson))
            .preferredColorScheme(schemeOverride)
            // ← issue#39: 教务流程进行中禁止下滑关闭(绕过退出确认 = 静默丢进度)
            .interactiveDismissDisabled(jwActiveImport)
        }
        // ★ sheet 冲突修复续: ImportSheet dismiss 完成后(0.45s 动画)再 present JW 流程
        .onChange(of: jwImportRequested) { req in
            guard req else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if jwImportRequested {
                    jwImportActive = true
                    jwImportRequested = false
                }
            }
        }
    }

    // ← AppPrefs.isDarkMode(context, systemDark)
    private var isDark: Bool {
        AppPrefs.shared.isDarkMode(isSystemDark: systemScheme == .dark)
    }

    // ← Android isSystemInDarkTheme() 真跟随: system 模式传 nil(不强制覆盖)。
    //   preferredColorScheme 非 nil 会把 @Environment(\.colorScheme) 锁成被覆盖的值,
    //   导致控制中心切换深浅色时 app 永远不跟 → "跟随系统"是假的。nil = 原生跟随。
    private var schemeOverride: ColorScheme? {
        themeMode == AppPrefs.THEME_MODE_SYSTEM ? nil : (isDark ? .dark : .light)
    }

    @ViewBuilder
    private var mainContent: some View {
        // ★ 根浮层 = 自绘 ZStack 容器(PresentOverlay):
        //   - 所有 OverlayScreen 页共用一份右滑转场 + 跟手侧滑返回驱动
        //   - 状态机(handleBack/pendingNewTable 丢弃链/深链)时序不变
        //   - holiday 子页由 GeneralSettings 内部 NavigationView 承载,不再列根
        // ★ type-check: 浮层内容仍走单一 PresentOverlay ViewModifier, 子树独立推导
        tabs
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .modifier(PresentOverlay(
                isDark: isDark,
                themeKey: themeKey,
                customThemeVersion: customThemesJson,
                overlayScreen: $root.overlayScreen,
                editingCourse: root.editingCourse,
                editTableId: root.editTableId,
                pendingNewTableId: root.pendingNewTableId,
                periodEditId: root.periodEditId,
                pendingNewPeriodTableId: root.pendingNewPeriodTableId,
                onOpenPeriodEdit: { periodId, isNew in
                    root.periodEditId = periodId
                    root.pendingNewPeriodTableId = isNew ? periodId : nil
                    root.overlayScreen = .periodEdit
                },
                scheduleViewModel: root.scheduleViewModel,
                themeMode: themeMode,
                onDismiss: { root.overlayScreen = nil; root.editingCourse = nil },
                onBack: { root.handleBack() },
                onSavedAdd: {
                    root.overlayScreen = nil
                    root.editingCourse = nil
                    root.currentTab = .schedule
                },
                onSavedTable: {
                    root.overlayScreen = nil
                    root.editTableId = nil
                    root.pendingNewTableId = nil
                    root.previousDefaultTableId = nil
                },
                onDeletedTable: {
                    root.overlayScreen = nil
                    root.editTableId = nil
                    root.currentTab = .schedule
                },
                onCreateNewTable: { root.createNewTableThenEdit() },
                onOpenEditTable: { tableId in
                    root.editTableId = tableId
                    root.pendingNewTableId = nil
                    root.overlayScreen = .editTable
                },
                onThemeModeChange: { mode in
                    themeMode = mode
                    themeKey = AppPrefs.shared.getThemeKey()
                },
                // ← Android themeKeyFlow.collectAsState: 选主题色即时下发全树,
                //   不再等重进页面/重启(AppRoot.themeKey 是一次性 @State,必须回写)
                onThemeKeyChange: {
                    themeKey = AppPrefs.shared.getThemeKey()
                },
                onOpenLicense: { root.overlayScreen = .license }))
    }

    // ← Scaffold + PillNavigationBar + 4 Tab
    // ★ 2026-10-26 两项制三态分流(NavStyleResolver 单一真源):
    //   - native:   悬浮档 + iOS 26+ 原生可用 → 系统 TabView(Liquid Glass 原生悬浮玻璃)
    //   - floating: ZStack(alignment: .bottom) + content fillMaxSize 直通屏底 +
    //              bar 作为 overlay 浮在底部 12pt 上(背景延续,无空缺)。
    //              ← Android ff66ddd "dock 模式弃 Scaffold bottomBar 占位, Box overlay
    //                Align.BottomCenter 叠加; 内容 fillMaxSize 直通屏幕底" 1:1。
    //   - docked:  VStack(content + bar) → bar 贴底 76pt 占用下方(非全面屏/Home 键设备)
    //   floating/docked = 自绘二态(用户显式选择或 iOS<26); scroll padding 补偿
    //   floatingScrollBottomPadding(FAB 式滚动余量, Android LocalNavExtraBottomPadding 同位)。
    private var tabs: some View {
        Group {
            switch root.navMode {
            case .native:
                nativeTabs
            case .floating:
                floatingTabs
            case .docked:
                dockedTabs
            case .rail:
                railTabs
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TabsCanvasBackground().ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    // ★ rail 模式(iPad 横屏/分屏宽侧 ≥600pt 且横屏几何): Row{侧栏, 双栏内容} —
    //   ← Android 版本 SleepyNavHost issue#45 ③ PR#114 master-detail 终态:
    //   Row{ NavigationRail(3 槽跑道胶囊), Row(padding h16/v12, spacedBy 16){
    //     左 50% ScheduleScreen 永久固定(surfaceContainerLow 16 圆角卡),
    //     12dp 暗色沟槽(background 色),
    //     右 50% AnimatedContent(200ms 淡切) Today/Manage/Mine(同款卡) } }
    //   导航仍是 root.currentTab 单点真值(切 tab 不换容器, 与 Android 同);
    //   宽屏下 currentTab=.schedule(Compact 缺省)派生右半=.today(← Android
    //   effectiveRightTab 同款), rail 点击只设 today/manage/mine。
    //   宽度通道: background GeometryReader 零布局侵入, .global 系分屏/Stage
    //   Manager 缩放后的实际窗口尺寸; 变更即回灌 refreshNavMode 重判。
    private var railTabs: some View {
        HStack(spacing: 0) {
            NavigationRailBar(rightTabs: tabletRailItems,
                              selectedTab: tabletRightTab,
                              scheduleIcon: "calendar")
                .ignoresSafeArea(edges: .bottom)
            // ← Android 内容 Row: padding(horizontal=16, vertical=12) +
            //   spacedBy(16){ 左卡; Box(width=12, background 沟槽); 右卡 }
            //   → 两卡之间总间隔 = 16 + 12(沟槽盒) + 16 = 44dp, 沟槽盒 background
            //   色整高(卡片同高, 含卡上下缘)。iOS HStack(spacing:16) + 12pt 盒逐字复刻。
            HStack(spacing: 16) {
                tabletPaneCard(content: tabletSchedulePane)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle()
                    .fill(railGapColor)
                    .frame(width: 12)
                tabletPaneCard(content: tabletRightPane)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    /// 双栏派生右半 tab(← Android effectiveRightTab: currentTab==Schedule → Today)。
    private var tabletRightTab: AppRootViewModel.Tab {
        root.currentTab == .schedule ? .today : root.currentTab
    }

    /// rail 三项数据(today/manage/mine 固定槽位, ← Android rail 无 Schedule 独立项)。
    private var tabletRailItems: [PillNavItemData] {
        [
            PillNavItemData(id: "today", icon: "doc.on.doc",
                            label: L10n.format("tab_today"),
                            selected: tabletRightTab == .today) { root.currentTab = .today },
            PillNavItemData(id: "manage", icon: "gearshape",
                            label: L10n.format("tab_manage"),
                            selected: tabletRightTab == .manage) { root.currentTab = .manage },
            PillNavItemData(id: "mine", icon: "person",
                            label: L10n.format("tab_mine"),
                            selected: tabletRightTab == .mine,
                            // ← Android: 普通项形态才吃 updateNoticeVisible(胶囊
                            //   形态由 NavigationRailBar 内 tabShowUpdateDot 分支处理)
                            badge: updateNotifier.noticeVisible) { root.currentTab = .mine },
        ]
    }

    /// 左半课表 pane — ← Android tablet 分支 ScheduleScreen 直构(非 MainTabs 的
    /// Tab.Schedule 包装): onGoImport = 切 Manage + 新建课表流(iOS 无 AddTable 路由,
    /// createNewTableThenEdit = MainActivity 等价封装, SleepyApp:690 同款映射)。
    private var tabletSchedulePane: some View {
        ScheduleScreen(
            viewModel: root.scheduleViewModel,
            viewMode: $root.scheduleViewMode,
            onGoImport: {
                root.currentTab = .manage
                root.createNewTableThenEdit()
            },
            onManualAdd: { root.navigator.openAddCourse() },
            onCreateTable: { root.createNewTableThenEdit() },
            onEditCourse: { course in
                root.navigator.session.beginEditCourse(course)
                root.navigator.openAddCourse(courseId: course.id, editing: true)
            })
    }

    /// 右半 pane — ← Android RightHalfContent(AnimatedContent 200ms 淡切):
    /// Today 用 compact 变体(← CompactTodayPane: 无背景/竖排紧凑/无底部药丸余量),
    /// Manage/Mine 复用手机版原样(与 Android 右半直构 ManagementPage/MineScreen 同)。
    @ViewBuilder
    private var tabletRightPane: some View {
        let tab = tabletRightTab
        Group {
            switch tab {
            case .today:
                TodayScreen(viewModel: root.scheduleViewModel,
                            compact: true,
                            onEditCourse: { course in
                                root.navigator.session.beginEditCourse(course)
                                root.navigator.openAddCourse(courseId: course.id, editing: true)
                            })
            case .manage:
                managementPage
            default:
                screen(for: tab)
            }
        }
        // .id 强制 tab 切换时重建视图身份 → 入场/离场各走 opacity 过渡(← fade 200ms)
        .id(tab)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: tab)
    }

    /// 双栏面板卡(← Android Box.clip(RoundedCornerShape(16.dp))
    ///   .background(colors.surfaceContainerLow))
    private func tabletPaneCard<Content: View>(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(railCardColor)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // 主题色在计算属性内解析(AppRoot 已注入 @Environment colors)
    private var railCardColor: Color { colors.surfaceContainerLow }
    private var railGapColor: Color { colors.background }

    // ★ native 分支(ios26 起生效 — 部署目标 15.6 下此分支永不触达, iOS15/16
    //   设备由 resolver 判 floating/docked): 系统 TabView = 原生悬浮玻璃胶囊,
    //   选中动效/长按交互/无障碍/横屏收敛全部交系统。
    //   - ★ 内容直通屏底(2026-10-26 Kerry 实机指出): iOS26 系统栏仍给子内容
    //     加 bottom safe area → 课表容器在玻璃 dock 上方就被截断, dock 区露出
    //     一条死白背景。修复 = 每屏 ignoresSafeArea(.container,.bottom) 铺到
    //     屏底, 再注入 nativeScrollBottomPadding 作滚动余量(最后一行可滚离
    //     玻璃遮挡) — 与自绘 floating 的"直通屏底+navExtra"同一语义。
    //   - tabItem 图标沿用 PillNavigationBar 同款 SF Symbols, 文案沿用 tab_* 键。
    //   - Mine 红点: badge("") = UITabBarItem 空串小圆点语义(iOS16+ API;
    //     iOS15 编译兜底 .badge(0/1), 实际永不执行)。
    //   - 4 屏无 onAppear 副作用(数据经 root/scheduleViewModel 常驻订阅),
    //     TabView 懒实例化其余 tab 安全。
    private var nativeTabs: some View {
        TabView(selection: Binding(
            get: { root.currentTab },
            set: { root.currentTab = $0 })) {
            screen(for: .schedule)
                    .nativeScreen(extraBottom: nativeScrollBottomPadding)
                .tabItem { Label(L10n.t("tab_schedule"), systemImage: "calendar") }
                .tag(AppRootViewModel.Tab.schedule)
            screen(for: .today)
                    .nativeScreen(extraBottom: nativeScrollBottomPadding)
                .tabItem { Label(L10n.t("tab_today"), systemImage: "doc.on.doc") }
                .tag(AppRootViewModel.Tab.today)
            screen(for: .manage)
                    .nativeScreen(extraBottom: nativeScrollBottomPadding)
                .tabItem { Label(L10n.t("tab_manage"), systemImage: "gearshape") }
                .tag(AppRootViewModel.Tab.manage)
            nativeMineScreen
                    .nativeScreen(extraBottom: nativeScrollBottomPadding)
                .tabItem { Label(L10n.t("tab_mine"), systemImage: "person") }
                .tag(AppRootViewModel.Tab.mine)
        }
        .tint(colors.primary)
        // ★ 视口直通屏底(2026-10-26 实机): 每屏子级 ignoresSafeArea 在 iOS26
        // TabView 内被系统重新钳回安全区 → 提到 TabView 层打穿, 内容容器
        // 铺到玻璃 dock 正下方(与 Android edge-to-edge 一致)。
        .ignoresSafeArea(.container, edges: .bottom)
    }

    /// ★ native 每屏统一处理(2026-10-26 实机修复): 内容容器直通屏底
    /// (玻璃 dock 下透出课表背景, 不再截断成死白条), 同时注入滚动底部余量
    /// = 玻璃 dock 占位高(胶囊 ~64 + 底隙 ~20 + 缓冲), 最后一行可滚离遮挡。
    /// 余量走 .localNavExtraBottomPadding 与自绘 floating 同一注入点 —
    /// CourseTableView/Today/Mine/Management 已统一读该 env, 零页面改动。
    private var nativeScrollBottomPadding: CGFloat { 64 + 20 + 8 }

    @ViewBuilder
    private var nativeMineScreen: some View {
        let dot: String? = updateNotifier.noticeVisible ? "" : nil
        if #available(iOS 16.0, *) {
            screen(for: .mine).badge(dot)
        } else {
            screen(for: .mine).badge(updateNotifier.noticeVisible ? 1 : 0)
        }
    }

    /// 4 屏内容工厂(← v1.0.60 差量: Mine badge 走 UpdateNotifier.noticeVisible,
    /// 与 Android SleepyNavHost 同一状态源) — docked/floating 单屏渲染与
    /// native TabView 多屏实例化共用, 页面接线零重复。
    @ViewBuilder
    private func screen(for tab: AppRootViewModel.Tab) -> some View {
        switch tab {
        case .schedule:
            ScheduleScreen(
                viewModel: root.scheduleViewModel,
                viewMode: $root.scheduleViewMode,
                onGoImport: { root.currentTab = .manage },
                // ← Android MainTabs:328 onManualAdd = navigator.openAddCourse()
                onManualAdd: { root.navigator.openAddCourse() },
                onCreateTable: { root.createNewTableThenEdit() },
                // ← Android MainTabs:330 onEditCourse = session.beginEditCourse(course)
                //   + navigator.openAddCourse(course.id, editing: true)
                onEditCourse: { course in
                    root.navigator.session.beginEditCourse(course)
                    root.navigator.openAddCourse(courseId: course.id, editing: true)
                })
        case .today:
            TodayScreen(viewModel: root.scheduleViewModel,
                        // ← Android MainTabs:333 TodayScreen.onEditCourse 同式
                        onEditCourse: { course in
                            root.navigator.session.beginEditCourse(course)
                            root.navigator.openAddCourse(courseId: course.id, editing: true)
                        })
        case .manage:
            managementPage
        case .mine:
            // ← Android MainTabs:370-377 MineScreen 八入口全部 navigator.openXxx()
            MineScreen(
                viewModel: root.scheduleViewModel,
                onOpenAllTables: { root.navigator.openAllTables() },
                onOpenCourseList: { root.navigator.openCourseList() },
                onOpenPeriodTables: { root.navigator.openPeriodTables() },
                onOpenAppearance: { root.navigator.openAppearance() },
                onOpenGeneral: { root.navigator.openGeneral() },
                onOpenExport: { root.navigator.openExport() },
                onOpenReminder: { root.navigator.openReminder() },
                onOpenAbout: { root.navigator.openAbout() })
        }
    }

    // 4 个 tab 的数据:共用于 docked / floating 两个自绘分支,避免重复
    // ← v1.0.60 差量: Mine tab badge = UpdateNotifier.noticeVisible (更新红点,
    //   与 Android SleepyNavHost badge = updateNoticeVisible && tab == Mine 同一状态源)
    @ObservedObject private var updateNotifier = UpdateNotifier.shared
    private var navItems: [PillNavItemData] {
        [
            PillNavItemData(id: "schedule", icon: "calendar",
                            label: L10n.format("tab_schedule"),
                            selected: root.currentTab == .schedule) { root.currentTab = .schedule },
            PillNavItemData(id: "today", icon: "doc.on.doc",
                            label: L10n.format("tab_today"),
                            selected: root.currentTab == .today) { root.currentTab = .today },
            PillNavItemData(id: "manage", icon: "gearshape",
                            label: L10n.format("tab_manage"),
                            selected: root.currentTab == .manage) { root.currentTab = .manage },
            PillNavItemData(id: "mine", icon: "person",
                            label: L10n.format("tab_mine"),
                            selected: root.currentTab == .mine,
                            badge: updateNotifier.noticeVisible) { root.currentTab = .mine },
        ]
    }

    // 当前 Tab 对应屏 — 工厂 screen(for:) 单源, 本壳仅供自绘 docked/floating 分支取当前页。
    @ViewBuilder
    private var tabContent: some View {
        screen(for: root.currentTab)
    }

    // 管理页(AppRoot 私有状态绑定最重的一屏) — docked/floating/native 共用。
    private var managementPage: some View {
        ManagementPage(
            viewModel: root.scheduleViewModel,
            autoShowImportSheet: PendingImportText.value != nil,
            onJwImportRequested: { jwImportRequested = true },
            // ← Android MainTabs:352 onCreateNewTableRequested = onCreateNewTable
            //   (MainActivity 闭包 = createEmptyTable + openEditTable; iOS 状态机
            //   封装在 createNewTableThenEdit, 含 allTables-cover 换页时序, 保持直调)
            onCreateNewTableRequested: { root.createNewTableThenEdit() },
            // ← Android MainTabs:355 onManualAdd = navigator.openAddCourse()
            onManualAdd: { root.navigator.openAddCourse() },
            // ← Android MainTabs:355 onEditCurrentTable = navigator.openEditTable()
            onEditCurrentTable: { root.navigator.openEditTable() },
            // ← Android MainTabs:355 onExportRequested = navigator.openExport()
            onExportRequested: { root.navigator.openExport() },
            // ★ 导入完成链(← Android onImported: 留在管理页, 摘要卡就地刷新)
            onImported: {
                // ← Android ce7f7924: 导入完成留在管理页(摘要卡就地刷新), 不再硬跳课表 Tab
                PendingImportText.value = nil
            },
            // ← Android SleepyNavHost: onOpenAllTables = navigator.openAllTables()
            onOpenAllTables: { root.navigator.openAllTables() },
            // ← Android MainTabs:354 createPeriodTableAndEdit(newId) =
            //   navigator.createPeriodTableAndEdit(newId) (内部 openPeriodEdit(newId, isNew=true))
            onCreateNewPeriodTableRequested: { newId in
                root.navigator.createPeriodTableAndEdit(newId: newId)
            },
            // ← Android MainActivity.kt:353-364 drafts/onRestoreDraft/onDeleteDraft
            //   (onRestoreDraft = startActivity(JwImportActivity + EXTRA_DRAFT_ID) —
            //   iOS 无 Activity 通道, restoreImportDraft → pendingDraftId 等价 plumbing)
            drafts: root.importDrafts,
            onRestoreDraft: { id in root.restoreImportDraft(id) },
            onDeleteDraft: { id in root.deleteDraft(id) })
    }

    // ★ docked 模式:bar 占用 76pt(老行为)
    //   (注: ← Android 版 Compact 贴底已改官方 NavigationBar; iOS 维持自绘 docked =
    //   2026-10-26 Kerry 两项制定稿的有意差异, 不随 Android 动)
    private var dockedTabs: some View {
        VStack(spacing: 0) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            PillNavigationBar(items: navItems, dockStyle: .docked)
        }
    }

    // ★ floating 模式:
    //   - ZStack overlay 让 bar 浮在内容之上,不占布局空间
    //   - ignoresSafeArea bottom 让内容背景直通屏幕底(无空缺)
    //   - 内容底部 padding = floatingScrollBottomPadding → FAB 式滚动余量,
    //     最后一节课不被悬浮 bar 遮挡(Android LocalNavExtraBottomPadding 同位)
    //   - bar alignment .bottom 自带 PillNavigationBar 内部 bottomFloat=12pt,
    //     浮在屏幕底 12pt 上(可视即"悬浮胶囊")
    //   - 同步把 floatingScrollBottomPadding 注入 .localNavExtraBottomPadding
    //     让 MineScreen/ManagementPage/TodayScreen/CourseTableView 自己读 →
    //     内部 padding(bottom, 16 + navExtra) 一字对齐 Android。
    private var floatingTabs: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .bottom)
            PillNavigationBar(items: navItems, dockStyle: .floating)
        }
        .environment(\.localNavExtraBottomPadding, floatingScrollBottomPadding)
    }

    // FAB 式滚动余量 = capsuleHeight(64) + bottomFloat(12) + extra(12 视觉缓冲)
    // ← Android ff66ddd navHeight + fabPadding + WindowInsets.navigationBars
    private var floatingScrollBottomPadding: CGFloat {
        DockSpec.capsuleHeight + DockSpec.bottomFloat + 12
    }

    // ← handleDeepLinkIntent(平台差异表#4: Intent extras → URL scheme)
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "sleepy" else { return }
        switch url.host {
        case "open":
            break   // widget 点击(sleepy://open) → 冷启/回前台即达
        case "course":
            if let id = Int64(url.lastPathComponent) {
                root.handleDeepLinkCourse(id)
            }
        case "import":
            // 分享扩展/其他 app 传文本: sleepy://import?text=...
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let text = comps.queryItems?.first(where: { $0.name == "text" })?.value {
                PendingImportText.value = text
                root.currentTab = .manage
            }
        default:
            break
        }
    }
}

// ★ v7.10.18 type-check v3: 9 个独立 PresentXxx ViewModifier, 每个只挂 1 个
//   presentation (.fullScreenCover 或 .sheet), 由 Group { EmptyView().modifier(...) }
//   在 mainContent 里链式挂载。每个 modifier 子树类型推导独立预算, 避免
//   "unable to type-check this expression in reasonable time"。
//   闭包走构造注入, AppRoot 显式传 root 派生值。

/// tabs 画布底色。★ 必须是独立子 View:AppRoot.colors 读的是
/// SleepyThemeProvider 之上的环境值(= WakeUpColorsKey.defaultValue = lightScheme),
/// 直接 `.background(colors.background)` 会让暗黑模式透出 #FEF7FF 白底
/// (切换控件行留白/卡片缝隙处可见)。子 View 在 provider 子树内解析 env → 主题正确。
/// ★ native 每屏统一处理(2026-10-26 实机修复 — Kerry 指出课表没铺到 dock 下面):
/// iOS26 系统 TabView 仍给子内容加 bottom safe area → 屏幕内容在玻璃 dock 上方
/// 就截断, 露出 UITabBarController 的白底(死白条)。修复 = ignoresSafeArea 让
/// 内容直通屏底(玻璃下透出课表背景), 并注入滚动底部余量(与自绘 floating 同
/// 一点位 .localNavExtraBottomPadding, CourseTableView/Today/Mine/Management
/// 已统一读该 env) → 最后一行可滚离玻璃遮挡。
private struct NativeScreenModifier: ViewModifier {
    let extraBottom: CGFloat
    func body(content: Content) -> some View {
        content
            .ignoresSafeArea(.container, edges: .bottom)
            .environment(\.localNavExtraBottomPadding, extraBottom)
            // overlay 全屏坐标挂载(2026-10-26): background 探针被压缩 0×0 停在
            // 视口底, 爬到的链不完整 → 改 overlay + ignoresSafeArea 让探针
            // 铺满真实全屏 frame, 链 dump 才有意义。
            .overlay(TabBarTransparentProbe().allowsHitTesting(false).ignoresSafeArea())
    }
}

/// ★ iOS26 TabView 容器白底打透 + 视口下探(2026-10-26 红画布实验定位):
/// SwiftUI TabView 底层 UITabBarController.view / wrapper 视图默认不透明
/// systemBackground, 盖在 TabsCanvasBackground 之上 → 玻璃 dock 区露死白条;
/// 且 iOS26 floating bar 注入 ~85pt bottom safe area, 子级/TabView 级
/// ignoresSafeArea 均被重钳(两层实验皆无效)。修复 = 探针沿 superview 链:
/// ① 沿途 wrapper 背景设 clear(画布从玻璃下透出);
/// ② 链上首个 VC 设 additionalSafeAreaInsets.bottom = -(系统基础 inset),
///    把视口推回真屏底(edge-to-edge, 与 Android 一致; 玻璃 bar 悬浮其上,
///    滚动余量经 .localNavExtraBottomPadding=92pt 让最后一行可滚离遮挡)。
private struct TabBarTransparentProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        DispatchQueue.main.async { Self.apply(from: v) }
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { Self.apply(from: uiView) }
    }
    static func apply(from v: UIView) {
        var cur = v.superview
        var fixedVC = false
        var lines: [String] = ["probe frame=\(v.frame) win=\(String(describing: v.window?.frame))"]
        while let c = cur, let w = c.window, c !== w {
            c.backgroundColor = .clear
            let vc = c.next as? UIViewController
            lines.append("\(String(describing: type(of: c))) frame=\(c.frame) saBottom=\(c.safeAreaInsets.bottom) vc=\(vc.map { String(describing: type(of: $0)) } ?? "-") addSA=\(vc?.additionalSafeAreaInsets.bottom.description ?? "-")")
            // ★ 目标 = UITabBarController 本体(2026-10-26 二次修正): iOS26 的
            // 玻璃 bar 给其 view 注入 ~85pt bottom safe area, 子 tab 内容全部
            // 继承该 inset → 视口死锁 bar 上沿。给 bar 自己加负 additional →
            // 整棵内容树视口推到屏底。bar 悬浮位置由 bar 布局自管, 不随
            // safe area 移动(实测验证)。子级 hosting VC 的 additional 无效
            // (TabView 重钳), 不打。
            if !fixedVC, let tbc = c.next as? UITabBarController {
                fixedVC = true
                // ★ 打的是 tab 子 VC(2026-10-26 三次修正): iOS26 玻璃 bar 把
                // 自身高度(49pt)作为 safe area 注入每个 tab 内容 VC → 视口
                // 死锁 bar 上沿, 内容滚不到屏底。TBC.additionalSafeAreaInsets
                // 无效(实测 -34 只削掉 home indicator, 49 在子 VC 层另加)。
                // → 逐子 VC 抵消其 bar 贡献量, 只保留 home indicator(34),
                //   与 Android edge-to-edge + gesture inset 语义一致。
                for child in tbc.children {
                    let cs = child.view.safeAreaInsets.bottom - child.additionalSafeAreaInsets.bottom
                    let target = -(max(cs - 34, 0))
                    if abs(child.additionalSafeAreaInsets.bottom - target) > 0.5 {
                        var i = child.additionalSafeAreaInsets
                        i.bottom = target
                        child.additionalSafeAreaInsets = i
                    }
                    lines.append("child \(String(describing: type(of: child))) saBottom=\(child.view.safeAreaInsets.bottom) → addSA=\(target)")
                }
            }
            cur = c.superview
        }
        // TEMP DEBUG: dump chain to app Documents (simulator FS shared with Mac)
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("chain.txt"), atomically: true, encoding: .utf8)
        }
    }
}

private extension View {
    func nativeScreen(extraBottom: CGFloat) -> some View {
        modifier(NativeScreenModifier(extraBottom: extraBottom))
    }
}

/// 实时窗口尺寸上报通道(AppRoot background GeometryReader → root.updateWindowSize)。
/// 初值 .zero = 未就绪(与 VM windowSize=nil 区分开: 首个真实回调前不参与判定)。
private struct WindowSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct TabsCanvasBackground: View {
    @Environment(\.localWakeUpColors) private var colors

    var body: some View {
        colors.background
    }
}

/// overlay 容器底色 ← Android SleepyNavHost 每个 composable 自带 Scaffold(containerColor)。
/// 同 TabsCanvasBackground: 独立子 View 在 themedOverlay 的 provider 子树内解析 env,
/// 深色模式不会误取 provider 之上的 lightScheme 默认值。
private struct OverlayCanvasBackground: View {
    @Environment(\.localWakeUpColors) private var colors

    var body: some View {
        colors.background
    }
}

private struct PresentOverlay: ViewModifier {
    let isDark: Bool
    let themeKey: String
    // ← AppRoot.customThemesJson 同源下发: 浮层页在自定义主题就地编辑后也要重跑 provider
    var customThemeVersion: String = ""
    @Binding var overlayScreen: AppRootViewModel.OverlayScreen?
    let editingCourse: CourseEntity?
    let editTableId: Int64?
    let pendingNewTableId: Int64?
    // ← v1.0.60 作息表编辑路由参数(镜像 editTable 的 pending 丢弃链)
    let periodEditId: Int64?
    let pendingNewPeriodTableId: Int64?
    let onOpenPeriodEdit: (Int64, _ isNew: Bool) -> Void
    let scheduleViewModel: ScheduleViewModel
    let themeMode: String
    let onDismiss: () -> Void
    let onBack: () -> Void
    let onSavedAdd: () -> Void
    let onSavedTable: () -> Void
    let onDeletedTable: () -> Void
    let onCreateNewTable: () -> Void
    let onOpenEditTable: (Int64) -> Void
    let onThemeModeChange: (String) -> Void
    let onThemeKeyChange: () -> Void
    let onOpenLicense: () -> Void

    // ← AppRoot.schemeOverride 同源: system 模式 nil = 真跟随系统
    private var schemeOverride: ColorScheme? {
        themeMode == AppPrefs.THEME_MODE_SYSTEM ? nil : (isDark ? .dark : .light)
    }

    // 浮层容器状态: shownScreen 镜像 activeScreen(带转场生命周期),
    // dragX = 侧滑跟手位移, dismissSeq 防过期定时器串页。
    @State private var shownScreen: AppRootViewModel.OverlayScreen?
    @State private var dragX: CGFloat = 0
    @State private var dismissSeq = 0

    // ← 原 fullScreenCover(item:) get 闭包语义: 深链直接置 editingCourse 也能呈现 addCourse
    private var activeScreen: AppRootViewModel.OverlayScreen? {
        if overlayScreen != nil { return overlayScreen }
        return editingCourse == nil ? nil : .addCourse
    }

    func body(content: Content) -> some View {
        // ★ 系统性手势适配: 所有 overlay 页共用一个自绘容器, 右滑转场 + 跟手侧滑返回。
        //   不再逐页挂 recognizer——以后新增 OverlayScreen case 自动获得同一套手势。
        ZStack {
            content
            if let screen = shownScreen {
                overlayContent(screen)
                    .offset(x: dragX)
                    // 容器级不透明底 ← Android SleepyNavHost 每个 composable 自带
                    // Scaffold(containerColor)。旧行为: 浮层零背景 → 直接透出下层
                    // tab 页, 深色模式下 = 白屏 (真机报告 "我的→设置页 全白")。
                    // 必须 ignoresSafeArea — 与 TabsCanvasBackground 挂载点(479)同款,
                    // 否则状态栏/底部 home indicator 区仍透底。
                    // ★ 必须独立子 View 在 provider 子树内解析 env: PresentOverlay
                    // 整体挂在根 SleepyThemeProvider 之外, 直接读环境拿到的是
                    // WakeUpColorsKey.defaultValue = lightScheme (白) 而非当前主题。
                    .background(OverlayCanvasBackground().ignoresSafeArea())
                    // ← Android SleepyNavHost.kt:171 sleepyForwardTransform: 入页 fadeIn110
                    //   + 中心浮起220, 出页 fadeOut+scaleOut(→0.92)。此前硬编码
                    //   .move(edge:.trailing) = 只有侧滑, 零消费 Material 转场表 (F069)。
                    .transition(SleepyMaterialTransition.forwardTransform)
            }
        }
        .onChange(of: activeScreen) { syncPresentation($0) }
        .onAppear {
            // 语言切换 → .id(languageReload) 整树重建 → 本修饰器 @State 复位 nil,
            // 但 VM.overlayScreen 仍持页 → 不恢复会把用户弹回根页
            // (Android Activity.recreate 保留当前页, 此处对齐)
            if shownScreen == nil, let active = activeScreen { shownScreen = active }
        }
    }

    private func syncPresentation(_ active: AppRootViewModel.OverlayScreen?) {
        if let screen = active {
            guard shownScreen != screen else { return }
            if shownScreen == nil {
                // 打开: 中心浮起 + 淡入(← Android sleepyForwardEnter, 非右缘滑入)。
                // forwardEnter 的 opacity/scale 段已自带 110ms/220ms 曲线,
                // 此处 withAnimation 只提供转场触发上下文。
                dragX = 0
                withAnimation(SleepyMaterialTransition.forwardAnimation) { shownScreen = screen }
            } else {
                // 极端竞态: 未经过 nil 直接换页 → 无动画切换, 复位位移
                shownScreen = screen
                dragX = 0
            }
        } else if shownScreen != nil {
            // 关闭路径①: 程序化关闭(✕ 按钮/保存/删除) → 右滑出动画后移除
            if dragX > 60 {
                shownScreen = nil
                dragX = 0
            } else {
                animateOutThen(then: {})
            }
        }
    }

    /// 关闭路径②: 侧滑过阈值 → 页面跟手滑出全程, 动画结束才回调 onBack(保持
    /// handleBack/createNewTableThenEdit 的状态机时序不变)。
    private func commitGestureDismiss(_ then: @escaping () -> Void) {
        animateOutThen(then: then)
    }

    // 关闭通路 ← F069 Option A: 出页交给 forwardTransform 的 removal(forwardExit =
    //   淡出 + 缩向 0.92, 220ms, Android sleepyPopExit 同形态), 不再把 dragX 推到屏外
    //   滑出 —— 滑出与 forwardExit 叠加 = 页面既滑走又缩放(双演)。dragX 只保留
    //   手势跟手 + 释放后 commit/cancel 的职责, 复位挪到移除完成后(此时已不可见, 无回弹)。
    private func animateOutThen(then: @escaping () -> Void) {
        withAnimation(SleepyMaterialTransition.forwardAnimation) { shownScreen = nil }
        dismissSeq += 1
        let seq = dismissSeq
        DispatchQueue.main.asyncAfter(deadline: .now() + SleepyMaterialTransition.forwardDuration) {
            guard seq == dismissSeq else { return }
            dragX = 0
            then()
        }
    }


    @ViewBuilder
    @MainActor
    private func overlayContent(_ screen: AppRootViewModel.OverlayScreen) -> some View {
        switch screen {
        case .addCourse:
            AddCourseScreen(
                viewModel: scheduleViewModel,
                onDismiss: onDismiss,
                onSaved: onSavedAdd,
                editingCourse: editingCourse)
                .themedOverlay(isDark: isDark, themeKey: themeKey, schemeOverride: schemeOverride,
                               customThemeVersion: customThemeVersion)
                .edgeBackGesture(dragX: $dragX, onBack: onDismiss, onCommit: commitGestureDismiss)
        case .allTables:
            AllTablesScreen(
                viewModel: scheduleViewModel,
                onDismiss: onDismiss,
                onCreateNewTable: onCreateNewTable,
                onOpenEditTable: onOpenEditTable)
                .themedOverlay(isDark: isDark, themeKey: themeKey, schemeOverride: schemeOverride,
                               customThemeVersion: customThemeVersion)
                .edgeBackGesture(dragX: $dragX, onBack: onDismiss, onCommit: commitGestureDismiss)
        case .editTable:
            EditTableScreen(
                viewModel: scheduleViewModel,
                tableId: editTableId,
                pendingNewTableId: pendingNewTableId,
                onDismiss: onBack,
                onDiscardPending: onBack,
                onSaved: onSavedTable,
                onDeleted: onDeletedTable)
                .themedOverlay(isDark: isDark, themeKey: themeKey, schemeOverride: schemeOverride,
                               customThemeVersion: customThemeVersion)
                .edgeBackGesture(dragX: $dragX, onBack: onBack, onCommit: commitGestureDismiss)
        case .general:
            GeneralSettingsScreen(onDismiss: onDismiss)
                .themedOverlay(isDark: isDark, themeKey: themeKey, schemeOverride: schemeOverride,
                               customThemeVersion: customThemeVersion)
                .edgeBackGesture(dragX: $dragX, onBack: onDismiss, onCommit: commitGestureDismiss)
        case .theme:
            AppearanceScreen(
                onDismiss: onDismiss,
                themeMode: themeMode,
                onThemeModeChange: onThemeModeChange,
                onThemeKeyChange: onThemeKeyChange,
                // ← Android Appearance Section④ 节次表头入口 (默认 no-op 已解除)
                onOpenPeriodHeaderSettings: { overlayScreen = .periodHeaderSettings })
                .themedOverlay(isDark: isDark, themeKey: themeKey, schemeOverride: schemeOverride,
                               customThemeVersion: customThemeVersion)
                .edgeBackGesture(dragX: $dragX, onBack: onDismiss, onCommit: commitGestureDismiss)
        case .export:
            ExportScreen(viewModel: scheduleViewModel, onDismiss: onDismiss)
                .themedOverlay(isDark: isDark, themeKey: themeKey, schemeOverride: schemeOverride,
                               customThemeVersion: customThemeVersion)
                .edgeBackGesture(dragX: $dragX, onBack: onDismiss, onCommit: commitGestureDismiss)
        case .reminder:
            ReminderScreen(onDismiss: onDismiss)
                .themedOverlay(isDark: isDark, themeKey: themeKey, schemeOverride: schemeOverride,
                               customThemeVersion: customThemeVersion)
                .edgeBackGesture(dragX: $dragX, onBack: onDismiss, onCommit: commitGestureDismiss)
        case .about:
            AboutScreen(onDismiss: onDismiss, onOpenLicense: onOpenLicense)
                .themedOverlay(isDark: isDark, themeKey: themeKey, schemeOverride: schemeOverride,
                               customThemeVersion: customThemeVersion)
                .edgeBackGesture(dragX: $dragX, onBack: onDismiss, onCommit: commitGestureDismiss)
        case .license:
            LicenseScreen(onDismiss: onDismiss)
                .themedOverlay(isDark: isDark, themeKey: themeKey, schemeOverride: schemeOverride,
                               customThemeVersion: customThemeVersion)
                .edgeBackGesture(dragX: $dragX, onBack: onDismiss, onCommit: commitGestureDismiss)
        case .courseList:
            CourseListScreen(onBack: onDismiss)
                .environmentObject(scheduleViewModel)
                .themedOverlay(isDark: isDark, themeKey: themeKey, schemeOverride: schemeOverride,
                               customThemeVersion: customThemeVersion)
                .edgeBackGesture(dragX: $dragX, onBack: onDismiss, onCommit: commitGestureDismiss)
        case .periodTables:
            PeriodTablesScreen(
                onBack: onDismiss,
                onOpenEdit: { periodId in
                    onOpenPeriodEdit(periodId, false)
                },
                onCreateNew: { newId in
                    // 新建 → 编辑页按"未保存新表"处理(返回时 handleBack 丢弃残留行)
                    onOpenPeriodEdit(newId, true)
                })
                .environmentObject(scheduleViewModel)
                .themedOverlay(isDark: isDark, themeKey: themeKey, schemeOverride: schemeOverride,
                               customThemeVersion: customThemeVersion)
                .edgeBackGesture(dragX: $dragX, onBack: onDismiss, onCommit: commitGestureDismiss)
        case .periodHeaderSettings:
            // ← Android PeriodHeaderSettingsScreen(外观页 Section④ 节次表头入口)
            //   屏自身直读 AppPrefs, 无需 VM 参数 (F087/F088 路由接线)
            PeriodHeaderSettingsScreen(onBack: onDismiss)
                .themedOverlay(isDark: isDark, themeKey: themeKey, schemeOverride: schemeOverride,
                               customThemeVersion: customThemeVersion)
                .edgeBackGesture(dragX: $dragX, onBack: onDismiss, onCommit: commitGestureDismiss)
        case .periodEdit:
            PeriodTableEditScreen(
                viewModel: scheduleViewModel,
                periodTableId: periodEditId ?? SleepyRoute.NO_ID,
                isNewUnsaved: pendingNewPeriodTableId != nil,
                onBack: onBack)
                .themedOverlay(isDark: isDark, themeKey: themeKey, schemeOverride: schemeOverride,
                               customThemeVersion: customThemeVersion)
                .edgeBackGesture(dragX: $dragX, onBack: onBack, onCommit: commitGestureDismiss)
        case .scheduleDisplay:
            ScheduleDisplayScreen(onBack: onDismiss)
                .themedOverlay(isDark: isDark, themeKey: themeKey, schemeOverride: schemeOverride,
                               customThemeVersion: customThemeVersion)
                .edgeBackGesture(dragX: $dragX, onBack: onDismiss, onCommit: commitGestureDismiss)
        }
    }
}

private extension View {
    func themedOverlay(isDark: Bool, themeKey: String, schemeOverride: ColorScheme?,
                       customThemeVersion: String = "") -> some View {
        modifier(SleepyThemeProvider(darkTheme: isDark, themeKey: themeKey,
                                     customThemeVersion: customThemeVersion))
            .preferredColorScheme(schemeOverride)
    }
}
// ★ 系统性侧滑返回驱动: 一个 UIKit 边缘 pan 识别器桥接 SwiftUI 容器位移。
//   页面跟手移动、可取消;内层 UINavigationController(HolidaySettings)的
//   原生 pop 识别器按 UIKit 独占规则优先, 本识别器自动失败, 无双重返回。
private struct OverlayBackDriver: UIViewControllerRepresentable {
    let onProgress: (CGFloat) -> Void
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> EdgeBackDriverVC {
        EdgeBackDriverVC(onProgress: onProgress, onFinish: onFinish)
    }

    func updateUIViewController(_ controller: EdgeBackDriverVC, context: Context) {
        controller.onProgress = onProgress
        controller.onFinish = onFinish
    }
}

private final class EdgeBackDriverVC: UIViewController, UIGestureRecognizerDelegate {
    var onProgress: (CGFloat) -> Void
    var onFinish: (Bool) -> Void
    private weak var installedView: UIView?
    private var committed = false

    init(onProgress: @escaping (CGFloat) -> Void, onFinish: @escaping (Bool) -> Void) {
        self.onProgress = onProgress
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        committed = false
        installRecognizerIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        installedView?.gestureRecognizers?.removeAll(where: { $0.delegate === self })
        installedView = nil
    }

    private func installRecognizerIfNeeded() {
        guard installedView == nil else { return }
        let hostView: UIView = parent?.view ?? self.view
        let recognizer = UIPanGestureRecognizer(target: self,
                                                action: #selector(handleEdgePan(_:)))
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        hostView.addGestureRecognizer(recognizer)
        installedView = hostView
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        let point = touch.location(in: gestureRecognizer.view)
        return point.x <= 30
    }

    // 独占: 内层原生 pop(HolidaySettings)先 begin 则本识别器失败, 避免双重返回
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        false
    }

    @objc private func handleEdgePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .changed:
            guard !committed else { return }
            onProgress(recognizer.translation(in: recognizer.view).x)
        case .ended:
            guard !committed else { return }
            let translation = recognizer.translation(in: recognizer.view)
            let velocity = recognizer.velocity(in: recognizer.view)
            let width = max(recognizer.view?.bounds.width ?? 1, 1)
            let commit = translation.x / width > 0.25 || velocity.x > 600
            committed = commit
            onFinish(commit)
        case .cancelled, .failed:
            if !committed { onFinish(false) }
        default:
            break
        }
    }
}

private extension View {
    /// 浮层页统一接入: 跟手位移写入容器 dragX, 过阈值由容器滑出后回调 onBack。
    func edgeBackGesture(dragX: Binding<CGFloat>,
                         onBack: @escaping () -> Void,
                         onCommit: @escaping (@escaping () -> Void) -> Void) -> some View {
        overlay {
            OverlayBackDriver(
                onProgress: { translation in
                    guard translation > 0 else { return }
                    dragX.wrappedValue = translation
                },
                onFinish: { commit in
                    if commit {
                        onCommit(onBack)
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                            dragX.wrappedValue = 0
                        }
                    }
                })
                .allowsHitTesting(false)
        }
    }
}
