// Android v1.0.64 dedicated 4×2 receiver. Existing WeekGrid family is unchanged.
import SwiftUI
import WidgetKit

struct WeekGridWideWidgetEntry: TimelineEntry {
    let date: Date
    let data: WeekData
    let settings: WeekGridWideSettings
}

struct WeekGridWideWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekGridWideWidgetEntry {
        WidgetArchiveLog.append(kind: WeekGridWideSettings.kind, family: context.family.description, result: "success")
        return WeekGridWideWidgetEntry(date: Date(), data: WeekData(days: [], hasTable: false),
                                      settings: WeekGridWideSettings())
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekGridWideWidgetEntry) -> Void) {
        Task {
            let now = Date(), settings = WeekGridWideSettingsStore.read()
            let data = await WeekGridWideDataLoader.load(mode: settings.mode, now: now)
            WidgetArchiveLog.append(kind: WeekGridWideSettings.kind, family: context.family.description, result: "success")
            completion(WeekGridWideWidgetEntry(date: now, data: data, settings: settings))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekGridWideWidgetEntry>) -> Void) {
        Task {
            let now = Date(), settings = WeekGridWideSettingsStore.read()
            let data = await WeekGridWideDataLoader.load(mode: settings.mode, now: now)
            let refresh = WidgetBoundaryScheduler.nextRefresh(after: now)
            let entries = Self.timelineDates(data: data, mode: settings.mode, from: now, before: refresh).map {
                WeekGridWideWidgetEntry(date: $0, data: data, settings: settings)
            }
            WidgetArchiveLog.append(kind: WeekGridWideSettings.kind, family: context.family.description, result: "success")
            completion(Timeline(entries: entries, policy: .after(refresh)))
        }
    }

    /// Period boundaries apply even on empty days and when no course ends at this time.
    static func timelineDates(data: WeekData, mode: WeekGridWideMode, from now: Date,
                              before refresh: Date, calendar: Calendar = .current) -> [Date] {
        guard mode == .vertical else { return [now] }
        let midnight = calendar.startOfDay(for: now)
        let dates = WeekGridWideWindowCore.periods(timeJson: data.days.first?.timeJson ?? "")
            .compactMap(\.endMinute).compactMap { calendar.date(byAdding: .minute, value: $0, to: midnight) }
            .filter { $0 > now && $0 < refresh }
        return [now] + Set(dates).sorted()
    }
}

struct WeekGridWideCard: Identifiable {
    let course: CourseEntity
    let date: Date
    let bounds: CGRect
    let isGrey: Bool
    var id: String { "\(date.timeIntervalSince1970)|\(course.id)" }
}

struct WeekGridWideGeometry {
    let dates: [Date]
    let periods: [WidePeriod]
    let window: WidePeriodWindow
    let body: CGRect
    let cards: [WeekGridWideCard]

    static func make(data: WeekData, settings: WeekGridWideSettings, now: Date,
                     size: CGSize, fontScale: CGFloat = 1) -> WeekGridWideGeometry {
        let dates = WeekGridWideWindowCore.visibleDates(today: now, mode: settings.mode)
        let periods = WeekGridWideWindowCore.periods(timeJson: data.days.first?.timeJson ?? "")
        let vertical = settings.mode == .vertical
        let window = vertical
            ? WeekGridWideWindowCore.visiblePeriods(periods, nowMinute: WidgetWindows.nowMinutes(now),
                capacity: WeekGridWideWindowCore.capacity(height: size.height, fontScale: fontScale))
            : WidePeriodWindow(startIndex: 0, count: periods.count)
        let body = WeekGridWideWindowCore.bodyRect(size: size, mode: settings.mode, side: settings.labelSide)
        var cards: [WeekGridWideCard] = []
        for (dayIndex, date) in dates.enumerated() {
            guard let day = data.days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) else { continue }
            let validCourses = day.courses.filter {
                WeekGridWideWindowCore.periodNodeSpan(startNode: $0.startNode, step: $0.step) != nil
            }
            for lane in ConflictLayoutEngine.gridDayLanes(validCourses, timeJson: day.timeJson) {
                let course = lane.course
                guard let nodes = WeekGridWideWindowCore.periodNodeSpan(startNode: course.startNode, step: course.step),
                      let first = periods.firstIndex(where: { $0.node >= nodes.lowerBound }),
                      let last = periods.lastIndex(where: { $0.node < nodes.upperBound }),
                      last >= first else { continue }
                var span = CGFloat(first)..<CGFloat(last + 1)
                if course.ownTime || course.isIrregularTime,
                   let start = WeekGridWideWindowCore.minute(course.startTime),
                   let end = WeekGridWideWindowCore.minute(course.endTime),
                   let fractional = WeekGridWideWindowCore.fractionalSpan(startMinute: start, endMinute: end, periods: periods) {
                    span = fractional
                }
                guard let visible = WeekGridWideWindowCore.intersectPeriodSpan(start: span.lowerBound,
                    end: span.upperBound, window: window),
                      let bounds = WeekGridWideWindowCore.cardRect(body: body, dayIndex: dayIndex,
                        dayCount: dates.count, laneStart: CGFloat(lane.laneStartFraction),
                        laneWidth: CGFloat(lane.laneWidthFraction), span: visible,
                        windowCount: window.count, vertical: vertical) else { continue }
                cards.append(WeekGridWideCard(course: course, date: date, bounds: bounds, isGrey: day.isGrey))
            }
        }
        return WeekGridWideGeometry(dates: dates, periods: periods, window: window, body: body, cards: cards)
    }
}

