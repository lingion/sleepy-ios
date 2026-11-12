// WidgetManagementScreen.swift — ← ui/screen/widget/WidgetManagementScreen.kt
// 列出桌面上已放置的 Sleepy 小组件,点击行进入 WidgetEditScreen 选该组件呈现的课表。
// 空态文案引导去系统桌面添加(添加动作完全在 launcher,App 内无法代劳)。
//
// v1.0.62 B4 (+34 对齐): ①标题栏右上「＋」进 WidgetGallery 画廊页直接添加;
//   ②画廊 pin/编辑绑定后回本页重扫已放置实例(原版本 ON_RESUME 重扫同义);
//   ③空态文案改 widget_manage_empty_v2(引导右上「＋」)。
//
// ★ 平台差异(差异表#8 附注): 原版本 用 AppWidgetManager.getAppWidgetIds 枚举 10 个
//   receiver 变体的已放置实例;iOS 等价物 = WidgetCenter.getCurrentConfigurations(),
//   返回的 WidgetInfo 只有 kind + family,无稳定实例 ID → 行键 = kind+family,
//   同 kind 的多实例显示为相同行(粒度上限即 per-kind,见 WidgetBindingStore.swift 头注)。

import SwiftUI
import WidgetKit

// ← PlacedWidgetItem — 原版本 1:1, 实例 ID 换成 kind(平台差异表#8)
struct PlacedWidgetItem: Identifiable {
    let kind: String
    let family: WidgetFamily
    let tableName: String?
    var id: String { kind + "|" + family.description }
    // ← variant.displayNameRes — kind → 既有 widget 标签键 (WidgetVariantInfo.kt 顺序)
    var displayName: String {
        allWidgetVariants.first { $0.kind == kind }.map { L10n.format($0.displayNameKey) } ?? kind
    }
}

// ← WidgetManagementViewModel.reload 的取数序列(AppWidgetManager 枚举 + 绑定表名)。
//   async 形态 iOS 16+, 部署目标 15.6 → completion API + withCheckedContinuation。
//   v1.0.62 B4: internal 化 — WidgetSettingsScreen 页尾「刷新所有小组件」按钮的
//   存在条件与「添加或管理」列表同一条数据源(单一真源, 零新通路)。
func loadPlacedWidgets() async -> [PlacedWidgetItem] {
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("-SLEEPY_UI_TEST_SEED"), arguments.contains("-SLEEPY_UI_TEST_PLACED_WIDGETS") {
        // Only the host's installed-widget list is injected. Rows, editors,
        // bindings, settings stores, loaders and preview views remain production code.
        return WeekGridWideMode.allCases.map {
            PlacedWidgetItem(kind: $0.widgetKind, family: .systemMedium, tableName: nil)
        }
    }
    guard let repo = WidgetLoader.makeRepo() else {
        return []
    }
    let infos: [WidgetInfo] = await withCheckedContinuation { cont in
        WidgetCenter.shared.getCurrentConfigurations { result in
            cont.resume(returning: (try? result.get()) ?? [])
        }
    }
    let knownKinds = Set(allWidgetVariants.map(\.kind))
    return infos.filter { knownKinds.contains($0.kind) }.map { info in
        PlacedWidgetItem(
            kind: info.kind,
            family: info.family,
            // ← tableName = 绑定表名,nil = 跟随默认(widget_edit_default_label)
            tableName: WidgetBindingStore.resolveBoundTable(info.kind, repo: repo)?.name
        )
    }
}

