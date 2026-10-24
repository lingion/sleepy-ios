// WidgetEditScreen.swift — ← ui/screen/widget/WidgetEditScreen.kt
//   + WidgetEditSection.kt + WidgetEditScheduleSection.kt (三文件合一, 职责分区注释保留)。
// 逐 widget 编辑页: 选这个小组件呈现哪张课表。改绑定写 WidgetBindingStore 并触发
// WidgetCenter.reloadAllTimelines (← WidgetUpdater.notifyDataChanged), 桌面即时重绘。
//
// 平台差异(差异表#8): Android widgetId:Int → iOS kind:String (粒度 per-kind,
// 见 WidgetBindingStore.swift 头注); section 扩展点等价物见下方注释块。

import SwiftUI
import WidgetKit

// ← WidgetEditScope: 传给每个 section 的状态 + 选择回调 (tableId nil = 清绑定回默认)
//   issue#26: useAlias/onUseAliasChange — widget 场景 课程名显示 原名/别名 (全局一档);
//   默认参数兜底, 旧构造点(未传)不破编译。
//   设计 §6 (v1.0.60 对齐): receiverSimpleName → iOS 无 receiver, 等价族信息 =
//   WidgetKit family (小/中/大); scrollEnabled / compactTodayFirst — per-kind 一档
//   (差异表#8: Android per-widgetId → iOS per-kind)。
struct WidgetEditScope {
    let kind: String
    let currentBinding: Int64?
    let availableTables: [TimeTableEntity]
    let onSelectTable: (Int64?) -> Void
    var useAlias: Bool = false
    var onUseAliasChange: (Bool) -> Void = { _ in }
    // ← 设计 §6: family = 族判断依据(系统小=Android「· 小」变体); nil = 未知
    var family: WidgetFamily? = nil
    // ← 强制滚动(实验) — 本 kind 一档, 默认 false = FIXED 固定窗口
    var scrollEnabled: Bool = false
    var onScrollEnabledChange: (Bool) -> Void = { _ in }
    // ← 最小档三天窗口 — 本 kind 一档 (仅系统小 family 显示); true = 今日居第一位
    var compactTodayFirst: Bool = true
    var onCompactTodayFirstChange: (Bool) -> Void = { _ in }
}

// ← WidgetEditSection.kt 的协议扩展点在 SwiftUI 下不成立(existential View 不能做
//   ForEach 内容, Xcode14/Swift5.8)。等价扩展点 = 本文件直接加同级 section struct +
//   WidgetEditScreen.sections 里加一项 — 与 Android "新文件+列表加一项" 同构。
//   当前两节 (WidgetEditScheduleSection + WidgetEditAliasSection), 保持直连组合。

// ← WidgetEditViewModel.reload / setBinding / setUseAlias 的取数与落库序列:
//   availableTables = 有课的表 (← WidgetEditCore.filterAvailableTables, 保序)
//   currentBinding = WidgetEditCore.displayBinding(WidgetBindingStore.get(kind))
//   (← vm.reload L72-74: 首装哨兵 0/非正值 → nil = 「默认」行选中, 非「无选中」);
//   选择回调写库 + WidgetCenter 通知。
//   useAlias = AppPrefs.isWidgetUseAlias; 切换回调写库(set 内已刷 timeline)。
func makeWidgetEditScope(kind: String,
                         family: WidgetFamily? = nil,
                         onSelect: @escaping (Int64?) -> Void,
                         onUseAliasChange: @escaping (Bool) -> Void = { _ in },
                         onScrollEnabledChange: @escaping (Bool) -> Void = { _ in },
                         onCompactTodayFirstChange: @escaping (Bool) -> Void = { _ in }) -> WidgetEditScope {
    let repo = WidgetLoader.makeRepo()
    let all = repo.map { (try? $0.getAllTables()) ?? [] } ?? []
    var available: [TimeTableEntity] = []
    for table in all {
        let count = ((try? repo?.getCourses(table.id)) ?? []).count
        if count > 0 {
            available.append(table)
        }
    }
    return WidgetEditScope(
        kind: kind,
        currentBinding: WidgetEditCore.displayBinding(WidgetBindingStore.get(kind)),
        availableTables: available,
        onSelectTable: onSelect,
        useAlias: AppPrefs.shared.isWidgetUseAlias(),
        onUseAliasChange: onUseAliasChange,
        family: family,
        // ← 迁移语义: 显式值 ?: 旧全局 — 显式值由 per-kind store 持有, 旧全局
        //   走 AppPrefs (compact 默认 true, scroll 默认 false, 与 Android 一致)。
        //   三天窗口 (WidgetCompactWindow.swift) + 滚动 (WidgetScrollStore.swift)
        //   已在 v1.0.60 落位, 本节仅接 store 接口。
        scrollEnabled: WidgetScrollStore.isScrollEnabled(kind: kind),
        onScrollEnabledChange: onScrollEnabledChange,
        compactTodayFirst: WidgetCompactWindowStore.isTodayFirst(kind),
        onCompactTodayFirstChange: onCompactTodayFirstChange
    )
}

