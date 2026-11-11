// CustomThemeEditorScreen.swift — ← ui/screen/mine/CustomThemeEditorScreen.kt
// 自定义主题创建/微调编辑器 — 外观页弹出(等价 原版本 全屏 overlay)。
//
// 三动作区:随机生成 / 选主色生成整套 / 逐角色手选。
// 草稿语义:全部改动只改内存草稿 draft,底部「保存」才落 CustomThemeStore。
// 主色生成整套的邻近色逻辑:secondary = 色相 +40°、tertiary = 色相 −40°
// (M3 邻近色思想:同主题氛围内拉开间隔,避免互补色刺眼),表面用该色相低 chroma。
// 删除区(errorContainer 整宽色块,全 app 纯色块禁描边)→ 确认对话框。
//
// ★ iOS 适配(与 原版本 的有意差异,语义等价):
//   1. 取色器:原版本 ColorPickerDialog → 本仓 NativeColorPicker(UIColorPickerViewController)。
//      它回 "#AARRGGBB"(9 位),落库前统一裁成 "#RRGGBB",保持与 原版本 同一存储形状。
//   2. 返回拦截:原版本 BackHandler 分层(删除确认 > 取色器 > 编辑器)→ iOS
//      .interactiveDismissDisabled(dirty) 挡住下滑手势 + 顶栏返回键在 dirty 时弹确认,
//      绝静默丢弃(95c1dab3 语义)。
//   3. 「从主色生成整套」与「逐角色手选」是独立入口;手选主色只更新主色。

import SwiftUI
import UIKit

struct CustomThemeEditorScreen: View {
    @Environment(\.sleepyUIStyle) private var uiStyle
    @Environment(\.localWakeUpColors) private var colors

    let editing: CustomTheme?
    /// 新建态默认名 "主题 N" 的 N(外观页传 现有数量+1)
    let nextThemeNumber: Int
    let onBack: () -> Void
    let onSaved: (CustomTheme) -> Void
    let onDeleted: (String) -> Void

    // ── 草稿:所有改动只动这里,保存才落盘 ──
    @State private var draft: CustomTheme
    /// 进入页面时的快照,dirty = draft != initial(返回拦截与下滑禁用都靠它)
    private let initial: CustomTheme

    // 取色器状态:nil = 关闭;非 nil = 正在编辑该角色的种子
    @State private var pickingRole: Role?
    @State private var showDeleteConfirm = false
    @State private var showDiscardConfirm = false
    @State private var manualExpanded = false

    init(editing: CustomTheme?,
         nextThemeNumber: Int,
         onBack: @escaping () -> Void,
         onSaved: @escaping (CustomTheme) -> Void,
         onDeleted: @escaping (String) -> Void) {
        self.editing = editing
        self.nextThemeNumber = nextThemeNumber
        self.onBack = onBack
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        // ← 原版本 remember(editing) { editing ?: CustomTheme(默认草稿) }
        let base = editing ?? CustomThemeEditorScreen.newDraft(number: nextThemeNumber)
        _draft = State(initialValue: base)
        initial = base
    }

    /// 新建态默认草稿 ← 原版本 同名字段:#7C4DFF / #546E7A / #EF6C00,表面 265/8
    static func newDraft(number: Int) -> CustomTheme {
        CustomTheme(
            id: "",   // 保存时生成
            name: L10n.format("theme_custom_default_name", number),
            primary: "#7C4DFF",
            secondary: "#546E7A",
            tertiary: "#EF6C00",
            surfaceHue: 265.0,
            surfaceChroma: 8.0,
            createdAt: Int64(Date().timeIntervalSince1970)
        )
    }

