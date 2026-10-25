// AddCourseEditTests.swift — ← Android ui/screen/edit 同包 5 个测试类移植:
//   BuildCourseEntityAliasTest.kt / GroupSlotsForEditTest.kt /
//   IrregularOptionsCollapseTest.kt / IrregularValidationTest.kt /
//   EditCourseSlotSummaryContractTest.kt
// 前置 (fix_hint 6): groupSlotsForEdit / irregularOptionsSummary / meetingBlockSummary /
// buildCourseEntity / validateCourseDraft 均为 AddCourseScreen 的 static 纯函数, 可直测;
// UI 结构走源码级守卫 (先例: UndoCaptureCoverageTests 读源头文件当契约)。

import XCTest
@testable import Sleepy

final class AddCourseEditTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // 摘要/校验文案断言从固定语言出发 (AppPrefs 进程级单例, 用例间显式复位)
        AppPrefs.shared.setLanguage("zh-CN")
    }

    override func tearDown() {
        AppPrefs.shared.setLanguage("zh-CN")
        super.tearDown()
    }

    // MARK: - 工厂 (← 各 Android 测试类私有 factory)

    private func block(startNode: Int = 1, step: Int = 2,
                       days: Set<Int> = [1],
                       isIrregularNode: Bool = false, selectedEdgeNode: Int = 0,
                       isIrregularTime: Bool = false,
                       startTime: String = "08:00", endTime: String = "09:40",
                       startWeek: Int = 1, endWeek: Int = 16,
                       weekType: Int = 0,
                       room: String = "", teacher: String = "",
                       color: String = "", colorMode: Int = CourseColorMode.GROUP)
        -> MeetingBlockDraft {
        MeetingBlockDraft(id: 1, days: days, startNode: startNode, step: step,
                          startTime: startTime, endTime: endTime,
                          startWeek: startWeek, endWeek: endWeek, weekType: weekType,
                          room: room, teacher: teacher,
                          color: color, colorMode: colorMode,
                          isIrregularNode: isIrregularNode,
                          selectedEdgeNode: selectedEdgeNode,
                          isIrregularTime: isIrregularTime)
    }

    private func course(startNode: Int, step: Int, startWeek: Int, endWeek: Int, type: Int,
                        day: Int = 1, ownTime: Bool = false,
                        startTime: String = "", endTime: String = "",
                        room: String = "", teacher: String = "") -> CourseEntity {
        CourseEntity(groupId: "g", tableId: 1, courseName: "课",
                     teacher: teacher, room: room,
                     day: day, startNode: startNode, step: step,
                     startWeek: startWeek, endWeek: endWeek, type: type,
                     color: "#FF6750A4",
                     ownTime: ownTime, startTime: startTime, endTime: endTime)
    }

    // MARK: - BuildCourseEntityAliasTest.kt (4 案)

    func testAlias_trims_and_lands_on_entity() {
        let e = AddCourseScreen.buildCourseEntity(tableId: 1, groupId: "g1",
                                                  courseName: "高等数学", day: 1,
                                                  block: block(), alias: "  高数  ")
        XCTAssertEqual("高数", e.alias)
        XCTAssertEqual("高等数学", e.courseName)
    }

    func testBlank_alias_normalizes_to_empty_string() {
        let e = AddCourseScreen.buildCourseEntity(tableId: 1, groupId: "g1",
                                                  courseName: "大学英语", day: 2,
                                                  block: block(), alias: "   ")
        XCTAssertEqual("", e.alias)
    }

    func testDefault_alias_keeps_original_name() {
        // 不传 alias(默认 "")→ 行为与旧版本完全一致
        let e = AddCourseScreen.buildCourseEntity(tableId: 1, groupId: "g1",
                                                  courseName: "数据结构", day: 3,
                                                  block: block())
        XCTAssertEqual("", e.alias)
        XCTAssertEqual("数据结构", e.courseName)
    }

    func testOther_fields_untouched_by_alias_param() {
        let e = AddCourseScreen.buildCourseEntity(tableId: 7, groupId: "g9",
                                                  courseName: "高等数学", day: 1,
                                                  block: block(), alias: "高数")
        XCTAssertEqual(7, e.tableId)
        XCTAssertEqual("g9", e.groupId)
        XCTAssertEqual(1, e.day)
        XCTAssertEqual(1, e.startNode)
        XCTAssertEqual(2, e.step)
    }

    // MARK: - ownTime 反算真实节点 (用户报障 2026-09-10, AddCourseScreen.kt L887-891)

    func testBuildCourseEntity_ownTime_backcomputes_real_nodes() {
        let e = AddCourseScreen.buildCourseEntity(
            tableId: 1, groupId: "g", courseName: "课", day: 1,
            block: block(startNode: 1, step: 1, isIrregularTime: true,
                         startTime: "10:00", endTime: "11:40"),
            timeJson: TimeTableUtils.DEFAULT_TIME_JSON)
        // 10:00–11:40 = 标准节 3..4 — 表单占位节点 (1,1) 必须被反算覆盖
        XCTAssertEqual(3, e.startNode, "ownTime 落库必须反算真实起始节点")
        XCTAssertEqual(2, e.step, "ownTime 落库必须反算真实跨节数")
    }

    func testBuildCourseEntity_edgeCard_keeps_placeholder_node() {
        let e = AddCourseScreen.buildCourseEntity(
            tableId: 1, groupId: "g", courseName: "课", day: 1,
            block: block(startNode: 1, step: 1, isIrregularNode: true, selectedEdgeNode: -1,
                         isIrregularTime: true, startTime: "07:30", endTime: "08:00"),
            timeJson: TimeTableUtils.DEFAULT_TIME_JSON)
        // 边缘槽位卡不反算: 保持槽位号 + step 锁 1
        XCTAssertEqual(-1, e.startNode)
        XCTAssertEqual(1, e.step)
    }

    // MARK: - GroupSlotsForEditTest.kt (6 案)

    func testUserReportedCase_twoGroups() {
        let courses = [course(startNode: 1, step: 3, startWeek: 1, endWeek: 5, type: 0),
                       course(startNode: 5, step: 3, startWeek: 6, endWeek: 10, type: 0)]
        XCTAssertEqual(2, AddCourseScreen.groupSlotsForEdit(courses).count)
    }

    func testSameSlotDifferentDays_oneGroup() {
        let courses = [course(startNode: 1, step: 2, startWeek: 1, endWeek: 16, type: 0, day: 1),
                       course(startNode: 1, step: 2, startWeek: 1, endWeek: 16, type: 0, day: 3)]
        XCTAssertEqual(1, AddCourseScreen.groupSlotsForEdit(courses).count)
    }

    func testSameNodeDifferentWeeks_twoGroups() {
        let courses = [course(startNode: 1, step: 2, startWeek: 1, endWeek: 8, type: 0),
                       course(startNode: 1, step: 2, startWeek: 9, endWeek: 16, type: 0)]
        XCTAssertEqual(2, AddCourseScreen.groupSlotsForEdit(courses).count)
    }

    func testSameRangeDifferentType_twoGroups() {
        let courses = [course(startNode: 1, step: 2, startWeek: 1, endWeek: 16, type: 1),
                       course(startNode: 1, step: 2, startWeek: 1, endWeek: 16, type: 2)]
        XCTAssertEqual(2, AddCourseScreen.groupSlotsForEdit(courses).count)
    }

    func testOwnTimeDifferentTimes_twoGroups() {
        let courses = [course(startNode: 1, step: 2, startWeek: 1, endWeek: 16, type: 0,
                              ownTime: true, startTime: "08:00", endTime: "09:40"),
                       course(startNode: 1, step: 2, startWeek: 1, endWeek: 16, type: 0,
                              ownTime: true, startTime: "10:00", endTime: "11:40")]
        XCTAssertEqual(2, AddCourseScreen.groupSlotsForEdit(courses).count)
    }

    func testGroupMembersPreserved() {
        let courses = [course(startNode: 1, step: 2, startWeek: 1, endWeek: 16, type: 0, day: 1),
                       course(startNode: 1, step: 2, startWeek: 1, endWeek: 16, type: 0, day: 3),
                       course(startNode: 5, step: 2, startWeek: 1, endWeek: 16, type: 0, day: 1)]
        let groups = AddCourseScreen.groupSlotsForEdit(courses)
        XCTAssertEqual(2, groups.count)
        XCTAssertEqual(2, groups.first { $0[0].startNode == 1 }?.count)
    }

    /// 顺序契约 (审计 issue 10): Android groupBy 走 LinkedHashMap 保持首次出现序 —
    /// 锁"分组顺序本身"而非仅"分组存在性" (设计规范铁律③)。
    func testGroupOrder_follows_firstAppearance() {
        let courses = [course(startNode: 9, step: 1, startWeek: 1, endWeek: 2, type: 0),
                       course(startNode: 1, step: 2, startWeek: 1, endWeek: 16, type: 0),
                       course(startNode: 9, step: 1, startWeek: 1, endWeek: 2, type: 0, day: 3),
                       course(startNode: 5, step: 1, startWeek: 3, endWeek: 4, type: 0)]
        let groups = AddCourseScreen.groupSlotsForEdit(courses)
        XCTAssertEqual([9, 1, 5], groups.map { $0[0].startNode }, "组序必须 = key 首次出现序")
        XCTAssertEqual(2, groups[0].count, "首组聚合两条 day=1/3")
    }

    /// issue#22: room/teacher 进分组 key — 同节次同周次不同地点/老师 → 独立块
    func testRoomTeacher_splitGroups() {
        let courses = [course(startNode: 1, step: 2, startWeek: 1, endWeek: 16, type: 0,
                              room: "A101"),
                       course(startNode: 1, step: 2, startWeek: 1, endWeek: 16, type: 0,
                              room: "B202"),
                       course(startNode: 1, step: 2, startWeek: 1, endWeek: 16, type: 0,
                              room: "A101", teacher: "王老师")]
        // A101/无老师、B202/无老师、A101/王老师 = 3 个独立时段块
        XCTAssertEqual(3, AddCourseScreen.groupSlotsForEdit(courses).count)
    }

    // MARK: - IrregularValidationTest.kt (5 案)

    func testSave_path_persists_pending_edges_via_insertEdgeNode() {
        var timeJson = TimeTableUtils.DEFAULT_TIME_JSON
        let pending = [PendingEdgeInsert(edgeClass: .before, node: 0,
                                         start: "07:30", end: "08:00"),
                       PendingEdgeInsert(edgeClass: .after, node: 13,
                                         start: "21:30", end: "22:15")]
        for p in pending {
            timeJson = TimeTableUtils.insertEdgeNode(timeJson: timeJson, edgeClass: p.edgeClass,
                                                     start: p.start, end: p.end)
        }
        let rows = TimeTableUtils.parseTimeSlotRows(timeJson)
        XCTAssertEqual(14, rows.count, "标准 12 + 前 0 + 后 13 = 14")
        let zero = rows.first { $0.node == 0 }
        let thirteen = rows.first { $0.node == 13 }
        XCTAssertNotNil(zero, "前置 0 节必须存在")
        XCTAssertEqual("07:30", zero?.start)
        XCTAssertNotNil(thirteen, "后置 13 节必须存在")
        XCTAssertEqual("21:30", thirteen?.start)
    }

    func testSave_path_chained_before_inserts_descending_node_numbers() {
        var timeJson = TimeTableUtils.DEFAULT_TIME_JSON
        for i in 0..<3 {
            timeJson = TimeTableUtils.insertEdgeNode(
                timeJson: timeJson, edgeClass: .before,
                start: String(format: "0%ld:00", i), end: String(format: "0%ld:30", i))
        }
        let beforeNodes = TimeTableUtils.parseTimeSlotRows(timeJson)
            .filter { $0.edgeClass == .before }.map { $0.node }.sorted(by: >)
        XCTAssertEqual([0, -1, -2], beforeNodes)
    }

    func testSave_path_chained_after_inserts_ascending_node_numbers() {
        var timeJson = TimeTableUtils.DEFAULT_TIME_JSON
        for i in 0..<3 {
            timeJson = TimeTableUtils.insertEdgeNode(
                timeJson: timeJson, edgeClass: .after,
                start: String(format: "20:0%ld", i), end: String(format: "20:3%ld", i))
        }
        let afterNodes = TimeTableUtils.parseTimeSlotRows(timeJson)
            .filter { $0.edgeClass == .after }.map { $0.node }.sorted()
        XCTAssertEqual([13, 14, 15], afterNodes)
    }

    func testIrregularDisabled_leaves_timeJson_untouched() {
        let rows = TimeTableUtils.parseTimeSlotRows(TimeTableUtils.DEFAULT_TIME_JSON)
        XCTAssertEqual(12, rows.count)
        XCTAssertTrue(rows.allSatisfy { $0.edgeClass == nil }, "默认作息不得含边缘节点")
        XCTAssertNil(TimeTableUtils.edgeNodesOf(timeJson: TimeTableUtils.DEFAULT_TIME_JSON,
                                                edgeClass: .before).first)
        XCTAssertTrue(TimeTableUtils.edgeNodesOf(timeJson: TimeTableUtils.DEFAULT_TIME_JSON,
                                                 edgeClass: .after).isEmpty)
    }

    func testIrregularEnabled_edge_path_extends_timeJson() {
        let afterEdge = TimeTableUtils.insertEdgeNode(
            timeJson: TimeTableUtils.DEFAULT_TIME_JSON,
            edgeClass: .after, start: "21:00", end: "21:45")
        XCTAssertEqual(13, TimeTableUtils.parseTimeSlotRows(afterEdge).count)
    }

    // MARK: - validateCourseDraft 卡级校验 (Android 同名私有函数经 save 前拦截, iOS 已抽 static 直测)

    func testValidate_rejects_inverted_week_range_as_typed() {
        // issue 8 语义: 20→5 倒挂原样进草稿, 由 slot_week_order 拦截 (不静默交换)
        let issues = AddCourseScreen.validateCourseDraft(
            courseName: "课", blocks: [block(startWeek: 20, endWeek: 5)],
            startWeek: 1, endWeek: 16, timeJson: TimeTableUtils.DEFAULT_TIME_JSON)
        XCTAssertTrue(issues.contains { $0.blockId == 1 && $0.message.contains("开始周") },
                      "倒挂周次必须报 slot_week_order, 实际=\(issues.map { $0.message })")
    }

    func testValidate_rejects_edge_node_missing_from_effective_table() {
        let issues = AddCourseScreen.validateCourseDraft(
            courseName: "课",
            blocks: [block(isIrregularNode: true, selectedEdgeNode: -3)],
            startWeek: 1, endWeek: 16, timeJson: TimeTableUtils.DEFAULT_TIME_JSON)
        XCTAssertTrue(issues.contains { $0.message.contains("非常规节次无效") })
    }

    // MARK: - IrregularOptionsCollapseTest.kt

    // ---- A. 折叠栏默认展开状态: 由构造派生 ----

    func testNew_normal_block_collapsed_by_default() {
        XCTAssertFalse(block().shouldExpandIrregularOptions, "新建普通课程卡: 折叠栏必须默认收起")
    }

    func testEditing_irregular_node_block_expands_by_default() {
        XCTAssertTrue(block(isIrregularNode: true).shouldExpandIrregularOptions,
                      "编辑已启用非常规节次的卡: 折叠栏必须自动展开")
    }

    func testEditing_irregular_time_block_expands_by_default() {
        XCTAssertTrue(block(isIrregularTime: true).shouldExpandIrregularOptions,
                      "编辑已启用非常规时间的卡: 折叠栏必须自动展开")
    }

    func testEditing_both_irregular_block_expands_by_default() {
        XCTAssertTrue(block(isIrregularNode: true, isIrregularTime: true)
                        .shouldExpandIrregularOptions,
                      "两项都启用时折叠栏必须自动展开")
    }

    // ---- B. 折叠态摘要 (纯函数直测) ----

    func testSummary_blank_when_no_option_active() {
        XCTAssertEqual("", AddCourseScreen.irregularOptionsSummary(
            isIrregularNode: false, isIrregularTime: false,
            startTime: "08:00", endTime: "09:40",
            nodeSwitchLabel: "非常规节次", edgeNodeLabel: "第 0 节",
            timeSwitchLabel: "非常规时间"))
    }

    func testSummary_lists_node_when_only_node_active() {
        XCTAssertEqual("非常规节次 · 第 0 节", AddCourseScreen.irregularOptionsSummary(
            isIrregularNode: true, isIrregularTime: false,
            startTime: "", endTime: "",
            nodeSwitchLabel: "非常规节次", edgeNodeLabel: "第 0 节",
            timeSwitchLabel: "非常规时间"))
    }

    func testSummary_lists_time_when_only_time_active() {
        XCTAssertEqual("非常规时间 · 19:00–20:40", AddCourseScreen.irregularOptionsSummary(
            isIrregularNode: false, isIrregularTime: true,
            startTime: "19:00", endTime: "20:40",
            nodeSwitchLabel: "非常规节次", edgeNodeLabel: "第 0 节",
            timeSwitchLabel: "非常规时间"))
    }

    func testSummary_lists_both_joined_with_slash() {
        XCTAssertEqual("非常规节次 · 第 -1 节 / 非常规时间 · 19:00–20:40",
                       AddCourseScreen.irregularOptionsSummary(
                            isIrregularNode: true, isIrregularTime: true,
                            startTime: "19:00", endTime: "20:40",
                            nodeSwitchLabel: "非常规节次", edgeNodeLabel: "第 -1 节",
                            timeSwitchLabel: "非常规时间"))
    }

    func testSummary_time_without_valid_range_shows_label_only() {
        // 跨午夜守卫会清空 endTime — 摘要降级为只显示开关名, 不拼半截区间
        XCTAssertEqual("非常规时间", AddCourseScreen.irregularOptionsSummary(
            isIrregularNode: false, isIrregularTime: true,
            startTime: "23:00", endTime: "",
            nodeSwitchLabel: "非常规节次", edgeNodeLabel: "第 0 节",
            timeSwitchLabel: "非常规时间"))
    }

    // ---- C. 源码级守卫: AddCourseScreen 表单结构 (先例 UndoCaptureCoverageTests) ----

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SleepyTests/
            .deletingLastPathComponent()   // 工程根
    }

    private var editorURL: URL {
        projectRoot.appendingPathComponent("Sleepy/ui/screen/edit/AddCourseScreen.swift")
    }

    private func editorSource() throws -> String {
        guard (try? String(contentsOf: editorURL, encoding: .utf8)) != nil else {
            throw XCTSkip("源文件不在盘(真机宿主?) — 契约测试需在模拟器/主机构建运行: \(editorURL.path)")
        }
        return try String(contentsOf: editorURL, encoding: .utf8)
    }

    /// 结构体函数体: 声明起点到下一个顶层 `private struct` 声明为止。
    /// NSString 坐标系 (与 Android substringAfter/Before 语义一致)。
    private func structBody(_ source: String, _ name: String) -> String {
        let ns = source as NSString
        let start = ns.range(of: "struct \(name)").location
        XCTAssertNotEqual(start, NSNotFound, "AddCourseScreen.swift 必须定义 \(name)")
        guard start != NSNotFound else { return "" }
        let tail = (ns.substring(from: start) as NSString)
        let next = tail.range(of: "\nprivate struct", options: [],
                              range: NSRange(location: 0, length: tail.length))
        let end = next.location == NSNotFound ? tail.length : next.location
        return tail.substring(to: end)
    }

    func testSection_struct_exists_with_expand_collapse_affordance() throws {
        let body = structBody(try editorSource(), "IrregularOptionsSection")
        XCTAssertFalse(body.isEmpty)
        XCTAssertTrue(body.contains("chevron.down"), "折叠栏必须有 chevron (ExpandMore 等价)")
        XCTAssertTrue(body.contains("rotationEffect") && body.contains("180"),
                      "chevron 必须随展开旋转 180° (仓库既有模式)")
        XCTAssertTrue(body.contains("if expanded"), "折叠栏内容必须随 expanded 条件展开/收起")
    }

    func testBoth_irregular_switches_live_inside_section() throws {
        let body = structBody(try editorSource(), "IrregularOptionsSection")
        XCTAssertTrue(body.contains("irregular_node_switch\""), "「非常规节次」开关必须在折叠栏内部")
        XCTAssertTrue(body.contains("irregular_time_switch\""), "「非常规时间」开关必须在折叠栏内部")
        XCTAssertTrue(body.contains("irregular_options_section\""),
                      "折叠栏标题必须用 irregular_options_section 文案")
        XCTAssertTrue(body.contains("edge_node_range\""),
                      "非常规节次的槽位摘要必须随开关收进折叠栏")
        XCTAssertTrue(body.contains("irregular_duration_label\""),
                      "非常规时间的时长输入必须随开关收进折叠栏")
    }

    func testStandard_node_fields_stay_outside_section() throws {
        let body = structBody(try editorSource(), "MeetingBlockEditor")
        XCTAssertTrue(body.contains("start_node\"") && body.contains("step_count\""),
                      "标准节次字段 (start_node/step_count) 必须留在折叠栏外")
        XCTAssertTrue(body.contains("IrregularOptionsSection("),
                      "MeetingBlockEditor 必须挂载 IrregularOptionsSection")
        XCTAssertFalse(body.contains("irregular_node_switch\"") || body.contains("irregular_time_switch\""),
                       "两个非常规开关不得再平铺在 MeetingBlockEditor 主体里")
    }

    func testNo_border_stroke_or_outlined_button_in_editor() throws {
        let source = try editorSource()
        XCTAssertFalse(source.contains("BorderStroke"), "Sleepy 全 app 禁 BorderStroke")
        XCTAssertFalse(source.contains("OutlinedButton"), "Sleepy 全 app 禁 OutlinedButton")
    }

    // ---- D. 五 locale 文案齐全 (Android 六 values 目录 → iOS 五 lproj) ----

    func testSection_strings_present_in_all_locales() throws {
        _ = try editorSource()  // 同守卫: 真机宿主无源文件时 skip
        for locale in ["en", "es", "ja", "zh-Hans", "zh-Hant"] {
            let url = projectRoot.appendingPathComponent(
                "Sleepy/resources/\(locale).lproj/Localizable.strings")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                XCTFail("\(locale) Localizable.strings 读不到: \(url.path)")
                continue
            }
            XCTAssertTrue(text.contains("\"irregular_options_section\""),
                          "\(locale) 缺 irregular_options_section")
            XCTAssertTrue(text.contains("\"irregular_options_section_sub\""),
                          "\(locale) 缺 irregular_options_section_sub")
        }
    }

    // MARK: - EditCourseSlotSummaryContractTest.kt (语义移植: 纯函数直测代替源码扫)

    func testSlot_header_uses_live_two_line_summary() throws {
        let source = try editorSource()
        XCTAssertTrue(source.contains("meetingBlockSummary(block: block, timeJson: timeJson)"),
                      "卡头必须调用两行摘要纯函数")
        XCTAssertTrue(source.contains("summary.calendar") && source.contains("summary.detail"),
                      "卡头必须渲染 calendar + detail 两行")
        XCTAssertFalse(source.contains("selected_days"),
                       "旧卡头不能只显示已选星期 (Android 无此 key)")
        let summary = AddCourseScreen.meetingBlockSummary(
            block: block(startWeek: 1, endWeek: 8),
            timeJson: TimeTableUtils.DEFAULT_TIME_JSON)
        XCTAssertFalse(summary.calendar.isEmpty)
        XCTAssertFalse(summary.detail.isEmpty)
    }

    func testSummary_covers_calendar_range_and_every_timing_mode() {
        let std = AddCourseScreen.meetingBlockSummary(
            block: block(), timeJson: TimeTableUtils.DEFAULT_TIME_JSON)
        XCTAssertTrue(std.calendar.contains("第 1–16 周"), "周次范围: \(std.calendar)")
        XCTAssertTrue(std.calendar.contains("每周"), "周次类型: \(std.calendar)")
        XCTAssertTrue(std.detail.contains("第 1–2 节（共 2 节）"), "标准区间: \(std.detail)")

        let single = AddCourseScreen.meetingBlockSummary(
            block: block(step: 1, startWeek: 3, endWeek: 3),
            timeJson: TimeTableUtils.DEFAULT_TIME_JSON)
        XCTAssertTrue(single.calendar.contains("第 3 周"), "单周摘要: \(single.calendar)")
        XCTAssertTrue(single.detail.contains("第 1 节"), "单节摘要: \(single.detail)")

        let own = AddCourseScreen.meetingBlockSummary(
            block: block(isIrregularTime: true, startTime: "19:00", endTime: "20:40"),
            timeJson: TimeTableUtils.DEFAULT_TIME_JSON)
        XCTAssertTrue(own.detail.contains("19:00–20:40"), "自定时间: \(own.detail)")

        // 边缘槽位模式: 先经 insertEdgeNode 造出真实槽位, 再摘要
        let edgeJson = TimeTableUtils.insertEdgeNode(
            timeJson: TimeTableUtils.DEFAULT_TIME_JSON,
            edgeClass: .after, start: "21:30", end: "22:15")
        let edge = AddCourseScreen.meetingBlockSummary(
            block: block(isIrregularNode: true, selectedEdgeNode: 13), timeJson: edgeJson)
        XCTAssertTrue(edge.detail.contains("第 13 节"), "边缘槽位标签: \(edge.detail)")
        XCTAssertTrue(edge.detail.contains("21:30–22:15"), "边缘槽位默认时间: \(edge.detail)")

        let odd = AddCourseScreen.meetingBlockSummary(
            block: block(weekType: 1), timeJson: TimeTableUtils.DEFAULT_TIME_JSON)
        XCTAssertTrue(odd.calendar.contains("单周"), "单周类型: \(odd.calendar)")
    }

    func testTeacher_and_room_appear_only_when_filled() {
        let empty = AddCourseScreen.meetingBlockSummary(
            block: block(), timeJson: TimeTableUtils.DEFAULT_TIME_JSON)
        XCTAssertFalse(empty.detail.contains("老师"), "未填老师不得出现: \(empty.detail)")
        XCTAssertFalse(empty.detail.contains("地点"), "未填地点不得出现: \(empty.detail)")

        let filled = AddCourseScreen.meetingBlockSummary(
            block: block(room: " A101 ", teacher: " 王老师 "),
            timeJson: TimeTableUtils.DEFAULT_TIME_JSON)
        XCTAssertTrue(filled.detail.contains("老师：王老师"), "老师 trim 进摘要: \(filled.detail)")
        XCTAssertTrue(filled.detail.contains("地点：A101"), "地点 trim 进摘要: \(filled.detail)")
    }

    func testSummary_days_empty_falls_back_to_hint() {
        let s = AddCourseScreen.meetingBlockSummary(
            block: block(days: []), timeJson: TimeTableUtils.DEFAULT_TIME_JSON)
        XCTAssertTrue(s.calendar.contains("至少选一天"), "空星期回退文案: \(s.calendar)")
    }
}
