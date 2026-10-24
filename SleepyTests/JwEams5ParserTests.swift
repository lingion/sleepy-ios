// JwEams5ParserTests.swift — ← JwEams5ParserTest.kt + HfutIssue46LayoutNodeMappingTest.kt (v1.0.61)
//
// 合工大 EAMS5 (金智 eams5-student) + 安徽大学 print-data 双形态解析器测试。
// 用例逐一对应 Android 侧两份测试文件:
//   - JwEams5ParserTest.kt (681 行, HFUT 行映射 / AHU 优先级 / parseWeekRanges RLE / teacher 6 级 fallback)
//   - HfutIssue46LayoutNodeMappingTest.kt (issue #46: courseUnitList 布局查表, 宣城 12 节次)
//
// fixture (SleepyTests/resources/, 与 Android test resources 逐字节一致):
//   - eams5-schedule-table-datum.sample.json   ← jw/fixtures/eams5/schedule-table-datum.sample.json
//   - eams5-get-data-ahu.sample.json           ← jw/fixtures/eams5/get-data-ahu.sample.json
//   - eams5-hfut-xc-datum-with-layout.json     ← jw/fixtures/eams5/hfut-xc-datum-with-layout.json

import XCTest
@testable import Sleepy

final class JwEams5ParserTests: XCTestCase {

    // MARK: - Fixture loading

