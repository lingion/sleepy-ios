// JwJsonParsers.swift — ← JwSeuParser.kt / JwZjuParser.kt / JwUstcParser.kt / JwScuParser.kt
// 四所高校课表 JSON 协议解析器(985 批次 B 档)。JwNeuParser.kt 已拆到独立文件
// Sleepy/data/jw/JwNeuParser.swift(v1.0.60 全量移植: cellDetail/lab/parity)。共同点: source 不是 HTML 而是课表 JSON
// (用户粘入或 WebView fetch 拿到), JSON 解析 + 字段映射一次性完成。
// 逐解析器的协议形态/上游参考/单双周限制见各 struct 头注释与 JwProtocol.swift 常量注释。

import Foundation

// MARK: - JSON 容器取值辅助(等价 Kotlin str() 扩展; 模块级 internal 供 JwCquParser 复用)

func jsonObj(_ any: Any?) -> [String: Any]? { any as? [String: Any] }
func jsonArr(_ any: Any?) -> [Any]? { any as? [Any] }

/// JsonPrimitive.contentOrNull 等价: 字符串/数字都取 trimmed 字符串
func jstr(_ o: [String: Any]?, _ key: String) -> String {
    guard let o = o, let v = o[key] else { return "" }
    if let s = v as? String { return s.trimmingCharacters(in: .whitespaces) }
    if let n = v as? NSNumber { return n.stringValue }
    return ""
}

func jint(_ o: [String: Any]?, _ key: String) -> Int? {
    let s = jstr(o, key)
    return s.isEmpty ? nil : Int(s)
}

/// 对齐 Kotlin `Json { ignoreUnknownKeys = true; isLenient = true }` 的容错解析:
/// 当前工具链(Swift 5.8/iOS 16.4 SDK)没有 allowJSON5Syntax(iOS 17 Foundation),
/// 宽松重试不可编译 — 保持严格 JSONSerialization + .allowFragments;
/// kotlinx 对标量 root 的接受由 .allowFragments 对齐 ("42" 解析成 fragment,
/// 由调用方形状分发落到空列表, 不当解析失败)。
func jwParseJSONLenient(_ s: String) -> Any? {
    guard let data = s.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data, options: [.allowFragments])
}

// MARK: - 东南大学(正方 URP 系, newxk.urp.seu.edu.cn)
//
// 字段映射: KCM→name SKJS→teacher JASMC→room SKXQ→day KSJC→startNode JSJC→endNode ZCMC→周次段。
// 支持三形态 ZCMC: 范围"1-16周"/单双周"1-10周(单)"/离散"2,4,6周"。
// 单/双标记按逗号段内检测 (混合串各段独立成立); 端点修正走 JwParity.adjustedRange
// (端点相等时 end 抬回 start 防倒挂, endWeek 不做奇偶收缩)。
final class JwSeuParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() throws -> [JwCourse] {
        // 对齐 Kotlin Json { ignoreUnknownKeys = true; isLenient = true }
        guard let root = jwParseJSONLenient(source.trimmingCharacters(in: .whitespacesAndNewlines)) else { return [] }

        var arr: [Any] = []
        if let a = root as? [Any] {
            arr = a
        } else if let o = root as? [String: Any], let a = jsonArr(o["data"]) {
            arr = a
        } else {
            return []
        }

