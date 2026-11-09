import XCTest
@testable import Sleepy

final class JwImportLifecycleTests: XCTestCase {
    private let snapshot = JwImportDraftSnapshot(
        school: JwSchoolInfo(sortKey: "T", name: "Test school"),
        courses: [JwCourse(name: "Math", day: 1, startNode: 1, endNode: 2, startWeek: 1, endWeek: 16)],
        periods: [], tableName: "Parsed snapshot")

    func testRestoredUnverifiedLoginWaitsForCatalogConfirmation() {
        let school = JwSchoolInfo(sortKey: "T", name: "Unverified school", url: "https://jw.example.edu/",
                                  type: "zf_new", status: JwSchoolInfo.STATUS_UNVERIFIED)
        let snapshot = JwImportDraftSnapshot(school: school, courses: [], periods: [], phase: .webViewLogin)
        for newTableOnly in [false, true] {
            let route = JwImportEntryRoute(snapshot: snapshot, newTableOnly: newTableOnly)
            XCTAssertTrue(school.canImport)
            XCTAssertEqual(route.stage, .selectSchool)
            XCTAssertEqual(route.catalogNotice, school)
        }
    }

    func testRestoredUnavailableLoginCannotOpenWebView() {
        let schools = [
            JwSchoolInfo(sortKey: "T", name: "Pending school", url: "https://jw.example.edu/",
                         type: "zf_new", status: JwSchoolInfo.STATUS_PENDING),
            JwSchoolInfo(sortKey: "T", name: "Missing URL", type: "zf_new"),
            JwSchoolInfo(sortKey: "T", name: "Unknown protocol", url: "https://jw.example.edu/",
                         type: "unknown-protocol", status: JwSchoolInfo.STATUS_UNVERIFIED)
        ]
        for school in schools {
            let snapshot = JwImportDraftSnapshot(school: school, courses: [], periods: [], phase: .webViewLogin)
            let route = JwImportEntryRoute(snapshot: snapshot, newTableOnly: true)
            XCTAssertFalse(school.canImport)
            XCTAssertEqual(route.stage, .selectSchool)
            XCTAssertEqual(route.catalogNotice, school)
        }
    }

    func testRestoredSupportedLoginOpensWebViewWithoutNotice() {
        let school = JwSchoolInfo(sortKey: "T", name: "Supported school", url: "https://jw.example.edu/", type: "zf_new")
        let snapshot = JwImportDraftSnapshot(school: school, courses: [], periods: [], phase: .webViewLogin)
        let route = JwImportEntryRoute(snapshot: snapshot, newTableOnly: true)
        XCTAssertEqual(route.stage, .webViewLogin)
        XCTAssertNil(route.catalogNotice)
    }

    func testParsedDraftKeepsItsConfiguredFlowWithoutRepeatingSchoolNotice() {
        var parsed = snapshot
        parsed.school = JwSchoolInfo(sortKey: "T", name: "Unverified school", url: "https://jw.example.edu/",
                                     type: "zf_new", status: JwSchoolInfo.STATUS_UNVERIFIED)
        let newTable = JwImportEntryRoute(snapshot: parsed, newTableOnly: true)
        XCTAssertEqual(newTable.stage, .configureConfirm)
        XCTAssertNil(newTable.catalogNotice)
        let addingCourses = JwImportEntryRoute(snapshot: parsed, newTableOnly: false)
        XCTAssertEqual(addingCourses.stage, .preview)
        XCTAssertNil(addingCourses.catalogNotice)
    }

    func testSupportedSchoolSelectionOpensWebViewWithoutNotice() {
        for status in [JwSchoolInfo.STATUS_SUPPORTED, JwSchoolInfo.STATUS_GRAD_SUPPORTED] {
            let school = JwSchoolInfo(sortKey: "T", name: "Supported school", url: "https://jw.example.edu/",
                                      type: "qz", status: status)
            let route = JwImportEntryRoute(school: school)
            XCTAssertEqual(route.stage, .webViewLogin)
            XCTAssertNil(route.catalogNotice)
        }
    }

    func testUnverifiedAndUnavailableSchoolSelectionWaitsForNotice() {
        for status in [JwSchoolInfo.STATUS_UNVERIFIED, JwSchoolInfo.STATUS_GRAD_UNVERIFIED,
                       JwSchoolInfo.STATUS_PENDING, JwSchoolInfo.STATUS_GRAD_PENDING, JwSchoolInfo.STATUS_LEGACY] {
            let school = JwSchoolInfo(sortKey: "T", name: "Catalog school", url: "https://jw.example.edu/",
                                      type: "qz", status: status)
            let route = JwImportEntryRoute(school: school)
            XCTAssertEqual(route.stage, .selectSchool, status)
            XCTAssertEqual(route.catalogNotice, school, status)
        }
        let missingURL = JwSchoolInfo(sortKey: "T", name: "Missing URL", type: "qz")
        let route = JwImportEntryRoute(school: missingURL)
        XCTAssertEqual(route.stage, .selectSchool)
        XCTAssertEqual(route.catalogNotice, missingURL)
    }

