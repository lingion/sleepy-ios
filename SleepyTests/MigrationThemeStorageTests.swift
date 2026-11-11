import XCTest
@testable import Sleepy

final class MigrationThemeStorageTests: XCTestCase {
    private var previousThemes: Any?
    private var previousDomain: [String: Any] = [:]
    private let theme = CustomTheme(id: "migration-production-theme", name: "Shared theme",
        primary: "#123456", secondary: "#345678", tertiary: "#56789A",
        surfaceHue: 220, surfaceChroma: 6, createdAt: 1)

    override func setUp() {
        super.setUp()
        previousThemes = CustomThemeStore.defaults.object(forKey: CustomThemeCore.KEY_THEMES)
        let defaults = UserDefaults(suiteName: CustomThemeCore.PREFS_NAME)!
        previousDomain = defaults.persistentDomain(forName: CustomThemeCore.PREFS_NAME) ?? [:]
        defaults.removePersistentDomain(forName: CustomThemeCore.PREFS_NAME)
    }

    override func tearDown() {
        if let previousThemes { CustomThemeStore.defaults.set(previousThemes, forKey: CustomThemeCore.KEY_THEMES) }
        else { CustomThemeStore.defaults.removeObject(forKey: CustomThemeCore.KEY_THEMES) }
        UserDefaults(suiteName: CustomThemeCore.PREFS_NAME)!.setPersistentDomain(previousDomain,
            forName: CustomThemeCore.PREFS_NAME)
        super.tearDown()
    }

    func testProductionThemeIsExportedInTheAndroidCompatibleLogicalFile() throws {
        CustomThemeStore.defaults.set(CustomThemeCore.toJson([theme]), forKey: CustomThemeCore.KEY_THEMES)
        let db = try AppDatabase.inMemory()
        let result = try MigrationExecutor.export(selected: [.PREFERENCES], prefsStore: RuntimeMigrationPrefsStore(),
            courseDao: db.courseDao, timeTableDao: db.timeTableDao, periodTableDao: db.periodTableDao,
            importDraftDao: db.importDraftDao, dbQueue: db.dbQueue)
        let content = try MigrationPackageCodec.read(result.bytes)
        let files = try MigrationPrefsCodec.decode(XCTUnwrap(content.modules[.PREFERENCES])).files
        let exported = try XCTUnwrap(files["custom_themes"]?.entries[CustomThemeCore.KEY_THEMES])
        XCTAssertEqual(exported.type, .STRING)
        XCTAssertEqual(CustomThemeCore.parse(exported.string), [theme])
    }

    func testAndroidThemeBackupIsReadByTheProductionThemeStore() throws {
        CustomThemeStore.defaults.removeObject(forKey: CustomThemeCore.KEY_THEMES)
        let snapshot = MigrationPrefsCodec.PrefsSnapshot(files: ["custom_themes": .init(entries: [
            CustomThemeCore.KEY_THEMES: .init(type: .STRING, string: CustomThemeCore.toJson([theme]))])])
        let bytes = try MigrationPackageCodec.write(modules: [.PREFERENCES: MigrationPrefsCodec.encode(snapshot)], createdAt: 1)
        let db = try AppDatabase.inMemory()
        try MigrationExecutor.import(bytes: bytes, mode: .OVERWRITE, prefsStore: RuntimeMigrationPrefsStore(),
            courseDao: db.courseDao, timeTableDao: db.timeTableDao, periodTableDao: db.periodTableDao,
            importDraftDao: db.importDraftDao, dbQueue: db.dbQueue)
        XCTAssertEqual(CustomThemeStore.getAll(), [theme])
    }

    func testOldIosThemeLocationStillRestoresAndLogicalThemeFileWinsWhenBothExist() throws {
        let store = RuntimeMigrationPrefsStore()
        let oldSnapshot = MigrationPrefsCodec.PrefsFileSnapshot(entries: [
            CustomThemeCore.KEY_THEMES: .init(type: .STRING, string: CustomThemeCore.toJson([theme]))])
        try store.apply(oldSnapshot, fileName: AppPrefs.FILE, merge: true)
        XCTAssertEqual(CustomThemeStore.getAll(), [theme])

        let logicalTheme = CustomTheme(id: theme.id, name: "Logical theme wins", primary: theme.primary,
            secondary: theme.secondary, tertiary: theme.tertiary, surfaceHue: theme.surfaceHue,
            surfaceChroma: theme.surfaceChroma, createdAt: theme.createdAt)
        let files = [AppPrefs.FILE: oldSnapshot, CustomThemeCore.PREFS_NAME:
            MigrationPrefsCodec.PrefsFileSnapshot(entries: [CustomThemeCore.KEY_THEMES:
                .init(type: .STRING, string: CustomThemeCore.toJson([logicalTheme]))])]
        let bytes = try MigrationPackageCodec.write(modules: [.PREFERENCES:
            MigrationPrefsCodec.encode(.init(files: files))], createdAt: 1)
        let db = try AppDatabase.inMemory()
        try MigrationExecutor.import(bytes: bytes, mode: .MERGE, prefsStore: store,
            courseDao: db.courseDao, timeTableDao: db.timeTableDao, periodTableDao: db.periodTableDao,
            importDraftDao: db.importDraftDao, dbQueue: db.dbQueue)
        XCTAssertEqual(CustomThemeStore.getAll(), [logicalTheme])
    }
}
