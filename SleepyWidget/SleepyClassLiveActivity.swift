import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct SleepyClassLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepyClassActivityAttributes.self) { context in
            CourseActivityDetails(state: context.state, stale: isStale(context))
                .padding(16)
                .activityBackgroundTint(Color(.secondarySystemBackground))
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(URL(string: "sleepy://open"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    CourseActivityDetails(state: context.state, stale: isStale(context))
                }
            } compactLeading: {
                Image(systemName: isStale(context) ? "clock.badge.exclamationmark" : "book.fill")
                    .accessibilityLabel(L10n.t("live_activity_title"))
            } compactTrailing: {
                if let entry = context.state.entries.first {
                    if isStale(context) {
                        Image(systemName: "arrow.clockwise")
                    } else {
                        ActivityCountdown(entry: entry, upcoming: context.state.phase == "upcoming",
                                          reminderStart: context.state.reminderStart)
                            .frame(maxWidth: 66)
                    }
                }
            } minimal: {
                Image(systemName: isStale(context) ? "clock.badge.exclamationmark" : "book.fill")
                    .accessibilityLabel(L10n.t("live_activity_title"))
            }
            .widgetURL(URL(string: "sleepy://open"))
        }
    }

    private func isStale(_ context: ActivityViewContext<SleepyClassActivityAttributes>) -> Bool {
        if #available(iOS 16.2, *), context.isStale { return true }
        guard let entry = context.state.entries.first else { return true }
        let boundary = context.state.phase == "upcoming" ? entry.start : entry.end
        return Date() >= boundary
    }
}

@available(iOS 16.1, *)
private struct CourseActivityDetails: View {
    let state: SleepyClassActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.tableName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let entry = state.entries.first {
                Text(entry.name).font(.headline).lineLimit(1)
                if !entry.room.isEmpty { Label(entry.room, systemImage: "mappin.and.ellipse").font(.caption).lineLimit(1) }
                // Fixed times remain correct when the app cannot execute. A
                // system timer updates its text, not arbitrary phase branches.
                if state.usesFixedCourseTimes {
                    HStack(spacing: 3) {
                        Text(entry.start, style: .time)
                        Text("–")
                        Text(entry.end, style: .time)
                    }
                    .font(.caption)
                }
                HStack {
                    Text(L10n.t(stale ? "live_activity_stale" : state.phase == "upcoming" ? "live_activity_starts" : "live_activity_ends"))
                        .font(.caption)
                    Spacer()
                    if !stale {
                        ActivityCountdown(entry: entry, upcoming: state.phase == "upcoming",
                                          reminderStart: state.reminderStart)
                    }
                }
                if !stale, state.phase != "upcoming", entry.end > entry.start {
                    ProgressView(timerInterval: entry.start...entry.end, countsDown: false)
                        .labelsHidden()
                }
                if let next = state.entries.dropFirst().first {
                    Text(L10n.format("live_activity_next", next.name)).font(.caption2).lineLimit(1)
                }
                if stale { Text(L10n.t("live_activity_open_to_refresh")).font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }
}

@available(iOS 16.1, *)
private struct ActivityCountdown: View {
    let entry: SleepyClassActivityAttributes.Entry
    let upcoming: Bool
    var reminderStart: Date? = nil

    var body: some View {
        // The range is built from stable endpoints, never from repeated Date() reads near an end boundary.
        let end = upcoming ? entry.start : entry.end
        let start = reminderStart ?? (upcoming ? entry.start.addingTimeInterval(-999 * 60) : min(entry.start, entry.end))
        Text(timerInterval: start...max(start, end), countsDown: true)
            .font(.caption.monospacedDigit())
    }
}
