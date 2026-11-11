import XCTest
@testable import Sleepy

/// Exercises the stores used by the app and widget extension, rather than an unrelated defaults suite.
final class WidgetBackupProductionTests: XCTestCase {
    private let fileNames = ["widget_bindings", "widget_scroll_prefs", "widget_compact_window_prefs",
                             "widget_today_nav", "widget_wide_grid"]
    private var previousFiles: [String: Data] = [:]
    private var previousDomains: [String: [String: Any]] = [:]
    private let kind = "backup-production-test"

    override func setUpWithError() throws {
        try super.setUpWithError()
        for name in fileNames {
            let url = fileURL(name)
            if FileManager.default.fileExists(atPath: url.path) {
                previousFiles[name] = try Data(contentsOf: url)
                try FileManager.default.removeItem(at: url)
            }
            let defaults = UserDefaults(suiteName: name)!
            previousDomains[name] = defaults.persistentDomain(forName: name) ?? [:]
            defaults.removePersistentDomain(forName: name)
        }
    }

    override func tearDownWithError() throws {
        for name in fileNames {
            let url = fileURL(name)
            if let data = previousFiles[name] { try data.write(to: url, options: .atomic) }
            else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            UserDefaults(suiteName: name)!.setPersistentDomain(previousDomains[name] ?? [:], forName: name)
        }
        previousFiles.removeAll()
        previousDomains.removeAll()
        try super.tearDownWithError()
    }

    private func fileURL(_ name: String) -> URL {
        AppGroupResolver.sharedDirectory().appendingPathComponent(name + ".json")
    }

    private func export(_ database: AppDatabase) throws -> Data {
        try MigrationExecutor.export(selected: [.WIDGETS], prefsStore: RuntimeMigrationPrefsStore(),
            courseDao: database.courseDao, timeTableDao: database.timeTableDao,
            periodTableDao: database.periodTableDao, importDraftDao: database.importDraftDao,
            dbQueue: database.dbQueue).bytes
    }

    @discardableResult
    private func restore(_ bytes: Data, _ database: AppDatabase,
                         mode: MigrationExecutor.ImportMode = .OVERWRITE) throws -> MigrationExecutor.ImportReport {
        try MigrationExecutor.import(bytes: bytes, mode: mode, prefsStore: RuntimeMigrationPrefsStore(),
            courseDao: database.courseDao, timeTableDao: database.timeTableDao,
            periodTableDao: database.periodTableDao, importDraftDao: database.importDraftDao,
            dbQueue: database.dbQueue)
    }

    private func package(_ files: [String: MigrationPrefsCodec.PrefsFileSnapshot],
                         database: MigrationDatabaseCodec.DatabaseSnapshot? = nil) throws -> Data {
        var modules = [MigrationModule.WIDGETS: try MigrationPrefsCodec.encode(.init(files: files))]
        if let database { modules[.DATABASE] = try MigrationDatabaseCodec.encode(database) }
        return try MigrationPackageCodec.write(modules: modules, createdAt: 1)
    }

    func testRealWidgetSettingsRoundTripThroughTheUnchangedBackupEnvelope() throws {
        let database = try AppDatabase.inMemory()
        let today = DateUtils.parseDate("2026-11-11")!
        WidgetBindingStore.put(kind, tableId: 42)
        WidgetScrollStore.write(kind, true)
        WidgetCompactWindowStore.setTodayFirst(kind, false)
        TodayDateNavStore.shift(kind, today, 2)
        WeekGridWideSettingsStore.write(.init(mode: .horizontal, labelSide: .right), kind: kind)

        let bytes = try export(database)
        let content = try MigrationPackageCodec.read(bytes)
        let files = try MigrationPrefsCodec.decode(XCTUnwrap(content.modules[.WIDGETS])).files
        XCTAssertEqual(Set(files.keys), Set(fileNames))
        XCTAssertEqual(files["widget_bindings"]?.entries[kind], .init(type: .LONG, number: 42))
        XCTAssertEqual(files["widget_scroll_prefs"]?.entries["scroll_" + kind], .init(type: .BOOL, bool: true))
        XCTAssertEqual(files["widget_wide_grid"]?.entries["mode_" + kind], .init(type: .STRING, string: "HORIZONTAL"))
        XCTAssertEqual(files["widget_wide_grid"]?.entries["side_" + kind], .init(type: .STRING, string: "RIGHT"))

        WidgetBindingStore.put(kind, tableId: 99)
        WidgetScrollStore.write(kind, false)
        WidgetCompactWindowStore.setTodayFirst(kind, true)
        TodayDateNavStore.remove(kind)
        WeekGridWideSettingsStore.write(.init(mode: .original, labelSide: .left), kind: kind)
        try restore(bytes, database)

        XCTAssertEqual(WidgetBindingStore.get(kind), 42)
        XCTAssertEqual(WidgetScrollStore.read(kind), true)
        XCTAssertFalse(WidgetCompactWindowStore.isTodayFirst(kind))
        XCTAssertEqual(Calendar.epochDay(TodayDateNavStore.target(kind, today)), Calendar.epochDay(today) + 2)
        XCTAssertEqual(WeekGridWideSettingsStore.read(kind: kind), .init(mode: .horizontal, labelSide: .right))
    }

