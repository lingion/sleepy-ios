import Foundation
import SwiftSoup

enum JwZfVariantHtml {
    static func parse(_ source:String)->[JwCourse]? {
        guard let doc=try? SwiftSoup.parse(source) else { return nil }
        if let nested=try? doc.getElementById("table_tb") { let rows=parseNested(nested);if !rows.isEmpty { return rows } }
        if let table=try? doc.getElementById("table1"),!jw1064Elements(table,"td[id] .title").isEmpty {
            for cell in jw1064Elements(table,"td[id]") { for record in jw1064Elements(cell,"div") {
                guard !jw1064Elements(record,".title").isEmpty else { continue };let paragraphs=jw1064Elements(record,"p")
                guard !paragraphs.isEmpty,!paragraphs.contains(where:{!jw1064Elements($0,"[title]").isEmpty}) else { continue }
                for (index,title) in ["节/周","上课地点","教师"].enumerated() where paragraphs.indices.contains(index) { _ = try? paragraphs[index].attr("title",title) }
            } }
            if let html=try? doc.outerHtml(),let rows=try? JwNewZfParser(html).generateCourseList(),!rows.isEmpty { return rows }
        }
        guard let table=(try? doc.getElementById("Table6")) ?? (try? doc.getElementById("table6")) else { return nil }
        return parseClassTable(doc,table)
    }
    static func parseClass(_ source:String)->[JwCourse] {
        guard let doc=try? SwiftSoup.parse(source),let table=(try? doc.getElementById("Table6")) ?? (try? doc.getElementById("table6")) else { return [] };return parseClassTable(doc,table)
    }
    private static func parseClassTable(_ doc:Document,_ table:Element)->[JwCourse] {
        _ = try? table.attr("id","Table1")
        for cell in jw1064Elements(table,"td") {
            if let festival=jw1064Integer(jw1064Text(cell,".festival")),jw1064Text(cell)==String(festival) { _ = try? cell.text("第\(festival)节");continue }
            let pieces=jw1064Split(#"(?i)<br\s*/?>"#,(try? cell.html()) ?? "");if pieces.count<3 { continue }
            _ = try? cell.html(pieces.map(normalizeClassTime).joined(separator:"<br>"))
        }
        return (try? JwOldZfParser((try? doc.outerHtml()) ?? "").generateCourseList()) ?? []
    }
    private static func normalizeClassTime(_ value:String)->String {
        if value.contains("{") { return value }
        let normalized=value.replacingOccurrences(of:"（",with:"(").replacingOccurrences(of:"）",with:")")
        if let m=jw1064Matches(#"([0-9]+)节/([单双]?)周\(([^)]*)\)"#,normalized).first { return "{第"+m[3]+"周}"+(m[2]=="单" ? "单周":m[2]=="双" ? "双周":"")+m[1]+"节/" }
        let before=normalized.components(separatedBy:"(")[0].trimmingCharacters(in:.whitespacesAndNewlines)
        guard let m=jw1064Matches(#"^([0-9]+)(?:-([0-9]+))?([单双]?)$"#,before).first else { return value }
        let after=normalized.range(of:before).map{String(normalized[$0.upperBound...])} ?? normalized
        return "{第"+m[1]+"-"+(m[2].isEmpty ? m[1]:m[2])+"周}"+(m[3]=="单" ? "单周":m[3]=="双" ? "双周":"")+after
    }
    private static func parseNested(_ table:Element)->[JwCourse] {
        var out:[JwCourse]=[]
        for cell in jw1064Elements(table,"td[id^=td_][rowspan]") {
            guard let m=jw1064Matches(#"^td_([1-7])-([0-9]+)$"#,cell.id()).first,let day=jw1064Integer(m[1]),let start=jw1064Integer(m[2]),let span=jw1064Integer(jw1064Attribute(cell,"rowspan")),start>0,span>0,start+span-1<=Int(Int32.max) else { continue }
            for record in jw1064Elements(cell,"table") {
                let p=jw1064Elements(record,"p");guard p.count>=5,let doc=try? SwiftSoup.parseBodyFragment("<div></div>"),let field=try? doc.select("div").first() else { continue }
                _ = try? field.text(jw1064Text(p[0]));_ = try? field.appendElement("br");_ = try? field.appendElement("font").attr("title","教师").text(jw1064Text(p[3]));_ = try? field.appendElement("br");_ = try? field.appendElement("font").attr("title","教室").text(jw1064Text(p[2]));_ = try? field.appendElement("br");_ = try? field.appendElement("font").attr("title","周次(节次)").text("\(jw1064Text(p[4]))[\(start)-\(start+span-1)节]")
                JwQzParser("").convert(day:day,nodeCount:1,infoStr:(try? field.html()) ?? "",courseList:&out)
            }
        };return out
    }
}
