// JwImportFlow.swift — ← ui/screen/imports/JwImportActivity.kt (v1.0.61, 1040 行)
// 教务直连导入主屏: 学校选择 → WebView 登录抓 HTML → 解析 → 预览 → 配置确认 → 落库。
// Activity+Stage sealed → NavigationStack-less 状态机 View。
//
// v1.0.61 全对齐(F080): Preview stage + 追加模式(applyImportPreview)、草稿全生命周期
// (save/update/delete + incomingDraftId 恢复 + phase 映射)、ExitDraftState 退出确认接线
// (issue#39 静默丢进度防御)、第三 Tab「作息表」(v1.0.56 T6/T10, -1 合成项自动建表)、
// effectiveRowsForConfirm 绑表真源校验 (2026-09-20 误报修复)、smartConfig 播种/线程化
// (issue#28 P2)、错误 AlertDialog(知道了/导出排查全量包 + 进度卡, ← exportDiagnosticDump)、
// onCaptureError 六态映射、errorMsg 阶段切换清零 (#27)、ConfigureConfirm 返回保留课程、
// 解析失败文案补 jw_parse_failed_hint 后缀、DiagMapper UNKNOWN_EMPTY 保留网络提示尾。

import Foundation
import SwiftUI
import WebKit

enum JwStage: Int, Comparable {
    case selectSchool = 0
    case webViewLogin = 1
    case preview = 2
    case configureConfirm = 3