    func testCatalogConfirmationOnlyAdmitsAvailableUnverifiedSchool() {
        let cases: [(JwSchoolInfo, Bool)] = [
            (.init(sortKey: "T", name: "Unverified", url: "https://jw.example.edu/", type: "qz",
                   status: JwSchoolInfo.STATUS_UNVERIFIED), true),
            (.init(sortKey: "T", name: "Graduate unverified", url: "https://jw.example.edu/", type: "qz",
                   status: JwSchoolInfo.STATUS_GRAD_UNVERIFIED), true),
            (.init(sortKey: "T", name: "Pending", url: "https://jw.example.edu/", type: "qz",
                   status: JwSchoolInfo.STATUS_PENDING), false),
            (.init(sortKey: "T", name: "Unsupported", url: "https://jw.example.edu/", type: "unknown-protocol",
                   status: JwSchoolInfo.STATUS_UNVERIFIED), false),
            (.init(sortKey: "T", name: "Missing URL", type: "qz",
                   status: JwSchoolInfo.STATUS_UNVERIFIED), false)
        ]
        for (school, mayTry) in cases {
            let route = JwImportEntryRoute(school: school, acceptedCatalogNotice: true)
            XCTAssertEqual(route.stage, mayTry ? .webViewLogin : .selectSchool, school.name)
            XCTAssertNil(route.catalogNotice, school.name)
        }
    }

    func testNewParseAndFlowExitRejectEarlierAsyncReplies() {
        var lifecycle = JwImportParseLifecycle()
        let old = lifecycle.beginParse()
        let current = lifecycle.beginParse()
        XCTAssertFalse(lifecycle.accepts(old, didFinishFlow: false))
        XCTAssertTrue(lifecycle.accepts(current, didFinishFlow: false))
        XCTAssertFalse(lifecycle.accepts(current, didFinishFlow: true))
        lifecycle.invalidate()
        XCTAssertFalse(lifecycle.accepts(current, didFinishFlow: false))
    }

    func testDeleteDraftRemovesAnAutosaveThatCompletesAfterExit() throws {
        let repository = ImportDraftRepository(try AppDatabase.inMemory())
        var lifecycle = JwImportParseLifecycle()
        let epoch = lifecycle.beginParse()
        lifecycle.invalidate(keepingDraft: false)
        let lateId = try repository.save(snapshot)
        XCTAssertFalse(lifecycle.accepts(epoch, didFinishFlow: true))
        XCTAssertTrue(lifecycle.shouldDeleteLateSave(lateId, retainedDraftId: nil))
        if lifecycle.shouldDeleteLateSave(lateId, retainedDraftId: nil) {
            try repository.delete(lateId)
        }
        XCTAssertTrue(try repository.getAll().isEmpty)
    }

    func testKeepDraftRetainsLatestSnapshotAndRemovesOnlyTheDiscardedAutosave() throws {
        let repository = ImportDraftRepository(try AppDatabase.inMemory())
        var lifecycle = JwImportParseLifecycle()
        _ = lifecycle.beginParse()
        var latest = snapshot
        latest.tableName = "Kept user changes"
        let keptId = try repository.save(latest)
        lifecycle.invalidate(keepingDraft: true)
        let lateId = try repository.save(snapshot)
        XCTAssertFalse(lifecycle.shouldDeleteLateSave(keptId, retainedDraftId: keptId))
        XCTAssertTrue(lifecycle.shouldDeleteLateSave(lateId, retainedDraftId: keptId))
        if lifecycle.shouldDeleteLateSave(lateId, retainedDraftId: keptId) {
            try repository.delete(lateId)
        }
        XCTAssertEqual(try repository.getAll().map(\.id), [keptId])
        XCTAssertEqual(try repository.get(keptId), latest)
    }

    func testKeepDraftFallsBackToPendingAutosaveIfItsExplicitSaveFailed() {
        var lifecycle = JwImportParseLifecycle()
        _ = lifecycle.beginParse()
        lifecycle.invalidate(keepingDraft: true)
        XCTAssertFalse(lifecycle.shouldDeleteLateSave("pending-save", retainedDraftId: nil))
    }

    func testSupersededParseDiscardsItsUnadoptedAutosave() {
        var lifecycle = JwImportParseLifecycle()
        let old = lifecycle.beginParse()
        _ = lifecycle.beginParse()
        XCTAssertFalse(lifecycle.accepts(old, didFinishFlow: false))
        XCTAssertTrue(lifecycle.shouldDeleteLateSave("old-save", retainedDraftId: "current-save"))
    }
}
