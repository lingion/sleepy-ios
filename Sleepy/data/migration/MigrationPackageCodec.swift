// MigrationPackageCodec.swift — ← data/migration/MigrationPackageCodec.kt
// .sleepybackup ZIP 容器读写。坏包在写入本机数据前被拒绝。
// 1:1 对照 Android MigrationPackageCodec.kt,entry 命名/目录结构保持完全一致
// (manifest.json + modules/<name>.json),让跨端包互通。

import Foundation
import ZIPFoundation

/// ZIP 容器读写 — 兼容 Android java.util.zip 输出(标准 DEFLATE 模式)。
enum MigrationPackageCodec {

    static func moduleEntryName(_ module: MigrationModule) -> String {
        return "\(MigrationBackup.ENTRY_MODULES_DIR)/\(module.entryName).json"
    }

    /// 写包: manifest.json + 每个模块一个 <name>.json。
    /// 排序规则: 模 entryName 字典序(与 Android sortedBy { it.entryName } 一致)。
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
    static func read(_ bytes: Data) throws -> MigrationPackageContent {
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

        for entry in archive {
            let name = entry.path
            // Path traversal 防御: 与 Android 1:1
            if name.hasPrefix("/") || name.contains("..") {
                throw MigrationPackageException(message: "illegal zip entry: \(name)")
            }
            if !seenEntries.insert(name).inserted {
                throw MigrationPackageException(message: "duplicate zip entry: \(name)")
            }
            if name == MigrationBackup.ENTRY_MANIFEST {
                // Android: entry 解压异常走外层 catch → "backup ZIP unreadable" 整体失败;
                // 仅 decode 失败才是 "manifest unreadable"。fail-fast, 不留半成品。
                let text: String
                do {
                    text = try readEntryAsString(archive: archive, entry: entry)
                } catch {
                    throw MigrationPackageException(message: "backup ZIP unreadable", cause: error)
                }
                do {
                    manifest = try MigrationBackup.decodeManifest(text)
                } catch {
                    throw MigrationPackageException(message: "manifest unreadable", cause: error)
                }
            } else if name.hasPrefix("\(MigrationBackup.ENTRY_MODULES_DIR)/") && name.hasSuffix(".json") {
                let prefix = "\(MigrationBackup.ENTRY_MODULES_DIR)/"
                let base = String(name.dropFirst(prefix.count).dropLast(".json".count))
                // 与 Android fail-fast 对齐: 坏 entry 必须中止整个 read(),
                // 禁止 `try? ... else { continue }` 静默丢模块后半包导入(坏包在写入本机数据前被拒绝)。
                let text: String
                do {
                    text = try readEntryAsString(archive: archive, entry: entry)
                } catch {
                    throw MigrationPackageException(message: "backup ZIP unreadable", cause: error)
                }
                if let module = MigrationModule.fromEntryName(base) {
                    known[module] = text
                } else {
                    unknown.append(base)
                }
            }
            // 其余 entry(extensions/、未知顶层)静默跳过 — Android 走 zip.closeEntry 也不抛
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

    private static func readEntryAsString(archive: Archive, entry: Entry) throws -> String {
        var buffer = Data()
        _ = try archive.extract(entry, bufferSize: 32 * 1024) { chunk in
            buffer.append(chunk)
        }
        return String(data: buffer, encoding: .utf8) ?? ""
    }
}
