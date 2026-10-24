// SchoolSelectScreen.swift — ← ui/screen/imports/SchoolSelectScreen.kt (824 行)
// 学校选择页 — 教务直连第一步。
// schools.json 145 所 + 拼音搜索(PinyinMatcher) + URL 直连识别(detectProtocolFromUrl)
// + issue #25 注册域映射目录条目(SchoolDomainMatch.matchSchool)
// + 「自定义教务链接」引导入口(CustomUrlEntryRow)
// + 首字母分组(sortKeyFull 拼音排序) + 右侧字母索引栏(点击/滑动跳转, 高亮随滚动派生)
// + 跨 stage 往返状态保持(SchoolSelectStateStore ← rememberSaveable/viewModel)。

import SwiftUI
import Combine
import CoreLocation
import UIKit

// ← looksLikeUrl
func looksLikeUrl(_ s: String) -> Bool {
    let t = s.trimmingCharacters(in: .whitespaces)
    if t.hasPrefix("http://") || t.hasPrefix("https://") { return true }
    // 域名形态
    if t.range(of: #"^[a-zA-Z0-9][-a-zA-Z0-9]{0,62}\.[a-zA-Z]{2,}([/:].*)?$"#,
               options: .regularExpression) != nil { return true }
    // IP 形态
    if t.range(of: #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?(/.*)?$"#,
               options: .regularExpression) != nil { return true }
    return false
}

// ← normalizeUrl
func normalizeUrl(_ s: String) -> String {
    let t = s.trimmingCharacters(in: .whitespaces)
    return t.hasPrefix("http://") || t.hasPrefix("https://") ? t : "https://\(t)"
}

/// 学校首字母分组 ← SchoolSection
struct SchoolSection {
    let letter: String
    let schools: [JwSchoolInfo]
}

/// 跨 stage 往返状态仓 ← Android rememberSaveable(query / resumeLocationAfterSettings /
/// rememberSaveable(city) expanded) + JwImportActivity stage 分支的 SaveableStateProvider
/// (列表滚动位置) + viewModel() 作用域(学校列表/定位状态随同一 VM 实例跨 stage 存活)。
///
/// JwImportFlow 在 selectSchool→webViewLogin→selectSchool 的 stage 切换里会整树销毁
/// SchoolSelectScreen 连同其 @State/@StateObject;「选校进 WebView 再返回, 搜索词也要
/// 跟着回来」要求这些状态存活于比 View 更久的载体。JwImportFlow.swift 不在本 agent
/// 可改文件集内, 故用文件级单例仓承载 — 语义对齐 Activity 存活期:
/// 同一次导入流程内往返完整保留, 返回键退出流程(onDismiss)清零。
/// (流程「新进入」也需要调 resetForNewEntry 对齐 Activity 重建 — 见交付报告的
///  needs_shared_wiring: JwImportFlow.onAppear 一行。)
final class SchoolSelectStateStore: ObservableObject {
    static let shared = SchoolSelectStateStore()

    /// ← var query by rememberSaveable { mutableStateOf("") }
    @Published var query = ""
    /// ← var resumeLocationAfterSettings by rememberSaveable { mutableStateOf(false) }
    @Published var resumeLocationAfterSettings = false
    /// ← rememberSaveable(city) { expanded } 键控 — 推荐卡展开态跨 stage 保留
    @Published var expandedCity = ""
    /// ← rememberLazyListState().firstVisibleItemIndex 的一维近似快照:
    ///   滚动派生的当前激活分组字母(返回时 scrollTo 对应组头; 组内偏移为近似)。
    ///   nil = 顶部区(推荐卡/入口行) → 返回时不滚动。
    var scrollLetter: String? = nil
    /// ← viewModel(): 同实例贯穿一次导入流程, WebView 返回不重载学校列表
    let viewModel = JwImportViewModel()

    private init() {}

    /// 新进入整个导入流程 → 等价 Activity 重建: saveable 状态清零
    func resetForNewEntry() {
        query = ""
        resumeLocationAfterSettings = false
        expandedCity = ""
        scrollLetter = nil
    }
}