    func testAndroidWideGridEnvelopeUsesTheNativeWidgetSettingsStore() throws {
        let database = try AppDatabase.inMemory()
        let bytes = try package(["widget_wide_grid": .init(entries: [
            "mode_" + kind: .init(type: .STRING, string: "HORIZONTAL"),
            "side_" + kind: .init(type: .STRING, string: "RIGHT")])])
        try restore(bytes, database)
        XCTAssertEqual(WeekGridWideSettingsStore.read(kind: kind), .init(mode: .horizontal, labelSide: .right))
        let actual = try JSONDecoder().decode([String: [String: String]].self,
            from: Data(contentsOf: fileURL("widget_wide_grid")))
        XCTAssertEqual(actual[kind]?["mode"], "horizontal")
        XCTAssertEqual(actual[kind]?["labelSide"], "right")
    }

    func testOldBackupWithoutWideGridLeavesItsRealFileUntouchedAndMergePreservesOtherKinds() throws {
        let database = try AppDatabase.inMemory()
        WidgetBindingStore.put(kind, tableId: 1)
        WidgetBindingStore.put("other", tableId: 2)
        WeekGridWideSettingsStore.write(.init(mode: .horizontal, labelSide: .right), kind: kind)
        let wideBefore = try Data(contentsOf: fileURL("widget_wide_grid"))
        let bytes = try package(["widget_bindings": .init(entries: [kind: .init(type: .LONG, number: 3)])])

        try restore(bytes, database, mode: .MERGE)
        XCTAssertEqual(WidgetBindingStore.get(kind), 3)
        XCTAssertEqual(WidgetBindingStore.get("other"), 2)
        XCTAssertEqual(try Data(contentsOf: fileURL("widget_wide_grid")), wideBefore)

        try restore(bytes, database)
        XCTAssertEqual(WidgetBindingStore.get(kind), 3)
        XCTAssertNil(WidgetBindingStore.get("other"))
        XCTAssertEqual(try Data(contentsOf: fileURL("widget_wide_grid")), wideBefore)
    }

    func testDatabaseAndWidgetMergeRemapsIncomingBindingsAndPreservesLocalBindings() throws {
        let database = try AppDatabase.inMemory()
        let localId = try database.timeTableDao.insert(.init(name: "Local table", startDate: "2026-11-02"))
        XCTAssertEqual(localId, 1)
        WidgetBindingStore.put(kind, tableId: localId)
        WidgetBindingStore.put("local-only", tableId: localId)
        let incoming = MigrationDatabaseCodec.TimeTableRow(id: 1, name: "Imported table",
            startDate: "2026-11-02", timeJson: "[]", createdAt: 1)
        let bytes = try package(["widget_bindings": .init(entries: [
            kind: .init(type: .LONG, number: 1),
            "int-kind": .init(type: .INT, number: 1)])], database: .init(timeTables: [incoming]))

        try restore(bytes, database, mode: .MERGE)

        let imported = try XCTUnwrap(database.timeTableDao.getAll().first { $0.name == "Imported table" })
        XCTAssertNotEqual(imported.id, localId)
        XCTAssertEqual(WidgetBindingStore.get(kind), imported.id)
        XCTAssertEqual(WidgetBindingStore.get("int-kind"), imported.id)
        XCTAssertEqual(WidgetBindingStore.get("local-only"), localId)
        let repo = ScheduleRepository(database)
        XCTAssertEqual(WidgetTableResolver.resolveBoundTable(kind, repo: repo)?.name, "Imported table")
        XCTAssertEqual(WidgetTableResolver.resolveBoundTable("local-only", repo: repo)?.name, "Local table")
    }

    func testDatabaseAndWidgetMergeSkipsBindingsWithoutAnImportedTarget() throws {
        let database = try AppDatabase.inMemory()
        let localId = try database.timeTableDao.insert(.init(name: "Local table", startDate: "2026-11-02"))
        let otherId = try database.timeTableDao.insert(.init(name: "Other local table", startDate: "2026-11-02"))
        WidgetBindingStore.put(kind, tableId: otherId)
        let incoming = MigrationDatabaseCodec.TimeTableRow(id: 90, name: "Imported table",
            startDate: "2026-11-02", timeJson: "[]", createdAt: 1)
        // The missing imported ID exists locally: importing it unchanged would select the wrong table.
        let bytes = try package(["widget_bindings": .init(entries: [
            kind: .init(type: .LONG, number: localId),
            "new-kind": .init(type: .LONG, number: localId)])], database: .init(timeTables: [incoming]))

        try restore(bytes, database, mode: .MERGE)

        XCTAssertEqual(try database.timeTableDao.getAll().count, 3)
        XCTAssertEqual(WidgetBindingStore.get(kind), otherId)
        XCTAssertNil(WidgetBindingStore.get("new-kind"))
        XCTAssertEqual(WidgetTableResolver.resolveBoundTable(kind, repo: ScheduleRepository(database))?.name, "Other local table")
    }

