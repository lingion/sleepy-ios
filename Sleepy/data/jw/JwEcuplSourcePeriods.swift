import Foundation
import SwiftSoup

enum JwEcuplSourcePeriods {
    static func resolve(_ source: String) -> [(Int, String, String)] {
        guard let doc = try? SwiftSoup.parse(source), let table = jw1064Elements(doc, "table.listTable").first,
              let row = jw1064Elements(table, "tr").first else { return [] }
        let cells = jw1064Elements(row, "td").dropFirst()
        guard !cells.isEmpty else { return [] }
        var periods: [(Int, String, String)] = []
        for (index, cell) in cells.enumerated() {
            guard let match = jw1064Matches(#"^([0-9]{1,2}):([0-9]{2})\s*-\s*([0-9]{1,2}):([0-9]{2})$"#, jw1064Text(cell)).first,
                  let sh = Int(match[1]), let sm = Int(match[2]), let eh = Int(match[3]), let em = Int(match[4]),
                  (0...23).contains(sh), (0...23).contains(eh), (0...59).contains(sm), (0...59).contains(em), sh * 60 + sm < eh * 60 + em else { return [] }
            periods.append((index + 1, String(format: "%02d:%02d", sh, sm), String(format: "%02d:%02d", eh, em)))
        }
        return periods
    }
}
