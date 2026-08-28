// SleepyApp.swift — ← SleepyApp.kt + MainActivity.kt
// iOS App 壳: 全局依赖初始化 + 主题 Provider + 4 Tab 底栏 + overlay 导航 + 深链。
//
// 平台映射:
//   - SleepyApp.onCreate(通知调度/小组件刷新) → AppDelegate.init + didFinishLaunching
//   - MainActivity.setContent + AppRoot → WindowGroup { AppRoot }
//   - 深链 EXTRA_COURSE_ID → URL scheme sleepy://course/<id>(平台差异表#4)
//   - pendingImportText(外部 json 打开) → onOpenURL sleepy://import?text=

import SwiftUI
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
        super.init()
        // ← onCreate: 通知调度器接 repo;数据变更 → 刷 widget + 重排通知
        notificationScheduler.repositoryProvider = { [weak self] in self?.repository }
        repository.onDataChangedHook = { [weak self] in
            guard let self = self else { return }
            WidgetCenter.shared.reloadAllTimelines()
            self.notificationScheduler.scheduleAll()
        }
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // ← onCreate: 首启刷新小组件(WidgetUpdater.notifyDataChanged)
        WidgetCenter.shared.reloadAllTimelines()
        return true
    }
}

// ← AppRoot 状态机(overlay 导航 + 深链)
@MainActor
final class AppRootViewModel: ObservableObject {
    enum Tab: Hashable { case schedule, today, manage, mine }
    enum OverlayScreen: String { case addCourse, allTables, editTable, theme, general, export, reminder, about }

    @Published var currentTab: Tab = .schedule
    @Published var overlayScreen: OverlayScreen? = nil
    @Published var editingCourse: CourseEntity? = nil
    // ← rememberSaveable 导航参数(旋转恢复语义 — iOS 状态默认保留)
    @Published var editTableId: Int64? = nil
    @Published var pendingNewTableId: Int64? = nil
    @Published var previousDefaultTableId: Int64? = nil
    // 深链课程
    @Published var deepLinkCourse: CourseEntity? = nil

    let scheduleViewModel: ScheduleViewModel

    init(repository: ScheduleRepository) {
        scheduleViewModel = ScheduleViewModel(
            repo: repository,
            onWidgetsNeedReload: { WidgetCenter.shared.reloadAllTimelines() })
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
        } else {
            overlayScreen = nil
            editingCourse = nil
            editTableId = nil
        }
    }

    // ← 新建空表(AllTables / Management 共用)
    func createNewTableThenEdit() {
        let previousId = scheduleViewModel.state.currentTable?.id
        let newId = scheduleViewModel.createEmptyTable(commitSelection: false)
        previousDefaultTableId = previousId
        pendingNewTableId = newId
        editTableId = newId
        overlayScreen = .editTable
    }

    // ← 深链: sleepy://course/<id>
    func handleDeepLinkCourse(_ id: Int64) {
        if deepLinkCourse?.id == id { return }
        let repo = ScheduleRepository(AppDatabase.getShared())
        if let course = try? repo.getCourse(id) {
            deepLinkCourse = course
        }
    }
}

// ← AppRoot composable
struct AppRoot: View {
    @EnvironmentObject var root: AppRootViewModel
    @Environment(\.colorScheme) private var systemScheme
    // ← themeMode/手动切主题联动
    @State private var themeMode: String = AppPrefs.shared.getThemeMode()
    @State private var themeKey: String = AppPrefs.shared.getThemeKey()
    @State private var jwImportActive = false
    // ★ iOS 16 sheet 冲突修复: ImportSheet 关闭动画中直接 present JwImportFlow
    //   会被 SwiftUI 丢弃(同一 runloop 两个 sheet 状态翻转)→ 延到 dismiss 完成。
    @State private var jwImportRequested = false

