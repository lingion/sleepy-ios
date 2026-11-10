// ShareScheduleSheet.swift — ← ui/component/ShareScheduleSheet.kt (v7.10.7)
// 顶栏分享按钮的格式选择底部弹层 — 沿用导出页格式:
// WakeUp JSON / 分享文本(原生 marker 格式,同第 4 项) / ICS 日历。条目视觉与
// 导出操作全部复用
// ExportScreen 的现成实现,选中即走系统分享,弹层保持展开(用户下滑关闭)。

import SwiftUI
import UIKit

struct ShareScheduleSheet: View {
    @Environment(\.localWakeUpColors) private var colors
    @ScaledMetric(relativeTo: .headline) private var headingSize: CGFloat = 16
    let table: TimeTableEntity
    let courses: [CourseEntity]
    let onDismiss: () -> Void

    @State private var shareSheet: SharePayload? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text(L10n.format("share_sheet_title"))
                    .font(.system(size: headingSize, weight: .semibold))
                    .foregroundColor(colors.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)   // ← 原 Column 默认 start 对齐(VStack 默认 center 会把标题居中)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                VStack(spacing: 0) {
                    ShareRow(icon: "curlybraces",
                             title: L10n.format("export_json_title"),
                             subtitle: L10n.format("export_json_subtitle")) {
                        exportFile(ext: "json", mime: "application/json",
                                   content: ScheduleExporter.exportWakeUpJson(table, courses))
                    }
                    .accessibilityIdentifier("share_format_json")
                    ShareRowDivider()
                    ShareRow(icon: "square.and.arrow.up",
                             title: L10n.format("export_share_title"),
                             subtitle: L10n.format("export_share_subtitle")) {
                        // ← 原版本 ShareScheduleSheet.kt:95 — 与第 4 项同为原生分享文本
                        //   (原版本 v1.0.61 弹层从不提供 WakeUp URL 编码 JSON 这一格式)
                        shareSheet = SharePayload(
                            text: SleepyNativeExporter.exportShareText(
                                tableName: table.name, startDate: table.startDate,
                                maxWeek: table.maxWeek, nodesPerDay: table.nodesPerDay,
                                timeJson: table.timeJson, courses: courses, importSourceJson: table.importSourceJson),
                            subject: table.name, url: nil)
                    }
                    .accessibilityIdentifier("share_format_text")
                    ShareRowDivider()
                    ShareRow(icon: "calendar",
                             title: L10n.format("export_ics_title"),
                             subtitle: L10n.format("export_ics_subtitle")) {
                        exportFile(ext: "ics", mime: "text/calendar",
                                   content: ScheduleExporter.exportIcs(table, courses,
                                       transfers: AppPrefs.shared.getHolidayTransfers(table.id)))
                    }
                    .accessibilityIdentifier("share_format_ics")
                    ShareRowDivider()
                    // v7.10.7 第 4 项: Sleepy 原生格式 — marker 包裹 + 无 chk(IM 场景最小体积)
                    ShareRow(icon: "star",
                             title: L10n.format("export_native_title"),
                             subtitle: L10n.format("export_native_subtitle")) {
                        shareSheet = SharePayload(
                            text: SleepyNativeExporter.exportShareText(
                                tableName: table.name, startDate: table.startDate,
                                maxWeek: table.maxWeek, nodesPerDay: table.nodesPerDay,
                                timeJson: table.timeJson, courses: courses, importSourceJson: table.importSourceJson),
                            subject: table.name, url: nil)
                    }
                    .accessibilityIdentifier("share_format_native")
                }
            }
            .padding(.bottom, 24)
        }
        .sheetDetents([.medium, .large])
        // 有意差异: 原 containerColor = colors.surface,iOS 用系统弹层背景;条目图标 Material outlined → SF Symbols
        .sheet(item: $shareSheet) { item in
            SharePayloadSheet(text: item.text, subject: item.subject, url: item.url)
                .onAppear {
                    // 成就：分享弹窗显示
                    AchievementTracker.shared.checkShareSuccess()
                }
        }
    }

    // ← exportAndShare: 写临时文件 + 分享
    private func exportFile(ext: String, mime: String, content: String) {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        let fileName = "sleepy_\(table.name)_\(f.string(from: Date())).\(ext)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        if (try? content.data(using: .utf8)?.write(to: url)) != nil {
            shareSheet = SharePayload(text: nil, subject: table.name, url: url)
        }
    }
}

// 分享载荷(Identifiable for sheet(item:))
private struct SharePayload: Identifiable {
    let id = UUID()
    let text: String?
    let subject: String
    let url: URL?
}

// UIActivityViewController 包装
private struct SharePayloadSheet: UIViewControllerRepresentable {
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

// 弹层条目(视觉对齐 ExportScreen ExportItem)
private struct ShareRow: View {
    @Environment(\.localWakeUpColors) private var colors
    @ScaledMetric(relativeTo: .subheadline) private var titleSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var subtitleSize: CGFloat = 12
    let icon: String
    let title: String
    let subtitle: String
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 16) {
                Group {
                    switch icon {
                    case "curlybraces": AndroidSettingsIcon(name: .code, size: 24)
                    case "square.and.arrow.up": AndroidSettingsIcon(name: .share, size: 24)
                    case "calendar": AndroidMaterialIcon(name: .calendarMonth, size: 24)
                    case "star": AndroidSettingsIcon(name: .star, size: 24)
                    default: Image(systemName: icon).font(.system(size: 24))
                    }
                }   // ← M3 Icon 默认 24dp(原 ExportItem 未覆写 size),此前 20
                    .foregroundColor(colors.onPrimaryContainer)
                    .frame(width: 44, height: 44)
                    .background(colors.primaryContainer)
                    .cornerRadius(SleepyShapes.medium)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: titleSize, weight: .medium))
                        .foregroundColor(colors.onSurface)
                    Text(subtitle)
                        .font(.system(size: subtitleSize))
                        .foregroundColor(colors.onSurfaceVariant)
                        .multilineTextAlignment(.leading)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(SleepyButtonStyle())
    }
}

private struct ShareRowDivider: View {
    @Environment(\.localWakeUpColors) private var colors
    var body: some View {
        Rectangle()
            .fill(colors.outlineVariant.opacity(SleepyTheme.Alpha.hairline))
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }
}
