// SleepyNavHost — Android SleepyNavHost.kt → iOS 文档式对齐文件.
//
// Android 侧: Composable NavHost — 每个 SleepyRoute 对应一个页面 composable,
// 按路由类型挂 BackHandler (EditTable pendingNew 丢弃兜底; PeriodEdit 未保存新期丢弃),
// MainRoute 双击返回 2s 内退 App, 平板 master-detail 分栏.
//
// iOS 侧无 Composable NavHost 等价物 — 导航由既有构件承担, 本文件只固化
// "谁驱动什么"的映射, 让路由表 (SleepyRoutes) 与导航实现可审计对应:
//
//   Android 构件                  →  iOS 承接
//   ─────────────────────────────────────────────────────────────────
//   NavHost (composable 分发表)   →  AppRoot.content + PresentOverlay.overlayContent
//                                     (SleepyApp.swift; 按 OverlayScreen 分发页面)
//   每路由 BackHandler            →  AppRootViewModel.handleBack()
//                                     (EditTable pendingNew 丢弃链 + fallback)
//                                     + PresentOverlay 跟手侧滑 dismiss
//   MainRoute 双击返回 2s 退 App  →  iOS 原生: 无应用级退出键 (store policy), 记录 no-analog
//   平板 master-detail 分栏       →  无 iOS 等价 (iPad 走全屏 overlay), 记录 no-analog
//
// 路由 ↔ OverlayScreen 映射总表 (unported 行 = 尚无 iOS 页面, 🚫silent skip,
// 各由对应功能切片落地后回填):
//
//   SleepyRoute              iOS OverlayScreen / 承载
//   ──────────────────────────────────────────────────────
//   Main                    — (根 tab 栏: currentTab)
//   AddCourse               .addCourse
//   AllTables               .allTables
//   CourseList              .courseList
//   EditTable               .editTable (editTableId/pendingNew/prevDefault 参数在 VM)
//   Appearance              .theme
//   PeriodHeaderSettings    .periodHeaderSettings
//   General                 .general
//   Holiday                 内嵌 GeneralSettingsScreen sheet (by design, 不出现在根 enum)
//   Export                  .export
//   Reminder                .reminder
//   About                   .about
//   License                 .license
//   WidgetManagement        内嵌 GeneralSettingsScreen sheet (by design)
//   WidgetEdit              内嵌 WidgetManagementScreen→GeneralSettings 链 (by design)
//   PeriodTables            .periodTables
//   PeriodEdit              .periodEdit (periodEditId/pendingNewPeriodTableId 参数在 VM)
//
// 每路由返回不变量 (与 Android BackHandler 契约一致):
//   • EditTable + pendingNew: 返回/侧滑 → 丢弃新表, 回退到 previousDefault (handleBack 已实现)
//   • 已落地路由: 单值 overlay, 返回 = overlayScreen = nil, 无栈深
//   • 连续同路由去重由单值语义天然保证 (无二次 push)

import SwiftUI

extension AppRootViewModel {
    /// 路由 → iOS 导航态 单点入口 (Android SleepyNavigator.openXxx 的 VM 直驱版).
    /// 未落地路由在此集中留痕, 避免散落的 no-op.
    @discardableResult
    func navigate(to route: SleepyRoute) -> Bool {
        guard route.isIOSPorted else { return false }
        switch route {
        case .main:
            break
        case .addCourse:
            overlayScreen = .addCourse
        case .allTables:
            overlayScreen = .allTables
        case .editTable(let tableId, let pendingNew, let prevDefault):
            editTableId = (tableId == SleepyRoute.NO_ID) ? nil : tableId
            pendingNewTableId = (pendingNew == SleepyRoute.NO_ID) ? nil : pendingNew
            previousDefaultTableId = (prevDefault == SleepyRoute.NO_ID) ? nil : prevDefault
            overlayScreen = .editTable
        case .appearance:
            overlayScreen = .theme
        case .general:
            overlayScreen = .general
        case .export:
            overlayScreen = .export
        case .reminder:
            overlayScreen = .reminder
        case .about:
            overlayScreen = .about
        case .license:
            overlayScreen = .license
        case .courseList:
            overlayScreen = .courseList
        case .periodTables:
            overlayScreen = .periodTables
        case .periodEdit(let periodId, let isNew):
            // 绑定 = 生产 onOpenPeriodEdit 同式 (SleepyApp PresentOverlay 接线) —
            // facade 桥接收编于此, 单一真源恢复。
            periodEditId = periodId
            pendingNewPeriodTableId = isNew ? periodId : nil
            overlayScreen = .periodEdit
        case .periodHeaderSettings:
            overlayScreen = .periodHeaderSettings
        default:
            return false
        }
        return true
    }
}
