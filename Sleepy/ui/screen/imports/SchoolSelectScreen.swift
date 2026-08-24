// SchoolSelectScreen.swift — ← ui/screen/imports/SchoolSelectScreen.kt (514 行)
// 学校选择页 — 教务直连第一步。
// schools.json 145 所 + 拼音搜索(PinyinMatcher) + URL 直连识别(detectProtocolFromUrl)
// + 首字母分组(sortKeyFull 拼音排序) + 右侧字母索引栏(点击/滑动跳转)。

import SwiftUI

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
    let sorted = schools.sorted { schoolSortKey($0) < schoolSortKey($1) }
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
    let onSchoolSelected: (JwSchoolInfo) -> Void
    let onBack: () -> Void

    @StateObject private var viewModel = JwImportViewModel()
    @State private var query = ""
    @State private var selectedLetter: String? = nil

    private var filtered: [JwSchoolInfo] {
        let schools = viewModel.schools
        if query.trimmingCharacters(in: .whitespaces).isEmpty { return schools }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matched = schools.filter { PinyinMatcher.match($0.name, $0.sortKey, query, aliases: $0.aliases) }
        // 别名精确匹配优先
        return matched.sorted { a, b in
            let aExact = a.aliases.contains { $0.lowercased() == q }
            let bExact = b.aliases.contains { $0.lowercased() == q }
            if aExact != bExact { return aExact }
            return false
        }
    }

    private var isUrl: Bool { looksLikeUrl(query) }
    private var urlProtocol: String? { isUrl ? JwImportViewModel.detectProtocolFromUrl(query) : nil }

    private var sections: [SchoolSection] { groupByLetter(filtered) }
    private var showIndexBar: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty && sections.count > 1 }

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("select_school"), onBack: onBack)

            // 搜索框
            TextField(L10n.format("search_school_url"), text: $query)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(colors.surfaceContainer)
                .cornerRadius(SleepyTheme.fieldShape)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Text(L10n.format("school_pinyin_hint"))
                .font(.system(size: 10))
                .foregroundColor(colors.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

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
                UrlDirectRow(url: query.trimmingCharacters(in: .whitespaces),
                             protocolType: urlProtocol) {
                    let school = JwSchoolInfo(
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
                    .foregroundColor(colors.onSurfaceVariant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !(isUrl && filtered.isEmpty) {
                HStack(alignment: .top, spacing: 0) {
                    // 学校列表
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
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
                        .onChange(of: selectedLetter) { letter in
                            if let letter = letter {
                                withAnimation {
                                    proxy.scrollTo("header_\(letter)", anchor: .top)
                                }
                            }
                        }
                    }

                    // 字母索引栏(点击+滑动)
                    if showIndexBar {
                        AlphabetIndexBar(letters: sections.map { $0.letter },
                                         activeLetter: selectedLetter,
                                         onLetterTap: { selectedLetter = $0 })
                            .frame(width: 32)
                    }
                }
            }
        }
        .background(colors.background)
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

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 12) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 20))
                    .foregroundColor(colors.onPrimaryContainer)
                    .frame(width: 36, height: 36)
                    .background(colors.primaryContainer)
                    .cornerRadius(SleepyShapes.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(school.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colors.onSurface)
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
        .buttonStyle(.plain)
    }
}

// ← UrlDirectRow
private struct UrlDirectRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let url: String
    let protocolType: String?
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
                    Text(url)
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                        .lineLimit(1)
                    if let proto = protocolType {
                        Text("\(L10n.format("url_detected")) \(JwProtocol.displayName(proto))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.primary)
                    } else {
                        Text(L10n.format("url_auto_detect"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
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
