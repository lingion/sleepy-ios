import XCTest
@testable import Sleepy

final class JwSchoolStatusRegressionTests: XCTestCase {
    // 顺序：supported / unverified / grad / pending / canImport。
    private let states: [(String, [Bool])] = [
        ("supported", [true, false, false, false, true]),
        ("grad_supported", [true, false, true, false, true]),
        ("unverified", [false, true, false, false, true]),
        ("grad_unverified", [false, true, true, false, true]),
        ("pending", [false, false, false, true, false]),
        ("grad_pending", [false, false, true, true, false]),
        ("legacy", [false, false, false, false, false]),
    ]

    private func school(_ status: String, type: String? = "qz",
                        url: String = "https://jw.example.edu.cn/course") -> JwSchoolInfo {
        JwSchoolInfo(sortKey: "T", name: "状态测试学校", url: url, type: type,
                     status: status, catalogId: "test:status")
    }

    func testAllSevenStatesHaveIndependentAdmissionAndGraduateSemantics() {
        for (status, expected) in states {
            let value = school(status)
            XCTAssertEqual([value.isSupported, value.isUnverified, value.isGrad,
                            value.isPending, value.canImport], expected, status)
        }
    }

    func testUnverifiedRequiresRegisteredProtocolAndBlockedStatesNeverImport() {
        for status in ["unverified", "grad_unverified", "pending", "grad_pending", "legacy"] {
            for type: String? in [nil, "", " \n", "unknown-protocol"] {
                XCTAssertFalse(school(status, type: type).canImport, "\(status): \(type ?? "nil")")
            }
        }
        // 新注册协议只允许未验证候选确认后尝试，pending/legacy 仍然拦停。
        for status in ["pending", "grad_pending", "legacy"] {
            for type in ["qz", "jw_home", "sg_asset"] {
                XCTAssertFalse(school(status, type: type).canImport, "\(status): \(type)")
            }
        }
        for status in ["supported", "grad_supported"] {
            for type: String? in [nil, "", " \n"] {
                // Supported is a catalog status; admission still requires a valid URL.
                XCTAssertTrue(school(status, type: type).isSupported)
                XCTAssertTrue(school(status, type: type).canImport)
            }
        }
    }

    func testURLsGateAllStatesWithoutUpgradingSupport() {
        let valid = ["http://jw.example.edu.cn", "HTTPS://jw.example.edu.cn:8443/a?b=1",
                     " \nhttps://jw.example.edu.cn/course\t"]
        let invalid = ["", " \n", "/course", "jw.example.edu.cn", "https:///",
                       "file:///course", "javascript:alert(1)", "ftp://jw.example.edu.cn",
                       "https://student@jw.example.edu.cn", "https://student:secret@jw.example.edu.cn",
                       "https://@jw.example.edu.cn"]
        for (status, expected) in states {
            for url in valid {
                let value = school(status, url: url)
                XCTAssertTrue(value.hasUrl, url)
                XCTAssertEqual(value.canImport, expected[4], status)
                XCTAssertEqual(value.isSupported, expected[0], status)
            }
            for url in invalid {
                let value = school(status, url: url)
                XCTAssertFalse(value.hasUrl, url)
                XCTAssertFalse(value.canImport, "\(status): \(url)")
            }
        }
    }

    func testNormalizationPreservesLegacyMissingStatusButRejectsUnknownStatus() {
        for raw: String? in [nil, ""] {
            XCTAssertEqual(JwSchoolInfo.normalizeStatus(raw), "supported")
        }
        for (status, _) in states {
            XCTAssertEqual(JwSchoolInfo.normalizeStatus(status), status)
        }
        for raw in ["future-status", "SUPPORTED", " \n"] {
            let value = school(JwSchoolInfo.normalizeStatus(raw))
            XCTAssertEqual(value.status, "pending")
            XCTAssertFalse(value.canImport)
        }
    }

