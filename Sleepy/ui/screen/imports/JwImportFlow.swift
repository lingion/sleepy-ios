// JwImportFlow.swift — ← ui/screen/imports/JwImportActivity.kt (320 行)
// 教务直连导入主屏: 学校选择 → WebView 登录抓 HTML → 解析 → 配置确认 → 落库。
// Activity+Stage sealed → NavigationStack-less 状态机 View。

import SwiftUI

enum JwStage {
    case selectSchool
    case webViewLogin
    case configureConfirm
}

struct JwImportFlow: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.dismiss) private var dismiss
    let onFinish: () -> Void

    @StateObject private var jwViewModel = JwImportViewModel()

    @State private var selectedSchool: JwSchoolInfo? = nil
    @State private var stage: JwStage = .selectSchool
    @State private var errorMsg: String? = nil
    @State private var statusMsg: String? = nil
    @State private var importFinished = false
    // 解析后的课程暂存 + 配置确认状态
    @State private var parsedCourses: [JwCourse] = []
    @State private var parsedSchool: JwSchoolInfo? = nil
    @State private var configStartDate = ""
    @State private var configTimeJson = ""
    @State private var configRows: [TimeTableUtils.TimeSlotRow] = []

    var body: some View {
        ZStack {
            content

            // 错误提示(中央 errorContainer 卡)
            if let msg = errorMsg {
                Text(msg)
                    .font(.system(size: 14))
                    .foregroundColor(colors.onErrorContainer)
                    .padding(16)
                    .background(colors.errorContainer)
                    .cornerRadius(SleepyShapes.medium)
                    .padding(32)
                    .onTapGesture { errorMsg = nil }
            }
            // 状态提示(底部)
            if let msg = statusMsg {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.system(size: 13))
                        .foregroundColor(colors.onSurface)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(colors.surfaceContainerHighest)
                        .cornerRadius(8)
                        .padding(.bottom, 16)
                }
            }
        }
        .onAppear {
            if importFinished { onFinish() }
        }
        .onChange(of: importFinished) { finished in
            if finished { onFinish() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if importFinished {
            EmptyView()   // LaunchedEffect(finish) → onFinish 已由 onChange 触发
        } else if stage == .configureConfirm && !parsedCourses.isEmpty {
            if parsedSchool == nil {
                // school 丢失 → 回 WebView
                Color.clear.onAppear {
                    stage = .webViewLogin
                    parsedCourses = []
                }
            } else {
                configureConfirmSheet
            }
        } else if stage == .selectSchool {
            SchoolSelectScreen(onSchoolSelected: { school in
                if school.url.isEmpty {
                    errorMsg = L10n.format("jw_no_url")
                    return
                }
                selectedSchool = school
                stage = .webViewLogin
            }, onBack: onFinish)
        } else if stage == .webViewLogin {
            if let school = selectedSchool {
                JwWebViewLoginScreen(school: school, onHtmlCaptured: onHtmlCaptured) {
                    stage = .selectSchool
                }
            } else {
                Color.clear.onAppear { stage = .selectSchool }
            }
        }
    }

    // ← ConfigureConfirm AlertDialog
    private var configureConfirmSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.format("jw_config_title"))
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(colors.onSurface)
                    Text("\(parsedCourses.count) \(L10n.format("import_courses"))")
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                }
                DatePickerField(value: configStartDate, onValueChange: { configStartDate = $0 },
                                label: L10n.format("import_week_start"), isError: false)
                TimeSlotEditor(rows: configRows, onRowsChange: { newRows in
                    configRows = newRows
                    configTimeJson = TimeTableUtils.buildTimeJsonFromRows(newRows)
                })

                HStack {
                    Button(L10n.format("back")) {
                        stage = .webViewLogin
                        parsedCourses = []
                    }
                    .foregroundColor(colors.onSurfaceVariant)
                    Spacer()
                    Button(L10n.format("jw_config_confirm")) {
                        confirmAndImport()
                    }
                    .foregroundColor(colors.primary)
                }
                .buttonStyle(SleepyButtonStyle())
            }
            .padding(20)
        }
        .background(colors.surface)
    }

    // ← onHtmlCaptured: 解析 → 配置确认页
    private func onHtmlCaptured(_ html: String, _ sch: JwSchoolInfo,
                                _ periods: [(Int, String, String)]) {
        statusMsg = L10n.format("import_parsing")
        let courses = (try? JwImportViewModel.parseHtml(html, protocolType: sch.type ?? "")) ?? []
        if courses.isEmpty {
            errorMsg = L10n.format("jw_parse_empty")
            statusMsg = nil
            return
        }
        // 不直接落库, 进配置确认页
        parsedCourses = courses
        parsedSchool = sch
        // 课程实际节次数生成行; WebView 抓到 periods 则预填
        let maxNode = courses.map { max($0.startNode, $0.endNode) }.max() ?? 0
        let periodMap = Dictionary(periods.map { ($0.0, ($0.1, $0.2)) }, uniquingKeysWith: { a, _ in a })
        configRows = (1...max(1, maxNode)).map { node in
            let filled = periodMap[node]
            return TimeTableUtils.TimeSlotRow(node: node,
                                              start: filled?.0 ?? "",
                                              end: filled?.1 ?? "")
        }
        configStartDate = ""
        configTimeJson = ""
        stage = .configureConfirm
        statusMsg = nil
    }

    // ← confirmButton 校验链 + 落库
    private func confirmAndImport() {
        // 校验(与 ImportConfirmDialog 同链)
        if configStartDate.isEmpty ||
           configStartDate.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) == nil {
            errorMsg = L10n.format("start_date_format")
            return
        }
        if let first = configRows.first(where: { $0.start.isEmpty || $0.end.isEmpty }) {
            errorMsg = L10n.format("slot_time_required", first.node)
            return
        }
        if let first = configRows.first(where: {
            $0.start.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) == nil ||
            $0.end.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) == nil ||
            $0.start >= $0.end
        }) {
            errorMsg = L10n.format("slot_time_invalid", first.node)
            return
        }
        configTimeJson = TimeTableUtils.buildTimeJsonFromRows(configRows)
        // 落库
        statusMsg = L10n.format("import_parsing")
        guard let school = parsedSchool else { return }
        do {
            let maxNode = configRows.map { $0.node }.max() ?? 0
            let tableId = try JwImportViewModel.importAsNewTable(
                AppDatabase.getShared(),
                courses: parsedCourses,
                tableName: L10n.format("jw_import_title", school.name),
                startDate: configStartDate,
                timeJson: configTimeJson,
                nodesPerDay: maxNode)
            _ = tableId
            statusMsg = L10n.format("jw_import_success", parsedCourses.count)
            importFinished = true
        } catch {
            errorMsg = L10n.format("jw_parse_failed", error.localizedDescription)
            statusMsg = nil
        }
    }
}
