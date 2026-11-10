import XCTest
import GRDB
import Combine
@testable import Sleepy

final class Android1064DataParityTests: XCTestCase {
    private func course(_ table: Int64 = 1, name: String = "Math", day: Int = 1, node: Int = 1) -> CourseEntity {
        CourseEntity(groupId: "g", tableId: table, courseName: name, day: day,
            startNode: node, step: 1, startWeek: 1, endWeek: 16, color: "#FF123456")
    }
    func testReminderAutomaticallyFollowsSelectionAndRetainsLegacyDisabled() throws {
        var a = TimeTableEntity(name: "A", startDate: "2026-09-07", id: 1)
        let b = TimeTableEntity(name: "B", startDate: "2026-09-07", id: 2)
        XCTAssertEqual(resolveReminderTableScope(tables: [a,b], selectedTableId: 2).map(\.reminderEnabled), [false,true])
        a.reminderEnabled = false
        XCTAssertEqual(resolveReminderTableScope(tables: [a,b], selectedTableId: 1).map(\.reminderEnabled), [false,false])
    }
    func testFirstManualChoiceFreezesAllRowsAndNewRowsRemainUnselected() throws {
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let a = try repo.insertTable(TimeTableEntity(name: "A", startDate: "2026-09-07"))
        let b = try repo.insertTable(TimeTableEntity(name: "B", startDate: "2026-09-07"))
        try repo.setTableReminderEnabled(id: b, enabled: true)
        try repo.setDefault(b)
        _ = try repo.insertTable(TimeTableEntity(name: "C", startDate: "2026-09-07"))
        let enabled = try repo.getReminderTables().filter(\.reminderEnabled).map(\.id)
        XCTAssertEqual(Set(enabled), Set([a,b]))
        try repo.setTableReminderEnabled(id: a, enabled: false)
        try repo.setTableReminderEnabled(id: b, enabled: false)
        try repo.setDefault(a)
        XCTAssertTrue(try repo.getReminderTables().allSatisfy { !$0.reminderEnabled })
    }
    func testSourceAndScopeSurviveBackupEntityRoundTrip() throws {
        let source = #"{"schoolKey":"ＦＯＯ/１","startDate":null,"unknown":{"x":2}}"#
        let t = TimeTableEntity(name: "T", startDate: "2026-09-07", reminderEnabled: false, reminderOverride: false, importSourceJson: source, id: 4)
        let row = MigrationDatabaseCodec.toRow(t)
        let decoded = try JSONDecoder().decode(MigrationDatabaseCodec.TimeTableRow.self, from: JSONEncoder().encode(row))
        let restored = MigrationDatabaseCodec.toEntity(decoded)
        XCTAssertEqual(restored.importSourceJson, source)
        XCTAssertEqual(restored.reminderOverride, false)
        XCTAssertFalse(restored.reminderEnabled)
        let legacy = #"{"id":1,"name":"Old","startDate":"2026-09-07","timeJson":"[]","createdAt":0}"#.data(using: .utf8)!
        let old = try JSONDecoder().decode(MigrationDatabaseCodec.TimeTableRow.self, from: legacy)
        XCTAssertNil(old.reminderOverride)
        XCTAssertEqual(old.importSourceJson, "")
    }
    func testBackupMergePreservesLocalAutomaticAndManualReminderSelection() throws {
        for localOverride: Bool? in [nil, false, true] {
            for importedOverride in [false, true] {
                let db = try AppDatabase.inMemory()
                let localId = try db.timeTableDao.insert(TimeTableEntity(name: "Local", startDate: "2026-09-07",
                    isDefault: true, reminderOverride: localOverride))
                let incoming = TimeTableEntity(name: "Imported", startDate: "2026-09-07", isDefault: true,
                    reminderOverride: importedOverride, importSourceJson: "opaque source", id: 99)
                let snapshot = MigrationDatabaseCodec.DatabaseSnapshot(timeTables: [MigrationDatabaseCodec.toRow(incoming)])
                try MigrationDatabaseCodec.applyMerge(snapshot, courseDao: db.courseDao, timeTableDao: db.timeTableDao,
                    periodTableDao: db.periodTableDao, importDraftDao: db.importDraftDao, dbQueue: db.dbQueue)
                let tables = try db.timeTableDao.getAll()
                let imported = try XCTUnwrap(tables.first { $0.name == "Imported" })
                XCTAssertFalse(imported.isDefault)
                XCTAssertFalse(imported.reminderEnabled)
                XCTAssertNil(imported.reminderOverride)
                XCTAssertEqual(imported.importSourceJson, "opaque source")
                let scope = resolveReminderTableScope(tables: tables, selectedTableId: localId)
                XCTAssertEqual(scope.filter(\.reminderEnabled).map(\.id), localOverride == false ? [] : [localId])
                XCTAssertEqual(tables.filter(\.isDefault).map(\.id), [localId])
            }
        }
    }

