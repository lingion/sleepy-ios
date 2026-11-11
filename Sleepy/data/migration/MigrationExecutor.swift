// MigrationExecutor.swift — ← data/migration/MigrationExecutor.kt
// 全量迁移编排层: 把协议层 (ZIP) 与各模块 codec (prefs/database) 接起来。
//
// 约束 (设计文档 §导出/导入流程):
// - 导出选中 DATABASE 自动带上 PERSISTED_STATE 依赖闭包;
// - 导入先完整读包校验, 坏包在写任何本机数据前被拒绝;
// - 包内缺失的文件/模块不动本机 (设备自有设置优先于默认);
// - CREDENTIALS 枚举保留但当前两端均无内容, 暂不进包。

import Foundation
import GRDB

/// Logical backup files can map to defaults domains or shared widget JSON files.
protocol MigrationPrefsStoreProtocol {
    func open(fileName: String) -> UserDefaults
    func collect(fileName: String) throws -> MigrationPrefsCodec.PrefsFileSnapshot
    func validate(_ snapshot: MigrationPrefsCodec.PrefsFileSnapshot, fileName: String) throws
    func apply(_ snapshot: MigrationPrefsCodec.PrefsFileSnapshot, fileName: String, merge: Bool) throws
    func prepareApply(_ snapshot: MigrationPrefsCodec.PrefsFileSnapshot, fileName: String, merge: Bool) throws -> () throws -> Void
}

extension MigrationPrefsStoreProtocol {
    func collect(fileName: String) throws -> MigrationPrefsCodec.PrefsFileSnapshot {
        MigrationPrefsCodec.collect(open(fileName: fileName))
    }

    func validate(_ snapshot: MigrationPrefsCodec.PrefsFileSnapshot, fileName: String) throws {}

    func apply(_ snapshot: MigrationPrefsCodec.PrefsFileSnapshot, fileName: String, merge: Bool) throws {
        MigrationPrefsCodec.apply(open(fileName: fileName), snapshot, merge: merge)
    }

    func prepareApply(_ snapshot: MigrationPrefsCodec.PrefsFileSnapshot, fileName: String, merge: Bool) throws -> () throws -> Void {
        try validate(snapshot, fileName: fileName)
        return { try self.apply(snapshot, fileName: fileName, merge: merge) }
    }

    /// Validate and capture local bindings before database writes; imported IDs are only
    /// known after the database merge. Keep local IDs outside that mapping unchanged.
    func prepareWidgetBindingMerge(_ snapshot: MigrationPrefsCodec.PrefsFileSnapshot) throws -> ([Int64: Int64]) throws -> Void {
        let fileName = "widget_bindings"
        try validate(snapshot, fileName: fileName)
        let local = try collect(fileName: fileName)
        try validate(local, fileName: fileName)
        return { tableIdMap in
            var entries = local.entries
            for (kind, value) in snapshot.entries {
                // A missing imported target must not accidentally bind to a same-ID local
                // table. Preserve an existing binding, or leave a new kind to normal fallback.
                guard let tableId = tableIdMap[value.number] else { continue }
                entries[kind] = .init(type: .LONG, number: tableId)
            }
            try self.apply(.init(entries: entries), fileName: fileName, merge: false)
        }
    }
}

/// The application's preference domains, shared by the backup screen and its production-storage tests.
struct RuntimeMigrationPrefsStore: MigrationPrefsStoreProtocol {
    func open(fileName: String) -> UserDefaults {
        if fileName == AppPrefs.FILE { return AppPrefs.shared.sharedBackedStore }
        return UserDefaults(suiteName: fileName) ?? .standard
    }

    func collect(fileName: String) throws -> MigrationPrefsCodec.PrefsFileSnapshot {
        if widgetFiles.contains(fileName) { return try collectWidget(fileName) }
        var snapshot = MigrationPrefsCodec.collect(open(fileName: fileName))
        if fileName == AppPrefs.FILE {
            // iOS stores themes with AppPrefs; the package retains Android's logical file boundary.
            snapshot.entries.removeValue(forKey: CustomThemeCore.KEY_THEMES)
        } else if fileName == CustomThemeCore.PREFS_NAME {
            snapshot.entries.removeValue(forKey: CustomThemeCore.KEY_THEMES)
            if let themes = CustomThemeStore.defaults.string(forKey: CustomThemeCore.KEY_THEMES) {
                snapshot.entries[CustomThemeCore.KEY_THEMES] = .init(type: .STRING, string: themes)
            }
        }
        return snapshot
    }