    private var isDirty: Bool { draft != initial }
    /// 保存前校验:三个种子 hex 必须可解析(坏 hex 会让派生引擎退回模板相,静默出错)
    private var isValid: Bool {
        [draft.primary, draft.secondary, draft.tertiary].allSatisfy { CustomSchemeDeriver.parseHex($0) != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(
                title: L10n.format(editing == nil ? "theme_new" : "theme_custom_edit"),
                onBack: requestBack
            )
            ScrollView {
                VStack(spacing: 12) {
                    // ── 命名 ──
                    FieldTextField(
                        text: Binding(get: { draft.name }, set: { draft = draft.copy(name: $0) }),
                        label: L10n.t("theme_custom_name_label")
                    )

                    // ── 实时预览:迷你课表样例(顶栏条 + 胶囊 + 卡片)用草稿派生 scheme 渲染 ──
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.format("theme_editor_preview"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colors.onSurface)
                        DraftPreview(draft: draft)
                    }

                    // ── 三动作区(原版本 Column spacedBy(8.dp),整体是外层 12 间距网格的一个 item)──
                    VStack(alignment: .leading, spacing: 8) {
                        EditorActionEntry(
                            icon: .palette,
                            title: L10n.format("theme_editor_from_seed"),
                            desc: L10n.format("theme_editor_from_seed_desc"),
                            onClick: { pickingRole = .seedPrimary }
                        )
                        EditorActionEntry(
                            icon: .autoAwesome,
                            title: L10n.format("theme_editor_random"),
                            desc: L10n.format("theme_editor_random_desc"),
                            onClick: { draft = Self.randomDraft(draft) }
                        )
                        EditorActionEntry(
                            icon: .tune,
                            title: L10n.format("theme_editor_manual"),
                            desc: L10n.format("theme_editor_manual_desc"),
                            onClick: { withAnimation(.easeInOut(duration: 0.15)) { manualExpanded.toggle() } }
                        )
                    }

                    // ── 逐角色手选(展开后四个角色行)──
                    if manualExpanded {
                        VStack(spacing: SettingsLayout.cardGap) {
                            EditorRoleRow(
                                title: L10n.format("theme_role_primary"),
                                desc: L10n.format("theme_role_primary_desc"),
                                swatchHex: draft.primary,
                                isValid: CustomSchemeDeriver.parseHex(draft.primary) != nil
                            ) { pickingRole = .primary }

                            EditorRoleRow(
                                title: L10n.format("theme_role_secondary"),
                                desc: L10n.format("theme_role_secondary_desc"),
                                swatchHex: draft.secondary,
                                isValid: CustomSchemeDeriver.parseHex(draft.secondary) != nil
                            ) { pickingRole = .secondary }

                            EditorRoleRow(
                                title: L10n.format("theme_role_tertiary"),
                                desc: L10n.format("theme_role_tertiary_desc"),
                                swatchHex: draft.tertiary,
                                isValid: CustomSchemeDeriver.parseHex(draft.tertiary) != nil
                            ) { pickingRole = .tertiary }

                            EditorRoleRow(
                                title: L10n.format("theme_role_surface"),
                                desc: L10n.format("theme_role_surface_desc"),
                                swatchHex: Self.surfacePreviewHex(hue: draft.surfaceHue, chroma: draft.surfaceChroma),
                                isValid: true
                            ) { pickingRole = .surface }

                        }
                    }

                    // ── 底部动作:保存 ──
                    Button(action: save) {
                        Text(L10n.format("save"))
                            .font(.system(size: 16, weight: .medium))   // ← titleMedium 16sp Medium (Theme.kt:274)
                            .frame(maxWidth: .infinity)
                            .frame(height: uiStyle == .liquidGlass ? nil : 56)   // ← SleepyTheme.Buttons.ctaHeight
                            .foregroundColor(isValid ? colors.onPrimary : colors.onSurfaceVariant)
                            .sleepyControlSurface(cornerRadius: SleepyShapes.large,
                                                  tint: isValid ? colors.primary : colors.surfaceVariant, prominent: true)   // ← SleepyTheme.Buttons.shape = shapes.large
                    }
                    .buttonStyle(SleepyPlatformButtonStyle(prominent: true, cornerRadius: SleepyShapes.large))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .tint(isValid ? colors.primary : colors.surfaceVariant)
                    .disabled(!isValid)
                    .accessibilityIdentifier("theme_editor_save")

                    // ── 删除区(仅微调既有主题时;errorContainer 整宽色块,禁描边)──
                    if editing != nil {
                        Button(action: { showDeleteConfirm = true }) {
                            HStack(spacing: 8) {
                                AndroidSettingsIcon(name: .delete, size: 18)   // ← Icons.Outlined.Delete 18.dp
                                Text(L10n.format("delete")).font(.system(size: 14, weight: .medium))   // ← Button 默认 labelLarge 14sp Medium
                            }
                            .foregroundColor(colors.onErrorContainer)
                            .frame(maxWidth: .infinity)
                            .frame(height: uiStyle == .liquidGlass ? nil : 48)   // ← SleepyTheme.Buttons.regularHeight
                            .sleepyControlSurface(cornerRadius: SleepyShapes.large, tint: colors.errorContainer, prominent: true)   // ← SleepyTheme.Buttons.shape = shapes.large
                        }
                        .buttonStyle(SleepyPlatformButtonStyle(prominent: true, cornerRadius: SleepyShapes.large))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .tint(colors.errorContainer)
                        .accessibilityIdentifier("theme_editor_delete")
                    }
                }
                .padding(16)
            }
        }
        .background(colors.background)
        // ── 取色器(公共组件)──
        .sheet(item: $pickingRole) { role in
            NativeColorPicker(initialHex: initialHexFor(role)) { hex in
                applyPicked(hex: hex, role: role)
                pickingRole = nil
            }
        }
        // ── 删除确认 ──
        .alert(L10n.format("theme_editor_delete_confirm"), isPresented: $showDeleteConfirm) {
            Button(L10n.format("delete"), role: .destructive) {
                if let editing = editing { onDeleted(editing.id) }
            }
            Button(L10n.format("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.format("theme_editor_delete_confirm_body"))
        }
        // ── 未保存改动确认(返回拦截,见文件头 iOS 适配 ②)──
        .alert(L10n.format("theme_editor_discard_confirm"), isPresented: $showDiscardConfirm) {
            Button(L10n.format("theme_editor_discard"), role: .destructive) { onBack() }
            Button(L10n.format("cancel"), role: .cancel) {}
        }
        .interactiveDismissDisabled(isDirty)
    }

    private func requestBack() {
        isDirty ? (showDiscardConfirm = true) : onBack()
    }

    private func save() {
        guard isValid else { return }
        let id = draft.id.trimmingCharacters(in: .whitespaces).isEmpty ? CustomThemeCore.newId() : draft.id
        onSaved(CustomTheme(
            id: id,
            name: draft.name,   // ← 原 kt:214-217 原样保存 draft.name(仅 id 补 UUID),不 trim
            primary: Self.normalizedHex(draft.primary),
            secondary: Self.normalizedHex(draft.secondary),
            tertiary: Self.normalizedHex(draft.tertiary),
            surfaceHue: draft.surfaceHue,
            surfaceChroma: draft.surfaceChroma,
            createdAt: draft.createdAt
        ))
    }

    private func initialHexFor(_ role: Role) -> String {
        switch role {
        case .primary: return draft.primary
        case .secondary: return draft.secondary
        case .tertiary: return draft.tertiary
        case .surface: return Self.surfacePreviewHex(hue: draft.surfaceHue, chroma: draft.surfaceChroma)
        case .seedPrimary: return draft.primary
        }
    }

    /// 取色器确认 → 按角色写草稿(逐分支对齐 原 onConfirm when(role))
    private func applyPicked(hex rawHex: String, role: Role) {
        draft = Self.applyingPickedColor(hex: rawHex, role: role, to: draft)
    }

    /// Manual edits preserve every other role; only the explicit seed action generates a palette.
    static func applyingPickedColor(hex rawHex: String, role: ThemeEditorRole, to draft: CustomTheme) -> CustomTheme {
        let hex = normalizedHex(rawHex)
        guard let color = CustomSchemeDeriver.parseHex(hex) else { return draft }
        let rgb = CustomSchemeDeriver.rgb(of: color)
        let seedHue = Double(CustomSchemeDeriver.normalizeHue(
            Double(CustomSchemeDeriver.rgbToHsv(r: rgb.r, g: rgb.g, b: rgb.b).h)))

        switch role {
        case .primary:
            return draft.copy(primary: hex)
        case .secondary:
            return draft.copy(secondary: hex)
        case .tertiary:
            return draft.copy(tertiary: hex)
        case .surface:
            // 表面中性色:只取色相,chroma 钳回低饱和推荐区间(4-12)
            return draft.copy(surfaceHue: seedHue, surfaceChroma: min(max(draft.surfaceChroma, 4.0), 12.0))
        case .seedPrimary:
            // 选主色生成整套:secondary 色相 +40°、tertiary 色相 −40°(M3 邻近色)
            return draft.copy(
                primary: hex,
                secondary: Self.hexAtHue(hue: seedHue + 40.0, s: 0.45, v: 0.45),
                tertiary: Self.hexAtHue(hue: seedHue - 40.0, s: 0.55, v: 0.50),
                surfaceHue: seedHue,
                surfaceChroma: 8.0
            )
        }
    }

    /// 取色器回 "#AARRGGBB" → 统一 "#RRGGBB"(存储形状与原实现一致)
    private static func normalizedHex(_ hex: String) -> String {
        let s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("#") else { return s }
        let body = String(s.dropFirst())
        guard body.count == 8 else { return s.uppercased() }
        return ("#" + body.suffix(6)).uppercased()
    }

    // ── 草稿生成工具(文件尾同名私有函数)──

    /// 随机生成:4 源角色各随机 — 色相均匀随机、primary 高饱和、表面低 chroma(4-12)
    static func randomDraft(_ current: CustomTheme) -> CustomTheme {
        CustomTheme(
            id: current.id,
            name: current.name,
            primary: hexAtHue(hue: Double.random(in: 0..<360), s: 0.70, v: 0.55),
            secondary: hexAtHue(hue: Double.random(in: 0..<360), s: 0.40, v: 0.50),
            tertiary: hexAtHue(hue: Double.random(in: 0..<360), s: 0.50, v: 0.55),
            surfaceHue: Double.random(in: 0..<360),
            surfaceChroma: 4.0 + Double.random(in: 0..<8.0),   // 4-12 低饱和推荐区间
            createdAt: current.createdAt
        )
    }

    /// 表面倾向的预览 hex(编辑器里展示用)— 用浅色端 V=0.92 反推
    static func surfacePreviewHex(hue: Double, chroma: Double) -> String {
        hexAtHue(hue: hue, s: min(max(chroma, 0.0), 48.0) / 100.0, v: 0.92)
    }

    /// HSV → "#RRGGBB"(与派生引擎同源:走 CustomSchemeDeriver.hsvToColor 的 8-bit 量化)
    static func hexAtHue(hue: Double, s: Double, v: Double) -> String {
        let c = CustomSchemeDeriver.hsvToColor(h: Float(hue), s: Float(s), v: Float(v))
        let rgb = CustomSchemeDeriver.rgb(of: c)
        return String(format: "#%02X%02X%02X",
                      Int((Double(rgb.r) * 255).rounded()),
                      Int((Double(rgb.g) * 255).rounded()),
                      Int((Double(rgb.b) * 255).rounded()))
    }
}

// ── 取色器路由角色(← ROLE_* 常量)──
enum ThemeEditorRole: String, Identifiable {
    case seedPrimary = "seed_primary"
    case primary = "primary"
    case secondary = "secondary"
    case tertiary = "tertiary"
    case surface = "surface"

