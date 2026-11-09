import XCTest
@testable import Sleepy

final class ImportPreviewSessionTests: XCTestCase {
    private func preview(course: String, table: String = "外部课表") throws -> ImportPreview {
        let text = "#sleepy-v1\nT\(table)|2026-11-02|16|12\nC\(course)|1|1-2|1-16"
        let parsed = try ScheduleParser.parse(text, defaultTableId: 0).get()
        return ImportPreview(targetTableId: 0, targetTableName: "", parseResult: parsed,
                             existingCourses: [], conflicts: [])
    }

    func testSecondDocumentClearsPreviousConfirmationAndAllEditedFields() throws {
        let first = try preview(course: "数学")
        let second = try preview(course: "物理")
        var session = ImportPreviewSession()
        session.replacePreview(first)
        session.pendingMode = .importAsNew
        session.confirmedPreview = first
        session.confirmedTableName = "旧文档的编辑名"
        session.confirmedStartDate = "2026-09-01"
        session.confirmedTimeJson = "old-private-times"
        session.confirmedBindPeriodTableId = 42

        session.replacePreview(second)
        XCTAssertEqual(session.preview?.parseResult.courses.map(\.courseName), ["物理"])
        XCTAssertNil(session.pendingMode, "The new document must return to its own preview")
        XCTAssertNil(session.confirmedPreview, "The previous confirmation must no longer be actionable")
        XCTAssertEqual(session.confirmedTableName, "")
        XCTAssertEqual(session.confirmedStartDate, "")
        XCTAssertEqual(session.confirmedTimeJson, "")
        XCTAssertNil(session.confirmedBindPeriodTableId)
    }

    func testInvalidOrShareDeliveryClearsOldPreviewBeforeItsOwnFlow() throws {
        let first = try preview(course: "数学")
        var session = ImportPreviewSession()
        session.replacePreview(first)
        session.pendingMode = .replaceCurrent
        session.confirmedPreview = first
        session.confirmedBindPeriodTableId = 42
        session.replacePreview(nil)
        XCTAssertNil(session.preview)
        XCTAssertNil(session.pendingMode)
        XCTAssertNil(session.confirmedPreview)
        XCTAssertNil(session.confirmedBindPeriodTableId)
    }

    func testDifferentDocumentsWithSameTitleAndCountsHaveDistinctStableIdentities() throws {
        let first = try preview(course: "数学")
        let second = try preview(course: "物理")
        XCTAssertEqual(first.parseResult.tableName, second.parseResult.tableName)
        XCTAssertEqual(first.parseResult.courses.count, second.parseResult.courses.count)
        XCTAssertNotEqual(first.id, second.id, "A second document must replace the rendered sheet even when its metadata matches")
        var session = ImportPreviewSession()
        session.replacePreview(first)
        let identity = session.preview?.id
        session.pendingMode = .importAsNew
        session.confirmedTableName = "重命名"
        XCTAssertEqual(session.preview?.id, identity, "Editing confirmation must not recreate the preview presentation")
        session.replacePreview(second)
        XCTAssertEqual(session.preview?.id, second.id)
        XCTAssertNotEqual(session.preview?.id, identity)
    }
}