func applyWidgetBinding(kind: String, tableId: Int64?) {
    if let id = tableId {
        WidgetBindingStore.put(kind, tableId: id)
    } else {
        WidgetBindingStore.remove(kind)
    }
    WidgetCenter.shared.reloadAllTimelines()
}

struct WidgetEditScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let kind: String
    // ← 设计 §6: family(系统小/中/大) = Android receiverSimpleName 的 iOS 等价族信息,
    //   由管理页 WidgetInfo.family 传入 (nil = 未知, 族门控节按各自规则处理)
    var family: WidgetFamily? = nil
    let onDismiss: () -> Void

    // ← state: currentBinding + availableTables (选完 reload, 选中态即时切换)
    @State private var scope: WidgetEditScope?

    // ← sections: 后续 per-widget 见本文件头注 (SwiftUI 扩展点等价物)
    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("widget_edit_title"), onBack: onDismiss)
            ScrollView {
                LazyVStack(spacing: 16) {
                    if let s = scope {
                        // ← Android WidgetEditScreen.kt L52 sections 列表 1:1:
                        //   Schedule / Alias / Scroll / CompactWindow
                        WidgetEditScheduleSection(scope: s)
                        WidgetEditAliasSection(scope: s)
                        WidgetEditScrollSection(scope: s)
                        WidgetEditCompactWindowSection(scope: s)
                    }
                }
                .padding(.horizontal, 16)
                // ← Android WidgetEditScreen.kt L92 仅 horizontal 16, 无纵向 padding
            }
        }
        .background(colors.background)
        .onAppear {
            reloadScope()
        }
    }

    // ← vm.reload(): 选完/切完重读 scope, 选中态即时切换 — 全部回调同走"写库 + 重读"管线
    private func reloadScope() {
        scope = makeWidgetEditScope(
            kind: kind,
            family: family,
            onSelect: { tableId in
                applyWidgetBinding(kind: kind, tableId: tableId)
                reloadScope()
            },
            onUseAliasChange: { v in
                // ← vm.setUseAlias: 写 AppPrefs(内部已 WidgetCenter 全量刷) + reload
                AppPrefs.shared.setWidgetUseAlias(v)
                reloadScope()
            },
            onScrollEnabledChange: { v in
                // ← vm.setScrollEnabled: 写 per-kind store + reload + 全量重推
                //   (评审 #25: 否则「看着没生效」)
                WidgetScrollStore.setScrollEnabled(kind: kind, enabled: v)
                WidgetCenter.shared.reloadAllTimelines()
                reloadScope()
            },
            onCompactTodayFirstChange: { v in
                // ← vm.setCompactTodayFirst: 与 setScrollEnabled 同管线
                WidgetCompactWindowStore.setTodayFirst(kind, v)
                WidgetCenter.shared.reloadAllTimelines()
                reloadScope()
            }
        )
    }
}

