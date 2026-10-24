// JwOldZfParser.swift — ← JwOldZfParser.kt
//
// 正方教务（老版）课表解析器 — issue #5。
//
// 适配 zf / zf_1 协议学校（default2.aspx 时代，个人课表页 xskbcx.aspx）。
// 移植上游 dIT8Zv/WakeupSchedule_BUPT (Apache-2.0) ZhengFangParser.kt：
//   https://github.com/dIT8Zv/WakeupSchedule_BUPT/blob/master/app/src/main/java/com/suda/yzune/wakeupschedule/schedule_import/parser/ZhengFangParser.kt
//
// 页面结构：
//   - 外层表格 id="Table1"（部分学校 class="blacktab" 或无标识，由兜底链处理 — T1 G5）
//   - 节次行头："第N节"（数字或中文数字一~二十）；合并行头 "第N-M节" / "第N,M节" /
//     "第一节-第二节" 按首段 N 解析（T1 G6，有意偏离上游 — 上游返回 -1 导致整行错位）
//   - 课程单元格（<a> 内 <br> 分隔）：
//       课程名<br>[属性词]<br>{第N-M周}[|单周|双周]<br>[老师<br>]教室
//   - 同格多门课用 <br><br>（type=0）或 <br><br><br>（type=0 异常变体）分隔
//
// type 参数对应上游 zfType：0 = 通用变体，1 = zf_1 变体（单元格无 <a> 链接，
// 内容以空格分隔且周次带花括号）。
//
// T1 有意偏离上游的修复（上游同病）：
//   G1  parseTime 的 (N-M节) 写回 startNode（上游本就写回，sleepy 移植时丢成死代码）
//   G2  COURSE_PROPERTY 对齐上游 47 项（sleepy 原缺 23 项）
//   G3  parseImportBean1 的 hasTypeFlag 每门课后复位（上游永不复位）
//   G4  parseImportBean1 时间 token 为末尾 token 时不再 split[preIndex+1] 越界
//   G5  表格选择器兜底 blacktab / 含"星期一"的第一个 table
//   G6  合并节次行头按首段解析（上游返回 -1）
//   G7  "周天"→7 别名（sleepy 扩展，上游仅"周日"）
//   G8  OTHER_HEADER 补"中午"（sleepy 扩展，上游无）
//   G12 parseTime 补 result[1]=step（上游 L214, sleepy 移植漏行 — 缺此行 endNode 恒 startNode-1）

import Foundation
import SwiftSoup

final class JwOldZfParser: JwParser, JwParserConfidenceReporting {

    let source: String
    /// 0 = 通用变体, 1 = zf_1 变体 ← internal val type
    let oldType: Int

    init(_ source: String, oldType: Int = 0) {
        self.source = source
        self.oldType = oldType
    }

    private struct ImportBean {
        var name: String
        var timeInfo: String
        var teacher: String?
        var room: String?
        var startNode: Int
        let cDay: Int
    }