        var out: [JwCourse] = []
        for el in arr {
            guard let o = jsonObj(el) else { continue }
            let name = jstr(o, "KCM")
            if name.isEmpty { continue }
            var teacher = jstr(o, "SKJS")
            if teacher.lowercased() == "null" { teacher = "" }
            var room = jstr(o, "JASMC")
            if room.lowercased() == "null" { room = "" }
            guard let day = jint(o, "SKXQ") else { continue }
            guard let startNode = jint(o, "KSJC") else { continue }
            let endNode = jint(o, "JSJC") ?? startNode
            let zcmc = jstr(o, "ZCMC")

            for (sw, ew, type) in parseWeekRanges(zcmc) {
                out.append(JwCourse(
                    name: name, room: room, teacher: teacher,
                    day: min(max(day, 1), 7),
                    startNode: max(startNode, 1),
                    endNode: max(endNode, startNode),
                    startWeek: sw, endWeek: ew, type: type))
            }
        }
        return out
    }

    /// ZCMC 串 → [(startWeek, endWeek, type)]。三形态: 范围/单双周/离散/单值。
    /// 单/双标记按逗号段内检测 (混合串 "1-8周(单),9-16周(双)" 两段各自成立,
    /// 整串 first-match 会标错后半段)。端点修正走 JwParity.adjustedRange —
    /// 只抬起点到首个合法周, 端点相等时 end 抬回 start; endWeek 不做奇偶收缩
    /// (UI 连续显示, type 驱动斜体/灰显, 周次命中由下游 inWeek 按奇偶判定)。
    func parseWeekRanges(_ zcmc: String) -> [(Int, Int, Int)] {
        if zcmc.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        var out: [(Int, Int, Int)] = []

        // 剥 "周" + 全角括号归一 "(单)/(双)"; 按逗号拆段 — 单/双标记按段内检测
        let clean = zcmc
            .replacingOccurrences(of: "周", with: "")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
        let segments = clean.split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for seg in segments {
            let typeInt: Int
            if seg.contains("单") { typeInt = 1 }
            else if seg.contains("双") { typeInt = 2 }
            else { typeInt = 0 }
            let bare = seg
                .replacingOccurrences(of: "(单)", with: "")
                .replacingOccurrences(of: "(双)", with: "")
            if bare.contains("-") {
                let parts = bare.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard let a = Int(parts[0]) else { continue }
                let b = parts.count > 1 ? (Int(parts[1]) ?? a) : a
                // 单双周端点修正 (共享 helper: 端点相等时不产出倒挂区间)
                let (sw, ew) = JwParity.adjustedRange(a, b, parity: typeInt)
                out.append((sw, ew, typeInt))
            } else if let v = Int(bare) {
                out.append((v, v, 0))
            }
        }
        return out
    }

    var confidenceValue: Int {
        let quoted = source.contains("\"KCM\"") && source.contains("\"ZCMC\"")
        let bare = source.contains("KCM") && source.contains("ZCMC")
        if quoted { return 90 }
        if bare { return 70 }
        return 0
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("\"KCM\"") { out.append("KCM") }
        if source.contains("\"ZCMC\"") { out.append("ZCMC") }
        if source.contains("\"SKXQ\"") { out.append("SKXQ") }
        return out
    }
}

// MARK: - 浙江大学(正方新版 UGR 本研, zdbk.zju.edu.cn)
//
// 数据源: /classroom-web/classroom/searchTimetable 返回 kbList 数组。
// kcb 是 "课名<br>周次串<br>老师<br>教室" 拼接的 HTML 片段(以 zwf 截断);
// dsz="0"单/"1"双, djj=起始节, skcd=节次长度。单/双周端点修正由本 parser 负责。
final class JwZjuParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() throws -> [JwCourse] {
        // 对齐 Kotlin Json { ignoreUnknownKeys = true; isLenient = true }
        guard let root = jwParseJSONLenient(source) as? [String: Any],
              let kbList = jsonArr(root["kbList"]) else { return [] }
        var out: [JwCourse] = []
        for el in kbList {
            guard let obj = jsonObj(el) else { continue }
            guard let xqj = jint(obj, "xqj") else { continue }
            let dsz = jstr(obj, "dsz")
            let typeInt = dsz == "0" ? 1 : (dsz == "1" ? 2 : 0)
            guard let djj = jint(obj, "djj") else { continue }
            let skcd = jint(obj, "skcd") ?? 1
            let rawKcb = jstr(obj, "kcb")
            // zwf 截断 + <br> 分段(忠实 Kotlin: rawKcb.split("zwf")[0].split("<br>"))
            let beforeZwf = rawKcb.components(separatedBy: "zwf").first ?? rawKcb
            let fields = beforeZwf.components(separatedBy: "<br>")
            if fields.isEmpty { continue }
            // 忠实 Kotlin: getOrNull(0)?.replace(...)?.trim() — split 永远 ≥1 元素,
            // 仅在整体缺失时 continue; 空课名(如 "<br>1-16周<br>…")照常产出 name=""
            let name = fields[0].replacingOccurrences(of: "(", with: "（").replacingOccurrences(of: ")", with: "）")
                .trimmingCharacters(in: .whitespaces)
            let timeString = fields.count > 1 ? fields[1].trimmingCharacters(in: .whitespaces) : ""
            let teacher = fields.count > 2 ? fields[2].trimmingCharacters(in: .whitespaces) : ""
            let location = fields.count > 3 ? fields[3].trimmingCharacters(in: .whitespaces) : ""
            let segments = parseWeekSegments(timeString)
            for (startW, endW) in segments {
                // 共享 helper: 端点相等时 end 抬回 start, 不产出 (7,6) 倒挂区间
                let (sw, ew) = JwParity.adjustedRange(startW, endW, parity: typeInt)
                out.append(JwCourse(
                    name: name, room: location, teacher: teacher,
                    day: xqj, startNode: djj, endNode: djj + skcd - 1,
                    startWeek: sw, endWeek: ew, type: typeInt))
            }
        }
        return out
    }

    /// 解析周次串: "1-16周"/"2,4,6,8,10,12,14,16周"/"1-8周,10-16周"。
    /// 端点已定型不动调整(单/双修正交 generateCourseList)。
    func parseWeekSegments(_ s: String) -> [(Int, Int)] {
        if s.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        let clean = s
            .replacingOccurrences(of: "周", with: "")
            .replacingOccurrences(of: "(单)", with: "")
            .replacingOccurrences(of: "(双)", with: "")
            .trimmingCharacters(in: .whitespaces)
        var out: [(Int, Int)] = []
        for seg in clean.split(whereSeparator: { $0 == "," || $0 == "，" })
            .map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }) {
            if seg.contains("-") {
                let parts = seg.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard let a = Int(parts[0]) else { continue }
                let b = parts.count > 1 ? (Int(parts[1]) ?? a) : a
                out.append((a, b))
            } else if let v = Int(seg) {
                out.append((v, v))
            }
        }
        return out
    }

    var confidenceValue: Int {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let root = jwParseJSONLenient(source) as? [String: Any] else { return 0 }
        return root["kbList"] is [Any] ? 90 : 0
    }

    var matchedFeatureList: [String] {
        guard let root = jwParseJSONLenient(source) as? [String: Any],
              root["kbList"] is [Any] else { return [] }
        return ["kbList"]
    }
}

