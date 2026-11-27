import Foundation
import GRDB
import XCTest
@testable import Sleepy

final class WeekCountRecoveryTests: XCTestCase {
    private let fixture = """
    {
      "timeTables": [
        {"id":11,"name":"Fall","startDate":"2026-08-31","timeJson":"[]","createdAt":1,"maxWeek":0,"isDefault":true},
        {"id":12,"name":"Empty","startDate":"2026-08-31","timeJson":"[]","createdAt":2,"maxWeek":-3},
        {"id":13,"name":"Short","startDate":"2026-08-31","timeJson":"[]","createdAt":3,"maxWeek":4}
      ],
      "courses": [
        {"id":81,"groupId":"g","tableId":11,"courseName":"Early","day":1,"startNode":1,"step":1,"startWeek":1,"endWeek":3,"color":"#112233"},
        {"id":82,"groupId":"g2","tableId":11,"courseName":"Late","day":2,"startNode":1,"step":1,"startWeek":2,"endWeek":17,"color":"#112233"},
        {"id":83,"groupId":"g3","tableId":13,"courseName":"Other","day":3,"startNode":1,"step":1,"startWeek":1,"endWeek":22,"color":"#112233"}
      ]
    }
    """

    func testReopeningRepairsLegacyRowsWithoutChangingIdentity() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("legacy.db")
        let snapshot = try MigrationDatabaseCodec.decode(fixture)
        do {
            let db = try AppDatabase(persistentURL: url)
            try db.dbQueue.write { connection in
                for row in snapshot.timeTables {
                    try db.timeTableDao.insertInDb(connection, MigrationDatabaseCodec.toEntity(row))
                }
                for row in snapshot.courses {
                    try db.courseDao.insertKeepIdInDb(connection, MigrationDatabaseCodec.toEntity(row))
                }
            }
            XCTAssertEqual(try db.timeTableDao.getById(11)?.maxWeek, 0)
        }

        for _ in 0..<2 {
            let db = try AppDatabase(persistentURL: url)
            try assertRepaired(db, ids: [11: 11, 12: 12, 13: 13])
            XCTAssertEqual(try db.timeTableDao.getDefault()?.id, 11)
            XCTAssertEqual(Set(try db.courseDao.getByTable(11).map(\.id)), [81, 82])
        }
    }

    func testOverwriteRepairsBeforeReturning() throws {
        let db = try AppDatabase.inMemory()
        try MigrationDatabaseCodec.applyOverwrite(
            MigrationDatabaseCodec.decode(fixture),
            courseDao: db.courseDao, timeTableDao: db.timeTableDao, periodTableDao: db.periodTableDao,
            importDraftDao: db.importDraftDao, dbQueue: db.dbQueue
        )
        try assertRepaired(db, ids: [11: 11, 12: 12, 13: 13])
        XCTAssertEqual(try db.timeTableDao.getDefault()?.id, 11)
        XCTAssertEqual(Set(try db.courseDao.getByTable(11).map(\.id)), [81, 82])
    }

    func testMergeRepairsNewIDsWithoutChangingLocalSelection() throws {
        let db = try AppDatabase.inMemory()
        let local = try db.timeTableDao.insert(TimeTableEntity(
            name: "Local", startDate: "2026-08-31", maxWeek: 15, isDefault: true, id: 11
        ))
        let ids = try MigrationDatabaseCodec.applyMerge(
            MigrationDatabaseCodec.decode(fixture),
            courseDao: db.courseDao, timeTableDao: db.timeTableDao, periodTableDao: db.periodTableDao,
            importDraftDao: db.importDraftDao, dbQueue: db.dbQueue
        )
        try assertRepaired(db, ids: ids)
        XCTAssertNotEqual(ids[11], local)
        XCTAssertEqual(try db.timeTableDao.getDefault()?.id, local)
        XCTAssertEqual(try db.timeTableDao.getById(local)?.maxWeek, 15)
    }

    private func assertRepaired(_ db: AppDatabase, ids: [Int64: Int64]) throws {
        let fall = try XCTUnwrap(ids[11])
        let empty = try XCTUnwrap(ids[12])
        let short = try XCTUnwrap(ids[13])
        XCTAssertEqual(try db.timeTableDao.getById(fall)?.maxWeek, 17)
        XCTAssertEqual(try db.timeTableDao.getById(empty)?.maxWeek, 1)
        XCTAssertEqual(try db.timeTableDao.getById(short)?.maxWeek, 4)
        XCTAssertEqual(Set(try db.courseDao.getByTable(fall).map(\.courseName)), ["Early", "Late"])
        XCTAssertEqual(try db.courseDao.getByTable(short).first?.endWeek, 22)
    }
}
