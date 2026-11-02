// ImportedPeriodTableDraftTests.swift — ← util/ImportedPeriodTableDraftTest.kt (v1.0.62 B7b)
// 导入新建课表的作息表草稿纯函数三例: 确认行 owns 新表 / 选中共享不新建 / 各次导入草稿独立。

import XCTest
@testable import Sleepy

final class ImportedPeriodTableDraftTests: XCTestCase {

    private let confirmed = "[{\"node\":1,\"start\":\"09:10\",\"end\":\"10:00\"},{\"node\":2,\"start\":\"10:15\",\"end\":\"11:05\"}]"

    func testConfirmedRowsOwnNewScheduleAndCount() throws {
        let draft = try XCTUnwrap(importedPeriodTableDraft(bindingId: nil,
                                                           name: "Imported",
                                                           confirmedTimeJson: confirmed))
        XCTAssertEqual("Imported", draft.name)
        XCTAssertEqual(confirmed, draft.timeJson)
        XCTAssertEqual(2, draft.nodesPerDay)
        XCTAssertEqual("09:10", TimeTableUtils.parseTimeSlotRows(draft.timeJson).first?.start)
    }

    func testExplicitSharedBindingDoesNotCreateOrOverwritePeriodTable() {
        XCTAssertNil(importedPeriodTableDraft(bindingId: 7, name: "Imported", confirmedTimeJson: confirmed))
    }

    func testSeparateImportsHaveIndependentUnsavedDrafts() throws {
        let a = try XCTUnwrap(importedPeriodTableDraft(bindingId: nil, name: "A", confirmedTimeJson: confirmed))
        let b = try XCTUnwrap(importedPeriodTableDraft(bindingId: nil, name: "B",
                                                       confirmedTimeJson: confirmed.replacingOccurrences(of: "09:10", with: "09:20")))
        XCTAssertEqual(0, a.id)
        XCTAssertEqual(0, b.id)
        XCTAssertEqual("09:10", TimeTableUtils.parseTimeSlotRows(a.timeJson).first?.start)
        XCTAssertEqual("09:20", TimeTableUtils.parseTimeSlotRows(b.timeJson).first?.start)
    }
}