struct WidgetManagementScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var uiStyle
    @Environment(\.scenePhase) private var scenePhase
    let onDismiss: () -> Void
    var loadItems: () async -> [PlacedWidgetItem] = loadPlacedWidgets

    // ← vm.state (WidgetManagementViewModel)
    @State private var items: [PlacedWidgetItem] = []
    // 点击行 → 编辑页(等价 原版本 onSelect(id) 导航)
    @State private var editTarget: PlacedWidgetItem? = nil
    // v1.0.62 B4: 标题栏右上「＋」进画廊页直接添加(设计 §3)
    @State private var showGallery = false

    var body: some View {
        VStack(spacing: 0) {
            // ← TopAppBar + actions{ IconButton(Add) }: 48pt触控槽与 Android 同源。
            SettingsTopBar(title: L10n.format("widget_manage_title"), onBack: onDismiss)
                .overlay(alignment: .trailing) {
                    Button(action: { showGallery = true }) {
                        AndroidMaterialIcon(name: .add, size: 24)   // ← 原 Icon 默认 24dp
                            .frame(width: uiStyle == .classic ? 48 : nil, height: uiStyle == .classic ? 48 : nil)
                            .foregroundColor(colors.onBackground)
                    }
                    .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 20, compact: true, shape: .circle))
                    .frame(width: 48, height: 48)
                    .accessibilityIdentifier("widget_gallery_add")
                    .accessibilityLabel(L10n.format("widget_gallery_title"))
                    .padding(.trailing, 4)   // ← TopAppBarHorizontalPadding 4dp
                }
            if items.isEmpty {
                VStack(spacing: 16) {
                    Text(L10n.format("widget_manage_empty_v2"))
                        .font(.system(size: 16))
                        .foregroundColor(colors.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                    Button { showGallery = true } label: {
                        Text(L10n.format("widget_gallery_title"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.onSecondaryContainer)
                            .padding(.horizontal, 24)
                            .frame(height: uiStyle == .liquidGlass ? nil : 40)
                            .sleepyControlSurface(cornerRadius: SleepyShapes.large,
                                                  tint: colors.secondaryContainer, prominent: true)
                    }
                    .buttonStyle(SleepyPlatformButtonStyle(prominent: true, cornerRadius: SleepyShapes.large))
                    .frame(minHeight: 40)
                    .tint(colors.secondaryContainer)
                    .accessibilityIdentifier("widget_empty_gallery")
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { item in
                            PlacedWidgetRow(item: item) { editTarget = item }
                        }
                    }
                    .padding(.horizontal, 16)
                    // ← 原版本 WidgetManagementScreen.kt L97 仅 horizontal 16, 无纵向 padding
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(colors.background)
        .task { items = await loadItems() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { items = await loadItems() }
            }
        }
        // ← onSelect(widgetId) 导航: fullScreenCover 叠放(manage → edit 两级)
        .fullScreenCover(item: $editTarget) { target in
            // ← family 透传 (设计 §6): 编辑页族门控 (滚动/三天窗口节) 依据
            WidgetEditScreen(kind: target.kind, family: target.family,
                             onDismiss: {
                                 editTarget = nil
                                 // ← 原版本 ON_RESUME 重扫: 编辑绑定改课后回列表重扫
                                 Task { items = await loadItems() }
                             })
        }
        // v1.0.62 B4: 右上「＋」→ 画廊页(第三级叠放)
        .fullScreenCover(isPresented: $showGallery) {
            WidgetGalleryScreen(onDismiss: {
                showGallery = false
                // ← 画廊 pin → 返回本页: 重扫已放置实例(单一真源 = WidgetCenter),
                //    新卡片即时可见, 无需手动刷新(原版本 ON_RESUME 重扫同义)
                Task { items = await loadItems() }
            })
        }
    }
}

// ← v1.0.63 Material3 1.5.0-beta02 默认 Card: surfaceContainerHighest + medium(12), padding 12dp
private struct PlacedWidgetRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let item: PlacedWidgetItem
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack {
                // ← 原版本 PlacedWidgetRow L123 Column 无 verticalArrangement → 间距 0
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.displayName)
                        .font(.system(size: 16))
                        .foregroundColor(colors.onSurface)
                    // ← tableName ?: widget_edit_default_label
                    Text(item.tableName ?? L10n.format("widget_edit_default_label"))
                        .font(.system(size: 14))
                        .foregroundColor(colors.onSurfaceVariant)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surfaceContainerHighest)
            .cornerRadius(SleepyShapes.medium)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("widget_manage_row_\(item.kind)")
    }
}
