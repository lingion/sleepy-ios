// Dedicated 4×2 policies, ported from Android v1.0.64. Indices are physical slots.
import Foundation
import CoreGraphics

enum WeekGridWideMode: String, Codable, CaseIterable, Hashable {
    case vertical, horizontal
    var labelKey: String { "widget_wide_grid_\(rawValue)" }
    var widgetKind: String { self == .vertical ? "WeekGridVerticalWidget" : "WeekGridHorizontalWidget" }
    var displayNameKey: String { "widget_week_grid_\(rawValue)_label" }

    init?(kind: String) {
        guard let mode = Self.allCases.first(where: { $0.widgetKind == kind }) else { return nil }
        self = mode
    }
}

enum WeekGridWideLabelSide: String, Codable, CaseIterable, Hashable {
    case left, right
    var labelKey: String { "widget_wide_grid_\(rawValue)" }
}

struct WeekGridWideSettings: Codable, Equatable {
    var mode: WeekGridWideMode = .vertical
    var labelSide: WeekGridWideLabelSide = .left
}

struct WidePeriod: Equatable {
    let node: Int
    let startMinute: Int?
    let endMinute: Int?
}

struct WidePeriodWindow: Equatable {
    let startIndex: Int
    let count: Int
}

enum WeekGridWideWindowCore {
    /// Validate legacy database values before conflict geometry performs any node arithmetic.
    static func periodNodeSpan(startNode: Int, step: Int) -> Range<Int>? {
        guard startNode >= 0, step > 0 else { return nil }
        let (end, overflow) = startNode.addingReportingOverflow(step)
        guard !overflow else { return nil }
        return startNode..<end
    }

