// AboutScreen.swift — ← ui/screen/mine/AboutScreen.kt
// 关于页: App 名+版本 / 反馈 / QQ 群 / 作者 / 源码 / 隐私 / 许可证。
// (1.0.64: 获取更新切片移除 — 分发收敛到 App Store/TestFlight, GitHub 仅源码公开。)

import SwiftUI

struct AboutScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var uiStyle
    let onDismiss: () -> Void
    // ★ v7.10.18 Track D: 长 License 卡拆二级页, AboutScreen 留入口行
    var onOpenLicense: () -> Void = {}

    @State private var snackMessage: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("about_title"), onBack: onDismiss)
            ScrollView {
                VStack(spacing: 0) {
                    // ← 原版本 无横幅恒有 Spacer(24)(名字上方 8+24=32); 1.0.64 更新横幅随功能移除
                    Spacer().frame(height: 24)

                    appNameHeader

                    Group {
                    // Version info card
                    InfoCard(inset: 20) {
                        HStack(spacing: 12) {
                            AndroidSettingsIcon(name: .newReleases, size: 24)
                                .foregroundColor(colors.primary)
                            VStack(alignment: .leading, spacing: SettingsLayout.descriptionGap) {
                                Text(L10n.format("about_version"))
                                    .font(SettingsLayout.headingStyle)
                                    .foregroundColor(colors.onSurface)
                                Text(L10n.format("about_version_detail",
                                                 VersionUtils.currentVersionName, buildCode))
                                    .font(SettingsLayout.descriptionStyle)
                                    .foregroundColor(colors.onSurfaceVariant)
                            }
                        }
                    }
                    Spacer().frame(height: 12)

                    // Feedback card — ← 1.0.51 反馈卡: GitHub Issue / 邮件两个入口
                    //   (FeedbackComposer 已 1:1 移植, 这里只是接上 UI)
                    InfoCard(inset: 20) {
                        HStack(spacing: 12) {
                            AndroidSettingsIcon(name: .bugReport, size: 24)
                                .foregroundColor(colors.primary)
                            VStack(alignment: .leading, spacing: SettingsLayout.descriptionGap) {
                                Text(L10n.format("about_feedback"))
                                    .font(SettingsLayout.headingStyle)
                                    .foregroundColor(colors.onSurface)
                                Text(L10n.format("about_feedback_detail"))
                                    .font(.system(size: 12))
                                    .foregroundColor(colors.onSurfaceVariant)
                            }
                            Spacer()
                            Button { openGitHubFeedback() } label: {
                                AndroidSettingsIcon(name: .openInNew, size: 20)
                                    .frame(width: uiStyle == .classic ? SettingsLayout.minRowHeight : nil,
                                           height: uiStyle == .classic ? SettingsLayout.minRowHeight : nil)
                                    .foregroundColor(colors.primary)
                            }
                            .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 24, compact: true, shape: .circle))
                            .frame(width: SettingsLayout.minRowHeight, height: SettingsLayout.minRowHeight)
                            .accessibilityLabel(L10n.format("about_feedback_github"))
                            Button { openEmailFeedback() } label: {
                                AndroidSettingsIcon(name: .email, size: 20)
                                    .frame(width: uiStyle == .classic ? SettingsLayout.minRowHeight : nil,
                                           height: uiStyle == .classic ? SettingsLayout.minRowHeight : nil)
                                    .foregroundColor(colors.primary)
                            }
                            .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 24, compact: true, shape: .circle))
                            .frame(width: SettingsLayout.minRowHeight, height: SettingsLayout.minRowHeight)
                            .accessibilityLabel(L10n.format("about_feedback_email"))
                        }
                    }
                    Spacer().frame(height: 12)

                    // QQ 群入口: 点卡复制群号并拉起 QQ(群资料卡 → ALT → TIM → QQ 首页 → 加群页 五级降级) ← AboutScreen.kt joinQqGroup
                    InfoCard(inset: 20) {
                        HStack(spacing: 0) {
                            Button(action: joinQqGroup) {
                                HStack(spacing: 12) {
                                    AndroidSettingsIcon(name: .groups, size: 24) // ← Icons.Outlined.Groups 24dp
                                        .foregroundColor(colors.primary)
                                    VStack(alignment: .leading, spacing: SettingsLayout.descriptionGap) {
                                        Text(L10n.format("about_qq_title"))
                                            .font(SettingsLayout.headingStyle)
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
                                AndroidSettingsIcon(name: .contentCopy, size: 20)
                                    .frame(width: uiStyle == .classic ? SettingsLayout.minRowHeight : nil,
                                           height: uiStyle == .classic ? SettingsLayout.minRowHeight : nil)
                                    .foregroundColor(colors.primary)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 24, compact: true, shape: .circle))
                            .frame(width: SettingsLayout.minRowHeight, height: SettingsLayout.minRowHeight)
                            .accessibilityLabel(L10n.format("about_qq_copy_action"))
                        }
                    }
                    Spacer().frame(height: 12)

                    }
                    Group {
                    // Author card
                    InfoCard(inset: 20) {
                        HStack(spacing: 12) {
                            AndroidSettingsIcon(name: .person, size: 24)
                                .foregroundColor(colors.primary)
                            VStack(alignment: .leading, spacing: SettingsLayout.descriptionGap) {
                                Text(L10n.format("about_author"))
                                    .font(SettingsLayout.headingStyle)
                                    .foregroundColor(colors.onSurface)
                                Text(L10n.format("about_author_name"))
                                    .font(SettingsLayout.descriptionStyle)
                                    .foregroundColor(colors.onSurfaceVariant)
                            }
                            Spacer()
                            Button {
                                openURL("https://github.com/lingion")
                            } label: {
                                AndroidSettingsIcon(name: .openInNew, size: 20)
                                    .frame(width: uiStyle == .classic ? SettingsLayout.minRowHeight : nil,
                                           height: uiStyle == .classic ? SettingsLayout.minRowHeight : nil)
                                    .foregroundColor(colors.primary)
                            }
                            .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 24, compact: true, shape: .circle))
                            .frame(width: SettingsLayout.minRowHeight, height: SettingsLayout.minRowHeight)
                            .accessibilityLabel(L10n.format("about_author"))
                        }
                    }
                    Spacer().frame(height: 12)

                    // Source code card
                    InfoCard(inset: 20) {
                        HStack(spacing: 12) {
                            AndroidSettingsIcon(name: .code, size: 24)
                                .foregroundColor(colors.primary)
                            VStack(alignment: .leading, spacing: SettingsLayout.descriptionGap) {
                                Text(L10n.format("about_source"))
                                    .font(SettingsLayout.headingStyle)
                                    .foregroundColor(colors.onSurface)
                                Button {
                                    openURL("https://github.com/lingion/sleepy")
                                } label: {
                                    Text(L10n.format("about_source_url"))
                                        .font(SettingsLayout.descriptionStyle)
                                        .foregroundColor(colors.primary)
                                        .underline()
                                }
                                .buttonStyle(SleepyButtonStyle())
                            }
                            Spacer()
                            Button {
                                openURL("https://github.com/lingion/sleepy")
                            } label: {
                                AndroidSettingsIcon(name: .openInNew, size: 20)
                                    .frame(width: uiStyle == .classic ? SettingsLayout.minRowHeight : nil,
                                           height: uiStyle == .classic ? SettingsLayout.minRowHeight : nil)
                                    .foregroundColor(colors.primary)
                            }
                            .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 24, compact: true, shape: .circle))
                            .frame(width: SettingsLayout.minRowHeight, height: SettingsLayout.minRowHeight)
                            .accessibilityLabel(L10n.format("about_source"))
                        }
                    }
                    Spacer().frame(height: 12)

                    // Privacy policy card — ← v1.0.62 商店审核要求: 应用内可达
                    //   https://sleepy.qdp.qzz.io/privacy (与 web 关于页同源) ← AboutScreen.kt 隐私卡
                    InfoCard(inset: 20) {
                        HStack(spacing: 12) {
                            AndroidSettingsIcon(name: .shield, size: 24) // ← Icons.Outlined.Shield 24dp
                                .foregroundColor(colors.primary)
                            VStack(alignment: .leading, spacing: SettingsLayout.descriptionGap) {
                                Text(L10n.format("about_privacy"))
                                    .font(SettingsLayout.headingStyle)
                                    .foregroundColor(colors.onSurface)
                                Button {
                                    openURL("https://sleepy.qdp.qzz.io/privacy")
                                } label: {
                                    Text(L10n.format("about_privacy_url"))
                                        .font(SettingsLayout.descriptionStyle)
                                        .foregroundColor(colors.primary)
                                        .underline()
                                }
                                .buttonStyle(SleepyButtonStyle())
                            }
                            Spacer()
                            Button {
                                openURL("https://sleepy.qdp.qzz.io/privacy")
                            } label: {
                                AndroidSettingsIcon(name: .openInNew, size: 20) // ← Icons.AutoMirrored.OpenInNew 20dp
                                    .frame(width: uiStyle == .classic ? SettingsLayout.minRowHeight : nil,
                                           height: uiStyle == .classic ? SettingsLayout.minRowHeight : nil)
                                    .foregroundColor(colors.primary)
                            }
                            .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 24, compact: true, shape: .circle))
                            .frame(width: SettingsLayout.minRowHeight, height: SettingsLayout.minRowHeight)
                            .accessibilityLabel(L10n.format("about_privacy"))
                        }
                    }
                    Spacer().frame(height: 12)

                    // License 入口行(v1.0.46 用户令): 长卡拆独立二级页, 这里只留入口
                    InfoCard(inset: 20) {
                        Button(action: onOpenLicense) {
                            // ← 原版本 无前导图标: 标题+副题+尾随 ChevronRight(20dp)
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: SettingsLayout.descriptionGap) {
                                    Text(L10n.format("about_license_title"))
                                        .font(SettingsLayout.headingStyle)
                                        .foregroundColor(colors.onSurface)
                                    Text(L10n.format("about_license_detail"))
                                        .font(.system(size: 12))
                                        .foregroundColor(colors.onSurfaceVariant)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                AndroidMaterialIcon(name: .chevronRight, size: 20)
                                    .frame(width: SettingsLayout.minRowHeight, height: SettingsLayout.minRowHeight)
                                    .foregroundColor(colors.onSurfaceVariant)
                            }
                        }
                        .buttonStyle(SleepyButtonStyle())
                    }
                    Spacer().frame(height: 12)

                    Spacer().frame(height: 32)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .background(colors.background)
        .overlay(alignment: .bottom) {
            if let msg = snackMessage {
                Text(msg)
                    .font(SettingsLayout.descriptionStyle) // ← 原 Snackbar bodyMedium 14
                    // ← G5: 稳定锚点 — QQ 群复制/无邮件客户端提示的结果信号,
                    //   无 id 时 UI 测试无法断言该分支。
                    .accessibilityIdentifier("about_snackbar")
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
    }

    private var buildCode: Int {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap(Int.init) ?? 0
    }

    // App name(← 1.0.51: 纯文字, 无 logo 图; headlineMedium bold 28sp)
    //   间距 1:1 原版本 头部 Column: Spacer(8)+name+Spacer(4)+version+Spacer(24)
    @ViewBuilder
    private var appNameHeader: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 8)
            Text(L10n.format("app_name"))
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(colors.onSurface)
            Spacer().frame(height: 4)
            Text("v\(VersionUtils.currentVersionName)")
                .font(SettingsLayout.descriptionStyle)
                .foregroundColor(colors.onSurfaceVariant)
            Spacer().frame(height: 24)
        }
    }

    private func openURL(_ s: String) {
        if let url = URL(string: s) { UIApplication.shared.open(url) }
    }

    // ← joinQqGroup: 复制群号 → 五级拉起降级链(群资料卡 → ALT → TIM → QQ 首页 → 浏览器加群页)。
    //   原版本 用 getPackageInfo 判定 TIM/QQ 是否安装; iOS canOpenURL 需 QQ scheme 在
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
            openURL("tim://"); launched = true // ← 原 getLaunchIntentForPackage("com.tencent.tim")
        } else if canOpen("mqq://") {
            openURL("mqq://"); launched = true // ← 原 getLaunchIntentForPackage("com.tencent.mobileqq")
        }
        if !launched, canOpen(QqJoin.webFallbackUri(group)) {
            openURL(QqJoin.webFallbackUri(group)); launched = true
        }
        snackMessage = launched ? L10n.format("about_qq_copied") : L10n.format("about_qq_no_qq")
    }

    // ← diagnostic(): 原版本 FeedbackComposer.Diagnostic 的 iOS 填实
    private func diagnostic() -> FeedbackComposer.Diagnostic {
        let scale = UIScreen.main.scale
        let bounds = UIScreen.main.bounds.size
        return FeedbackComposer.Diagnostic(
            versionName: VersionUtils.currentVersionName,
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

    // ← openGitHubFeedback: bug_report.yml 模板 + 诊断块(标题/正文与 原版本 同源)
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

}

// ← InfoCard 已迁移到 Sleepy/ui/component/SettingsCards.swift 共享