/// 各分组 header 在滚动容器坐标系的 minY(LazyVStack 只测屏上 header;
/// 离屏回收的保留最后一次观测值 — header 越过顶边后该值恒 ≤0, 判定「已滚过」仍正确)
private struct SectionHeaderMinYKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// 滚动派生量宿主 ← rememberLazyListState + derivedStateOf。
/// @StateObject 承载: preference 回调只写这里, 不直接 @State — 每帧滚动的更新
/// 只重建依赖它的子树(与 Android derivedStateOf 只触发订阅者一致)。
final class SchoolSelectScrollModel: ObservableObject {
    @Published var headerYs: [String: CGFloat] = [:]

    func merge(_ patch: [String: CGFloat]) {
        guard !patch.isEmpty else { return }
        var merged = headerYs
        merged.merge(patch, uniquingKeysWith: { $1 })
        headerYs = merged
    }

    /// 跳转前清理陈旧观测: 滚动跳位后目标 header 锚定顶边、其后各组必然位于视口下方,
    /// 它们上一次深滚留下的 ≤1 值必为陈旧 → 删除, 防止派生高亮粘在旧底部字母
    /// (Android firstVisibleItemIndex 无陈旧态, 此为 preference 方案的对应补正;
    /// 被删条目重新进入视口时会重新上报, 删除本身不会漏判)。
    func dropHeaders(after letter: String, in order: [String]) {
        guard let idx = order.firstIndex(of: letter), idx + 1 < order.count else { return }
        let stale = Set(order[(idx + 1)...])
        headerYs = headerYs.filter { !stale.contains($0.key) }
    }
}

/// 完整拼音排序键(sortKeyFull 预生成; 缺失 fallback name) ← schoolSortKey
func schoolSortKey(_ s: JwSchoolInfo) -> String {
    let firstLetter = !s.sortKey.isEmpty && s.sortKey.first!.isLetter
        ? String(s.sortKey.first!).uppercased()
        : "★"
    return "\(firstLetter)|\(s.sortKeyFull.isEmpty ? s.name : s.sortKeyFull)"
}

/// 扁平列表 → 拼音排序 → 首字母分组 ← groupByLetter
func groupByLetter(_ schools: [JwSchoolInfo]) -> [SchoolSection] {
    if schools.isEmpty { return [] }
    // Kotlin compareBy 稳定排序(同键保原序); Swift sorted 不保证稳定 → 下标 tie-break 复刻
    let sorted = schools.enumerated().sorted { a, b in
        let ka = schoolSortKey(a.element), kb = schoolSortKey(b.element)
        if ka != kb { return ka < kb }
        return a.offset < b.offset
    }.map { $0.element }
    var groups: [String: [JwSchoolInfo]] = [:]
    var order: [String] = []
    for s in sorted {
        let letter = !s.sortKey.isEmpty && s.sortKey.first!.isLetter
            ? String(s.sortKey.first!).uppercased()
            : "★"
        if groups[letter] == nil { order.append(letter) }
        groups[letter, default: []].append(s)
    }
    return order.map { SchoolSection(letter: $0, schools: groups[$0]!) }
}

