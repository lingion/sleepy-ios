import Foundation

enum JwThuCapturePayload {
    static func semester(_ html: String) -> String? {
        let values = Set(Jw64.select(Jw64.doc(html), "[name=p_xnxq]").compactMap { element -> String? in
            let value = Jw64.trim((try? element.val()) ?? ""); return value.isEmpty ? nil : value
        })
        guard values.count == 1, let value = values.first, Jw64.full("[0-9]+(?:-[0-9]+)*", value) != nil else { return nil }
        return value
    }
    static func sameSemester(_ before: String, _ after: String) -> Bool { semester(before).map { $0 == semester(after) } ?? false }
    static func calendarUrl(_ html: String) -> String? { semester(html).map { "https://schedule-data.netlify.app/\($0).json" } }
    static func wrap(_ html: String, _ semesterJson: String) throws -> String {
        guard let selected = semester(html) else { throw JwParseError(message: "未找到唯一的清华学期字段") }
        guard validCalendar(semesterJson), let calendar = Jw64.json(semesterJson) as? [String: Any] else { throw JwParseError(message: "清华学期日历数据无效") }
        return String(data: try JSONSerialization.data(withJSONObject: ["sleepyThuCapture": true, "semester": selected, "html": html, "semesterData": calendar]), encoding: .utf8)!
    }
    static func htmlOrOriginal(_ source: String) -> String {
        guard let root = Jw64.json(source) as? [String: Any], root.keys.contains("sleepyThuCapture") else { return source }
        return read(root)?.0 ?? ""
    }
    static func semesterJson(_ source: String) -> String? { (Jw64.json(source) as? [String: Any]).flatMap(read)?.1 }
    private static func read(_ root: [String: Any]) -> (String, String)? {
        guard root["sleepyThuCapture"] as? Bool == true, let html = root["html"] as? String, let selected = semester(html), root["semester"] as? String == selected, let calendar = root["semesterData"] as? [String: Any], let data = try? JSONSerialization.data(withJSONObject: calendar), let raw = String(data: data, encoding: .utf8), validCalendar(raw) else { return nil }
        return (html, raw)
    }
    private static func validCalendar(_ raw: String) -> Bool {
        guard let root = Jw64.json(raw) as? [String: Any], root.keys.contains("weekCount") || root.keys.contains("reschedule") else { return false }
        return JwThuScriptParser.validSemesterData(raw)
    }
}
