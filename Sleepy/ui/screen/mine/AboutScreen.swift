// AboutScreen.swift — ← ui/screen/mine/AboutScreen.kt + UpdateChangelogDialog.kt
// 关于页: App 名+版本 / 一键更新(检查+changelog+下载 IPA)/作者/源码/许可证。
// 平台差异表#2: Android 下载 APK 自装 → iOS 下载 IPA 后提示重新侧载(install 动作降级)。

import SwiftUI

// ← UpdateUiState sealed class
enum UpdateUiState: Equatable {
    case idle
    case checking
    case noUpdate(String)
    case updateAvailable(version: String, changelog: String, url: String)
    case downloading(Int)
    case installing
    case failed(message: String, version: String, changelog: String, url: String, isCheckFailure: Bool)

    var isActiveDialog: Bool {
        switch self {
        case .updateAvailable, .downloading, .failed, .installing: return true
        default: return false
        }
    }
}

struct AboutScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let onBack: () -> Void

    @State private var uiState: UpdateUiState = .idle
    @State private var downloadTask: Task<Void, Never>? = nil
    @State private var snackMessage: String? = nil
    @State private var downloadedIpa: URL? = nil

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("about_title"), onBack: onBack)
            ScrollView {
                VStack(spacing: 12) {
                    Spacer().frame(height: 24)

                    // App name + icon
                    VStack(spacing: 4) {
                        Spacer().frame(height: 8)
                        Text(L10n.format("app_name"))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(colors.onSurface)
                        Text("v\(UpdateManager.currentVersionName)")
                            .font(.system(size: 14))
                            .foregroundColor(colors.onSurfaceVariant)
                        Spacer().frame(height: 24)
                    }

                    // Version info card
                    InfoCard {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles.rectangle.stack")
                                .font(.system(size: 24))
                                .foregroundColor(colors.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.format("about_version"))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(colors.onSurface)
                                Text(L10n.format("about_version_detail",
                                                 UpdateManager.currentVersionName, buildCode))
                                    .font(.system(size: 14))
                                    .foregroundColor(colors.onSurfaceVariant)
                            }
                        }
                    }

                    // One-click update
                    InfoCard {
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 24))
                                    .foregroundColor(colors.primary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.format("about_update"))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(colors.onSurface)
                                    Text(L10n.format("about_update_detail"))
                                        .font(.system(size: 12))
                                        .foregroundColor(colors.onSurfaceVariant)
                                }
                            }
                            Button(action: checkUpdate) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.down.circle")
                                    Text(isChecking ? L10n.format("about_update_checking")
                                                    : L10n.format("about_update"))
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colors.onPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(colors.primary)
                                .cornerRadius(SleepyShapes.large)
                            }
                            .buttonStyle(.plain)
                            .disabled(isChecking)
                            .accessibilityIdentifier("about_check_update")
                        }
                    }

                    // Author card
                    InfoCard {
                        HStack(spacing: 12) {
                            Image(systemName: "person")
                                .font(.system(size: 24))
                                .foregroundColor(colors.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.format("about_author"))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(colors.onSurface)
                                Text(L10n.format("about_author_name"))
                                    .font(.system(size: 14))
                                    .foregroundColor(colors.onSurfaceVariant)
                            }
                            Spacer()
                            Button {
                                openURL("https://github.com/lingion")
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 20))
                                    .foregroundColor(colors.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Source code card
                    InfoCard {
                        HStack(spacing: 12) {
                            Image(systemName: "curlybraces")
                                .font(.system(size: 24))
                                .foregroundColor(colors.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.format("about_source"))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(colors.onSurface)
                                Button {
                                    openURL("https://github.com/lingion/sleepy")
                                } label: {
                                    Text(L10n.format("about_source_url"))
                                        .font(.system(size: 14))
                                        .foregroundColor(colors.primary)
                                        .underline()
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                            Button {
                                openURL("https://github.com/lingion/sleepy")
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 20))
                                    .foregroundColor(colors.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // License card
                    InfoCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.format("about_license_title"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colors.onSurface)
                            Text(L10n.format("about_license_body"))
                                .font(.system(size: 14))
                                .foregroundColor(colors.onSurfaceVariant)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer().frame(height: 32)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(colors.background)
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
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { snackMessage = nil }
                        }
                    }
            }
        }
        // ← UpdateChangelogDialog
        .sheet(isPresented: Binding(
            get: { uiState.isActiveDialog },
            set: { if !$0 { uiState = .idle } }
        )) {
            UpdateChangelogDialog(state: uiState,
                                  onDismiss: { uiState = .idle },
                                  onDownload: { version, changelog, url in
                                      startDownload(version: version, changelog: changelog, url: url)
                                  },
                                  onCancelDownload: { cancelDownload() },
                                  onRetry: { version, changelog, url in
                                      if case .failed(_, _, _, _, let isCheck) = uiState, isCheck {
                                          checkUpdate()
                                      } else {
                                          startDownload(version: version, changelog: changelog, url: url)
                                      }
                                  })
                .presentationDetents([.medium])
        }
    }

    private var isChecking: Bool {
        if case .checking = uiState { return true }
        return false
    }

    private var buildCode: Int {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap(Int.init) ?? 0
    }

    private func openURL(_ s: String) {
        if let url = URL(string: s) { UIApplication.shared.open(url) }
    }

    // ← checkUpdate
    private func checkUpdate() {
        guard !isChecking else { return }
        uiState = .checking
        Task {
            do {
                let info = try await UpdateManager.fetchUpdateInfo()
                if info.isUpdateAvailable {
                    uiState = .updateAvailable(version: info.version, changelog: info.changelog,
                                               url: info.downloadUrl)
                } else {
                    // NoUpdate → snackbar + 回 Idle
                    snackMessage = L10n.format("about_update_latest", info.version)
                    uiState = .idle
                }
            } catch {
                uiState = .failed(message: error.localizedDescription, version: "", changelog: "",
                                  url: "", isCheckFailure: true)
            }
        }
    }

    // ← startDownload: 下载 IPA;完成 → Installing(= iOS 提示侧载)
    private func startDownload(version: String, changelog: String, url: String) {
        let info = UpdateInfo(version: version, changelog: changelog, downloadUrl: url, isUpdateAvailable: true)
        uiState = .downloading(0)
        downloadTask = Task {
            do {
                let file = try await UpdateManager.downloadIpa(info) { progress in
                    uiState = .downloading(progress)
                }
                downloadedIpa = file
                uiState = .installing
            } catch is CancellationError {
                uiState = .updateAvailable(version: version, changelog: changelog, url: url)
            } catch {
                uiState = .failed(message: error.localizedDescription, version: version,
                                  changelog: changelog, url: url, isCheckFailure: false)
            }
        }
    }

    private func cancelDownload() {
        downloadTask?.cancel()
    }
}