    func validate(_ snapshot: MigrationPrefsCodec.PrefsFileSnapshot, fileName: String) throws {
        if widgetFiles.contains(fileName) {
            for (key, value) in snapshot.entries {
                switch fileName {
                case "widget_bindings", "widget_today_nav":
                    guard value.type == .LONG || value.type == .INT else { throw invalid(fileName, key) }
                case "widget_scroll_prefs", "widget_compact_window_prefs":
                    guard value.type == .BOOL else { throw invalid(fileName, key) }
                default:
                    if key.hasPrefix("mode_") {
                        guard value.type == .STRING, WeekGridWideMode(rawValue: value.string.lowercased()) != nil else {
                            throw invalid(fileName, key)
                        }
                    } else if key.hasPrefix("side_") {
                        guard value.type == .STRING, WeekGridWideLabelSide(rawValue: value.string.lowercased()) != nil else {
                            throw invalid(fileName, key)
                        }
                    }
                }
            }
        }
        if (fileName == CustomThemeCore.PREFS_NAME || fileName == AppPrefs.FILE),
           let themes = snapshot.entries[CustomThemeCore.KEY_THEMES], themes.type != .STRING {
            throw invalid(fileName, CustomThemeCore.KEY_THEMES)
        }
    }

    func apply(_ snapshot: MigrationPrefsCodec.PrefsFileSnapshot, fileName: String, merge: Bool) throws {
        try prepareApply(snapshot, fileName: fileName, merge: merge)()
    }

    func prepareApply(_ snapshot: MigrationPrefsCodec.PrefsFileSnapshot, fileName: String, merge: Bool) throws -> () throws -> Void {
        try validate(snapshot, fileName: fileName)
        if widgetFiles.contains(fileName) {
            var entries = merge ? try collectWidget(fileName).entries : [:]
            entries.merge(snapshot.entries, uniquingKeysWith: { _, incoming in incoming })
            let data: Data
            switch fileName {
            case "widget_bindings", "widget_today_nav":
                data = try JSONEncoder().encode(entries.mapValues(\.number))
            case "widget_scroll_prefs", "widget_compact_window_prefs":
                data = try JSONEncoder().encode(entries.mapValues(\.bool))
            default:
                var root: [String: [String: String]] = [:]
                for (key, value) in entries {
                    if key.hasPrefix("mode_") { root[String(key.dropFirst(5)), default: [:]]["mode"] = value.string.lowercased() }
                    else if key.hasPrefix("side_") { root[String(key.dropFirst(5)), default: [:]]["labelSide"] = value.string.lowercased() }
                }
                data = try JSONEncoder().encode(root)
            }
            let url = widgetURL(fileName)
            return { try data.write(to: url, options: .atomic) }
        }
        return { self.applyDefaults(snapshot, fileName: fileName, merge: merge) }
    }

    private func applyDefaults(_ snapshot: MigrationPrefsCodec.PrefsFileSnapshot, fileName: String, merge: Bool) {
        if fileName == AppPrefs.FILE {
            let previousTheme = CustomThemeStore.defaults.object(forKey: CustomThemeCore.KEY_THEMES)
            MigrationPrefsCodec.apply(open(fileName: fileName), snapshot, merge: merge)
            // An absent logical custom_themes file must not be erased by replacing sleepy_prefs.
            if snapshot.entries[CustomThemeCore.KEY_THEMES] == nil, let previousTheme {
                CustomThemeStore.defaults.set(previousTheme, forKey: CustomThemeCore.KEY_THEMES)
            }
        } else {
            MigrationPrefsCodec.apply(open(fileName: fileName), snapshot, merge: merge)
            if fileName == CustomThemeCore.PREFS_NAME {
                if let theme = snapshot.entries[CustomThemeCore.KEY_THEMES] {
                    CustomThemeStore.defaults.set(theme.string, forKey: CustomThemeCore.KEY_THEMES)
                } else if !merge {
                    CustomThemeStore.defaults.removeObject(forKey: CustomThemeCore.KEY_THEMES)
                }
            }
        }
    }

    private var widgetFiles: Set<String> {
        ["widget_bindings", "widget_scroll_prefs", "widget_compact_window_prefs", "widget_today_nav", "widget_wide_grid"]
    }

    private func widgetURL(_ name: String) -> URL {
        AppGroupResolver.sharedDirectory().appendingPathComponent(name + ".json")
    }

    private func invalid(_ file: String, _ key: String) -> MigrationPackageException {
        MigrationPackageException(message: "invalid \(file) backup value: \(key)")
    }