struct SchoolSelectScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.scenePhase) private var scenePhase
    let onSchoolSelected: (JwSchoolInfo) -> Void
    let onDismiss: () -> Void

    /// ← rememberSaveable(query / resumeLocationAfterSettings / expanded) + JwImportActivity
    /// stage 分支 SaveableStateProvider(滚动位置) + viewModel() 作用域(学校列表跨 stage 存活):
    /// 全部状态存放于比 View 更久的单例仓, 选校进 WebView 再返回不再被整树销毁重置。
    @StateObject private var store = SchoolSelectStateStore.shared
    /// @ObservedObject 直订共享 VM — 其 @Published schools/schoolLocation 更新驱动本屏刷新
    @ObservedObject private var viewModel = SchoolSelectStateStore.shared.viewModel
    /// ← rememberLazyListState + derivedStateOf: 滚动位置派生高亮字母的宿主
    @StateObject private var scrollModel = SchoolSelectScrollModel()
    /// ← searchFocusRequester.requestFocus() + keyboard?.show(): 「自定义教务链接」入口
    /// 点击聚焦搜索框, iOS 上设置 focus 即自动弹键盘
    @FocusState private var searchFocused: Bool

    /// ← resumeLocationAfterSettings: 仅当「设置」按钮打开过系统设置, 返回时才续定位
    ///   (存于跨 stage 仓, WebView 往返不清)
    private var resumeLocationAfterSettings: Bool {
        get { store.resumeLocationAfterSettings }
        set { store.resumeLocationAfterSettings = newValue }
    }
    /// query 同样读自跨 stage 仓(写入只在 TextField 绑定处)
    private var query: String { store.query }
    /// ← rememberSaveable(city) expanded 键控(跨 stage 保留)
    private var expandedCityBinding: Binding<String> {
        Binding(get: { store.expandedCity }, set: { store.expandedCity = $0 })
    }

    private var filtered: [JwSchoolInfo] {
        let schools = viewModel.schools
        if query.trimmingCharacters(in: .whitespaces).isEmpty { return schools }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matched = schools.filter { PinyinMatcher.match($0.name, $0.sortKey, query, aliases: $0.aliases) }
        // 别名精确匹配优先 ← Android matched.sortedByDescending{...}: Kotlin 排序稳定,
        // 同键保持原序; Swift sorted 不保证稳定 → 用原始下标做同键 tie-break 复刻稳定语义
        let keyed = matched.enumerated().map { ($0.element, $0.offset) }
        let ordered = keyed.sorted { a, b in
            let aExact = a.0.aliases.contains { $0.lowercased() == q }
            let bExact = b.0.aliases.contains { $0.lowercased() == q }
            if aExact != bExact { return aExact }
            return a.1 < b.1
        }
        return ordered.map { $0.0 }
    }

    private var isUrl: Bool { looksLikeUrl(query) }
    private var urlProtocol: String? { isUrl ? JwImportViewModel.detectProtocolFromUrl(query) : nil }
    /// ← issue #25: 输入 URL 的注册域若与目录条目同域, 直接映射到目录条目
    ///   (拿权威教务 URL + 协议 type), 而不是建 type=nil 的自定义条目。
    private var matchedSchool: JwSchoolInfo? {
        isUrl ? SchoolDomainMatch.matchSchool(normalizeUrl(query.trimmingCharacters(in: .whitespaces)),
                                              viewModel.schools)
              : nil
    }

    private var sections: [SchoolSection] { groupByLetter(filtered) }
    private var showIndexBar: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty && sections.count > 1 }
    private var showRecommendations: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty }
    /// ← derivedStateOf { firstVisibleItemIndex in headerIdx..lastSchoolIdx }:
    ///   高亮 = 已滚过滚动容器顶边的最后一个分组 header(其分组正占据视口顶边);
    ///   列表顶部区(推荐卡/入口行)无任何 header 越线 → nil, 与 Android 顶部无高亮一致。
    ///   离屏回收的 header 保留最后一次观测值(越过顶边后恒 ≤0)。
    private var activeLetter: String? {
        var letter: String? = nil
        for section in sections {
            if let y = scrollModel.headerYs[section.letter], y <= 1 { letter = section.letter }
        }
        return letter
    }
    private var recommendedSchools: [JwSchoolInfo] {
        guard case .ready(let city) = viewModel.schoolLocation else { return [] }
        return SchoolCityIndex.schoolsInCity(viewModel.schools, city: city)
    }
    private var hasLocationPermission: Bool {
        CLLocationManager.authorizationStatus() == .authorizedWhenInUse
            || CLLocationManager.authorizationStatus() == .authorizedAlways
    }
    private var openPermissionSettings: () -> Void {
        {
            // ← Android openPermissionSettings 不碰 resume 标志(仅 locationDisabled 分支设)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }
    private var retryLocation: () -> Void {
        {
            // ← Android retryLocation: LocationDisabled → 开系统设置 + resume 标志;
            //   其余 → requestLocation(): 有权限直接定位, 无权限走授权结果回调定位。
            if CLLocationManager.locationServicesEnabled() {
                if hasLocationPermission {
                    viewModel.locateSchoolCity()
                } else {
                    // ← launcher.launch 等价: 授权回调(granted)里直接 locateSchoolCity,
                    //   不设 resume 标志 — 授权框不离开本 app, 无需「返回续定位」
                    viewModel.locator.requestPermission { granted in
                        if granted { viewModel.locateSchoolCity() }
                    }
                }
            } else {
                // 计算属性 setter 在 struct self 的逃逸闭包里不可变 — 直写 store(真相源)
                store.resumeLocationAfterSettings = true
                // iOS 无公开 API 打开「定位服务」总开关页; app 设置页是最近可达点
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("select_school"), onBack: onDismiss)

            // 搜索框 ← query 存于 SchoolSelectStateStore(rememberSaveable 语义),
            // 跨 WebView 往返不丢; focusRequester 等价 = @FocusState
            TextField(L10n.format("search_school_url"), text: Binding(
                get: { store.query },
                set: { store.query = $0 }
            ))
                .focused($searchFocused)
                .accessibilityIdentifier("school_search")
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(colors.surfaceContainerHighest)   // ← fieldColors 容器色 surfaceContainerHighest
                .cornerRadius(SleepyTheme.fieldShape)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Text(L10n.format("school_pinyin_hint"))
                .font(.system(size: 12))   // ← M3 supportingText bodySmall 12sp
                .foregroundColor(colors.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                // ← M3 supporting 文案缩进 = 字段内 16 + 屏幕边 16 = 32
                .padding(.leading, 32)
                .padding(.trailing, 16)
                .padding(.bottom, 2)

            // 计数行
            HStack {
                Text(L10n.format("school_count_total", viewModel.schools.count))
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
                Spacer()
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("匹配 \(filtered.count)")
                        .font(.system(size: 12))
                        .foregroundColor(colors.primary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)

            if isUrl {
                // issue #25: 域名命中目录条目 → 直接选中目录条目(权威 URL + type),
                // 未命中才回退到自定义条目(与 Android `matchedSchool ?: JwSchoolInfo(...)` 一致)
                UrlDirectRow(url: query.trimmingCharacters(in: .whitespaces),
                             protocolType: urlProtocol,
                             matchedSchool: matchedSchool) {
                    let school = matchedSchool ?? JwSchoolInfo(
                        sortKey: "",
                        name: "自定义教务",
                        url: normalizeUrl(query.trimmingCharacters(in: .whitespaces)),
                        type: urlProtocol,
                        status: JwSchoolInfo.STATUS_SUPPORTED)
                    onSchoolSelected(school)
                }
            }

            if filtered.isEmpty && !isUrl {
                Text(viewModel.schools.isEmpty ? L10n.format("loading") : L10n.format("no_school_found"))
                    .font(.system(size: 16))   // ← Android 无 style 参数 = bodyLarge 16
                    .foregroundColor(colors.onSurfaceVariant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !(isUrl && filtered.isEmpty) {
                // 布局回归修复(本会话引入): ScrollViewReader 的内容闭包是普通 ViewBuilder,
                // 把 AlphabetIndexBar 与 ScrollView 并列为它的两个子节点 = 隐式 VStack 堆叠
                // → 索引栏整条沉到列表下方(iPhone 6 实测「跑到页面底部」)。
                // Android 真值 SchoolSelectScreen.kt: Row { LazyColumn(Modifier.weight(1f));
                // AlphabetIndexBar(Modifier.width(32.dp).fillMaxSize()) } — 索引栏是贴右缘的
                // 水平并列兄弟。此处把整个 HStack 包进 ScrollViewReader(proxy 对尾部索引栏
                // 仍可见), 恢复 HEAD 的兄弟结构。
                ScrollViewReader { proxy in
                    HStack(alignment: .top, spacing: 0) {
                        // 学校列表
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                if showRecommendations {
                                    PossibleSchoolsCard(
                                        state: viewModel.schoolLocation,
                                        schools: recommendedSchools,
                                        isLoadingSchools: viewModel.schools.isEmpty,
                                        onLocate: retryLocation,
                                        onPermissionSettings: openPermissionSettings,
                                        onSchoolSelected: onSchoolSelected,
                                        expanded: expandedCityBinding
                                    )
                                    .padding(.vertical, 8)
                                }
                                // 自定义教务链接入口 — 位于推荐卡后、A 分组前,
                                // 不随搜索过滤消失; 点击聚焦搜索框弹键盘输 URL
                                CustomUrlEntryRow(onClick: { searchFocused = true })
                                DividerRow()
                                ForEach(sections, id: \.letter) { section in
                                    SchoolSectionHeader(letter: section.letter)
                                        .id("header_\(section.letter)")
                                    ForEach(section.schools, id: \.name) { school in
                                        SchoolRow(school: school) {
                                            onSchoolSelected(school)
                                        }
                                        DividerRow()
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                        .coordinateSpace(name: "schoolList")
                        .onPreferenceChange(SectionHeaderMinYKey.self) { scrollModel.merge($0) }
                        .onAppear {
                            // ← SaveableStateProvider 恢复 firstVisibleItemIndex 的一维近似:
                            //   返回本 stage 时跳回上次激活分组
                            if let letter = store.scrollLetter {
                                proxy.scrollTo("header_\(letter)", anchor: .top)
                            }
                        }
                        .onChange(of: activeLetter) { store.scrollLetter = $0 }

                        // 字母索引栏(点击+滑动) — 高亮随滚动派生; 点击直接滚动,
                        // 同字母重复点击也能重新跳转
                        if showIndexBar {
                            AlphabetIndexBar(letters: sections.map { $0.letter },
                                             activeLetter: activeLetter,
                                             onLetterTap: { letter in
                                                 // 跳位后清除目标之后各组的陈旧 minY,
                                                 // 防止高亮粘在旧底部字母(见 dropHeaders)
                                                 scrollModel.dropHeaders(after: letter,
                                                                         in: sections.map { $0.letter })
                                                 withAnimation {
                                                     proxy.scrollTo("header_\(letter)", anchor: .top)
                                                 }
                                             })
                                .frame(width: 32)
                        }
                    }
                }
            }
        }
        .background(colors.background)
        // ← Android DisposableEffect: ON_STOP 取消; ON_RESUME 且来自设置页 → 续定位
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                viewModel.cancelSchoolLocation()
            } else if resumeLocationAfterSettings {
                store.resumeLocationAfterSettings = false
                viewModel.locateSchoolCity()
            }
        }
        .onDisappear {
            viewModel.cancelSchoolLocation()
            // 清掉未完成的授权回调(引用 viewModel, 滞留会挡 VM 释放)
            viewModel.locator.requestPermission(completion: nil)
        }
    }
}

// ← PossibleSchoolsCard(Android 434-530): 同城推荐单卡 — 标题/8 态副标题/定位按钮/
// Ready 空表→loading|no_matches/有表→city_hint+行(expanded?全部:take 5)+分隔线/
// 底部 FlowRow: Ready&&>5 展开/收起 + 恒显权限设置。行走 SchoolRow 原点击路径。
private struct PossibleSchoolsCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let state: SchoolLocationState
    let schools: [JwSchoolInfo]
    let isLoadingSchools: Bool
    let onLocate: () -> Void
    let onPermissionSettings: () -> Void
    let onSchoolSelected: (JwSchoolInfo) -> Void
    @Binding var expanded: String

    // expanded 键控城市(rememberSaveable(city) 语义): 城市变了就回到收起态
    private var isExpanded: Bool { expanded == cityKey }
    private var cityKey: String {
        if case .ready(let city) = state { return city }
        return ""
    }

    private var subtitle: String {
        switch state {
        case .ready(let city):
            let count = schools.count
            return L10n.plural("school_location_city", count, city, count)
        case .locating: return L10n.t("school_location_loading")
        case .permissionDenied: return L10n.t("school_location_denied")
        case .accuracyInsufficient: return L10n.t("school_location_accuracy_insufficient")
        case .locationDisabled: return L10n.t("school_location_disabled")
        case .positionUnavailable: return L10n.t("school_location_no_fix")
        case .unavailable: return L10n.t("school_location_unavailable")
        case .idle: return L10n.t("school_location_hint")
        }
    }

    private var actionLabel: String {
        switch state {
        case .idle: return L10n.t("school_location_locate")
        case .permissionDenied: return L10n.t("school_location_enable")
        case .locationDisabled: return L10n.t("school_location_settings")
        default: return L10n.t("school_location_retry")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("possible_schools"))
                        .font(.system(size: 16, weight: .medium))   // ← titleMedium 16sp
                        .foregroundColor(colors.primary)
                    Text(subtitle)
                        .font(.system(size: 12))                    // ← bodySmall 12sp
                        .foregroundColor(colors.onSurfaceVariant)
                }
                Spacer()
                if state == .locating {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)                           // ← 20dp 圈
                        .padding(8)
                } else {
                    Button(action: onLocate) {
                        Text(actionLabel)
                    }
                    .buttonStyle(SleepyButtonStyle())
                }
            }

            if case .ready = state {
                if schools.isEmpty {
                    Text(isLoadingSchools ? L10n.t("loading") : L10n.t("school_location_no_matches"))
                        .font(.system(size: 12))
                        .padding(.top, 8)
                } else {
                    Text(L10n.t("school_location_city_hint"))
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                        .padding(.top, 8)
                    let visible = isExpanded ? schools : Array(schools.prefix(5))
                    ForEach(visible, id: \.name) { school in
                        // ← Android 卡内行走共享 SchoolRow(含 badge/URL 行), 非独立 inline
                        SchoolRow(school: school) {
                            onSchoolSelected(school)
                        }
                        DividerRow()
                    }
                }
            }

            let showFlowRow: Bool = {
                switch state {
                case .permissionDenied, .accuracyInsufficient: return true
                case .ready: return true
                default: return false
                }
            }()
            if showFlowRow {
                HStack(spacing: 8) {
                    if case .ready = state, schools.count > 5 {
                        Button(action: { expanded = isExpanded ? "" : cityKey }) {
                            Text(isExpanded ? L10n.t("school_location_collapse")
                                            : L10n.t("school_location_show_all"))
                        }
                        .buttonStyle(SleepyButtonStyle())
                    }
                    Button(action: onPermissionSettings) {
                        Text(L10n.t("school_location_permission_settings"))
                    }
                    .buttonStyle(SleepyButtonStyle())
                }
            }
        }
        .padding(12)
        .background(colors.surface)
        .overlay(
            // ← M3 OutlinedCard 默认边框 = outlineVariant 满 alpha 1dp(非 hairline 分隔线)
            RoundedRectangle(cornerRadius: SleepyShapes.medium)
                .stroke(colors.outlineVariant, lineWidth: 1)
        )
        .cornerRadius(SleepyShapes.medium)   // ← OutlinedCard
    }
}