    func testBackupMergeIntoEmptyDatabaseRetainsItsDefaultAndReminderScope() throws {
        let db = try AppDatabase.inMemory()
        let incoming = TimeTableEntity(name: "Imported", startDate: "2026-09-07", isDefault: true,
            reminderEnabled: true, reminderOverride: true, importSourceJson: "opaque source", id: 99)
        let snapshot = MigrationDatabaseCodec.DatabaseSnapshot(timeTables: [MigrationDatabaseCodec.toRow(incoming)])
        try MigrationDatabaseCodec.applyMerge(snapshot, courseDao: db.courseDao, timeTableDao: db.timeTableDao,
            periodTableDao: db.periodTableDao, importDraftDao: db.importDraftDao, dbQueue: db.dbQueue)
        let restored = try XCTUnwrap(db.timeTableDao.getAll().first)
        XCTAssertTrue(restored.isDefault)
        XCTAssertTrue(restored.reminderEnabled)
        XCTAssertEqual(restored.reminderOverride, true)
        XCTAssertEqual(restored.importSourceJson, "opaque source")
    }

    func testNewDatabaseStoresNullableOverrideAndOpaqueSource() throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let source = #"{"startDate":null}"#
        let id = try repo.insertTable(TimeTableEntity(name: "T", startDate: "2026-09-07", importSourceJson: source))
        let table = try XCTUnwrap(repo.getTable(id))
        XCTAssertNil(table.reminderOverride)
        XCTAssertEqual(table.importSourceJson, source)
        let columns = try db.dbQueue.read { try $0.columns(in: "time_tables").map(\.name) }
        XCTAssertTrue(columns.contains("reminderOverride")); XCTAssertTrue(columns.contains("importSourceJson"))
    }
    func testManualUpdateExactMatchesWinBeforeUniqueFallback() {
        var first = course(node: 1); first.id = 1; first.note = "first"
        var second = course(node: 3); second.id = 2; second.note = "second"
        let result = diffImportedCourses(existing: [first,second], incoming: [course(node: 5), course(node: 3)])
        XCTAssertEqual(result.merged.map(\.id), [1,2]); XCTAssertEqual(result.merged.map(\.note), ["first","second"])
        XCTAssertTrue(result.added.isEmpty); XCTAssertTrue(result.removed.isEmpty)
    }
    func testManualUpdateAmbiguousFallbackDoesNotStealCustomFields() {
        var a = course(node: 1); a.id = 1; a.note = "private"
        var b = course(node: 3); b.id = 2
        let diff = diffImportedCourses(existing: [a,b], incoming: [course(node: 5),course(node: 7)])
        XCTAssertEqual(diff.added.count,2); XCTAssertEqual(diff.removed.count,2)
        XCTAssertTrue(diff.merged.allSatisfy { $0.id == 0 && $0.note.isEmpty })
    }
    func testManualUpdatePreservesLocalFieldsAndNewRowsInheritOnlyGroupPresentation() {
        var old = course(); old.id = 9; old.alias = "Alias"; old.note = "Note"
        old.ownTime = true; old.startTime = "07:00"; old.endTime = "08:00"
        old.colorMode = CourseColorMode.GROUP
        let diff = diffImportedCourses(existing: [old], incoming: [course(),course(day: 2)])
        XCTAssertEqual(diff.merged[0].note,"Note"); XCTAssertEqual(diff.merged[0].startTime,"07:00")
        XCTAssertEqual(diff.merged[1].groupId,"g"); XCTAssertEqual(diff.merged[1].alias,"Alias")
        XCTAssertTrue(diff.merged[1].note.isEmpty); XCTAssertFalse(diff.merged[1].ownTime)
    }
    func testBlankLegacyGroupsDoNotPropagatePresentationAndAreRepairedOnUpdate() throws {
        var old = course(); old.groupId = " \n "; old.alias = "Alias"; old.colorMode = CourseColorMode.GROUP
        let diff = diffImportedCourses(existing: [old], incoming: [course(day: 2)])
        XCTAssertTrue(diff.merged[0].alias.isEmpty)
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let id = try repo.insertTable(TimeTableEntity(name: "T", startDate: "2026-09-07"))
        try repo.updateImportedCourses(tableId: id, courses: [old])
        XCTAssertFalse(try repo.getCourses(id)[0].groupId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    func testInvalidMinimumStepIsRejectedWithoutArithmeticTrapOrMutation() throws {
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let id = try repo.insertTable(TimeTableEntity(name: "T", startDate: "2026-09-07"))
        var invalid = course(id); invalid.step = Int.min
        XCTAssertThrowsError(try repo.updateImportedCourses(tableId: id, courses: [invalid]))
        XCTAssertTrue(try repo.getCourses(id).isEmpty)
    }
    func testManualUpdateStalePreviewAndForeignIDsLeaveRowsUnchanged() throws {
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let t = try repo.insertTable(TimeTableEntity(name: "T", startDate: "2026-09-07"))
        _ = try repo.insertCourse(course(t))
        let old = try repo.getCourses(t)
        _ = try repo.insertCourse(course(t, name: "Other", day: 2))
        XCTAssertThrowsError(try repo.updateImportedCourses(tableId: t, courses: old, expectedCourses: old))
        let before = try repo.getCourses(t)
        var foreign = course(t); foreign.id = 999
        XCTAssertThrowsError(try repo.updateImportedCourses(tableId: t, courses: [foreign]))
        XCTAssertEqual(try repo.getCourses(t),before)
    }
    func testManualUpdateCanBeUndoneAndRetainsTablePreferences() throws {
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let t = try repo.insertTable(TimeTableEntity(name: "T", startDate: "2026-09-07", importSourceJson: "source"))
        _ = try repo.insertCourse(course(t))
        let before = try repo.getCourses(t)
        Sleepy.UndoManager.shared.clear()
        let diff = diffImportedCourses(existing: before, incoming: [course(t, name: "New")])
        try repo.updateImportedCourses(tableId: t, courses: diff.merged, expectedCourses: before)
        XCTAssertEqual(try repo.getCourses(t).map(\.courseName),["New"])
        XCTAssertEqual(try repo.getTable(t)?.importSourceJson,"source")
        XCTAssertTrue(try repo.restoreLastSnapshot()); XCTAssertEqual(try repo.getCourses(t),before)
        Sleepy.UndoManager.shared.clear()
    }
    func testNamedCopyRejectsDuplicateAndBlankWithoutCreatingTable() throws {
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let id = try repo.insertTable(TimeTableEntity(name: "A", startDate: "2026-09-07"))
        XCTAssertThrowsError(try repo.duplicateTable(id,newName: "  "))
        XCTAssertThrowsError(try repo.duplicateTable(id,newName: " A "))
        XCTAssertEqual(try repo.getAllTables().count,1)
        let copy = try repo.duplicateTable(id,newName: " B ")
        XCTAssertEqual(try repo.getTable(copy)?.name,"B")
    }
    func testNativeAndJSONSourceKeepFullWidthIdentifiers() throws {
        let source = #"{"school":"Ａ｜１","startDate":null,"note":"first\nsecond"}"#
        let table = TimeTableEntity(name: "T", startDate: "2026-09-07", importSourceJson: source)
        let native = SleepyNativeExporter.exportFile(tableName: table.name,startDate: table.startDate,maxWeek: 20,nodesPerDay: 12,timeJson: table.timeJson,courses: [course()],importSourceJson: source)
        XCTAssertEqual(try ScheduleParser.parse(native,defaultTableId: 1).get().importSourceJson,source)
        let json = ScheduleExporter.exportWakeUpJson(table,[course()])
        XCTAssertEqual(try ScheduleParser.parse(json,defaultTableId: 1).get().importSourceJson,source)
    }
    func testNativeSourceKeepsUnicodeLineSeparatorsAcrossRealLineEndings() throws {
        for separator in ["\u{0085}", "\u{2028}", "\u{2029}"] {
            let source = "{\"school\":\"A\(separator)B\"}"
            let native = SleepyNativeExporter.exportFile(tableName: "T", startDate: "2026-09-07",
                maxWeek: 20, nodesPerDay: 12, timeJson: TimeTableUtils.DEFAULT_TIME_JSON,
                courses: [course()], importSourceJson: source)
            for ending in ["\n", "\r\n", "\r"] {
                let text = native.replacingOccurrences(of: "\n", with: ending)
                XCTAssertEqual(try SleepyNativeParser.parse(text, defaultTableId: 1,
                    defaultColor: "#FF123456").importSourceJson, source)
                XCTAssertEqual(try ScheduleParser.parse(text, defaultTableId: 1).get().importSourceJson, source)
            }
        }
    }

    func testNativeSourceKeepsEscapedPipesBackslashesAndWhitespace() throws {
        let source = #"  {"school":"Ａ|Ｂ｜１","path":"C:\\folder\\x","note":"first\nsecond"}  "#
        let native = SleepyNativeExporter.exportFile(tableName: "T", startDate: "2026-09-07",
            maxWeek: 20, nodesPerDay: 12, timeJson: TimeTableUtils.DEFAULT_TIME_JSON,
            courses: [course()], importSourceJson: source)
        XCTAssertEqual(try ScheduleParser.parse(native, defaultTableId: 1).get().importSourceJson, source)
    }
    func testNativeSourceMatchesLowercaseIndentedHeaderAfterMagic() throws {
        let source = #"{"school":"Ａ|Ｂ｜１","startDate":null}"#
        let share = SleepyNativeExporter.exportShareText(tableName: "T", startDate: "2026-09-07",
            maxWeek: 20, nodesPerDay: 12, timeJson: TimeTableUtils.DEFAULT_TIME_JSON,
            courses: [course()], importSourceJson: source)
        let indented = share.replacingOccurrences(of: "#sleepy-v1", with: "  #SLEEPY-v1  ")
            .replacingOccurrences(of: "\nT", with: "\n  t")
        XCTAssertEqual(try ScheduleParser.parse(indented, defaultTableId: 1).get().importSourceJson, source)
    }
    func testNativeSourceIgnoresHeaderLookingPreamble() throws {
        let source = #"{"school":"Ａ|Ｂ｜１"}"#
        let share = SleepyNativeExporter.exportShareText(tableName: "T", startDate: "2026-09-07",
            maxWeek: 20, nodesPerDay: 12, timeJson: TimeTableUtils.DEFAULT_TIME_JSON,
            courses: [course()], importSourceJson: source)
        let text = share.replacingOccurrences(of: "#sleepy-v1", with: "Tnotice|date|20|12|source=wrong\n#sleepy-v1")
        XCTAssertEqual(try ScheduleParser.parse(text, defaultTableId: 1).get().importSourceJson, source)
    }
    func testUIStyleMigratesLegacyWithoutChangingNavigationOrTheme() {
        let name = "android64-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!; defer { d.removePersistentDomain(forName: name) }
        d.set("liquid_glass",forKey: AppPrefs.KEY_DOCK_THEME)
        let prefs = AppPrefs(defaults: d)
        var received: [String] = []
        let token = prefs.uiStylePublisher.sink { received.append($0) }
        XCTAssertEqual(received,["liquid_glass"])
        prefs.setUiStyle("classic"); XCTAssertEqual(received,["liquid_glass","classic"])
        XCTAssertNil(d.object(forKey: AppPrefs.KEY_NAV_DOCK)); XCTAssertNil(d.object(forKey: AppPrefs.KEY_THEME_MODE))
        withExtendedLifetime(token) {}
    }
}
