// JwNewUrpParser.swift — ← JwNewUrpParser.kt
// 新版 URP 教务系统解析器。
//
// URP 综合教务(新正方/URP/wisedu 等厂商)登录后,课表页用 JS 渲染,
// 课表数据从后端 `/jwglxt/kbcx/xskbcx` 之类 API 拿 JSON 注入页面。
//
// 数据结构(wakeup NewUrpParser 协议):
// ```
// {
//   "dateList": [
//     {
//       "selectCourseList": [
//         {
//           "courseName": "...",
//           "attendClassTeacher": "...",
//           "timeAndPlaceList": [
//             {
//               "classDay": 1,
//               "classSessions": 3,
//               "continuingSession": 2,
//               "classWeek": "11111111111111111111"  // 20 位 0/1,第 i 位 = 是否第 i 周
//               "campusName": "...",
//               "teachingBuildingName": "...",
//               "classroomName": "..."
//             }
//           ]
//         }
//       ]
//     }
//   ]
// }
// ```
//
// 注意:HTML 源码里这段 JSON 通常被嵌入到某个 <script> 标签的赋值里,
// 形如 `var kbxx_json = {...};`。需要从 HTML 里把它抠出来再 JSONSerialization。

import Foundation

final class JwNewUrpParser: JwParser {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() -> [JwCourse] {
        var result: [JwCourse] = []

        // 1. 从 HTML 里抠出 JSON 字符串
        guard let jsonText = Self.extractJsonFromHtml(source) else { return result }

        // 2. 解析 JSON
        guard let data = jsonText.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return result
        }
        guard let dateList = root["dateList"] as? [[String: Any]] else { return result }
        if dateList.isEmpty { return result }

        let firstDate = dateList[0]
        guard let courseList = firstDate["selectCourseList"] as? [[String: Any]] else { return result }

        for course in courseList {
            let name = (course["courseName"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let teacher = (course["attendClassTeacher"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard let timeAndPlaceList = course["timeAndPlaceList"] as? [[String: Any]] else { continue }

            for tp in timeAndPlaceList {
                func optInt(_ k: String, _ d: Int) -> Int {
                    if let v = tp[k] as? Int { return v }
                    if let v = tp[k] as? String, let i = Int(v) { return i }
                    return d
                }
                let day = optInt("classDay", 1)
                let startNode = optInt("classSessions", 1)
                let continuing = optInt("continuingSession", 1)
                let endNode = startNode + continuing - 1
                let classWeek = tp["classWeek"] as? String ?? ""
                let campus = tp["campusName"] as? String ?? ""
                let building = tp["teachingBuildingName"] as? String ?? ""
                let room = tp["classroomName"] as? String ?? ""
                let fullRoom = (campus + building + room).trimmingCharacters(in: .whitespaces)

                // 解析 classWeek: 字符串每位 0/1,从左到右对应第 1..N 周
                let weekBits = Self.parseWeekBits(classWeek)
                if weekBits.isEmpty { continue }

                // 用 wakeup 的 weekIntList2WeekBeanList 思路归并成 (start, end, type) 范围
                let ranges = Self.weekBitsToRanges(weekBits)
                for r in ranges {
                    result.append(JwCourse(
                        name: name,
                        room: fullRoom,
                        teacher: teacher,
                        day: day,
                        startNode: startNode,
                        endNode: endNode,
                        startWeek: r.0,
                        endWeek: r.1,
                        type: r.2
                    ))
                }
            }
        }
        return result
    }

    /// 从 HTML 源码里抠 JSON(供测试直接调用) ← extractJsonForTest
    func extractJsonForTest(_ html: String) -> String? {
        Self.extractJsonFromHtml(html)
    }

    /// 多种常见嵌入方式:
    ///   1. var xxx = {...};
    ///   2. <script>...{...}...</script>
    ///   3. window.xxx = {...};
    /// 启发式:找 `dateList` 关键字,截取最大合法 JSON
    private static func extractJsonFromHtml(_ html: String) -> String? {
        // 找包含 "dateList" 那一段
        let marker = "dateList"
        guard let idxRange = html.range(of: marker) else { return nil }
        let idx = html.distance(from: html.startIndex, to: idxRange.lowerBound)

        // 往前找最近的 '{'(JSON 开始)
        var start = idx
        let chars = Array(html)
        while start > 0 && chars[start] != "{" { start -= 1 }
        if chars[start] != "{" { return nil }

        // 往后数括号配对,找配对的 '}'
        var depth = 0
        var inString = false
        var escape = false
        var end = start
        for i in start..<chars.count {
            let c = chars[i]
            if escape { escape = false; continue }
            if c == "\\" { escape = true; continue }
            if c == "\"" && !escape { inString = !inString; continue }
            if inString { continue }
            switch c {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 { end = i; return String(chars[start...end]) }
            default:
                break
            }
        }
        return nil
    }

    private static func parseWeekBits(_ s: String) -> [Int] {
        var out: [Int] = []
        for (i, c) in s.enumerated() where c == "1" {
            out.append(i + 1)
        }
        return out
    }

    /// 把周次数组归并成 (start, end, type) 范围
    /// type: 0=每周 1=单周 2=双周
    private static func weekBitsToRanges(_ weeks: [Int]) -> [(Int, Int, Int)] {
        if weeks.isEmpty { return [] }
        var result: [(Int, Int, Int)] = []
        var i = 0
        while i < weeks.count {
            let start = weeks[i]
            var end = start
            var step = 1
            // 探测步长:看后一个是不是 start+1(每周)或 start+2(单/双)
            if i + 1 < weeks.count {
                let gap = weeks[i + 1] - start
                switch gap {
                case 1:
                    step = 1
                    end = weeks[i + 1]
                    var k = i + 1
                    while k + 1 < weeks.count && weeks[k + 1] - weeks[k] == 1 { k += 1; end = weeks[k] }
                    i = k + 1
                case 2:
                    // 奇数开头→单周;偶数开头→双周
                    step = 2
                    var k = i + 1
                    end = weeks[i + 1]
                    while k + 1 < weeks.count && weeks[k + 1] - weeks[k] == 2 { k += 1; end = weeks[k] }
                    let type = start % 2 != 0 ? 1 : 2
                    i = k + 1
                    result.append((start, end, type))
                    continue
                default:
                    i += 1
                    result.append((start, end, 0))
                    continue
                }
                let type = step == 1 ? 0 : (start % 2 != 0 ? 1 : 2)
                result.append((start, end, type))
            } else {
                result.append((start, end, 0))
                i += 1
            }
        }
        return result
    }
}
