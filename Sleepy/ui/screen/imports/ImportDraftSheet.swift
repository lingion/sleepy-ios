// ImportDraftSheet.swift — ← ui/screen/imports/ImportDraftSheet.kt
// 导入草稿恢复 sheet — UI-only representation; persistence belongs to the caller.

import SwiftUI

/// UI-only representation of an import draft; persistence belongs to the caller.
/// ← Android data class ImportDraft(savedAt: String? = null) — explicit init keeps the default.
struct ImportDraftRowModel: Identifiable, Equatable {
    let id: String
    let name: String
    let details: String
    let savedAt: String?

    init(id: String, name: String, details: String, savedAt: String? = nil) {
        self.id = id
        self.name = name
        self.details = details
        self.savedAt = savedAt
    }
}

struct ImportDraftSheet: View {
    let drafts: [ImportDraftRowModel]
    let onDismiss: () -> Void
    let onRestore: (String) -> Void
    let onDelete: (String) -> Void

    @Environment(\.localWakeUpColors) private var colors

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            Text(L10n.t("import_drafts"))
                .font(.system(size: 24, weight: .semibold))   // ← headlineSmall 24sp + SemiBold (Theme.kt:262)
                .foregroundColor(colors.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)

            if drafts.isEmpty {
                VStack {
                    Text(L10n.t("import_drafts_empty"))
                        .font(.system(size: 16))              // ← bodyLarge 16sp
                        .foregroundColor(colors.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity)
                // ← Compose 链 heightIn(min=160).padding(vertical=24): padding 在 minHeight 框内层。
                //   SwiftUI 同构: 先 padding 再外层 minHeight frame(顺序反了总高变 208)。
                .padding(.vertical, 24)                       // ← padding(vertical = 24.dp)
                .frame(minHeight: 160)                        // ← heightIn(min = 160.dp)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(drafts) { draft in
                            ImportDraftRow(
                                draft: draft,
                                onRestore: { onRestore(draft.id) },
                                onDelete: { onDelete(draft.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .frame(maxHeight: 520)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        // ← Android sheetState 默认 rememberModalBottomSheetState(skipPartiallyExpanded = true)
        //   (ImportDraftSheet.kt:49) = 打开即全展开。在组件根声明(与 Android 组件级默认同构),
        //   等价于在调用点 .sheet 上加 .sheetDetents([.large]) 而无需改 ImportSheet.swift;
        //   否则 iOS 默认 medium detent,列表 maxHeight 520 不可达。
        .sheetDetents([.large])
    }
}

private struct ImportDraftRow: View {
    let draft: ImportDraftRowModel
    let onRestore: () -> Void
    let onDelete: () -> Void

    @Environment(\.localWakeUpColors) private var colors

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(draft.name)
                    .font(.system(size: 16, weight: .medium))   // ← titleMedium 16sp Medium
                    .foregroundColor(colors.onSurface)
                Text(draft.details)
                    .font(.system(size: 14))                    // ← bodyMedium 14sp
                    .foregroundColor(colors.onSurfaceVariant)
                    .padding(.top, 2)
                // ← Android draft.savedAt?.takeIf { it.isNotBlank() }: 纯空白串也隐藏
                if let savedAt = draft.savedAt,
                   !savedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(L10n.format("import_draft_saved_at", savedAt))
                        .font(.system(size: 12))                // ← bodySmall 12sp
                        .foregroundColor(colors.onSurfaceVariant)
                        .padding(.top, 4)
                }
            }
            Spacer()
            Button(action: onRestore) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 22, weight: .medium))   // ← Icon size(22.dp)
                    .foregroundColor(colors.primary)
            }
            .accessibilityLabel(Text(L10n.t("import_draft_restore")))
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 22, weight: .medium))   // ← Icon size(22.dp)
                    .foregroundColor(colors.error)              // ← colors.error (主题派生,非固定红)
            }
            .accessibilityLabel(Text(L10n.t("import_draft_delete")))
        }
        .padding(.leading, 16)                                   // ← padding(start = 16
        .padding(.trailing, 8)                                   //    end = 8, 非对称)
        .padding(.vertical, 12)
        .background(colors.surfaceContainer)
        .cornerRadius(16)                                        // ← shapes.large = 16dp
    }
}