    private func loadJson(name: String) throws -> String {
        let bundle = Bundle(for: JwEams5ParserTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "resources") else {
            XCTFail("测试资源 \(name).json 应存在")
            throw NSError(domain: "test", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func parseDatumSample() throws -> [JwCourse] {
        try JwEams5Parser(try loadJson(name: "eams5-schedule-table-datum.sample")).generateCourseList()
    }

    private func parseAhuSample() throws -> [JwCourse] {
        try JwEams5Parser(try loadJson(name: "eams5-get-data-ahu.sample")).generateCourseList()
    }

    private func parseLayoutSample() throws -> [JwCourse] {
        try JwEams5Parser(try loadJson(name: "eams5-hfut-xc-datum-with-layout")).generateCourseList()
    }

    // MARK: - HFUT 形态 (schedule-table/datum)

    func test_eams5_total_count_equals_schedule_rows() throws {
        XCTAssertEqual(4, try parseDatumSample().count)
    }

    func test_eams5_1001_gaoshu_maps_name_and_time() throws {
        let courses = try parseDatumSample()
        let c = try XCTUnwrap(courses.first { $0.name == "高等数学" })
        XCTAssertEqual(1, c.day)
        // startTime=800 (08:00) → 推断节点 1; periods=2 → 节点 2
        XCTAssertEqual(1, c.startNode)
        XCTAssertEqual(2, c.endNode)
        XCTAssertEqual(1, c.startWeek)
        XCTAssertEqual(1, c.endWeek)
        XCTAssertEqual(0, c.type)
        XCTAssertEqual("张三", c.teacher)
        XCTAssertEqual("A楼101", c.room)
    }

    func test_eams5_1002_wuli_weekday_mapping() throws {
        let courses = try parseDatumSample()
        let c = try XCTUnwrap(courses.first { $0.name == "大学物理" })
        XCTAssertEqual(3, c.day)
        // 10:10 → node3 (上午第二大段), endTime 12:00 不可映射 → 3 + 2 - 1 = 4
        XCTAssertEqual(3, c.startNode)
        XCTAssertEqual(4, c.endNode)
        XCTAssertEqual(1, c.startWeek)
    }

    func test_eams5_1003_shiyan_4_period_row() throws {
        let courses = try parseDatumSample()
        let c = try XCTUnwrap(courses.first { $0.name == "数据结构实验" })
        XCTAssertEqual(5, c.day)
        // 14:00 → node5; periods=4 → 节点 8
        XCTAssertEqual(5, c.startNode)
        XCTAssertEqual(8, c.endNode)
        XCTAssertEqual("实验楼401", c.room)
        XCTAssertEqual("王五", c.teacher)
    }

    func test_eams5_lessonId_not_in_list_falls_back_to_id_string() throws {
        let parser = JwEams5Parser("""
            {
              "result": {
                "lessonList": [],
                "scheduleList": [
                  {
                    "lessonId": 9999,
                    "room": null,
                    "weekday": 2,
                    "personName": "外教",
                    "weekIndex": 3,
                    "startTime": 1900,
                    "periods": 1,
                    "endTime": 1950,
                    "date": "2024-09-10",
                    "lessonType": ""
                  }
                ]
              }
            }
            """)
        let courses = try parser.generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual("9999", courses[0].name)
        XCTAssertEqual("", courses[0].room)
    }

    func test_eams5_cross_section_endtime_uses_periods() throws {
        // 实验课 14:00-17:55 (跨下午两节次): 17:55 不在段起点 → periods 兜底 5 + 4 - 1 = 8
        let parser = JwEams5Parser("""
            { "result": { "lessonList": [], "scheduleList": [
                { "lessonId": 7, "room": null, "weekday": 4, "personName": "X", "weekIndex": 6,
                  "startTime": 1400, "periods": 4, "endTime": 1755, "date": "2024-09-26", "lessonType": "" }
            ] } }
            """)
        let courses = try parser.generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual(8, courses[0].endNode)
    }

    func test_eams5_confidence_high_for_datum_shape() throws {
        let p = JwEams5Parser(try loadJson(name: "eams5-schedule-table-datum.sample"))
        XCTAssertGreaterThanOrEqual(p.confidenceValue, 80)
    }

    func test_eams5_matched_features_lists_datum_anchors() throws {
        let p = JwEams5Parser(try loadJson(name: "eams5-schedule-table-datum.sample"))
        let feats = p.matchedFeatureList
        XCTAssertTrue(feats.contains { $0.contains("scheduleList") })
        XCTAssertTrue(feats.contains { $0.contains("lessonList") })
    }

    func test_eams5_unmappable_start_falls_back_to_periods_not_dropped() throws {
        // KDoc 承诺: startTime 不可映射时退 startNode=1, endNode = 1 + periods - 1
        let p = JwEams5Parser("""
        {"result": {
          "lessonList": [{"id": 9001, "courseName": "兜底课"}],
          "scheduleList": [
            {"lessonId": 9001, "weekday": 2, "weekIndex": 3,
             "startTime": 0, "endTime": 0, "periods": 3}
          ]
        }}
        """)
        let courses = try p.generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual(1, courses[0].startNode)
        XCTAssertEqual(3, courses[0].endNode)
    }

    func test_eams5_unmappable_start_without_periods_drops_row() throws {
        let p = JwEams5Parser("""
        {"result": {
          "lessonList": [{"id": 9002, "courseName": "无信息课"}],
          "scheduleList": [
            {"lessonId": 9002, "weekday": 2, "weekIndex": 3,
             "startTime": 0, "endTime": 0, "periods": 0}
          ]
        }}
        """)
        XCTAssertTrue(try p.generateCourseList().isEmpty)
    }

    // MARK: - AHU print-data 形态 (studentTableVms[0].activities[])

    func test_ahu_print_data_total_count_after_rle_expansion() throws {
        // 5 activities RLE 展开: 1-16(1) + 1-8双(1) + 5,7,9(3) + 1-16单(1) + 8,10,12,14(4) = 10
        XCTAssertEqual(10, try parseAhuSample().count)
    }

    func test_ahu_print_data_1001_gaoshu_fields() throws {
        let courses = try parseAhuSample()
        let c = try XCTUnwrap(courses.first { $0.name == "高等数学" })
        XCTAssertEqual(1, c.day)
        XCTAssertEqual(1, c.startNode)   // startUnit 直接给定
        XCTAssertEqual(2, c.endNode)
        XCTAssertEqual(1, c.startWeek)   // "1-16" → RLE 全周
        XCTAssertEqual(16, c.endWeek)
        XCTAssertEqual("张教授", c.teacher)
        XCTAssertEqual("龙河校区 博学南楼 A101", c.room)
    }

    func test_ahu_print_data_1002_multi_teacher_join() throws {
        let courses = try parseAhuSample()
        let c = try XCTUnwrap(courses.first { $0.name == "大学物理" })
        XCTAssertEqual("李副教授/钱讲师", c.teacher)
        XCTAssertEqual(2, c.day)
        XCTAssertEqual(3, c.startNode)
        XCTAssertEqual(4, c.endNode)
        XCTAssertEqual(2, c.startWeek)   // "1-8双" JwParity 抬到首个偶数
        XCTAssertEqual(8, c.endWeek)
        XCTAssertEqual(2, c.type)
    }

    func test_ahu_print_data_1003_discrete_weeks_emit_multiple() throws {
        let courses = try parseAhuSample()
        let ds = try XCTUnwrap(courses.first { $0.name == "数据结构" })
        XCTAssertEqual(3, ds.day)
        XCTAssertEqual(5, ds.startNode)
        XCTAssertEqual(6, ds.endNode)
        XCTAssertEqual(5, ds.startWeek)  // "5,7,9" 离散第 1 段
        XCTAssertEqual(3, courses.filter { $0.name == "数据结构" }.count)  // Swift Array 无 count(predicate) — Kotlin 直觉
    }

    func test_ahu_print_data_1005_evening_bitmap() throws {
        let courses = try parseAhuSample()
        let c = try XCTUnwrap(courses.first { $0.name == "形势与政策" })
        XCTAssertEqual(9, c.startNode)
        XCTAssertEqual(10, c.endNode)
        XCTAssertEqual(5, c.day)
        XCTAssertEqual(8, c.startWeek)   // "8,10,12,14" → 首个 8
    }

    func test_ahu_print_data_1003_campus_room_join() throws {
        let courses = try parseAhuSample()
        let c = try XCTUnwrap(courses.first { $0.name == "数据结构" })
        XCTAssertEqual("磬苑校区 计算机学院实验楼 301", c.room)
    }

    func test_ahu_print_data_confidence_is_100() throws {
        let p = JwEams5Parser(try loadJson(name: "eams5-get-data-ahu.sample"))
        XCTAssertEqual(100, p.confidenceValue)
        XCTAssertTrue(p.matchedFeatureList.contains { $0.contains("studentTableVms") })
    }

    func test_ahu_print_data_precedence_over_lessons_and_hfut() throws {
        // 三层同现时 print-data activities 优先 (5 仓共识)
        let p = JwEams5Parser("""
        {
          "code": 200,
          "studentTableVms": [{
            "activities": [
              {"lessonId": "A1", "courseName": "AHU优先课",
               "teacherNames": ["T"], "campus": "X", "building": "Y", "room": "Z",
               "weekday": 1, "weekIndexes": "1-16", "startUnit": 1, "endUnit": 2}
            ]
          }],
          "data": { "lessons": [
            {"lessonId": 1, "courseName": "AHU_metadata_课", "teacher": "T", "room": "R",
             "weekday": 1, "weekIndex": 1, "startTime": 800, "endTime": 950, "periods": 2}
          ]},
          "result": { "lessonList": [{"id":"99","courseName":"HFUT抢课"}],
                      "scheduleList": [{"lessonId":99, "weekday":1, "weekIndex":1,
                                        "startTime":800, "endTime":950, "periods":2}]}
        }
        """)
        let courses = try p.generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual("AHU优先课", courses[0].name)
        XCTAssertEqual("X Y Z", courses[0].room)
    }

    func test_ahu_data_lessons_fallback_confidence_85() throws {
        let p = JwEams5Parser("""
        {
          "code": 200,
          "data": { "lessons": [
            {"lessonId": 1, "courseName": "AHU_meta_only", "teacher": "T", "room": "R",
             "weekday": 1, "weekIndex": 1, "startTime": 800, "endTime": 950, "periods": 2}
          ]}
        }
        """)
        XCTAssertEqual(85, p.confidenceValue)
        XCTAssertEqual(1, try p.generateCourseList().count)
    }

    func test_ahu_empty_weekindexes_falls_back_to_week_1() throws {
        let p = JwEams5Parser("""
        {
          "code": 200,
          "studentTableVms": [{
            "activities": [
              {"lessonId": "X", "courseName": "TestNoWeek",
               "teacherNames": ["T"], "weekday": 1, "weekIndexes": "",
               "startUnit": 1, "endUnit": 2}
            ]
          }]
        }
        """)
        let courses = try p.generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual(1, courses[0].startWeek)
    }

    // MARK: - parseWeekRanges 完整 RLE (12 例, 经 generateCourseList 行为锁定)

    private func ahuWeek(_ weekIndexes: String) throws -> [JwCourse] {
        let p = JwEams5Parser("""
        {"studentTableVms": [{"activities": [
          {"lessonId": "A", "courseName": "T", "teacherNames": ["t"],
           "weekday": 1, "weekIndexes": "\(weekIndexes)", "startUnit": 1, "endUnit": 2}
        ]}]}
        """)
        return try p.generateCourseList()
    }

    func test_week_ranges_1_16dan_type1() throws {
        let c = try XCTUnwrap(ahuWeek("1-16单").first)
        XCTAssertEqual(1, c.startWeek)
        XCTAssertEqual(16, c.endWeek)   // JwParity 不收缩 endWeek
        XCTAssertEqual(1, c.type)
    }

    func test_week_ranges_2_15shuang_type2() throws {
        let c = try XCTUnwrap(ahuWeek("2-15双").first)
        XCTAssertEqual(2, c.startWeek)
        XCTAssertEqual(15, c.endWeek)
        XCTAssertEqual(2, c.type)
    }

    func test_week_ranges_1_16_full_week_type0() throws {
        let c = try XCTUnwrap(ahuWeek("1-16").first)
        XCTAssertEqual(1, c.startWeek)
        XCTAssertEqual(16, c.endWeek)
        XCTAssertEqual(0, c.type)
    }

    func test_week_ranges_1_16shuang_start_raised_to_even() throws {
        let c = try XCTUnwrap(ahuWeek("1-16双").first)
        XCTAssertEqual(2, c.startWeek)   // JwParity 抬到首个偶数
        XCTAssertEqual(2, c.type)
    }

    func test_week_ranges_1_16dan_start_kept_odd() throws {
        let c = try XCTUnwrap(ahuWeek("1-16单").first)
        XCTAssertEqual(1, c.startWeek)
    }

    func test_week_ranges_discrete_8_10_12_14_emits_four() throws {
        let cs = try ahuWeek("8,10,12,14")
        XCTAssertEqual(4, cs.count)
        XCTAssertEqual([8, 10, 12, 14], cs.map { $0.startWeek })
        cs.forEach { XCTAssertEqual(0, $0.type) }
    }

    func test_week_ranges_combined_1_8_10_16_emits_two() throws {
        let cs = try ahuWeek("1-8,10-16")
        XCTAssertEqual(2, cs.count)
        XCTAssert((1, 8, 0) == (cs[0].startWeek, cs[0].endWeek, cs[0].type))
        XCTAssert((10, 16, 0) == (cs[1].startWeek, cs[1].endWeek, cs[1].type))
    }

    func test_week_ranges_5_5dan_no_inversion() throws {
        let c = try XCTUnwrap(ahuWeek("5-5单").first)
        XCTAssertEqual(5, c.startWeek)
        XCTAssertEqual(5, c.endWeek)
        XCTAssertEqual(1, c.type)
    }

    func test_week_ranges_6_6shuang_endpoints_equal() throws {
        let c = try XCTUnwrap(ahuWeek("6-6双").first)
        XCTAssertEqual(6, c.startWeek)
        XCTAssertEqual(6, c.endWeek)
        XCTAssertEqual(2, c.type)
    }

    func test_week_ranges_english_even_type2() throws {
        let c = try XCTUnwrap(ahuWeek("1-16 even").first)
        XCTAssertEqual(2, c.type)
    }

    func test_week_ranges_english_odd_type1() throws {
        let c = try XCTUnwrap(ahuWeek("1-16 odd").first)
        XCTAssertEqual(1, c.type)
    }

    func test_week_ranges_5_12_basic() throws {
        let c = try XCTUnwrap(ahuWeek("5-12").first)
        XCTAssertEqual(5, c.startWeek)
        XCTAssertEqual(12, c.endWeek)
    }

    func test_week_ranges_single_value_5zhou() throws {
        let c = try XCTUnwrap(ahuWeek("5周").first)
        XCTAssertEqual(5, c.startWeek)
        XCTAssertEqual(5, c.endWeek)
    }

    func test_week_ranges_mixed_dan_shuang_each_segment_independent() throws {
        // 段独立判定 (SEU 同型 bug fix): 不能整串 first-match
        let cs = try ahuWeek("1-8周(单),9-16周(双)")
        XCTAssertEqual(2, cs.count)
        XCTAssertEqual(1, cs[0].startWeek)
        XCTAssertEqual(1, cs[0].type)
        XCTAssertEqual(10, cs[1].startWeek)   // JwParity 抬
        XCTAssertEqual(2, cs[1].type)
    }

    func test_week_ranges_empty_bitmap_falls_back() throws {
        let c = try XCTUnwrap(ahuWeek("").first)
        XCTAssert((1, 1, 0) == (c.startWeek, c.endWeek, c.type))
    }

    // 直接对 static parseWeekRanges 的边界回归 (锁定 issue #3 split-limit-2 对齐):
    // Android bare.split("-", limit = 2) 且 b 解析失败回退 a → "5-12-16" → (5,5,parity)
    func test_week_ranges_malformed_multi_dash_behaves_like_split_limit_2() {
        let r = JwEams5Parser.parseWeekRanges("5-12-16")
        XCTAssertEqual(1, r.count)
        XCTAssert((5, 5, 0) == r[0])
    }

    func test_week_ranges_malformed_multi_dash_with_parity() {
        let r = JwEams5Parser.parseWeekRanges("3-4-5单")
        XCTAssertEqual(1, r.count)
        XCTAssert((3, 3, 1) == r[0])   // a=3, b="4-5" 解析失败 → b=a=3
    }

    // MARK: - teacher 字段多形态 fallback (5 仓共识)

    private func ahuTeacher(_ json: String) throws -> String {
        let p = JwEams5Parser("""
        {"studentTableVms": [{"activities": [
          \(json)
        ]}]}
        """)
        let courses = try p.generateCourseList()
        return try XCTUnwrap(courses.first).teacher
    }

    func test_teacher_teacherNames_join_slash() throws {
        XCTAssertEqual("张三/李四", try ahuTeacher(
            #"{"lessonId": "A", "courseName": "Test", "teacherNames": ["张三", "李四"], "weekday": 1, "weekIndexes": "1-16", "startUnit": 1, "endUnit": 2}"#))
    }

    func test_teacher_teachers_array_fallback() throws {
        XCTAssertEqual("甲/乙/丙", try ahuTeacher(
            #"{"lessonId": "A", "courseName": "Test", "teachers": ["甲", "乙", "丙"], "weekday": 1, "weekIndexes": "1-16", "startUnit": 1, "endUnit": 2}"#))
    }

    func test_teacher_teacherList_array_fallback() throws {
        XCTAssertEqual("王老师", try ahuTeacher(
            #"{"lessonId": "A", "courseName": "Test", "teacherList": ["王老师"], "weekday": 1, "weekIndexes": "1-16", "startUnit": 1, "endUnit": 2}"#))
    }

    func test_teacher_single_string_fallback() throws {
        XCTAssertEqual("外教", try ahuTeacher(
            #"{"lessonId": "A", "courseName": "Test", "teacher": "外教", "weekday": 1, "weekIndexes": "1-16", "startUnit": 1, "endUnit": 2}"#))
    }

    func test_teacher_personName_fallback() throws {
        XCTAssertEqual("兜底教师", try ahuTeacher(
            #"{"lessonId": "A", "courseName": "Test", "personName": "兜底教师", "weekday": 1, "weekIndexes": "1-16", "startUnit": 1, "endUnit": 2}"#))
    }

    func test_teacher_all_missing_emits_empty_string() throws {
        XCTAssertEqual("", try ahuTeacher(
            #"{"lessonId": "A", "courseName": "无师课", "weekday": 1, "weekIndexes": "1-16", "startUnit": 1, "endUnit": 2}"#))
    }

    func test_teacher_empty_array_degrades_to_single_string() throws {
        XCTAssertEqual("降级到单字符串", try ahuTeacher(
            #"{"lessonId": "A", "courseName": "Test", "teacherNames": [], "teacher": "降级到单字符串", "weekday": 1, "weekIndexes": "1-16", "startUnit": 1, "endUnit": 2}"#))
    }

    // MARK: - issue #46: HFUT 布局查表 (courseUnitList, 宣城 12 节次)
    // ← HfutIssue46LayoutNodeMappingTest.kt

    func test_issue46_layout_all_122_rows_produce_courses() throws {
        XCTAssertEqual(122, try parseLayoutSample().count)
    }

    func test_issue46_layout_1550_slot_maps_to_7_8_not_morning() throws {
        // 修复前: sectionIndex(1550)=null → 兜底 node 1-2 (错到上午)
        let rows = try parseLayoutSample()
            .filter { $0.startWeek == 5 && $0.day == 2 && $0.name == "习近平新时代中国特色社会主义思想概论" }
        XCTAssertFalse(rows.isEmpty, "应存在 习概 周二 week5 行 (宣城 1550 时段)")
        for c in rows {
            XCTAssertEqual(7, c.startNode)    // 1550 → unit7 起点
            XCTAssertEqual(8, c.endNode)      // 1730 → unit8 终点
        }
    }

    func test_issue46_layout_1920_slot_maps_to_10_11_not_9_10() throws {
        // 修复前: sectionIndex(1920) 吸到 19:00 段 → node 9-10 (差 1)
        let rows = try parseLayoutSample().filter { $0.name == "情景喜剧与美国文化" }
        XCTAssertFalse(rows.isEmpty, "应存在 情景喜剧与美国文化 行 (1920 时段)")
        for c in rows {
            XCTAssertEqual(10, c.startNode)   // 1920 → unit10
            XCTAssertEqual(11, c.endNode)     // 2100 → unit11
        }
    }

    func test_issue46_layout_morning_afternoon_unchanged() throws {
        let courses = try parseLayoutSample()
        let os = courses.filter { $0.name == "操作系统" && $0.day == 1 }
        XCTAssertFalse(os.isEmpty)
        // 1000-1140 → units 3-4 (布局查表不回归旧行为)
        XCTAssertEqual(3, os[0].startNode)
        XCTAssertEqual(4, os[0].endNode)
        let dm = courses.filter { $0.name == "数字媒体技术" }
        XCTAssertFalse(dm.isEmpty)
        // 1400-1540 → units 5-6
        XCTAssertEqual(5, dm[0].startNode)
        XCTAssertEqual(6, dm[0].endNode)
    }

    func test_issue46_layout_node_pair_distribution_matches_capture() throws {
        let dist = Dictionary(grouping: try parseLayoutSample(), by: { $0.startNode * 100 + $0.endNode })
            .mapValues { $0.count }
        XCTAssertEqual(22, dist[102])    // 1-2
        XCTAssertEqual(47, dist[304])    // 3-4
        XCTAssertEqual(35, dist[506])    // 5-6
        XCTAssertEqual(10, dist[708])    // 7-8
        XCTAssertEqual(8, dist[1011])    // 10-11
    }

    func test_issue46_no_layout_legacy_985_heuristic_kept() throws {
        // 无 courseUnitList → 旧五段 heuristic 行为保持 (CUMTB/老包零回归)
        let legacy = """
            {"result":{"lessonList":[
                {"id":1001,"courseName":"高等数学"},
                {"id":1002,"courseName":"大学物理"}
              ],
              "scheduleList":[
                {"lessonId":1001,"room":{"nameZh":"A楼101"},"weekday":1,"personName":"张三","weekIndex":1,"startTime":800,"endTime":950,"periods":2},
                {"lessonId":1002,"room":{"nameZh":"B楼205"},"weekday":3,"personName":"李四","weekIndex":1,"startTime":1010,"endTime":1200,"periods":2}
              ]}
            }
            """
        let courses = try JwEams5Parser(legacy).generateCourseList()
        XCTAssertEqual(2, courses.count)
        XCTAssert((1, 2) == (courses[0].startNode, courses[0].endNode))
        XCTAssert((3, 4) == (courses[1].startNode, courses[1].endNode))
    }

    func test_issue46_no_layout_1550_keeps_periods_fallback() throws {
        // 1550 无布局时 sectionIndex=null → 兜底 node 1..1+periods-1 (旧语义, 不抛不丢行)
        let legacy = """
            {"result":{"lessonList":[{"id":7,"courseName":"习概"}],
              "scheduleList":[
                {"lessonId":7,"room":{"nameZh":"x"},"weekday":2,"personName":"周","weekIndex":5,"startTime":1550,"endTime":1730,"periods":2}
              ]}
            }
            """
        let courses = try JwEams5Parser(legacy).generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual(1, courses[0].startNode)
        XCTAssertEqual(2, courses[0].endNode)
    }

    func test_issue46_layout_covers_all_referenced_start_times() throws {
        // 服务端布局 startTime 集合必须覆盖 datum 出现的每个 startTime
        // (JS 侧 periods 预填与 parser 查表共同依赖此不变量; Android 用正则抽取,
        //  iOS 直接 JSON 解析 — 断言语义等价)
        guard let data = try loadJson(name: "eams5-hfut-xc-datum-with-layout").data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let units = root["courseUnitList"] as? [[String: Any]],
              let result = root["result"] as? [String: Any],
              let schedule = result["scheduleList"] as? [[String: Any]] else {
            XCTFail("fixture 结构应含顶层 courseUnitList + result.scheduleList")
            return
        }
        func timeSet(_ arr: [[String: Any]], _ key: String) -> Set<Int> {
            Set(arr.compactMap { v in
                if let n = v[key] as? NSNumber { return n.intValue }
                if let s = v[key] as? String { return Int(s) }
                return nil
            })
        }
        let unitStarts = timeSet(units, "startTime")
        let schedStarts = timeSet(schedule, "startTime")
        XCTAssertTrue(unitStarts.isSuperset(of: schedStarts),
                      "布局 startTime 集必须覆盖所有 schedule startTime (差集=\(schedStarts.subtracting(unitStarts)))")
    }
}
