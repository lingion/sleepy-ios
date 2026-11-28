// MigrationPackageCodec.swift — ← data/migration/MigrationPackageCodec.kt
// .sleepybackup ZIP 容器读写。坏包在写入本机数据前被拒绝。
// 1:1 对照 原版本 MigrationPackageCodec.kt,entry 命名/目录结构保持完全一致
// (manifest.json + modules/<name>.json),让跨端包互通。

import Foundation
import ZIPFoundation

/// ZIP 容器读写 — 兼容 原版本 java.util.zip 输出(标准 DEFLATE 模式)。
enum MigrationPackageCodec {

    struct ReadLimits {
        let maximumExpandedBytes: Int
        let maximumEntries: Int

        static let remoteBackup = ReadLimits(maximumExpandedBytes: 256 * 1024 * 1024, maximumEntries: 1_024)
    }

    enum ReadLimitError: Error, Equatable { case expandedBytes, entries }

    static func moduleEntryName(_ module: MigrationModule) -> String {
        return "\(MigrationBackup.ENTRY_MODULES_DIR)/\(module.entryName).json"
    }

    /// 写包: manifest.json + 每个模块一个 <name>.json。
    /// 排序规则: 模 entryName 字典序(与 原 sortedBy { it.entryName } 一致)。
    static func write(modules: [MigrationModule: String], createdAt: Int64) throws -> Data {
        guard !modules.isEmpty else {
            throw MigrationPackageException(message: "migration package needs at least one module")
        }
        let manifest = MigrationBackup.Manifest(
            createdAt: createdAt,
            modules: modules.keys.map { $0.entryName }.sorted()
        )
        let manifestJson = try MigrationBackup.encodeManifest(manifest)

        // 与 JwCaptureDump 不同, 这里直接输出 Data — 用 ZIPFoundation in-memory archive
        // 流程: 临时 zip 文件 → addEntry → Data(contentsOf:) → 删除
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sleepy-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }
        let zipUrl = tmpDir.appendingPathComponent("package.zip")
        guard let archive = try? Archive(url: zipUrl, accessMode: .create) else {
            throw MigrationPackageException(message: "archive open failed for write")
        }

        // 1. manifest.json — 必须最先写
        try addStringEntry(archive: archive, path: MigrationBackup.ENTRY_MANIFEST,
                          content: manifestJson)

        // 2. 各模块 <name>.json — 按 entryName 排序
        let sortedModules = modules.keys.sorted { $0.entryName < $1.entryName }
        for module in sortedModules {
            try addStringEntry(archive: archive, path: moduleEntryName(module),
                              content: modules[module] ?? "")
        }

