// PendingPolicyBanner.swift — ← ui/screen/mine/PendingPolicyBanner.kt
// 甲案(设计文档 §4.2) 待执行提醒 Banner — 用户登记策略后编辑页常驻。
//
// 不变量 (§4.2):
//  - 点「修改」= 重新弹三选项(不清空作息草稿)
//  - 作息草稿再次变化 → 策略作废(updateDraft 内自动失效), Banner 随 pendingPolicy==NONE 消失
//
// iOS 端 SchedulePolicy 由 ScheduleEditPolicyState.swift 定义(2026-10 期间同源移植
// 已落地), enum 名称为 .none / .detachCopy / .createNew / .sync。

import SwiftUI

struct PendingPolicyBanner: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    let policy: SchedulePolicy
    let onModify: () -> Void

    var body: some View {
        if policy == .none {
            EmptyView()
        } else {
            HStack(spacing: 8) {
                AndroidSettingsIcon(name: .info, size: 18)
                    .foregroundColor(colors.onSecondaryContainer)
                    .frame(height: 18)
                Text(L10n.format("schedule_conflict_banner_format", policyText))
                    .font(.system(size: 14))   // ← 原 bodyMedium 14sp
                    .foregroundColor(colors.onSecondaryContainer)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onModify) {
                    Text(L10n.t("schedule_conflict_banner_modify"))
                        .font(.system(size: 14, weight: .semibold))   // ← labelLarge SemiBold
                        .foregroundColor(colors.primary)
                        .padding(.horizontal, style == .classic ? 12 : 0)
                        .padding(.vertical, style == .classic ? 6 : 0)
                        .frame(minHeight: style == .classic ? 48 : nil)
                }
                .buttonStyle(SleepyPlatformButtonStyle())
                .tint(colors.primary)
                .frame(minHeight: 48)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(colors.secondaryContainer)
            .cornerRadius(SleepyShapes.large)
        }
    }

    private var policyText: String {
        switch policy {
        case .detachCopy: return L10n.t("schedule_conflict_option_detach_title")
        case .createNew:  return L10n.t("schedule_conflict_option_create_title")
        case .sync:       return L10n.t("schedule_conflict_option_sync_sub_only")
        case .none:       return ""
        }
    }
}
