import SwiftUI
import WidgetKit
import Combine
import GRDB

enum WideGridPreviewStatus { case loading, ready, empty, noTable, unavailable, error }

/// Screen-owned observation and cancellation. No stock courses are substituted for the binding.
@MainActor final class WeekGridWidePreviewModel: ObservableObject {
    @Published private(set) var frames: [WeekGridWideMode: WeekData] = [:]
    @Published private(set) var status: WideGridPreviewStatus = .loading
    @Published private(set) var now = Date()
    private var observation: AnyCancellable?
    private var loadTask: Task<Void, Never>?

    func start() {
        stop()
        guard let repo = WidgetLoader.makeRepo() else { status = .error; return }
        observation = ValueObservation.tracking { db -> [Row] in
            // Observing every row also catches edits with unchanged course/table counts.
            try ["time_tables", "courses", "period_tables", "course_colors"].flatMap {
                try Row.fetchAll(db, sql: "SELECT * FROM \($0)")
            }
        }
        .publisher(in: repo.database.dbQueue)
        .sink(receiveCompletion: { [weak self] result in
            if case .failure = result { self?.status = .error }
        }, receiveValue: { [weak self] _ in self?.refresh() })
    }

    func refresh() {
        loadTask?.cancel()
        frames = [:]
        status = .loading
        loadTask = Task {
            let binding = WidgetBindingStore.get(WeekGridWideSettings.kind)
            let settings = WeekGridWideSettingsStore.read()
            let alias = AppPrefs.shared.isWidgetUseAlias()
            let theme = AppPrefs.shared.getThemeKey()
            let configurations: [WidgetInfo]? = await withCheckedContinuation { continuation in
                WidgetCenter.shared.getCurrentConfigurations { result in
                    continuation.resume(returning: try? result.get())
                }
            }
            guard !Task.isCancelled else { return }
            guard let configurations else { status = .error; return }
            guard configurations.contains(where: { $0.kind == WeekGridWideSettings.kind }) else {
                status = .unavailable; return
            }
            let date = Date()
            let source = await WidgetWeekDataLoader.resolve(WeekGridWideSettings.kind)
            var batch: [WeekGridWideMode: WeekData] = [:]
            for mode in WeekGridWideMode.allCases {
                guard !Task.isCancelled else { return }
                batch[mode] = await WeekGridWideDataLoader.dataForSource(source, mode: mode, now: date)
            }
            guard !Task.isCancelled,
                  binding == WidgetBindingStore.get(WeekGridWideSettings.kind),
                  settings == WeekGridWideSettingsStore.read(), alias == AppPrefs.shared.isWidgetUseAlias(),
                  theme == AppPrefs.shared.getThemeKey() else { return }
            now = date
            frames = batch
            status = source == nil ? .noTable : batch.values.allSatisfy { $0.days.allSatisfy { $0.courses.isEmpty } }
                ? .empty : .ready
        }
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        observation?.cancel()
        observation = nil
    }
}