    var id: String { rawValue }
}

private typealias Role = ThemeEditorRole

// ── 子视图 ──

/// 动作入口卡 — 图标 + 标题 + 说明,整卡可点 ← ActionEntry
private struct EditorActionEntry: View {
    @Environment(\.localWakeUpColors) private var colors
    let icon: AndroidSettingsIcon.Name
    let title: String
    let desc: String
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 12) {
                AndroidSettingsIcon(name: icon, size: 24)
                    .foregroundColor(colors.primary)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onSurface)
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surfaceContainer)
            .cornerRadius(SleepyShapes.large)
        }
        .buttonStyle(SleepyButtonStyle())
    }
}

/// 角色行 — 角色名 + 说明 + 当前 hex + 色块,点击弹取色器 ← RoleRow
private struct EditorRoleRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    let desc: String
    let swatchHex: String
    var isValid: Bool = true
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onSurface)
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                }
                Spacer()
                Text(swatchHex.uppercased())
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(isValid ? colors.onSurfaceVariant : colors.error)
                Circle()
                    .fill(CustomSchemeDeriver.parseHex(swatchHex) ?? colors.surfaceVariant)
                    .frame(width: 32, height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surfaceContainer)
            .cornerRadius(SleepyShapes.medium)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("theme_role_\(title)")
    }
}

