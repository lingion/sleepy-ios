"""独立回归：执行生产 Swift 纯策略 + 检查 SwiftUI 接线，不构建主工程。

运行：python3 scripts/tests/test_header_hue_regression.py
非 Swift 脚本放在 scripts/tests，避免作为 XCTest bundle 资源参与签名。
源码接线检查不替代 SwiftUI 生命周期/像素验收。
"""
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def source(path):
    return (ROOT / "Sleepy" / path).read_text()


def declaration(text, marker):
    start = text.index(marker)
    opening = text.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


class HeaderHueRegression(unittest.TestCase):
    def test_alignment_applies_to_legacy_not_three_line(self):
        cell = source("ui/component/PeriodHeaderCellContent.swift")
        self.assertIn("legacyBody(cardW: cardW, cardH: cardH, label: label, hideTime: hideTime, centerTime: centerTime)", cell)
        three = declaration(cell, "private func threeLineBody")
        self.assertNotIn("centerTime", three)
        settings = source("ui/screen/mine/PeriodHeaderSettingsScreen.swift")
        legacy = declaration(settings, 'if layout == "legacy"')
        self.assertIn('appearance_header_time_alignment', legacy)

    def test_preview_and_persisted_cell_have_explicit_dependencies(self):
        settings = source("ui/screen/mine/PeriodHeaderSettingsScreen.swift")
        self.assertIn('centerTime: timeAlignment == "center"', settings)
        self.assertIn("centerTimeOverride: centerTime", settings)
        widths = declaration(settings, "private var styleWidths")
        self.assertIn("centerTime: centerTime", widths)
        cell = source("ui/component/PeriodHeaderCellContent.swift")
        self.assertIn("@AppStorage(AppPrefs.KEY_PERIOD_HEADER_TIME_ALIGNMENT", cell)

    def test_column_width_and_axis_share_alignment_policy(self):
        cell = source("ui/component/PeriodHeaderCellContent.swift")
        grid = source("ui/component/CourseTableView.swift")
        self.assertIn("legacyTimeColumnPx", declaration(cell, "func legacyLineWidthDp"))
        self.assertIn("legacyTimeColumnPx", declaration(grid, "private struct HeaderColumnGeometry"))
        self.assertIn("@AppStorage(AppPrefs.KEY_PERIOD_HEADER_TIME_ALIGNMENT", grid)
        self.assertIn("centerTime: headerCenterTime", grid)

    def test_hide_time_remains_label_only_and_width_aware(self):
        cell = source("ui/component/PeriodHeaderCellContent.swift")
        hidden = declaration(cell, "if hideTime")
        self.assertIn("Text(label)", hidden)
        self.assertNotIn("Text(displayStart)", hidden)
        self.assertNotIn("centerTime", hidden)
        self.assertIn(".frame(width: cardW, height: cardH)", hidden)
        width = declaration(cell, "func legacyTimeWidthDp")
        self.assertIn("if !hideTime", width)
        self.assertIn("centerTime: centerTime", width)
        self.assertIn("return max(content, 36 * scale)", width)
        settings = source("ui/screen/mine/PeriodHeaderSettingsScreen.swift")
        self.assertIn("prefs.setPeriodHeaderHideTime(newValue)", settings)
        self.assertIn("hideTimeOverride: hideTime", settings)
        grid = source("ui/component/CourseTableView.swift")
        self.assertIn("legacyTimeWidthDp(slots: renderSlots", grid)
        self.assertIn("hideTime: headerHideTime", grid)
        self.assertIn("@AppStorage(AppPrefs.KEY_PERIOD_HEADER_HIDE_TIME", grid)

    def test_hue_caller_keeps_session_baseline_after_commit(self):
        appearance = source("ui/screen/mine/AppearanceScreen.swift")
        section = source("ui/screen/mine/CourseColorSection.swift")
        self.assertNotIn("private struct CourseColorSection", appearance)
        self.assertIn("@State private var hueSession = HueEditingSession", appearance)
        self.assertIn("sliderHue: hueSession.current", appearance)
        self.assertIn("initialHue: hueSession.baseline", appearance)
        self.assertIn("onSliderChange: { hueSession.current = $0 }", appearance)
        self.assertIn("onSeedCommit: commitCourseHue", appearance)
        self.assertIn("initialHue: initialHue", section)
        self.assertNotIn("initialHue: prefs.", appearance + section)
        self.assertEqual(appearance.count("hueSession ="), 1)
        self.assertNotIn("hueSession.baseline =", appearance + section)
        commit = declaration(appearance, "private func commitCourseHue")
        self.assertIn("prefs.setCourseColorSeedHue(hue)", commit)
        self.assertIn("recalcAllCourses()", commit)

    def test_new_section_preserves_uniform_and_real_persisted_preview(self):
        appearance = source("ui/screen/mine/AppearanceScreen.swift")
        section = source("ui/screen/mine/CourseColorSection.swift")
        self.assertIn("colorless: courseColorless", appearance)
        self.assertIn("previewGroups: previewGroups", appearance)
        self.assertIn("hueMap: hueStore.hueMap", appearance)
        self.assertIn("getAllCourses()", appearance)
        self.assertIn("prefs.setCourseColorless(true)", appearance)
        self.assertIn("prefs.setCourseColorless(false)", appearance)
        self.assertIn("selected: colorless ? -1 : mode", section)
        self.assertIn('L10n.format("course_color_uniform")', section)
        self.assertIn("CourseColorWriteGlue.resolveAnchor(mode: mode, prefs: .shared)", section)
        # 真实课程不再用试算色覆盖首页的 stableHue 回退；保留完整组行走首页入口。
        self.assertIn("CourseColorPreview.groups(from: courses)", appearance)
        self.assertIn("item.color(", section)
        self.assertIn("? nil : hueMap[item.course.groupId]", section)
        preview = source("ui/screen/mine/CourseColorPreview.swift")
        self.assertIn("CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(", preview)
        self.assertIn("course, groupRows: groupRows", preview)
        self.assertNotIn("planHuesForGroups", preview)
        self.assertIn("previewGroups.isEmpty", section)

    def test_display_sliders_keep_all_six_baselines_and_quantized_bindings(self):
        display = source("ui/screen/mine/ScheduleDisplayScreen.swift")
        names = ("GridScale", "WeekScale", "CornerRatio", "ConflictStackInset", "ConflictRailInset", "ConflictFoldSize")
        for name in names:
            self.assertIn("baseline: baseline" + name, display)
        capture = declaration(display, "private func captureBaselines")
        self.assertIn("guard baselineGridScale == nil else { return }", capture)
        self.assertEqual(display.count(".onAppear { captureBaselines() }"), 1)
        self.assertIn("NativeBaselineSlider(value: value, range: range, baseline: baseline", display)
        self.assertIn("onValueChange: onValueChange, onFinished: onFinished", display)
        self.assertNotIn("trackPadding", display)
        native = source("ui/component/NativeBaselineSlider.swift")
        self.assertIn("slider.frame = bounds", native)
        self.assertIn("ghost.frame = bounds", native)
        self.assertIn(".forceRightToLeft : .forceLeftToRight", native)
        self.assertIn("ghost.isUserInteractionEnabled = false", native)
        self.assertIn("ghost.accessibilityElementsHidden = true", native)
        self.assertIn("if !slider.isTracking { parent.onFinished() }", native)

    def test_real_swift_repeated_display_capture_preserves_session(self):
        display = source("ui/screen/mine/ScheduleDisplayScreen.swift")
        self.assertIn("private func captureBaselines", display)
        capture = declaration(display, "private func captureBaselines")
        names = ("GridScale", "WeekScale", "CornerRatio", "ConflictStackInset", "ConflictRailInset", "ConflictFoldSize")
        fields = []
        checks = []
        edits = []
        for index, name in enumerate(names, 1):
            value = name[0].lower() + name[1:]
            fields.extend([f"var {value}: Double = {index}", f"var baseline{name}: Double? = nil"])
            checks.append(f"assert(s.baseline{name} == {index})")
            edits.append(f"s.{value} = {index + 10}")
        program = "\n".join([
            "final class Session {", *fields,
            capture.replace("private func", "func", 1), "}",
            "let s = Session()", "s.captureBaselines()", *checks,
            *edits, "s.captureBaselines()", *checks,
            "let reopened = Session()", "reopened.gridScale = 12", "reopened.captureBaselines()",
            "assert(reopened.baselineGridScale == 12)",
        ])
        result = subprocess.run(["swift", "-"], input=program, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_real_swift_geometry_and_edit_session(self):
        model = source("util/PeriodHeaderLayoutModel.swift")
        cell = source("ui/component/PeriodHeaderCellContent.swift")
        hue = source("ui/component/HueSlider.swift")
        self.assertIn("func legacyTimeColumnPx", cell, "缺少居中列几何策略")
        self.assertIn("struct HueEditingSession", hue, "缺少编辑会话固定基线")
        parts = ["import Foundation"]
        for name in ("struct LegacyDashRowInk", "struct LegacyDashPlacement", "struct LegacyDashColumn", "func legacyDashColumnPx"):
            parts.append(declaration(model, name))
        parts.append(declaration(cell, "func legacyTimeColumnPx"))
        parts.append(declaration(hue, "struct HueEditingSession"))
        parts.append('''
let rows = [
    LegacyDashRowInk(labelPx: 12, timeLeftPx: 20, dashPx: 4, timeRightPx: 40),
    LegacyDashRowInk(labelPx: 80, timeLeftPx: 50, dashPx: 4, timeRightPx: 10)
]
let centered = legacyTimeColumnPx(rows: rows, padPx: 3, centerTime: true)
assert(centered.columnWidthPx == 86)
assert(centered.dashCenterX == 43)
for (row, placement) in zip(rows, centered.placements) {
    assert(placement.labelLeft + row.labelPx / 2 == 43)
    assert(placement.timeLeft + (row.timeLeftPx + row.dashPx + row.timeRightPx) / 2 == 43)
    assert(placement.labelLeft >= 3 && placement.timeLeft >= 3)
}
let dash = legacyTimeColumnPx(rows: rows, padPx: 3, centerTime: false)
assert(dash == legacyDashColumnPx(rows: rows, padPx: 3))
assert(dash.columnWidthPx == 100)
assert(legacyTimeColumnPx(rows: [], padPx: 3, centerTime: true).columnWidthPx == 0)
var session = HueEditingSession(initialHue: 180)
session.current = 300
let persisted = session.current
assert(persisted == 300 && session.baseline == 180)
assert(HueEditingSession(initialHue: persisted).baseline == 300)
session.current = 180
assert(session.current == session.baseline)
let unset = HueEditingSession(initialHue: -1)
assert(unset.current == 0 && unset.baseline == unset.current)
assert(HueEditingSession(initialHue: 400).baseline == 360)
assert(HueEditingSession(initialHue: .nan).baseline == 0)
assert(HueEditingSession(initialHue: .infinity).current == 0)
print("Swift geometry/session regressions passed")
''')
        result = subprocess.run(["swift", "-"], input="\n".join(parts), text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
