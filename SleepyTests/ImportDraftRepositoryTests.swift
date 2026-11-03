// ImportDraftRepositoryTests.swift — 原版本 ImportDraftRepository 行为测试 (GPL-3.0)
// save/get/update/delete 走真实 GRDB 库 + 真实 codec (不 mock)。

import XCTest
@testable import Sleepy

final class ImportDraftRepositoryTests: XCTestCase {
    private func makeRepo() throws -> (AppDatabase, ImportDraftRepository) {
        let db = try AppDatabase.inMemory()
        return (db, ImportDraftRepository(db))
    }

    private static let snapshot = JwImportDraftSnapshot(
        school: JwSchoolInfo(sortKey: "Q", name: "示例大学"),
        courses: [JwCourse(name: "高数", day: 1, startNode: 1, endNode: 2, startWeek: 1, endWeek: 16)],
        periods: [JwImportDraftPeriod(node: 1, start: "08:00", end: "08:45")]
    )

    func testSaveGetUpdateDelete() throws {
        let (_, repo) = try makeRepo()
        let id = try repo.save(Self.snapshot, sourceType: "jw", sourceUrl: "https://jw.example")
        XCTAssertFalse(id.isEmpty)

        let got = try repo.get(id)
        XCTAssertEqual(Self.snapshot, got, "codec 往返完整")

        // update 后 payload 刷新, 元信息保留
        var mutated = Self.snapshot
        mutated.tableName = "秋季"
        try repo.update(id, mutated)
        XCTAssertEqual(mutated, try repo.get(id))

        // update 不存在的 id = 静默 no-op (Kotlin `?: return`)
        try repo.update("missing", mutated)

        let all = try repo.getAll()
        XCTAssertEqual(1, all.count)
        XCTAssertEqual("jw", all[0].sourceType)

        try repo.delete(id)
        XCTAssertNil(try repo.get(id), "删除后 get = nil")
        XCTAssertEqual(0, try repo.getAll().count)
    }

    func testGetReturnsNilForUnknownId() throws {
        let (_, repo) = try makeRepo()
        XCTAssertNil(try repo.get("nope"))
    }
}