struct WeekGridWideWidgetEntryView: View {
    let entry: WeekGridWideWidgetEntry
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if entry.settings.mode == .original {
            WeekGridWidgetEntryView(entry: WeekGridWidgetEntry(date: entry.date, data: entry.data))
        } else {
            WidgetGlassModeContent { mode in
                let dark = effectiveWidgetIsDark(themeMode: entry.data.themeMode, snapshotIsDark: entry.data.isDark,
                                                 envScheme: colorScheme)
                let scheme = resolveWidgetScheme(themeKey: entry.data.themeKey, isDark: dark,
                    renderingMode: mode, increasedContrast: contrast == .increased)
                GeometryReader { proxy in
                    let geometry = WeekGridWideGeometry.make(data: entry.data, settings: entry.settings,
                        now: entry.date, size: proxy.size, fontScale: fontScale)
                    ZStack(alignment: .topLeading) {
                        labels(geometry, scheme: scheme, size: proxy.size)
                        if AppPrefs.shared.isGridShowSeparators() {
                            separators(geometry).stroke(scheme.surfaceVariant, lineWidth: 0.5)
                        }
                        ForEach(geometry.cards) { card in
                            WideCourseCard(card: card, allCourses: entry.data.days.flatMap(\.courses),
                                           scheme: scheme, fontScale: fontScale)
                                .frame(width: card.bounds.width, height: card.bounds.height)
                                .offset(x: card.bounds.minX, y: card.bounds.minY)
                        }
                        if !entry.data.hasTable {
                            Text(L10n.format("widget_create_schedule"))
                                .font(.system(size: 12)).foregroundColor(scheme.onSurface)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .clipped()
                }
                .sleepyWidgetBackground { scheme.surface }
                .cornerRadius(18)
            }
            .widgetURL(URL(string: "sleepy://open"))
        }
    }

    private var fontScale: CGFloat { max(UIFont.preferredFont(forTextStyle: .body).pointSize / 17, 1) }

    @ViewBuilder private func labels(_ geometry: WeekGridWideGeometry, scheme: WidgetScheme, size: CGSize) -> some View {
        let vertical = entry.settings.mode == .vertical
        let periodExtent = (vertical ? geometry.body.height : geometry.body.width) / CGFloat(max(geometry.window.count, 1))
        let dayExtent = geometry.body.height / CGFloat(max(geometry.dates.count, 1))
        if !vertical {
            ForEach(Array(geometry.dates.enumerated()), id: \.offset) { index, date in
                VStack(spacing: 2) {
                    Text(DateUtils.localizedDay(DateUtils.todayDayOfWeek(today: date))).font(.system(size: 9))
                    Text(DateUtils.shortDate(date)).font(.system(size: 8))
                }
                .foregroundColor(scheme.onSurfaceVariant)
                .frame(width: 34, height: dayExtent)
                .offset(x: entry.settings.labelSide == .left ? 0 : size.width - 34,
                        y: geometry.body.minY + CGFloat(index) * dayExtent)
            }
        }
        ForEach(0..<geometry.window.count, id: \.self) { index in
            let period = geometry.periods[geometry.window.startIndex + index]
            if vertical {
                Text("\(period.node)").font(.system(size: 9)).foregroundColor(scheme.onSurfaceVariant)
                    .frame(width: geometry.body.minX, height: periodExtent)
                    .offset(y: geometry.body.minY + CGFloat(index) * periodExtent)
            } else {
                VStack(spacing: 1) {
                    Text("\(period.node)").font(.system(size: 9))
                    Text(time(period.startMinute)).font(.system(size: min(7, periodExtent / 3.3)))
                    Text(time(period.endMinute)).font(.system(size: min(7, periodExtent / 3.3)))
                }
                .foregroundColor(scheme.onSurfaceVariant)
                .frame(width: periodExtent, height: 34).clipped()
                .offset(x: geometry.body.minX + CGFloat(index) * periodExtent, y: 6)
            }
        }
    }

    private func separators(_ geometry: WeekGridWideGeometry) -> Path {
        Path { path in
            for index in 1..<geometry.dates.count {
                let fraction = CGFloat(index) / CGFloat(geometry.dates.count)
                if entry.settings.mode == .vertical {
                    let x = geometry.body.minX + geometry.body.width * fraction
                    path.move(to: CGPoint(x: x, y: geometry.body.minY)); path.addLine(to: CGPoint(x: x, y: geometry.body.maxY))
                } else {
                    let y = geometry.body.minY + geometry.body.height * fraction
                    path.move(to: CGPoint(x: geometry.body.minX, y: y)); path.addLine(to: CGPoint(x: geometry.body.maxX, y: y))
                }
            }
        }
    }

    private func time(_ minute: Int?) -> String {
        minute.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) } ?? ""
    }
}

