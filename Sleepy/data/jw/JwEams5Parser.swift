// JwEams5Parser.swift — ← JwEams5Parser.kt
//
// 合工大教务 (金智 EAMS5, eams5-student 系列) 课表 JSON 解析器。
//
// 适配学校：合肥工业大学 (jxglstu.hfut.edu.cn) + 安徽大学 (jw.ahu.edu.cn, 金智 EAMS 新版)。
// 与 JwCquParser 同类：source 不是 HTML，而是课表 API 的 JSON 响应。
//
// 数据来源 (WebView 内 fetch):
//
//   **HFUT 形态** (JwWebViewLoginScreen EAMS5_FETCH_JS 三段):
//     1) GET /eams5-student/for-std/course-table                → studentId
//     2) GET /eams5-student/for-std/lessons?studentId=…        → lessonIds[]
//     3) POST /eams5-student/ws/schedule-table/datum            → 完整课表
//        body: {"lessonIds":[…], "studentId":…, "weekIndex":""}
//        resp: {"result":{"lessonList":[…],"scheduleList":[…],"scheduleGroupList":[…]}}
//
//   **AHU 形态** (JwWebViewLoginScreen EAMS5_AHU_FETCH_JS, 2026-09-06 加):
//     1) GET /student/for-std/course-table                       → HTML 含 allSemesters
//     2) 从 HTML 提取 allSemesters, 取首个 semesterId
//     3) GET /student/for-std/course-table/semester/<semesterId>/print-data
//        ?semesterId=<id>&hasExperiment=false
//        resp: {"studentTableVms":[{"activities":[…],"scheduleGroupVms":[…]}]}
//
//     (旧实现) GET /student/for-std/course-table/get-data?bizTypeId=2&semesterId=<id>&dataId=
//        resp: {"data":{"lessons":[…]}}  — metadata-only, 不可作为课表主数据源。
//
// 字段映射（教务 → JwCourse）：
//   HFUT scheduleList[].lessonId / AHU activities[].lessonId
//     → 查 lessonList[].id → courseName; 找不到回退 lessonId.toString()
//   room: HFUT scheduleList[].room.nameZh / AHU campus + " " + building + " " + room
//   weekday → day (1=周一..7=周日)
//   teacher: HFUT scheduleList[].personName / AHU activities[].teacherNames.join("/")
//   week: HFUT scheduleList[].weekIndex (单值) / AHU activities[].weekIndexes (bitmap)
//   节次: HFUT startTime/endTime → 推断 / AHU startUnit/endUnit (直接给定)
//
// 外部佐证 (5 仓):
//   HFUT: Chiu-xaH/HFUT-Schedule, BoynChan/HfutOpenApi, elonzh/django-hfut-auth, Aoi-cn/hfut_schedule_hacker
//   AHU: MoeclubM/AHU-AIO (Dart, GPL-3.0), qiqqqqq517/shangkeschschedule (Apache-2.0),
//        abydym/Ahu_Plus (GPL-3.0, Kotlin 同栈), Landon-3314/AHU-TimeTable (Flutter),
//        Zeraora-807/Anhui-Univ-DSH-Tool (TypeScript)

import Foundation