// MARK: - 中国科学技术大学(自研新版, jw.ustc.edu.cn)
//
// JSON 路径: x.studentTableVm.activities[]。weeksStr 一次性给完整周次串:
// "1-16"/"1-16单"/"1-16双"/"2,4,6..."。lessonCode 4 位数字, 1-2 位=startNode, 3-4 位=endNode;
// 缺失/不合式时按 startDate/endDate (HH:mm) 时间推断节次兜底, 不整行丢弃。
final class JwUstcParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() throws -> [JwCourse] {
        // 对齐 Kotlin Json { ignoreUnknownKeys = true; isLenient = true }
        guard let root = jwParseJSONLenient(source) as? [String: Any],
              let tableVm = jsonObj(root["studentTableVm"]),
              let activities = jsonArr(tableVm["activities"]) else { return [] }
        var out: [JwCourse] = []
        for el in activities {
            guard let obj = jsonObj(el) else { continue }
            let name = jstr(obj, "courseName")
            if name.isEmpty { continue }
            let room = fallbackRoom(obj)
            let teacher = joinTeachers(obj)
            // lessonCode 4 位定宽是自创解读 (上游 json_version.py 只把它拼进
            // description, 节次实际由 startDate/endDate 时间表达); 不合式时用
            // startDate/endDate 推断兜底, 不整行丢弃。(同 Android v1.0.61)
            let fromCode = parseLessonCode(obj)
            let startNode: Int, endNode: Int
            if fromCode.start > 0 {
                (startNode, endNode) = fromCode
            } else if let inferred = inferNodesFromTime(jstr(obj, "startDate"), jstr(obj, "endDate")) {
                (startNode, endNode) = inferred
            } else {
                continue
            }
            guard let weekday = jint(obj, "weekday") else { continue }
            let weeksStr = jstr(obj, "weeksStr")
            if weeksStr.isEmpty { continue }
            let (typeInt, cleanStr) = parseWeeksType(weeksStr)
            for (sw0, ew0) in parseWeekSegments(cleanStr) {
                // 共享 helper: 端点相等时 end 抬回 start, 不产出 (7,6) 倒挂区间
                let (sw, ew) = JwParity.adjustedRange(sw0, ew0, parity: typeInt)
                out.append(JwCourse(
                    name: name, room: room, teacher: teacher,
                    day: weekday, startNode: startNode, endNode: endNode,
                    startWeek: sw, endWeek: ew, type: typeInt))
            }
        }
        return out
    }

    /// weeksStr → (type, cleanStr): type 0=每周 1=单 2=双, cleanStr 已剥"单/双"后缀。
    func parseWeeksType(_ s: String) -> (Int, String) {
        if s.contains("单") { return (1, s.replacingOccurrences(of: "单", with: "").trimmingCharacters(in: .whitespaces)) }
        if s.contains("双") { return (2, s.replacingOccurrences(of: "双", with: "").trimmingCharacters(in: .whitespaces)) }
        return (0, s.trimmingCharacters(in: .whitespaces))
    }

    /// 解析 "1-16"/"2,4,6,8" 形式的周次串(已剥"单/双")。
    func parseWeekSegments(_ s: String) -> [(Int, Int)] {
        if s.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        var out: [(Int, Int)] = []
        for seg in s.split(whereSeparator: { $0 == "," || $0 == "，" })
            .map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }) {
            if seg.contains("-") {
                let parts = seg.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard let a = Int(parts[0]) else { continue }
                let b = parts.count > 1 ? (Int(parts[1]) ?? a) : a
                out.append((a, b))
            } else if let v = Int(seg) {
                out.append((v, v))
            }
        }
        return out
    }

    /// room 优先; room 为空/缺失时回退 customPlace; 两者皆空则空串。
    private func fallbackRoom(_ o: [String: Any]) -> String {
        let room = jstr(o, "room")
        if !room.isEmpty { return room }
        return jstr(o, "customPlace")
    }

    private func joinTeachers(_ o: [String: Any]) -> String {
        guard let arr = jsonArr(o["teachers"]) else { return jstr(o, "teachers") }
        let names = arr.compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return names.joined(separator: " ")
    }

    private func parseLessonCode(_ o: [String: Any]) -> (start: Int, end: Int) {
        let s = jstr(o, "lessonCode")
        guard s.count >= 4, s.allSatisfy({ $0.isNumber }) else { return (0, 0) }
        // 忠实 Kotlin substring(0,2)/substring(2,4): 固定取第 3-4 位, 非尾 2 位
        let chars = Array(s)
        let start = Int(String(chars[0...1])) ?? 0
        let end = Int(String(chars[2...3])) ?? start
        return (start, end)
    }

    /// lessonCode 缺失/不合式时的节次推断兜底: startDate/endDate (HH:mm) 按
    /// 标准 985 节次布局映射 (同 JwEams5Parser 段起点表, ±10 分钟吸附)。
    /// 推断不出返回 nil (调用方跳过该行)。
    private func inferNodesFromTime(_ startDate: String, _ endDate: String) -> (start: Int, end: Int)? {
        func parseHHmm(_ s: String) -> Int? {
            let parts = s.split(separator: ":")
            guard let h = parts.first.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }),
                  parts.count > 1,
                  let m = Int(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
            guard (0...23).contains(h), (0...59).contains(m) else { return nil }
            return h * 60 + m
        }
        guard let startMins = parseHHmm(startDate), let endMins = parseHHmm(endDate) else { return nil }
        let slots: [(Int, Int)] = [
            (8 * 60, 1),          // 08:00 → node 1
            (10 * 60 + 10, 3),    // 10:10 → node 3
            (14 * 60, 5),         // 14:00 → node 5
            (16 * 60 + 10, 7),    // 16:10 → node 7
            (19 * 60, 9),         // 19:00 → node 9
        ]
        func nodeOf(_ mins: Int) -> Int? {
            for (slotMins, node) in slots where abs(mins - slotMins) <= 10 { return node }
            return nil
        }
        guard let startNode = nodeOf(startMins) else { return nil }
        let endNode = max(nodeOf(endMins) ?? (startNode + 1), startNode)
        return (startNode, endNode)
    }

    var confidenceValue: Int {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let root = jwParseJSONLenient(source) as? [String: Any] else { return 0 }
        return jsonObj(root["studentTableVm"]) != nil ? 90 : 0
    }

    var matchedFeatureList: [String] {
        guard let root = jwParseJSONLenient(source) as? [String: Any],
              jsonObj(root["studentTableVm"]) != nil else { return [] }
        return ["studentTableVm"]
    }
}

