// MigrationDatabaseCodecTests.swift — Android MigrationDatabaseCodec.kt 契约测试
// 锁定向前兼容契约: Kotlin `Json { ignoreUnknownKeys = true }` + 构造默认值使
// 缺省字段解码回落默认值; Swift 端手写 init(from:) 必须给出同一行为。
// (Android 侧无对应单测 — android_test=null, 本文件按 fix_hint 补契约锁。)

import XCTest
@testable import Sleepy

final class MigrationDatabaseCodecTests: XCTestCase {

    // MARK: - 最小必需字段包 → 缺省字段回落构造默认值

    func testCourseRowMissingDefaultedFieldsDecodesWithDefaults() throws {
        // 只保留 Kotlin 侧无默认值的字段: id/groupId/tableId/courseName/day/
        // startNode/step/startWeek/endWeek/color
        let minimal = """
        {"periodTables":[],"timeTables":[],"importDrafts":[],"courses":[
          {"id":1,"groupId":"g1","tableId":2,"courseName":"高数",
           "day":1,"startNode":1,"step":2,"startWeek":1,"endWeek":16,"color":"#FF0000"}
        ]}
        """
        let snap = try MigrationDatabaseCodec.decode(minimal)
        XCTAssertEqual(snap.courses.count, 1)
        let row = snap.courses[0]
        XCTAssertEqual(row.teacher, "")
        XCTAssertEqual(row.room, "")
        XCTAssertEqual(row.note, "")
        XCTAssertEqual(row.alias, "")
        XCTAssertEqual(row.type, 0)
        XCTAssertEqual(row.colorMode, 0)
        XCTAssertEqual(row.ownTime, false)
        XCTAssertEqual(row.isIrregularNode, false)
        XCTAssertEqual(row.isIrregularTime, false)
        XCTAssertEqual(row.startTime, "")
        XCTAssertEqual(row.endTime, "")
        XCTAssertEqual(row.credit, 0)
        XCTAssertEqual(row.level, 0)
        // 必需字段照常解码
        XCTAssertEqual(row.courseName, "高数")
        XCTAssertEqual(row.endWeek, 16)
    }

    func testTimeTableRowMissingDefaultedFieldsDecodesWithDefaults() throws {
        // Kotlin 无默认值字段: id/name/startDate/timeJson/createdAt
        let minimal = """
        {"timeTables":[
          {"id":3,"name":"2026 春","startDate":"2026-02-23","timeJson":"[]","createdAt":100}
        ],"periodTables":[],"courses":[],"importDrafts":[]}
        """
        let snap = try MigrationDatabaseCodec.decode(minimal)
        let row = try XCTUnwrap(snap.timeTables.first)
        XCTAssertEqual(row.maxWeek, 20)
        XCTAssertEqual(row.nodesPerDay, 12)
        XCTAssertEqual(row.color, "#FF6750A4")
        XCTAssertEqual(row.isDefault, false)
        XCTAssertEqual(row.smartConfigJson, "")
        XCTAssertEqual(row.periodTableId, nil)
        XCTAssertEqual(row.preBindSnapshotJson, "")
    }

    func testTimeTableRowNullPeriodTableIdDecodesAsNil() throws {
        // 显式 null: decodeIfPresent → nil (与 Kotlin Long? = null 解码 JSON null 一致)
        let text = """
        {"timeTables":[
          {"id":3,"name":"t","startDate":"2026-02-23","timeJson":"[]","createdAt":1,
           "periodTableId":null}
        ]}
        """
        let snap = try MigrationDatabaseCodec.decode(text)
        XCTAssertNil(snap.timeTables[0].periodTableId)
    }

    func testPeriodTableRowMissingDefaultedFieldsDecodesWithDefaults() throws {
        // Kotlin 无默认值字段: id/name/timeJson/createdAt/updatedAt
        let minimal = """
        {"periodTables":[
          {"id":4,"name":"节次表","timeJson":"[]","createdAt":1,"updatedAt":2}
        ]}
        """
        let snap = try MigrationDatabaseCodec.decode(minimal)
        let row = try XCTUnwrap(snap.periodTables.first)
        XCTAssertEqual(row.nodesPerDay, 12)
        XCTAssertEqual(row.smartConfigJson, "")
    }

    func testImportDraftRowMissingDefaultedFieldsDecodesWithDefaults() throws {
        // Kotlin 无默认值字段: id/payloadJson/createdAt/updatedAt
        let minimal = """
        {"importDrafts":[
          {"id":"d1","payloadJson":"{}","createdAt":1,"updatedAt":2}
        ]}
        """
        let snap = try MigrationDatabaseCodec.decode(minimal)
        let row = try XCTUnwrap(snap.importDrafts.first)
        XCTAssertEqual(row.sourceType, "")
        XCTAssertEqual(row.sourceUrl, "")
    }

    func testEmptyObjectDecodesAsEmptySnapshot() throws {
        // 四数组全缺 → emptyList 默认值。更早版本/手工裁剪的包含 `{}` 时
        // Android 可解, iOS 此前必失败 — 本条即回归锁。
        let snap = try MigrationDatabaseCodec.decode("{}")
        XCTAssertTrue(snap.periodTables.isEmpty)
        XCTAssertTrue(snap.timeTables.isEmpty)
        XCTAssertTrue(snap.courses.isEmpty)
        XCTAssertTrue(snap.importDrafts.isEmpty)
    }

    // MARK: - 未知键忽略 (ignoreUnknownKeys = true 等价)

