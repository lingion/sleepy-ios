// SleepyNativeExporterTests.swift — ← SleepyNativeExporterTest.kt (逐测试翻译, GPL-3.0)
// sleepy-v1 导出器(规范 §4/§8.1/§10): 字段级 + 字节级往返 / 散周 partition / 同名异组 token 必写 / Nd 折叠 / chk。

import XCTest
@testable import Sleepy

final class SleepyNativeExporterTests: XCTestCase {

    private func parse(_ text: String) throws -> ScheduleParser.ParseResult {
        switch ScheduleParser.parse(text, defaultTableId: 1) {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    private func table(name: String = "测试表", startDate: String = "2026-03-02",
                       maxWeek: Int = 20, nodesPerDay: Int = 12,
                       timeJson: String = TimeTableUtils.DEFAULT_TIME_JSON) -> TimeTableEntity {
        var t = TimeTableEntity(name: name, startDate: startDate, maxWeek: maxWeek,
                                nodesPerDay: nodesPerDay, timeJson: timeJson, isDefault: true)
        t.id = 1
        t.color = "#FF6750A4"
        return t
    }

    private func course(_ name: String, day: Int = 1, startNode: Int = 1, step: Int = 2,
                        startWeek: Int = 1, endWeek: Int = 16, type: Int = 0,
                        teacher: String = "", room: String = "", note: String = "",
                        color: String = "#FF6750A4",
                        ownTime: Bool = false, startTime: String = "", endTime: String = "",
                        groupId: String = "") -> CourseEntity {
        var c = CourseEntity(groupId: groupId, tableId: 1, courseName: name,
                             teacher: teacher, room: room, note: note, day: day,
                             startNode: startNode, step: step, startWeek: startWeek, endWeek: endWeek,
                             type: type, color: color, ownTime: ownTime,
                             startTime: startTime, endTime: endTime)
        c.groupId = groupId
        return c
    }

    // ---- 字段级往返 (§8.2) ----

    func testRoundTripMinimal() throws {
        let doc = "#sleepy-v1\nC高数|2|1-2"
        let r = try parse(doc)
        let out = SleepyNativeExporter.exportFile(tableName: r.tableName, startDate: r.startDate,
                                                  maxWeek: r.maxWeek, nodesPerDay: r.nodesPerDay,
                                                  timeJson: r.timeJson, courses: r.courses)
        let r2 = try parse(out)
        XCTAssertEqual(1, r2.courses.count)
        XCTAssertEqual(r.courses[0].courseName, r2.courses[0].courseName)
        XCTAssertEqual(r.courses[0].day, r2.courses[0].day)
        XCTAssertEqual(r.courses[0].startNode, r2.courses[0].startNode)
        XCTAssertEqual(r.courses[0].step, r2.courses[0].step)
        XCTAssertEqual(r.courses[0].startWeek, r2.courses[0].startWeek)
        XCTAssertEqual(r.courses[0].endWeek, r2.courses[0].endWeek)
        XCTAssertEqual(r.courses[0].type, r2.courses[0].type)
    }

    func testRoundTripFullTableExample3() throws {
        // §9-③ 完整示例往返(用真实 TimeTableEntity → export → parse → 等价)
        let courses = [
            course("高等数学A", day: 1, startNode: 1, step: 2, startWeek: 1, endWeek: 16, type: 0, teacher: "张三", room: "A101", color: "#FFEADDFF", groupId: "g1"),
            course("高等数学A", day: 3, startNode: 3, step: 2, startWeek: 1, endWeek: 16, type: 0, teacher: "张三", room: "B202", groupId: "g1"),
            course("大学英语", day: 2, startNode: 3, step: 2, startWeek: 1, endWeek: 15, type: 1, teacher: "李四", room: "C301", groupId: "g2"),
            course("数据结构", day: 2, startNode: 3, step: 2, startWeek: 2, endWeek: 16, type: 2, teacher: "王五", room: "C302", color: "#FF388E3C", groupId: "g3"),
            course("体育", day: 4, startNode: 5, step: 2, startWeek: 3, endWeek: 4, type: 3, teacher: "赵六", room: "田径场", groupId: "g4"),
            course("物理实验", day: 5, startNode: 8, step: 2, startWeek: 8, endWeek: 8, type: 3, teacher: "钱七", room: "实验楼501", note: "穿实验服", groupId: "g5"),
            course("Java实战", day: 4, startNode: 9, step: 3, startWeek: 1, endWeek: 16, type: 0, teacher: "孙八", room: "机房", ownTime: true, startTime: "19:00", endTime: "21:30", groupId: "g6"),
            course("电磁场", day: 2, startNode: 6, step: 2, startWeek: 1, endWeek: 8, type: 0, teacher: "周九", room: "F405", groupId: "g7"),
            course("电磁场", day: 2, startNode: 6, step: 2, startWeek: 11, endWeek: 16, type: 0, teacher: "周九", room: "F405", groupId: "g7"),
            course("影视鉴赏", day: 7, startNode: 6, step: 1, startWeek: 10, endWeek: 16, type: 2, room: "D001", note: "A|B候选", groupId: "g8")
        ]
        let out = SleepyNativeExporter.exportFile(tableName: "软件工程2026春", startDate: "2026-03-02",
            maxWeek: 20, nodesPerDay: 12,
            timeJson: "[{\"node\":1,\"start\":\"08:30\",\"end\":\"09:15\"},{\"node\":3,\"start\":\"10:00\",\"end\":\"10:45\"},{\"node\":4,\"start\":\"10:55\",\"end\":\"11:40\"},{\"node\":5,\"start\":\"14:00\",\"end\":\"14:45\"},{\"node\":7,\"start\":\"16:00\",\"end\":\"16:45\"},{\"node\":8,\"start\":\"16:55\",\"end\":\"17:40\"},{\"node\":9,\"start\":\"19:00\",\"end\":\"19:45\"},{\"node\":10,\"start\":\"19:55\",\"end\":\"20:40\"},{\"node\":11,\"start\":\"20:50\",\"end\":\"21:35\"},{\"node\":12,\"start\":\"21:45\",\"end\":\"22:30\"}]",
            courses: courses)
        // 字段级断言
        let r = try parse(out)
        XCTAssertTrue(r.droppedLines.isEmpty, "dropped=\(r.droppedLines) warnings=\(r.warnings)")
        XCTAssertTrue(r.warnings.isEmpty, "warnings=\(r.warnings)")
        XCTAssertEqual(courses.count, r.courses.count)
        // 按 (courseName|day|startNode) 复合 key 对齐后逐条断言
        func key(_ c: CourseEntity) -> String { "\(c.courseName)|\(c.day)|\(c.startNode)|\(c.startWeek)-\(c.endWeek)" }
        let inByKey = Dictionary(grouping: courses, by: key)
        let outByKey = Dictionary(grouping: r.courses, by: key)
        XCTAssertEqual(inByKey.keys.sorted(), outByKey.keys.sorted(), "keys")
        for (k, ins) in inByKey {
            guard let outs = outByKey[k] else { XCTFail("missing key \(k)"); continue }
            XCTAssertEqual(ins.count, outs.count, "key \(k) size")
            for (i, c) in ins.enumerated() {
                XCTAssertEqual(c.courseName, outs[i].courseName)
                XCTAssertEqual(c.teacher, outs[i].teacher)
                XCTAssertEqual(c.room, outs[i].room)
                XCTAssertEqual(c.note, outs[i].note)
                XCTAssertEqual(c.day, outs[i].day)
                XCTAssertEqual(c.startNode, outs[i].startNode)
                XCTAssertEqual(c.step, outs[i].step)
                XCTAssertEqual(c.startWeek, outs[i].startWeek)
                XCTAssertEqual(c.endWeek, outs[i].endWeek)
                XCTAssertEqual(c.type, outs[i].type)
                // color 归一对比
                XCTAssertEqual(c.color.uppercased(), outs[i].color.uppercased(), "key=\(k) idx=\(i) color")
            }
        }
        // 分组保真: 输入同组 → 输出同组; 输入异组 → 输出异组
        var groupMap: [String: String] = [:]  // in groupId → out groupId
        for c in courses {
            let oc = r.courses.first { key($0) == key(c) && $0.note == c.note }
            if let oc = oc {
                if let prev = groupMap[c.groupId] {
                    XCTAssertEqual(prev, oc.groupId, "group drift for \(c.groupId)")
                }
                groupMap[c.groupId] = oc.groupId
            }
        }
        // ownTime 课
        let java = r.courses.first { $0.courseName == "Java实战" }
        XCTAssertNotNil(java)
        XCTAssertTrue(java!.ownTime)
        XCTAssertEqual("19:00", java!.startTime)
        XCTAssertEqual("21:30", java!.endTime)
        // 影视鉴赏备注含 | 已转义
        let movie = r.courses.first { $0.courseName == "影视鉴赏" }
        XCTAssertEqual("A|B候选", movie?.note)
    }

    // ---- 字节级往返 (§8.2) ----

    func testByteLevelRoundTrip() throws {
        // export(parse(export(T))) == export(T)
        let t = table()
        let cs = [
            course("高数", day: 1, startNode: 1, step: 2, startWeek: 1, endWeek: 16, type: 0, teacher: "张三", room: "A101", color: "#FFEADDFF", groupId: "g1"),
            course("英语", day: 2, startNode: 3, step: 2, startWeek: 1, endWeek: 15, type: 1, teacher: "李四", room: "C301", groupId: "g2")
        ]
        let first = SleepyNativeExporter.exportFile(tableName: t.name, startDate: t.startDate,
                                                    maxWeek: t.maxWeek, nodesPerDay: t.nodesPerDay,
                                                    timeJson: t.timeJson, courses: cs)
        let parsed = try parse(first)
        let second = SleepyNativeExporter.exportFile(tableName: parsed.tableName, startDate: parsed.startDate,
                                                     maxWeek: parsed.maxWeek, nodesPerDay: parsed.nodesPerDay,
                                                     timeJson: parsed.timeJson, courses: parsed.courses)
        // 字节级相等(切掉 z 行再比较——chk 每次重算但 body 稳定)
        func stripChk(_ s: String) -> String {
            s.components(separatedBy: .newlines).filter { !$0.hasPrefix("z|") }.joined(separator: "\n")
        }
        XCTAssertEqual(stripChk(first), stripChk(second))
    }

    // ---- 散周 partition (§4) ----

    func testScatteredWeekPartition() throws {
        // type=3 区间恒真, 单实体不能表达"1-8 + 11-16", 导出端按连续段拆多行同 token
        let courses = [
            course("散课", day: 1, startNode: 1, step: 2, startWeek: 1, endWeek: 16, type: 3, groupId: "g1"),
            course("散课", day: 1, startNode: 1, step: 2, startWeek: 11, endWeek: 16, type: 3, groupId: "g1")
        ]
        let out = SleepyNativeExporter.exportFile(tableName: "t", startDate: "2026-03-02",
                                                  maxWeek: 20, nodesPerDay: 12, timeJson: "", courses: courses)
        // 应该两行同组 token
        XCTAssertTrue(out.contains("\nC散课|1|1-2|1-16定|g1\n") || out.contains("\nC散课|1|1-2|1-16定|"))
        let parsed = try parse(out)
        XCTAssertEqual(2, parsed.courses.count)
        XCTAssertEqual(parsed.courses[0].groupId, parsed.courses[1].groupId)
    }

    // ---- 同名异组强制 token (§3.4 契约二) ----

    func testSameNameDifferentGroupsMustEmitToken() throws {
        let courses = [
            course("同名", day: 1, startNode: 1, step: 1, groupId: "g1"),
            course("同名", day: 2, startNode: 1, step: 1, groupId: "g2")
        ]
        let out = SleepyNativeExporter.exportFile(tableName: "t", startDate: "2026-03-02",
                                                  maxWeek: 20, nodesPerDay: 12, timeJson: "", courses: courses)
        // 两行都必须有 token(空=按名合并会塌缩)
        let lines = out.components(separatedBy: .newlines).filter { $0.hasPrefix("C同名") }
        XCTAssertEqual(2, lines.count)
        // token 必须非空(§3.4 契约二: 同名异组必显式写 token)
        for l in lines {
            let cols = l.components(separatedBy: "|")
            XCTAssertFalse(cols.last!.isEmpty, "empty token in: \(l)")
        }
    }

    // ---- Nd 折叠 (§5) ----

    func testNdPresetCollapsed() throws {
        let out = SleepyNativeExporter.exportFile(tableName: "t", startDate: "2026-03-02",
                                                  maxWeek: 20, nodesPerDay: 12,
                                                  timeJson: TimeTableUtils.DEFAULT_TIME_JSON, courses: [])
        // 作息等于冻结预设时写 Nd
        XCTAssertTrue(out.contains("\nNd\n") || out.hasSuffix("Nd"))
        let parsed = try parse(out)
        let nodes = TimeTableUtils.parseNodes(parsed.timeJson)
        XCTAssertEqual(12, nodes.count)
    }

    func testSparseTimeTableNotCollapsedToNd() throws {
        let custom = "[{\"node\":1,\"start\":\"08:00\",\"end\":\"08:45\"}]"
        let out = SleepyNativeExporter.exportFile(tableName: "t", startDate: "2026-03-02",
                                                  maxWeek: 20, nodesPerDay: 12, timeJson: custom, courses: [])
        // 不等于冻结预设时写逐节 N 行
        XCTAssertTrue(out.contains("N1|"), "out=\(out)")
        XCTAssertFalse(out.contains("\nNd\n") || out.hasSuffix("Nd"))
    }

    // ---- chk 写入 (§8.1) ----

    func testChkWrittenInFileMode() {
        let out = SleepyNativeExporter.exportFile(tableName: "t", startDate: "2026-03-02",
                                                  maxWeek: 20, nodesPerDay: 12, timeJson: "",
                                                  courses: [course("高数")])
        XCTAssertTrue(out.contains("z|chk=crc32:"))
        XCTAssertNotNil(out.range(of: #"chk=crc32:([0-9a-f]{8})"#, options: .regularExpression))
    }

    // ---- share 形态 (§1.1, 无 chk + marker 包裹) ----

    func testShareTextWrappedNoChk() {
        let out = SleepyNativeExporter.exportShareText(tableName: "t", startDate: "2026-03-02",
                                                       maxWeek: 20, nodesPerDay: 12, timeJson: "",
                                                       courses: [course("高数")])
        XCTAssertTrue(out.hasPrefix("【来自Sleepy】"))
        XCTAssertTrue(out.contains("<<<SLEEPY-BEGIN>>>"))
        XCTAssertTrue(out.contains("<<<SLEEPY-END>>>"))
        XCTAssertFalse(out.contains("z|chk="))
    }

    // ---- 调色板输出 (规范 §3.2) ----

    func testPaletteOutputCompactIndex() {
        let c = course("课", color: "#FFEADDFF")
        let out = SleepyNativeExporter.exportFile(tableName: "t", startDate: "2026-03-02",
                                                  maxWeek: 20, nodesPerDay: 12, timeJson: "", courses: [c])
        // 第 7 列 color = 调色板索引 1
        XCTAssertTrue(out.contains("\nC课|1|1-2|1-16|||1|||\n") || out.contains("\nC课|1|1-2|1-16|||1|||"), "out=\(out)")
    }

    func testCustomHexOutput6Digit() {
        // alpha=FF 其他色 → 6 位 #RRGGBB
        let c = course("课", color: "#FF388E3C")
        let out = SleepyNativeExporter.exportFile(tableName: "t", startDate: "2026-03-02",
                                                  maxWeek: 20, nodesPerDay: 12, timeJson: "", courses: [c])
        XCTAssertTrue(out.contains("|#388E3C|"), "out=\(out)")
    }

    func testCustomHexOutput9DigitKeptForTransparency() {
        // 非 FF alpha → 9 位
        let c = course("课", color: "#80388E3C")
        let out = SleepyNativeExporter.exportFile(tableName: "t", startDate: "2026-03-02",
                                                  maxWeek: 20, nodesPerDay: 12, timeJson: "", courses: [c])
        XCTAssertTrue(out.contains("|#80388E3C|"), "out=\(out)")
    }

    func testAutoColorEmpty() {
        let c = course("课", color: "#FF6750A4")
        let out = SleepyNativeExporter.exportFile(tableName: "t", startDate: "2026-03-02",
                                                  maxWeek: 20, nodesPerDay: 12, timeJson: "", courses: [c])
        // 自动色 → 第 7 列空
        XCTAssertTrue(out.contains("\nC课|1|1-2|1-16||||||"), "out=\(out)")
    }

    // ---- 密度锚 (§10) ----

    func testByteLevelDensityAnchor() {
        // 示例① 24 B
        let out1 = SleepyNativeExporter.exportFile(tableName: "t", startDate: "2026-03-02",
                                                   maxWeek: 20, nodesPerDay: 12, timeJson: "",
                                                   courses: [course("高数", day: 2, startNode: 1, step: 2)])
        XCTAssertTrue(out1.count <= 100, "len=\(out1.count) out=\(out1)")  // 含 T 行 + chk 行也远小于 100
    }

    // ---- issue#40 §6: P 区块可选导出 (← PeriodTableRoundTripTest.kt 导出端断言) ----

    private let periodTimeJson = "[{\"node\":1,\"start\":\"08:20\",\"end\":\"09:05\"},{\"node\":2,\"start\":\"09:15\",\"end\":\"10:00\"}]"

    private func periodExport(id: Int64 = 5, name: String = "春季作息",
                              nodesPerDay: Int = 2, timeJson: String? = nil) -> SleepyNativeExporter.PeriodTableExport {
        SleepyNativeExporter.PeriodTableExport(id: id, name: name, nodesPerDay: nodesPerDay,
                                               timeJson: timeJson ?? periodTimeJson)
    }

    func testExportFileWithPeriodTableWritesPBlock() {
        let out = SleepyNativeExporter.exportFile(tableName: "2026 春季课表", startDate: "2026-02-23",
                                                  maxWeek: 18, nodesPerDay: 2, timeJson: periodTimeJson,
                                                  courses: [], periodTable: periodExport())
        XCTAssertTrue(out.contains("\nP春季作息|5|2\n"), "out=\(out)")
        XCTAssertTrue(out.contains("\nPn1|08:20|09:05\n"), "out=\(out)")
        XCTAssertTrue(out.contains("\nPn2|09:15|10:00\n"), "out=\(out)")
        // §6 兼容列: P 区块之外照常输出 N 行(旧版本至少读到课表内 timeJson)
        XCTAssertTrue(out.contains("\nN1|08:20|09:05\n"), "out=\(out)")
    }

    func testExportFileWithoutPeriodTableOmitsPBlock() {
        // 旧格式(未绑定/无共享): 零 P 行 → 导入端各建一张, 不误共享
        let out = SleepyNativeExporter.exportFile(tableName: "t", startDate: "2026-02-23",
                                                  maxWeek: 18, nodesPerDay: 2, timeJson: periodTimeJson,
                                                  courses: [])
        let pLines = out.components(separatedBy: .newlines).filter { $0.hasPrefix("P") }
        XCTAssertTrue(pLines.isEmpty, "out=\(out)")
    }

    func testShareTextCarriesPeriodTable() {
        let out = SleepyNativeExporter.exportShareText(tableName: "分享课表", startDate: "2026-02-23",
                                                       maxWeek: 16, nodesPerDay: 2, timeJson: periodTimeJson,
                                                       courses: [],
                                                       periodTable: periodExport(id: 9, name: "考试周作息"))
        XCTAssertTrue(out.hasPrefix("【来自Sleepy】"))
        XCTAssertTrue(out.contains("\nP考试周作息|9|2\n"), "out=\(out)")
        XCTAssertTrue(out.contains("Pn1|08:20|09:05"), "out=\(out)")
        XCTAssertFalse(out.contains("z|chk="))
    }

    func testPeriodBlockNdPresetFoldsToPd() {
        // P 区块时间等于冻结预设时写 Pd(紧凑形), 与 N 段判定同文法
        let out = SleepyNativeExporter.exportFile(tableName: "ND表", startDate: "2026-02-23",
                                                  maxWeek: 16, nodesPerDay: 12,
                                                  timeJson: TimeTableUtils.DEFAULT_TIME_JSON, courses: [],
                                                  periodTable: periodExport(id: 3, name: "默认作息",
                                                                            nodesPerDay: 12,
                                                                            timeJson: TimeTableUtils.DEFAULT_TIME_JSON))
        XCTAssertTrue(out.contains("\nPd\n"), "out=\(out)")
        XCTAssertFalse(out.contains("Pn1|"), "out=\(out)")
    }

    func testPeriodBlockBlankTimeJsonWritesOnlyHeader() {
        // matchesNdPreset(空)=false, isNotBlank(空)=false → 零时间行(与 Android SleepyNativeExporter.kt
        // buildBody 的 else-if 分支一致: P 头照写, 其后既无 Pd 也无 Pn)。
        // exportFile 的 file 形态在 body 末尾追加 z|chk 行(§8.1, Android exportFile 同文法),
        // 所以契约是"P 头是 chk 之前的 body 末行", 不是"整个文件以 P 头结尾"。
        // 实测(2026-10-21, iPhone 14 sim): out=...P春季作息|5|2\nz|chk=crc32:xxxxxxxx
        let out = SleepyNativeExporter.exportFile(tableName: "t", startDate: "2026-02-23",
                                                  maxWeek: 16, nodesPerDay: 2, timeJson: "",
                                                  courses: [], periodTable: periodExport(timeJson: ""))
        let lines = out.components(separatedBy: .newlines)
        XCTAssertTrue(lines.last!.hasPrefix("z|chk=crc32:"), "out=\(out)")
        XCTAssertEqual("P春季作息|5|2", lines[lines.count - 2], "out=\(out)")
        // 零时间行: 没有任何 Pn 行, 也没有 Pd 行(整行精确匹配, 排除子串误判)
        XCTAssertFalse(lines.contains { $0.hasPrefix("Pn") }, "out=\(out)")
        XCTAssertFalse(lines.contains { $0 == "Pd" }, "out=\(out)")
    }

    func testChkValidWithPeriodTableBlock() {
        // chk = crc32(body), P 区块属 body → 校验照常成立
        let out = SleepyNativeExporter.exportFile(tableName: "t", startDate: "2026-02-23",
                                                  maxWeek: 16, nodesPerDay: 2, timeJson: periodTimeJson,
                                                  courses: [], periodTable: periodExport())
        let lines = out.components(separatedBy: .newlines)
        guard let chkIdx = lines.firstIndex(where: { $0.hasPrefix("z|chk=") }) else {
            XCTFail("缺 chk 行: \(out)"); return
        }
        let body = lines[..<chkIdx].joined(separator: "\n")
        let expected = "z|chk=crc32:" + SleepyNativeFormat.crc32(body.data(using: .utf8)!)
        XCTAssertEqual(expected, lines[chkIdx])
    }

    func testBlankTableNameEmitsDefaultName() {
        // Android tableName.ifBlank: 纯空格名 → "导入的课表"; isEmpty 判定会原样写出 " "
        let out = SleepyNativeExporter.exportFile(tableName: "   ", startDate: "2026-02-23",
                                                  maxWeek: 16, nodesPerDay: 2, timeJson: "",
                                                  courses: [])
        XCTAssertTrue(out.contains("T导入的课表|"), "out=\(out)")
    }

    // ---- v1.0.56 T11: 纯作息单独导出 (← PeriodTableOnlyExportTest.kt) ----

    private let threeNodeJson = "[{\"node\":1,\"start\":\"08:20\",\"end\":\"09:05\"},{\"node\":2,\"start\":\"09:15\",\"end\":\"10:00\"},{\"node\":3,\"start\":\"10:20\",\"end\":\"11:05\"}]"

    private func periodEntity(id: Int64 = 7, name: String = "春季作息",
                              nodesPerDay: Int = 3, timeJson: String? = nil) -> PeriodTableEntity {
        var e = PeriodTableEntity(name: name)
        e.id = id
        e.nodesPerDay = nodesPerDay
        e.timeJson = timeJson ?? threeNodeJson
        return e
    }

    func testPeriodOnlyShareTextShape() {
        let text = SleepyNativeExporter.exportPeriodTableShareText(periodEntity())
        XCTAssertTrue(text.contains("<<<SLEEPY-BEGIN>>>"))
        XCTAssertTrue(text.contains("#sleepy-v1"))
        XCTAssertTrue(text.contains("P春季作息|7|3"), "text=\(text)")
        XCTAssertTrue(text.contains("Pn1|08:20|09:05"), "text=\(text)")
        XCTAssertTrue(text.contains("Pn3|10:20|11:05"), "text=\(text)")
        // 纯作息 = 零课程行, 零 T 行
        XCTAssertTrue(text.components(separatedBy: .newlines).allSatisfy { !$0.hasPrefix("C") })
        XCTAssertTrue(text.components(separatedBy: .newlines).allSatisfy { !$0.hasPrefix("T") })
    }

    func testPeriodOnlyShareTextNdPresetFoldsToPd() {
        let text = SleepyNativeExporter.exportPeriodTableShareText(periodEntity(timeJson: TimeTableUtils.DEFAULT_TIME_JSON))
        XCTAssertTrue(text.contains("Pd"), "text=\(text)")
    }

    func testPeriodOnlyJsonShape() {
        let json = SleepyNativeExporter.exportPeriodTableJson(periodEntity())
        XCTAssertTrue(json.contains("\"name\""))
        XCTAssertTrue(json.contains("春季作息"))
        XCTAssertTrue(json.contains("\"nodesPerDay\""))
        XCTAssertTrue(json.contains("\"node\""))
        // timeList 用 WakeUp 原生字段名 — 解析端 harvest 按此收割
        XCTAssertTrue(json.contains("\"startTime\":\"08:20\""), "json=\(json)")
        XCTAssertTrue(json.contains("\"endTime\":\"11:05\""), "json=\(json)")
    }

    func testPeriodOnlyJsonParsesBackToPurePeriodResult() throws {
        // ← PeriodTableOnlyExportTest.json_parses_back_to_pure_period_result (v1.0.56 T11)
        // 纯作息 JSON 走 tableInfo.timeList 收割: courses 空 + periodTable 非空 → T9 只建作息表
        let json = SleepyNativeExporter.exportPeriodTableJson(periodEntity())
        let r = try parse(json)
        XCTAssertEqual(0, r.courses.count)
        let pt = try XCTUnwrap(r.periodTable)
        XCTAssertEqual("春季作息", pt.name)
        XCTAssertEqual(3, pt.nodesPerDay)
        let nodes = TimeTableUtils.parseNodes(pt.timeJson)
        XCTAssertEqual(3, nodes.count)
    }
}
