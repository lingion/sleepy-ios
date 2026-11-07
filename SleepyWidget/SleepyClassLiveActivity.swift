// SleepyClassLiveActivity.swift — 课程实况活动渲染 (v1.0.64)
//
// Live Activity 界面属于 WidgetKit 扩展(ActivityConfiguration 是
// WidgetConfiguration, 不要求独立扩展点) → 挂靠现有 SleepyWidget 扩展,
// 在 WidgetBundle 里并列注册。
//
// 能力上限: 段内倒计时用 Text(timerInterval:) 由系统走字, 长时间不刷新也
// 不会显示过期数值; 段的切换依赖主 App 回前台刷新(无服务端, 无法后台新建)。
//
// iOS 16.1+ 门控: WidgetBundleBuilder 原生支持 #available 分支。

import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct SleepyClassLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepyClassActivityAttributes.self) { ctx in
            lockScreenView(ctx)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    expandedView(ctx)
                }
            } compactLeading: {
                Image(systemName: "book.fill")   // 书本 = 上课语义, 与课表主视觉一致
                .foregroundColor(.white)
            } compactTrailing: {
                if let current = currentEntry(ctx, now: Date()) {
                    Text(timerInterval: max(current.start, Date())...current.end)
                        .monospacedDigit()
                        .foregroundColor(.white)
                }
            } minimal: {
                if let current = currentEntry(ctx, now: Date()) {
                    Text("\(remainingMinutes(current, now: Date()))m")
                        .monospacedDigit()
                        .foregroundColor(.white)
                }
            }
        }
    }

    // MARK: - 锁屏(所有机型可见) / 展开

    @ViewBuilder
    private func lockScreenView(_ ctx: ActivityViewContext<SleepyClassActivityAttributes>)
        -> some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 4) {
            if let current = currentEntry(ctx, now: now) {
                Text(current.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if !current.room.isEmpty {
                        Label(current.room, systemImage: "mappin.and.ellipse")
                            .font(.caption)
                    }
                    Spacer()
                    Text(timerInterval: max(current.start, now)...current.end)
                        .font(.caption)
                        .monospacedDigit()
                }
                progressBar(current, now: now)
                    .padding(.top, 2)
                if let next = ctx.state.entries.first(where: { $0.start >= current.end }) {
                    Label("\(L10n.format("reminder_mode_banner")) → \(next.name)",
                          systemImage: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(L10n.format("reminder_fluid_note"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func expandedView(_ ctx: ActivityViewContext<SleepyClassActivityAttributes>)
        -> some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 6) {
            Text(ctx.state.tableName)
                .font(.subheadline.weight(.semibold))
            if let current = currentEntry(ctx, now: now) {
                Text(current.name)
                    .font(.title3.weight(.semibold))
                HStack(spacing: 8) {
                    if !current.room.isEmpty {
                        Image(systemName: "mappin.and.ellipse")
                        Text(current.room)
                    }
                    Spacer()
                    Text(timerInterval: max(current.start, now)...current.end)
                        .monospacedDigit()
                }
                .font(.subheadline)
                progressBar(current, now: now)
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func progressBar(_ entry: SleepyClassActivityAttributes.Entry,
                             now: Date) -> some View {
        let total = entry.end.timeIntervalSince(entry.start)
        let progress = total > 0 ? min(1, max(0, now.timeIntervalSince(entry.start) / total)) : 0
        ProgressView(value: progress)
            .progressViewStyle(.linear)
    }

    /// 进行中的课(半开区间: 下课瞬间即离开); 无则 nil。
    private func currentEntry(_ ctx: ActivityViewContext<SleepyClassActivityAttributes>,
                              now: Date) -> SleepyClassActivityAttributes.Entry? {
        ctx.state.entries.first { $0.start <= now && now < $0.end }
    }

    private func remainingMinutes(_ entry: SleepyClassActivityAttributes.Entry, now: Date) -> Int {
        max(0, Int(entry.end.timeIntervalSince(now) / 60))
    }
}
