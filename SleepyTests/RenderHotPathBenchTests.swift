import SwiftUI
import XCTest
@testable import Sleepy

final class RenderHotPathBenchTests: XCTestCase {
    private var shouldRun: Bool {
        ProcessInfo.processInfo.environment["SLEEPY_RUN_PERFORMANCE_TESTS"] == "1"
    }

    private func makeFixtureCourses() -> [CourseEntity] {
        (0..<24).map { idx in
            var c = CourseEntity(
                groupId: "g-\(idx % 6)",
                tableId: 101,
                courseName: "高等数学 \(idx + 1)",
                teacher: "张老师",
                room: "逸夫楼 \(101 + idx)",
                day: (idx % 7) + 1,
                startNode: (idx % 5) * 2 + 1,
                step: 2,
                startWeek: 1,
                endWeek: 20,
                color: idx % 3 == 0 ? "#FF6750A4" : "",
                id: Int64(idx + 1)
            )
            c.colorMode = idx % 3
            return c
        }
    }

    private func measureMedianMs(samples: Int = 7, iterations: Int, label: String, block: (Int) -> Int) {
        var checksum = 0
        checksum &+= block(0)
        var timings: [Double] = []
        timings.reserveCapacity(samples)
        for _ in 0..<samples {
            let start = DispatchTime.now().uptimeNanoseconds
            for iter in 0..<iterations {
                checksum &+= block(iter)
            }
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
            timings.append(elapsedMs)
        }
        let sorted = timings.sorted()
        print("HOTPATH_BENCH \(label) total_ms=\(timings) median_ms=\(sorted[samples / 2]) checksum=\(checksum)")
    }

    func testBenchmarkDateAndOccurrenceHotPath() throws {
        try XCTSkipUnless(shouldRun, "Set SLEEPY_RUN_PERFORMANCE_TESTS=1")
        let anchor = "2026-09-07"
        let sampleDates = (1...28).compactMap { CourseOccurrences.date(startDate: anchor, week: ($0 - 1) / 7 + 1, day: ($0 - 1) % 7 + 1) }
        XCTAssertEqual(sampleDates.count, 28)

        measureMedianMs(iterations: 2000, label: "date_occurrence_2000") { iter in
            let w = (iter % 18) + 1
            let d = (iter % 7) + 1
            let parsed = CourseOccurrences.parseDate(anchor)
            let dd = CourseOccurrences.date(startDate: anchor, week: w, day: d) ?? sampleDates[0]
            let backWeek = CourseOccurrences.week(startDate: anchor, date: dd) ?? 0
            let key = HolidayTransferOps.dayKey(dd)
            let short = DateUtils.shortDate(dd)
            return (parsed != nil ? 1 : 0) &+ backWeek &+ key.count &+ short.count
        }
    }

    func testBenchmarkAppPrefsHotReads() throws {
        try XCTSkipUnless(shouldRun, "Set SLEEPY_RUN_PERFORMANCE_TESTS=1")
        let suiteName = "RenderHotPathBenchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let prefs = AppPrefs(defaults: defaults)
        prefs.setVisibleDays(Set(1...7))
        prefs.setHolidayTransfers(101, [
            HolidayTransferEntry(
                sourceDate: DateUtils.parseDate("2026-10-01")!,
                targetDate: DateUtils.parseDate("2026-10-10")!,
                segmentId: "nd"
            )
        ])

        measureMedianMs(iterations: 1500, label: "app_prefs_1500") { _ in
            var acc = 0
            acc &+= Int(prefs.getGridScale() * 100)
            acc &+= Int(prefs.getGridCornerRatio() * 100)
            acc &+= prefs.isGridAdaptiveHeight() ? 1 : 0
            acc &+= prefs.isGridAutoHideEmptyEvening() ? 1 : 0
            acc &+= prefs.getGridEveningStart().count
            acc &+= prefs.isGridShowSeparators() ? 1 : 0
            acc &+= prefs.isGridLongBreakSpacing() ? 1 : 0
            acc &+= prefs.getPeriodHeaderStyle().count
            acc &+= prefs.getPeriodHeaderLayout().count
            acc &+= Int(prefs.getPeriodHeaderHanging() * 10)
            acc &+= prefs.isPeriodHeaderShowX() ? 1 : 0
            acc &+= prefs.getVisibleDays().count
            acc &+= prefs.getConflictStyle().count
            acc &+= prefs.isCourseColorless() ? 1 : 0
            acc &+= prefs.isGridUseAlias() ? 1 : 0
            acc &+= prefs.getHolidayTransfers(101).count
            return acc
        }
    }

    func testBenchmarkGridLayoutAndColorPipeline() throws {
        try XCTSkipUnless(shouldRun, "Set SLEEPY_RUN_PERFORMANCE_TESTS=1")
        let courses = makeFixtureCourses()
        let timeJson = TimeTableUtils.DEFAULT_TIME_JSON
        let slots = TimeTableUtils.renderSlots(timeJson: timeJson)
        let visibleDays = Set(1...7)
        let baseSlots = CourseDropCandidateLayout.visibleBaseSlots(
            allCourses: courses, timeSlots: slots, visibleDays: visibleDays,
            timeJson: timeJson, autoHideEmptyEvening: false, eveningStartMinutes: 18 * 60
        )

        measureMedianMs(iterations: 200, label: "grid_pipeline_200") { _ in
            let plan = TimeTableUtils.buildRenderSlotPlan(courses: courses, timeJson: timeJson, baseSlots: baseSlots)
            let w1 = threeLineWidthDp(slots: plan.slots, headerStyle: "arabic", scale: 1.0, hangingUnits: 0, showX: false)
            let w2 = legacyTimeWidthDp(slots: plan.slots, headerStyle: "arabic", scale: 1.0, showX: false, hideTime: false, centerTime: false)
            var sum = Int(w1 + w2)
            for c in courses {
                let group = courses.filter { $0.groupId == c.groupId }
                let bg = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
                    c, groupRows: group, isDark: false, neutralColor: .gray, colorless: false, persistedHue: nil
                )
                let _ = CourseColorUtil.textColorOn(bg: bg, isDark: false, onSurface: .black)
                sum &+= CourseDisplayUtil.displayName(c, false).count
                if let pair = TimeTableUtils.effectiveCourseTime(
                    isIrregularTime: c.ownTime, startTime: c.startTime, endTime: c.endTime,
                    startNode: c.startNode, step: c.step, timeJson: timeJson
                ) {
                    sum &+= pair.0.count
                }
            }
            return sum
        }
    }
}
