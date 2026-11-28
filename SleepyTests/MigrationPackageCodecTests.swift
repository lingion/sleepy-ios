// MigrationPackageCodecTests.swift — ← MigrationPackageCodecTest.kt (逐用例)
// 纯逻辑往返测试: ZIP 容器 write/read 的 manifest + modules 语义、
// 未知模块前向兼容、坏包 fail-fast(在写入本机数据前被拒绝)、依赖闭包解析。

import XCTest
import ZIPFoundation
@testable import Sleepy

final class MigrationPackageCodecTests: XCTestCase {

    // 原版本: `write and read preserves manifest and module JSON`
    func testWriteAndReadPreservesManifestAndModuleJSON() throws {
        let bytes = try MigrationPackageCodec.write(
            modules: [
                .PREFERENCES: "{\"theme\":\"dark\"}",
                .DATABASE: "{\"tables\":[]}",
                .PERSISTED_STATE: "{\"drafts\":[]}"
            ],
            createdAt: 1234
        )

        let result = try MigrationPackageCodec.read(bytes)

        XCTAssertEqual(result.manifest.format, MigrationBackup.FORMAT)
        XCTAssertEqual(result.manifest.version, 1)
        XCTAssertEqual(result.manifest.createdAt, 1234)
        XCTAssertEqual(result.modules[.PREFERENCES], "{\"theme\":\"dark\"}")
        XCTAssertEqual(result.manifest.modules, ["database", "persisted_state", "preferences"])
    }

    // 原版本: `unknown module is reported and ignored`
    func testUnknownModuleIsReportedAndIgnored() throws {
        let known = try MigrationPackageCodec.write(
            modules: [.PREFERENCES: "{}"],
            createdAt: 1
        )
        XCTAssertFalse(known.isEmpty)

        let result = try MigrationPackageCodec.read(unknownModulePackage())
        XCTAssertEqual(result.unknownModules, ["future_settings"])
        XCTAssertTrue(result.modules.isEmpty)
    }

    // 原版本: `invalid bytes are rejected before import`
    func testInvalidBytesAreRejectedBeforeImport() {
        XCTAssertThrowsError(
            try MigrationPackageCodec.read(Data("not a zip".utf8))
        ) { error in
            XCTAssertTrue(error is MigrationPackageException,
                          "expected MigrationPackageException, got \(type(of: error))")
        }
    }

    // 原版本: `database selection receives persisted state dependency`
    func testDatabaseSelectionReceivesPersistedStateDependency() {
        XCTAssertEqual(
            MigrationModuleDeps.resolve([.DATABASE]),
            Set([.DATABASE, .PERSISTED_STATE])
        )
    }

    func testRemoteReadCapsCumulativeExpandedBytes() throws {
        // Each entry fits alone, but together exceed the expanded-byte budget.
        let payload = String(repeating: "a", count: 20_000)
        let bytes = try MigrationPackageCodec.write(modules: [
            .DATABASE: #"{"padding":"\#(payload)"}"#,
            .PREFERENCES: #"{"padding":"\#(payload)"}"#
        ], createdAt: 1234)
        XCTAssertLessThan(bytes.count, 25_000)
        XCTAssertThrowsError(try MigrationPackageCodec.read(bytes,
            limits: .init(maximumExpandedBytes: 25_000, maximumEntries: 16))) { error in
            XCTAssertEqual(error as? MigrationPackageCodec.ReadLimitError, .expandedBytes)
        }
        XCTAssertEqual(try MigrationPackageCodec.read(bytes,
            limits: .init(maximumExpandedBytes: 50_000, maximumEntries: 16)).modules.count, 2)
    }

    func testRemoteReadCountsManifestAndEveryArchiveEntry() throws {
        let bytes = try MigrationPackageCodec.write(modules: [.DATABASE: "{}", .PREFERENCES: "{}"], createdAt: 1)
        XCTAssertThrowsError(try MigrationPackageCodec.read(bytes,
            limits: .init(maximumExpandedBytes: 10_000, maximumEntries: 2))) { error in
            XCTAssertEqual(error as? MigrationPackageCodec.ReadLimitError, .entries)
        }
        XCTAssertEqual(try MigrationPackageCodec.read(bytes,
            limits: .init(maximumExpandedBytes: 10_000, maximumEntries: 3)).modules.count, 2)
    }

    func testRemotePreflightDecodesAllKnownPayloadsBeforeConfirmation() throws {
        let invalid = try MigrationPackageCodec.write(modules: [.DATABASE: "{}", .PREFERENCES: "[]"], createdAt: 1)
        XCTAssertThrowsError(try MigrationPreparedArchive.decodeRemote(invalid))
        let valid = try MigrationPackageCodec.write(modules: [.DATABASE: "{}", .PREFERENCES: "{}"], createdAt: 1)
        let ready = try MigrationPreparedArchive.decodeRemote(valid)
        XCTAssertEqual(ready.modules, [.DATABASE, .PREFERENCES])
        XCTAssertEqual(ready.database?.timeTables, [])
        XCTAssertEqual(ready.preferences[.PREFERENCES]?.files.count, 0)
    }

    func testRemotePreflightRejectsArchiveWithoutRestorableModules() {
        XCTAssertThrowsError(try MigrationPreparedArchive.decodeRemote(unknownModulePackage()))
    }

    func testRemotePreflightKeepsOnlySupportedPreferenceDomains() throws {
        let bytes = try MigrationPackageCodec.write(modules: [.PREFERENCES:
            #"{"files":{"sleepy_prefs":{"entries":{}},"foreign_store":{"entries":{}}}}"#
        ], createdAt: 1)
        let archive = try MigrationPreparedArchive.decodeRemote(bytes)
        XCTAssertEqual(archive.preferences[.PREFERENCES]?.files.keys.sorted(), ["sleepy_prefs"])
    }

    // MARK: - helpers

    /// 与 原版本 unknownModulePackage() 等价: manifest(modules=["future_settings"])
    /// + modules/future_settings.json 的有效 ZIP, 走临时文件构造。
    private func unknownModulePackage() -> Data {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sleepy-codec-test-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let zipUrl = tmpDir.appendingPathComponent("unknown.zip")
        let archive = try! Archive(url: zipUrl, accessMode: .create)

        let manifest = MigrationBackup.Manifest(createdAt: 1, modules: ["future_settings"])
        let manifestJson = try! MigrationBackup.encodeManifest(manifest)
        addTextEntry(archive, path: MigrationBackup.ENTRY_MANIFEST, text: manifestJson)
        addTextEntry(archive, path: "modules/future_settings.json", text: "{\"value\":true}")

        return try! Data(contentsOf: zipUrl)
    }

    private func addTextEntry(_ archive: Archive, path: String, text: String) {
        let data = Data(text.utf8)
        var cursor = 0
        try! archive.addEntry(with: path, type: .file,
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
}
