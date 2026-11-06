// ClassDayActivityCoreTests.swift — 实况活动分段纯逻辑单测 (v1.0.64)
// 由用户真机/CI 执行(用户令测试一律真机验证)。
import XCTest
@testable import Sleepy

final class ClassDayActivityCoreTests: XCTestCase {

    private func item(_ s: Int, _ e: Int) -> WatchAgendaCore.ClassItem {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return WatchAgendaCore.ClassItem(
            courseName: "c\(s)", room: "R", startLabel: "\(s)",
            startMin: s, endMin: e,
            startDate: base.addingTimeInterval(Double(s) * 60),
            endDate: base.addingTimeInterval(Double(e) * 60))
    }

    func testSegmentsBreakOnGapAboveThreshold() {
        let items = [item(480, 540), item(650, 720)]  // 间隔 110min > 60 → 断段
        let segs = ClassDayActivityCore.segments(from: items)
        XCTAssertEqual(segs.count, 2)
    }

    func testSegmentsKeepAdjacentClassesTogether() {
        let items = [item(480, 540), item(600, 660)]  // 间隔 60min = 阈值, 不断
        XCTAssertEqual(ClassDayActivityCore.segments(from: items).count, 1)
    }

    func testActiveSegmentPrefersRunningThenNext() {
        let items = [item(480, 540), item(600, 660)]
        // 10:05 (605min) 在第二段进行中
        let at605 = AccountForMinute(605)
        XCTAssertEqual(ClassDayActivityCore.activeSegment(from: items, now: at605)?.first?.startMin, 600)
        // 课后 17:00 (540) 前 → 最近未来段
        let at590 = AccountForMinute(590)
        XCTAssertEqual(ClassDayActivityCore.activeSegment(from: items, now: at590)?.first?.startMin, 600)
    }

    func testActiveSegmentNilAfterAllPast() {
        let items = [item(480, 540)]
        XCTAssertNil(ClassDayActivityCore.activeSegment(from: items, now: AccountForMinute(600)))
    }

    private func AccountForMinute(_ min: Int) -> Date {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(bySettingHour: 0, minute: 0, second: 0, of: Date())!
        return start.addingTimeInterval(Double(min) * 60)
    }
}
