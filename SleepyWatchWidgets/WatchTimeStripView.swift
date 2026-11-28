import SwiftUI
import WidgetKit

struct WatchTimeStripView: View {
    @Environment(\.watchMaterialPalette) private var palette
    let entry: WatchTimeStripEntry

    private var snapshot: WatchTimeStripCore.Snapshot { entry.snapshot }
    private var bundle: Bundle { LocaleHelper.bundle(for: entry.language) }
    private var locale: Locale { LocaleHelper.locale(for: entry.language) }

    var body: some View {
        WatchTimeStripContent(entry: entry, snapshot: snapshot, bundle: bundle, locale: locale,
                              palette: palette)
            .watchMaterialSurface(.accessoryRectangular)
            .widgetURL(URL(string: "sleepy://watch?tab=today"))
    }
}

private struct WatchTimeStripContent: View {
    @Environment(\.watchMaterialPalette) private var envPalette
    let entry: WatchTimeStripEntry
    let snapshot: WatchTimeStripCore.Snapshot
    let bundle: Bundle
    let locale: Locale
    let palette: WatchMaterialPalette

    private var activePalette: WatchMaterialPalette {
        envPalette.usesMaterial ? envPalette : palette
    }

    var body: some View {
        let p = activePalette
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(snapshot.isTomorrow ? text("watch_time_strip_preview") : text("watch_time_strip_display_name"))
                    .foregroundColor(p.usesMaterial ? p.accent : p.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .widgetAccentable()
                Spacer(minLength: 0)
                Text(snapshot.isTomorrow ? dayLabel : text("watch_time_strip_scale"))
                    .foregroundColor(p.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.system(size: 11, weight: .semibold))

            if snapshot.segments.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 12))
                    .foregroundColor(p.secondaryText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                strip(p)
                HStack(spacing: 2) {
                    Text(snapshot.isTomorrow ? time(snapshot.windowStart) : "\(text("watch_mark_now")) \(time(snapshot.windowStart))")
                    Spacer(minLength: 0)
                    Text(time(snapshot.windowEnd))
                }
                .font(.system(size: 9).monospacedDigit())
                .foregroundColor(p.secondaryText)
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func strip(_ p: WatchMaterialPalette) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                ForEach(Array(snapshot.segments.enumerated()), id: \.offset) { _, segment in
                    let width = max(0, geometry.size.width * segment.widthFraction)
                    segmentView(segment, width: width, palette: p)
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

    private func segmentView(_ segment: WatchTimeStripCore.Segment, width: CGFloat,
                             palette p: WatchMaterialPalette) -> some View {
        ZStack {
            if !segment.courses.isEmpty {
                RoundedRectangle(cornerRadius: SleepyShapes.extraSmall)
                    .fill(p.stripCourseFill)
                    .widgetAccentable()
                RoundedRectangle(cornerRadius: SleepyShapes.extraSmall)
                    .strokeBorder(p.stripCourseStroke, lineWidth: 1)
                    .widgetAccentable()
            } else {
                RoundedRectangle(cornerRadius: SleepyShapes.extraSmall)
                    .strokeBorder(p.stripFreeStroke, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
            if width >= 26 {
                ViewThatFits(in: .horizontal) {
                    Text(segmentTitle(segment))
                        .font(.system(size: 10, weight: segment.courses.isEmpty ? .regular : .semibold))
                        .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: segment.courses.isEmpty ? "cup.and.saucer" : "book.closed")
                        .font(.system(size: 10))
                }
                .foregroundColor(segment.courses.isEmpty ? p.secondaryText : p.stripActiveText)
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
