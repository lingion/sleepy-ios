// JwImportDraftCodecTests.swift — Android JwImportDraftCodec 契约测试 (GPL-3.0)
// round-trip + 逐条拒绝规则 (schemaVersion/phase/school/courses/periods 校验)。

import XCTest
@testable import Sleepy

final class JwImportDraftCodecTests: XCTestCase {
    /// 镜像 Android JwImportDraftTest.kt 的 `school` fixture (enableFetch = true)。
    private let school = JwSchoolInfo(sortKey: "H", name: "哈尔滨工程大学",
                                      url: "https://jw.example.edu.cn", type: "qz",
                                      status: JwSchoolInfo.STATUS_SUPPORTED,
                                      aliases: ["哈工程"], sortKeyFull: "haerbingongchengdaxue",
                                      enableFetch: true)

    /// 镜像 Android JwImportDraftTest.kt 的 `snapshot` fixture (全部确认字段, 含 smartConfigJson)。
    private func validSnapshot() -> JwImportDraftSnapshot {
        JwImportDraftSnapshot(
            school: school,
            courses: [
                JwCourse(name: "高等数学", room: "教一101", teacher: "张老师", day: 1,
                         startNode: 1, endNode: 2, startWeek: 1, endWeek: 16),
                JwCourse(name: "实验课", room: "实验楼", teacher: "李老师", day: 3,
                         startNode: 5, endNode: 5, startWeek: 2, endWeek: 8, type: 2),
            ],
            periods: [JwImportDraftPeriod(node: 1, start: "08:00", end: "08:45"),
                      JwImportDraftPeriod(node: 2, start: "08:55", end: "09:40")],
            termStartDate: "2026-09-07",
            tableName: "教务导入 - 哈工程",
            smartConfigJson: #"{"enabled":true,"morningStart":"08:00"}"#
        )
    }

    func testRoundTrip() throws {
        // 对齐 Android `snapshot round trips all import confirmation fields`:
        // 整包相等 + smartConfigJson 显式断言。
        let snapshot = validSnapshot()
        let json = JwImportDraftCodec.toJson(snapshot)
        let back = try XCTUnwrap(JwImportDraftCodec.fromJson(json))
        XCTAssertEqual(snapshot, back)
        XCTAssertEqual(snapshot.smartConfigJson, back.smartConfigJson)
    }

    func testOptionalSchoolRoundTrip() throws {
        // 对齐 Android `optional school values remain distinguishable when absent`:
        // 最小学校走 toJson→fromJson 往返 (非仅裸 JSON 解析)。
        let minimal = JwImportDraftSnapshot(
            school: JwSchoolInfo(sortKey: "X", name: "测试学校"),
            courses: validSnapshot().courses,
            periods: [],
            termStartDate: "",
            tableName: "",
            smartConfigJson: validSnapshot().smartConfigJson
        )
        let back = try XCTUnwrap(JwImportDraftCodec.fromJson(JwImportDraftCodec.toJson(minimal)))
        XCTAssertEqual(minimal, back)
        XCTAssertNil(back.school.type)
        XCTAssertEqual([], back.school.aliases)
    }

    func testWebViewDraftRoundTripWithoutCourses() throws {
        // 对齐 Android `webview draft round trips without courses`。
        let draft = JwImportDraftSnapshot(school: school, courses: [], periods: [],
                                          phase: .webViewLogin)
        let back = try XCTUnwrap(JwImportDraftCodec.fromJson(JwImportDraftCodec.toJson(draft)))
        XCTAssertEqual(draft, back)
        XCTAssertEqual(JwImportDraftPhase.webViewLogin, back.phase)
    }

    func testJsonUsesExplicitSchemaAndPreservesCourseOrdering() {
        // 对齐 Android `json uses explicit schema and preserves course ordering` (行 126-132)。
        let json = JwImportDraftCodec.toJson(validSnapshot())
        XCTAssertTrue(json.contains("\"schemaVersion\":1"))
        guard let first = json.range(of: "高等数学"), let second = json.range(of: "实验课") else {
            return XCTFail("课程名应原样出现在 JSON 中")
        }
        XCTAssertLessThan(first.lowerBound, second.lowerBound, "courses 数组顺序必须保留")
        XCTAssertTrue(json.contains("\"type\":2"), "非零 type 必须显式序列化")
    }