    private func collectWidget(_ name: String) throws -> MigrationPrefsCodec.PrefsFileSnapshot {
        let url = widgetURL(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        let data = try Data(contentsOf: url)
        let entries: [String: MigrationPrefsCodec.PrefValue]
        switch name {
        case "widget_bindings", "widget_today_nav":
            entries = try JSONDecoder().decode([String: Int64].self, from: data)
                .mapValues { .init(type: .LONG, number: $0) }
        case "widget_scroll_prefs", "widget_compact_window_prefs":
            entries = try JSONDecoder().decode([String: Bool].self, from: data)
                .mapValues { .init(type: .BOOL, bool: $0) }
        default:
            let root = try JSONDecoder().decode([String: [String: String]].self, from: data)
            var values: [String: MigrationPrefsCodec.PrefValue] = [:]
            for (kind, settings) in root {
                if let mode = settings["mode"] { values["mode_" + kind] = .init(type: .STRING, string: mode.uppercased()) }
                if let side = settings["labelSide"] { values["side_" + kind] = .init(type: .STRING, string: side.uppercased()) }
            }
            entries = values
        }
        let snapshot = MigrationPrefsCodec.PrefsFileSnapshot(entries: entries)
        try validate(snapshot, fileName: name)
        return snapshot
    }
}

/// 全量迁移编排 — 与 原版本 MigrationExecutor.kt 1:1。
enum MigrationExecutor {

    enum ImportMode: String {
        case OVERWRITE
        case MERGE
    }

    struct ExportResult {
        let bytes: Data
        let modules: [MigrationModule]
        let manifest: MigrationBackup.Manifest
    }

    struct ImportCounts {
        var periodTables: Int = 0
        var timeTables: Int = 0
        var courses: Int = 0
        var importDrafts: Int = 0
        var prefFiles: Int = 0
        var prefKeys: Int = 0
    }

    struct ImportReport {
        let mode: ImportMode
        let appliedModules: [MigrationModule]
        let unknownModules: [String]
        let counts: ImportCounts
    }

    // MARK: - 导出

    /// 导出选中的模块为 .sleepybackup 字节。
    /// CREDENTIALS 当前无内容, 不进包(与原实现一致)。
    /// iOS 同步 throws(GRDB DAO throws 而非 suspend)。
    static func export(
        selected: Set<MigrationModule>,
        prefsStore: MigrationPrefsStoreProtocol,
        courseDao: CourseDao,
        timeTableDao: TimeTableDao,
        periodTableDao: PeriodTableDao,
        importDraftDao: ImportDraftDao,
        dbQueue: DatabaseQueue,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) throws -> ExportResult {
        let resolved = MigrationModuleDeps.resolve(selected)
            .filter { $0 != .CREDENTIALS }
            .sorted()

        var payloads: [MigrationModule: String] = [:]
        for module in resolved {
            switch module {
            case .DATABASE:
                let snapshot = try MigrationDatabaseCodec.collect(
                    courseDao: courseDao, timeTableDao: timeTableDao,
                    periodTableDao: periodTableDao, importDraftDao: importDraftDao
                )
                payloads[module] = try MigrationDatabaseCodec.encode(snapshot)
            case .PREFERENCES, .WIDGETS, .PERSISTED_STATE:
                payloads[module] = try MigrationPrefsCodec.encode(collectPrefs(prefsStore, module: module))
            case .CREDENTIALS:
                continue
            }
        }
        let manifest = MigrationBackup.Manifest(
            createdAt: createdAt,
            // MigrationModule 的 Comparable 按 原 ordinal 排序 (DATABASE,PREFERENCES,
            // WIDGETS,PERSISTED_STATE);Dictionary.keys 无序,必须显式 .sorted() 才与
            // 原版本 LinkedHashMap 插入序 (=ordinal 序) 一致, manifest.modules 确定性输出。
            modules: payloads.keys.sorted().map { $0.entryName }
        )
        let bytes = try MigrationPackageCodec.write(modules: payloads, createdAt: createdAt)
        return ExportResult(
            bytes: bytes,
            modules: Array(payloads.keys).sorted(),
            manifest: manifest
        )
        // dbQueue 参数保留以对齐 原版本 出口签名;iOS 端 collect() 全 read,
        // 不需 dbQueue.write — 参数忽略即可。
    }

    private static func collectPrefs(_ store: MigrationPrefsStoreProtocol, module: MigrationModule) throws -> MigrationPrefsCodec.PrefsSnapshot {
        var files: [String: MigrationPrefsCodec.PrefsFileSnapshot] = [:]
        for fileName in MigrationPrefsFileMap.files(of: module) {
            // Empty logical files stay absent so older backups preserve receiver-owned settings.
            // The store resolves the actual domain/file; the executor never guesses a defaults suite.
            let snapshot = try store.collect(fileName: fileName)
            if !snapshot.entries.isEmpty {
                files[fileName] = snapshot
            }
        }
        return MigrationPrefsCodec.PrefsSnapshot(files: files)
    }

    // MARK: - 导入

