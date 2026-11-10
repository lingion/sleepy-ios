import XCTest
@testable import Sleepy

final class Jw1064SourceContractTests: XCTestCase {
    func testMissingNullAndExplicitZeroRemainDistinct() throws {
        let source = #"{"sleepySgAsset":true,"coursesJson":"[]","config":{"semesterStartDate":null,"defaultBreakDuration":0},"adapter":{"adapterId":"test"}}"#
        let metadata = try JwSgSourceMetadata.capture(source, JwProtocol.TYPE_SG_ASSET)
        let root = try XCTUnwrap(JwSgSourceMetadata.read(metadata))
        let config = try XCTUnwrap(root["config"] as? [String: Any])
        XCTAssertTrue(config["semesterStartDate"] is NSNull)
        XCTAssertEqual(config["defaultBreakDuration"] as? Int, 0)
        XCTAssertNil(config["defaultClassDuration"])
        XCTAssertEqual(JwSourceCalendar.resolveStartDate(source, JwProtocol.TYPE_SG_ASSET, capturedDate: "2026-09-07"), "")
    }

    func testInvalidExternalSourceMetadataIsRejected() {
        for config in [#"{"semesterStartDate":"2026-02-30"}"#, #"{"semesterTotalWeeks":0}"#,
                       #"{"semesterTotalWeeks":"20"}"#, #"{"firstDayOfWeek":true}"#,
                       #"{"defaultClassDuration":1.5}"#, #"{"defaultClassDuration":1.0}"#,
                       #"{"defaultClassDuration":1e0}"#, #"{"defaultBreakDuration":-1}"#] {
            XCTAssertNil(JwSgSourceMetadata.read("{\"schemaVersion\":1,\"config\":" + config + "}"))
        }
    }

    func testActualTimeAndSparseWeeksSurviveSourceAndDraft() throws {
        let payload = #"[{"name":"实验","isCustomTime":true,"customStartTime":"08:15","customEndTime":"09:40","day":2,"weeks":[1,5],"credit":1.5}]"#
        let courses = try JwSgAssetParser(payload).generateCourseList()
        XCTAssertEqual(courses.map(\.startWeek), [1, 5])
        XCTAssertTrue(courses.allSatisfy { $0.startWeek == $0.endWeek && $0.hasActualTime && $0.credit == 1.5 })
        let snapshot = JwImportDraftSnapshot(school: JwSchoolInfo(sortKey: "T", name: "测试"), courses: courses, periods: [], termWeekCount: 22, termWeekText: "022")
        XCTAssertEqual(JwImportDraftCodec.fromJson(JwImportDraftCodec.toJson(snapshot)), snapshot)
    }

    func testConfirmationRetainsUnusedSourcePeriods() {
        let rows = JwSourcePeriods.confirmationRows(courseMaxNode: 2, sourcePeriods: [(1, "08:00", "08:45"), (4, "11:00", "11:45")])
        XCTAssertEqual(rows.map { $0.0 }, [1, 2, 3, 4])
        XCTAssertEqual(rows.last?.1, "11:00")
    }

    func testRecentSuccessfulSchoolsPreserveStableIdentityAndOrder() {
        XCTAssertEqual(RecentJwSchools.merge(["a", "b", "a", "c"], importedKey: "b"), ["b", "a", "c"])
        let schools = [JwSchoolInfo(sortKey: "A", name: "重命名学校", catalogId: "a")]
        XCTAssertEqual(RecentJwSchools.resolve(["missing", "a"], schools: schools).map(\.name), ["重命名学校"])
    }

    func testFetchBudgetPausesWhileWaitingAndRejectsOldResults() {
        var clock: TimeInterval = 100
        let budget = JwFetchBudget(now: { clock })
        budget.begin(id: "new", timeout: 20)
        clock = 105; budget.setWaiting(id: "new", waiting: true)
        clock = 500; XCTAssertNil(budget.remainingSeconds(id: "new"))
        budget.setWaiting(id: "new", waiting: false)
        clock = 505; XCTAssertEqual(budget.remainingSeconds(id: "new"), 10)
        XCTAssertFalse(budget.complete(id: "old"))
        XCTAssertTrue(budget.complete(id: "new"))
        XCTAssertNil(budget.captureId)
    }
}