        return try Data(contentsOf: zipUrl)
    }

    /// 读包 + 校验: illegal path / duplicate entry / missing manifest / wrong format /
    /// newer-version 包 → 全部 throw MigrationPackageException,在写本机数据前 fail-fast。
    static func read(_ bytes: Data, limits: ReadLimits? = nil) throws -> MigrationPackageContent {
        // 解到临时文件, ZIPFoundation 不支持 Data 入参 → URL only
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sleepy-migration-read-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }
        let zipUrl = tmpDir.appendingPathComponent("package.zip")
        try bytes.write(to: zipUrl)

        guard let archive = try? Archive(url: zipUrl, accessMode: .read) else {
            throw MigrationPackageException(message: "backup ZIP unreadable")
        }

        var known: [MigrationModule: String] = [:]
        var unknown: [String] = []
        var manifest: MigrationBackup.Manifest?
        var seenEntries: Set<String> = []

        var remaining = limits.map { max(0, $0.maximumExpandedBytes) }
        func readPayload(_ entry: Entry) throws -> String {
            do {
                let (text, length) = try readEntryAsString(archive: archive, entry: entry, remaining: remaining)
                if let budget = remaining { remaining = budget - length }
                return text
            } catch let limit as ReadLimitError {
                throw limit
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw MigrationPackageException(message: "backup ZIP unreadable", cause: error)
            }
        }

        for entry in archive {
            try Task.checkCancellation()
            if let limits = limits, seenEntries.count >= limits.maximumEntries { throw ReadLimitError.entries }
            let name = entry.path
            if name.hasPrefix("/") || name.contains("..") {
                throw MigrationPackageException(message: "illegal zip entry: \(name)")
            }
            if !seenEntries.insert(name).inserted {
                throw MigrationPackageException(message: "duplicate zip entry: \(name)")
            }
            if name == MigrationBackup.ENTRY_MANIFEST {
                let text = try readPayload(entry)
                do {
                    manifest = try MigrationBackup.decodeManifest(text)
                } catch {
                    throw MigrationPackageException(message: "manifest unreadable", cause: error)
                }
            } else if name.hasPrefix("\(MigrationBackup.ENTRY_MODULES_DIR)/") && name.hasSuffix(".json") {
                let prefix = "\(MigrationBackup.ENTRY_MODULES_DIR)/"
                let base = String(name.dropFirst(prefix.count).dropLast(".json".count))
                let text = try readPayload(entry)
                if let module = MigrationModule.fromEntryName(base) {
                    known[module] = text
                } else {
                    unknown.append(base)
                }
            }
            // 其余 entry(extensions/、未知顶层)静默跳过 — 原版本 走 zip.closeEntry 也不抛
        }

        guard let m = manifest else {
            throw MigrationPackageException(message: "manifest.json missing")
        }
        if m.format != MigrationBackup.FORMAT {
            throw MigrationPackageException(message: "unknown backup format: \(m.format)")
        }
        if m.version > MigrationBackup.VERSION {
            throw MigrationPackageException(message: "backup made by newer Sleepy (v\(m.version))")
        }
        return MigrationPackageContent(manifest: m, modules: known, unknownModules: unknown.sorted())
    }

    // MARK: - helpers

    private static func addStringEntry(archive: Archive, path: String, content: String) throws {
        let data = Data(content.utf8)
        var cursor = 0
        try archive.addEntry(with: path, type: .file,
                             uncompressedSize: Int64(data.count),
                             compressionMethod: .deflate,
                             bufferSize: 32 * 1024,
                             progress: nil) { _, size in
            if cursor >= data.count { return Data() }
            let end = min(cursor + size, data.count)
            let chunk = data.subdata(in: cursor..<end)
            cursor = end
            return chunk
        }
    }

    private static func readEntryAsString(archive: Archive, entry: Entry, remaining: Int?) throws -> (String, Int) {
        guard entry.type == .file else { throw MigrationPackageException(message: "non-file backup entry") }
        if let limit = remaining, entry.uncompressedSize > UInt64(limit) { throw ReadLimitError.expandedBytes }
        var buffer = Data()
        let checksum = try archive.extract(entry, bufferSize: 32 * 1024) { chunk in
            try Task.checkCancellation()
            if let limit = remaining, chunk.count > limit - buffer.count { throw ReadLimitError.expandedBytes }
            buffer.append(chunk)
        }
        guard checksum == entry.checksum, UInt64(buffer.count) == entry.uncompressedSize,
              let text = String(data: buffer, encoding: .utf8) else {
            throw MigrationPackageException(message: "damaged backup entry")
        }
        return (text, buffer.count)
    }
}

/// Decoded, not applied. Both Files and WebDAV can present a confirmation without
/// opening the production database or capturing a preference write.
struct MigrationPreparedArchive {
    let modules: [MigrationModule]
    let unknownModules: [String]
    let database: MigrationDatabaseCodec.DatabaseSnapshot?
    let preferences: [MigrationModule: MigrationPrefsCodec.PrefsSnapshot]

    static func decode(_ bytes: Data, limits: MigrationPackageCodec.ReadLimits? = nil) throws -> Self {
        let content = try MigrationPackageCodec.read(bytes, limits: limits)
        var database: MigrationDatabaseCodec.DatabaseSnapshot?
        var preferences: [MigrationModule: MigrationPrefsCodec.PrefsSnapshot] = [:]
        for (module, payload) in content.modules {
            try Task.checkCancellation()
            switch module {
            case .DATABASE: database = try MigrationDatabaseCodec.decode(payload)
            case .PREFERENCES, .WIDGETS, .PERSISTED_STATE: preferences[module] = try MigrationPrefsCodec.decode(payload)
            case .CREDENTIALS: break
            }
        }
        return Self(modules: content.modules.keys.sorted(), unknownModules: content.unknownModules,
                    database: database, preferences: preferences)
    }

    static func decodeRemote(_ bytes: Data) throws -> Self {
        let prepared = try decode(bytes, limits: .remoteBackup)
        // A server archive cannot use a file name as an arbitrary UserDefaults domain.
        // Keep known cross-platform files; platform-specific file names do not acquire a local destination.
        let supported = prepared.preferences.reduce(into: [MigrationModule: MigrationPrefsCodec.PrefsSnapshot]()) { result, item in
            let allowed = Set(MigrationPrefsFileMap.files(of: item.key))
            result[item.key] = .init(files: item.value.files.filter { allowed.contains($0.key) })
        }
        guard prepared.database != nil || supported.values.contains(where: { !$0.files.isEmpty }) else {
            throw MigrationPackageException(message: "remote backup has no restorable modules")
        }
        return Self(modules: prepared.modules, unknownModules: prepared.unknownModules,
                    database: prepared.database, preferences: supported)
    }
}
