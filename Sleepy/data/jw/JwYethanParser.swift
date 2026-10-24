// JwYethanParser.swift — ← JwYethanParser.kt
//
// 西南交通大学 yhxt.swjtu.edu.cn(YETHAN/以专 逐专平台)课表 JSON 解析器。
//
// 适配学校:西南交通大学本部 (yhxt.swjtu.edu.cn)。
//
// 数据来源:GET /yethan/common/course-schedule/student-course-schedule(零参数)
//   headers: ytoken: <JWT>(localStorage `ytoken` 取)+ .swjtu.edu.cn cookie
// 返回结构:{"code":"00000","data":[{...}]}
//
// 字段映射(教务 → JwCourse):
//   courseName → name
//   staffName  → teacher(整名保留)
//   classPlace{N}/classTime{N} 成对槽位 (1..40):
//     classTime  "7、10-12、14-15周 星期三 5节" → 周次段×星期×节次
//     classPlace "X30547(犀浦)(教师甲)"        → room(教师括号截掉)
//
// classTime 文法(顿号枚举正解,2026-09-15 采集包 85/85 实锤):
//   ^([0-9、\-]+)周\s*星期(.)\s*([0-9\-]+)节$
//   、枚举只作用于周次列表,整串共享一个「星期X 节」后缀
//   (首版按 、切分各段独立解析 → 11/85 FAIL,已弃)。
//
// classPlace 括号判别(4 形态):
//   "X30547(犀浦)(教师甲)" → room=X30547(犀浦)(两个括号=第二个是教师)
//   "X5218 (Martin Levesley)" / "X5218(Martin Levesley)" → room=X5218(无校区)
//   "北区田径场(犀浦)" / "X2319(犀浦)" → 原样保留(单括号=校区)
//   "Online(Anna Murawska)" / "Online" → room=Online
//
// 失效码(Arex 跨仓验证):00000 成功;401/A0230/A0422 登录失效 → 空列表。
// SM2 `_j` 加密只在 /register/…、/sport/…(选课),课表接口无 SM2,Sleepy 不需要。

import Foundation

