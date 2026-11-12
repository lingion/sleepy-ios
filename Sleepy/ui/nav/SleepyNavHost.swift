// SleepyNavHost — 原版本 SleepyNavHost.kt → iOS 文档式对齐文件.
//
// 原版本 侧: Composable NavHost — 每个 SleepyRoute 对应一个页面 composable,
// 按路由类型挂 BackHandler (EditTable pendingNew 丢弃兜底; PeriodEdit 未保存新期丢弃),
// MainRoute 双击返回 2s 内退 App, 平板 master-detail 分栏.
//
// iOS 侧无 Composable NavHost 等价物 — 导航由既有构件承担, 本文件只固化
// "谁驱动什么"的映射, 让路由表 (SleepyRoutes) 与导航实现可审计对应:
//
//   原版本 构件                  →  iOS 承接
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
// 每路由返回不变量 (与 原版本 BackHandler 契约一致):
//   • EditTable + pendingNew: 返回/侧滑 → 丢弃新表, 回退到 previousDefault (handleBack 已实现)
//   • 已落地路由: pushOverlay 记录来源, 返回弹出当前页并恢复父 overlay
//   • 连续同路由去重由单值语义天然保证 (无二次 push)

import SwiftUI

/// 自绘 tab / 平板右栏的内容宿主；原生 TabView 保留系统转场。
/// id 仅随路由变化，重算 body 不重置页面。宿主不裁切弹簧略微超出的内容。
struct SleepyNavigationContent<Key: Hashable, Page: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let selection: Key
    @ViewBuilder var page: (Key) -> Page

    var body: some View {
        let motion = SleepyMotionPolicy(reduceMotion: reduceMotion)
        ZStack {
            page(selection)
                .id(selection)
                .transition(motion.content)
        }
        .animation(motion.defaultEffects, value: selection)
    }
}

/// 覆盖层下面的目标页保持树身份；push 退场，pop 重新缩放淡入。
/// 必须由 PresentOverlay 的 shownScreen 驱动，而不是先变化的外部 route。
struct SleepyNavigationUnderlay: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let covered: Bool

    func body(content: Content) -> some View {
        let motion = SleepyMotionPolicy(reduceMotion: reduceMotion)
        content
            .scaleEffect(covered ? motion.contentScale : 1)
            .animation(motion.defaultSpatial, value: covered)
            .opacity(covered ? 0 : 1)
            .animation(motion.defaultEffects, value: covered)
            .allowsHitTesting(!covered)
            .disabled(covered)
            .accessibilityHidden(covered)
    }
}

/// A full-screen child page that keeps its source view and input state alive.
/// Import methods and manual editors are Android navigation entries, rather than
/// modal sheets. Only their presentation changes; their data sessions stay local.
private struct SleepyNavigationPage<Item: Identifiable, Page: View, Canvas: View>: ViewModifier {
    @Binding var item: Item?
    let onDismiss: () -> Void
    @ViewBuilder var canvas: () -> Canvas
    @ViewBuilder var page: (Item) -> Page
    @State private var shownItem: Item?
    @State private var dragX: CGFloat = 0
    @State private var dismissal: UUID?
    @State private var childPageIsPresented = false

    func body(content: Content) -> some View {
        ZStack {
            content.modifier(SleepyNavigationUnderlay(covered: shownItem != nil))
            if let shownItem {
                page(shownItem)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(canvas())
                    .offset(x: dragX)
                    .onPreferenceChange(SleepyChildPageKey.self) { childPageIsPresented = $0 }
                    .edgeBackGesture(dragX: $dragX, enabled: !childPageIsPresented, onBack: { item = nil },
                                     onCommit: { action in action() })
                    .id(shownItem.id)
                    .transition(SleepyMaterialTransition.forwardTransform)
                    .zIndex(1)
            }
        }
        .background(canvas())
        .onAppear { shownItem = item }
        .onChange(of: item?.id) { _ in syncPresentation() }
        .preference(key: SleepyChildPageKey.self, value: shownItem != nil)
    }

    private func syncPresentation() {
        if let item {
            dismissal = nil
            dragX = 0
            withAnimation(SleepyMaterialTransition.forwardAnimation) { shownItem = item }
        } else if shownItem != nil {
            let ticket = UUID()
            dismissal = ticket
            withAnimation(SleepyMaterialTransition.forwardAnimation) { shownItem = nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + SleepyMaterialTransition.forwardDuration) {
                guard dismissal == ticket, self.item == nil, shownItem == nil else { return }
                dismissal = nil
                dragX = 0
                onDismiss()
            }
        }
    }
}

private struct SleepyChildPageKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

private struct SleepyNavigationPageToken: Identifiable {
    let id = 0
}

extension View {
    func sleepyNavigationPage<Item: Identifiable, Page: View, Canvas: View>(
        item: Binding<Item?>, onDismiss: @escaping () -> Void = {},
        @ViewBuilder canvas: @escaping () -> Canvas,
        @ViewBuilder content: @escaping (Item) -> Page
    ) -> some View {
        modifier(SleepyNavigationPage(item: item, onDismiss: onDismiss, canvas: canvas, page: content))
    }

    func sleepyNavigationPage<Page: View, Canvas: View>(
        isPresented: Binding<Bool>, onDismiss: @escaping () -> Void = {},
        @ViewBuilder canvas: @escaping () -> Canvas,
        @ViewBuilder content: @escaping () -> Page
    ) -> some View {
        sleepyNavigationPage(item: Binding(
            get: { isPresented.wrappedValue ? SleepyNavigationPageToken() : nil },
            set: { isPresented.wrappedValue = $0 != nil }), onDismiss: onDismiss,
            canvas: canvas, content: { _ in content() })
    }
}

extension AppRootViewModel {
    /// 路由 → iOS 导航态 单点入口 (原版本 SleepyNavigator.openXxx 的 VM 直驱版).
    /// 未落地路由在此集中留痕, 避免散落的 no-op.
    @discardableResult
    func navigate(to route: SleepyRoute) -> Bool {
        guard route.isIOSPorted else { return false }
        switch route {
        case .main:
            break
        case .addCourse:
            initialCourseSlot = nil
            pushOverlay(.addCourse)
        case .allTables:
            pushOverlay(.allTables)
        case .editTable(let tableId, let pendingNew, let prevDefault):
            editTableId = (tableId == SleepyRoute.NO_ID) ? nil : tableId
            pendingNewTableId = (pendingNew == SleepyRoute.NO_ID) ? nil : pendingNew
            previousDefaultTableId = (prevDefault == SleepyRoute.NO_ID) ? nil : prevDefault
            pushOverlay(.editTable)
        case .appearance:
            pushOverlay(.theme)
        case .scheduleDisplay:
            pushOverlay(.scheduleDisplay)
        case .general:
            pushOverlay(.general)
        case .export:
            pushOverlay(.export)
        case .reminder:
            pushOverlay(.reminder)
        case .about:
            pushOverlay(.about)
        case .license:
            pushOverlay(.license)
        case .courseList:
            pushOverlay(.courseList)
        case .periodTables:
            pushOverlay(.periodTables)
        case .periodEdit(let periodId, let isNew):
            // 绑定 = 生产 onOpenPeriodEdit 同式 (SleepyApp PresentOverlay 接线) —
            // facade 桥接收编于此, 单一真源恢复。
            periodEditId = periodId
            pendingNewPeriodTableId = isNew ? periodId : nil
            pushOverlay(.periodEdit)
        case .periodHeaderSettings:
            pushOverlay(.periodHeaderSettings)
        default:
            return false
        }
        return true
    }
}
