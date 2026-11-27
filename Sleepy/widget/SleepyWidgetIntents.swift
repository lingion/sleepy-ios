#if compiler(>=5.9)
import AppIntents
import Foundation
import WidgetKit

@available(iOS 17.0, *)
struct TimetableEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("widget_edit_section_schedule")
    )
    static let defaultQuery = TimetableQuery()

    let id: Int64
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

@available(iOS 17.0, *)
struct TimetableQuery: EntityQuery {
    func entities(for identifiers: [Int64]) async throws -> [TimetableEntity] {
        guard let repo = WidgetLoader.makeRepo(),
              let tables = try? repo.getAllTables() else { return [] }
        let wanted = Set(identifiers)
        return tables.filter { wanted.contains($0.id) }
            .map { TimetableEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [TimetableEntity] {
        guard let repo = WidgetLoader.makeRepo(),
              let tables = try? repo.getAllTables() else { return [] }
        return tables.map { TimetableEntity(id: $0.id, name: $0.name) }
    }

    func defaultResult() async -> TimetableEntity? {
        nil
    }
}

@available(iOS 17.0, *)
struct SelectTimetableIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = LocalizedStringResource("widget_edit_section_schedule")
    static let description: IntentDescription? = IntentDescription(LocalizedStringResource("widget_edit_section_schedule"))

    @Parameter(title: LocalizedStringResource("widget_edit_section_schedule"))
    var timetable: TimetableEntity?

    init() {}

    init(timetable: TimetableEntity?) {
        self.timetable = timetable
    }
}

@available(iOS 17.0, *)
struct TodayNavIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource("widget_today_label")
    static let isDiscoverable: Bool = false

    @Parameter(title: "Delta")
    var delta: Int

    @Parameter(title: "Widget Key")
    var widgetKey: String

    init() {
        self.delta = 0
        self.widgetKey = "TodayWidgetRV"
    }

    init(delta: Int, widgetKey: String = "TodayWidgetRV") {
        self.delta = delta
        self.widgetKey = widgetKey
    }

    func perform() async throws -> some IntentResult {
        let key = widgetKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetKey = key.isEmpty ? "TodayWidgetRV" : key
        if delta == 0 {
            TodayDateNavStore.remove(targetKey)
        } else {
            TodayDateNavStore.shift(targetKey, Date(), delta)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "TodayWidgetRV")
        WidgetCenter.shared.reloadTimelines(ofKind: "LockScreenCourseWidget")
        return .result()
    }
}
#endif