// ← WidgetEditScheduleSection: "呈现的课表" 分区。
//   选中态 = primaryContainer 色块 + Check 图标 (ui-blocks-no-border-rule, 无描边)。
//   空表已被过滤 — 永不给用户绑到会渲染"请先创建课表"的表。
private struct WidgetEditScheduleSection: View {
    @Environment(\.localWakeUpColors) private var colors
    let scope: WidgetEditScope

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.format("widget_edit_section_schedule"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colors.onSurface)
            Spacer().frame(height: 8)
            // ← Surface(shape 16dp, surfaceContainer): 纵向 padding 4dp + 行列
            VStack(spacing: 0) {
                sectionRow(
                    label: L10n.format("widget_edit_default_label"),
                    selected: scope.currentBinding == nil,
                    checkSpacer: false // ← Android DefaultRow 无 Spacer(8), 仅 TableRow 有
                ) {
                    scope.onSelectTable(nil)
                }
                ForEach(scope.availableTables) { table in
                    sectionRow(
                        label: table.name,
                        selected: scope.currentBinding == table.id
                    ) {
                        scope.onSelectTable(table.id)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(colors.surfaceContainer)
            .cornerRadius(16)
        }
    }

    // ← DefaultRow / TableRow (合一, checkSpacer 区分: Default 无 Spacer(8), Table 有):
    //   bodyLarge 16 + Check primary
    private func sectionRow(label: String, selected: Bool, checkSpacer: Bool = true,
                            onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack {
                Text(label)
                    .font(.system(size: 16))
                    .foregroundColor(colors.onSurface)
                Spacer()
                if selected {
                    if checkSpacer {
                        Spacer().frame(width: 8)
                    }
                    Image(systemName: "checkmark")
                        // ← Android Check 无 size 修饰符 = 默认 24dp (ScheduleSection L91/L121, AliasSection L91)
                        .font(.system(size: 24))
                        .foregroundColor(colors.primary)
                        .accessibilityLabel(L10n.format("selected"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(selected ? colors.primaryContainer : colors.surfaceContainer)
        }
        .buttonStyle(SleepyButtonStyle())
    }
}

// ← WidgetEditAliasSection (issue#26): "课程名显示" 分区 — 原名/别名 全局一档,
//   所有小组件共享同一开关(渲染器无 widgetId, 读 AppPrefs — 与 colorless/separator 同先例)。
//   选中态 = primaryContainer 色块 + Check 图标 (ui-blocks-no-border-rule, 无描边),
//   与 WidgetEditScheduleSection.sectionRow 同模式。
private struct WidgetEditAliasSection: View {
    @Environment(\.localWakeUpColors) private var colors
    let scope: WidgetEditScope

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.format("widget_edit_section_alias"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colors.onSurface)
            Spacer().frame(height: 8)
            // ← Surface(shape 16dp, surfaceContainer): 纵向 padding 4dp + 两行 optionRow
            VStack(spacing: 0) {
                optionRow(
                    label: L10n.format("settings_name_original"),
                    selected: !scope.useAlias
                ) {
                    scope.onUseAliasChange(false)
                }
                optionRow(
                    label: L10n.format("settings_name_alias"),
                    selected: scope.useAlias
                ) {
                    scope.onUseAliasChange(true)
                }
            }
            .padding(.vertical, 4)
            .background(colors.surfaceContainer)
            .cornerRadius(16)
        }
    }

    // ← OptionRow: bodyLarge 16 + Check 24 primary (Android AliasSection L89-95
    //   选中态直接放 Icon, 无 Spacer(8) — 同 DefaultRow), 选中 primaryContainer 底, padding 16×14
    private func optionRow(label: String, selected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack {
                Text(label)
                    .font(.system(size: 16))
                    .foregroundColor(colors.onSurface)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24))
                        .foregroundColor(colors.primary)
                        .accessibilityLabel(L10n.format("selected"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(selected ? colors.primaryContainer : colors.surfaceContainer)
        }
        .buttonStyle(SleepyButtonStyle())
    }
}

// ← WidgetEditScrollSection (设计 §6): "滚动方式" 分区 — 强制滚动(实验) 本 kind 一档。
//   出厂默认关 = FIXED 固定窗口; 开启前确认弹窗如实告知厂商 ROM 风险, 取消即回弹
//   (不写入); 关闭无需确认。
//   ★ iOS 平台差异: Android 该节依赖厂商 ROM 的 RemoteViews 滚动服务; WidgetKit
//     无逐帧滚动条带, 但保留本节与存储 (WidgetKit 列表型 timeline 语义上的"滚动"),
//     族门控同 Android: WeekGrid 族隐藏(网格无滚动形态), 未知(nil)按显示处理。
private struct WidgetEditScrollSection: View {
    @Environment(\.localWakeUpColors) private var colors
    let scope: WidgetEditScope
    @State private var showConfirm = false

    // ← 族注入 (评审 #15): WeekGrid 族隐藏; 未知(nil)按显示处理
    private var isWeekGridFamily: Bool {
        scope.kind.contains("WeekGrid")
    }

    var body: some View {
        if !isWeekGridFamily {
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.format("widget_edit_section_scroll"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colors.onSurface)
                Spacer().frame(height: 8)
                VStack(spacing: 0) {
                    Button {
                        // ← 行点击与 Switch 同逻辑: 已开 → 直接关; 未开 → 确认弹窗
                        if scope.scrollEnabled {
                            scope.onScrollEnabledChange(false)
                        } else {
                            showConfirm = true
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(L10n.format("widget_scroll_dialog_title"))
                                    .font(.system(size: 16))
                                    .foregroundColor(colors.onSurface)
                                Text(L10n.format("widget_edit_scroll_subtitle"))
                                    .font(.system(size: 12))
                                    .foregroundColor(colors.onSurfaceVariant)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { scope.scrollEnabled },
                                set: { on in
                                    if on { showConfirm = true }
                                    else { scope.onScrollEnabledChange(false) }
                                }))
                                .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(SleepyButtonStyle())
                }
                .background(colors.surfaceContainer)
                .cornerRadius(16)
            }
            .alert(L10n.format("widget_scroll_dialog_title"), isPresented: $showConfirm) {
                // 2026-09-16 用户: 裸 TextButton 无边界无色块 — 平台差异:
                // iOS 原生 alert 按钮即系统样式, 无裸文本问题, 等价意图成立
                Button(L10n.format("widget_scroll_dialog_confirm")) {
                    showConfirm = false
                    scope.onScrollEnabledChange(true)
                }
                Button(L10n.format("widget_scroll_dialog_cancel"), role: .cancel) {
                    showConfirm = false
                }
            } message: {
                Text(L10n.format("widget_scroll_dialog_body"))
            }
        }
    }
}

// ← WidgetEditCompactWindowSection (2026-09-15 用户定稿): "三天窗口" 分区 —
//   三天窗口档位, 本 kind 一档。仅 WeekList/WeekView 两族的系统小 family
//   (Android「· 小」变体 WeekListSmall/WeekViewSmall) 显示; 其它族与未知族
//   隐藏 (档位对其它变体无效果, 显示出来只会误导)。
//   non-private: 门控纯函数供 SleepyTests 锁死 (← Android object 可被单测引用)。
struct WidgetEditCompactWindowSection: View {
    @Environment(\.localWakeUpColors) private var colors
    let scope: WidgetEditScope