    static func < (lhs: JwStage, rhs: JwStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// 与 原版本 Regex("""^...$""").matches 同语义的整串匹配。
private func jwMatchesFull(_ regex: NSRegularExpression, _ s: String) -> Bool {
    let range = NSRange(s.startIndex..., in: s)
    guard let m = regex.firstMatch(in: s, range: range) else { return false }
    return m.range == range
}

private func jwIsBlank(_ s: String) -> Bool {
    s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

private let jwDateRegex = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}$"#)
private let jwHmRegex = try! NSRegularExpression(pattern: #"^\d{2}:\d{2}$"#)

struct JwImportFlow: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.dismiss) private var dismiss
    let onFinish: () -> Void

    // ← EXTRA_DRAFT_ID: 草稿恢复入口。SleepyApp 侧注入待集成者接线(见交付 needs_shared_wiring)。
    var incomingDraftId: String? = nil
    // activeImport 变化外抛(← issue#39 防御延伸): sheet 宿主可据此
    // .interactiveDismissDisabled(flag) 封掉下滑关闭手势绕过退出确认。默认 nil 零行为变化。
    var onActiveImportChanged: ((Bool) -> Void)? = nil
    // 下滑关闭尝试外抛回调 (当处于有进度态 interactiveDismissDisabled(true) 触发)
    var onDismissAttempt: (() -> Void)? = nil

    @StateObject private var jwViewModel = JwImportViewModel()
    // ← SleepyApp.get().importDraftRepository: iOS 无 app 级单例, 自装配同库仓储。
    private let draftRepository = ImportDraftRepository(AppDatabase.getShared())

    @State private var selectedSchool: JwSchoolInfo? = nil
    @State private var stage: JwStage = .selectSchool
    @State private var isNavigatingForward = true
    @State private var errorMsg: String? = nil
    @State private var statusMsg: String? = nil
    @State private var importFinished = false
    @State private var isApplying = false
    // ← importPreview / pendingMode: 预览 → 追加/覆盖/新课表 五模式共用通道
    @State private var importPreview: ImportPreview? = nil
    @State private var pendingMode: ImportApplyMode = .importAsNew
    // ← exitDraftState: issue#39 退出确认防御(reducer 已移植, 本文件接线)
    @State private var exitDraftState = ExitDraftState()
    // 排查全量包导出: 错误弹窗「导出排查全量包」→ JwCaptureDump 落 zip
    @State private var lastCaptureResult: FrameCaptureResult? = nil
    @State private var webViewForDump: WebViewCoordinator? = nil
    @State private var dumpProgress: DiagDumpProgress? = nil
    // 解析后的课程暂存 + 配置确认状态
    @State private var parsedCourses: [JwCourse] = []
    @State private var parsedSchool: JwSchoolInfo? = nil
    @State private var draftId: String? = nil
    @State private var configStartDate = ""
    @State private var configUsedDefaultTimes = false
    @State private var configTimeJson = ""
    @State private var configRows: [TimeTableUtils.TimeSlotRow] = []
    // issue#28 P2 / issue#23 T5: 智慧节次配置播种(解析/草稿恢复两个入口)
    @State private var configSmartConfig = SmartPeriodConfig()
    // v1.0.56 T6/T10: 第三 Tab「作息表」绑定选择; -1 = 本次导入自动建表(合成项),
    // nil = 未绑定(节次只作课表内置), >0 = 绑定既有表。
    @State private var configBindPeriodTableId: Int64? = nil
    // v1.0.56 第三 Tab 数据源(← scheduleViewModel.allPeriodTables)
    @State private var periodTables: [PeriodTableEntity] = []
    // 课表名 — 默认 jw_import_title(校名)模板, 用户可编辑; 与 原版本 ConfigureConfirm
    // AlertDialog 里 OutlinedTextField 一致。
    @State private var configTableName = ""
    // confirmError: 留在确认框内联展示(2026-09-20: 只标红出错字段, 不上全局横幅)
    @State private var confirmError: String? = nil
    // ← catalogNotice: 选校准入确认(未验证/待适配条目点进前的告知弹窗)
    //   ← 原 `var catalogNotice by remember { mutableStateOf<JwSchoolInfo?>(null) }`
    @State private var catalogNotice: JwSchoolInfo? = nil
    // ← reportDialogSchool: 未验证学校导入成功后的报告弹窗(2026-10-18 离线回路)
    //   ← 原 `var reportDialogSchool by remember { mutableStateOf<JwSchoolInfo?>(null) }`
    @State private var reportDialogSchool: JwSchoolInfo? = nil

    var body: some View {
        ZStack {
            content

            // 退出确认弹窗 ← ExitDraftConfirmationDialog(遮罩轻点 = 继续)
            if exitDraftState.confirmationVisible {
                ExitDraftConfirmationDialog(
                    onContinue: { handleExitChoice(.continueImport) },
                    onKeepDraft: { handleExitChoice(.keepDraft) },
                    onDeleteDraft: { handleExitChoice(.deleteDraft) })
                    .transition(.opacity)
                    .zIndex(2)
            }

            // ← 选校准入确认(未验证/待适配条目点进前)
            //   ← 原 `catalogNotice?.let { school -> AlertDialog(...) }`
            if let school = catalogNotice {
                JwCatalogNoticeDialog(
                    school: school,
                    onDismiss: { catalogNotice = nil },
                    onConfirm: {
                        catalogNotice = nil
                        // mayTry 才有"仍要尝试"这条路; 不可导入的条目确认键只是关闭
                        if school.isUnverified && school.canImport {
                            selectedSchool = school
                            exitDraftState.activeImport = true
                            stage = .webViewLogin
                        }
                    })
                    .transition(.opacity)
                    .zIndex(3)
            }

            // ← 导入成功报告弹窗(未验证学校 → 生成可粘贴报告文本)
            //   ← 原 `reportDialogSchool?.let { school -> AlertDialog(...) }`
            if let school = reportDialogSchool {
                JwImportReportDialog(
                    school: school,
                    courseCount: parsedCourses.count,
                    onDismiss: { closeReportDialog() },
                    onCopyReport: { copyTextToClipboard(currentReportText()) },
                    onJoinQq: { launchQqGroupJoin() })
                    .transition(.opacity)
                    .zIndex(4)
            }

            // ← 错误提示统一 AlertDialog 双按钮 (2026-09-18 用户: 全 app 报错必须是弹窗,
            //   确定 + 导出排查全量包 — 学生把包发给开发者, 免来回截图问诊)。
            //   旧「可点关闭横幅」不是 原版本 等价面, 已替换。
            if let msg = errorMsg {
                JwErrorDialog(
                    message: msg,
                    dumpProgress: dumpProgress,
                    onDismiss: { errorMsg = nil },
                    onExport: { exportDiagnosticDump(parsedSchool ?? selectedSchool) })
                    .zIndex(3)
            }
            // 状态提示(底部)
            if let msg = statusMsg {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.system(size: 14)) // ← 原 Snackbar bodyMedium 14
                        .foregroundColor(colors.onSurface)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(colors.surfaceContainerHighest)
                        .cornerRadius(8)
                        .padding(.bottom, 16)
                }
                .zIndex(1)
            }
        }
        .onSheetDismissAttempt {
            handleDismissAttempt()
        }
        .onAppear {
            // F084: 流程「新进入」= Activity 重建 → saveable 状态清零。
            //   外层 ZStack 身份在 stage 切换中稳定, onAppear 每次流程呈现只跑一次,
            //   WebView 往返(不重挂外层)因此保留搜索词/展开/滚动 — 与 rememberSaveable 同语义。
            SchoolSelectStateStore.shared.resetForNewEntry()
            if importFinished { finishFlow() }
            restoreIncomingDraftIfNeeded()
        }
        .onChange(of: importFinished) { finished in
            if finished { finishFlow() }
        }
        // #27: 红条此前只置不清, 报错后必须退出页面才消失。阶段一切换即清零。
        //    ← LaunchedEffect(stage) { errorMsg = null }
        .onChange(of: stage) { _ in errorMsg = nil }
        // issue#39: activeImport 翻转外抛给 sheet 宿主(交互下滑关闭闸门用)
        .onChange(of: exitDraftState.activeImport) { active in
            onActiveImportChanged?(active)
        }
    }

    private var stageTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: isNavigatingForward ? .trailing : .leading)),
            removal: .opacity.combined(with: .move(edge: isNavigatingForward ? .leading : .trailing))
        )
    }

    private func navigateToStage(_ newStage: JwStage) {
        let forward = newStage >= stage
        isNavigatingForward = forward
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            stage = newStage
        }
    }

    private func handleDismissAttempt() {
        if exitDraftState.activeImport {
            requestExit()
        }
        onDismissAttempt?()
    }

    private func handleBackFromWebView() {
        if draftId != nil || !parsedCourses.isEmpty {
            requestExit()
        } else {
            exitDraftState.activeImport = false
            navigateToStage(.selectSchool)
        }
    }

    @ViewBuilder
    private var content: some View {
        if importFinished {
            EmptyView()   // LaunchedEffect(finish) → onFinish 已由 onChange 触发
        } else {
            ZStack {
                switch stage {
                case .selectSchool:
                    SchoolSelectScreen(onSchoolSelected: { school in
                        if jwIsBlank(school.url) {
                            errorMsg = L10n.format("jw_no_url")
                            return
                        }
                        selectedSchool = school
                        // ← activeImport=true: 选校即进入"有进度"态, 退出须走确认(issue#39)
                        exitDraftState.activeImport = true
                        navigateToStage(.webViewLogin)
                    }, onDismiss: { requestExit() })
                    .transition(stageTransition)
                    .zIndex(stage == .selectSchool ? 1 : 0)

                case .webViewLogin:
                    if let school = selectedSchool {
                        JwWebViewLoginScreen(
                            school: school,
                            onHtmlCaptured: onHtmlCaptured,
                            onBack: { handleBackFromWebView() },
                            onDismiss: { requestExit() },
                            onWebViewReady: { coordinator in
                                // 排查包导出通道(← onWebViewReady → webViewForDump)
                                webViewForDump = coordinator
                            },
                            onCaptureError: { result, hint in
                                handleCaptureError(result, hint)
                            })
                            .transition(stageTransition)
                            .zIndex(stage == .webViewLogin ? 1 : 0)
                    } else {
                        Color.clear.onAppear { navigateToStage(.selectSchool) }
                    }

                case .preview:
                    if !parsedCourses.isEmpty {
                        Group {
                            if let preview = importPreview {
                                JwImportPreviewDialog(preview: preview,
                                                      isApplying: isApplying,
                                                      onDismiss: { requestExit() },
                                                      onApply: onPreviewApply)
                            } else {
                                ProgressView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .task(id: parsedCourses.count) { rebuildPreview() }
                        .transition(stageTransition)
                        .zIndex(stage == .preview ? 1 : 0)
                    } else {
                        Color.clear.onAppear { navigateToStage(.webViewLogin) }
                    }

                case .configureConfirm:
                    if !parsedCourses.isEmpty && parsedSchool != nil {
                        configureConfirmSheet
                            .transition(stageTransition)
                            .zIndex(stage == .configureConfirm ? 1 : 0)
                    } else {
                        Color.clear.onAppear {
                            navigateToStage(.webViewLogin)
                            parsedCourses = []
                        }
                    }
                }
            }
        }
    }

    // MARK: - 退出 / 草稿生命周期 (← requestExit / checkpointDraft / handleExitChoice / completeImport)

    /// F084: 流程真正结束(← Activity finish) → 共享选校状态清零后外抛 onFinish。
    /// 所有退出通路(完成导入 / 保留草稿 / 删除草稿 / 无进度直接退)统一走这里;
    /// WebView 往返不调本函数, 故搜索词/展开/滚动跨 stage 保留(rememberSaveable 语义)。
    private func finishFlow() {
        SchoolSelectStateStore.shared.resetForNewEntry()
        onFinish()
    }

    private func requestExit() {
        if isApplying { return }
        let result = reduceExitDraftState(exitDraftState, .requestExit)
        exitDraftState = result.state
        if result.outcome == .finishDirectly { finishFlow() }
    }

    private func handleExitChoice(_ choice: ExitDraftChoice) {
        let result = reduceExitDraftState(exitDraftState, .choose(choice))
        exitDraftState = result.state
        switch result.outcome {
        case .keepDraft:
            guard let snapshot = currentDraftSnapshot() else { finishFlow(); return }
            if draftId == nil {
                draftId = try? draftRepository.save(snapshot, sourceType: "jw",
                                                    sourceUrl: snapshot.school.url)
            } else {
                try? draftRepository.update(draftId!, snapshot)
            }
            finishFlow()
        case .deleteDraft:
            if let id = draftId { try? draftRepository.delete(id) }
            finishFlow()
        case .none, .finishDirectly:
            break
        }
    }

    private func currentDraftSnapshot() -> JwImportDraftSnapshot? {
        guard let school = selectedSchool ?? parsedSchool else { return nil }
        return JwImportDraftSnapshot(
            school: school,
            courses: parsedCourses,
            periods: configRows.map { JwImportDraftPeriod(node: $0.node, start: $0.start, end: $0.end) },
            termStartDate: configStartDate,
            tableName: configTableName,
            smartConfigJson: encodeSmartConfigJson(configSmartConfig),
            usedDefaultTimes: configUsedDefaultTimes,
            phase: parsedCourses.isEmpty ? .webViewLogin : .configureConfirm)
    }

    /// 每次日期/课表名/行/智慧配置变化即快照落草稿(← checkpointDraft); 无 draftId 不建。
    private func checkpointDraft() {
        guard let id = draftId, let snapshot = currentDraftSnapshot() else { return }
        try? draftRepository.update(id, snapshot)
    }

    private func completeImport() {
        if let id = draftId { try? draftRepository.delete(id) }
        importFinished = true
        exitDraftState.activeImport = false
    }

    // MARK: - 离线报告回路 (2026-10-18, ← 原 finishOrReport / copyTextToClipboard / launchQqGroupJoin)

    /// 未验证学校导入成功 → 先弹报告弹窗(复制文本 + 拉起 QQ 群粘贴);
    /// 已支持学校维持原静默 finish, 零额外打扰。
    /// ← 原 `suspend fun finishOrReport(school: JwSchoolInfo?)`
    private func finishOrReport(_ school: JwSchoolInfo?) {
        if let school, school.isUnverified {
            reportDialogSchool = school
        } else {
            completeImport()
        }
    }

    /// 只写剪贴板, 不拉起任何应用 — 与 launchQqGroupJoin 的剪贴板边界互斥。
    /// ← 原 `copyTextToClipboard(text, label)`
    private func copyTextToClipboard(_ text: String) {
        UIPasteboard.general.string = text
    }

    /// 报告正文 — 学校侧公开信息 + 计数 + 版本号 + 日期, 不含任何凭据。
    /// ← 原 `JwImportReport.build(school, courseCount, VERSION_NAME, VERSION_CODE)`
    private func currentReportText() -> String {
        guard let school = reportDialogSchool else { return "" }
        return JwImportReport.build(
            school: school,
            courseCount: parsedCourses.count,
            versionName: UpdateManager.currentVersionName,
            versionCode: appBuildCode,
            date: JwImportReport.todayStamp())
    }

    /// 完成/点外 = 同一收口: 清弹窗 → completeImport → importFinished → finish()
    /// ← 原 `closeReportDialog`
    private func closeReportDialog() {
        reportDialogSchool = nil
        completeImport()
    }

    /// QQ 拉起降级链复用 AboutScreen.joinQqGroup 时序(群资料卡 → 备选形态 → TIM → QQ → 浏览器),
    /// 但**不**像 AboutScreen 那样先复制群号 — 此刻剪贴板装着待粘贴的报告, 覆盖 = 回路断裂。
    /// ← 原 `launchQqGroupJoin(group)`
    private func launchQqGroupJoin() {
        let group = L10n.t("about_qq_group_number")
        func canOpen(_ s: String) -> Bool {
            guard let url = URL(string: s) else { return false }
            return UIApplication.shared.canOpenURL(url)
        }
        func open(_ s: String) {
            guard let url = URL(string: s) else { return }
            UIApplication.shared.open(url)
        }
        var launched = false
        // 旧实现的 mqqopensdkapi 通道因缺少官方 key 被 QQ 拒解析, 不启用 ← QqJoin.officialJoinComponentUri
        if canOpen(QqJoin.groupCardUri(group)) {
            open(QqJoin.groupCardUri(group)); launched = true
        } else if canOpen(QqJoin.groupCardUriAlt(group)) {
            open(QqJoin.groupCardUriAlt(group)); launched = true
        } else if canOpen("tim://") {
            open("tim://"); launched = true
        } else if canOpen("mqq://") {
            open("mqq://"); launched = true
        }
        if !launched, canOpen(QqJoin.webFallbackUri(group)) {
            open(QqJoin.webFallbackUri(group)); launched = true
        }
        if !launched {
            statusMsg = L10n.format("jw_import_report_qq_manual", group)
        }
    }

    /// App 构建号(= 原版本 BuildConfig.VERSION_CODE; iOS = CFBundleVersion)
    private var appBuildCode: Int {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap(Int.init) ?? 0
    }

    // MARK: - 草稿恢复 (← LaunchedEffect(incomingDraftId))

    private func restoreIncomingDraftIfNeeded() {
        guard let id = incomingDraftId, draftId == nil else { return }
        let repo = draftRepository
        Task { @MainActor in
            let snapshot = await Task.detached(priority: .userInitiated) {
                try? repo.get(id)
            }.value
            guard let snapshot = snapshot else {
                // snapshot 缺失 → import_drafts_empty(← 原版本)
                errorMsg = L10n.format("import_drafts_empty")
                return
            }
            draftId = id
            parsedSchool = snapshot.school
            selectedSchool = snapshot.school
            parsedCourses = snapshot.courses
            configStartDate = snapshot.termStartDate
            configTableName = jwIsBlank(snapshot.tableName)
                ? L10n.format("jw_import_title", snapshot.school.name)
                : snapshot.tableName
            configRows = snapshot.periods.map {
                TimeTableUtils.TimeSlotRow(node: $0.node, start: $0.start, end: $0.end)
            }
            // 补齐标志随快照恢复 — 默认作息提示不因退出重进而丢失
            configUsedDefaultTimes = snapshot.usedDefaultTimes
            configTimeJson = TimeTableUtils.buildTimeJsonFromRows(configRows)
            // issue#23 T5: 草稿已存配置仍能 derive 出恢复的行 → 原样保留; 缺失/损坏 →
            // 从恢复行重推断; 行不可推断 → 保底默认(TimeSlotEditor 保持手动 + 既有校验兜底)。
            let restoredStored = jwIsBlank(snapshot.smartConfigJson)
                ? nil : decodeSmartPeriodConfig(snapshot.smartConfigJson)
            configSmartConfig = resolveAutoPeriodConfig(rows: configRows, stored: restoredStored)
                ?? SmartPeriodConfig(
                    startTime: configRows.first.map { jwIsBlank($0.start) ? "08:00" : $0.start } ?? "08:00",
                    totalPeriods: max(configRows.count, 1))
            // v1.0.56 T10: 默认选中「本次导入自动建作息表」(合成 id=-1)
            configBindPeriodTableId = -1
            exitDraftState.activeImport = true
            navigateToStage(snapshot.phase == .webViewLogin ? .webViewLogin : .preview)
        }
    }

    // MARK: - 抓取失败 / 解析

    /// ← onCaptureError: FrameCaptureStatus 六态映射; 保留 FrameCaptureResult 给导出按钮。
    private func handleCaptureError(_ result: FrameCaptureResult, _ hint: String) {
        switch result.status {
        case .crossDomainIframeBlocked:
            errorMsg = L10n.format("jw_err_cross_domain_iframe", hint)
        case .containerEmptyAfterDelay:
            errorMsg = L10n.format("jw_err_container_empty_after_delay")
        case .iframeNavPending:
            errorMsg = L10n.format("jw_err_iframe_nav_pending")
        case .wrongPage:
            // #18: UCAS SEP 门户页 LoginScreen 已把 hint 换成精确动线指引
            // (jw_err_ucas_sep_portal), 非空则优先展示
            errorMsg = hint.isEmpty ? L10n.format("jw_err_wrong_page") : hint
        case .sessionExpired:
            errorMsg = L10n.format("jw_err_session_expired")
        default:
            errorMsg = L10n.format("jw_parse_empty")
        }
        lastCaptureResult = result
        statusMsg = nil
    }

    private func onHtmlCaptured(_ html: String, _ sch: JwSchoolInfo,
                                _ periods: [(Int, String, String)],
                                _ termStartDate: String) {
        statusMsg = L10n.format("import_parsing")
        // UCAS 详情补全要发原生 HTTP, 必须离开主线程; 回来后仍回主线程改 @State
        Task { @MainActor in
            await parseAndAdvance(html, sch, periods, termStartDate)
        }
    }

    private func parseAndAdvance(_ html: String, _ sch: JwSchoolInfo,
                                 _ periods: [(Int, String, String)],
                                 _ termStartDate: String) async {
        // T6 双层判定: sch.type 已知直接用; 空 → HTML/URL 组合兜底
        let rawType = sch.type
        let effectiveType = (rawType?.isEmpty == false ? rawType : nil)
            ?? JwImportViewModel.detectProtocol(html, url: sch.url.isEmpty ? nil : sch.url)
        // #18 UCAS: 课程格链到跨源详情站 xkcts:8443 (WebView fetch 被 CORS 挡),
        // 详情页免登录 → 原生 HTTP 逐课直抓补全周次/教室; 失败降级原 HTML
        // (parser 落 1-16 占位, 与既有行为一致) ← runCatching{enrich}.getOrDefault(html)
        let htmlForParse: String
        if effectiveType == JwProtocol.TYPE_UCAS {
            htmlForParse = await UcasDetailFetch.enrich(html)
        } else {
            htmlForParse = html
        }
        // ← 原 parseHtml 在 scope.launch try/catch 内: parser 抛异常 →
        //   errorMsg = jw_parse_failed(message) + jw_parse_failed_hint。
        //   iOS parse 返回 Outcome(error), 语义映射: error 非空 = 原版本 异常路径。
        let parsed = JwParseDispatch.parse(htmlForParse, effectiveType ?? "")
        if let parseError = parsed.error {
            errorMsg = L10n.format("jw_parse_failed", parseError)
                + L10n.format("jw_parse_failed_hint")
            statusMsg = nil
            return
        }
        let courses = parsed.courses
        let attempts = parsed.attempts
        if courses.isEmpty {
            // T9 诊断壳: classify 先做页面级嗅探再选文案 (← JwImportActivity.kt:740)
            errorMsg = DiagMapper.diagnosis(html: html, school: sch, attempts: attempts)
            statusMsg = nil
            return
        }
        // 不直接落库, 进预览页(v1.0.56 T10 起解析成功默认选中自动建表)
        parsedCourses = courses
        parsedSchool = sch
        exitDraftState.activeImport = true
        // 课程实际节次数生成行; WebView 抓到 periods 则预填
        let maxNode = courses.map { max($0.startNode, $0.endNode) }.max() ?? 0
        let periodMap = Dictionary(periods.map { ($0.0, ($0.1, $0.2)) }, uniquingKeysWith: { a, _ in a })
        let newRows = (1...max(1, maxNode)).map { node -> TimeTableUtils.TimeSlotRow in
            let filled = periodMap[node]
            return TimeTableUtils.TimeSlotRow(node: node,
                                              start: filled?.0 ?? "",
                                              end: filled?.1 ?? "")
        }
        let initialized = TimeTableUtils.initialManualRows(newRows)
        configRows = initialized.rows
        configUsedDefaultTimes = initialized.usedDefaults
        // 学期起始日预填: JSON 直连协议 (boya_pp/cqu/chaoxing) 能从接口拿到第一周周一
        // (如燕大 2026-2027-1 实为 2026-08-31, 本地 9 月首一推断会差一周), 用户仍可改
        configStartDate = termStartDate
        configTimeJson = TimeTableUtils.buildTimeJsonFromRows(configRows)
        configTableName = L10n.format("jw_import_title", sch.name)
        // issue#23 T5: 实时确认态与草稿持久化用同一推断结果播种; 行不全 → 简单兜底,
        // 无法补齐的行留在手动校验，其余使用已提示的默认作息。
        let inferredSmartConfig = TimeTableUtils.inferSmartPeriodConfig(configRows)
            ?? SmartPeriodConfig(
                startTime: newRows.first.map { jwIsBlank($0.start) ? "08:00" : $0.start } ?? "08:00",
                totalPeriods: max(newRows.count, 1))
        configSmartConfig = inferredSmartConfig
        // 解析成功即建草稿(sourceType=jw), 后续编辑 checkpoint, 完成/删除时清。
        let snapshot = JwImportDraftSnapshot(
            school: sch,
            courses: courses,
            periods: configRows.map { JwImportDraftPeriod(node: $0.node, start: $0.start, end: $0.end) },
            termStartDate: termStartDate,
            tableName: L10n.format("jw_import_title", sch.name),
            smartConfigJson: encodeSmartConfigJson(inferredSmartConfig),
            usedDefaultTimes: configUsedDefaultTimes)
        let repo = draftRepository
        draftId = await Task.detached(priority: .userInitiated) {
            try? repo.save(snapshot, sourceType: "jw", sourceUrl: sch.url)
        }.value
        navigateToStage(.preview)
        // v1.0.56 T10: 默认选中「本次导入自动建作息表」(合成 id=-1)
        configBindPeriodTableId = -1
        statusMsg = nil
    }

    // MARK: - 预览 (← Stage.Preview LaunchedEffect(parsedCourses))

    private func rebuildPreview() {
        let courses = parsedCourses
        let rows = configRows
        let bindId = configBindPeriodTableId
        let tableName = configTableName
        let startDate = configStartDate
        // L10n 取词留主线程; DB IO 走工作线程(repo.getAllTables suspend)
        let currentTableLabel = L10n.format("manage_current_table")
        Task { @MainActor in
            do {
                let inputs = try await Task.detached(priority: .userInitiated) { () throws -> (Int64, [(Int64, String)]) in
                    let repo = ScheduleRepository(AppDatabase.getShared())
                    let tables = try repo.getAllTables()
                    let targetId = tables.first(where: { $0.isDefault })?.id ?? tables.first?.id ?? 0
                    let periodTimeRows = ((try? repo.getAllPeriodTables()) ?? []).map { ($0.id, $0.timeJson) }
                    return (targetId, periodTimeRows)
                }.value
                let targetId = inputs.0
                // 绑定作息表时以表 timeJson 为真源(v1.0.56 T6; 协议无节次时间旧代码误报
                // 「第 X 节时间不能为空」的 2026-09-20 修复)
                let effectiveRows = TimeTableUtils.effectiveRowsForConfirm(
                    manualRows: rows, bindId: bindId, tables: inputs.1)
                let timeJson = TimeTableUtils.buildTimeJsonFromRows(
                    effectiveRows.filter { !jwIsBlank($0.start) && !jwIsBlank($0.end) })
                configTimeJson = timeJson
                let entities = JwImportViewModel.toCourseEntities(
                    courses, tableId: targetId, defaultColor: "#FF6750A4")
                let preview = try await Task.detached(priority: .userInitiated) { () throws -> ImportPreview in
                    let repo = ScheduleRepository(AppDatabase.getShared())
                    let parseResult = ScheduleParser.ParseResult(
                        tableName: tableName,
                        startDate: startDate,
                        courses: entities,
                        timeJson: timeJson,
                        nodesPerDay: courses.map { max($0.startNode, $0.endNode) }.max() ?? 0,
                        maxWeek: courses.map { $0.endWeek }.max() ?? 0)
                    let existingTable = targetId == 0 ? nil : ((try? repo.getTable(targetId)) ?? nil)
                    let existingCourses = targetId == 0 ? [] : ((try? repo.getCourses(targetId)) ?? [])
                    let conflicts: [CourseConflict] = targetId == 0 ? []
                        : parseResult.courses.compactMap { incoming in
                            existingCourses.first { ImportSheet.coursesConflict(incoming, $0) }
                                .map { CourseConflict(incoming: incoming, existing: $0) }
                        }
                    // issue#22: 同 groupId 多地点提示 — 不阻塞导入, 只让用户心里有数
                    var multiLocWarnings: [String] = []
                    let roomGroups = Dictionary(grouping: parseResult.courses) { $0.groupId }
                    for (gid, cs) in roomGroups {
                        if jwIsBlank(gid) { continue }
                        let distinctRooms = Set(cs.map { $0.room.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty })
                        if distinctRooms.count >= 2 {
                            multiLocWarnings.append(L10n.format(
                                "import_multi_location_warning_detail",
                                cs.first?.courseName ?? "", distinctRooms.count))
                        }
                    }
                    return ImportPreview(
                        targetTableId: targetId,
                        targetTableName: existingTable?.name ?? currentTableLabel,
                        parseResult: parseResult,
                        existingCourses: existingCourses,
                        conflicts: conflicts,
                        multiLocationWarnings: multiLocWarnings)
                }.value
                withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                    importPreview = preview
                }
                loadPeriodTables()
            } catch {
                errorMsg = L10n.format("jw_parse_failed", error.localizedDescription)
            }
        }
    }

    // MARK: - 预览五模式路由 (← ImportPreviewDialog onApply)

    private func onPreviewApply(_ mode: ImportApplyMode) {
        if isApplying { return }   // ← 原 onApply 首行 isApplying 防重复提交
        pendingMode = mode
        if mode == .appendNonConflict || mode == .appendAll {
            guard let preview = importPreview else { return }
            isApplying = true
            Task { @MainActor in
                do {
                    try await applySharedImport(preview: preview, mode: mode)
                } catch {
                    errorMsg = L10n.format("jw_parse_failed", error.localizedDescription)
                }
                isApplying = false
            }
        } else {
            navigateToStage(.configureConfirm)
        }
    }

    /// ← applySharedImport: 追加走共享 applyImportPreview; 被拒绝的追加必须保留
    /// 预览与可恢复草稿(仅 imported 才 completeImport 删草稿)。
    private func applySharedImport(preview: ImportPreview, mode: ImportApplyMode) async throws {
        var varResult = preview.parseResult
        // ← 原版本 TimeTableUtils.parseTimeSlotRows(configTimeJson).maxOfOrNull { it.node } ?: 0
        //   (坏/空 JSON 走 12 默认行兜底, iOS 同名函数语义一致, 禁另开 Safe 分支)
        varResult.timeJson = configTimeJson
        varResult.nodesPerDay = max(varResult.nodesPerDay,
                                    TimeTableUtils.parseTimeSlotRows(configTimeJson)
                                        .map { $0.node }.max() ?? 0)
        let adjusted = ImportPreview(
            targetTableId: preview.targetTableId,
            targetTableName: preview.targetTableName,
            parseResult: varResult,
            existingCourses: preview.existingCourses,
            conflicts: preview.conflicts,
            multiLocationWarnings: preview.multiLocationWarnings)
        var imported = false
        _ = ImportSheet.applyImportPreview(
            preview: adjusted,
            mode: mode,
            confirmedStartDateRaw: configStartDate,
            confirmedTableName: configTableName,
            confirmedTimeJson: configTimeJson,
            onImported: { imported = true },
            onError: { msg in errorMsg = msg },
            bindPeriodTableId: (configBindPeriodTableId ?? 0) > 0 ? configBindPeriodTableId : nil)
        // A rejected append must keep the preview and its recoverable draft.
        // ← 原版本: `if (imported) finishOrReport(selectedSchool ?: parsedSchool)`
        if imported { finishOrReport(selectedSchool ?? parsedSchool) }
    }

    // MARK: - 配置确认 (← Stage.ConfigureConfirm AlertDialog)

    private var configureConfirmSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.format("jw_config_title"))
                        .font(.system(size: 24))   // ← M3 AlertDialog title = headlineSmall 24sp 常规
                        .foregroundColor(colors.onSurface)
                    Text("\(parsedCourses.count) \(L10n.format("import_courses"))")
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                }
                // ← 原版本 1.0.51 ConfigureConfirm 字段序: DatePickerField → 课表名 TextField;
                // 名默认 jw_import_title(校名), 用户可改; 提交时空字符串 fallback 回模板。
                DatePickerField(value: configStartDate, onValueChange: { newValue in
                    configStartDate = newValue
                    checkpointDraft()
                },
                                label: L10n.format("import_week_start"),
                                // 只在日期错误时标红; 节次错误标到节次区(2026-09-20 反馈:
                                // 节次错也标日期框误导) ← isError = confirmError != null && 日期本身非法
                                isError: confirmError != nil &&
                                    (jwIsBlank(configStartDate) ||
                                     !jwMatchesFull(jwDateRegex, configStartDate)),
                                fillsWidth: true)
                TextField(L10n.format("jw_table_name_label"), text: $configTableName)
                    .onChange(of: configTableName) { _ in checkpointDraft() }
                    .frame(maxWidth: .infinity)   // ← 原 fillMaxWidth()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(colors.surfaceContainer)
                    .cornerRadius(SleepyTheme.fieldShape)
                    .accessibilityIdentifier("jw_config_table_name")
                // ← confirmError 内联展示(不上全局横幅): error 色 bodySmall
                if let confirmError = confirmError {
                    Text(confirmError)
                        .font(.system(size: 12))   // ← MaterialTheme.typography.bodySmall
                        .foregroundColor(colors.error)
                }
                TimeSlotEditor(rows: $configRows,
                               onRowsChange: { newRows in
                    configRows = newRows
                    configTimeJson = TimeTableUtils.buildTimeJsonFromRows(newRows)
                    checkpointDraft()
                },
                               // issue#28 P2: 智慧节次配置接线(此前默认 no-op → 「添加课间」点了没反应)
                               usedDefaultTimes: configUsedDefaultTimes,
                               smartConfig: configSmartConfig,
                               onSmartConfigChange: { newConfig in
                    configSmartConfig = newConfig
                    checkpointDraft()
                },
                               // v1.0.56 T6/T10 第三 Tab「作息表」: -1 合成项=本次导入自动建表
                               // (名随课表名, 默认选中), 其余=全部既有作息表
                               periodTableOptions: periodTableOptions(),
                               selectedPeriodTableId: configBindPeriodTableId,
                               onSelectPeriodTable: { configBindPeriodTableId = $0 })

                HStack {
                    // ← 原版本 TextButton 默认色 = primary, labelLarge 14sp Medium, 高 40dp;
                    //   dismissButton = importPreview=null; stage=Preview — 保留已解析课程回预览
                    Button(L10n.format("back")) {
                        importPreview = nil
                        navigateToStage(.preview)
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.primary)
                    .frame(height: 40)
                    .disabled(isApplying)
                    Spacer()
                    Button(L10n.format("jw_config_confirm")) {
                        confirmAndImport()
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.primary)
                    .frame(height: 40)
                    .disabled(isApplying)
                }
                .buttonStyle(SleepyButtonStyle())
            }
            .padding(20)
        }
        .background(colors.surface)
    }

    /// v1.0.56 T6/T10: configRows 非空时合成 id=-1「本次导入自动建作息表」置顶,
    /// 其余为 allPeriodTables (id/name/nodesPerDay)。
    private func periodTableOptions() -> [PeriodTableOption] {
        var options: [PeriodTableOption] = []
        if !configRows.isEmpty {
            // ← 原版本 configTableName.ifBlank { jw_import_title(school.name) }
            let autoName = jwIsBlank(configTableName)
                ? L10n.format("jw_import_title", parsedSchool?.name ?? "")
                : configTableName
            options.append(PeriodTableOption(id: -1, name: autoName, nodesPerDay: configRows.count))
        }
        options.append(contentsOf: periodTables.map {
            PeriodTableOption(id: $0.id, name: $0.name, nodesPerDay: $0.nodesPerDay)
        })
        return options
    }

    private func loadPeriodTables() {
        Task { @MainActor in
            let tables = await Task.detached(priority: .userInitiated) { () -> [PeriodTableEntity] in
                let repo = ScheduleRepository(AppDatabase.getShared())
                return (try? repo.getAllPeriodTables()) ?? []
            }.value
            periodTables = tables
        }
    }

    // ← confirmButton 校验链 + 落库
    private func confirmAndImport() {
        // 校验(与 原版本 同链: confirmError 内联, 只置字段级错误)
        if jwIsBlank(configStartDate) || !jwMatchesFull(jwDateRegex, configStartDate) {
            confirmError = L10n.format("start_date_format")
            return
        }
        // v1.0.56 T6 修正: 绑了作息表(id>0)时以表的 timeJson 为真源; 教务协议没回
        // 节次时间 → 手动 rows 全空 → 旧代码误报「第 X 节时间不能为空」(2026-09-20)。
        let periodTimeRows = periodTables.map { ($0.id, $0.timeJson) }
        let effectiveRows = TimeTableUtils.effectiveRowsForConfirm(
            manualRows: configRows, bindId: configBindPeriodTableId, tables: periodTimeRows)
        if let first = effectiveRows.first(where: { jwIsBlank($0.start) || jwIsBlank($0.end) }) {
            confirmError = L10n.format("slot_time_required", first.node)
            return
        }
        if let first = effectiveRows.first(where: {
            !jwMatchesFull(jwHmRegex, $0.start) || !jwMatchesFull(jwHmRegex, $0.end) ||
            $0.start >= $0.end
        }) {
            confirmError = L10n.format("slot_time_invalid", first.node)
            return
        }
        confirmError = nil
        configTimeJson = TimeTableUtils.buildTimeJsonFromRows(effectiveRows)
        // 落库
        statusMsg = L10n.format("import_parsing")
        guard let school = parsedSchool else { return }
        isApplying = true
        // 工作线程闭包只捕获值拷贝(Sendable 友好), 不捕获 self
        let mode = pendingMode
        let courses = parsedCourses
        let startDate = configStartDate
        let timeJson = configTimeJson
        let bindId = configBindPeriodTableId
        let smartJson = encodeSmartConfigJson(configSmartConfig)
        let rawTableName = configTableName
        let previewSnapshot = importPreview
        Task { @MainActor in
            do {
                if mode == .importAsNew {
                    let maxNode = effectiveRows.map { $0.node }.max() ?? 0
                    // ← 原版本 一致: 用户编辑的课表名为空白时回退 jw_import_title(校名)
                    //   (ifBlank = Kotlin 原串非空即用, 不 trim)
                    let finalTableName = jwIsBlank(rawTableName)
                        ? L10n.format("jw_import_title", school.name)
                        : rawTableName
                    // v1.0.56 T10: id=-1 = 本次导入自动建作息表(名字随课表名, VM 内走
                    // 全局唯一名顺延); id>0 = 绑定既有表; nil = 不建不绑。effectiveRows
                    // 已按绑定语义解析(id>0 = 表时间, 否则手动 rows)。
                    let autoPeriodEntity: PeriodTableEntity? =
                        (bindId == -1 && !effectiveRows.isEmpty)
                        ? PeriodTableEntity(name: finalTableName,
                                            nodesPerDay: effectiveRows.count,
                                            timeJson: timeJson)
                        : nil
                    let tableId = try await Task.detached(priority: .userInitiated) { () throws -> Int64 in
                        try JwImportViewModel.importAsNewTable(
                            AppDatabase.getShared(),
                            courses: courses,
                            tableName: finalTableName,
                            startDate: startDate,
                            timeJson: timeJson,
                            nodesPerDay: maxNode,
                            smartConfigJson: smartJson,
                            periodTable: autoPeriodEntity)
                    }.value
                    // v1.0.56 T6: 选了既有作息表 Tab → 导入的课表直接绑定该表(节次以表为准)
                    if let chosenId = bindId, chosenId > 0 {
                        await Task.detached(priority: .userInitiated) {
                            let repo = ScheduleRepository(AppDatabase.getShared())
                            try? repo.bindPeriodTable(timeTableId: tableId, periodTableId: chosenId)
                        }.value
                    }
                    // ← 原 `finishOrReport(school)` (未验证学校 → 报告弹窗, 非静默结束)
                    finishOrReport(school)
                } else {
                    guard let preview = previewSnapshot else {
                        isApplying = false
                        return
                    }
                    try await applySharedImport(preview: preview, mode: mode)
                    if !importFinished {
                        // 被拒绝的追加: 保留预览, 回预览页可再试(草稿不删)
                        statusMsg = nil
                    }
                }
            } catch {
                errorMsg = L10n.format("jw_parse_failed", error.localizedDescription)
                statusMsg = nil
            }
            isApplying = false
        }
    }

    // MARK: - 排查全量包导出 (← exportDiagnosticDump / JwImportDiagnosticsFlow.run)

    private func exportDiagnosticDump(_ school: JwSchoolInfo?) {
        guard let result = lastCaptureResult else {
            // ← 原版本: statusMsg = jw_diag_export_failed("无抓取记录")
            statusMsg = L10n.format("jw_diag_export_failed", "无抓取记录")
            return
        }
        dumpProgress = nil
        let coordinator = webViewForDump
        Task { @MainActor in
            // 管线编排器每次导出新建实例(stepsDone 承载于实例, ← 原版本 闭包局部 var)
            var flow = JwImportDiagnosticsFlow(
                onProgress: { progress in
                    Task { @MainActor in dumpProgress = progress }
                },
                onStatus: { msg in
                    Task { @MainActor in
                        statusMsg = msg
                        dumpProgress = nil   // ← 原 终态(成功/失败)均清进度卡
                    }
                })
            await flow.run(
                school: school,
                lastCaptureResult: result,
                evalJs: { js in
                    await withCheckedContinuation { cont in
                        // webView 已释放 → 直接 nil(wv?.let 同兜底), 禁悬挂
                        guard let coordinator = coordinator, coordinator.webView != nil else {
                            cont.resume(returning: nil)
                            return
                        }
                        coordinator.evaluate(js) { raw in
                            cont.resume(returning: JwImportDiagnosticsFlow.unwrapEvalResult(raw))
                        }
                    }
                },
                replayEval: { marker, timeout in
                    await JwReplayBridge.eval(coordinator: coordinator, marker: marker,
                                              timeout: timeout)
                },
                fetchCookies: {
                    await withCheckedContinuation { cont in
                        let store = WKWebsiteDataStore.default().httpCookieStore
                        store.getAllCookies { cookies in
                            // ← 原版本 CookieManager.getCookie(webView.url): 仅本页可见 cookie;
                            //   页面 URL 缺失 → 全量也不该给(≈ 原 null 兜底)
                            let host = coordinator?.webView?.url?.host ?? ""
                            let page = coordinator?.webView?.url
                            let visible = cookies.filter { c in
                                guard let url = page, !host.isEmpty else { return false }
                                let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
                                return (host == d || host.hasSuffix(".\(d)")) &&
                                    c.isValidFor(url)
                            }
                            let joined = visible.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                            cont.resume(returning: joined.isEmpty ? nil : joined)
                        }
                    }
                },
                dumpExport: { school, result, inventoryJson, cookiesFull, storageJson,
                             linksJson, resourceReplayJson, networkReplayJson, networkLiveJson in
                    await Task.detached(priority: .userInitiated) {
                        JwCaptureDump.exportDump(
                            school: school, result: result,
                            domInventoryJson: inventoryJson, cookiesFull: cookiesFull,
                            storageJson: storageJson, linksJson: linksJson,
                            resourceReplayJson: resourceReplayJson,
                            networkLiveJson: networkReplayJson ?? networkLiveJson)
                    }.value
                },
                share: { _, url in
                    Task { @MainActor in JwCaptureDump.share(url: url) }
                },
                noCaptureMsg: "无抓取记录",
                failFmt: { reason in L10n.format("jw_diag_export_failed", reason) },
                savedFmt: { zipName in L10n.format("jw_diag_export_saved", zipName) })
        }
    }
}