/// 迷你实时预览 — 顶栏条 + 一个胶囊 + 一张卡片样例,用草稿派生 scheme 渲染 ← DraftPreview
private struct DraftPreview: View {
    @Environment(\.localWakeUpColors) private var colors
    let draft: CustomTheme

    // isDark 跟随当前页面背景红色通道,所见即所得 ← 原版本 kt:379 `pageColors.background.red < 0.5f`(只比红色通道,非亮度)
    private var previewScheme: WakeUpColorScheme {
        let ui = UIColor(colors.background)
        var red: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&red, green: &g, blue: &b, alpha: &a)
        return CustomSchemeDeriver.derive(theme: draft, isDark: red < 0.5)
    }

    var body: some View {
        let scheme = previewScheme
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(scheme.primary).frame(width: 10, height: 10)
                Text(L10n.format("theme_editor_preview"))
                    .font(.system(size: 14, weight: .medium))   // ← labelLarge 14sp Medium (Theme.kt:304)
                    .foregroundColor(scheme.onSurface)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(scheme.surfaceContainer)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.format("schedule_week_prefix", 8))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(scheme.onPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(scheme.primary)
                    .cornerRadius(999)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.format("theme_editor_preview_card_title"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(scheme.onSecondaryContainer)
                    HStack(spacing: 6) {
                        Text("1-2")
                            .font(.system(size: 11, weight: .medium))   // ← labelSmall 11sp Medium (Theme.kt:316)
                            .foregroundColor(scheme.onTertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                            .background(scheme.tertiary)
                            .cornerRadius(999)
                        Text(L10n.format("theme_editor_preview_card_room"))
                            .font(.system(size: 12))
                            .foregroundColor(scheme.onSecondaryContainer)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(scheme.secondaryContainer)
                .cornerRadius(SleepyShapes.medium)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scheme.surface)
        .cornerRadius(SleepyShapes.large)
    }
}
