// MigrationPackageCodecTests.swift — ← MigrationPackageCodecTest.kt (逐用例)
// 纯逻辑往返测试: ZIP 容器 write/read 的 manifest + modules 语义、
// 未知模块前向兼容、坏包 fail-fast(在写入本机数据前被拒绝)、依赖闭包解析。

import XCTest
import ZIPFoundation
@testable import Sleepy

final class MigrationPackageCodecTests: XCTestCase {

    // Android: `write and read preserves manifest and module JSON`
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

    // Android: `unknown module is reported and ignored`
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

    // Android: `invalid bytes are rejected before import`
    func testInvalidBytesAreRejectedBeforeImport() {
        XCTAssertThrowsError(
            try MigrationPackageCodec.read(Data("not a zip".utf8))
        ) { error in
            XCTAssertTrue(error is MigrationPackageException,
                          "expected MigrationPackageException, got \(type(of: error))")
        }
    }

    // Android: `database selection receives persisted state dependency`
    func testDatabaseSelectionReceivesPersistedStateDependency() {
        XCTAssertEqual(
            MigrationModuleDeps.resolve([.DATABASE]),
            Set([.DATABASE, .PERSISTED_STATE])
        )
    }

    // MARK: - helpers

    /// 与 Android unknownModulePackage() 等价: manifest(modules=["future_settings"])
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