// MARK: - 支撑小工具

/// SmartPeriodConfig -> JSON(← kotlinx Json.encodeToString)。空/失败回空串。
private func encodeSmartConfigJson(_ config: SmartPeriodConfig) -> String {
    guard let data = try? JSONEncoder().encode(config),
          let out = String(data: data, encoding: .utf8) else { return "" }
    return out
}

extension HTTPCookie {
    /// WKWebView 页面 URL 对该 cookie 是否可见(路径 + 安全位, 域匹配在调用方;
    /// 近似 原版本 CookieManager.getCookie(url) 的匹配语义)。
    func isValidFor(_ url: URL) -> Bool {
        if isSecure, let scheme = url.scheme, scheme.lowercased() != "https" { return false }
        let urlPath = url.path.isEmpty ? "/" : url.path
        return urlPath.hasPrefix(path)
    }
}

// MARK: - 错误弹窗 (errorMsg AlertDialog + dumpProgress Card)

/// 报错统一弹窗: 标题 jw_error_dialog_title, 文本可滚(≤320pt),
/// DialogActionButtons: 确定位 = jw_err_dismiss(只关窗不退页 #27)、
/// 第三位 = jw_diag_export_btn → 导出排查全量包; 导出后同窗内展开进度卡。
struct JwErrorDialog: View {
    @Environment(\.localWakeUpColors) private var colors
    let message: String
    let dumpProgress: DiagDumpProgress?
    let onDismiss: () -> Void
    let onExport: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 0) {
                // ← AlertDialog title
                Text(L10n.format("jw_error_dialog_title"))
                    .font(.system(size: 24))   // ← headlineSmall 24sp
                    .foregroundColor(colors.onSurface)
                    .padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(message)
                            .font(.system(size: 14))
                            .foregroundColor(colors.onSurfaceVariant)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        // ← Spacer(20.dp)
                        Spacer().frame(height: 20)
                        // 导出(第三位 secondary) / 确定(confirm 位 primary)
                        DialogActionButtons(
                            confirmText: L10n.format("jw_err_dismiss"),
                            onConfirm: onDismiss,
                            thirdText: L10n.format("jw_diag_export_btn"),
                            onThird: onExport)
                        // 点击导出后在同一个错误弹窗内向下展开进度区 — 用户不离开
                        // 当前问题上下文即可看到步骤、阶段文案和百分比。
                        if let progress = dumpProgress {
                            Spacer().frame(height: 12)
                            DiagDumpProgressCard(progress: progress)
                        }
                    }
                }
                .frame(maxHeight: 320)   // ← heightIn(max = 320.dp)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: SleepyShapes.extraLarge)
                .fill(colors.surfaceContainerHigh))
            .padding(.horizontal, 24)
        }
        .accessibilityIdentifier("jw_error_dialog")
    }
}