    func generateCourseList() throws -> [JwCourse] {
        let doc = try SwiftSoup.parse(source)
        // T1 G5: #Table1 → table.blacktab → 文本含"星期一"的第一个 table
        let table1 = (try? doc.getElementById("Table1")) ?? nil
            ?? ((try? doc.select("table.blacktab").first()) ?? nil)
            ?? pickTableByMonday(doc)
        guard let table = table1 else { return [] }
        let trs = (try? table.getElementsByTag("tr")) ?? Elements()
        var importBeanList: [ImportBean] = []
        var node = -1
        for tr in trs {
            let tds = (try? tr.getElementsByTag("td")) ?? Elements()
            var countFlag = false
            var countDay = 0
            for td in tds {
                let courseSource = ((try? td.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if courseSource.count <= 1 {
                    if countFlag {
                        countDay += 1
                    }
                    continue
                }
                if Self.OTHER_HEADER.contains(courseSource) {
                    // 表头行（"时间" "星期一" "中午" 等组头）
                    continue
                }
                let result = Self.parseHeaderNodeString(courseSource)
                if result != -1 {
                    // T1 G6: 合并行头"第N-M节"也在此返回首段 N, 不落入下方 countDay++
                    node = result
                    countFlag = true
                    continue
                }
                countDay += 1
                switch oldType {
                case 0:
                    importBeanList.append(contentsOf: parseImportBean(countDay, (try? td.html()) ?? "", node))
                default:
                    importBeanList.append(contentsOf: parseImportBean1(countDay, courseSource, node))
                }
            }
        }
        return importList2CourseList(importBeanList, source)
    }

    /// type=0：标准老正方单元格，<a>课程名<br>周次<br>[老师<br>教室] </a>，多门课 <br><br> 分隔（未改动）
    private func parseImportBean(_ cDay: Int, _ html: String, _ node: Int) -> [ImportBean] {
        var courses: [ImportBean] = []
        var isAbnormal = false
        // ← Kotlin substringBeforeLast("</td>"): 最后个 "</td>" 前的部分; 无则原串
        let inner: String
        if let r = html.range(of: "</td>", options: .backwards)?.lowerBound {
            inner = String(html[html.startIndex..<r])
        } else {
            inner = html
        }
        let courseSplits: [String]
        if inner.contains("<br><br><br>") {
            isAbnormal = true
            courseSplits = inner.components(separatedBy: "<br><br><br>")
        } else {
            courseSplits = inner.components(separatedBy: "<br><br>")
        }
        for courseStr in courseSplits {
            // ← substringAfter("\">"): 首个 "\">" 后的部分; 无则原串。
            //   再 substringBeforeLast("</a>"): 末个 "</a>" 前的部分; 无则原串。
            let mid: String
            if let r = courseStr.range(of: "\">") {
                mid = String(courseStr[r.upperBound...])
            } else {
                mid = courseStr
            }
            let beforeCloseA: String
            if let r = mid.range(of: "</a>", options: .backwards) {
                beforeCloseA = String(mid[mid.startIndex..<r.lowerBound])
            } else {
                beforeCloseA = mid
            }
            let split = beforeCloseA.components(separatedBy: "<br>")
                .map { Self.stripAnchorTag($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if split.isEmpty || split.count < 3 { continue }
            var temp: ImportBean
            if Self.COURSE_PROPERTY.contains(split[1]) {
                if split.count == 4 {
                    temp = ImportBean(name: split[0], timeInfo: split[2], teacher: "", room: split[3], startNode: node, cDay: cDay)
                } else {
                    temp = ImportBean(name: split[0], timeInfo: split[2], teacher: split[3], room: split[4], startNode: node, cDay: cDay)
                }
            } else {
                if split.count == 3 {
                    if !isAbnormal {
                        temp = ImportBean(name: split[0], timeInfo: split[1], teacher: "", room: split[2], startNode: node, cDay: cDay)
                    } else {
                        temp = ImportBean(name: split[0], timeInfo: split[1], teacher: split[2], room: "", startNode: node, cDay: cDay)
                    }
                } else {
                    temp = ImportBean(name: split[0], timeInfo: split[1], teacher: split[2], room: split[3], startNode: node, cDay: cDay)
                }
            }
            courses.append(temp)
        }
        return courses
    }

    /// type=1（zf_1）：单元格无 <a>，以空格分隔，周次带花括号。
    /// T1 修复: G3 hasTypeFlag 每门课后复位 / G4 末尾 token 越界守卫 / DEF-1 preIndex==0 守卫。
    private func parseImportBean1(_ cDay: Int, _ source: String, _ node: Int) -> [ImportBean] {
        var courses: [ImportBean] = []
        // ← Kotlin source.split(" ".toRegex()).dropLastWhile { it.isEmpty() }:
        //   保留连续/前导空格产生的空 token(下标语义依赖它们); courseSource 已 trim,
        //   天然无尾部空 token, 与 dropLastWhile 等价。Swift split 默认丢空子串, 不可用。
        let split = source.components(separatedBy: " ")
        var preIndex = -1
        var hasTypeFlag = false
        for i in split.indices {
            if split[i].contains("{") && split[i].contains("}") {
                if preIndex != -1 {
                    if preIndex < 1 {
                        // DEF-1: brace token 在 split[0] 时 split[preIndex-1] 越界, 该段无课程名, 跳过
                        preIndex = i
                        continue
                    }
                    if Self.COURSE_PROPERTY.contains(split[preIndex - 1]) {
                        hasTypeFlag = true
                    }
                    var temp = ImportBean(name: (hasTypeFlag && preIndex >= 2) ? split[preIndex - 2] : split[preIndex - 1],
                        timeInfo: split[preIndex], teacher: "", room: "", startNode: node, cDay: cDay)
                    // T1 G4: 边界守卫 — 时间 token 后无足够 token 时 teacher/room 留空, 不越界
                    if (i - preIndex - 2) == 1 {
                        if preIndex + 1 < split.count { temp.teacher = split[preIndex + 1] }
                    } else {
                        if preIndex + 1 < split.count { temp.teacher = split[preIndex + 1] }
                        if preIndex + 2 < split.count { temp.room = split[preIndex + 2] }
                    }
                    courses.append(temp)
                    // T1 G3: 每门课构造完成后立即复位, 否则同格下一门无属性行的课名错取前前 token
                    hasTypeFlag = false
                    preIndex = i
                } else {
                    preIndex = i
                }
            }
            if i == split.count - 1 {
                if preIndex < 1 { continue }
                if Self.COURSE_PROPERTY.contains(split[preIndex - 1]) {
                    hasTypeFlag = true
                }
                var temp = ImportBean(name: (hasTypeFlag && preIndex >= 2) ? split[preIndex - 2] : split[preIndex - 1],
                        timeInfo: split[preIndex], teacher: "", room: "", startNode: node, cDay: cDay)
                // T1 G4: 末尾分支同款守卫 (原代码在时间 token 为最后一个 token 时
                // (i-preIndex)==0 走 else 取 split[preIndex+1] → IndexOutOfBoundsException)
                if (i - preIndex) == 1 {
                    if preIndex + 1 < split.count { temp.teacher = split[preIndex + 1] }
                } else {
                    if preIndex + 1 < split.count { temp.teacher = split[preIndex + 1] }
                    if preIndex + 2 < split.count { temp.room = split[preIndex + 2] }
                }
                courses.append(temp)
                hasTypeFlag = false
            }
        }
        return courses
    }

    private func importList2CourseList(_ importList: [ImportBean], _ source: String) -> [JwCourse] {
        var result: [JwCourse] = []
        for i in importList {
            var bean = i
            let time = parseTime(&bean, i.timeInfo, source)
            // 周次串里带"周X"时以串为准，否则用网格列号（"周天"经 WEEK_ALIAS 归 7）
            let day: Int
            if i.timeInfo.count >= 2 && Self.getWeekFromChinese(String(i.timeInfo.prefix(2))) > 0 {
                day = time[0]
            } else {
                day = i.cDay
            }
            // T1 G1: 与 Kotlin 一致读 parseTime 写回后的 startNode（Kotlin 收引用可直接读 i,
            // Swift 结构体是值拷贝, 必须读被 parseTime 改过的 bean, 否则写回丢失）
            result.append(JwCourse(
                name: i.name, room: i.room ?? "", teacher: i.teacher ?? "",
                day: day, startNode: bean.startNode,
                endNode: bean.startNode + time[1] - 1,
                startWeek: time[2],
                endWeek: time[3],
                type: time[4]))
        }
        return result
    }

    /// 返回 [day, step, startWeek, endWeek, type]。
    /// T1 G1: 签名改为收 ImportBean 实例（上游 ZhengFangParser.parseTime 同样收 importBean），
    /// 使 (N-M节) 分支能写回 bean.startNode。
    private func parseTime(_ bean: inout ImportBean, _ time: String, _ source: String) -> [Int] {
        var result = [Int](repeating: 0, count: 5)
        // day: 周次串以"周X"开头时从串里取（G7: "周天"→7 走 WEEK_ALIAS）
        if time.hasPrefix("周") {
            let idx = Self.getWeekFromChinese(String(time.prefix(2)))
            if idx > 0 { result[0] = idx }
        }
        if result[0] == 0 {
            // 从源码里数课程名之前出现了多少次行标记（"Center" 是老正方 td 对齐样式）
            var startIndex = source.range(of: ">第\(bean.startNode)节</td>")?.lowerBound
            if startIndex == nil {
                startIndex = source.range(of: ">第\(Self.getNodeStr(bean.startNode))节</td>")?.lowerBound
            }
            var endIndex: String.Index? = nil
            if let si = startIndex {
                endIndex = source.range(of: bean.name, range: si..<source.endIndex)?.lowerBound
            }
            if let si = startIndex, let ei = endIndex {
                result[0] = Self.countStr(String(source[si..<ei]), "Center")
            }
        }

        // step（连上节数）
        var step = 0
        if time.contains("节/") {
            if let numLocate = time.range(of: "节/") {
                // Kotlin substring(numLocate-1, numLocate): "节/" 前一个字符
                let beforeIdx = time.index(before: numLocate.lowerBound)
                step = Int(String(time[beforeIdx])) ?? 0
            }
        } else if time.contains(",") {
            var locate = time.startIndex
            step = 1
            while let r = time.range(of: ",", range: locate..<time.endIndex) {
                step += 1
                locate = r.upperBound
            }
        } else if time.contains("第\(bean.startNode)节") {
            step = 1
        }
        if step == 0 {
            if let matchResult = time.range(of: Self.NODE_PATTERN, options: .regularExpression) {
                let nodeInfo = String(time[matchResult])
                // 去 "(" 与 "节"
                let inner = String(nodeInfo.dropFirst().dropLast())
                let nodes = inner.components(separatedBy: "-")
                if !nodes.isEmpty {
                    // T1 G1: 真正写回（上游 Common/ZhengFangParser 语义; 原为空 let 死代码）
                    bean.startNode = Int(nodes[0].trimmingCharacters(in: .whitespaces)) ?? bean.startNode
                }
                if nodes.count > 1 {
                    let s = Int(nodes[0].trimmingCharacters(in: .whitespaces)) ?? bean.startNode
                    let e = Int(nodes[1].trimmingCharacters(in: .whitespaces)) ?? s
                    step = e - s + 1
                }
            }
        }
        if step == 0 { step = 1 }
        // T1 G12: 补移植漏行(上游 L214 result[1] = step) — 缺此行 endNode 恒 = startNode-1
        result[1] = step

        // 周数 {第N-M周
        var startWeek = 1
        var endWeek = 20
        if let weekResult = time.range(of: Self.WEEK_PATTERN, options: .regularExpression) {
            let weekInfo = String(time[weekResult])
            // Kotlin "{第N-M周".substring(2, len-1): 剥前 2 字符与末 1 字符
            let chars = Array(weekInfo)
            let inner = chars.count >= 3 ? String(chars[2..<(chars.count - 1)]) : ""
            let weeks = inner.components(separatedBy: "-")
            if !weeks.isEmpty, let v = Int(weeks[0].trimmingCharacters(in: .whitespaces)) {
                startWeek = v
                result[2] = v
            }
            if weeks.count > 1, let v = Int(weeks[1].trimmingCharacters(in: .whitespaces)) {
                endWeek = v
                result[3] = v
            }
        } else {
            // 无花括号周次时按整学期处理（与上游默认一致; sleepy 显式回填保留）
            result[2] = startWeek
            result[3] = endWeek
        }

        // 单双周
        if time.contains("单周") {
            result[4] = 1
        } else if time.contains("双周") {
            result[4] = 2
        }

        return result
    }

    // MARK: - companion object ← static

    /// 正则与上游 Common.kt 逐字符一致, 勿改
    private static let NODE_PATTERN = #"\(\d{1,2}[-]*\d*节"#
    private static let WEEK_PATTERN = #"\{第\d{1,2}[-]*\d*周"#
    private static let HEADER_NODE_PATTERN = #"第.*节"#

    /// 表头词（与上游 Common.otherHeader 一致 + T1 G8 追加"中午", 后者为 sleepy 扩展非上游原文）
    private static let OTHER_HEADER: Set<String> = [
        "时间", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日",
        "早晨", "上午", "下午", "晚上", "中午",
    ]

    /// 课程属性词（上游 Common.courseProperty 47 项全量; T1 G2 补齐后 24→47）。
    /// 前 24 项为 sleepy 原有(恰为上游前 24 项, 顺序一致), 后 23 项按上游顺序追加。
    private static let COURSE_PROPERTY: Set<String> = [
        "任选", "限选", "实践选修", "必修课", "选修课", "必修", "选修", "专基", "专选",
        "公必", "公选", "义修", "选", "必", "主干", "专限", "公基", "值班", "通选",
        "思政必", "思政选", "自基必", "自基选", "语技必",
        "语技选", "体育必", "体育选", "专业基础课", "双创必", "双创选",
        "新生必", "新生选", "学科必修", "学科选修",
        "通识必修", "通识选修", "公共基础", "第二课堂",
        "学科实践", "专业实践", "专业必修", "辅修", "专业选修",
        "外语", "方向", "专业必修课", "全选",
    ]

    /// 与上游 Common.chineseWeekList 一致(8 元素)。T1 G7: "周天"别名放 WEEK_ALIAS, 勿追加进数组(下标会变 8)
    private static let CHINESE_WEEK_LIST = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    /// T1 G7: 部分学校打印"周天", 归一为 7
    private static let WEEK_ALIAS = ["周天": 7]

    /// 上游 Common.getWeekFromChinese 语义 + WEEK_ALIAS 兜底; 返回 0 = 非"周X"词
    private static func getWeekFromChinese(_ chineseWeek: String) -> Int {
        if let idx = CHINESE_WEEK_LIST.firstIndex(of: chineseWeek), idx > 0 { return idx }
        return WEEK_ALIAS[chineseWeek] ?? 0
    }

    private static let CN_NUM = [
        "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7,
        "七": 7, "八": 8, "九": 9, "十": 10, "十一": 11, "十二": 12,
        "十三": 13, "十四": 14, "十五": 15, "十六": 16, "十七": 17,
        "十八": 18, "十九": 19, "二十": 20,
    ]

    /// "第N节" 行头 → N；不是行头返回 -1。
    /// T1 G6（有意偏离上游）: 区间/逗号行头按首段解析 —
    ///   "第3-4节"→3  "第1,2节"→1  "第一节-第二节"→1(剥首尾后是"一节-第二", 首段再剥 第/节)
    /// 上游 Common.parseHeaderNodeString 对以上均返回 -1。
    static func parseHeaderNodeString(_ str: String) -> Int {
        guard str.range(of: "^\(HEADER_NODE_PATTERN)$", options: .regularExpression) != nil else { return -1 }
        let raw = String(str.dropFirst().dropLast())
        // ← Kotlin raw.split('-', '—', '~', ',').firstOrNull(): 保留首段为空的空 token
        //   (如 "第-4节" → 首段 ""→ -1); Swift split 会丢掉空段导致取到后段, 用 components。
        let firstSegRaw = raw
            .components(separatedBy: CharacterSet(charactersIn: "-—~,"))[0]
            .trimmingCharacters(in: .whitespaces)
        var seg = firstSegRaw
        if seg.hasPrefix("第") { seg.removeFirst() }
        if seg.hasSuffix("节") { seg.removeLast() }
        seg = seg.trimmingCharacters(in: .whitespaces)
        if seg.isEmpty { return -1 }
        return Int(seg) ?? CN_NUM[seg] ?? -1
    }

    /// T1 G5: 兜底 — 遍历所有 table 取文本含"星期一"的第一个（Speas-y/ClassScheduleApp 同策略）
    private func pickTableByMonday(_ doc: Document) -> Element? {
        guard let tables = try? doc.select("table") else { return nil }
        for t in tables {
            if let text = try? t.text(), text.contains("星期一") { return t }
        }
        return nil
    }

    static func getNodeStr(_ node: Int) -> String {
        switch node {
        case 1: return "一"; case 2: return "二"; case 3: return "三"; case 4: return "四"
        case 5: return "五"; case 6: return "六"; case 7: return "七"; case 8: return "八"
        case 9: return "九"; case 10: return "十"; case 11: return "十一"; case 12: return "十二"
        case 13: return "十三"; case 14: return "十四"; case 15: return "十五"; case 16: return "十六"
        default: return ""
        }
    }

    static func countStr(_ str1: String, _ str2: String) -> Int {
        var times = 0
        var startIndex = 0
        var findIndex: Int?
        // String.Index 不可做整数运算, 先转 NSString 视角
        let ns = str1 as NSString
        findIndex = ns.range(of: str2).location == NSNotFound ? nil : ns.range(of: str2).location
        while let fi = findIndex, fi != str1.count - 1 {
            times += 1
            startIndex = fi + 1
            let r = ns.range(of: str2, options: [], range: NSRange(location: startIndex, length: max(0, ns.length - startIndex)))
            findIndex = r.location == NSNotFound ? nil : r.location
        }
        if findIndex == str1.count - 1 {
            times += 1
        }
        return times
    }

    /// 剥掉残留的 <a> / <a href=...> 前缀（部分页面课程单元无 href 属性）
    static func stripAnchorTag(_ s: String) -> String {
        var t = s
        if t.hasPrefix("<a") {
            if let gt = t.firstIndex(of: ">") {
                t = String(t[t.index(after: gt)...])
            } else {
                t = String(t.dropFirst(2))
            }
        }
        return t
    }

    /// T8: #Table1 + 花括号周次 = 100; blacktab = 90; 仅 Table1 = 70
    var confidenceValue: Int {
        guard let doc = try? SwiftSoup.parse(source) else { return 0 }
        let table1 = (try? doc.getElementById("Table1")) ?? nil
        let blacktab = ((try? doc.select("table.blacktab").first()) ?? nil) != nil
        let hasWeek = source.range(of: Self.WEEK_PATTERN, options: .regularExpression) != nil
        if (table1 != nil || blacktab) && hasWeek { return 100 }
        if blacktab { return 90 }
        if table1 != nil { return 70 }
        return 0
    }

    var matchedFeatureList: [String] {
        guard let doc = try? SwiftSoup.parse(source) else { return [] }
        var out: [String] = []
        if ((try? doc.getElementById("Table1")) ?? nil) != nil { out.append("id=Table1") }
        if ((try? doc.select("table.blacktab").first()) ?? nil) != nil { out.append("class=blacktab") }
        if source.contains("<a") { out.append("<a>课程链接") }
        if source.range(of: Self.WEEK_PATTERN, options: .regularExpression) != nil { out.append("{第N-M周}") }
        return out
    }
}
