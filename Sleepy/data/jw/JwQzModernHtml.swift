// Android v1.0.64 modern QZ tooltip and Element table layouts.
import Foundation
import SwiftSoup

enum JwQzModernHtml {
    static func features(_ document: Document) -> [String] {
        var result: [String] = []
        if Jw64.first(document, "td[name=kbDataTd] li.qz-toolitiplists .qz-tooltipContent-title") != nil { result.append("qz-2024-tooltip") }
        let header = Jw64.text(Jw64.first(document, ".el-table__header"))
        let days = Set(jw1064Matches("星期[一二三四五六日天]", header).map { $0[0].replacingOccurrences(of: "天", with: "日") })
        if days.count == 7 && Jw64.select(document, ".el-table__body .cell[style]").contains(where: centered) { result.append("qz-2017-element-table") }
        return result
    }

    static func parse(_ document: Document) -> [JwCourse]? {
        let values = features(document)
        if values.contains("qz-2024-tooltip") { return parse2024(document) }
        if values.contains("qz-2017-element-table") { return parse2017(document) }
        return nil
    }

    private static func centered(_ cell: Element) -> Bool { Jw64.attr(cell, "style").replacingOccurrences(of: " ", with: "").contains("text-align:center") }
    private static func parse2024(_ document: Document) -> [JwCourse] {
        var result: [JwCourse] = []
        for cell in Jw64.select(document, "[name=kbDataTd]") {
            guard let parent = cell.parent(), let day = Jw64.children(parent).firstIndex(where: { $0 === cell }), (1...7).contains(day) else { continue }
            for record in Jw64.select(cell, "li.qz-toolitiplists") {
                let name = Jw64.text(Jw64.first(record, ".qz-tooltipContent-title"))
                var fields: [String: String] = [:]
                for field in Jw64.select(record, ".qz-tooltipContent-detailitem") {
                    let text = Jw64.text(field)
                    if let separator = text.firstIndex(of: "：") { fields[Jw64.trim(String(text[..<separator]))] = Jw64.trim(String(text[text.index(after: separator)...])) }
                    else { fields[text] = "" }
                }
                let time = fields["时间"] ?? ""
                guard !jw1064Matches(#"\[[^]]+]"#, time).isEmpty else { continue }
                result += convert(name, fields["老师"] ?? "", fields["地点"] ?? "", time, day)
            }
        }
        return result
    }

    private static func parse2017(_ document: Document) -> [JwCourse] {
        let headers = Jw64.select(Jw64.first(document, ".el-table__header"), "div")
        let sunday = headers.firstIndex { Jw64.text($0).contains("星期日") }, monday = headers.firstIndex { Jw64.text($0).contains("星期一") }
        let sundayFirst = sunday != nil && monday != nil && sunday! < monday!
        let rows = Jw64.first(document, ".el-table__body tbody").map(Jw64.children)?.filter { $0.tagNameNormal() == "tr" } ?? []
        var result: [JwCourse] = []
        for (rowIndex, row) in rows.enumerated() {
            let start = rowIndex * 2 + 1, end = start + (rowIndex == rows.count - 1 ? 2 : 1)
            for (column, cell) in Jw64.select(row, ".cell[style]").filter(centered).enumerated() where column < 7 {
                let day = sundayFirst ? [7, 1, 2, 3, 4, 5, 6][column] : column + 1
                for record in Jw64.children(cell) {
                    let fields = Jw64.children(record)
                    guard let index = fields.lastIndex(where: { !jw1064Matches("[0-9]{1,2}周", Jw64.text($0)).isEmpty }), index >= 3 else { continue }
                    let name = Jw64.text(fields[index - 3]), teacher = Jw64.text(fields[index - 2]), time = Jw64.text(fields[index])
                    let slash = time.components(separatedBy: "/")
                    let room: String, schedule: String
                    if slash.count == 3 && slash[1].contains("节") { room = Jw64.trim(slash[0]); schedule = slash[2] + "[" + slash[1] + "]" }
                    else {
                        room = index + 1 < fields.count ? Jw64.text(fields[index + 1]) : ""
                        if let sections = jw1064Matches(#"^([0-9,，、 -]+)节"#, time).first { schedule = String(time.dropFirst(sections[0].count)) + "[" + sections[1] + "节]" }
                        else { schedule = "\(time)[\(start)-\(end) 节]" }
                    }
                    result += convert(name, teacher, room, schedule.replacingOccurrences(of: "单双", with: ""), day)
                }
            }
        }
        return result
    }

    private static func convert(_ name: String, _ teacher: String, _ room: String, _ time: String, _ day: Int) -> [JwCourse] {
        guard !name.isEmpty, !time.isEmpty else { return [] }
        func escaped(_ text: String) -> String { text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        let html = "\(escaped(name))<br><font title='教师'>\(escaped(teacher))</font><br><font title='上课地点'>\(escaped(room))</font><br><font title='周次(节次)'>\(escaped(time))</font>"
        var courses: [JwCourse] = []
        JwQzParser("").convert(day: day, nodeCount: 1, infoStr: html, courseList: &courses)
        return courses
    }
}
