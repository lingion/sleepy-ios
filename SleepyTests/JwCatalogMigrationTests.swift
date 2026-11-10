import XCTest
import CryptoKit
@testable import Sleepy

final class JwCatalogMigrationTests: XCTestCase {
    private var bundle: Bundle { Bundle(for: JwCatalogMigrationTests.self) }

    private func resource(_ name: String, extension ext: String = "json") throws -> URL {
        try XCTUnwrap(bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "resources")
            ?? Bundle.main.url(forResource: name, withExtension: ext))
    }

    private func catalog() throws -> [[String: Any]] {
        let data = try Data(contentsOf: resource("schools"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    func testCandidateIdentitiesAndPinnedV1064Metadata() throws {
        let rows = try catalog()
        XCTAssertEqual(rows.count, 4140)
        let ids = rows.compactMap { $0["catalogId"] as? String }
        XCTAssertEqual(Set(ids).count, 4140)
        // Android v1.0.62 全部稳定身份（UTF-8 排序、换行连接，无末尾换行）。
        let identityBytes = Data(ids.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.joined(separator: "\n").utf8)
        let digest = SHA256.hash(data: identityBytes).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "655c88d589bbebd3ab86456605585f07befba578393e8f82c0fea76230843876")
        let lookup = Dictionary(uniqueKeysWithValues: rows.map { ($0["catalogId"] as! String, $0) })
        let data = try Data(contentsOf: resource("catalog-v1064-candidates"))
        let ledger = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(ledger.count, 1402)
        XCTAssertEqual(ledger.filter { $0["type"] as? String == "jw_home" }.count, 700)
        XCTAssertEqual(ledger.filter { $0["type"] as? String == "sg_asset" }.count, 42)
        XCTAssertEqual(ledger.filter { $0["status"] as? String == "grad_unverified" }.count, 48)
        for expected in ledger {
            let id = try XCTUnwrap(expected["catalogId"] as? String)
            let actual = try XCTUnwrap(lookup[id], id)
            for field in ["name", "type", "status", "url"] {
                XCTAssertEqual(field == "status" ? JwSchoolInfo.normalizeStatus(actual[field] as? String) : actual[field] as? String, expected[field] as? String, "\(id): \(field)")
            }
            XCTAssertEqual(actual["enableFetch"] as? Bool ?? false, expected["enableFetch"] as? Bool ?? false, id)
            XCTAssertTrue(JwParserRegistry.supports(actual["type"] as? String), id)
        }
        XCTAssertEqual(rows.filter { ["pending", "grad_pending"].contains($0["status"] as? String ?? "") }.count, 1259)
    }

    func testPinnedSchoolMetadataUsesV1064Declarations() throws {
        // These are shipped source declarations, not iOS authentication evidence.
        let rows = try catalog()
        for id in ["moe:4133012645", "moe:4123010222", "N_南开大学"] {
            let row = try XCTUnwrap(rows.first { $0["catalogId"] as? String == id })
            XCTAssertEqual(JwSchoolInfo.normalizeStatus(row["status"] as? String), "supported")
            XCTAssertEqual(row["enableFetch"] as? Bool ?? false, id != "moe:4123010222")
            XCTAssertEqual(row["type"] as? String, id == "moe:4123010222" ? "kingo_new" : "classic_eams")
        }
    }

    func testEverySgSchoolLoadsItsRealBundledAdapterAndLicense() throws {
        let roots = [bundle.resourceURL, Bundle.main.resourceURL].compactMap { $0 }
        let root = try XCTUnwrap(roots.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent(JwSgAssetBridge.manifestPath).path)
        })
        let manifest = try Data(contentsOf: root.appendingPathComponent(JwSgAssetBridge.manifestPath))
        let license = try String(contentsOf: root.appendingPathComponent("third_party/shiguang/LICENSE-MIT.txt"), encoding: .utf8)
        XCTAssertTrue(license.contains("Copyright (c) 2025 星河欲转"))
        XCTAssertTrue(license.contains("Permission is hereby granted"))
        let schools = try catalog().filter { $0["type"] as? String == "sg_asset" }
        XCTAssertEqual(schools.count, 43)
        for school in schools {
            let name = try XCTUnwrap(school["name"] as? String)
            let choices = try JwSgAssetBridge.entries(schoolName: name, manifest: manifest)
            XCTAssertFalse(choices.isEmpty, name)
            if choices.count > 1 {
                XCTAssertThrowsError(try JwSgAssetBridge.entry(schoolName: name, manifest: manifest))
            }
            for choice in choices {
                let entry = try JwSgAssetBridge.entry(schoolName: name, manifest: manifest, selectedAdapterId: choice.id)
                XCTAssertEqual(entry, choice)
                let original = try String(contentsOf: root.appendingPathComponent(entry.jsPath), encoding: .utf8)
                let bridge = try JwSgAssetBridge.bridgeJs(schoolName: name, resourceRoot: root, selectedAdapterId: choice.id)
                XCTAssertTrue(bridge.contains(original), name)
                XCTAssertTrue(bridge.contains("window.webkit.messageHandlers.__sleepyBridge"), name)
            }
        }
    }
}