// ← SectionHeader(首字母)
private struct SchoolSectionHeader: View {
    @Environment(\.localWakeUpColors) private var colors
    let letter: String

    var body: some View {
        Text(letter)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(colors.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(colors.primaryContainer.opacity(SleepyTheme.Alpha.hairline))
            .cornerRadius(SleepyShapes.extraSmall)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            // 滚动派生高亮的观测点: 上报 header 在列表坐标系的 minY(← firstVisibleItemIndex)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: SectionHeaderMinYKey.self,
                                           value: [letter: geo.frame(in: .named("schoolList")).minY])
                }
            )
    }
}

// ← AlphabetIndexBar
private struct AlphabetIndexBar: View {
    @Environment(\.localWakeUpColors) private var colors
    let letters: [String]
    let activeLetter: String?
    let onLetterTap: (String) -> Void

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { letter in
                    let isActive = letter == activeLetter
                    Text(letter)
                        .font(.system(size: 11, weight: isActive ? .bold : .regular))
                        .foregroundColor(isActive ? colors.primary : colors.onSurfaceVariant)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(isActive
                            ? colors.primaryContainer.opacity(SleepyTheme.Alpha.inactive)
                            : Color.clear)
                        .cornerRadius(SleepyShapes.extraSmall)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        // 触摸 Y → index 精准对应(每字母 1/N)
                        let ratio = min(max(g.location.y / geo.size.height, 0), 0.999)
                        let idx = Int(ratio * Double(letters.count))
                        if letters.indices.contains(idx) {
                            onLetterTap(letters[idx])
                        }
                    }
            )
        }
        .padding(.trailing, 4)
    }
}

