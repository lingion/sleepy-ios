// PeriodTableShareSheet.swift — ← ui/component/PeriodTableShareSheet.kt (v1.0.56 T11)
// 作息表分享底部弹窗 — 两种格式:
//  - Sleepy 原生格式(纯 P 区块文本): 其他 Sleepy 粘贴导入 → T9 纯作息路径吃回
//  - JSON 格式: 节次时间数据通用形态(WakeUp timeList 语义), 同样可被吃回
// 条目视觉复用 ShareScheduleSheet 的 ShareRow 样式; 选完即走系统分享, 弹窗保持
// 展开(与 ShareScheduleSheet 行为一致, 由用户下滑关闭)。

import SwiftUI

struct PeriodTableShareSheet: View {
    @Environment(\.localWakeUpColors) private var colors
    let periodTable: PeriodTableEntity
    let onDismiss: () -> Void

    @State private var shareSheet: ShareTextPayload? = nil

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.t("period_table_share_sheet_title"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colors.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)   // ← 原 Column 默认 start
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            VStack(spacing: 0) {
                shareRow(icon: .star,              // ← Icons.Outlined.Star
                         title: L10n.t("period_table_share_native_title"),
                         subtitle: L10n.t("period_table_share_native_sub")) {
                    shareSheet = ShareTextPayload(
                        text: SleepyNativeExporter.exportPeriodTableShareText(periodTable),
                        subject: periodTable.name)
                }
                RowDivider()
                shareRow(icon: .code, // ← Icons.Outlined.Code
                         title: L10n.t("period_table_share_json_title"),
                         subtitle: L10n.t("period_table_share_json_sub")) {
                    shareSheet = ShareTextPayload(
                        text: SleepyNativeExporter.exportPeriodTableJson(periodTable),
                        subject: periodTable.name)
                }
            }
        }
        .padding(.bottom, 24)
        .sheetDetents([.medium])
        .sheet(item: $shareSheet) { payload in
            ShareTextPayloadSheet(text: payload.text, subject: payload.subject)
        }
    }

    private func shareRow(icon: AndroidSettingsIcon.Name, title: String, subtitle: String,
                          onClick: @escaping () -> Void) -> some View {
        Button(action: onClick) {
            HStack(spacing: 16) {
                AndroidSettingsIcon(name: icon, size: 24)   // ← 原默认 Icon 24dp
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
        .buttonStyle(SleepyButtonStyle())
    }
}

// 分享载荷(Identifiable for sheet(item:))
private struct ShareTextPayload: Identifiable {
    let id = UUID()
    let text: String
    let subject: String
}

// UIActivityViewController 包装
private struct ShareTextPayloadSheet: UIViewControllerRepresentable {
    let text: String
    let subject: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        vc.setValue(subject, forKey: "subject")
        return vc
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
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