private struct WideCourseCard: View {
    let card: WeekGridWideCard
    let allCourses: [CourseEntity]
    let scheme: WidgetScheme
    let fontScale: CGFloat

    var body: some View {
        let colorless = AppPrefs.shared.isWidgetColorless()
        let base = scheme.isGlass ? Color.white : CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
            card.course, groupRows: allCourses.filter { $0.groupId == card.course.groupId },
            isDark: scheme.isDark, neutralColor: scheme.secondaryContainer, colorless: colorless,
            persistedHue: CourseHueStore.hueFor(groupId: card.course.groupId))
        let color = scheme.isGlass ? scheme.onSurface : foreground(base)
        let inset = min(3, min(card.bounds.width, card.bounds.height) * 0.08)
        let height = max(card.bounds.height - inset * 2, 0.1)
        let hasRoom = !card.course.room.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let roomHeight = hasRoom ? height * 0.36 : 0
        let strike = card.isGrey && AppPrefs.shared.getHolidayStyle() == "strikethrough"
        let width = max(card.bounds.width - inset * 2, 0.1)
        let title = WideGridTextLayout.make(CourseDisplayUtil.displayName(card.course, AppPrefs.shared.isWidgetUseAlias()),
            width: width, height: height - roomHeight, preferred: 11 * fontScale)
        let room = WideGridTextLayout.make(card.course.room, width: width, height: roomHeight, preferred: 8 * fontScale)
        VStack(spacing: 0) {
            Text(title.text)
                .font(.system(size: title.size))
                .strikethrough(strike)
                .frame(maxWidth: .infinity).frame(height: height - roomHeight)
            if hasRoom {
                Text(room.text).font(.system(size: room.size))
                    .strikethrough(strike)
                    .frame(maxWidth: .infinity).frame(height: roomHeight)
            }
        }
        .multilineTextAlignment(.center)
        .foregroundColor(color.opacity(card.isGrey ? 0.6 : 1))
        .padding(inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: min(6, card.bounds.height / 4))
            .fill(scheme.isGlass ? scheme.secondaryContainer : base.opacity(
                colorless ? (card.isGrey ? 0.6 : 1) : (card.isGrey ? 120.0 / 255 : 220.0 / 255))))
        .clipped()
    }

    private func foreground(_ color: Color) -> Color {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return red * 0.299 + green * 0.587 + blue * 0.114 < 145.0 / 255 ? .white : Color(0xFF1D1B20)
    }
}

/// Wrap and ellipsize against the intersected card. A narrow cell still keeps a real first glyph.
struct WideGridTextLayout {
    let text: String
    let size: CGFloat

    static func make(_ value: String, width: CGFloat, height: CGFloat, preferred: CGFloat) -> WideGridTextLayout {
        guard width > 0, height > 0 else { return WideGridTextLayout(text: "", size: 0.1) }
        let clean = value.replacingOccurrences(of: "\n", with: " ")
        var size = max(min(preferred, height * 0.8), 0.1)
        func measured(_ text: String) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size)]).width
        }
        // Fallback fonts and composed emoji may round differently at the resized point size.
        // Leave a small margin and remeasure every grapheme before wrapping.
        for _ in 0..<12 {
            let glyphWidth = clean.map { measured(String($0)) }.max() ?? 0
            if glyphWidth <= width { break }
            size *= width / glyphWidth * 0.98
        }
        let lineHeight = UIFont.systemFont(ofSize: size).lineHeight
        let maxLines = max(Int(height / lineHeight), 1)
        var rest = Array(clean), lines: [String] = []
        while !rest.isEmpty && lines.count < maxLines {
            var count = 0
            while count < rest.count && measured(String(rest.prefix(count + 1))) <= width + 0.01 { count += 1 }
            guard count > 0 else { break }
            if lines.count == maxLines - 1 && count < rest.count {
                let fitting = count
                while count > 0 && measured(String(rest.prefix(count)) + "…") > width { count -= 1 }
                lines.append(count > 0 ? String(rest.prefix(count)) + "…" : String(rest.prefix(fitting)))
                break
            }
            lines.append(String(rest.prefix(count)))
            rest.removeFirst(count)
        }
        return WideGridTextLayout(text: lines.joined(separator: "\n"), size: size)
    }
}

struct WeekGridWideWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WeekGridWideSettings.kind, provider: WeekGridWideWidgetProvider()) {
            WeekGridWideWidgetEntryView(entry: $0)
        }
        .configurationDisplayName(L10n.format("widget_week_grid_wide_label"))
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