// ← SchoolRow
private struct SchoolRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let school: JwSchoolInfo
    let onClick: () -> Void

    private var isClickable: Bool {
        school.isSupported && !school.url.isEmpty
    }

    var body: some View {
        Group {
            if isClickable {
                Button(action: onClick) {
                    rowContent
                }
                .buttonStyle(SleepyButtonStyle())
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "graduationcap")   // ← Android Icons.Outlined.School
                .font(.system(size: 20))
                .foregroundColor(colors.onPrimaryContainer)
                .frame(width: 36, height: 36)
                .background(colors.primaryContainer)
                .cornerRadius(SleepyShapes.small)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    schoolStatusBadge
                    Text(school.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isClickable ? colors.onSurface : colors.onSurfaceVariant)
                }
                if !school.url.isEmpty {
                    Text(JwProtocol.displayName(school.type) + " · " +
                         school.url.replacingOccurrences(of: "https://", with: "")
                             .replacingOccurrences(of: "http://", with: "")
                             .trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var schoolStatusBadge: some View {
        switch school.status {
        case JwSchoolInfo.STATUS_PENDING:
            badge(label: L10n.t("jw_pending_pending"),
                  background: colors.tertiaryContainer,
                  foreground: colors.onTertiaryContainer)
        case JwSchoolInfo.STATUS_GRAD_PENDING:
            badge(label: L10n.t("jw_pending_pending") + " · " + L10n.t("jw_pending_grad"),
                  background: colors.tertiaryContainer,
                  foreground: colors.onTertiaryContainer)
        case JwSchoolInfo.STATUS_GRAD_SUPPORTED:
            badge(label: L10n.t("jw_pending_grad"),
                  background: colors.secondaryContainer,
                  foreground: colors.onSecondaryContainer)
        case JwSchoolInfo.STATUS_LEGACY:
            badge(label: L10n.t("jw_pending_legacy"),
                  background: colors.surfaceVariant,
                  foreground: colors.onSurfaceVariant)
        default:
            EmptyView()
        }
    }

    private func badge(label: String, background: Color, foreground: Color) -> some View {
        Text(label)
            .font(.system(size: 11))
            .foregroundColor(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background)
            .cornerRadius(SleepyShapes.small)
    }
}

// ← CustomUrlEntryRow(Android 520-565): 「自定义教务链接」引导入口 —
// 与 UrlDirectRow 同构(Link 图标 + primary 色)但语义是引导: 点击不导入,
// 聚焦搜索框弹键盘, 用户把教务 URL 输进去后搜索框下方出现 UrlDirectRow 完成导入。
private struct CustomUrlEntryRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 20))
                    .foregroundColor(colors.onPrimary)
                    .frame(width: 36, height: 36)
                    .background(colors.primary)
                    .cornerRadius(SleepyShapes.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.format("custom_url_entry"))
                        .font(.system(size: 16, weight: .medium))   // ← bodyLarge Medium 16sp
                        .foregroundColor(colors.primary)
                    Text(L10n.format("custom_url_entry_hint"))
                        .font(.system(size: 12))                    // ← bodySmall 12sp
                        .foregroundColor(colors.onSurfaceVariant)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("custom_url_entry_row")
    }
}