    /// 导入 .sleepybackup 字节。
    /// 先完整校验并解码, 任何坏包在触碰本机数据之前失败。
    static func `import`(
        bytes: Data,
        mode: ImportMode,
        prefsStore: MigrationPrefsStoreProtocol,
        courseDao: CourseDao,
        timeTableDao: TimeTableDao,
        periodTableDao: PeriodTableDao,
        importDraftDao: ImportDraftDao,
        dbQueue: DatabaseQueue
    ) throws -> ImportReport {
        // 先完整校验并解码, 任何坏包都在触碰本机数据之前失败
        let content = try MigrationPackageCodec.read(bytes)
        // Decode and validate every module before the first database/defaults/file write.
        var databaseSnapshot: MigrationDatabaseCodec.DatabaseSnapshot?
        var preferenceSnapshots: [MigrationModule: MigrationPrefsCodec.PrefsSnapshot] = [:]
        var preferenceWrites: [MigrationModule: [([Int64: Int64]) throws -> Void]] = [:]
        let remapWidgetBindings = mode == .MERGE && content.modules[.DATABASE] != nil
        for (module, payload) in content.modules {
            switch module {
            case .DATABASE:
                databaseSnapshot = try MigrationDatabaseCodec.decode(payload)
            case .PREFERENCES, .WIDGETS, .PERSISTED_STATE:
                let snapshot = try MigrationPrefsCodec.decode(payload)
                // Main-domain themes came from older iOS packages. The dedicated logical file
                // takes precedence if a package contains both locations.
                let names = snapshot.files.keys.sorted { left, right in
                    if left == AppPrefs.FILE { return right != AppPrefs.FILE }
                    if right == AppPrefs.FILE { return false }
                    if left == CustomThemeCore.PREFS_NAME { return false }
                    if right == CustomThemeCore.PREFS_NAME { return true }
                    return left < right
                }
                preferenceWrites[module] = try names.map { name in
                    if remapWidgetBindings, module == .WIDGETS, name == "widget_bindings" {
                        return try prefsStore.prepareWidgetBindingMerge(snapshot.files[name]!)
                    }
                    let write = try prefsStore.prepareApply(snapshot.files[name]!, fileName: name, merge: mode == .MERGE)
                    return { _ in try write() }
                }
                preferenceSnapshots[module] = snapshot
            case .CREDENTIALS: break
            }
        }
        var counts = ImportCounts()
        var applied: [MigrationModule] = []
        var tableIdMap: [Int64: Int64] = [:]

        let sorted = content.modules.keys.sorted()
        for module in sorted {
            switch module {
            case .DATABASE:
                guard let snapshot = databaseSnapshot else { continue }
                switch mode {
                case .OVERWRITE:
                    try MigrationDatabaseCodec.applyOverwrite(
                        snapshot, courseDao: courseDao, timeTableDao: timeTableDao,
                        periodTableDao: periodTableDao, importDraftDao: importDraftDao,
                        dbQueue: dbQueue
                    )
                case .MERGE:
                    tableIdMap = try MigrationDatabaseCodec.applyMerge(
                        snapshot, courseDao: courseDao, timeTableDao: timeTableDao,
                        periodTableDao: periodTableDao, importDraftDao: importDraftDao,
                        dbQueue: dbQueue
                    )
                }
                counts = ImportCounts(
                    periodTables: snapshot.periodTables.count,
                    timeTables: snapshot.timeTables.count,
                    courses: snapshot.courses.count,
                    importDrafts: snapshot.importDrafts.count,
                    prefFiles: counts.prefFiles,
                    prefKeys: counts.prefKeys
                )
                applied.append(module)

            case .PREFERENCES, .WIDGETS, .PERSISTED_STATE:
                guard let snapshot = preferenceSnapshots[module] else { continue }
                // Missing files stay untouched. Each prepared write already validated both
                // the incoming snapshot and any local file needed for a merge.
                for write in preferenceWrites[module] ?? [] { try write(tableIdMap) }
                let newPrefFiles = counts.prefFiles + snapshot.files.count
                let newPrefKeys = counts.prefKeys + snapshot.files.values.reduce(0) { $0 + $1.entries.count }
                counts = ImportCounts(
                    periodTables: counts.periodTables,
                    timeTables: counts.timeTables,
                    courses: counts.courses,
                    importDrafts: counts.importDrafts,
                    prefFiles: newPrefFiles,
                    prefKeys: newPrefKeys
                )
                applied.append(module)

            case .CREDENTIALS:
                continue   // 未知历史内容, 忽略
            }
        }
        return ImportReport(
            mode: mode,
            appliedModules: applied.sorted(),
            unknownModules: content.unknownModules,
            counts: counts
        )
    }
}