    func testRealDraftCodecRestoresConfirmationForBothUnverifiedStates() throws {
        for type in ["jw_home", "sg_asset"] {
            for status in ["unverified", "grad_unverified"] {
                let original = JwImportDraftSnapshot(school: school(status, type: type), courses: [], periods: [], phase: .webViewLogin)
                let restored = try XCTUnwrap(JwImportDraftCodec.fromJson(JwImportDraftCodec.toJson(original)))
                XCTAssertTrue(restored.school.canImport)
                XCTAssertTrue(restored.requiresSchoolConfirmation, "\(status): \(type)")
                XCTAssertFalse(restored.school.isSupported)
            }
        }
        for (status, _) in states {
            for phase in [JwImportDraftPhase.webViewLogin, .configureConfirm] {
                let original = JwImportDraftSnapshot(school: school(status), courses: [], periods: [], phase: phase)
                let restored = try XCTUnwrap(JwImportDraftCodec.fromJson(JwImportDraftCodec.toJson(original)))
                XCTAssertEqual(restored.school.status, status)
                XCTAssertEqual(restored.school.catalogId, "test:status")
                let expected = phase == .webViewLogin && !["supported", "grad_supported"].contains(status)
                XCTAssertEqual(restored.requiresSchoolConfirmation, expected, "\(status): \(phase)")
            }
        }
        for value in [school("supported", url: ""), school("unverified", type: "unknown-protocol")] {
            let draft = JwImportDraftSnapshot(school: value, courses: [], periods: [], phase: .webViewLogin)
            let restored = try XCTUnwrap(JwImportDraftCodec.fromJson(JwImportDraftCodec.toJson(draft)))
            XCTAssertTrue(restored.requiresSchoolConfirmation)
            XCTAssertFalse(restored.school.canImport)
        }
    }

    func testOldDraftWithoutStatusRetainsSupportedCompatibility() throws {
        let json = #"{"schemaVersion":1,"phase":"WEBVIEW_LOGIN","school":{"sortKey":"T","name":"旧草稿","type":"qz","url":"https://jw.example.edu.cn"},"courses":[],"periods":[]}"#
        let restored = try XCTUnwrap(JwImportDraftCodec.fromJson(json))
        XCTAssertEqual(restored.school.status, "supported")
        XCTAssertTrue(restored.school.canImport)
        XCTAssertFalse(restored.requiresSchoolConfirmation)
    }

    func testActualRegistrySupportsAuditedProtocolSet() {
        // v1.0.63：原 53 项 + jw_home 登记器 + sg_asset 桥；不代表逐校登录验证。
        let expected: Set<String> = [
            "wisedu", "whut", "cqu", "chaoxing", "boya_pp", "eams5", "classic_eams",
            "seu", "zju", "ustc", "scu", "neu", "bjtu", "urp_new", "zf_new", "zf", "zf_1",
            "urp", "qz", "qz_crazy", "qz_br", "qz_with_node", "qz_old", "qz_app", "qz_ieas",
            "ucas", "cf", "pku", "bnuz", "hnust", "hniu", "kingo_new", "kingo_zx", "jz",
            "south_soft", "login_chaoxing", "shuwei_json", "suda_post", "cumtb", "xju_post",
            "new_urp_super", "thu", "nwpu_post", "umooc", "yl", "ecupl", "ecupl_script",
            "ecupl_super", "scau", "kust", "nuit", "yethan", "cf_new", "jw_home", "sg_asset",
        ]
        XCTAssertEqual(expected.count, 55)
        for type in expected {
            XCTAssertTrue(JwParserRegistry.supports(type), type)
            XCTAssertNotNil(JwParserRegistry.factoryFor(type), type)
            XCTAssertTrue(school("unverified", type: type).canImport, type)
            XCTAssertTrue(school("grad_unverified", type: type).canImport, type)
        }
        for type in JwParserRegistry.TYPE_PRIORITY.map(\.0) {
            XCTAssertTrue(expected.contains(type), type)
        }
        for type: String? in [nil, "", "unknown-protocol"] {
            XCTAssertFalse(JwParserRegistry.supports(type))
        }
    }
}