    func testUnknownKeysAreIgnored() throws {
        let text = """
        {"periodTables":[],"timeTables":[],"importDrafts":[],"courses":[
          {"id":1,"groupId":"g","tableId":2,"courseName":"c","day":1,"startNode":1,
           "step":1,"startWeek":1,"endWeek":18,"color":"#FFF",
           "futureField":"added in v2","futureObj":{"a":1}}
        ]}
        """
        let snap = try MigrationDatabaseCodec.decode(text)
        XCTAssertEqual(snap.courses.count, 1)
        XCTAssertEqual(snap.courses[0].endWeek, 18)
    }

    // MARK: - 仍须抛错的行为 (与 Kotlin 默认 Json 配置一致, 不许放宽)

    func testMissingRequiredFieldStillThrows() {
        // courseName 在 Kotlin 无默认值 → 缺键必须失败
        let text = """
        {"courses":[{"id":1,"groupId":"g","tableId":2,"day":1,"startNode":1,
                     "step":1,"startWeek":1,"endWeek":18,"color":"#FFF"}]}
        """
        XCTAssertThrowsError(try MigrationDatabaseCodec.decode(text)) { error in
            guard case DecodingError.keyNotFound(let key, _) = error else {
                return XCTFail("期望 keyNotFound, 实得 \(error)")
            }
            XCTAssertEqual(key.stringValue, "courseName")
        }
    }

    func testWrongTypeForDefaultedFieldStillThrows() {
        // coerceInputValues=false(Kotlin 默认) → 存在但类型不符必须失败,
        // 不许 decodeIfPresent 语义被误写成"吞错回落默认值"
        let text = """
        {"courses":[{"id":1,"groupId":"g","tableId":2,"courseName":"c","day":1,
                     "startNode":1,"step":1,"startWeek":1,"endWeek":18,"color":"#FFF",
                     "type":"not-an-int"}]}
        """
        XCTAssertThrowsError(try MigrationDatabaseCodec.decode(text))
    }

    func testWrongTypeForRequiredFieldStillThrows() {
        let text = """
        {"courses":[{"id":"not-a-long","groupId":"g","tableId":2,"courseName":"c",
                     "day":1,"startNode":1,"step":1,"startWeek":1,"endWeek":18,
                     "color":"#FFF"}]}
        """
        XCTAssertThrowsError(try MigrationDatabaseCodec.decode(text))
    }

    // MARK: - encode 写全字段 + 全量 round-trip (encodeDefaults = true)

    func testEncodeWritesAllFieldsIncludingDefaults() throws {
        let row = MigrationDatabaseCodec.CourseRow(
            id: 1, groupId: "g1", tableId: 2, courseName: "高数",
            teacher: "王老师", room: "21B2086", note: "", alias: "",
            day: 2, startNode: 3, step: 3, startWeek: 2, endWeek: 8,
            type: 0, color: "#FF6750A4", colorMode: 0, ownTime: false,
            isIrregularNode: false, isIrregularTime: false,
            startTime: "", endTime: "", credit: 4.5, level: 0
        )
        let snap = MigrationDatabaseCodec.DatabaseSnapshot(
            periodTables: [], timeTables: [], courses: [row], importDrafts: []
        )
        let text = try MigrationDatabaseCodec.encode(snap)
        // 双端 encode 都写全字段 → release 内互导安全的前提。抽查带默认值字段。
        for key in ["teacher", "room", "note", "alias", "type", "colorMode",
                    "ownTime", "isIrregularNode", "isIrregularTime", "startTime",
                    "endTime", "credit", "level"] {
            XCTAssertTrue(text.contains("\"\(key)\""), "encode 应写全字段, 缺 \(key)")
        }
        let back = try MigrationDatabaseCodec.decode(text)
        XCTAssertEqual(back.courses, snap.courses)
    }

    func testFullSnapshotRoundTripPreservesFields() throws {
        let period = MigrationDatabaseCodec.PeriodTableRow(
            id: 10, name: "常规", nodesPerDay: 12,
            timeJson: #"[{"node":1,"start":"08:00","end":"08:45"}]"#,
            smartConfigJson: #"{"enabled":false}"#, createdAt: 1, updatedAt: 2
        )
        let table = MigrationDatabaseCodec.TimeTableRow(
            id: 20, name: "2026 春", startDate: "2026-02-23", maxWeek: 18,
            nodesPerDay: 13, timeJson: "[]", color: "#FF6750A4", isDefault: true,
            smartConfigJson: "", createdAt: 3, periodTableId: 10,
            preBindSnapshotJson: "{}"
        )
        let course = MigrationDatabaseCodec.CourseRow(
            id: 30, groupId: "g", tableId: 20, courseName: "英语", teacher: "李",
            room: "A101", note: "n", alias: "a", day: 5, startNode: 7, step: 2,
            startWeek: 1, endWeek: 16, type: 1, color: "#123456", colorMode: 2,
            ownTime: true, isIrregularNode: true, isIrregularTime: true,
            startTime: "16:00", endTime: "17:40", credit: 3.0, level: 1
        )
        let draft = MigrationDatabaseCodec.ImportDraftRow(
            id: "draft-1", sourceType: "jw", sourceUrl: "https://x",
            payloadJson: "{}", createdAt: 4, updatedAt: 5
        )
        let snap = MigrationDatabaseCodec.DatabaseSnapshot(
            periodTables: [period], timeTables: [table], courses: [course],
            importDrafts: [draft]
        )
        let text = try MigrationDatabaseCodec.encode(snap)
        let back = try MigrationDatabaseCodec.decode(text)
        XCTAssertEqual(back.periodTables, [period])
        XCTAssertEqual(back.timeTables, [table])
        XCTAssertEqual(back.courses, [course])
        XCTAssertEqual(back.importDrafts, [draft])
    }
}
