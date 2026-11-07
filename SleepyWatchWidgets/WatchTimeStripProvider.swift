import SwiftUI
import WidgetKit

struct WatchTimeStripEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchTimeStripCore.Snapshot
    let language: String
}

struct WatchTimeStripProvider: TimelineProvider {
    private let calendar = Calendar(identifier: .gregorian)

    func placeholder(in context: Context) -> WatchTimeStripEntry {
        let now = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: Date()) ?? Date()
        let day = calendar.startOfDay(for: now)
        let language = WatchTimeStripPreferencesStore.shared.load().language
        let name = NSLocalizedString("watch_time_strip_display_name",
                                     bundle: LocaleHelper.bundle(for: language), comment: "")
        let items = [(480, 570), (600, 690)].map { start, end in
            WatchAgendaCore.ClassItem(courseName: name, room: "", startLabel: "",
                                      startMin: start, endMin: end,
                                      startDate: day.addingTimeInterval(Double(start * 60)),
                                      endDate: day.addingTimeInterval(Double(end * 60)))
        }
        return WatchTimeStripEntry(date: now,
            snapshot: WatchTimeStripCore.snapshot(now: now, today: items, tomorrow: [], showsTomorrow: false),
            language: language)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchTimeStripEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let now = Date()
        let preferences = WatchTimeStripPreferencesStore.shared.load()
        completion(entry(at: now, agendas: loadAgendas(now: now, preferences: preferences),
                         preferences: preferences))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchTimeStripEntry>) -> Void) {
        let now = Date()
        let preferences = WatchTimeStripPreferencesStore.shared.load()
        guard let agendas = loadAgendas(now: now, preferences: preferences) else {
            completion(Timeline(entries: [entry(at: now, agendas: nil, preferences: preferences)],
                                policy: .after(now.addingTimeInterval(15 * 60))))
            return
        }
        let dates = WatchTimeStripCore.timelineDates(now: now,
            courseBoundaries: agendas.values.flatMap { $0.flatMap { [$0.startDate, $0.endDate] } },
            calendar: calendar)
        var entries: [WatchTimeStripEntry] = []
        for date in dates {
            let next = entry(at: date, agendas: agendas, preferences: preferences)
            if let previous = entries.last,
               next.snapshot.segments.isEmpty,
               next.snapshot.state == previous.snapshot.state,
               next.snapshot.day == previous.snapshot.day,
               date != dates.last {
                continue
            }
            entries.append(next)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date, agendas: [Date: [WatchAgendaCore.ClassItem]]?,
                       preferences: WatchTimeStripPreferences) -> WatchTimeStripEntry {
        guard let agendas = agendas else {
            return WatchTimeStripEntry(date: date, snapshot: .unavailable(at: date),
                                      language: preferences.language)
        }
        let day = calendar.startOfDay(for: date)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        return WatchTimeStripEntry(date: date,
            snapshot: WatchTimeStripCore.snapshot(now: date, today: agendas[day] ?? [],
                tomorrow: agendas[tomorrow] ?? [], showsTomorrow: preferences.showsTomorrow,
                calendar: calendar),
            language: preferences.language)
    }

    private func loadAgendas(now: Date, preferences: WatchTimeStripPreferences)
        -> [Date: [WatchAgendaCore.ClassItem]]? {
        let repo = ScheduleRepository(AppDatabase.getShared())
        guard let table = WidgetTableResolver.resolveCurrentTable(repo),
              let courses = try? repo.getCourses(table.id) else { return nil }
        let transfers = HolidayTransferOps.decodeTransfers(preferences.transfers[table.id] ?? "[]")
        var day = calendar.startOfDay(for: now)
        let horizonDay = calendar.startOfDay(for: now.addingTimeInterval(24 * 60 * 60))
        let lastDay = calendar.date(byAdding: .day, value: 1, to: horizonDay) ?? horizonDay
        var agendas: [Date: [WatchAgendaCore.ClassItem]] = [:]
        // Include tomorrow for every entry, even when a short DST day crosses two midnights.
        while day <= lastDay {
            agendas[day] = WatchAgendaCore.dayItems(table: table, courses: courses, date: day,
                                                   displayMode: "time", transfers: transfers)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return agendas
    }
}