// MARK: - 预览弹窗 (← ImportPreviewDialog + isApplying)

/// JW 导入专用预览面 — 与共享 ImportSheet 的 ImportPreviewDialog 同一内容契约
/// (指标卡/信息区/冲突/提示/五模式按钮), 差异: 共享组件为 private 且 JW 流需要
/// isApplying 防重复提交闸(ImportPreviewDialog(isApplying) 1.0.61)。
struct JwImportPreviewDialog: View {
    @Environment(\.localWakeUpColors) private var colors
    let preview: ImportPreview
    let isApplying: Bool
    let onDismiss: () -> Void
    let onApply: (ImportApplyMode) -> Void

    private var targetIsCurrent: Bool { preview.targetTableId != 0 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 14) {
                // ← title Column(spacedBy 6)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.format("import_preview_title"))
                        .font(.system(size: 22, weight: .semibold))   // ← titleLarge
                        .foregroundColor(colors.onSurface)
                    if !targetIsCurrent {
                        Text(L10n.format("import_new_table_hint"))
                            .font(.system(size: 12))                  // ← bodySmall
                            .foregroundColor(colors.primary)
                    } else {
                        Text(L10n.format("import_target_table", preview.targetTableName))
                            .font(.system(size: 12))
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            JwPreviewMetricCard(label: L10n.format("import_courses"),
                                                value: "\(preview.incomingCount)",
                                                bg: colors.primaryContainer,
                                                fg: colors.onPrimaryContainer)
                            if targetIsCurrent {
                                JwPreviewMetricCard(label: L10n.format("import_conflicts"),
                                                    value: "\(preview.conflictCount)",
                                                    bg: preview.conflictCount > 0 ? colors.errorContainer : colors.secondaryContainer,
                                                    fg: preview.conflictCount > 0 ? colors.onErrorContainer : colors.onSecondaryContainer)
                                JwPreviewMetricCard(label: L10n.format("import_appendable"),
                                                    value: "\(preview.cleanCount)",
                                                    bg: colors.tertiaryContainer,
                                                    fg: colors.onTertiaryContainer)
                            }
                        }
                        // ← 信息区 surfaceContainer clip large padding14 spaced8
                        VStack(alignment: .leading, spacing: 8) {
                            JwPreviewInfoRow(label: L10n.format("import_table_name"),
                                             value: preview.parseResult.tableName)
                            JwPreviewInfoRow(label: L10n.format("import_start_date"),
                                             value: preview.parseResult.startDate)
                            if targetIsCurrent {
                                JwPreviewInfoRow(
                                    label: L10n.format("import_suggestion"),
                                    value: preview.conflictCount == 0
                                        ? L10n.format("import_no_conflict")
                                        : L10n.format("import_conflict_count", preview.conflictCount))
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colors.surfaceContainer)
                        .cornerRadius(SleepyShapes.large)
                        // issue#22 同名课程多地点提示(secondaryContainer, 不阻塞)
                        if !preview.multiLocationWarnings.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.format("import_multi_location_warning"))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(colors.onSecondaryContainer)
                                ForEach(preview.multiLocationWarnings.prefix(5), id: \.self) { warning in
                                    Text("• \(warning)")
                                        .font(.system(size: 12))
                                        .foregroundColor(colors.onSecondaryContainer)
                                }
                                if preview.multiLocationWarnings.count > 5 {
                                    Text(L10n.format("more_unexpanded", preview.multiLocationWarnings.count - 5))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(colors.onSecondaryContainer)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(colors.secondaryContainer)
                            .cornerRadius(SleepyShapes.large)
                        }
                        // 冲突明细(前 3 条)
                        if !preview.conflicts.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L10n.format("import_conflicts"))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(colors.onSurface)
                                ForEach(preview.conflicts.prefix(3)) { conflict in
                                    Text("• \(conflict.incoming.courseName) ↔ \(conflict.existing.courseName)（\(DateUtils.localizedDay(conflict.incoming.day)) \(conflict.incoming.nodeString(isShort: true))）")
                                        .font(.system(size: 12))
                                        .foregroundColor(colors.onSurfaceVariant)
                                }
                                if preview.conflicts.count > 3 {
                                    Text(L10n.format("import_conflict_more", preview.conflicts.count - 3))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(colors.onSurfaceVariant)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(colors.surfaceContainer)
                            .cornerRadius(SleepyShapes.large)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 320)
                // ← confirmButton Column(spacedBy 8), 全部 enabled = !isApplying
                VStack(spacing: 8) {
                    if !targetIsCurrent {
                        // 没有任何课表时只允许「作为新课表导入」
                        JwApplyButton(title: L10n.format("import_as_new"), danger: false,
                                      enabled: !isApplying) { onApply(.importAsNew) }
                    } else {
                        HStack(spacing: 8) {
                            JwApplyButton(title: L10n.format("import_append_only"), danger: false,
                                          enabled: !isApplying) { onApply(.appendNonConflict) }
                            JwApplyButton(title: L10n.format("import_as_new"), danger: false,
                                          enabled: !isApplying) { onApply(.importAsNew) }
                        }
                        HStack(spacing: 8) {
                            // 追加冲突课表 — 危险动作(同格多层), errorContainer 色块底
                            JwApplyButton(title: L10n.format("import_append_conflict"), danger: true,
                                          enabled: !isApplying) { onApply(.appendAll) }
                            JwApplyButton(title: L10n.format("import_append_as_new"), danger: false,
                                          enabled: !isApplying) { onApply(.appendAsNew) }
                        }
                        // 覆盖课表为危险动作: errorContainer 色块底 + onErrorContainer 文字
                        JwApplyButton(title: L10n.format("import_overwrite"), danger: true,
                                      enabled: !isApplying) { onApply(.replaceCurrent) }
                    }
                    // ← 原版本 TextButton: 纯文字 40dp, onSurfaceVariant
                    Button(action: onDismiss) {
                        Text(L10n.format("cancel"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.onSurfaceVariant)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(SleepyButtonStyle())
                    .disabled(isApplying)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: SleepyShapes.extraLarge)
                .fill(colors.surface))
            .padding(.horizontal, 24)
        }
        .accessibilityIdentifier("import_preview_dialog")
    }
}

