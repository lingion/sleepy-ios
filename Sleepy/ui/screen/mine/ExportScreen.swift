// ExportScreen.swift — ← ui/screen/mine/ExportScreen.kt
// 导出课表页: WakeUp JSON / WakeUp 分享文本 / ICS 日历。
// 平台映射: MediaStore Downloads + ACTION_SEND → ShareLink/UIActivityViewController +
// 写临时文件(tmp)经 UIActivityViewController 分享(等价适配:iOS 沙箱无公共 Downloads)。

import SwiftUI
import UIKit

struct ExportScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @ObservedObject var viewModel: ScheduleViewModel
    let onBack: () -> Void

    @State private var shareSheet: ShareItem? = nil
    @State private var snackMessage: String? = nil

    var body: some View {
        let state = viewModel.state
        let table = state.currentTable
        let courses = state.courses

        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("export_title"), onBack: onBack)
            if let table = table {
                ScrollView {
                    VStack(spacing: 12) {
                        // 顶部信息卡
                        VStack(alignment: .leading, spacing: 4) {
                            Text(table.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(colors.onPrimaryContainer)
                            Text("\(L10n.format("export_course_count", courses.count)) · \(L10n.format("export_start_date", table.startDate))")
                                .font(.system(size: 14))
                                .foregroundColor(colors.onPrimaryContainer)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colors.primaryContainer)
                        .cornerRadius(SleepyShapes.large)

                        // 格式选项
                        VStack(spacing: 0) {
                            ExportItem(icon: "curlybraces",
                                       title: L10n.format("export_json_title"),
                                       subtitle: L10n.format("export_json_subtitle")) {
                                exportFile(table: table, courses: courses,
                                           ext: "json", mime: "application/json",
                                           content: ScheduleExporter.exportWakeUpJson(table, courses))
                            }
                            RowDivider()
                            ExportItem(icon: "square.and.arrow.up",
                                       title: L10n.format("export_share_title"),
                                       subtitle: L10n.format("export_share_subtitle")) {
                                // ← shareText: 直接分享文本
                                shareSheet = ShareItem(text: ScheduleExporter.exportWakeUpShareText(table, courses),
                                                       subject: table.name, url: nil)
                                snackMessage = L10n.format("export_copied_hint")
                            }
                            RowDivider()
                            ExportItem(icon: "calendar",
                                       title: L10n.format("export_ics_title"),
                                       subtitle: L10n.format("export_ics_subtitle")) {
                                exportFile(table: table, courses: courses,
                                           ext: "ics", mime: "text/calendar",
                                           content: ScheduleExporter.exportIcs(table, courses))
                            }
                        }
                        .background(colors.surfaceContainer)
                        .cornerRadius(SleepyShapes.large)
                    }
                    .padding(16)
                }
            } else {
                Text(L10n.format("export_no_table"))
                    .foregroundColor(colors.onSurfaceVariant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(colors.background)
        // ← snackbar 等价
        .overlay(alignment: .bottom) {
            if let msg = snackMessage {
                Text(msg)
                    .font(.system(size: 13))
                    .foregroundColor(colors.onSurface)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(colors.surfaceContainerHighest)
                    .cornerRadius(8)
                    .padding(.bottom, 12)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { snackMessage = nil }
                        }
                    }
            }
        }
        .sheet(item: $shareSheet) { item in
            ShareSheet(text: item.text, subject: item.subject, url: item.url)
        }
    }

    // ← exportAndShare: 写临时文件 + 分享
    private func exportFile(table: TimeTableEntity, courses: [CourseEntity],
                            ext: String, mime: String, content: String) {
        let fileName = "sleepy_\(table.name)_\(Self.stamp()).\(ext)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try content.data(using: .utf8)?.write(to: url)
            shareSheet = ShareItem(text: nil, subject: table.name, url: url)
            snackMessage = L10n.format("export_saved_to", fileName)
        } catch {
            snackMessage = L10n.format("export_failed")
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}

// 分享载荷(Identifiable for sheet(item:))
private struct ShareItem: Identifiable {
    let id = UUID()
    let text: String?
    let subject: String
    let url: URL?
}

// UIActivityViewController 包装(← Intent.createChooser)
private struct ShareSheet: UIViewControllerRepresentable {
    let text: String?
    let subject: String
    let url: URL?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = []
        if let text = text { items.append(text) }
        if let url = url { items.append(url) }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.setValue(subject, forKey: "subject")
        return vc
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// ← ExportItem
private struct ExportItem: View {
    @Environment(\.localWakeUpColors) private var colors
    let icon: String
    let title: String
    let subtitle: String
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(colors.onPrimaryContainer)
                    .frame(width: 44, height: 44)
                    .background(colors.primaryContainer)
                    .cornerRadius(SleepyShapes.medium)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onSurface)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }
}

private struct RowDivider: View {
    @Environment(\.localWakeUpColors) private var colors
    var body: some View {
        Rectangle()
            .fill(colors.outlineVariant.opacity(SleepyTheme.Alpha.hairline))
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }
}
