import Foundation

/// Exclude teaching weeks as sets before splitting recurring ranges.
func umoocWeeks(_ raw: String) -> [Int] {
    let text = Jw64.trim(raw).replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")").replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    let exclusion = Jw64.full(#"(.*?)(?:\(除([^()]*)\)|除([^()]*))"#, text)
    let include = exclusion?[1] ?? text
    let exclude = exclusion.map { $0[2].isEmpty ? $0[3] : $0[2] }
    func weekSet(_ expression: String, allowDefault: Bool) -> Set<Int>? {
        if allowDefault, ["全周", "单周", "双周"].contains(expression) {
            return Set((1...18).filter { expression == "全周" || $0 % 2 == (expression == "单周" ? 1 : 0) })
        }
        var weeks = Set<Int>()
        for token in expression.components(separatedBy: CharacterSet(charactersIn: ",，、.")) {
            guard let m = Jw64.full(#"(?:([单双全])周?)?第?([0-9]+)(?:-([0-9]+))?([单双全])?周?(?:\(([单双全])周?\))?"#, token),
                  let first = Int(m[2]), let last = Int(m[3].isEmpty ? m[2] : m[3]), (1...366).contains(first), (first...366).contains(last) else { return nil }
            let markers = Set([m[1],m[4],m[5]].filter { !$0.isEmpty }); guard markers.count <= 1 else { return nil }
            let parity = markers.first == "单" ? 1 : markers.first == "双" ? 2 : 0
            weeks.formUnion((first...last).filter { parity == 0 || $0 % 2 == parity % 2 })
        }
        return weeks
    }
    guard let included = weekSet(include, allowDefault: true) else { return [] }
    let excluded: Set<Int>
    if let exclude { guard let set = weekSet(exclude, allowDefault: false) else { return [] }; excluded = set }
    else { excluded = [] }
    return included.subtracting(excluded).sorted()
}
