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
    let onDismiss: () -> Void
    // ★ v7.10.18 Track D: 长 License 卡拆二级页, AboutScreen 留入口行
    var onOpenLicense: () -> Void = {}

    @State private var uiState: UpdateUiState = .idle
    @State private var downloadTask: Task<Void, Never>? = nil
    @State private var snackMessage: String? = nil
    @State private var downloadedIpa: URL? = nil
    // ← 1.0.51: 冷启动更新检查结果(横幅/高亮) + 自动检查开关(持久化 key 同 Android)
    @ObservedObject private var updateNotifier = UpdateNotifier.shared
    @State private var updateCheckEnabled = UpdateCheckPrefs.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("about_title"), onBack: onDismiss)
            ScrollView {
                VStack(spacing: 0) {
                    // ← 1.0.51 UpdateBanner: 仅提醒可见(未被该版本叉掉)时渲染, 点击跳 GitHub Releases tag 页
                    //   (镜像站只代理下载, 网页 UI 渲染不全, 浏览器入口一律走主站; iOS 更新源=lingion/sleepy-ios),
                    //   叉号按版本关闭提醒 ← UpdateNotifier.dismiss(version)
                    if updateNotifier.noticeVisible, let banner = updateNotifier.updateAvailable {
                        Spacer().frame(height: 12)
                        UpdateBanner(
                            version: banner.version,
                            onTap: {
                                openURL("https://github.com/lingion/sleepy-ios/releases/tag/v\(banner.version)")
                            },
                            onDismiss: { updateNotifier.dismiss(version: banner.version) }
                        )
                        Spacer().frame(height: 8)
                    }
                    // ← Android 无横幅时也恒有 Spacer(24): 名字上方 8+24=32, 有横幅时 12+banner+8+24
                    Spacer().frame(height: 24)

                    appNameHeader

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
                    Spacer().frame(height: 12)

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
                                .frame(height: 40)
                                .background(colors.primary)
                                .cornerRadius(20) // ← M3 Button 默认 shape=full-round(胶囊), 40 高 → 圆角 20
                            }
                            .buttonStyle(SleepyButtonStyle())
                            .disabled(isChecking)
                            .accessibilityIdentifier("about_check_update")
                        }
                    }
                    Spacer().frame(height: 12)

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
                            .buttonStyle(SleepyButtonStyle())
                        }
                    }
                    Spacer().frame(height: 12)

                    Group {  // ViewBuilder 上限 10 — 后半段卡片分组(Group 不改变 VStack 布局)
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
                                .buttonStyle(SleepyButtonStyle())
                            }
                            Spacer()
                            Button {
                                openURL("https://github.com/lingion/sleepy")
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 20))
                                    .foregroundColor(colors.primary)
                            }
                            .buttonStyle(SleepyButtonStyle())
                        }
                    }
                    Spacer().frame(height: 12)

                    // Feedback card — ← 1.0.51 反馈卡: GitHub Issue / 邮件两个入口
                    //   (FeedbackComposer 已 1:1 移植, 这里只是接上 UI)
                    InfoCard {
                        HStack(spacing: 12) {
                            Image(systemName: "ant")
                                .font(.system(size: 24))
                                .foregroundColor(colors.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.format("about_feedback"))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(colors.onSurface)
                                Text(L10n.format("about_feedback_detail"))
                                    .font(.system(size: 12))
                                    .foregroundColor(colors.onSurfaceVariant)
                            }
                            Spacer()
                            Button { openGitHubFeedback() } label: {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 20))
                                    .foregroundColor(colors.primary)
                            }
                            .buttonStyle(SleepyButtonStyle())
                            .accessibilityLabel(L10n.format("about_feedback_github"))
                            Button { openEmailFeedback() } label: {
                                Image(systemName: "envelope")
                                    .font(.system(size: 20))
                                    .foregroundColor(colors.primary)
                            }
                            .buttonStyle(SleepyButtonStyle())
                            .accessibilityLabel(L10n.format("about_feedback_email"))
                        }
                    }
                    Spacer().frame(height: 12)

                    // QQ 群入口: 点卡复制群号并拉起 QQ(群资料卡 → ALT → TIM → QQ 首页 → 加群页 五级降级) ← AboutScreen.kt joinQqGroup
                    InfoCard {
                        HStack(spacing: 0) {
                            Button(action: joinQqGroup) {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.3") // ← Icons.Outlined.Groups 24dp
                                        .font(.system(size: 24))
                                        .foregroundColor(colors.primary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(L10n.format("about_qq_title"))
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(colors.onSurface)
                                        Text(L10n.format("about_qq_detail", L10n.format("about_qq_group_number")))
                                            .font(.system(size: 12)) // ← bodySmall
                                            .foregroundColor(colors.onSurfaceVariant)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(SleepyButtonStyle())
                            Button(action: joinQqGroup) { // ← 尾随 ContentCopy IconButton 20dp
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 20))
                                    .foregroundColor(colors.primary)
                                    .padding(8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(SleepyButtonStyle())
                            .accessibilityLabel(L10n.format("about_qq_copy_action"))
                        }
                    }
                    Spacer().frame(height: 12)

                    // License 入口行(v1.0.46 用户令): 长卡拆独立二级页, 这里只留入口
                    InfoCard {
                        Button(action: onOpenLicense) {
                            // ← Android 无前导图标: 标题+副题+尾随 ChevronRight(20dp)
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.format("about_license_title"))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(colors.onSurface)
                                    Text(L10n.format("about_license_detail"))
                                        .font(.system(size: 12))
                                        .foregroundColor(colors.onSurfaceVariant)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 20))
                                    .foregroundColor(colors.onSurfaceVariant)
                            }
                        }
                        .buttonStyle(SleepyButtonStyle())
                    }
                    Spacer().frame(height: 12)

                    // ← 1.0.51 自动检查更新 Toggle: 关闭后冷启动不拉远端, 高亮也立即消失
                    InfoCard {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.format("about_update_check"))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(colors.onSurface)
                                Text(L10n.format("about_update_check_detail"))
                                    .font(.system(size: 12))
                                    .foregroundColor(colors.onSurfaceVariant)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Toggle("", isOn: $updateCheckEnabled)
                                .labelsHidden()
                                .tint(colors.primary) // ← M3 Switch checkedTrack=primary
                                .onChange(of: updateCheckEnabled) { v in
                                    UpdateCheckPrefs.setEnabled(v)
                                    if !v { updateNotifier.clearCache() }
                                }
                        }
                    }

                    Spacer().frame(height: 32)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        // ← 1.0.51: 有更新可用且提醒未被该版本叉掉时页面底色高亮 primary 5% (门控同横幅 = noticeVisible)
        .background(updateNotifier.noticeVisible ? colors.primary.opacity(0.05) : colors.background)
        // Android 在 MainActivity.onCreate 检查; iOS 入口不可改, 由关于页触发(一次进程最多一次)
        .task { updateNotifier.maybeCheckOnStart() }
        .overlay(alignment: .bottom) {
            if let msg = snackMessage {
                Text(msg)
                    .font(.system(size: 14)) // ← Android Snackbar bodyMedium 14
                    .foregroundColor(colors.onSurface)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(colors.surfaceContainerHighest)
                    .cornerRadius(8)
                    .padding(.bottom, 12)
                    .task(id: msg) {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation { snackMessage = nil }
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
                .sheetDetents([.medium])
        }
    }

    private var isChecking: Bool {
        if case .checking = uiState { return true }
        return false
    }

    private var buildCode: Int {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap(Int.init) ?? 0
    }

    // App name(← 1.0.51: 纯文字, 无 logo 图; headlineMedium bold 28sp)
    //   间距 1:1 Android 头部 Column: Spacer(8)+name+Spacer(4)+version+Spacer(24)
    @ViewBuilder
    private var appNameHeader: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 8)
            Text(L10n.format("app_name"))
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(colors.onSurface)
            Spacer().frame(height: 4)
            Text("v\(UpdateManager.currentVersionName)")
                .font(.system(size: 14))
                .foregroundColor(colors.onSurfaceVariant)
            Spacer().frame(height: 24)
        }
    }

    private func openURL(_ s: String) {
        if let url = URL(string: s) { UIApplication.shared.open(url) }
    }

    // ← Android `e.message ?: unknownErrorMessage`: 错误无有效信息时兜底 error_unknown
    private func errorMessage(_ error: Error) -> String {
        let raw = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? L10n.format("error_unknown") : raw
    }

    // ← joinQqGroup: 复制群号 → 五级拉起降级链(群资料卡 → ALT → TIM → QQ 首页 → 浏览器加群页)。
    //   Android 用 getPackageInfo 判定 TIM/QQ 是否安装; iOS canOpenURL 需 QQ scheme 在
    //   Info.plist LSApplicationQueriesSchemes(未配置则恒 false), 失败继续 web 兜底, 语义等价。
    //   全失败(连浏览器都打不开)只提示已复制 ← about_qq_no_qq。
    private func joinQqGroup() {
        let group = L10n.format("about_qq_group_number")
        UIPasteboard.general.string = group
        func canOpen(_ s: String) -> Bool {
            guard let url = URL(string: s) else { return false }
            return UIApplication.shared.canOpenURL(url)
        }
        var launched = false
        // 旧实现的 mqqopensdkapi 通道因缺少官方 key 被 QQ 拒解析, 不启用 ← QqJoin.officialJoinComponentUri
        if canOpen(QqJoin.groupCardUri(group)) {
            openURL(QqJoin.groupCardUri(group)); launched = true
        } else if canOpen(QqJoin.groupCardUriAlt(group)) {
            openURL(QqJoin.groupCardUriAlt(group)); launched = true
        } else if canOpen("tim://") {
            openURL("tim://"); launched = true // ← Android getLaunchIntentForPackage("com.tencent.tim")
        } else if canOpen("mqq://") {
            openURL("mqq://"); launched = true // ← Android getLaunchIntentForPackage("com.tencent.mobileqq")
        }
        if !launched, canOpen(QqJoin.webFallbackUri(group)) {
            openURL(QqJoin.webFallbackUri(group)); launched = true
        }
        snackMessage = launched ? L10n.format("about_qq_copied") : L10n.format("about_qq_no_qq")
    }

    // ← diagnostic(): Android FeedbackComposer.Diagnostic 的 iOS 填实
    private func diagnostic() -> FeedbackComposer.Diagnostic {
        let scale = UIScreen.main.scale
        let bounds = UIScreen.main.bounds.size
        return FeedbackComposer.Diagnostic(
            versionName: UpdateManager.currentVersionName,
            versionCode: buildCode,
            osVersion: UIDevice.current.systemVersion,
            deviceBrand: "Apple",
            deviceModel: UIDevice.current.model,
            resolution: "\(Int(bounds.width * scale))x\(Int(bounds.height * scale))",
            locale: Locale.preferredLanguages.first ?? "en",
            isDebug: isDebugBuild)
    }

    private var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    // ← openGitHubFeedback: bug_report.yml 模板 + 诊断块(标题/正文与 Android 同源)
    private func openGitHubFeedback() {
        openURL(FeedbackComposer.githubIssueUrl(
            title: "[Sleepy] ",
            body: "请描述你遇到的问题或建议：",
            diag: diagnostic(),
            template: "bug_report.yml"))
    }

    // ← openEmailFeedback: 无邮件客户端 → snackbar 改用 GitHub Issue
    private func openEmailFeedback() {
        let uri = FeedbackComposer.mailtoUri(
            subject: L10n.format("about_feedback_email_subject"),
            body: L10n.format("about_feedback_email_body"),
            diag: diagnostic())
        guard let url = URL(string: uri), UIApplication.shared.canOpenURL(url) else {
            snackMessage = L10n.format("about_feedback_no_mail_app")
            return
        }
        UIApplication.shared.open(url)
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
                // ← Android `e.message ?: unknownErrorMessage`: 空/无信息错误兜底 error_unknown
                uiState = .failed(message: errorMessage(error), version: "", changelog: "",
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
                // ← Android `e.message ?: unknownErrorMessage`
                uiState = .failed(message: errorMessage(error), version: version,
                                  changelog: changelog, url: url, isCheckFailure: false)
            }
        }
    }

    private func cancelDownload() {
        downloadTask?.cancel()
    }
}