// ← UpdateChangelogDialog
private struct UpdateChangelogDialog: View {
    @Environment(\.localWakeUpColors) private var colors
    let state: UpdateUiState
    let onDismiss: () -> Void
    let onDownload: (String, String, String) -> Void
    let onCancelDownload: () -> Void
    let onRetry: (String, String, String) -> Void

    var body: some View {
        let version = self.version
        let changelog = self.changelog
        let url = self.url
        let progress = self.progress
        let failMsg = self.failMsg

        VStack(alignment: .leading, spacing: 14) {
            Text(dialogTitle(version: version))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(colors.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !failMsg.isEmpty {
                        Text(L10n.format("update_download_failed", failMsg))
                            .font(.system(size: 14))
                            .foregroundColor(colors.error)
                    }
                    if progress >= 0 {
                        ProgressView(value: Double(progress) / 100.0)
                            .tint(colors.primary)
                        Text(L10n.format("update_downloading", progress))
                            .font(.system(size: 12))
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                    // ★ iOS 等价适配(平台差异表#2): 安装动作降级为提示重新侧载
                    if case .installing = state {
                        Text(L10n.format("update_ios_sideload_hint"))
                            .font(.system(size: 14))
                            .foregroundColor(colors.primary)
                    }
                    if !changelog.isEmpty {
                        Text(changelog)
                            .font(.system(size: 12))
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                switch state {
                case .updateAvailable:
                    Button(L10n.format("update_cancel"), action: onDismiss)
                        .foregroundColor(colors.onSurfaceVariant)
                    Button(L10n.format("update_download")) {
                        onDownload(version, changelog, url)
                    }
                    .foregroundColor(colors.primary)
                case .downloading:
                    Button(L10n.format("update_cancel"), action: onCancelDownload)
                        .foregroundColor(colors.primary)
                case .failed:
                    Button(L10n.format("update_cancel"), action: onDismiss)
                        .foregroundColor(colors.onSurfaceVariant)
                    Button(L10n.format("update_retry")) {
                        onRetry(version, changelog, url)
                    }
                    .foregroundColor(colors.primary)
                case .installing:
                    Button(L10n.format("ok"), action: onDismiss)
                        .foregroundColor(colors.primary)
                case .idle, .checking, .noUpdate:
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(colors.surface)
    }

    private var version: String {
        switch state {
        case .updateAvailable(let v, _, _), .failed(_, let v, _, _, _): return v
        default: return ""
        }
    }
    private var changelog: String {
        switch state {
        case .updateAvailable(_, let c, _), .failed(_, _, let c, _, _): return c
        default: return ""
        }
    }
    private var url: String {
        switch state {
        case .updateAvailable(_, _, let u), .failed(_, _, _, let u, _): return u
        default: return ""
        }
    }
    private var progress: Int {
        if case .downloading(let p) = state { return p }
        return -1
    }
    private var failMsg: String {
        if case .failed(let m, _, _, _, _) = state { return m }
        return ""
    }

    private func dialogTitle(version: String) -> String {
        switch state {
        case .installing: return L10n.format("update_ios_sideload_title")
        case .downloading(let p): return L10n.format("update_downloading", p)
        default: return L10n.format("update_found_title", version)
        }
    }
}

// ← InfoCard
private struct InfoCard<Content: View>: View {
    @Environment(\.localWakeUpColors) private var colors
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }
}
