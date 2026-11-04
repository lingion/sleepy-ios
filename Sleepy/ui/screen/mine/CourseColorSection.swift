// CourseColorSection.swift — ← ui/screen/mine/AppearanceScreen.kt 的 CourseColorSection
// 外观页 Section②·5「课程配色」(统一底色/三档配色 + 色相滑条 + 试算预览 + 手动重排)。
//
// 逐条对齐 原版本 CourseColorSection.kt:
//   - 三档单选 = SegmentedSwitcher(容器色 surfaceContainerHighest);
//   - CUSTOM 档才出种子色相行 + 彩虹滑条(拖动只动本地值, 松手才提交);
//   - 真实课程复用课表取色；空课表才用试算占位色;
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
    let colorless: Bool
    let seed: Float
    /// 滑条本地值(拖动中; 未提交)
    let sliderHue: Float
    /// 本次进页基线，不随提交后的 seed 改变。
    let initialHue: Float
    /// 持久色相快照(CourseHueStore) — 与主页胶囊同一事实源
    let hueMap: [String: Float]
    let previewGroups: [CourseColorPreview]

    let onModeChange: (Int) -> Void
    let onSliderChange: (Float) -> Void
    let onSeedCommit: (Float) -> Void
    let onRecalc: () -> Void

    /// 与主页/课表格/小组件同一 isDark 判定(isPaletteDark(palette))— S/L 档逐位同源
    private var isDark: Bool { CourseColorUtil.isPaletteDark(palette) }

    /// 试算仅用于空课表的占位组；真实课程缺记录时与主页一样回退 stableHue。
    private var planned: [String: Float] {
        let gids = (1...5).map { "preview-\($0)" }
        guard let anchor = CourseColorWriteGlue.resolveAnchor(mode: mode, prefs: .shared) else {
            var out: [String: Float] = [:]
            for gid in gids { out[gid] = CourseColorUtil.stableHue(gid) }
            return out
        }
        return CourseColorUtil.planHuesForGroups(anchor: anchor, existingHues: [], gids: gids)
    }

    var body: some View {
        VStack(spacing: 4) {
            SegmentedSwitcher(
                options: [
                    (-1, L10n.format("course_color_uniform")),
                    (AppPrefs.COURSE_COLOR_MODE_CLASSIC, L10n.format("course_color_classic")),
                    (AppPrefs.COURSE_COLOR_MODE_FOLLOW_THEME, L10n.format("course_color_follow_theme")),
                    (AppPrefs.COURSE_COLOR_MODE_CUSTOM, L10n.format("course_color_custom_seed"))
                ],
                selected: colorless ? -1 : mode,
                onSelect: onModeChange,
                // ← 原 containerColor = colors.surfaceContainerHighest:
                //   嵌进 surfaceContainer 卡片时同色隐形, 降一级保持对比
                containerColor: colors.surfaceContainerHighest
            )

            if !colorless && mode == AppPrefs.COURSE_COLOR_MODE_CUSTOM {
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
                          onHueCommit: onSeedCommit,
                          initialHue: initialHue)
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
                    if previewGroups.isEmpty {
                        ForEach(1...5, id: \.self) { index in
                            let hue = planned["preview-\(index)"] ?? 0
                            let (s, l) = GoldenAngleColor.hsl(hue, isDark)
                            let bg = colorless ? colors.secondaryContainer : CourseColorUtil.hslToColor(hue, s, l)
                            previewPill(L10n.format("format_help_example"), background: bg)
                        }
                    } else {
                        ForEach(previewGroups) { item in
                            previewPill(item.name, background: item.color(
                                isDark: isDark, neutral: colors.secondaryContainer,
                                colorless: colorless,
                                persistedHue: mode == AppPrefs.COURSE_COLOR_MODE_CLASSIC
                                    ? nil : hueMap[item.course.groupId]))
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

    private func previewPill(_ name: String, background: Color) -> some View {
        Text(name)
            .font(SleepyTypography.labelSmall)
            .foregroundColor(CourseColorUtil.textColorOn(bg: background,
                isDark: isDark, onSurface: colors.onSurface))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: SleepyShapes.small))
    }
}
