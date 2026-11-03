import Foundation

// SleepyRoutes — 原版本 SleepyRoutes.kt (NavHost 路由表) → iOS 等价路由表.
//
// 原版本 侧: 23 个 case 的 sealed `SleepyRoute : NavKey` 驱动 Compose Navigation.
// iOS 侧导航由 AppRootViewModel.currentTab + .overlayScreen (SleepyApp.PresentOverlay
// 跟手侧滑容器) 驱动, 本文件保留同一套 17 个 case 名称 + 参数语义作为"路由表真源",
// 并附 路由 → iOS 导航态 映射表 (recon.md 平台映射: NavigationStack 自有路由枚举,
// 不引入第三方导航库).
// Long 参数在 iOS 侧统一 Int64 (对齐 AppRootViewModel.editTableId: Int64?).

enum SleepyRoute: Equatable {
    case main
    case addCourse(courseId: Int64 = SleepyRoute.NO_ID, editing: Bool = false)
    case allTables
    case courseList
    case editTable(tableId: Int64 = SleepyRoute.NO_ID, pendingNew: Int64 = SleepyRoute.NO_ID, prevDefault: Int64 = SleepyRoute.NO_ID)
    case appearance
    case periodHeaderSettings
    case general
    case holiday
    case export
    case reminder
    case about
    case license
    case widgetManagement
    case widgetSettings
    case widgetGallery
    case widgetEdit(widgetId: Int)
    case periodTables
    case periodEdit(periodId: Int64, isNew: Bool = false)
}

extension SleepyRoute {
    /// 原版本 SleepyRoute.NO_ID 常量 1:1 (-1L → Int64).
    static let NO_ID: Int64 = -1

    /// 路由 → iOS 导航态映射 (AppRootViewModel: Tab + OverlayScreen).
    /// nil 有两种语义: .main = 根 tab 栏无 overlay; holiday/widget* = 内嵌 sheet 链
    /// 无根 overlay 承载 (平台忠实映射, by design). 各自注释留痕, 🚫silent skip.
    var iosNavigation: AppRootViewModel.OverlayScreen? {
        switch self {
        case .main:
            return nil // 根 tab 栏
        case .addCourse:
            return .addCourse
        case .allTables:
            return .allTables
        case .editTable:
            return .editTable
        case .appearance:
            return .theme
        case .general:
            return .general
        case .export:
            return .export
        case .reminder:
            return .reminder
        case .about:
            return .about
        case .license:
            return .license
        // 1.0.61 屏已落地 (OverlayScreen 已有对应 case, 见 SleepyApp.swift):
        case .courseList:
            return .courseList
        case .periodTables:
            return .periodTables
        case .periodEdit:
            return .periodEdit
        case .periodHeaderSettings:
            return .periodHeaderSettings
        // 以下无根 overlay 承载 = 平台忠实映射, by design (非缺口):
        //   holiday 内嵌 GeneralSettings 内部 sheet;
        //   v1.0.62 B4: widgetSettings/widgetGallery 内嵌 MineScreen→WidgetSettings
        //   →WidgetManagement→WidgetGallery cover 链(与 holiday/widgetManagement 同款惯例)。
        case .holiday: return nil
        case .widgetManagement: return nil
        case .widgetSettings: return nil
        case .widgetGallery: return nil
        case .widgetEdit: return nil
        }
    }

    /// 是否已有 iOS 页面承接 (SleepyNavigator facade 放行条件).
    /// 1.0.61 新放行: .courseList / .periodTables / .periodEdit / .periodHeaderSettings
    /// (屏均已落地, OverlayScreen 有对应 case); holiday / widgetManagement / widgetEdit
    /// / widgetSettings / widgetGallery 保持未放行 = 内嵌 sheet 链, 无根 overlay 路由
    /// (by design, 非缺口).
    var isIOSPorted: Bool {
        switch self {
        case .addCourse, .allTables, .editTable, .appearance,
             .general, .export, .reminder, .about, .license,
             .courseList, .periodTables, .periodEdit, .periodHeaderSettings:
            return true
        default:
            return false
        }
    }
}