struct WidgetEditWideGridSection: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var previews = WeekGridWidePreviewModel()
    let scope: WidgetEditScope

    static func appliesTo(kind: String) -> Bool { kind == WeekGridWideSettings.kind }

    var body: some View {
        if Self.appliesTo(kind: scope.kind) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.format("widget_wide_grid_layout")).font(.system(size: 14, weight: .semibold))
                if let message = statusMessage {
                    Text(message).font(.footnote).foregroundColor(colors.onSurfaceVariant)
                        .accessibilityIdentifier("wide-preview-status")
                }
                if style == .liquidGlass {
                    Picker(L10n.format("widget_wide_grid_shapes"), selection: Binding(
                        get: { scope.wideGridSettings.mode },
                        set: { scope.onWideGridSettingsChange(WeekGridWideSettings(
                            mode: $0, labelSide: scope.wideGridSettings.labelSide)) }
                    )) {
                        ForEach(WeekGridWideMode.allCases, id: \.self) { mode in
                            Text(L10n.format(mode.labelKey))
                                .tag(mode)
                                .accessibilityIdentifier("wide-shape-\(mode.rawValue)")
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(colors.primary)
                    .accessibilityIdentifier("wide-shape-picker")
                    preview(for: scope.wideGridSettings.mode)
                } else {
                    ForEach(WeekGridWideMode.allCases, id: \.self) { mode in
                        Button { scope.onWideGridSettingsChange(WeekGridWideSettings(mode: mode,
                            labelSide: scope.wideGridSettings.labelSide)) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    MaterialSelectionIndicator(kind: .radio, selected: scope.wideGridSettings.mode == mode)
                                        .frame(width: 48, height: 48)
                                    Text(L10n.format(mode.labelKey)).font(.system(size: 14, weight: .medium))
                                }
                                preview(for: mode)
                            }
                            .foregroundColor(colors.onSurface)
                            .padding(12)
                            .background(scope.wideGridSettings.mode == mode ? colors.secondaryContainer : colors.surfaceContainer)
                            .cornerRadius(16)
                        }
                        .buttonStyle(SleepyButtonStyle())
                        .accessibilityAddTraits(scope.wideGridSettings.mode == mode ? .isSelected : [])
                        .accessibilityIdentifier("wide-shape-\(mode.rawValue)")
                    }
                }
                if scope.wideGridSettings.mode == .horizontal {
                    if style == .liquidGlass {
                        Picker(L10n.format("widget_wide_grid_layout"), selection: Binding(
                            get: { scope.wideGridSettings.labelSide },
                            set: { scope.onWideGridSettingsChange(WeekGridWideSettings(mode: .horizontal, labelSide: $0)) }
                        )) {
                            ForEach(WeekGridWideLabelSide.allCases, id: \.self) { side in
                                Text(L10n.format(side.labelKey))
                                    .tag(side)
                                    .accessibilityIdentifier("wide-label-\(side.rawValue)")
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .tint(colors.primary)
                        .accessibilityIdentifier("wide-label-picker")
                    } else {
                        ForEach(WeekGridWideLabelSide.allCases, id: \.self) { side in
                            Button { scope.onWideGridSettingsChange(WeekGridWideSettings(mode: .horizontal, labelSide: side)) } label: {
                                HStack(spacing: 12) {
                                    MaterialSelectionIndicator(kind: .radio, selected: scope.wideGridSettings.labelSide == side)
                                        .frame(width: 48, height: 48)
                                    Text(L10n.format(side.labelKey))
                                    Spacer()
                                }
                                .foregroundColor(colors.onSurface).padding(8)
                            }
                            .buttonStyle(SleepyButtonStyle())
                            .accessibilityAddTraits(scope.wideGridSettings.labelSide == side ? .isSelected : [])
                            .accessibilityIdentifier("wide-label-\(side.rawValue)")
                        }
                    }
                }
            }
            .task(id: refreshKey) { previews.start() }
            .onDisappear { previews.stop() }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                if scenePhase == .active { previews.refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: L10n.didChangeNotification)) { _ in
                if scenePhase == .active { previews.refresh() }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                if scenePhase == .active { previews.refresh() }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active { previews.start() } else { previews.stop() }
            }
            .onChange(of: colorScheme) { _ in previews.refresh() }
        }
    }

    @ViewBuilder
    private func preview(for mode: WeekGridWideMode) -> some View {
        if let data = previews.frames[mode] {
            WeekGridWideWidgetEntryView(entry: WeekGridWideWidgetEntry(date: previews.now,
                data: data, settings: WeekGridWideSettings(mode: mode, labelSide: scope.wideGridSettings.labelSide)))
                .environment(\.sleepyWidgetGalleryFamily, .systemMedium)
                .environment(\.sleepyWidgetGalleryDate, previews.now)
                .aspectRatio(329.0 / 158.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .allowsHitTesting(false)
                .accessibilityIdentifier("wide-preview-\(mode.rawValue)")
        } else {
            ZStack {
                if previews.status == .loading { ProgressView() }
                else { Text(statusMessage ?? L10n.format("widget_wide_grid_preview_error")).font(.footnote) }
            }
            .frame(maxWidth: .infinity).aspectRatio(329.0 / 158.0, contentMode: .fit)
        }
    }

    private var refreshKey: String {
        "\(scope.currentBinding ?? 0)|\(scope.useAlias)|\(scope.wideGridSettings.mode)|\(scope.wideGridSettings.labelSide)"
    }

    private var statusMessage: String? {
        switch previews.status {
        case .loading: return L10n.format("loading")
        case .ready: return nil
        case .empty: return L10n.format("widget_wide_grid_empty")
        case .noTable: return L10n.format("widget_create_schedule")
        case .unavailable: return L10n.format("widget_wide_grid_unavailable")
        case .error: return L10n.format("widget_wide_grid_preview_error")
        }
    }
}
