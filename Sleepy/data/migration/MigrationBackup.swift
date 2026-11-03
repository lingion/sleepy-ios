// MigrationBackup.swift — ← data/migration/MigrationBackup.kt
// Sleepy 全量迁移备份协议常量与 manifest 模型。
// `.sleepybackup` 是单文件 ZIP 容器;`.sleepy` 仍保留给 sleepy-v1。

import Foundation

/// 全量迁移备份格式 — `.sleepybackup` 单文件 ZIP 容器。
/// 与 原版本 MigrationBackup.kt 1:1 对位; JSON 协议必须保持向后兼容(ignoreUnknownKeys)。
enum MigrationBackup {
    static let FILE_EXTENSION = "sleepybackup"
    static let FORMAT = "sleepy-migration"
    static let VERSION = 1
    static let ENTRY_MANIFEST = "manifest.json"
    static let ENTRY_MODULES_DIR = "modules"
    static let ENTRY_EXTENSIONS_DIR = "extensions"

    /// 备份 manifest — 顶层索引。
    struct Manifest: Codable {
        var format: String = FORMAT
        var version: Int = VERSION
        var createdAt: Int64
        var modules: [String]

        /// 显式便利 init — 调用方只需 createdAt + modules,format/version 用默认。
        init(createdAt: Int64, modules: [String]) {
            self.format = FORMAT
            self.version = VERSION
            self.createdAt = createdAt
            self.modules = modules
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // Swift 默认即 ignoreUnknownKeys=true (key 必须存在且匹配; 未知 key 不抛错)
        return d
    }()

    static func encodeManifest(_ manifest: Manifest) throws -> String {
        let data = try encoder.encode(manifest)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func decodeManifest(_ text: String) throws -> Manifest {
        guard let data = text.data(using: .utf8) else {
            throw MigrationPackageException(message: "manifest text not utf-8")
        }
        return try decoder.decode(Manifest.self, from: data)
    }
}

/// 迁移模块 — 每个模块对应包内一个 entryName.json。
enum MigrationModule: String, CaseIterable, Comparable {
    case DATABASE = "database"
    case PREFERENCES = "preferences"
    case WIDGETS = "widgets"
    case PERSISTED_STATE = "persisted_state"
    case CREDENTIALS = "credentials"

    /// ZIP entry 内的文件名片段(去掉 .json 后缀的 basename)。
    /// 与 原 entryName 字段语义一致 — 跨端兼容, 不要改。
    var entryName: String { rawValue }

    private var sortKey: Int {
        // 原版本 ordinal: DATABASE=0, PREFERENCES=1, WIDGETS=2, PERSISTED_STATE=3, CREDENTIALS=4
        switch self {
        case .DATABASE: return 0
        case .PREFERENCES: return 1
        case .WIDGETS: return 2
        case .PERSISTED_STATE: return 3
        case .CREDENTIALS: return 4
        }
    }

    static func < (lhs: MigrationModule, rhs: MigrationModule) -> Bool {
        return lhs.sortKey < rhs.sortKey
    }

    static func fromEntryName(_ name: String) -> MigrationModule? {
        return MigrationModule(rawValue: name)
    }
}

/// 模块依赖闭包 — 导出时自动带上。
/// 原版本 端: DATABASE → PERSISTED_STATE (后者当前为空, 预留给未来扩展)
enum MigrationModuleDeps {
    static let required: [MigrationModule: Set<MigrationModule>] = [
        .DATABASE: [.PERSISTED_STATE]
    ]

    /// DFS 解出闭包, 与 原版本 MigrationModuleDeps.resolve() 1:1。
    static func resolve(_ selected: Set<MigrationModule>) -> Set<MigrationModule> {
        var out = selected
        var pending = Array(selected)
        while let module = pending.popLast() {
            for dep in required[module] ?? [] {
                if out.insert(dep).inserted {
                    pending.append(dep)
                }
            }
        }
        return out
    }
}

class MigrationPackageException: Error, LocalizedError {
    let message: String
    let cause: Error?
    init(message: String, cause: Error? = nil) {
        self.message = message
        self.cause = cause
    }
    var errorDescription: String? { message }
}

/// 解码后的包内容。
struct MigrationPackageContent {
    let manifest: MigrationBackup.Manifest
    let modules: [MigrationModule: String]
    let unknownModules: [String]
}
