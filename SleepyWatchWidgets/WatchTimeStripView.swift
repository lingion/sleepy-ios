import SwiftUI
import WidgetKit

struct WatchTimeStripView: View {
    let entry: WatchTimeStripEntry

    private var snapshot: WatchTimeStripCore.Snapshot { entry.snapshot }
    private var bundle: Bundle { LocaleHelper.bundle(for: entry.language) }
    private var locale: Locale { LocaleHelper.locale(for: entry.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(snapshot.isTomorrow ? text("watch_time_strip_preview") : text("watch_time_strip_display_name"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .widgetAccentable()
                Spacer(minLength: 0)
                Text(snapshot.isTomorrow ? dayLabel : text("watch_time_strip_scale"))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.system(size: 11, weight: .semibold))

            if snapshot.segments.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                strip
                HStack(spacing: 2) {
                    Text(snapshot.isTomorrow ? time(snapshot.windowStart) : "\(text("watch_mark_now")) \(time(snapshot.windowStart))")
                    Spacer(minLength: 0)
                    Text(time(snapshot.windowEnd))
                }
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "sleepy://watch?tab=today"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var strip: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                ForEach(Array(snapshot.segments.enumerated()), id: \.offset) { _, segment in
                    let width = max(0, geometry.size.width * segment.widthFraction)
                    segmentView(segment, width: width)
                        .frame(width: width, height: geometry.size.height)
                        .offset(x: geometry.size.width * segment.offsetFraction(from: snapshot.windowStart))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            .clipped()
        }
        .frame(minHeight: 18)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func segmentView(_ segment: WatchTimeStripCore.Segment, width: CGFloat) -> some View {
        ZStack {
            if !segment.courses.isEmpty {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.primary.opacity(0.18))
                    .widgetAccentable()
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.primary, lineWidth: 1)
                    .widgetAccentable()
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
            if width >= 26 {
                ViewThatFits(in: .horizontal) {
                    Text(segmentTitle(segment))
                        .font(.system(size: 10, weight: segment.courses.isEmpty ? .regular : .semibold))
                        .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: segment.courses.isEmpty ? "cup.and.saucer" : "book.closed")
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 3)
            }
        }
        .padding(.horizontal, min(1, width / 4))
        .clipped()
    }

    private func segmentTitle(_ segment: WatchTimeStripCore.Segment) -> String {
        if segment.courses.count > 1 {
            return String(format: text("watch_time_strip_overlap"), locale: locale, segment.courses.count)
        }
        return segment.courses.first?.courseName ?? text(segment.isBreak ? "watch_time_strip_break" : "watch_time_strip_free")
    }

    private var emptyMessage: String {
        switch snapshot.state {
        case .finished: return text("watch_time_strip_finished")
        case .tomorrowEmpty: return text("watch_tomorrow_no_class")
        case .unavailable: return text("watch_time_strip_unavailable")
        default: return text("no_course")
        }
    }

    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: snapshot.day)
    }

    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    private var accessibilitySummary: String {
        let title = snapshot.isTomorrow
            ? "\(text("watch_time_strip_preview")) \(dayLabel)"
            : text("watch_time_strip_display_name")
        guard !snapshot.segments.isEmpty else { return "\(title). \(emptyMessage)" }
        let intervals = snapshot.segments.map { segment -> String in
            let names = segment.courses.isEmpty ? segmentTitle(segment) : segment.courses.map { item in
                item.room.isEmpty ? item.courseName : "\(item.courseName), \(item.room)"
            }.joined(separator: "; ")
            return "\(time(segment.start))–\(time(segment.end)), \(names)"
        }.joined(separator: "; ")
        return "\(title). \(text("watch_time_strip_scale")). \(intervals)"
    }
}