final class JwYethanParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    /// 顿号枚举正解文法:周次列表(顿号/区间)+ 共享一个「星期X 节」后缀
    static let classTimeRegex = "^([0-9、\\-]+)周\\s*星期(.)\\s*([0-9\\-]+)节$"

    private let dayCharToNumber: [Character: Int] = [
        "一": 1, "二": 2, "三": 3, "四": 4,
        "五": 5, "六": 6, "日": 7, "天": 7,
    ]

    // MARK: - T8

    func generateCourseList() throws -> [JwCourse] {
        guard let data = source.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["data"] as? [[String: Any]] else {
            return []
        }

        let regex = try! NSRegularExpression(pattern: Self.classTimeRegex, options: [])
        var result: [JwCourse] = []

        for o in rows {
            // Kotlin str(k) 用 .trim(): 去首尾空白(含 \n\r)。对齐 whitespacesAndNewlines。
            let name = (o["courseName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }
            let teacher = (o["staffName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            for i in 1...40 {
                let timeKey = "classTime\(i)"
                let placeKey = "classPlace\(i)"
                let timeRaw = (o[timeKey] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if timeRaw.isEmpty { continue }
                let placeRaw = (o[placeKey] as? String ?? "")
                let place = roomOf(placeRaw)

                let range = NSRange(timeRaw.startIndex..., in: timeRaw)
                guard let m = regex.firstMatch(in: timeRaw, options: [], range: range) else { continue }

                let ns = timeRaw as NSString
                guard let dayCh = ns.substring(with: m.range(at: 2)).first,
                      let day = dayCharToCharacter(dayCh) else { continue }

                let nodeStr = ns.substring(with: m.range(at: 3))
                // Kotlin 语义: substringBefore/After('-') 只按「首个」'-' 切分。
                // "5-6-7" → start=5, end=substringAfter="6-7".toIntOrNull()=null → 回落 start=5。
                let startNode: Int
                let endNode: Int
                if let dash = nodeStr.firstIndex(of: "-") {
                    let before = String(nodeStr[..<dash]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let after = String(nodeStr[nodeStr.index(after: dash)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let s = Int(before) else { continue }
                    startNode = s
                    endNode = Int(after) ?? s
                } else {
                    guard let s = Int(nodeStr.trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
                    startNode = s
                    endNode = s
                }

                let weekListStr = ns.substring(with: m.range(at: 1))
                for (sw, ew) in weekRuns(weekListStr) {
                    result.append(JwCourse(
                        name: name,
                        room: place,
                        teacher: teacher,
                        day: max(1, min(day, 7)),
                        startNode: max(1, startNode),
                        endNode: max(startNode, endNode),
                        startWeek: sw,
                        endWeek: ew
                    ))
                }
            }
        }
        return result
    }

    private func dayCharToCharacter(_ c: Character) -> Int? {
        let s = String(c)
        return ["一": 1, "二": 2, "三": 3, "四": 4,
                "五": 5, "六": 6, "日": 7, "天": 7][s]
    }

    /**
     * 周次列表(顿号枚举 + 区间混合,如 "7、10-12、14-15")→ 连续段列表 [(startWeek, endWeek)]。
     * 顿号只切分列表项;项内 '-' 是区间;单值起止相同。
     */
    func weekRuns(_ weekList: String) -> [(Int, Int)] {
        var runs: [(Int, Int)] = []
        for part in weekList.components(separatedBy: "、") {
            let p = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if p.isEmpty { continue }
            if let dash = p.firstIndex(of: "-") {
                // Kotlin substringBefore/After('-'): 只按首个 '-' 切分。
                // "7-8-9" → e = "8-9".toIntOrNull() = null → continue(整项丢弃)。
                let sStr = String(p[..<dash]).trimmingCharacters(in: .whitespacesAndNewlines)
                let eStr = String(p[p.index(after: dash)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let s = Int(sStr), let e = Int(eStr),
                      (1...30).contains(s), (s...30).contains(e) else { continue }
                runs.append((s, e))
            } else {
                guard let w = Int(p), (1...30).contains(w) else { continue }
                runs.append((w, w))
            }
        }
        return runs
    }

    /**
     * classPlace 括号判别 → room。
     * 两个括号 → 第二个是教师,截掉;单括号 → 校区,原样保留;
     * Online(教师) → Online;空 → ""。
     */
    func roomOf(_ place: String) -> String {
        let p = place.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { return "" }
        let openCount = p.filter { $0 == "(" || $0 == "（" }.count
        if openCount >= 2 {
            let lastOpen = p.lastIndex(of: "(") ?? p.lastIndex(of: "（") ?? p.startIndex
            if lastOpen > p.startIndex {
                return String(p[..<lastOpen]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if p.lowercased().hasPrefix("online") { return "Online" }
        // 编码教室的单括号可能是教师(如 X5218 (Martin Levesley)),
        // 校区单括号则保留(如 X2319(犀浦))。中文括号内容按校区处理。
        let single = try? NSRegularExpression(pattern: "^([A-Za-z0-9]+)\\s*\\(([^()]+)\\)$", options: [])
        if let r = single,
           let m = r.firstMatch(in: p, options: [], range: NSRange(p.startIndex..., in: p)),
           m.numberOfRanges >= 3 {
            let ns = p as NSString
            let inner = ns.substring(with: m.range(at: 2))
            if !inner.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
                return ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return p
    }

    // MARK: - T9

    var confidenceValue: Int {
        if (source.contains("student-course-schedule")
             || (source.contains("\"code\":\"00000\"") && source.contains("\"courseName\""))) {
            return 90
        }
        if source.contains("classTime1") || source.contains("classPlace1") { return 80 }
        if source.contains("\"code\":\"A0422\"") || source.contains("\"code\":\"A0230\"")
            || source.contains("yhxt") { return 60 }
        return 0
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("student-course-schedule") { out.append("student-course-schedule") }
        if source.contains("\"code\":\"00000\"") { out.append("code.00000") }
        if source.contains("classTime1") { out.append("classTime1..40") }
        if source.contains("classPlace1") { out.append("classPlace1..40") }
        if source.contains("staffName") { out.append("staffName") }
        return out
    }
}