// CourseColorSection.swift — ← ui/screen/mine/AppearanceScreen.kt 的 CourseColorSection
// 外观页 Section②·5「课程配色」(v1.0.62 三档 + 色相滑条 + 试算预览 + 手动重排)。
//
// 逐条对齐 原版本 CourseColorSection.kt:
//   - 三档单选 = SegmentedSwitcher(容器色 surfaceContainerHighest);
//   - CUSTOM 档才出种子色相行 + 彩虹滑条(拖动只动本地值, 松手才提交);
//   - 预览胶囊 = 试算 planned ∪ 持久快照 hueMap(有记录直读 → 所见即主页所得);
//   - 底部 FilledTonalButton「重排全部课程颜色」。
//
// anchor 取「写侧同一解析函数」CourseColorWriteGlue.resolveAnchor(mode:prefs:)
// (而非另一条 colors.primary → ARGB 路径): 预览必须等于重算真正落库所用的 anchor,
// 否则会出现「预览一套色、主页另一套色」。两路在 system/custom/preset 三种主题键下
// 本就同源(见 CourseColorWriteGlue.themePrimaryArgb 的分支注释)。

import SwiftUI

struct CourseColorSection: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localCoursePalette) private var palette

    let mode: Int
    let seed: Float
    /// 滑条本地值(拖动中; 未提交)
    let sliderHue: Float
    /// 持久色相快照(CourseHueStore) — 与主页胶囊同一事实源
    let hueMap: [String: Float]
    /// 预览胶囊数据源: gid → 课名(空课表时用占位名)
    let previewGroups: [(gid: String, name: String)]

    let onModeChange: (Int) -> Void
    let onSliderChange: (Float) -> Void
    let onSeedCommit: (Float) -> Void
    let onRecalc: () -> Void

    /// 与主页/课表格/小组件同一 isDark 判定(isPaletteDark(palette))— S/L 档逐位同源
    private var isDark: Bool { CourseColorUtil.isPaletteDark(palette) }

    /// 课表有课取真实前 5 组课名; 空课表用占位串(预览仍可看色相编排)
    private var items: [(gid: String, name: String)] {
        previewGroups.isEmpty
            ? (1...5).map { (gid: "preview-\($0)", name: L10n.format("format_help_example")) }
            : previewGroups
    }

    /// 试算层: 只对「无持久记录」的组生效(占位串/导入未落库的新课)
    private var planned: [String: Float] {
        let gids = items.map(\.gid)
        guard let anchor = CourseColorWriteGlue.resolveAnchor(mode: mode, prefs: .shared) else {
            var out: [String: Float] = [:]
            for gid in gids { out[gid] = CourseColorUtil.stableHue(gid) }
            return out
        }
        return CourseColorUtil.planHuesForGroups(anchor: anchor, existingHues: [], gids: gids)
    }

    /// 持久快照优先(有记录直读) → 预览即主页所得
    private var hues: [String: Float] {
        Dictionary(uniqueKeysWithValues: planned.map { key, value in
            (key: key, value: hueMap[key] ?? value)
        })
    }

    var body: some View {
        VStack(spacing: 4) {
            SegmentedSwitcher(
                options: [
                    (AppPrefs.COURSE_COLOR_MODE_CLASSIC, L10n.format("course_color_classic")),
                    (AppPrefs.COURSE_COLOR_MODE_FOLLOW_THEME, L10n.format("course_color_follow_theme")),
                    (AppPrefs.COURSE_COLOR_MODE_CUSTOM, L10n.format("course_color_custom_seed"))
                ],
                selected: mode,
                onSelect: onModeChange,
                // ← 原 containerColor = colors.surfaceContainerHighest:
                //   嵌进 surfaceContainer 卡片时同色隐形, 降一级保持对比
                containerColor: colors.surfaceContainerHighest
            )

            if mode == AppPrefs.COURSE_COLOR_MODE_CUSTOM {
                HStack {
                    Text(L10n.format("course_color_seed_label"))
                        .font(SleepyTypography.bodySmall)
                        .foregroundColor(colors.onSurfaceVariant)
                    Spacer(minLength: 8)
                    Text("\(Int(sliderHue.rounded()))°")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colors.onSurface)
                }
                .padding(.horizontal, 8)
                HueSlider(hue: sliderHue,
                          onHueChange: onSliderChange,
                          onHueCommit: onSeedCommit)
                    .padding(.horizontal, 8)
                    .frame(height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: SleepyShapes.large))
            }

            Spacer().frame(height: 4)

            Text(L10n.format("course_color_preview"))
                .font(SleepyTypography.labelMedium)
                .foregroundColor(colors.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.gid) { item in
                        if let hue = hues[item.gid] {
                            let (s, l) = GoldenAngleColor.hsl(hue, isDark)
                            let bg = CourseColorUtil.hslToColor(hue, s, l)
                            Text(item.name)
                                .font(SleepyTypography.labelSmall)
                                .foregroundColor(CourseColorUtil.textColorOn(bg: bg,
                                                                          isDark: isDark,
                                                                          onSurface: colors.onSurface))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(bg)
                                .clipShape(RoundedRectangle(cornerRadius: SleepyShapes.small))
                        }
                    }
                }
            }

            Spacer().frame(height: 8)

            Button(action: onRecalc) {
                Text(L10n.format("course_color_recalc"))
                    .font(SleepyTypography.labelLarge)
                    .foregroundColor(colors.onSecondaryContainer)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(colors.secondaryContainer)
                    .cornerRadius(SleepyShapes.large)
            }
            .buttonStyle(SleepyButtonStyle())
            .accessibilityIdentifier("course_color_recalc")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }
}
