import Foundation
import SwiftSoup

final class JwUndergradBHtmlParser: JwParser {
    let source: String
    let protocolType: String
    init(_ source: String, protocolType: String) { self.source = source; self.protocolType = protocolType }
    private lazy var doc: Document? = {
        let document = try? SwiftSoup.parse(source)
        _ = document?.outputSettings().prettyPrint(pretty: false)
        return document
    }()
    func generateCourseList() -> [JwCourse] {
        let rows: [JwCourse]
        switch protocolType {
        case "huat": rows = huat()
        case "seu_2017": rows = seu2017()
        case "shu2024": rows = shu2024()
        case "tju": rows = tju()
        case "hqu": rows = hqu()
        case "changzhou": rows = changzhou()
        default: rows = []
        }
        return rows.filter(Self.valid)
    }
    static func range(_ raw: String) -> (Int, Int)? {
        guard let m = jw1064Matches(#"^([0-9]+)(?:\s*[-~]\s*([0-9]+))?$"#, raw.trimmingCharacters(in: .whitespacesAndNewlines)).first,
              let a = jw1064Integer(m[1]), let b = jw1064Integer(m[2].isEmpty ? m[1] : m[2]), a > 0, b >= a else { return nil }
        return (a,b)
    }
    static func weeks(_ raw: String) -> [(Int,Int,Int)] {
        let pieces = jw1064Split(#"[,，、\\/ ]+"#, raw.trimmingCharacters(in: .whitespacesAndNewlines))
        var out: [(Int,Int,Int)] = []
        for piece in pieces {
            guard let m = jw1064Matches(#"^(?:第)?([0-9]+(?:[-~][0-9]+)?)(?:周)?(?:[（(]?([单双])[)）]?(?:周)?)?$"#,piece.trimmingCharacters(in: .whitespacesAndNewlines)).first,
                  let r = range(m[1]) else { return [] }
            out.append((r.0,r.1,jw1064Parity(m[2])))
        }
        return out
    }
    static func endNode(_ start: Int, _ length: Int) -> Int? {
        guard start > 0, length > 0, start <= Int(Int32.max), length <= Int(Int32.max), start + length - 1 <= Int(Int32.max) else { return nil }; return start + length - 1
    }
    static func mergeRanges(_ ranges: [(Int,Int)]) -> [(Int,Int)] {
        var out: [(Int,Int)] = []
        for value in ranges.sorted(by: { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }) {
            if let last = out.last, value.0 <= last.1 + 1 { out[out.count-1] = (last.0,max(last.1,value.1)) } else { out.append(value) }
        }
        return out
    }
    static func valid(_ c: JwCourse) -> Bool { !c.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (1...7).contains(c.day) && c.startNode > 0 && c.endNode >= c.startNode && c.startWeek > 0 && c.endWeek >= c.startWeek && (0...2).contains(c.type) && (c.type == 0 || c.startWeek % 2 == c.type % 2 || c.endWeek > c.startWeek) }
    private func huat() -> [JwCourse] {
        var out: [JwCourse] = []
        for (index,row) in jw1064Elements(try? doc?.getElementById("ctl00_ContentPlaceHolder1_CourseTable"),"[valign=middle]").enumerated() {
            var day = 0
            for cell in row.children().array() {
                if cell.hasAttr("align") { continue }; day += 1
                for body in jw1064Elements(cell,"tbody") {
                    let fields = jw1064Text(body).replacingOccurrences(of: #"([0-9]+)-([0-9]+周[（）全半]*)$"#,with:"$1 - $2",options:.regularExpression).components(separatedBy:" ")
                    guard fields.count >= 5, let first = jw1064Integer(fields[fields.count-3]), let last = jw1064Integer(fields.last!.replacingOccurrences(of:"[周（）全半]",with:"",options:.regularExpression)), let end = Self.endNode(index*2+1,index == 4 ? 3 : 2) else { continue }
                    var teacher = "未知教师", room = "未知教室"
                    if fields.count == 6 { if fields[fields.count-4].contains("H") { teacher = fields[1] } else { room = fields[2] } }
                    else if fields.count == 7 { teacher = fields[1]; room = fields[3] }
                    else if fields.count > 7 {
                        let candidate = fields[fields.count-4], hasRoom = candidate.range(of:#"^[0-9]{4}$"#,options:.regularExpression) != nil
                        if hasRoom { room = candidate }
                        teacher = fields[1..<(fields.count-(hasRoom ? 5 : 4))].joined(separator:" ")
                    }
                    out.append(JwCourse(name:fields[0],room:room,teacher:teacher,day:day,startNode:index*2+1,endNode:end,startWeek:first,endWeek:last))
                }
            }
        }
        return out
    }
    private func seu2017() -> [JwCourse] {
        let tables = jw1064Elements(doc,".tableline"); guard tables.count >= 2 else { return [] }
        var teachers: [String:(String,Float)] = [:], out:[JwCourse] = []
        for row in jw1064Elements(tables[0],"tr").dropFirst() { let c = jw1064Elements(row,"td"); if c.count >= 4 { teachers[jw1064Text(c[1])] = (jw1064Text(c[2]),Float(jw1064Text(c[3])) ?? 0) } }
        let headers:Set<String> = ["时间","星期一","星期二","星期三","星期四","星期五","星期六","星期日","早晨","上午","下午","晚上"]
        for row in jw1064Elements(tables.last,"tr").dropFirst() {
            var day = 0
            for cell in jw1064Elements(row,"td") {
                if headers.contains(jw1064Text(cell)) { continue }
                let fields = jw1064Lines(cell)
                for index in stride(from:0,to:fields.count,by:3) where index+2 < fields.count {
                    guard let m = jw1064Matches(#"^\[([^]]+)周]([^节]+)节$"#,fields[index+1]).first, let nodes = Self.range(m[2]) else { continue }
                    let name = fields[index], metadata = teachers[name] ?? ("",0), room = fields[index+2], parity = room.contains("(单)") ? 1 : room.contains("(双)") ? 2 : 0
                    for (first,last,_) in Self.weeks(m[1]) { out.append(JwCourse(name:name,room:room.replacingOccurrences(of:"(单)",with:"").replacingOccurrences(of:"(双)",with:""),teacher:metadata.0,day:day,startNode:nodes.0,endNode:nodes.1,startWeek:first,endWeek:last,type:parity,credit:metadata.1)) }
                }
                day += 1
            }
        }
        return out
    }
    private func shuCourses(_ name:String,_ teacher:String,_ room:String,_ timing:String,_ credit:Float) -> [JwCourse] {
        var out:[JwCourse] = []
        for part in timing.components(separatedBy:.whitespacesAndNewlines) where !part.isEmpty {
            guard let m = jw1064Matches(#"^([一二三四五六日])([0-9]+)-([0-9]+)([单双]?)(?:\(([^()]*)\))?([单双]?)$"#,part).first,
                  m[4].isEmpty || m[6].isEmpty, let nodes = Self.range(m[2]+"-"+m[3]) else { continue }
            var ranges:[(Int,Int)] = [], invalid = false
            if m[5].trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { ranges = [(1,10)] }
            else { for segment in m[5].components(separatedBy:",") { guard let token = jw1064Matches(#"^(?:第)?([0-9]+(?:[-~][0-9]+)?)(?:周)?$"#,segment).first, let r = Self.range(token[1]) else { invalid = true; break }; ranges.append(r) } }
            if invalid { continue }
            let day = Array("一二三四五六日").firstIndex(of:Character(m[1]))!+1
            for (first,last) in Self.mergeRanges(ranges) { out.append(JwCourse(name:name,room:room,teacher:teacher,day:day,startNode:nodes.0,endNode:nodes.1,startWeek:first,endWeek:last,type:jw1064Parity(m[4]+m[6]),credit:credit)) }
        }
        return out
    }
    private func shu2024() -> [JwCourse] {
        var out:[JwCourse] = []
        for card in jw1064Elements(doc,"div.arranged-content div.el-card.arranged-course-card") {
            var fields:[String:String] = [:]
            for item in jw1064Elements(card,"div.card-item.cv-clearfix") { let key = jw1064Text(item,"div.label.cv-pull-left"); fields[key.hasSuffix(":") ? String(key.dropLast()) : key] = jw1064Text(item,"div.value.cv-pull-left") }
            out += shuCourses(fields["课程名"] ?? "",fields["上课教师"] ?? "",fields["上课地点"] ?? "",fields["上课时间"] ?? "",Float(fields["学分"] ?? "") ?? 0)
        }
        if !out.isEmpty { return out }
        for row in jw1064Elements(doc,"div.arranged-content table.el-table__body tbody tr.el-table__row") { let c = jw1064Elements(row,"td"); if c.count >= 11 { out += shuCourses(jw1064Text(c[1]),jw1064Text(c[5]),jw1064Text(c[7]),jw1064Text(c[6]),Float(jw1064Text(c[3])) ?? 0) } }
        return out
    }
    func tableName() -> String? {
        guard protocolType == "shu2024",
              let title = try? doc?.select("a.gologin-btn span.el-link--inner").first()?.ownText(),
              let m = jw1064Matches(#"(\d{4})-(\d{4})学年(\S+)季学期"#, title).first else { return nil }
        return String(m[1].suffix(2)) + "-" + String(m[2].suffix(2)) + m[3]
    }
    private func tju() -> [JwCourse] {
        guard let header = try? doc?.select(".el-table__header").first() else { return [] }
        let headers = jw1064Elements(header,"th").map { jw1064Text($0) }
        func column(_ label:String)->Int { headers.firstIndex { $0.contains(label) } ?? -1 }
        let nameColumn = column("课程名称"), teacherColumn = column("教师"); guard nameColumn >= 0,teacherColumn >= 0 else { return [] }
        var out:[JwCourse] = []
        for row in jw1064Elements(try? doc?.select(".el-table__body").first(),"tr") {
            let cells = jw1064Elements(row,"td")
            func value(_ index:Int)->String { cells.indices.contains(index) ? jw1064Text(cells[index]) : "" }
            let primary = value(column("上课时间")),timing = primary.isEmpty ? value(column("教学安排")) : primary
            for part in timing.components(separatedBy:",星期") {
                guard let m = jw1064Matches(#"^(?:星期)?([一二三四五六日天])\s+(\d+(?:-\d+)?)节\[([^]]+)](.*)$"#,part.trimmingCharacters(in:.whitespacesAndNewlines)).first,let nodes = Self.range(m[2]) else { continue }
                let day = Array("一二三四五六日").firstIndex(of:Character(m[1].replacingOccurrences(of:"天",with:"日")))!+1
                let teacher = jw1064Split(#"\(.*?\)"#,value(teacherColumn)).filter { !$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }.joined(separator:",")
                for (first,last,parity) in Self.weeks(m[3]) { out.append(JwCourse(name:value(nameColumn),room:column("上课地点") < 0 ? m[4] : value(column("上课地点")),teacher:teacher,day:day,startNode:nodes.0,endNode:nodes.1,startWeek:first,endWeek:last,type:parity,credit:Float(value(column("学分"))) ?? 0,note:value(column("备注")))) }
            }
        }
        return out
    }
    private func hqu() -> [JwCourse] {
        struct Plan:Hashable { let name:String; let teacher:String;let credit:Float }
        let plans:[Plan] = jw1064Elements(try? doc?.getElementById("CoursePlanTable"),"tr").compactMap { row in let c = jw1064Elements(row,"td");return c.count < 3 || jw1064Text(c[0]).isEmpty ? nil : Plan(name:jw1064Text(c[0]),teacher:jw1064Text(c[1]),credit:Float(jw1064Text(c[2])) ?? 0) }
        var out:[JwCourse] = []
        for (day,row) in jw1064Elements(try? doc?.getElementById("ArrangeTable"),"tr").enumerated() where day > 0 {
            for (column,cell) in jw1064Elements(row,"td").enumerated() where column > 0 {
                let parts = jw1064Elements(cell,"div").map { jw1064Text($0) }; guard !parts.isEmpty else { continue }
                let candidates = Array(Set(plans.filter { parts[0].hasSuffix($0.name) })),longest = candidates.map { $0.name.count }.max()
                let selected = candidates.filter { $0.name.count == longest },plan = selected.count == 1 ? selected[0] : nil
                guard let weekIndex = parts.lastIndex(where: { $0.range(of:#"\d+周"#,options:.regularExpression) != nil }),weekIndex >= 1 else { continue }
                var room = parts[weekIndex-1];let start = (column-1)*2+1,length = jw1064Matches(#"\((\d+)节\)"#,room).first
                guard let count = length.flatMap({jw1064Integer($0[1])}) ?? (length == nil ? (start < 11 ? 2 : 3) : nil),let end = Self.endNode(start,count) else { continue }
                if let length { room = room.replacingOccurrences(of:length[0],with:"") }
                let html = (try? cell.html()) ?? "",parity = html.contains("单周") ? 1 : html.contains("双周") ? 2 : 0
                for (first,last,_) in Self.weeks(parts[weekIndex].components(separatedBy:"周")[0]) { out.append(JwCourse(name:plan?.name ?? parts[0],room:room,teacher:plan?.teacher ?? "",day:day,startNode:start,endNode:end,startWeek:first,endWeek:last,type:parity,credit:plan?.credit ?? 0)) }
            }
        }
        return out
    }
    private func changzhou() -> [JwCourse] {
        var teachers:[String:String] = [:],out:[JwCourse] = []
        for row in jw1064Elements(try? doc?.getElementById("GVxkall"),".dg1-item") { let c = jw1064Elements(row,"td");if c.count >= 6 { teachers[jw1064Text(c[1])] = jw1064Text(c[5]) } }
        for (node,row) in jw1064Elements(try? doc?.getElementById("GVxkkb"),".dg1-item").enumerated() {
            for (day,cell) in jw1064Elements(row,"td").enumerated() where day > 0 {
                var prefix = ""
                for part in jw1064Text(cell).components(separatedBy:"/") where !part.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                    let fields = part.trimmingCharacters(in:.whitespacesAndNewlines).components(separatedBy:" ")
                    guard fields.count == 4 else { prefix += part.trimmingCharacters(in:.whitespacesAndNewlines)+"/";continue }
                    let ranges = Self.weeks(fields[3]);if ranges.isEmpty { prefix += part.trimmingCharacters(in:.whitespacesAndNewlines)+"/";continue }
                    let parity = fields[2] == "单" ? 1 : fields[2] == "双" ? 2 : 0
                    for (first,last,_) in ranges { out.append(JwCourse(name:prefix+fields[0],room:fields[1],teacher:teachers[fields[0]] ?? "",day:day,startNode:node+1,endNode:node+1,startWeek:first,endWeek:last,type:parity)) };prefix = ""
                }
            }
        }
        return out
    }
    static let shuPeriods = JwSourcePeriods.rows("08:00-08:45 08:55-09:40 10:00-10:45 10:55-11:40 13:00-13:45 13:55-14:40 15:00-15:45 15:55-16:40 18:00-18:45 18:55-19:40 20:00-20:45 20:55-21:40")
}
