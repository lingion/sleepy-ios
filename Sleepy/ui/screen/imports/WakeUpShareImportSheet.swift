import SwiftUI

/// 仅负责获取服务端分享数据; 成功后由 ImportSheet 走既有预览/确认/落库流程。
@MainActor
final class WakeUpShareImportModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private let client: WakeUpShareClient
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(client: WakeUpShareClient = WakeUpShareClient()) { self.client = client }

    func fetch(_ text: String, onResolved: @escaping (String) -> Void) {
        cancel()
        errorMessage = nil
        isLoading = true
        let requestId = generation
        task = Task {
            do {
                let json = try await client.fetchScheduleJson(text)
                guard !Task.isCancelled, requestId == generation else { return }
                isLoading = false
                task = nil
                onResolved(json)
            } catch {
                guard !Task.isCancelled, requestId == generation else { return }
                isLoading = false
                task = nil
                if !(error is CancellationError) { errorMessage = error.localizedDescription }
            }
        }
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        isLoading = false
    }
}

@MainActor
struct WakeUpShareImportSheet: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    @StateObject private var model: WakeUpShareImportModel
    @State private var input: String
    let onResolved: (String) -> Void
    let onCancel: () -> Void

    init(initialText: String = "", client: WakeUpShareClient = WakeUpShareClient(),
         onResolved: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _input = State(initialValue: initialText)
        _model = StateObject(wrappedValue: WakeUpShareImportModel(client: client))
        self.onResolved = onResolved
        self.onCancel = onCancel
    }

    private func text(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, bundle: LocaleHelper.currentBundle(), value: fallback, comment: "")
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: text("wakeup_share_import_title", "导入 WakeUP 分享口令")) {
                model.cancel()
                onCancel()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(text("wakeup_share_import_hint", "粘贴 WakeUP 分享口令或完整分享文案，联网获取课表后预览。"))
                        .foregroundColor(colors.onSurfaceVariant)
                    TextEditor(text: $input)
                        .frame(minHeight: 140)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .padding(12)
                        .background(colors.surfaceContainer)
                        .cornerRadius(SleepyShapes.large)
                        .disabled(model.isLoading)
                        .accessibilityLabel(text("wakeup_share_input_label", "WakeUP 分享口令"))
                        .accessibilityIdentifier("wakeup_share_input")
                    if let error = model.errorMessage {
                        Text(error)
                            .foregroundColor(colors.onSurface)
                            .accessibilityIdentifier("wakeup_share_error")
                    }
                    if model.isLoading {
                        ProgressView(text("wakeup_share_fetching", "正在获取分享课表…"))
                            .accessibilityIdentifier("wakeup_share_progress")
                        cancelRequestButton
                    } else {
                        fetchButton
                    }
                }
                .padding(16)
            }
        }
        .background(colors.background)
        .onDisappear { model.cancel() }
    }

    @ViewBuilder
    private var cancelRequestButton: some View {
        let button = Button(text("wakeup_share_cancel_request", "取消请求")) { model.cancel() }
            .accessibilityIdentifier("wakeup_share_cancel_request")
        if style == .liquidGlass {
            button.buttonStyle(SleepyPlatformButtonStyle(shape: .capsule))
                .frame(minHeight: 44)
        } else {
            button
        }
    }

    @ViewBuilder
    private var fetchButton: some View {
        let button = Button(text("wakeup_share_fetch", "获取并预览")) {
            model.fetch(input, onResolved: onResolved)
        }
        .tint(colors.primary)
        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("wakeup_share_fetch")
        if style == .liquidGlass {
            button.buttonStyle(SleepyPlatformButtonStyle(prominent: true, shape: .capsule))
                .frame(minHeight: 44)
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }
}