private struct JwApplyButton: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    let danger: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)   // ← 原 maxLines = 1
                .foregroundColor(danger ? colors.onErrorContainer : colors.onPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(danger ? colors.errorContainer : colors.primary)
                .cornerRadius(SleepyShapes.medium)
        }
        .buttonStyle(SleepyButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

private struct JwPreviewMetricCard: View {
    let label: String
    let value: String
    let bg: Color
    let fg: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))   // ← labelSmall 11sp Medium
                .foregroundColor(fg.opacity(SleepyTheme.Alpha.highContent))
            Text(value)
                .font(.system(size: 22, weight: .bold))     // ← titleLarge 22sp Bold
                .foregroundColor(fg)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg)
        .cornerRadius(SleepyShapes.large)
    }
}

private struct JwPreviewInfoRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colors.onSurfaceVariant)
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(colors.onSurface)
        }
    }
}

// MARK: - 排查包重放桥 (DiagnosticReplayBridge / __sleepyDiagBridge)

/// WKScriptMessageHandler 一次性桥: 注入重放 JS → 等 window.webkit.messageHandlers
/// .__sleepyDiagBridge.postMessage(json) → 超时/回调即注销(← 原实现
/// addJavascriptInterface/removeJavascriptInterface + withTimeoutOrNull)。
///
/// 全部在主线程访问(WKScriptMessageHandler 回调 + Task { @MainActor } 驱动)。
/// removeScriptMessageHandler 对未注册桥名会抛 NSException → 用注册表精确追踪
/// "谁占着桥名", 只注销自己挂上去的那次(重复导出时后来者顶替, 前任跳过注销)。
final class JwReplayMessageHandler: NSObject, WKScriptMessageHandler {
    private static let bridgeName = "__sleepyDiagBridge"
    private static var activeBridges: [ObjectIdentifier: JwReplayMessageHandler] = [:]

