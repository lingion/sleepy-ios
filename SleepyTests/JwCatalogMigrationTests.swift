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

    func testAllCandidateIdentitiesAndExactMetadataRemainUnverified() throws {
        let rows = try catalog()
        XCTAssertEqual(rows.count, 4140)
        let ids = rows.compactMap { $0["catalogId"] as? String }
        XCTAssertEqual(Set(ids).count, 4140)
        // Android v1.0.62 全部稳定身份（UTF-8 排序、换行连接，无末尾换行）。
        let identityBytes = Data(ids.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.joined(separator: "\n").utf8)
        let digest = SHA256.hash(data: identityBytes).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "655c88d589bbebd3ab86456605585f07befba578393e8f82c0fea76230843876")
        let lookup = Dictionary(uniqueKeysWithValues: rows.map { ($0["catalogId"] as! String, $0) })
        let data = try Data(contentsOf: resource("catalog-v1063-candidates"))
        let ledger = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(ledger.count, 1402)
        XCTAssertEqual(ledger.filter { $0["type"] as? String == "jw_home" }.count, 810)
        XCTAssertEqual(ledger.filter { $0["type"] as? String == "sg_asset" }.count, 43)
        XCTAssertEqual(ledger.filter { $0["status"] as? String == "grad_unverified" }.count, 48)
        for expected in ledger {
            let id = try XCTUnwrap(expected["catalogId"] as? String)
            let actual = try XCTUnwrap(lookup[id], id)
            for field in ["name", "type", "status", "url"] {
                XCTAssertEqual(actual[field] as? String, expected[field] as? String, "\(id): \(field)")
            }
            XCTAssertEqual(actual["enableFetch"] as? Bool, false, id)
            XCTAssertTrue(["unverified", "grad_unverified"].contains(actual["status"] as? String ?? ""), id)
            XCTAssertTrue(JwParserRegistry.supports(actual["type"] as? String), id)
        }
        XCTAssertEqual(rows.filter { ["pending", "grad_pending"].contains($0["status"] as? String ?? "") }.count, 1260)
    }

    func testThreeSchoolDecisionsDoNotBorrowAndroidAuthenticationClaims() throws {
        let rows = try catalog()
        for id in ["moe:4133012645", "moe:4123010222"] {
            let row = try XCTUnwrap(rows.first { $0["catalogId"] as? String == id })
            XCTAssertEqual(row["status"] as? String, "unverified")
            XCTAssertEqual(row["enableFetch"] as? Bool, false)
            XCTAssertEqual(row["type"] as? String, id == "moe:4133012645" ? "classic_eams" : "kingo_new")
        }
        let nankai = try XCTUnwrap(rows.first { $0["catalogId"] as? String == "N_南开大学" })
        XCTAssertEqual(nankai["status"] as? String, "supported")
        XCTAssertEqual(nankai["enableFetch"] as? Bool, false)
        XCTAssertEqual(JwSchoolInfo.normalizeStatus(nil), "supported")
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
            let entry = try JwSgAssetBridge.entry(schoolName: name, manifest: manifest)
            let original = try String(contentsOf: root.appendingPathComponent(entry.jsPath), encoding: .utf8)
            let bridge = try JwSgAssetBridge.bridgeJs(schoolName: name, resourceRoot: root)
            XCTAssertTrue(bridge.contains(original), name)
            XCTAssertTrue(bridge.contains("window.webkit.messageHandlers.__sleepyBridge"), name)
        }
    }
}