    func testInvalidBindingRejectsCombinedMergeBeforeDatabaseOrFilesChange() throws {
        let database = try AppDatabase.inMemory()
        let localId = try database.timeTableDao.insert(.init(name: "Local table", startDate: "2026-11-02"))
        WidgetBindingStore.put(kind, tableId: localId)
        let bindingBefore = try Data(contentsOf: fileURL("widget_bindings"))
        let incoming = MigrationDatabaseCodec.TimeTableRow(id: 1, name: "Must not be merged",
            startDate: "2026-11-02", timeJson: "[]", createdAt: 1)
        let bytes = try package(["widget_bindings": .init(entries: [
            kind: .init(type: .STRING, string: "invalid")])], database: .init(timeTables: [incoming]))

        XCTAssertThrowsError(try restore(bytes, database, mode: .MERGE))
        XCTAssertEqual(try database.timeTableDao.getAll().map(\.id), [localId])
        XCTAssertEqual(try Data(contentsOf: fileURL("widget_bindings")), bindingBefore)
    }

    func testInvalidValueInEveryWidgetFileIsRejectedBeforeDatabaseOrFilesChange() throws {
        for name in fileNames {
            let database = try AppDatabase.inMemory()
            let table = try database.timeTableDao.insert(.init(name: "Keep me", startDate: "2026-11-02"))
            WidgetBindingStore.put(kind, tableId: 42)
            WidgetCompactWindowStore.setTodayFirst(kind, false)
            let bindingBefore = try Data(contentsOf: fileURL("widget_bindings"))
            let windowBefore = try Data(contentsOf: fileURL("widget_compact_window_prefs"))
            let key: String
            switch name {
            case "widget_bindings": key = kind
            case "widget_scroll_prefs": key = "scroll_" + kind
            case "widget_compact_window_prefs": key = "compact_today_first_" + kind
            case "widget_today_nav": key = "today_nav_sel_" + kind
            default: key = "mode_" + kind
            }
            let invalid = MigrationPrefsCodec.PrefValue(type: .STRING, string: "invalid")
            let bytes = try package([name: .init(entries: [key: invalid])], database: .init())

            XCTAssertThrowsError(try restore(bytes, database), name)
            XCTAssertEqual(try database.timeTableDao.getAll().map(\.id), [table], name)
            XCTAssertEqual(try Data(contentsOf: fileURL("widget_bindings")), bindingBefore, name)
            XCTAssertEqual(try Data(contentsOf: fileURL("widget_compact_window_prefs")), windowBefore, name)
        }
    }

    func testMalformedWidgetJsonCannotProduceASuccessfulIncompleteBackup() throws {
        let database = try AppDatabase.inMemory()
        for name in fileNames {
            let url = fileURL(name)
            try Data("broken JSON".utf8).write(to: url, options: .atomic)
            XCTAssertThrowsError(try export(database), name)
            try FileManager.default.removeItem(at: url)
        }
    }

    func testMalformedLaterModuleIsRejectedBeforeTheDatabaseIsReplaced() throws {
        let database = try AppDatabase.inMemory()
        let table = try database.timeTableDao.insert(.init(name: "Keep me", startDate: "2026-11-02"))
        let bytes = try MigrationPackageCodec.write(modules: [
            .DATABASE: try MigrationDatabaseCodec.encode(.init()), .WIDGETS: "broken JSON"], createdAt: 1)
        XCTAssertThrowsError(try restore(bytes, database))
        XCTAssertEqual(try database.timeTableDao.getAll().map(\.id), [table])
    }

    func testCorruptLocalWidgetFileRejectsMergeBeforeDatabaseOrFilesChange() throws {
        for name in fileNames {
            for file in fileNames where FileManager.default.fileExists(atPath: fileURL(file).path) {
                try FileManager.default.removeItem(at: fileURL(file))
            }
            let database = try AppDatabase.inMemory()
            let table = try database.timeTableDao.insert(.init(name: "Keep me", startDate: "2026-11-02"))
            let broken = Data("broken JSON".utf8)
            try broken.write(to: fileURL(name), options: .atomic)
            let incoming = MigrationDatabaseCodec.TimeTableRow(id: 90, name: "Must not be merged",
                startDate: "2026-11-02", timeJson: "[]", createdAt: 1)
            let bytes = try package([name: .init()], database: .init(timeTables: [incoming]))

            XCTAssertThrowsError(try restore(bytes, database, mode: .MERGE), name)
            XCTAssertEqual(try database.timeTableDao.getAll().map(\.id), [table], name)
            XCTAssertEqual(try Data(contentsOf: fileURL(name)), broken, name)
        }
    }
}