// MARK: - 四川大学(scu.edu.cn 自建门户 mobile JSON)
//
// JSON 路径: x.dateList[0].selectCourseList[].timeAndPlaceList[]。
// weekDescription 真实含单/双标记 ("3-9周单"/"1-16周（双）") — 保留 type=1/2,
// 剥限定词后按 [^\d\-,] 展开(上游 replaceAll 语义), 单周(1)起点须奇数/双周(2)
// 起点须偶数 (端点同 ZJU 修正, 只抬 start 不抬 end)。classDay 0-6 → day 1-7。
final class JwScuParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() throws -> [JwCourse] {
        // 对齐 Kotlin Json { ignoreUnknownKeys = true; isLenient = true }
        guard let root = jwParseJSONLenient(source) as? [String: Any],
              let dateList = jsonArr(root["dateList"]),
              let first = dateList.first as? [String: Any],
              let selectCourseList = jsonArr(first["selectCourseList"]) else { return [] }
        var out: [JwCourse] = []
        for el in selectCourseList {
            guard let course = jsonObj(el) else { continue }
            let name = jstr(course, "courseName")
            if name.isEmpty { continue }
            let teacher = jstr(course, "attendClassTeacher")
            guard let timeAndPlaceList = jsonArr(course["timeAndPlaceList"]) else { continue }
            for tpEl in timeAndPlaceList {
                guard let tp = jsonObj(tpEl) else { continue }
                let building = jstr(tp, "teachingBuildingName")
                let classroom = jstr(tp, "classroomName")
                let room = building + classroom
                let weekDesc = jstr(tp, "weekDescription")
                guard let startNode = jint(tp, "classSessions") else { continue }
                let continuing = jint(tp, "continuingSession") ?? 1
                let endNode = startNode + continuing - 1
                guard let rawDay = jint(tp, "classDay") else { continue }
                let day = rawDay + 1  // 0-indexed Mon..Sun → 1..7
                let (parity, cleanedWeeks) = extractParity(weekDesc)
                for (sw0, ew) in parseWeeks(cleanedWeeks) {
                    // Sleepy 语义保留 range: "1-16周" → startWeek=1, endWeek=16 (1 entry);
                    // 离散周 "2,4,6,8" → 4 entries (每个 sw=ew=week 单周范围)。
                    // 单周(1)起点须奇数/双周(2)起点须偶数, 端点同 ZJU 修正
                    let adjustedStart: Int
                    switch parity {
                    case 1: adjustedStart = sw0 % 2 == 0 ? sw0 + 1 : sw0
                    case 2: adjustedStart = sw0 % 2 != 0 ? sw0 + 1 : sw0
                    default: adjustedStart = sw0
                    }
                    out.append(JwCourse(
                        name: name, room: room, teacher: teacher,
                        day: day, startNode: startNode, endNode: endNode,
                        startWeek: adjustedStart, endWeek: ew, type: parity))
                }
            }
        }
        return out
    }

    /// 提取单/双周限定并剥净: 返回 (parity, 已剥限定词与括号的串)。
    /// parity: 0=每周 1=单周 2=双周。真实形态 "3-9周单" / "1-16周（双）" /
    /// "1-15周(单)" — ASCII/全角括号与"(单)/(双)"限定词剥除, 裸"单/双"字交
    /// parseWeeks 的 [^\d\-,] 过滤兜底 (同 Android extractParity)。
    func extractParity(_ s: String) -> (Int, String) {
        let parity: Int
        if s.contains("单") { parity = 1 }
        else if s.contains("双") { parity = 2 }
        else { parity = 0 }
        let clean = s
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "(单)", with: "")
            .replacingOccurrences(of: "(双)", with: "")
        return (parity, clean)
    }

    /// 解析 weekDescription (已剥单/双限定) — "1-16周"/"2,4,6,8"/"1-15周(单)"。
    /// 严格按上游 replaceAll("[^\\d\\-,]", "") 剥后展开。
    func parseWeeks(_ s: String) -> [(Int, Int)] {
        if s.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        let clean = String(s.unicodeScalars.filter { CharacterSet(charactersIn: "0123456789-,").contains($0) })
        if clean.isEmpty { return [] }
        var out: [(Int, Int)] = []
        for seg in clean.components(separatedBy: ",").map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }) {
            if seg.contains("-") {
                let parts = seg.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard let a = Int(parts[0]) else { continue }
                let b = parts.count > 1 ? (Int(parts[1]) ?? a) : a
                out.append((a, b))
            } else if let v = Int(seg) {
                out.append((v, v))
            }
        }
        return out
    }

    var confidenceValue: Int {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let root = jwParseJSONLenient(source) as? [String: Any],
              let dl = jsonArr(root["dateList"]), !dl.isEmpty,
              let first = dl.first as? [String: Any],
              first["selectCourseList"] is [Any] else { return 0 }
        return 90
    }

    var matchedFeatureList: [String] {
        guard let root = jwParseJSONLenient(source) as? [String: Any],
              let dl = jsonArr(root["dateList"]), !dl.isEmpty,
              let first = dl.first as? [String: Any],
              first["selectCourseList"] is [Any] else { return [] }
        return ["selectCourseList"]
    }
}
