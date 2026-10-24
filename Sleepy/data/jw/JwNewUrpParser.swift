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

final class JwNewUrpParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() throws -> [JwCourse] {
        var result: [JwCourse] = []

        // 1. 从 HTML 里抠出 JSON 字符串
        guard let jsonText = Self.extractJsonFromHtml(source) else { return result }

        // 2. 解析 JSON
        guard let data = jsonText.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return result
        }
        guard let dateList = root["dateList"] as? [Any] else { return result }
        if dateList.isEmpty { return result }

        // ← Android dateList.getJSONObject(0): 元素非对象时抛异常(不静默吞)
        // 注: Android 的 optJSONArray 无字符串强制转换(instanceof 检查而已), 故此处 as? 即对齐
        let firstDate = try Self.jsonObject(in: dateList, at: 0, path: "dateList")
        guard let courseList = firstDate["selectCourseList"] as? [Any] else { return result }

        for i in 0..<courseList.count {
            // ← Android courseList.getJSONObject(i)
            let course = try Self.jsonObject(in: courseList, at: i, path: "selectCourseList")
            let name = (course["courseName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let teacher = (course["attendClassTeacher"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // ← Android course.optJSONArray("timeAndPlaceList"): instanceof 检查, 无字符串强制转换
            guard let timeAndPlaceList = course["timeAndPlaceList"] as? [Any] else { continue }

            for j in 0..<timeAndPlaceList.count {
                // ← Android timeAndPlaceList.getJSONObject(j)
                let tp = try Self.jsonObject(in: timeAndPlaceList, at: j, path: "timeAndPlaceList")
                func optInt(_ k: String, _ d: Int) -> Int {
                    if let v = tp[k] as? Int { return v }
                    // ← org.json optInt: Integer.parseInt(value.toString().trim())
                    if let v = tp[k] as? String, let i = Int(v.trimmingCharacters(in: .whitespacesAndNewlines)) { return i }
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
                let fullRoom = (campus + building + room).trimmingCharacters(in: .whitespacesAndNewlines)

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

    /// ← org.json JSONArray.getJSONObject(index): 元素不是 JSON 对象时抛异常
    /// (Android 侧 JSONException 直接冒泡;iOS 不得静默丢弃整个数组)
    private static func jsonObject(in array: [Any], at index: Int, path: String) throws -> [String: Any] {
        guard let obj = array[index] as? [String: Any] else {
            throw JwParseError(message: "JwNewUrpParser: \(path)[\(index)] is not a JSON object")
        }
        return obj
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
                    // ← Kotlin: 循环前不给 end 赋值(2 元素段 end 保持 = start)
                    step = 2
                    var k = i + 1
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

    // MARK: - T8 置信度

    /// dateList+selectCourseList+timeAndPlaceList = 100; dateList+selectCourseList = 80; 仅 dateList = 50
    var confidenceValue: Int {
        let hasDate = source.contains("dateList")
        let hasSelect = source.contains("selectCourseList")
        let hasTime = source.contains("timeAndPlaceList")
        if hasDate && hasSelect && hasTime { return 100 }
        if hasDate && hasSelect { return 80 }
        if hasDate { return 50 }
        return 0
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("dateList") { out.append("dateList") }
        if source.contains("selectCourseList") { out.append("selectCourseList") }
        if source.contains("timeAndPlaceList") { out.append("timeAndPlaceList") }
        if source.contains("classWeek") { out.append("classWeek") }
        return out
    }
}