    func testDefaultsAndUnknownPhaseRejected() {
        // 缺省 phase = CONFIGURE_CONFIRM
        let json = """
        {"schemaVersion":1,"school":{"sortKey":"Q","name":"X","aliases":[]},"courses":[],"periods":[]}
        """
        XCTAssertEqual(JwImportDraftCodec.fromJson(json)?.phase, .configureConfirm)

        let badPhase = json.replacingOccurrences(of: "\"school\"", with: "\"phase\":\"NOPE\",\"school\"")
        XCTAssertNil(JwImportDraftCodec.fromJson(badPhase), "未知 phase → nil")
    }

    func testSchemaVersionGate() {
        let json = """
        {"schemaVersion":2,"school":{"sortKey":"Q","name":"X"},"courses":[],"periods":[]}
        """
        XCTAssertNil(JwImportDraftCodec.fromJson(json), "schemaVersion != 1 → nil")
        let missingVersion = """
        {"school":{"sortKey":"Q","name":"X"},"courses":[],"periods":[]}
        """
        XCTAssertNil(JwImportDraftCodec.fromJson(missingVersion), "缺省 schemaVersion (-1) → nil")
    }

    func testRejectsNonJsonAndMissingRequiredFields() {
        // 逐条镜像 Android `codec rejects unsupported version and missing required fields` (行 82-84)。
        XCTAssertNil(JwImportDraftCodec.fromJson(#"{"schemaVersion":99}"#), "不支持版本 → nil")
        XCTAssertNil(JwImportDraftCodec.fromJson(#"{"schemaVersion":1,"school":{"name":""},"courses":[]}"#),
                     "school 非法 + 缺 periods → nil")
        XCTAssertNil(JwImportDraftCodec.fromJson("not-json"), "非 JSON 输入 → nil")
        // 单独锁缺 periods: school/courses 全合法, 仅 periods 数组缺失。
        XCTAssertNil(JwImportDraftCodec.fromJson(
            #"{"schemaVersion":1,"school":{"sortKey":"Q","name":"X"},"courses":[]}"#),
                     "缺 periods → nil")
        // 镜像 Android `codec rejects malformed course and period entries`。
        XCTAssertNil(JwImportDraftCodec.fromJson("""
        {"schemaVersion":1,"school":{"sortKey":"X","name":"测试学校"},\
        "courses":[{"name":"","day":1,"startNode":1,"endNode":1,"startWeek":1,"endWeek":1}],\
        "periods":[]}
        """), "空课程名 → nil")
        XCTAssertNil(JwImportDraftCodec.fromJson("""
        {"schemaVersion":1,"school":{"sortKey":"X","name":"测试学校"},\
        "courses":[{"name":"课","day":1,"startNode":1,"endNode":1,"startWeek":1,"endWeek":1}],\
        "periods":[{"node":0,"start":"08:00","end":"08:45"}]}
        """), "node < 1 的时段 → nil")
    }

    func testSchoolValidation() {
        func schoolJson(keys: String = "") -> String {
            let k = keys.isEmpty ? "" : "," + keys
            return "{\"schemaVersion\":1,\"school\":{\"sortKey\":\"Q\",\"name\":\"X\"" + k + "},\"courses\":[],\"periods\":[]}"
        }
        // sortKey 空白 → nil
        let blankKey = "{\"schemaVersion\":1,\"school\":{\"sortKey\":\"  \",\"name\":\"X\"},\"courses\":[],\"periods\":[]}"
        XCTAssertNil(JwImportDraftCodec.fromJson(blankKey))
        // 换行-only 也算空白 (Kotlin isBlank = Character.isWhitespace 含 \n; 旧 .whitespaces 会误放行)
        let newlineKey = "{\"schemaVersion\":1,\"school\":{\"sortKey\":\"\\n\",\"name\":\"X\"},\"courses\":[],\"periods\":[]}"
        XCTAssertNil(JwImportDraftCodec.fromJson(newlineKey), "sortKey=\"\\n\" → nil")
        let newlineName = "{\"schemaVersion\":1,\"school\":{\"sortKey\":\"Q\",\"name\":\"\\n\"},\"courses\":[],\"periods\":[]}"
        XCTAssertNil(JwImportDraftCodec.fromJson(newlineName), "name=\"\\n\" → nil")
        // 空白 alias → 整包 nil
        let badAlias = schoolJson(keys: "\"aliases\":[\"OK\",\"\"]")
        XCTAssertNil(JwImportDraftCodec.fromJson(badAlias))
        // 空白 type 在 Kotlin 里 = 合法存 null (ifBlank{null}), 整包不 nil
        let blankType = schoolJson(keys: "\"type\":\" \"")
        let parsed = JwImportDraftCodec.fromJson(blankType)
        XCTAssertNotNil(parsed)
        XCTAssertNil(parsed?.school.type)
        // type 缺省 = nil; 非空白 = 原样保留
        XCTAssertNil(JwImportDraftCodec.fromJson(schoolJson())?.school.type)
        let withType = schoolJson(keys: "\"type\":\"qt\"")
        XCTAssertEqual(JwImportDraftCodec.fromJson(withType)?.school.type, "qt")
    }

    func testCourseValidation() {
        func courseJson(_ course: String) -> String {
            "{\"schemaVersion\":1,\"school\":{\"sortKey\":\"Q\",\"name\":\"X\"},\"courses\":[\(course)],\"periods\":[]}"
        }
        XCTAssertNil(JwImportDraftCodec.fromJson(courseJson(#"{"name":" "}"#)))
        XCTAssertNil(JwImportDraftCodec.fromJson(courseJson(#"{"name":"C","day":8,"startNode":1,"endNode":2,"startWeek":1,"endWeek":1}"#)))
        XCTAssertNil(JwImportDraftCodec.fromJson(courseJson(#"{"name":"C","day":0,"startNode":1,"endNode":2,"startWeek":1,"endWeek":1}"#)))
        XCTAssertNil(JwImportDraftCodec.fromJson(courseJson(#"{"name":"C","day":1,"startNode":3,"endNode":2,"startWeek":1,"endWeek":1}"#)))
        XCTAssertNil(JwImportDraftCodec.fromJson(courseJson(#"{"name":"C","day":1,"startNode":1,"endNode":2,"startWeek":5,"endWeek":1}"#)))
        XCTAssertNil(JwImportDraftCodec.fromJson(courseJson(#"{"name":"C","day":1,"startNode":1,"endNode":2,"type":-1}"#)))
        // 缺 name = 空串 → 非法
        XCTAssertNil(JwImportDraftCodec.fromJson(courseJson(#"{"day":1,"startNode":1,"endNode":2,"startWeek":1,"endWeek":1}"#)))
        // 合法课程
        let ok = JwImportDraftCodec.fromJson(courseJson(#"{"name":"C","day":1,"startNode":1,"endNode":2,"startWeek":1,"endWeek":16,"type":0}"#))
        XCTAssertEqual(1, ok?.courses.count)
    }

    func testPeriodValidation() {
        func periodJson(_ p: String) -> String {
            "{\"schemaVersion\":1,\"school\":{\"sortKey\":\"Q\",\"name\":\"X\"},\"courses\":[],\"periods\":[\(p)]}"
        }
        XCTAssertNil(JwImportDraftCodec.fromJson(periodJson(#"{"node":0,"start":"08:00","end":"08:45"}"#)))
        XCTAssertNil(JwImportDraftCodec.fromJson(periodJson(#"{"node":1,"start":"8:00","end":"08:45"}"#)))
        XCTAssertNil(JwImportDraftCodec.fromJson(periodJson(#"{"node":1,"start":"08:00","end":"07:00"}"#)))
        XCTAssertNil(JwImportDraftCodec.fromJson(periodJson(#"{"node":1,"start":"","end":"08:45"}"#)), "单边空 = 非法")
        // 双空合法 (自定义时间)
        let bothBlank = JwImportDraftCodec.fromJson(periodJson(#"{"node":1,"start":"","end":""}"#))
        XCTAssertNotNil(bothBlank)
        // 完整合法
        let ok = JwImportDraftCodec.fromJson(periodJson(#"{"node":2,"start":"08:50","end":"09:35"}"#))
        XCTAssertEqual([JwImportDraftPeriod(node: 2, start: "08:50", end: "09:35")], ok?.periods)
    }
}
