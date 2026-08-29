// AppearanceScreen.swift — ← ui/screen/mine/AppearanceScreen.kt
// 外观页(决策 D2 合并页): 仅主题色彩组(SystemThemeCard + 2列预设网格 + 深浅色三态)。
// 选主题/模式后立即刷小组件(refreshWidgets 管线保留)。

import SwiftUI
import WidgetKit
import Combine

struct AppearanceScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let onBack: () -> Void
    var themeMode: String = AppPrefs.THEME_MODE_SYSTEM
    var onThemeModeChange: (String) -> Void = { _ in }

    @State private var currentKey: String
    private let prefs = AppPrefs.shared

    init(onBack: @escaping () -> Void,
         themeMode: String = AppPrefs.THEME_MODE_SYSTEM,
         onThemeModeChange: @escaping (String) -> Void = { _ in }) {
        self.onBack = onBack
        self.themeMode = themeMode
        self.onThemeModeChange = onThemeModeChange
        _currentKey = State(initialValue: AppPrefs.shared.getThemeKey())
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("mine_appearance"), onBack: onBack)
            ScrollView {
                VStack(spacing: 12) {
                    // ── 分组① 主题色彩 ──
                    SectionHeader(title: L10n.format("appearance_section_theme"))

                    SystemThemeCard(selected: currentKey == ThemePresets.KEY_SYSTEM) {
                        prefs.setThemeKey(ThemePresets.KEY_SYSTEM)
                        currentKey = ThemePresets.KEY_SYSTEM
                        refreshWidgets()
                    }

                    // 2 列网格 5 套预设
                    let presets = ThemePresets.all
                    let rows = presets.chunked(into: 2)
                    VStack(spacing: 12) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 12) {
                                ForEach(row, id: \.key) { p in
                                    PresetThemeCard(preset: p, selected: currentKey == p.key) {
                                        prefs.setThemeKey(p.key)
                                        currentKey = p.key
                                        refreshWidgets()
                                    }
                                }
                                if row.count == 1 { Spacer() }
                            }
                        }
                    }

                    // 外观模式: 浅色/深色/跟随系统 三态分段
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.format("theme_appearance"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colors.onSurface)
                        let modes: [(String, String)] = [
                            (AppPrefs.THEME_MODE_SYSTEM, L10n.format("theme_mode_system")),
                            (AppPrefs.THEME_MODE_LIGHT, L10n.format("theme_mode_light")),
                            (AppPrefs.THEME_MODE_DARK, L10n.format("theme_mode_dark"))
                        ]
                        HStack(spacing: 3) {
                            ForEach(modes, id: \.0) { mode, label in
                                let sel = mode == themeMode
                                Button {
                                    guard mode != themeMode else { return }
                                    prefs.setThemeMode(mode)
                                    onThemeModeChange(mode)
                                    refreshWidgets()
                                } label: {
                                    Text(label)
                                        .font(.system(size: 14, weight: sel ? .semibold : .medium))
                                        .foregroundColor(sel ? colors.onPrimary : colors.onSurfaceVariant)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(sel ? colors.primary : colors.surfaceContainer)
                                        .cornerRadius(SleepyShapes.medium)
                                }
                                .buttonStyle(SleepyButtonStyle())
                                .accessibilityIdentifier("theme_mode_\(mode)")
                            }
                        }
                        .padding(3)
                        .background(colors.surfaceContainer)
                        .cornerRadius(SleepyShapes.medium)
                    }
                    .padding(.top, 4)
                }
                .padding(16)
            }
        }
        .background(colors.background)
    }

    // ★ 选主题/模式后立即刷小组件(← WidgetUpdater.notifyDataChanged)
    private func refreshWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// ← SystemThemeCard
private struct SystemThemeCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 28))
                    .foregroundColor(colors.onPrimaryContainer)
                    .frame(width: 56, height: 56)
                    .background(colors.primaryContainer)
                    .cornerRadius(SleepyShapes.large)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.format("theme_system"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colors.onSurface)
                    Text(L10n.format("theme_system_desc"))
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24))
                        .foregroundColor(colors.primary)
                }
            }
            .padding(16)
            .background(selected ? colors.primaryContainer : colors.surfaceContainer)
            .cornerRadius(SleepyShapes.large)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("theme_system_card")
    }
}

// ← PresetThemeCard
private struct PresetThemeCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let preset: ThemePreset
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        // 背景亮度决定展示 light 还是 dark 预览
        let scheme = CourseColorUtil.luminance(colors.background) < 0.5 ? preset.dark : preset.light
        Button(action: onClick) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ColorSwatch(color: scheme.primary)
                    ColorSwatch(color: scheme.secondary)
                    ColorSwatch(color: scheme.tertiary)
                }
                HStack {
                    Text(L10n.format(preset.nameKey))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onSurface)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20))
                            .foregroundColor(colors.primary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? colors.primaryContainer : colors.surfaceContainer)
            .cornerRadius(SleepyShapes.large)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("theme_preset_\(preset.key)")
    }
}

// ← ColorSwatch
private struct ColorSwatch: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: SleepyShapes.small)
            .fill(color)
            .frame(width: 28, height: 28)
    }
}
