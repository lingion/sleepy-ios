// JwQzAppParser.swift — ← JwQzAppParser.kt
//
// 强智移动教务 SPA 课表 JSON 解析器 (type=qz_app)。
//
// 适配学校: 河北资源环境职业技术学院 (jwpt.hebzyhj.edu.cn:1233, 2026-09-09 学生回传
// 采集包实锤)。与其它 JwParser 子类不同: source 不是 HTML, 而是移动端 JSON API 的
// 响应体 —
//
//   POST {ApiUrl}/student/curriculum?week=&kbjcmsid=   header: token: <JWT>
//   → {"code":"1","Msg":"success~","data":[{date:[…7 天],courses:[…]}],needClassName,needClassRoomNub}
//
// 端点一次只回一周: week= 空 = 当前教学周, week=N = 指定周; 响应 data 恒单元素,
// courses 只列该周出现的课 (classWeek 仍是全学期位图)。抓取侧 (QZ_APP_FETCH_JS)
// 先取 /teachingWeek 周数列表再并行逐周拉取, 合并成 {"weeks":[<单次响应>, …]}
// 组合源; 本 parser 遍历全部周元素, 完全相同的行只展开一次 — 只取当前周会让
// 仅在后续周出现的课整门丢失 (2026-09-11 学校学生反馈实锤)。
//
// 抓取方式: WebView 登录 SPA 后, JwWebViewLoginScreen 注入 QZ_APP_FETCH_JS 先 GET
// /dist/serverconfig.json (免鉴权) 发现 ApiUrl, 再带 sessionStorage.Token 请求课表;
// 结果经 __sleepyBridge.onWiseduResult({ok,data}) 桥回 (与 wisedu/NEU/CQU 同通道)。
// JS 侧只做 fetch 与透传, 禁止在 JS 里解码协议字段 (跨语言 invariant:
// 解码语义唯一落点 = 本 parser, 契约测试锁死)。
//
// 字段映射 (强智移动教务 → JwCourse):
//   courseName    → name
//   teacherName   → teacher
//   classroomNub  → room (楼-房完整房号, 回退 classroomName → location)
//   classTime     → day/startNode/endNode — 编码 = 星期+起止节, 如 "10304" =
//                   周一 3-4 节 (首位=星期 1-7, 后 4 位 = SS EE 各 2 位补零)
//   classWeek     → 周次集合 "1-4,6-19" (区间+单周混合), 带洞 → 拆连续段
//                   (整体等差 2 → 单/双周 type 1/2, 与 JwWiseduParser.weekRuns 同语义)
//
// date[] (本周 7 天 mxrq/zc) 深埋开学日期锚点, v1 不消费 (确认页手填学期开始日期,
// 与 NEU/CQU fetch 流程一致); needClassName/needClassRoomNub 为 SPA 显示开关,
// 与数据本体无关, 不消费。
//
// 未登录形态 {"code":"401","Msg":"非法访问：/student/curriculum"} → data 非数组 →
// emptyList (Registry 按 0 课空学期处理, 真实登录态由 WebView 会话保证)。
// 401 识别在 JS 传输层完成 (禁解码协议字段的跨语言 invariant 不受影响:
// weeks 信封的组装与逐元素透传都不是字段解码)。

import Foundation

final class JwQzAppParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() throws -> [JwCourse] {
        guard let data = source.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        let grids = Self.extractGrids(root)
        var seen = Set<String>()
        var result: [JwCourse] = []
        for grid in grids {
            // ← Android `if (el !is JsonObject) continue`: 逐元素过滤, 数组里混入
            // null/字符串等坏行只跳过该行, 不能像整体 `as? [[String: Any]]` 强转
            // 失败那样丢掉整个 grid 的全部课程。
            guard let rows = grid["courses"] as? [Any] else { continue }
            for case let o as [String: Any] in rows {
                // 逐周抓取后同一行课会在每周响应里重复出现 (classWeek 是全学期位图),
                // 完全相同的行只展开一次; 字段有任何差异的行都保留, 不猜并集
                guard seen.insert(Self.canonicalKey(o)).inserted else { continue }
                func str(_ k: String) -> String {
                    ((o[k] as? String) ?? (o[k] as? NSNumber)?.stringValue ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }

                let name = str("courseName")
                if name.isEmpty { continue }
                let teacher = str("teacherName")
                let room = [str("classroomNub"), str("classroomName"), str("location")]
                    .first { !$0.isEmpty } ?? ""
                let timeSpecs = Self.parseClassTime(str("classTime"))
                if timeSpecs.isEmpty { continue }
                let weeks = Self.parseWeekSpec(str("classWeek").isEmpty ? str("classWeekDetails") : str("classWeek"))
                let runs = Self.weekRuns(weeks)

                for (day, startNode, endNode) in timeSpecs {
                    for (sw, ew, type) in runs {
                        result.append(JwCourse(
                            name: name,
                            room: room,
                            teacher: teacher,
                            day: day,
                            startNode: startNode,
                            endNode: endNode,
                            startWeek: sw,
                            endWeek: ew,
                            type: type))
                    }
                }
            }
        }
        return result
    }