    static func visibleDates(today: Date, mode: WeekGridWideMode,
                             calendar: Calendar = .current) -> [Date] {
        let day = calendar.startOfDay(for: today)
        let weekday = (calendar.component(.weekday, from: day) + 5) % 7
        let start = mode == .horizontal ? day : calendar.date(byAdding: .day, value: -weekday, to: day)!
        return (0..<(mode == .horizontal ? 3 : 7)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    /// ISO LocalTime grammar used by Android's renderer; malformed clocks stay unresolved.
    static func minute(_ text: String) -> Int? {
        let bytes = Array(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        func pair(_ index: Int) -> Int? {
            guard index + 1 < bytes.count,
                  (48...57).contains(bytes[index]), (48...57).contains(bytes[index + 1]) else { return nil }
            return Int(bytes[index] - 48) * 10 + Int(bytes[index + 1] - 48)
        }
        guard bytes.count >= 5, bytes[2] == 58,
              let hour = pair(0), hour < 24, let minute = pair(3), minute < 60 else { return nil }
        if bytes.count > 5 {
            guard bytes.count >= 8, bytes[5] == 58,
                  let second = pair(6), second < 60 else { return nil }
            if bytes.count > 8 {
                // ISO_LOCAL_TIME accepts a decimal point with zero through nine fraction digits.
                guard bytes[8] == 46, bytes.count <= 18,
                      bytes.dropFirst(9).allSatisfy({ (48...57).contains($0) }) else { return nil }
            }
        }
        return hour * 60 + minute
    }

    static func periods(timeJson: String) -> [WidePeriod] {
        guard let data = timeJson.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return rows.enumerated().compactMap { index, value -> WidePeriod? in
            guard let row = value as? [String: Any] else { return nil }
            return WidePeriod(node: row["node"] as? Int ?? Int(row["node"] as? String ?? "") ?? index + 1,
                       startMinute: minute(row["start"] as? String ?? ""),
                       endMinute: minute(row["end"] as? String ?? ""))
        }.sorted { $0.node < $1.node }
    }

    static func capacity(height: CGFloat, fontScale: CGFloat = 1) -> Int {
        max(Int(floor((height - 12) / (36 * max(fontScale, 1)))), 4)
    }

    static func visiblePeriods(_ periods: [WidePeriod], nowMinute: Int, capacity: Int) -> WidePeriodWindow {
        let count = min(max(capacity, 4), periods.count)
        let finished = periods.prefix { $0.endMinute.map { nowMinute >= $0 } == true }.count
        return WidePeriodWindow(startIndex: min(finished, periods.count - count), count: count)
    }

    /// Intersect before measuring text, including long cards beginning above the window.
    static func intersectPeriodSpan(start: CGFloat, end: CGFloat,
                                    window: WidePeriodWindow) -> Range<CGFloat>? {
        let first = max(start, CGFloat(window.startIndex))
        let finish = min(end, CGFloat(window.startIndex + window.count))
        guard first < finish else { return nil }
        return (first - CGFloat(window.startIndex))..<(finish - CGFloat(window.startIndex))
    }

    static func fractionalSpan(startMinute: Int, endMinute: Int,
                               periods: [WidePeriod]) -> Range<CGFloat>? {
        let timed = periods.filter { $0.startMinute != nil && $0.endMinute != nil }
        guard timed.count == periods.count, let first = timed.first, let last = timed.last,
              endMinute > startMinute else { return nil }
        func position(_ minute: Int) -> CGFloat {
            if minute <= first.startMinute! { return 0 }
            if minute >= last.endMinute! { return CGFloat(timed.count) }
            if let index = timed.firstIndex(where: { $0.startMinute! <= minute && minute <= $0.endMinute! }) {
                let period = timed[index]
                return CGFloat(index) + CGFloat(minute - period.startMinute!) /
                    CGFloat(max(period.endMinute! - period.startMinute!, 1))
            }
            return CGFloat(timed.firstIndex { $0.startMinute! > minute } ?? timed.count)
        }
        let start = position(startMinute), end = position(endMinute)
        return start < end ? start..<end : nil
    }

    static func bodyRect(size: CGSize, mode: WeekGridWideMode, side: WeekGridWideLabelSide) -> CGRect {
        let vertical = mode == .vertical
        let labels: CGFloat = vertical ? 22 : 34
        let header: CGFloat = vertical ? 0 : 34
        let left = vertical || side == .left
        return CGRect(x: 6 + (left ? labels : 0), y: 6 + header,
                      width: max(size.width - 12 - labels, 1), height: max(size.height - 12 - header, 1))
    }

    static func cardRect(body: CGRect, dayIndex: Int, dayCount: Int, laneStart: CGFloat,
                         laneWidth: CGFloat, span: Range<CGFloat>, windowCount: Int,
                         vertical: Bool) -> CGRect? {
        let dayExtent = (vertical ? body.width : body.height) / CGFloat(max(dayCount, 1))
        let periodExtent = (vertical ? body.height : body.width) / CGFloat(max(windowCount, 1))
        let day = CGFloat(dayIndex) + laneStart
        let frame = vertical
            ? CGRect(x: body.minX + day * dayExtent, y: body.minY + span.lowerBound * periodExtent,
                     width: laneWidth * dayExtent, height: span.count * periodExtent)
            : CGRect(x: body.minX + span.lowerBound * periodExtent, y: body.minY + day * dayExtent,
                     width: span.count * periodExtent, height: laneWidth * dayExtent)
        let inset = frame.insetBy(dx: 1, dy: 1)
        return inset.width > 0 && inset.height > 0 ? inset : nil
    }
}

private extension Range where Bound == CGFloat {
    var count: CGFloat { upperBound - lowerBound }
}

// Independent defaults: never inherit the old global scroll or compact-window preference.
enum WeekGridWideSettingsStore {
    static func read(kind: String, url: URL? = nil) -> WeekGridWideSettings {
        let url = url ?? storeURL()
        let fixedMode = WeekGridWideMode(kind: kind)
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]],
              let values = root[kind] else { return WeekGridWideSettings(mode: fixedMode ?? .vertical) }
        return WeekGridWideSettings(mode: fixedMode ?? WeekGridWideMode(rawValue: values["mode"] ?? "") ?? .vertical,
                                    labelSide: WeekGridWideLabelSide(rawValue: values["labelSide"] ?? "") ?? .left)
    }

    static func write(_ settings: WeekGridWideSettings, kind: String,
                      url: URL? = nil) {
        let url = url ?? storeURL()
        var values = (try? Data(contentsOf: url)).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: [String: String]]
        } ?? [:]
        let mode = WeekGridWideMode(kind: kind) ?? settings.mode
        values[kind] = ["mode": mode.rawValue, "labelSide": settings.labelSide.rawValue]
        guard let data = try? JSONSerialization.data(withJSONObject: values) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func storeURL() -> URL {
        AppGroupResolver.sharedDirectory().appendingPathComponent("widget_wide_grid.json")
    }
}