    var body: some View {
        NavigationStack {
            mainContent
        }
        .modifier(SleepyThemeProvider(darkTheme: isDark, themeKey: themeKey))
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
        .sheet(isPresented: $jwImportActive) {
            JwImportFlow {
                jwImportActive = false
            }
            // Sheet 是独立 presentation tree；显式注入主题，避免自定义颜色环境回落到 lightScheme。
            .modifier(SleepyThemeProvider(darkTheme: isDark, themeKey: themeKey))
            .preferredColorScheme(isDark ? .dark : .light)
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

    @ViewBuilder
    private var mainContent: some View {
        // overlay 屏(← if overlayScreen == ... return 模式)
        if root.overlayScreen == .addCourse || root.editingCourse != nil {
            AddCourseScreen(
                viewModel: root.scheduleViewModel,
                onBack: { root.overlayScreen = nil; root.editingCourse = nil },
                onSaved: { root.overlayScreen = nil; root.editingCourse = nil; root.currentTab = .schedule },
                editingCourse: root.editingCourse)
        } else if root.overlayScreen == .allTables {
            AllTablesScreen(
                viewModel: root.scheduleViewModel,
                onBack: { root.overlayScreen = nil },
                onCreateNewTable: { root.createNewTableThenEdit() },
                onOpenEditTable: { tableId in
                    root.editTableId = tableId
                    root.pendingNewTableId = nil
                    root.overlayScreen = .editTable
                })
        } else if root.overlayScreen == .editTable {
            EditTableScreen(
                viewModel: root.scheduleViewModel,
                tableId: root.editTableId,
                pendingNewTableId: root.pendingNewTableId,
                onBack: { root.handleBack() },
                onDiscardPending: {
                    let discardId = root.pendingNewTableId
                    let fallback = root.previousDefaultTableId
                    root.pendingNewTableId = nil
                    root.previousDefaultTableId = nil
                    if let discardId = discardId {
                        root.scheduleViewModel.discardNewTable(discardId, fallbackId: fallback)
                    }
                    root.overlayScreen = nil
                    root.editTableId = nil
                },
                onSaved: {
                    root.overlayScreen = nil
                    root.editTableId = nil
                    root.pendingNewTableId = nil
                    root.previousDefaultTableId = nil
                },
                onDeleted: {
                    root.overlayScreen = nil
                    root.editTableId = nil
                    root.currentTab = .schedule
                })
        } else if root.overlayScreen == .theme {
            AppearanceScreen(
                onBack: { root.overlayScreen = nil },
                themeMode: themeMode,
                onThemeModeChange: { mode in
                    themeMode = mode
                    themeKey = AppPrefs.shared.getThemeKey()
                })
        } else if root.overlayScreen == .general {
            GeneralSettingsScreen(onBack: { root.overlayScreen = nil })
        } else if root.overlayScreen == .export {
            ExportScreen(viewModel: root.scheduleViewModel, onBack: { root.overlayScreen = nil })
        } else if root.overlayScreen == .reminder {
            ReminderScreen(onBack: { root.overlayScreen = nil })
        } else if root.overlayScreen == .about {
            AboutScreen(onBack: { root.overlayScreen = nil })
        } else {
            tabs
        }
    }

    // ← Scaffold + PillNavigationBar + 4 Tab
    private var tabs: some View {
        VStack(spacing: 0) {
            ZStack {
                switch root.currentTab {
                case .schedule:
                    ScheduleScreen(
                        viewModel: root.scheduleViewModel,
                        onGoImport: { root.currentTab = .manage },
                        onManualAdd: { root.overlayScreen = .addCourse },
                        onEditCourse: { course in root.editingCourse = course })
                case .today:
                    TodayScreen(viewModel: root.scheduleViewModel)
                case .manage:
                    ManagementPage(
                        viewModel: root.scheduleViewModel,
                        autoShowImportSheet: PendingImportText.value != nil,
                        onJwImportRequested: { jwImportRequested = true },
                        onCreateNewTableRequested: { root.createNewTableThenEdit() },
                        onManualAdd: { root.overlayScreen = .addCourse },
                        onEditCurrentTable: {
                            root.editTableId = nil
                            root.pendingNewTableId = nil
                            root.overlayScreen = .editTable
                        },
                        // ★ 导入完成链(← Android onImported: 关导入框+切课表 Tab;
                        //   onOpenEditTable: 新导入表 → 打开表编辑页)
                        onImported: {
                            PendingImportText.value = nil
                            root.currentTab = .schedule
                        },
                        onOpenEditTable: { tableId in
                            PendingImportText.value = nil
                            root.editTableId = tableId
                            root.pendingNewTableId = nil
                            root.overlayScreen = .editTable
                        })
                case .mine:
                    MineScreen(
                        viewModel: root.scheduleViewModel,
                        onOpenAllTables: { root.overlayScreen = .allTables },
                        onOpenAppearance: { root.overlayScreen = .theme },
                        onOpenGeneral: { root.overlayScreen = .general },
                        onOpenExport: { root.overlayScreen = .export },
                        onOpenReminder: { root.overlayScreen = .reminder },
                        onOpenAbout: { root.overlayScreen = .about })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // PillNavigationBar(← Scaffold.bottomBar)
            PillNavigationBar(items: [
                PillNavItemData(id: "schedule", icon: "calendar", label: L10n.format("tab_schedule"),
                                selected: root.currentTab == .schedule) { root.currentTab = .schedule },
                PillNavItemData(id: "today", icon: "doc.on.doc", label: L10n.format("tab_today"),
                                selected: root.currentTab == .today) { root.currentTab = .today },
                PillNavItemData(id: "manage", icon: "gearshape", label: L10n.format("tab_manage"),
                                selected: root.currentTab == .manage) { root.currentTab = .manage },
                PillNavItemData(id: "mine", icon: "person", label: L10n.format("tab_mine"),
                                selected: root.currentTab == .mine) { root.currentTab = .mine },
            ])
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