    /// 提取课表网格 (含 courses 数组的对象) 列表。
    /// 旧形态: source 就是单次 POST 响应, data[0] 唯一元素。
    /// 逐周合并形态 (QZ_APP_FETCH_JS 循环 teachingWeek 周数逐周抓取后合并):
    /// {"weeks":[<单次响应>, …]} — 每个元素只含该周出现的课, 全部遍历,
    /// 否则只在后续周出现的课整门丢失。
    static func extractGrids(_ root: [String: Any]) -> [[String: Any]] {
        if let weeks = root["weeks"] as? [Any] {
            var grids: [[String: Any]] = []
            for element in weeks.compactMap({ $0 as? [String: Any] }) {
                guard let payloadList = element["data"] as? [Any] else { continue }
                grids.append(contentsOf: payloadList.compactMap { $0 as? [String: Any] })
            }
            return grids
        }
        return (root["data"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    /// ← Kotlin `el.toString()` 整行去重键。JSONSerialization 字典无序, 故按 key 排序
    /// 递归序列化: 行内容完全相同 → 同串 (只展开一次); 任一字段有差异 → 不同串 (都保留)。
    static func canonicalKey(_ value: Any) -> String {
        if let dict = value as? [String: Any] {
            let parts = dict.keys.sorted().map { "\"\($0)\":\(canonicalKey(dict[$0] as Any))" }
            return "{" + parts.joined(separator: ",") + "}"
        }
        if let arr = value as? [Any] {
            return "[" + arr.map { canonicalKey($0) }.joined(separator: ",") + "]"
        }
        if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() { return num.boolValue ? "true" : "false" }
            return num.stringValue
        }
        if let text = value as? String { return "\"\(text)\"" }
        return "null"
    }

    /// classTime 编码 → [(day, start, end)] 列表 (一行课可含多段)。
    ///
    /// 已知形态 (2026-09-11 学生采集包实锤):
    ///   "10304"     → [(1, 3, 4)]            周一 3-4 节 (5 位 = 星期 + 一组起止)
    ///   "301020304" → [(3, 1, 2), (3, 3, 4)] 周三 1-2 + 3-4 连堂两段
    ///   首位 = 星期 (1-7, 禁 0); 其余每 2 位一对 = (start, end) 补零节次,
    ///   相邻对首尾相接的连堂合并不拆 (SPA 网格以每对独立格子渲染, 保持逐对 =
    ///   SPA 行为; weekNoteDetail "301,302,…" 与逐对节次一致)。
    /// 非数字 / 剩余位为奇数 / 节次非法 → 空列表。
    static func parseClassTime(_ v: String) -> [(day: Int, start: Int, end: Int)] {
        if v.isEmpty || v.contains(where: { $0 < "0" || $0 > "9" }) { return [] }
        guard let day = v.first?.wholeNumberValue, (1...7).contains(day) else { return [] }
        let rest = Array(v.dropFirst())
        if rest.isEmpty || rest.count % 2 != 0 { return [] }
        // 每 4 位 = (start, end) 各 2 位; 剩 2 位 = 单节 (start == end)
        var specs: [(day: Int, start: Int, end: Int)] = []
        var i = 0
        while i < rest.count {
            guard let start = Int(String(rest[i..<i + 2])) else { return [] }
            var end = start
            if i + 4 <= rest.count {
                guard let e = Int(String(rest[i + 2..<i + 4])) else { return [] }
                end = e
            }
            if start < 1 || end < start { return [] }
            specs.append((day, start, end))
            i += 4
        }
        return specs
    }

    /// 周次集合 "1-4,6-19" → 周次列表。区间 "a-b" + 单周 "a" 混合; 域外/非法 token 忽略。
    /// classWeek 为空时回退 classWeekDetails 逗号位图串 (",1,2,3,…")。
    static func parseWeekSpec(_ spec: String) -> [Int] {
        var weeks = Set<Int>()
        for token in spec.components(separatedBy: ",") {
            let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            if t.range(of: #"^\d+-\d+$"#, options: .regularExpression) != nil {
                // 锚定 ^…$ 整 token 匹配 (← Android Regex("^(\d+)-(\d+)$").find):
                // "1-2-3" 这类多段 token 整串不匹配 → 忽略, 不取前两段
                let parts = t.components(separatedBy: "-")
                guard let lo = Int(parts[0]), let hi = Int(parts[1]) else { continue }
                if (1...30).contains(lo) && (lo...30).contains(hi) {
                    for w in lo...hi { weeks.insert(w) }
                }
            } else if t.range(of: #"^(\d+)$"#, options: .regularExpression) != nil,
                      let one = Int(t), (1...30).contains(one) {
                weeks.insert(one)
            }
        }
        return weeks.sorted()
    }

    /// 周次列表 → 连续段 [(startWeek, endWeek, type)]。语义与 JwWiseduParser.weekRuns
    /// 一致: 单一连续段 → type=0; 整体等差 step=2 → 单周(1)/双周(2); 多段 → 逐段 type=0。
    static func weekRuns(_ weeks: [Int]) -> [(Int, Int, Int)] {
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
        if runs.count == 1 { return [(runs[0].0, runs[0].1, 0)] }
        if weeks.count >= 2 && (1..<weeks.count).allSatisfy({ weeks[$0] - weeks[$0 - 1] == 2 }) {
            let type = weeks.first! % 2 == 1 ? 1 : 2
            return [(weeks.first!, weeks.last!, type)]
        }
        return runs.map { ($0.0, $0.1, 0) }
    }

    var confidenceValue: Int {
        if source.contains("\"classWeekDetails\"") && source.contains("\"classTime\"") { return 90 }
        if source.contains("\"classWeek\"") && source.contains("\"classTime\"") { return 85 }
        return 0
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("\"classWeekDetails\"") { out.append("classWeekDetails") }
        if source.contains("\"classTime\"") { out.append("classTime") }
        if source.contains("\"courses\":[") { out.append("courses[]") }
        if source.contains("\"code\"") && source.contains("\"Msg\"") { out.append("code/Msg envelope") }
        return out
    }
}