    private var continuation: CheckedContinuation<String?, Never>?
    private var timeoutWork: DispatchWorkItem?
    private var settled = false
    private var uccKey: ObjectIdentifier?

    /// 在 webView 上注册桥 + 注入 js, 等回传或超时(超时 → nil, 管线继续)。
    /// @MainActor: WKWebView(configuration/evaluateJavaScript)主线程隔离,
    /// 调用方 JwReplayBridge.eval 本就 @MainActor, 回调也在主线程 — 显式声明。
    @MainActor
    func eval(on webView: WKWebView, js: String, timeout: TimeInterval) async -> String? {
        await withCheckedContinuation { cont in
            continuation = cont
            let ucc = webView.configuration.userContentController
            let key = ObjectIdentifier(ucc)
            // 同桥名重复注册会抛异常 — 前任若还占着桥名先顶替注销(每次导出全新一次性桥)
            if let existing = JwReplayMessageHandler.activeBridges[key] {
                ucc.removeScriptMessageHandler(forName: JwReplayMessageHandler.bridgeName)
                existing.markUnregistered()
            }
            ucc.add(self, name: JwReplayMessageHandler.bridgeName)
            JwReplayMessageHandler.activeBridges[key] = self
            uccKey = key
            webView.evaluateJavaScript(js, completionHandler: nil)
            let work = DispatchWorkItem { [weak self] in self?.settle(nil) }
            timeoutWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
        }
    }