    /// 纯函数门控 — 单测锁死, 防止族名漂移。
    /// Android appliesTo(receiverSimpleName) == WeekListSmall/WeekViewSmall →
    /// iOS 等价 = 族(kind) ∈ {WeekList, WeekView} 且 family == .systemSmall
    /// (「· 小」变体在 WidgetKit 的表达)。仅判 family 会把本节显示到
    /// Today/TwoDay/WeekGrid 的小档实例上, 设置无效果 = 误导, 违反 Android 语义。
    static func appliesTo(kind: String, family: WidgetFamily?) -> Bool {
        family == .systemSmall && (kind.contains("WeekList") || kind.contains("WeekView"))
    }

    var body: some View {
        if Self.appliesTo(kind: scope.kind, family: scope.family) {
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.format("widget_edit_compact_title"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colors.onSurface)
                Spacer().frame(height: 8)
                VStack(spacing: 0) {
                    optionRow(
                        label: L10n.format("widget_edit_compact_today_first"),
                        selected: scope.compactTodayFirst
                    ) {
                        scope.onCompactTodayFirstChange(true)
                    }
                    optionRow(
                        label: L10n.format("widget_edit_compact_today_second"),
                        selected: !scope.compactTodayFirst
                    ) {
                        scope.onCompactTodayFirstChange(false)
                    }
                }
                .background(colors.surfaceContainer)
                .cornerRadius(16)
            }
        }
    }

    // ← OptionRow: RadioButton + bodyLarge 16, padding horizontal 16 vertical 4
    //   (RadioButton 原生保留 — Android 此节原样用 M3 RadioButton, 非色块选中态规则场景)
    private func optionRow(label: String, selected: Bool, onSelect: @escaping () -> Void) -> some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                Image(systemName: selected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(selected ? colors.primary : colors.onSurfaceVariant)
                Text(label)
                    .font(.system(size: 16))
                    .foregroundColor(colors.onSurface)
                    .padding(.leading, 4)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .buttonStyle(SleepyButtonStyle())
    }
}
