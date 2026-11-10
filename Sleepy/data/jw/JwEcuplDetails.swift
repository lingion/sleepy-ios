import Foundation
import SwiftSoup

struct JwEcuplDetails {
    let name: String
    let teacher: String
    let credit: Float
    let note: String
}
func ecuplDetails(_ source: String) -> [String: JwEcuplDetails] {
    guard let doc = try? SwiftSoup.parse(source) else { return [:] }
    var details: [String: JwEcuplDetails] = [:]
    for table in jw1064Elements(doc, "table.listTable") {
        let rows = jw1064Elements(table, "tr")
        let headers = jw1064Elements(rows.first, "td,th").map { jw1064Text($0) }
        guard let code = headers.firstIndex(of: "课程序号"), let name = headers.firstIndex(where: { $0 == "课程名称" || $0 == "课程名" }),
              let teacher = headers.firstIndex(of: "教师"), let credit = headers.firstIndex(of: "学分"), let note = headers.firstIndex(of: "备注") else { continue }
        for row in rows.dropFirst() {
            let cells = jw1064Elements(row, "td")
            guard cells.count > max(code, name, teacher, credit, note) else { continue }
            let id = jw1064Text(cells[code])
            guard !id.isEmpty else { continue }
            let amount = Float(jw1064Text(cells[credit])) ?? 0
            details[id] = JwEcuplDetails(name: jw1064Text(cells[name]), teacher: jw1064Text(cells[teacher]),
                                       credit: amount.isFinite ? amount : 0, note: jw1064Text(cells[note]))
        }
    }
    return details
}