    private func settle(_ value: String?) {
        guard !settled else { return }
        settled = true
        timeoutWork?.cancel()
        if let key = uccKey {
            if JwReplayMessageHandler.activeBridges[key] === self {
                // 仍由本桥占名 → 注销; 已被新导出的桥顶替 → 什么都不做
                // 注: 顶替者 remove 时已注销旧 handler, 此处只会摘自己那次 add
                if let webView = webViewForUcc {
                    webView.configuration.userContentController
                        .removeScriptMessageHandler(forName: JwReplayMessageHandler.bridgeName)
                }
                JwReplayMessageHandler.activeBridges[key] = nil
            }
            uccKey = nil
        }
        continuation?.resume(returning: value)
        continuation = nil
    }

    private func markUnregistered() {
        uccKey = nil
        webViewForUcc = nil
    }

    // 桥存活期间持有 webView 引用注销用
    fileprivate var webViewForUcc: WKWebView?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        if let s = message.body as? String {
            settle(s)
        } else {
            // message.body 非 Optional(Any); 非字符串回传(对象/数组)按描述兜底
            settle(String(describing: message.body))
        }
    }
}

/// 重放段统一入口 — JwImportDiagnosticsFlow.replayEval 的 WKWebView 装配。
/// 桥名/回调约定见 JwImportDiagnosticsFlow 头注释(messageHandlers.__sleepyDiagBridge)。
enum JwReplayBridge {
    @MainActor
    static func eval(coordinator: WebViewCoordinator?, marker: String,
                     timeout: TimeInterval) async -> String? {
        guard let webView = coordinator?.webView else { return nil }
        let js = marker == "__networkReplay__" ? jwNetworkReplayJs : jwResourceReplayJs
        let handler = JwReplayMessageHandler()
        handler.webViewForUcc = webView
        return await handler.eval(on: webView, js: js, timeout: timeout)
    }
}

// MARK: - 重放 JS (← DIAGNOSTIC_NETWORK_EXPORT_JS / RESOURCE_REPLAY_JS, JwWebViewLoginScreen.kt)
// 桥接适配: 原版本 __sleepyDiagBridge.onReplayResult(json) → iOS
// window.webkit.messageHandlers.__sleepyDiagBridge.postMessage(json)。其余逐行 1:1。

