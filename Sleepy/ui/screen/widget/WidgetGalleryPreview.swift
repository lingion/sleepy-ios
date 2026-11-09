// Android v1.0.63 gallery images contain a fixed sample timetable. Reuse the
// iOS production EntryViews with equivalent sample data instead of a skeleton.
import SwiftUI
import WidgetKit

struct WidgetGalleryPreview: View {
    let card: WidgetGalleryCard

    var body: some View {
        let sample = WidgetGallerySampleData.make()
        let size = WidgetGalleryData.previewSize(of: card.previewFamily)
        GeometryReader { geometry in
            let scale = min(geometry.size.width / size.width, geometry.size.height / size.height)
            face(sample)
                .frame(width: size.width, height: size.height)
                .environment(\.sleepyWidgetGalleryFamily, card.previewFamily)
                .environment(\.sleepyWidgetGalleryDate, sample.today.date)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func face(_ sample: WidgetGallerySampleData) -> some View {
        switch card.variant.kind {
        case "WeekGridWidgetV19":
            WeekGridWidgetEntryView(entry: WeekGridWidgetEntry(date: sample.today.date, data: sample.week))
        case "TodayWidgetRV":
            TodayWidgetEntryView(entry: TodayWidgetEntry(date: sample.today.date, data: sample.today))
        case "WeekListWidgetRV":
            WeekListWidgetEntryView(entry: WeekListWidgetEntry(date: sample.today.date, data: sample.week))
        case "WeekViewWidgetRV":
            WeekViewWidgetEntryView(entry: WeekViewWidgetEntry(date: sample.today.date, data: sample.week))
        default:
            TwoDayWidgetEntryView(entry: TwoDayWidgetEntry(date: sample.today.date, data: sample.twoDay))
        }
    }
}

/// Pure sample construction: no provider, loader, repository, or persisted widget binding.
struct WidgetGallerySampleData {
    let today: WidgetData
    let week: WeekData
    let twoDay: TwoDayData

    static func make() -> WidgetGallerySampleData {
        let monday = DateUtils.parseDate("2026-10-19") ?? Date(timeIntervalSince1970: 1_792_368_000)
        let math = "widget_preview_calculus"
        let english = "widget_preview_english"
        let linear = "widget_preview_linear_algebra"
        let sports = "widget_preview_sports"
        let programming = "widget_preview_programming"
        let seminar = "widget_preview_seminar"
        let gym = L10n.t("widget_preview_gym")
        let specifications: [(day: Int, name: String, node: Int, step: Int, room: String, color: String)] = [
            (1, math, 1, 2, "A305", "#D7C8EA"),
            (1, english, 3, 2, "B201", "#EBE9C7"),
            (1, linear, 5, 2, "A305", "#C8EADB"),
            (2, math, 1, 2, "A305", "#D7C8EA"),
            (2, english, 3, 2, "B201", "#EBE9C7"),
            (2, sports, 5, 2, gym, "#C8CFEA"),
            (2, programming, 7, 2, "C102", "#EAC8DC"),
            (3, linear, 1, 2, "A305", "#C8EADB"),
            (3, seminar, 3, 1, "D203", "#EAD9C8"),
            (3, programming, 4, 2, "C102", "#EAC8DC"),
            (4, math, 2, 2, "A305", "#D7C8EA"),
            (4, english, 5, 2, "B201", "#EBE9C7"),
            (5, linear, 1, 2, "A305", "#C8EADB"),
            (5, seminar, 3, 1, "D203", "#EAD9C8"),
            (5, sports, 4, 2, gym, "#C8CFEA")
        ]
        let courses = specifications.enumerated().map { index, spec in
            CourseEntity(groupId: "widget-gallery-\(spec.name)", tableId: -1,
                courseName: L10n.t(spec.name), room: spec.room, day: spec.day,
                startNode: spec.node, step: spec.step, startWeek: 1, endWeek: 16,
                color: spec.color, colorMode: 2, id: Int64(index + 1))
        }
        let days = (1...7).map { day in
            DayData(date: Calendar.isoAddDays(monday, day - 1), dayOfWeek: day,
                courses: courses.filter { $0.day == day }, timeJson: TimeTableUtils.DEFAULT_TIME_JSON)
        }
        let today = WidgetData(date: days[1].date, courses: days[1].courses,
            timeJson: TimeTableUtils.DEFAULT_TIME_JSON, hasTable: true,
            themeMode: "system", isToday: true)
        let week = WeekData(days: days, hasTable: true, themeMode: "system", showDate: true,
            visibleDays: Set(1...5))
        let twoDay = TwoDayData(days: Array(days[1...2]), hasTable: true, themeMode: "system")
        return WidgetGallerySampleData(today: today, week: week, twoDay: twoDay)
    }
}