// ← InfoCard 已迁移到 Sleepy/ui/component/SettingsCards.swift 共享

// ← UpdateBanner(1.0.51): primary 12% 底色横幅, 左整行点击跳 Releases tag 页(主站), 右叉号按版本关闭提醒
private struct UpdateBanner: View {
    @Environment(\.localWakeUpColors) private var colors
    let version: String
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles.rectangle.stack") // ← Icons.Outlined.NewReleases 20dp
                        .font(.system(size: 20))
                        .foregroundColor(colors.primary)
                    Text(L10n.format("about_update_available", "v\(version)"))
                        .font(.system(size: 14, weight: .semibold)) // ← bodyMedium SemiBold primary
                        .foregroundColor(colors.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.up.right.square") // ← Icons.AutoMirrored.OpenInNew 18dp
                        .font(.system(size: 18))
                        .foregroundColor(colors.primary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(SleepyButtonStyle())
            Button(action: onDismiss) { // ← Icons.Outlined.Close IconButton, 默认图标 24dp, contentDescription about_update_dismiss
                Image(systemName: "xmark")
                    .font(.system(size: 24)) // ← Android Icon 无 size modifier = 默认 24dp
                    .foregroundColor(colors.primary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SleepyButtonStyle())
            .accessibilityLabel(L10n.format("about_update_dismiss"))
        }
        .padding(.init(top: 8, leading: 16, bottom: 8, trailing: 4)) // ← Android padding(start16/end4/vert8)
        .background(colors.primary.opacity(0.12))
        .cornerRadius(SleepyShapes.large) // ← clip(shapes.large) = 16dp
    }
}

// ← MarkdownChangelog(1.0.51): changelog 按 Markdown 渲染
//   标题: L1=titleLarge 22 Bold / L2=titleMedium 16 Bold / L3+=titleSmall 14 Bold, 上 10 下 2
//   圆点: "•" primary 12sp + 间距 8, 缩进 6, 行距 2; 段落行距 2; 链接 accent+下划线
private struct MarkdownChangelog: View {
    @Environment(\.localWakeUpColors) private var colors
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(MarkdownBlocks.parse(markdown).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlocks.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    bulletRow(item)
                }
            }
        case .paragraph(let text):
            Text(inlineText(text))
                .font(.system(size: 12)) // ← bodySmall 12sp
                .foregroundColor(colors.onSurfaceVariant)
                .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        // ← titleLarge 22 / titleMedium 16 / titleSmall 14, 均 Bold
        //   Android UpdateChangelogDialog.kt:216 标题用 raw block.text, 不做行内解析
        let size = level == 1 ? 22.0 : (level == 2 ? 16.0 : 14.0)
        Text(text)
            .font(.system(size: size, weight: .bold))
            .foregroundColor(colors.onSurfaceVariant)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private func bulletRow(_ item: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("•")
                .font(.system(size: 12))
                .foregroundColor(colors.primary)
            Spacer().frame(width: 8)
            Text(inlineText(item))
                .font(.system(size: 12))
                .foregroundColor(colors.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 6)
        .padding(.vertical, 2)
    }

    /// ← inlineAnnotated: 确定性 span 渲染(对齐 Android inlineAnnotated), 不再走
    ///   AttributedString(markdown:) 黑盒; 链接截断语义随 Android 正则(首 ')' 截止)
    private func inlineText(_ text: String) -> AttributedString {
        var out = AttributedString()
        for span in MarkdownBlocks.parseInline(text) {
            var a: AttributedString
            switch span {
            case .text(let s): a = AttributedString(s)
            case .bold(let s): a = AttributedString(s); a.font = .system(size: 12, weight: .bold)
            case .code(let s): a = AttributedString(s); a.font = .system(size: 12, design: .monospaced)
            case .link(let s, _): a = AttributedString(s); a.foregroundColor = colors.primary; a.underlineStyle = .single
            }
            a.font = a.font ?? .system(size: 12)
            a.foregroundColor = a.foregroundColor ?? colors.onSurfaceVariant
            out.append(a)
        }
        return out
    }
}