// ← UrlDirectRow
private struct UrlDirectRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let url: String
    let protocolType: String?
    /// ← issue #25: 非 nil = 输入 URL 的注册域命中目录条目
    let matchedSchool: JwSchoolInfo?
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 20))
                    .foregroundColor(colors.onPrimary)
                    .frame(width: 36, height: 36)
                    .background(colors.primary)
                    .cornerRadius(SleepyShapes.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.format("url_direct_login"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colors.primary)
                        .accessibilityIdentifier("url_direct_row")
                    Text(url)
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                        .lineLimit(1)
                    if let matched = matchedSchool {
                        // issue #25: 域名映射命中目录条目时, 显示学校名, 比协议名更可确认
                        Text(L10n.format("url_match_school", matched.name))
                            .font(.system(size: 11))   // ← labelSmall 11sp 常规
                            .foregroundColor(colors.primary)
                    } else if let proto = protocolType {
                        Text("\(L10n.format("url_detected")) \(JwProtocol.displayName(proto))")
                            .font(.system(size: 11))   // ← labelSmall 11sp 常规
                            .foregroundColor(colors.primary)
                    } else {
                        Text(L10n.format("url_auto_detect"))
                            .font(.system(size: 11))   // ← labelSmall 11sp 常规
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
        }
        .buttonStyle(SleepyButtonStyle())
    }
}

private struct DividerRow: View {
    @Environment(\.localWakeUpColors) private var colors
    var body: some View {
        Rectangle()
            .fill(colors.outlineVariant.opacity(SleepyTheme.Alpha.hairline))
            .frame(height: 1)
    }
}
