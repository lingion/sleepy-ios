// JwCquParser.swift — ← JwCquParser.kt
// 重庆大学 my.cqu.edu.cn 课表 JSON 解析器。
//
// 与 JwWiseduParser 同类: source 不是 HTML, 而是课表 API 的 JSON 响应
// (在 WebView 内通过 fetch 拿到, 见 JwWebViewLoginScreen 的 CQU 分支)。
//
// 数据来源: POST /api/timetable/class/timetable/student/my-table-detail?sessionId=…
//   headers: Authorization: Bearer <cqu_edu_ACCESS_TOKEN>(localStorage 取)
//   body: JSON 数组 [学号]
// 返回结构: {"classTimetableVOList":[{…}]}
//
// 字段映射(教务 → JwCourse):
//   courseName   课程名   → name
//   instructorName "张三-数学与统计学院" → teacher(取首个 '-' 前段, 多段职称/院系截断)
//   position ?: roomName  → room
//   weekDay      星期(1=周一..7=周日) → day
//   periodFormat "3-4" / "5" → startNode/endNode
//   teachingWeek "111…0" bitmap → 周次段(与金智 SKZC 同一套压缩规则)
//
// 外部佐证: 时光课程表 cqu.js(茵符草)、321CQU/pymycqu course_timetable.py。

import Foundation

final class JwCquParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() throws -> [JwCourse] {
        guard let data = source.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let rows = root["classTimetableVOList"] as? [Any] else { return [] }

        var result: [JwCourse] = []
        for el in rows {
            guard let o = el as? [String: Any] else { continue }
            let name = jstr(o, "courseName")
            if name.isEmpty { continue }

            // instructorName "张三-数学与统计学院-教授" → "张三"(首个 '-' 前段; 空/null → "")
            let teacherRaw = jstr(o, "instructorName")
            let teacher = teacherRaw.isEmpty ? "" : String(teacherRaw.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
                .trimmingCharacters(in: .whitespaces)

            // position 优先(我的课表常填), 缺位回退 roomName; 两者皆 null → ""
            let position = jstr(o, "position")
            let room = position.isEmpty ? jstr(o, "roomName") : position

            // Kotlin 端 int(k) = str(k).toIntOrNull(): 越界 Int32(如 "9999999999")返回 null → 丢弃该行。
            // Swift Int 为 64 位, 需范围守卫复刻该宽度(共享 jint 不改, 避免波及其它解析器)。
            func cint(_ key: String) -> Int? {
                guard let v = jint(o, key), v >= Int(Int32.min), v <= Int(Int32.max) else { return nil }
                return v
            }

            guard let day = cint("weekDay") else { continue }

            // periodFormat "3-4" / "5"(单节起止相同); 非数字整体 → 丢弃该行。
            // endNode 严格复刻 Kotlin substringAfter('-'): 取首个 '-' 之后整串再 trim().toIntOrNull(),
            // 多横线(如 "3-4-5")尾段为 "4-5" → 解析失败回退 startNode(≠ 取第二段)。
            let pf = jstr(o, "periodFormat")
            let startNode: Int
            let endNode: Int
            if let dash = pf.firstIndex(of: "-") {
                let head = String(pf[pf.startIndex..<dash]).trimmingCharacters(in: .whitespaces)
                guard let s = Int(head), s >= Int(Int32.min), s <= Int(Int32.max) else { continue }
                startNode = s
                let tail = String(pf[pf.index(after: dash)...]).trimmingCharacters(in: .whitespaces)
                if let e = Int(tail), e >= Int(Int32.min), e <= Int(Int32.max) {
                    endNode = e
                } else {
                    endNode = s
                }
            } else {
                guard let s = Int(pf.trimmingCharacters(in: .whitespaces)),
                      s >= Int(Int32.min), s <= Int(Int32.max) else { continue }
                startNode = s
                endNode = s
            }

            for (sw, ew, type) in weekRuns(jstr(o, "teachingWeek")) {
                result.append(JwCourse(
                    name: name, room: room, teacher: teacher,
                    day: min(max(day, 1), 7),
                    startNode: max(startNode, 1),
                    endNode: max(endNode, startNode),
                    startWeek: sw, endWeek: ew, type: type))
            }
        }
        return result
    }

    /// teachingWeek 周次 bitmap → 连续段列表 [(startWeek, endWeek, type)]。
    /// 与 JwWiseduParser SKZC 同一套压缩规则(单段 0=每周; 整体 step=2 → 1=单周/2=双周; 否则拆段)。
    func weekRuns(_ bitmap: String) -> [(Int, Int, Int)] {
        let weeks = bitmap.enumerated().compactMap { $0.element == "1" ? $0.offset + 1 : nil }
        if weeks.isEmpty { return [] }

        var runs: [(Int, Int)] = []
        var start = weeks[0]
        var prev = weeks[0]
        for w in weeks.dropFirst() {
            if w == prev + 1 {
                prev = w
            } else {
                runs.append((start, prev))
                start = w
                prev = w
            }
        }
        runs.append((start, prev))

        if runs.count == 1 {
            return [(runs[0].0, runs[0].1, 0)]
        }
        if weeks.count >= 2 && (1..<weeks.count).allSatisfy({ weeks[$0] - weeks[$0 - 1] == 2 }) {
            let type = weeks.first! % 2 == 1 ? 1 : 2
            return [(weeks.first!, weeks.last!, type)]
        }
        return runs.map { ($0.0, $0.1, 0) }
    }

    /// my-table-detail = 100; classTimetableVOList = 90(← confidence 覆盖)
    var confidenceValue: Int {
        if source.contains("classTimetableVOList") { return 90 }
        if source.contains("my-table-detail") { return 80 }
        return 0
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("classTimetableVOList") { out.append("classTimetableVOList.rows") }
        if source.contains("my-table-detail") { out.append("my-table-detail") }
        return out
    }
}