let jwNetworkReplayJs = #"""
(function(){
  var live = window.__sleepyDiagNetworkRecords || [];
  var same = function(u){ try{return new URL(u,location.href).origin===location.origin;}catch(e){return false;} };
  var replaceParam = function(text,name,value){
    var re = new RegExp('([?&]' + name + '=|(^|&)'+name+'=)([^&]*)','i');
    return re.test(text) ? text.replace(re,function(_,p){return p+encodeURIComponent(value);}) : text;
  };
  var weekOf = function(r){
    var s=(r.url||'')+'\n'+(r.requestBody||'');
    var m=s.match(/(?:^|[?&\s])((?:week|zc|weekIndex|zhouci|xq))=([^&\s]*)/i);
    return m ? {name:m[1],value:m[2]} : null;
  };
  var call = function(url, method, body, headers){
    var opts={method:method,credentials:'include',cache:'no-store'};
    if(method==='POST'){opts.body=body||''; opts.headers=headers||{'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8'};}
    return fetch(url,opts).then(function(r){return r.text().then(function(b){return {url:r.url||url,method:method,status:r.status,body:b,headers:(function(){var o={};try{r.headers.forEach(function(v,k){o[k]=v;});}catch(e){}return o;})()};});}).catch(function(e){return {url:url,method:method,status:0,error:String(e)};});
  };
  var replay = [];
  var jobs=[];
  for(var i=0;i<live.length && jobs.length<40;i++){
    var r=live[i]; if(!r||!same(r.url)||!r.url||r.source==='resource') continue;
    if(String(r.method).toUpperCase()==='POST') jobs.push(call(r.url,'POST',r.requestBody||'',r.requestHeaders||{}));
  }
  Promise.all(jobs).then(function(rs){ replay=rs; flushWeeks(replay); },function(){ flushWeeks(replay); });

  var weekState = [];
  function flushWeeks(replay){
    var seen={};
    for(var i=0;i<live.length && Object.keys(seen).length<10;i++){
      var r=live[i], w=weekOf(r); if(!r||!w||!same(r.url)) continue;
      var key=r.method+' '+r.url+' '+w.name; if(seen[key]) continue; seen[key]=1;
      weekState.push({key:key,r:r,name:w.name});
    }
    // 周重放必须串行(对齐桌面 collector): 校务服务器对 10 API × 25 周并发 = 风控/封禁风险。
    // 链式 reduce 逐个请求, 单项失败不影响后续。
    var tasks=[];
    weekState.forEach(function(ws){
      for(var n=1;n<=25;n++){
        var r=ws.r, method=String(r.method).toUpperCase();
        var u=r.url, b=r.requestBody||'';
        if(method==='POST') b=replaceParam(b,ws.name,String(n)); else u=replaceParam(u,ws.name,String(n));
        (function(week, weekName, weekMethod, weekUrl, weekBody){
          tasks.push(function(){
            return call(weekUrl,weekMethod,weekBody,ws.r.requestHeaders||{}).then(function(res){
              res.week=week; res.name=weekName; res.url=res.url || weekUrl; return res;
            }).catch(function(e){return {week:week,name:weekName,method:weekMethod,url:weekUrl,status:0,error:String(e)};});
          });
        })(n, ws.name, method, u, b);
      }
    });
    tasks.reduce(function(p,fn){
      return p.then(function(rs){ return fn().then(function(r){ rs.push(r); return rs; }); });
    }, Promise.resolve([])).then(function(rs){
      try { window.webkit.messageHandlers.__sleepyDiagBridge.postMessage(JSON.stringify({live:live,replay:replay,weeks:rs})); } catch(e) {}
    }, function(){
      try { window.webkit.messageHandlers.__sleepyDiagBridge.postMessage(JSON.stringify({live:live,replay:replay,weeks:[]})); } catch(e) {}
    });
  }
})()
"""#

/// 排查包专用 — 重取页面已经加载过的同源文本资源。
/// 只重放 GET, 使用浏览器缓存和当前 Cookie; 不重放 POST/表单写操作。
/// 每项保留 url/status/mime/body 或 error, 失败项不能被伪造为成功响应。
/// evaluateJavaScript 不等待 Promise, 所以最终 JSON 经一次性 JS bridge 回传。
let jwResourceReplayJs = #"""
(function(){
  var entries=[];
  var seen={};
  var resources=[];
  try { resources=performance.getEntriesByType('resource') || []; } catch(e) {}
  resources.push({name:location.href, initiatorType:'document'});
  function sameOrigin(u){ try { return new URL(u,location.href).origin===location.origin; } catch(e){ return false; } }
  function abs(u){ try { return new URL(u,location.href).href; } catch(e){ return String(u||''); } }
  function one(u){
    u=abs(u);
    if (!u || seen[u] || !sameOrigin(u)) return Promise.resolve();
    seen[u]=1;
    var controller = window.AbortController ? new AbortController() : null;
    var timer = controller ? setTimeout(function(){controller.abort();},5000) : null;
    var opts={method:'GET',credentials:'include',cache:'force-cache'};
    if (controller) opts.signal=controller.signal;
    return fetch(u,opts)
      .then(function(r){
        return r.text().then(function(body){
          entries.push({url:u,status:r.status,mime:r.headers.get('content-type')||'',body:body});
        });
      })
      .catch(function(e){ entries.push({url:u,status:0,mime:'',error:String(e)}); })
      .then(function(){ if (timer) clearTimeout(timer); });
  }
  var jobs=[];
  for (var i=0;i<resources.length;i++) {
    var u=resources[i] && resources[i].name;
    if (u) jobs.push(one(u));
  }
  function done(){
    try { window.webkit.messageHandlers.__sleepyDiagBridge.postMessage(JSON.stringify(entries)); } catch(e) {}
  }
  var all = Promise.all(jobs);
  var totalTimer = setTimeout(function(){ done(); },15000);
  all.then(function(){ clearTimeout(totalTimer); done(); },function(){ clearTimeout(totalTimer); done(); });
})()
"""#

/// 诊断结果 → 用户可见文案 ← JwImportActivity.kt DiagMapper (951-1040)。
///
/// 0 课不等于"空学期": 会话过期 / 图片课表 / 协议标注错 都会解析出 0 课,
/// 统一一句"本学期无课"会把用户引向错误方向。先 classify 分类, 再按类选文案,
/// 最后按学校/协议族补一条网络提示。
enum DiagMapper {

    /// 完整入口: 分类 + 映射。classify 的 html 非空是硬前置 (Swift 侧是
    /// precondition 而非可捕获异常) → 空 HTML 直接走兜底文案, 绝不喂进去。
    static func diagnosis(html: String, school: JwSchoolInfo,
                          attempts: [ParserAttemptSnapshot]) -> String {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return L10n.format("jw_err_empty_semester")
        }
        let diag = JwParseDiagnostics.classify(
            html, "", school, attempts.map { $0.asDiag })
        return map(diag, school)
    }

    static func map(_ diag: JwParseDiagnostics.Result, _ school: JwSchoolInfo) -> String {
        let features = diag.matchedFeatures.prefix(5).joined(separator: "/")
        let base: String
        switch diag.category {
        case .sessionExpired:     base = L10n.format("jw_diag_session_expired", school.name)
        case .noTableContainer:   base = L10n.format("jw_diag_no_container", school.name)
        case .headerNoNode:       base = L10n.format("jw_diag_header_no_node", school.name)
        case .imageOrEmptyCells:  base = L10n.format("jw_diag_image_cells", school.name)
        case .emptySemester:      base = L10n.format("jw_diag_empty_semester", school.name)
        case .wrongProtocol:      base = L10n.format("jw_diag_wrong_protocol", school.name)
        // 原版本 双参传 school.name+features(%2$s 内嵌); iOS 同文案双参等价形态
        case .unknownEmpty:       base = L10n.format("jw_diag_unknown_empty", school.name, features)
        }
        // v1.0.61 对齐(F080): 原 mapImpl 对 UNKNOWN_EMPTY 同样追加 hintPart
        // ("$base（features）$hintPart") — 24 个仅校内可达主机/5 个强智协议在
        // unknownEmpty 分类下也必须保留校园网/VPN 提示尾, 不再提前返回。
        let hint = schoolHint(school)
        return hint.isEmpty ? base : base + "\n\n" + hint
    }

    /// 特殊学校 hint: 临沂大学(校园网限制) / 强智系(会话踢下线) / B 档 985 校
    /// (校外多须 VPN/WebVPN) ← mapImpl 的 schoolHint
    static func schoolHint(_ school: JwSchoolInfo) -> String {
        let campusOnlyHosts = [
            "jwgl.lyu.edu.cn", "jwxt.lyu.edu.cn",
            // v1.0.46 B 档新 985 校: 教务域名普遍校外受限, 0 课兜底文案易被误读为学期选错
            "jwxt.neu.edu.cn",          // 东北大学
            "newxk.urp.seu.edu.cn",     // 东南大学
            "xsjw2018.jw.scut.edu.cn",  // 华南理工大学
            "jxglstu.hfut.edu.cn",      // 合肥工业大学
            "zdbk.zju.edu.cn",          // 浙江大学
            "jw.ustc.edu.cn",           // 中国科学技术大学
            "jwms.bit.edu.cn",          // 北京理工大学 (legacy URL 兼容)
            "jxzxehallapp.bit.edu.cn",  // 北京理工大学 (现行 URL)
            "csujwc.its.csu.edu.cn",    // 中南大学
            "jwxt.whut.edu.cn",         // 武汉理工大学 (登录后偶发限流, 提示换网络)
            // 2026-09 211 批量收录: 海外探测超时率高/域名校内受限的新校
            "jwxt.scnu.edu.cn",         // 华南师范大学
            "hdjw.hnu.edu.cn",          // 湖南大学 (Njw2017)
            "jw.ruc.edu.cn",            // 中国人民大学 (Njw2017)
            "jw.dhu.edu.cn",            // 东华大学
            "jw.ahu.edu.cn",            // 安徽大学 (supwisdom 新版)
            "jwxt.cumtb.edu.cn",        // 矿大北京 (supwisdom 新版)
            "jwxt.ybu.edu.cn",          // 延边大学
            "jwgl.shzu.edu.cn",         // 石河子大学
            "eams.uestc.edu.cn",        // 电子科技大学 (经典 EAMS, 202 鉴权)
            "eams.sufe.edu.cn",         // 上海财经大学 (经典 EAMS)
            "jwglnew.hunnu.edu.cn",     // 湖南师范大学 (经典 EAMS, iframe)
            "aao-eas.nuaa.edu.cn",      // 南京航空航天大学 (经典 EAMS)
            "jwgl.gzhmu.edu.cn",        // 广州医科大学 (强智, 教务域公网不解析)
        ]
        if campusOnlyHosts.contains(where: { school.url.contains($0) }) {
            return L10n.format("jw_diag_campus_vpn_hint")
        }
        // 四川大学条目 URL 即门户域, 整串相等才判
        if school.url == "https://scu.edu.cn/" {
            return L10n.format("jw_diag_campus_vpn_hint")
        }
        if [JwProtocol.TYPE_QZ, JwProtocol.TYPE_QZ_CRAZY, JwProtocol.TYPE_QZ_BR,
            JwProtocol.TYPE_QZ_WITH_NODE, JwProtocol.TYPE_QZ_OLD].contains(school.type) {
            return L10n.format("jw_diag_qz_vpn_hint")
        }
        return ""
    }
}
struct JwCatalogNoticeDialog: View {
    @Environment(\.localWakeUpColors) private var colors
    let school: JwSchoolInfo
    var onDismiss: () -> Void
    var onConfirm: () -> Void

    /// mayTry = 未验证 + 可导入(有 parser + 有 URL)
    private var mayTry: Bool { school.isUnverified && school.canImport }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 0) {
                Text(school.name)
                    .font(.system(size: 24))   // ← headlineSmall 24sp
                    .foregroundColor(colors.onSurface)
                    .padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(L10n.t(mayTry ? "jw_catalog_unverified_message" : "jw_catalog_pending_message"))
                            .font(.system(size: 14))
                            .foregroundColor(colors.onSurfaceVariant)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer().frame(height: 20)
                        DialogActionButtons(
                            confirmText: L10n.t(mayTry ? "jw_catalog_try" : "jw_pending_close"),
                            onConfirm: onConfirm,
                            // ← 原 dismissButton 仅在 mayTry 时存在
                            dismissText: mayTry ? L10n.t("jw_pending_close") : nil,
                            onDismiss: onDismiss)
                    }
                }
                .frame(maxHeight: 320)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: SleepyShapes.extraLarge)
                .fill(colors.surfaceContainerHigh))
            .padding(.horizontal, 24)
        }
        .accessibilityIdentifier("jw_catalog_notice_dialog")
    }
}

// MARK: - 导入成功报告弹窗 (reportDialogSchool?.let { AlertDialog(...) })

/// 未验证学校导入成功 = 对该校协议适配的一次真人验证。app 不上传任何数据,
/// 把成功事实压成可粘贴文本, 用户复制后进 QQ 群粘贴; 维护者据此把条目翻 verified。
/// ← 原 `reportDialogSchool?.let { school -> ... }`
struct JwImportReportDialog: View {
    @Environment(\.localWakeUpColors) private var colors
    let school: JwSchoolInfo
    let courseCount: Int
    var onDismiss: () -> Void          // 完成 / 点外 = 同一收口
    var onCopyReport: () -> Void       // 只写剪贴板, 不拉起任何应用
    var onJoinQq: () -> Void           // 拉起 QQ 群(不覆盖剪贴板)

    private var qqGroup: String { L10n.t("about_qq_group_number") }

    private var reportText: String {
        JwImportReport.build(
            school: school,
            courseCount: courseCount,
            versionName: UpdateManager.currentVersionName,
            versionCode: (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
                .flatMap(Int.init) ?? 0,
            date: JwImportReport.todayStamp())
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.t("jw_import_report_title"))
                    .font(.system(size: 24))   // ← headlineSmall 24sp
                    .foregroundColor(colors.onSurface)
                    .padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(L10n.format("jw_import_report_hint", qqGroup))
                            .font(.system(size: 14))   // ← bodyMedium 14sp
                            .foregroundColor(colors.onSurfaceVariant)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer().frame(height: 10)
                        // 报告正文: 等宽感用 surfaceVariant 底色块(全app纯色块禁描线 2026-08-25)
                        ScrollView {
                            Text(reportText)
                                .font(.system(size: 12))   // ← bodySmall 12sp
                                .foregroundColor(colors.onSurface)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        .frame(maxHeight: 220)
                        .background(RoundedRectangle(cornerRadius: SleepyShapes.large)
                            .fill(colors.surfaceVariant))
                        Spacer().frame(height: 20)
                        DialogActionButtons(
                            confirmText: L10n.t("jw_import_report_done"),
                            onConfirm: onDismiss,
                            dismissText: L10n.t("jw_import_report_copy"),
                            onDismiss: onCopyReport,
                            thirdText: L10n.t("jw_import_report_join_qq"),
                            onThird: onJoinQq)
                    }
                }
                .frame(maxHeight: 420)   // ← heightIn(max = 420.dp)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: SleepyShapes.extraLarge)
                .fill(colors.surfaceContainerHigh))
            .padding(.horizontal, 24)
        }
        .accessibilityIdentifier("jw_import_report_dialog")
    }
}