final class JwEams5Parser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() throws -> [JwCourse] {
        guard let data = source.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return []
        }

        func content(_ v: Any?) -> String? {
            if let s = v as? String { return s }
            if let n = v as? NSNumber { return n.stringValue }
            return nil
        }

        // AHU 形态优先匹配 (5 仓 cross-verified 共识):
        //   1) studentTableVms[0].activities[] (print-data) — 真正课表数据 (weekday/startUnit/...)
        //   2) data.lessons[] (get-data) — metadata-only, 含 courseCode/examMode 但缺节次
        // 逐元素容错 (对齐 Android runCatching{el.jsonObject}.getOrNull()?:continue):
        // 数组含脏元素只跳过该行, 不整体作废。
        if let stVms = root["studentTableVms"] as? [Any], !stVms.isEmpty {
            let firstTable = stVms.first as? [String: Any]
            if let activities = firstTable?["activities"] as? [Any], !activities.isEmpty {
                return parseAhuPrintDataActivities(activities)
            }
        }
        if let ahuLessons = (root["data"] as? [String: Any])?["lessons"] as? [Any], !ahuLessons.isEmpty {
            return parseAhuLessons(ahuLessons)
        }

        // HFUT 形态: result.lessonList[] + result.scheduleList[] (双层)
        guard let result = root["result"] as? [String: Any] else { return [] }

        // issue #46: 布局查表 (服务端权威节次表)。JS 链第 3.5 段 POST
        // /ws/schedule-table/timetable-layout 拿 result.courseUnitList 后并入 payload 顶层;
        // 有则 startTime→indexNo 精确映射 (HFUTer/kirsh1 社区共识算法),
        // 无则 fallback heuristic (inferNodes), CUMTB/老包零回归。
        func intContent(_ v: Any?) -> Int? {
            content(v).flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        var unitByStart: [Int: Int] = [:]
        var unitEnds: [(end: Int, indexNo: Int)] = []   // (endTime, indexNo)
        if let units = root["courseUnitList"] as? [Any] {
            for u in units {
                guard let o = u as? [String: Any] else { continue }
                guard let idx = intContent(o["indexNo"]) else { continue }
                guard let st = intContent(o["startTime"]) else { continue }
                guard let et = intContent(o["endTime"]) else { continue }
                unitByStart[st] = idx
                unitEnds.append((et, idx))
            }
            // Android sortBy 是稳定排序 (并列保持表序, 典型表序即 indexNo 升序),
            // Swift sort 不保证稳定 → 并列显式按 indexNo 升序, 行为对齐。
            unitEnds.sort { $0.end < $1.end || ($0.end == $1.end && $0.indexNo < $1.indexNo) }
        }

        // lessonList → lessonId (String) → courseName (HFUT 用 String, scheduleList 用 Int — 注意互转)
        var nameMap: [String: String] = [:]
        if let lessonArr = result["lessonList"] as? [Any] {
            for el in lessonArr {
                guard let o = el as? [String: Any] else { continue }
                let id = content(o["id"]) ?? ""
                let name = content(o["courseName"]) ?? ""
                if !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    nameMap[id] = name
                }
            }
        }

        guard let scheduleArr = result["scheduleList"] as? [Any] else { return [] }

        var out: [JwCourse] = []
        for el in scheduleArr {
            guard let o = el as? [String: Any] else { continue }
            guard let lessonIdInt = intContent(o["lessonId"]) else { continue }
            let lessonIdStr = String(lessonIdInt)
            let name = nameMap[lessonIdStr] ?? lessonIdStr

            let room = ((o["room"] as? [String: Any]).flatMap { content($0["nameZh"]) } ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let teacher = (content(o["personName"]) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let day = intContent(o["weekday"]) else { continue }
            guard let weekIndex = intContent(o["weekIndex"]) else { continue }
            let startTime = intContent(o["startTime"]) ?? 0
            let endTime = intContent(o["endTime"]) ?? 0
            let periods = intContent(o["periods"]) ?? 1

            // issue #46: 布局查表优先 — schedule.startTime 精确等于 unit.startTime (采集包 122/122);
            // endUnit = endTime >= unit.endTime 的最大 indexNo (11 仓实测零失败)。
            // 查表不完整 (start 缺 / end 无覆盖) → 整行走旧 heuristic。
            let inferred: (Int, Int)?
            if !unitByStart.isEmpty,
               let su = unitByStart[startTime],
               let eu = unitEnds.last(where: { $0.end <= endTime })?.indexNo,
               eu >= su {
                inferred = (su, eu)
            } else {
                inferred = Self.inferNodes(startTime, endTime, periods)
            }
            guard let inferred = inferred else { continue }

            out.append(JwCourse(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                room: room,
                teacher: teacher,
                day: min(max(day, 1), 7),
                startNode: max(inferred.0, 1),
                endNode: max(inferred.1, inferred.0),
                startWeek: weekIndex,
                endWeek: weekIndex,
                type: 0))
        }
        return out
    }

    /// AHU 形态解析: `data.lessons[]` 扁平结构 (已合并 scheduleList+lessonList)。
    /// 字段映射 (qiqqqqq517 ahu.js 实锤)。
    private func parseAhuLessons(_ lessons: [Any]) -> [JwCourse] {
        var out: [JwCourse] = []
        func content(_ v: Any?) -> String? {
            if let s = v as? String { return s }
            if let n = v as? NSNumber { return n.stringValue }
            return nil
        }
        for el in lessons {
            guard let o = el as? [String: Any] else { continue }
            let lessonId = content(o["lessonId"]) ?? content(o["id"])
            guard let lid = lessonId, !lid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let name = content(o["courseName"]) ?? lid
            let room = (content(o["room"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let teacher = (content(o["teacher"]) ?? content(o["personName"]) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let day = content(o["weekday"]).flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) else { continue }
            guard let weekIndex = content(o["weekIndex"]).flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) else { continue }
            let startTime = content(o["startTime"]).flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) ?? 0
            let endTime = content(o["endTime"]).flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) ?? 0
            let periods = content(o["periods"]).flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) ?? 1

            guard let inferred = Self.inferNodes(startTime, endTime, periods) else { continue }

            out.append(JwCourse(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                room: room,
                teacher: teacher,
                day: min(max(day, 1), 7),
                startNode: max(inferred.0, 1),
                endNode: max(inferred.1, inferred.0),
                startWeek: weekIndex,
                endWeek: weekIndex,
                type: 0))
        }
        return out
    }

    /// AHU print-data 形态解析: `studentTableVms[0].activities[]`
    /// (5 仓 cross-verified 共识: MoeclubM + abydym + Landon-3314 + Zeraora-807 + qiqqqqq517)
    private func parseAhuPrintDataActivities(_ activities: [Any]) -> [JwCourse] {
        var out: [JwCourse] = []
        func content(_ v: Any?) -> String? {
            if let s = v as? String { return s }
            if let n = v as? NSNumber { return n.stringValue }
            return nil
        }
        for el in activities {
            guard let o = el as? [String: Any] else { continue }
            guard let name = content(o["courseName"]) else { continue }

            // teacherNames → List<String> → join "/" (5 仓 consensus)
            // 防御性 fallback: teachers[] / teacherList / 单字符串 teacher / personName
            var teacher = ""
            let tArr = (o["teacherNames"] as? [Any])
                ?? (o["teachers"] as? [Any])
                ?? (o["teacherList"] as? [Any])
            if let tArr = tArr {
                let names = tArr.compactMap { content($0) }
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                if !names.isEmpty {
                    teacher = names.joined(separator: "/")
                }
            }
            if teacher.isEmpty {
                teacher = (content(o["teacher"]) ?? content(o["personName"]) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // room: campus + building + room 三段拼接 (Landon-3314 实锤)
            let campus = (content(o["campus"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let building = (content(o["building"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let roomNum = (content(o["room"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let room = [campus, building, roomNum].filter { !$0.isEmpty }.joined(separator: " ")

            guard let day = content(o["weekday"]).flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) else { continue }
            guard let startNode = content(o["startUnit"]).flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) else { continue }
            guard let endNode = content(o["endUnit"]).flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) else { continue }

            // weekIndexes bitmap 完整 RLE 解析 — emit 多 JwCourse (单/双周/区间/离散)
            // 5 仓 cross-validated 2026-09-06: parseWeekRanges 复用 JwParity 端点修正
            let weekIndexesStr = content(o["weekIndexes"]) ?? ""
            let weekRanges = Self.parseWeekRanges(weekIndexesStr)
            for (startWeek, endWeek, weekType) in weekRanges {
                out.append(JwCourse(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    room: room,
                    teacher: teacher,
                    day: min(max(day, 1), 7),
                    startNode: max(startNode, 1),
                    endNode: max(endNode, startNode),
                    startWeek: startWeek,
                    endWeek: endWeek,
                    type: weekType))
            }
        }
        return out
    }

    /// AHU weekIndexes bitmap 完整 RLE 解析 — emit 多 JwCourse
    ///
    /// 真实形态 (5 仓 cross-validated 2026-09-06):
    ///   "1-16"        → [(1,16,0)]         (全周)
    ///   "1-16单"      → [(1,15,1)]         (单周; JwParity 端点修正)
    ///   "1-16双"      → [(2,16,2)]         (双周)
    ///   "1-8,10-16"   → [(1,8,0), (10,16,0)]   (区间组合)
    ///   "8,10,12,14"  → [(8,8,0), (10,10,0), (12,12,0), (14,14,0)]  (离散)
    ///   "5周" / "5"   → [(5,5,0)]          (单值)
    ///   ""            → [(1,1,0)]          (兜底)
    ///
    /// 算法 (借 JwSeuParser.parseWeekRanges 同型, 复用 JwParity.adjustedRange)。
    /// Sleepy type 语义 (JwParity 共识): 0=每周 1=单周 2=双周
    static func parseWeekRanges(_ weekIndexes: String) -> [(Int, Int, Int)] {
        if weekIndexes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [(1, 1, 0)] }
        // 剥 "周" / 括号形态; 处理 "1-16周" / "1-16(单)" / "1-16 odd" 等
        let clean = weekIndexes
            .replacingOccurrences(of: "周", with: "")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "(", with: "(")
            .replacingOccurrences(of: ")", with: ")")
        let segments = clean.components(separatedBy: CharacterSet(charactersIn: ",，"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if segments.isEmpty { return [(1, 1, 0)] }

        var out: [(Int, Int, Int)] = []
        for seg in segments {
            // 段内 parity 检测: "单" / "双" / "odd" / "even" (不区分大小写)
            let parity: Int
            if seg.contains("单") || seg.range(of: #"\bodd\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                parity = 1
            } else if seg.contains("双") || seg.range(of: #"\beven\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                parity = 2
            } else {
                parity = 0
            }
            var bare = seg
                .replacingOccurrences(of: "(单)", with: "")
                .replacingOccurrences(of: "(双)", with: "")
                .replacingOccurrences(of: "(单", with: "")
                .replacingOccurrences(of: "(双", with: "")
                .replacingOccurrences(of: "单", with: "")
                .replacingOccurrences(of: "双", with: "")
            bare = bare.replacingOccurrences(of: "odd", with: "", options: .caseInsensitive)
            bare = bare.replacingOccurrences(of: "even", with: "", options: .caseInsensitive)
            bare = bare.trimmingCharacters(in: .whitespacesAndNewlines)
            if bare.isEmpty { continue }
            if bare.contains("-") {
                // 范围: "1-16" 或 "1- 16"
                // 对齐 Android bare.split("-", limit = 2): 只按首个横杠拆两段, 剩余部分保留 —
                // 畸形 "5-12-16" → a=5, b="12-16" 整串转 Int 失败 → b 回退 a → (5,5,parity)。
                let dash = bare.firstIndex(of: "-")!
                let aStr = String(bare[..<dash]).trimmingCharacters(in: .whitespaces)
                let bStr = String(bare[bare.index(after: dash)...]).trimmingCharacters(in: .whitespaces)
                guard let a = Int(aStr) else { continue }
                let b = Int(bStr) ?? a
                let r = JwParity.adjustedRange(a, b, parity: parity)
                out.append((r.start, r.end, parity))
            } else {
                // 单值: "5" 或 "5周"
                guard let v = Int(bare) else { continue }
                let r = JwParity.adjustedRange(v, v, parity: parity)
                out.append((r.start, r.end, parity))
            }
        }
        return out.isEmpty ? [(1, 1, 0)] : out
    }

    /// 由 startTime/endTime (HHmm) 推断 (startNode, endNode)。
    /// 标准 985 布局 (5 节次 × 2 节次 = 10 节点/天), 每节次 ~50 分钟 + 课间/午休/晚饭:
    ///   08:00-09:50  (node 1-2) / 10:10-12:00 (3-4) / 14:00-15:50 (5-6)
    ///   16:10-18:00  (7-8) / 19:00-20:50 (9-10)
    /// startTime 落到哪节次起点 → startNode 为该节次首节点;
    /// endTime 落在同一节次 → endNode = startNode + 1; 跨节次 → 按 periods 兜底。
    /// 失败时回退到 periods 推断。
    static func inferNodes(_ startTime: Int, _ endTime: Int, _ periods: Int) -> (Int, Int)? {
        guard let startSec = sectionIndex(startTime) else {
            // startTime 不在任何节次段窗口: KDoc 承诺的 periods 兜底 —
            // 起点退到第 1 节, endNode = 1 + periods - 1; 无 periods 信息
            // (<=0) 才放弃该行。
            if periods <= 0 { return nil }
            let endNode = max(1 + periods - 1, 1)
            return (1, endNode)
        }
        let startNode = startSec * 2 + 1
        let endSec = sectionIndex(endTime)
        let endNode: Int
        if endSec == nil {
            endNode = max(startNode + periods - 1, startNode)
        } else if endSec == startSec {
            endNode = startNode + 1
        } else if endSec! > startSec {
            endNode = endSec! * 2
        } else {
            endNode = startNode
        }
        return (startNode, max(endNode, startNode))
    }

    /// 时间 (HHmm) → 节次段索引 (0..4)。段起点 ±10 分钟内吸到该段; 其它返回 nil。
    private static func sectionIndex(_ time: Int) -> Int? {
        let hour = time / 100
        let minute = time % 100
        let mins = hour * 60 + minute
        let slots: [(Int, Int)] = [
            (8 * 60, 0),          // 08:00 → section 0 (node 1)
            (10 * 60 + 10, 1),    // 10:10 → section 1 (node 3)
            (14 * 60, 2),         // 14:00 → section 2 (node 5)
            (16 * 60 + 10, 3),    // 16:10 → section 3 (node 7)
            (19 * 60, 4),         // 19:00 → section 4 (node 9)
        ]
        for (slotMins, sec) in slots {
            if abs(mins - slotMins) <= 10 { return sec }
        }
        return nil
    }

    /// AHU print-data studentTableVms[0].activities[] = 100 (含 weekday+节次权威);
    /// AHU get-data data.lessons[] = 85 (metadata-only);
    /// HFUT 双层 = 95; schedule-table/datum = 80
    var confidenceValue: Int {
        if source.contains("studentTableVms") && source.contains("activities") { return 100 }
        if source.contains("data") && source.contains("\"lessons\"") { return 85 }
        if source.contains("scheduleList") && source.contains("lessonList") { return 95 }
        if source.contains("schedule-table/datum") { return 80 }
        return 0
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("studentTableVms") { out.append("studentTableVms[0].activities (AHU print-data)") }
        if source.contains("data") && source.contains("\"lessons\"") { out.append("data.lessons (AHU get-data metadata)") }
        if source.contains("scheduleList") { out.append("result.scheduleList") }
        if source.contains("lessonList") { out.append("result.lessonList") }
        if source.contains("schedule-table/datum") { out.append("ws/schedule-table/datum") }
        return out
    }
}
