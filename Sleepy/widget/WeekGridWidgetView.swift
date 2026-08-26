// WeekGridWidgetView.swift — ← WeekGridWidgetProvider.kt (v19 网格 + v21 竖排课名)
// 本周课表(网格) widget — 视觉复刻 CourseTableView: 圆角卡片 + gap + today 高亮 + 课名竖排居中。
//
// Canvas bitmap → SwiftUI 网格(平台差异表#5);布局参数逐项对齐:
// outerPad 6 / headH 56 / timeW 40 / gapH 1.5 / gapW 2.5 / 卡片圆角 10 / 容器圆角 18。
// v21 竖排(直书): token 化课名 — CJK 直立 / Latin run≥2 整组旋转90° / 标点按方案A'/B。

import SwiftUI
import WidgetKit

struct WeekGridWidgetEntry: TimelineEntry {
    let date: Date
    let data: WeekData
}

struct WeekGridWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekGridWidgetEntry {
        WeekGridWidgetEntry(date: Date(), data: WeekGridWidgetLoader.loadWeekData())
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekGridWidgetEntry) -> Void) {
        completion(WeekGridWidgetEntry(date: Date(), data: WeekGridWidgetLoader.loadWeekData()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekGridWidgetEntry>) -> Void) {
        let entry = WeekGridWidgetEntry(date: Date(), data: WeekGridWidgetLoader.loadWeekData())
        let refresh = Date().addingTimeInterval(6 * 3600)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - View ← renderBitmap

struct WeekGridWidgetEntryView: View {
    let entry: WeekGridWidgetEntry

    var body: some View {
        let data = entry.data
        let s = resolveWidgetScheme(themeKey: data.themeKey, isDark: data.isDark)
        let colorless = AppPrefs.shared.isWidgetColorless()
        let todayDow = DateUtils.todayDayOfWeek(today: Date())

        // ── 数据 ── (parseTimeSlots → TimeTableUtils; maxNode 派生同 Android)
        let timeJson = data.days.first?.timeJson ?? ""
        let allSlots = Self.parseTimeSlots(timeJson)
        let maxNode = max((data.days.flatMap { $0.courses }
            .map { $0.startNode + $0.step - 1 }.max() ?? allSlots.count), 1)
        let slots = Array(allSlots.prefix(maxNode))
        let sortedDays = data.visibleDays.sorted()
        let dayCount = min(max(sortedDays.count, 1), 7)

        // ── 布局 (dp 跟 CourseTableView 同参数) ──
        let outerPad: CGFloat = 6
        let headH: CGFloat = 56
        let timeW: CGFloat = 40
        let gapH: CGFloat = 1.5
        let gapW: CGFloat = 2.5

        VStack(spacing: 0) {
            // ★ 空状态: 无课表时占位提示, 不渲染空白网格
            // ★ 学期后课程被清空 → 落到这分支; 学期状态文案优先于"去创建课表"
            if !data.hasTable || data.days.isEmpty || data.days.allSatisfy({ $0.courses.isEmpty }) {
                VStack(spacing: 4) {
                    if data.semesterStatus != .inRange {
                        Text(data.semesterStatus == .beforeStart
                             ? L10n.format("semester_not_started")
                             : L10n.format("semester_ended"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(s.onSurface)
                        Text(L10n.format("today_semester_out_hint"))
                            .font(.system(size: 11))
                            .foregroundColor(s.onSurfaceVariant)
                    } else {
                        Text(L10n.format("widget_create_schedule"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(s.onSurface)
                        Text(L10n.format("widget_open_sleepy"))
                            .font(.system(size: 11))
                            .foregroundColor(s.onSurfaceVariant)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    let bodyW = geo.size.width - outerPad * 2
                    let bodyH = max(geo.size.height - outerPad * 2 - headH, 20)
                    let totalGapW = gapW * CGFloat(dayCount + 1)
                    let dayW = max((bodyW - timeW - totalGapW) / CGFloat(dayCount), 20)
                    let totalGapH = gapH * CGFloat(maxNode + 1)
                    let slotH = max((bodyH - totalGapH) / CGFloat(maxNode), 3)

                    VStack(spacing: 0) {
                        // ── Header (Day labels) ──
                        HStack(alignment: .top, spacing: gapW) {
                            // time column 角落
                            ZStack {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(s.surface)
                                // ★ 学期前(课照常显示供预习): 角落画学期状态, 用户知道现在学期没开始
                                if data.semesterStatus == .beforeStart {
                                    Text(L10n.format("semester_not_started"))
                                        .font(.system(size: min(headH * 0.16, 9), weight: .regular))
                                        .foregroundColor(s.onSurfaceVariant)
                                        .minimumScaleFactor(0.6)
                                        .lineLimit(1)
                                        .padding(.horizontal, 2)
                                }
                            }
                            .frame(width: timeW, height: headH)
                            ForEach(sortedDays, id: \.self) { dow in
                                let isToday = dow == todayDow
                                let dayData = data.days.first { $0.dayOfWeek == dow }
                                let count = dayData?.courses.count ?? 0
                                // showDate → 短日期; 否则课程数 / —
                                let sub: String = {
                                    if data.showDate, let dd = dayData { return DateUtils.shortDate(dd.date) }
                                    return count > 0 ? "\(count)" : "—"
                                }()

                                VStack(spacing: 2) {
                                    // day name 字号 = headH * 0.24 cap 13 floor 9
                                    Text(DateUtils.localizedDay(dow))
                                        .font(.system(size: min(max(headH * 0.24, 9), 13), weight: .bold))
                                        .foregroundColor(isToday ? s.primary : s.onSurface)
                                        .minimumScaleFactor(0.7)
                                    // date or count 字号 = headH * 0.18 cap 10 floor 7
                                    Text(sub)
                                        .font(.system(size: min(max(headH * 0.18, 7), 10)))
                                        .foregroundColor(s.onSurfaceVariant)
                                        .minimumScaleFactor(0.7)
                                }
                                .frame(width: dayW, height: headH)
                                .background(isToday ? s.primaryContainer : s.surface)
                                .cornerRadius(14)
                            }
                        }

                        // ── Body ──
                        HStack(alignment: .top, spacing: gapW) {
                            // time column labels
                            VStack(spacing: gapH) {
                                ForEach(1...maxNode, id: \.self) { i in
                                    VStack(spacing: 1) {
                                        // period number 字号 = slotH * 0.40 cap 13 floor 8
                                        Text("\(i)")
                                            .font(.system(size: min(max(slotH * 0.40, 8), 13), weight: .bold))
                                            .foregroundColor(s.onSurface)
                                        // time label 字号 = slotH * 0.20 cap 7 floor 4 (slotH>18 才显示)
                                        if i - 1 < slots.count && slotH > 18 {
                                            Text(slots[i - 1])
                                                .font(.system(size: min(max(slotH * 0.20, 4), 7)))
                                                .foregroundColor(s.onSurfaceVariant)
                                        }
                                    }
                                    .frame(width: timeW, height: slotH)
                                }
                            }

                            // day columns
                            ForEach(Array(sortedDays.enumerated()), id: \.element) { _, dow in
                                if let dayData = data.days.first(where: { $0.dayOfWeek == dow }) {
                                    let isToday = dow == todayDow
                                    WeekGridDayColumn(dayData: dayData, scheme: s, colorless: colorless,
                                                      isToday: isToday, maxNode: maxNode,
                                                      slotH: slotH, dayW: dayW, gapH: gapH)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, outerPad)
                    .padding(.bottom, outerPad)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(s.surfaceContainer)  // bgContainer
        .cornerRadius(18)
        .widgetURL(URL(string: "sleepy://open"))
    }

    // ← parseTimeSlots: timeJson 各节 start 时间; 解析失败回退默认 12 节
    static func parseTimeSlots(_ timeJson: String) -> [String] {
        guard let data = timeJson.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return ["08:00", "08:55", "10:00", "10:55", "14:00", "14:55",
                    "16:00", "16:55", "19:00", "19:55", "20:50", "21:45"]
        }
        return arr.compactMap { $0["start"] as? String }
    }
}

// MARK: - Day column(课程卡)

private struct WeekGridDayColumn: View {
    let dayData: DayData
    let scheme: WidgetScheme
    let colorless: Bool
    let isToday: Bool
    let maxNode: Int
    let slotH: CGFloat
    let dayW: CGFloat
    let gapH: CGFloat

    var body: some View {
        // today 背景列(primaryContainer @ 40/255 ≈ 16%)
        ZStack(alignment: .top) {
            if isToday {
                Rectangle()
                    .fill(scheme.primaryContainer.opacity(40.0 / 255.0))
            }
            VStack(spacing: gapH) {
                // 用对齐网格: maxNode 个槽,课程卡按 startNode 放置
                ForEach(1...maxNode, id: \.self) { node in
                    Group {
                        if let course = courseStarting(at: node) {
                            WeekGridCourseCard(course: course, scheme: scheme, colorless: colorless,
                                               slotH: slotH, gapH: gapH, dayW: dayW,
                                               maxNode: maxNode)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: dayW, height: slotHeight(for: node))
                }
            }
        }
    }

    private func courseStarting(at node: Int) -> CourseEntity? {
        dayData.courses.first { $0.startNode == node }
    }

    /// 该槽高度: 课程起始槽 = step 占多槽(前 step-1 槽由课程卡占位,后续槽高度 0)
    private func slotHeight(for node: Int) -> CGFloat {
        if let c = courseStarting(at: node) {
            return slotH * CGFloat(c.step) + gapH * CGFloat(max(c.step - 1, 0))
        }
        // 该槽被上方课程覆盖? 被覆盖 → 0 高度
        if let covering = dayData.courses.first(where: { $0.startNode < node && $0.startNode + $0.step > node }) {
            _ = covering
            return 0
        }
        return slotH
    }
}

// MARK: - 课程卡(v19k: 课名竖排居中 + 教室底部横排小字)

private struct WeekGridCourseCard: View {
    let course: CourseEntity
    let scheme: WidgetScheme
    let colorless: Bool
    let slotH: CGFloat
    let gapH: CGFloat
    let dayW: CGFloat
    let maxNode: Int

    var body: some View {
        // 卡片背景色 — 统一入口 CourseColorUtil (决策 D3); colorless 灰底传 surfaceVariant
        let baseColor = CourseColorUtil.pickCourseColorSwiftUI(
            course, isDark: scheme.isDark, neutralColor: scheme.surfaceVariant, colorless: colorless)
        // 文字色: 深底白字 / 浅底近黑 (isDarkOn)
        let textColor = Self.isDarkOn(baseColor) ? Color.white : Color(0xFF1D1B20)

        VStack(spacing: 1) {
            // ★ v21: token 化课名竖排
            VerticalNameView(name: course.courseName, charSize: charSize, nameAvailH: nameAvailH,
                             textColor: textColor)
            // ★ 教室: 底部横排小字角标, 0.62× 字号, 半透明, 按卡片宽截断省略
            if !roomStr.isEmpty {
                Text(roomVisible)
                    .font(.system(size: roomSize))
                    .foregroundColor(textColor.opacity(160.0 / 255.0))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(baseColor.opacity(200.0 / 255.0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(baseColor.opacity(80.0 / 255.0), lineWidth: 0.5)
        )
    }

    private var roomStr: String {
        course.room.filter { $0 != "\n" && $0 != " " }
    }

    private var roomSize: CGFloat {
        min(max(charSize * 0.62, 5), 8)
    }

    // 按卡片可用宽算能放几个字符, 超了截断 + … (中文≈0.55em宽)
    private var roomVisible: String {
        let availRoomW = dayW - 8  // unifiedPad*2 = 4*2
        let maxRoomChars = max(Int(availRoomW / (roomSize * 0.55)), 2)
        return roomStr.count > maxRoomChars ? String(roomStr.prefix(maxRoomChars - 1)) + "…" : roomStr
    }

    // v20b: 全表统一字号 — 每 cardH/unitH 理想字号在父级算不了(需要全表信息),
    // SwiftUl 版每卡独立计算: ideal = nameAvailH / unitH, 夹 [11, headH*0.24 cap 13]
    private var charSize: CGFloat {
        let cardH = slotH * CGFloat(course.step) + gapH * CGFloat(max(course.step - 1, 0))
        let availCardH = max(cardH - 8, 0)  // unifiedPad*2
        let roomReserve = roomStr.isEmpty ? 0 : min(11 * 0.7, availCardH * 0.35)
        let nameAvail = max(availCardH - roomReserve, 0)
        let tokens = VerticalNameTokenizer.tokenize(course.courseName)
        let unitH = max(VerticalNameTokenizer.unitHeight(tokens), 1)
        return min(max(nameAvail / unitH, 11), min(56 * 0.24, 13))
    }

    private var nameAvailH: CGFloat {
        let cardH = slotH * CGFloat(course.step) + gapH * CGFloat(max(course.step - 1, 0))
        let availCardH = max(cardH - 8, 0)
        let roomReserve = roomStr.isEmpty ? 0 : min(11 * 0.7, availCardH * 0.35)
        return max(availCardH - roomReserve, 0)
    }

    // ← isDarkOn: 相对亮度 < 0.55 判深色
    static func isDarkOn(_ color: Color) -> Bool {
        CourseColorUtil.luminance(color) < 0.55
    }
}

// MARK: - v21 竖排课名

/// token 化课名竖排渲染 — CJK 直立逐字 / Latin run≥2 整组旋转90° / 标点方案A'旋转
struct VerticalNameView: View {
    let name: String
    let charSize: CGFloat
    let nameAvailH: CGFloat
    let textColor: Color

    var body: some View {
        let tokens = VerticalNameTokenizer.tokenize(name)
        // v22: 字符级贪心截断 + 极端矮卡缩放首字
        let drawn = VerticalNameTokenizer.greedyDraw(tokens: tokens, charSize: charSize,
                                                     nameAvailH: nameAvailH)
        VStack(spacing: 0) {
            ForEach(drawn.indices, id: \.self) { idx in
                let tok = drawn[idx]
                switch tok.type {
                case .cjk:
                    Text(tok.text)
                        .font(.system(size: tok.size, weight: .bold))
                        .foregroundColor(textColor)
                        .frame(height: tok.h)
                case .latin, .punct:
                    // 整组顺时针旋转90°(LATIN run) / 单字旋转90°(PUNCT 方案A')
                    Text(tok.text)
                        .font(.system(size: tok.size, weight: .bold))
                        .foregroundColor(textColor)
                        .rotationEffect(.degrees(90))
                        .frame(height: tok.h)
                }
            }
        }
    }
}

// MARK: - token 化器 ← tokenizeName / measureUnitHeight / PUNCT_CHARS / VERT_FORM_MAP

enum TT { case cjk, latin, punct }

struct NameToken {
    let type: TT
    let text: String
    /// 绘制高度(px) — greedyDraw 输出携带; tokenize 输出为 0
    var h: CGFloat = 0
    /// 绘制字号(px) — 极端矮卡缩放首字场景 < charSize
    var size: CGFloat = 0
}

enum VerticalNameTokenizer {
    /// 标点字符集 — 横排符号, 需特殊处理(旋转或替换)
    static let PUNCT_CHARS: Set<Character> = [
        "(", ")", "（", "）", "〔", "〕", "【", "】", "《", "》", "〈", "〉",
        "「", "」", "『", "』", "[", "]", "{", "}",
        "—", "–", "～", "~", "…", "·", "・", "、", "，", "。", "：", "；",
        "！", "？", "”", "“", "’", "‘", "\"", "'", "/", "／", "｜", "|"
    ]

    /// 方案B: 横排符号 → Unicode Vertical Forms (U+FE19–FE44)
    static let VERT_FORM_MAP: [Character: Character] = [
        "(": "︵", "（": "︵",   // U+FE35
        ")": "︶", "）": "︶",   // U+FE36
        "〔": "︹",                  // U+FE39
        "〕": "︺",                  // U+FE3A
        "【": "︻",                  // U+FE3B
        "】": "︼",                  // U+FE3C
        "《": "︽",                  // U+FE3D
        "》": "︾",                  // U+FE3E
        "〈": "︿",                  // U+FE3F
        "〉": "﹀",                  // U+FE40
        "「": "﹁",                  // U+FE41
        "」": "﹂",                  // U+FE42
        "『": "﹃",                  // U+FE43
        "』": "﹄",                  // U+FE44
        "[": "︻",                  // 复用
        "]": "︼",                  // 复用
        "{": "︷",                  // U+FE37
        "}": "︸",                  // U+FE38
        "—": "︱",                  // U+FE31
        "…": "︙"                    // U+FE19
    ]

    static func isLatin(_ ch: Character) -> Bool {
        ("A"..."Z").contains(ch) || ("a"..."z").contains(ch) || ("0"..."9").contains(ch)
    }

    static func isCJK(_ ch: Character) -> Bool {
        ("一"..."鿿").contains(ch) || ("㐀"..."䶿").contains(ch) || ("豈"..."﫿").contains(ch)
    }

    /// 课名 → token 列表。先去空白, 再扫描连续 run。
    /// 方案B(vertPunctReplace=true): 标点替换 Vertical Forms(变 CJK 直立)
    /// 方案A'(false, 默认): 标点保持原样(绘制时逐个旋转)
    static func tokenize(_ name: String, useVertForms: Bool = false) -> [NameToken] {
        let useVertForms = useVertForms || AppPrefs.shared.isVertPunctReplace()
        let s = name.filter { $0 != "\n" && $0 != " " }
        if s.isEmpty { return [] }
        var tokens: [NameToken] = []
        var sb = ""
        var runType: TT?

        func flush() {
            if !sb.isEmpty, let rt = runType {
                tokens.append(NameToken(type: rt, text: sb))
                sb = ""
            }
            runType = nil
        }

        for ch in s {
            // 方案B: 标点先替换为 Vertical Forms → 归为 CJK 直立
            let c = useVertForms ? (VERT_FORM_MAP[ch] ?? ch) : ch
            let t: TT
            if isCJK(c) { t = .cjk }
            else if PUNCT_CHARS.contains(c) { t = .punct }
            else if isLatin(c) { t = .latin }
            else { t = .cjk }  // 其他字符(含替换后的竖排符号)按 CJK 直立
            if t != runType { flush(); runType = t }
            sb.append(c)
        }
        flush()

        // 后处理: LATIN run 长度=1 → 保持直立(改判 CJK 处理)
        return tokens.map { tok in
            tok.type == .latin && tok.text.count == 1 ? NameToken(type: .cjk, text: tok.text) : tok
        }
    }

    /// token 单位高度(与 charSize 无关的比值): CJK 每字 1.0 / LATIN 组≈组宽 / PUNCT 每字≈0.5
    /// (SwiftUI 无 measureText → 用近似宽度比; CJK=1em, Latin/digit≈0.55em, 标点≈0.5em)
    static func unitHeight(_ tokens: [NameToken]) -> CGFloat {
        var h: CGFloat = 0
        for tok in tokens {
            switch tok.type {
            case .cjk: h += CGFloat(tok.text.count) * 1.0
            case .latin: h += CGFloat(tok.text.count) * 0.55
            case .punct: h += CGFloat(tok.text.count) * 0.5
            }
        }
        return h
    }

    /// v22 字符级贪心截断 → 绘制 token 列表(任何 token 可拆到字符级, 杜绝溢出)
    static func greedyDraw(tokens: [NameToken], charSize: CGFloat, nameAvailH: CGFloat) -> [NameToken] {
        struct DrawnToken {
            let type: TT
            let text: String
            let h: CGFloat
            let size: CGFloat
        }
        var drawn: [DrawnToken] = []
        var cumH: CGFloat = 0
        var truncated = false
        let ellipsisH = charSize  // 省略号占~1字高

        for tok in tokens {
            if truncated { break }
            switch tok.type {
            case .cjk:
                for ch in tok.text {
                    if cumH + charSize > nameAvailH { truncated = true; break }
                    drawn.append(DrawnToken(type: .cjk, text: String(ch), h: charSize, size: charSize))
                    cumH += charSize
                }
            case .latin:
                // 旋转组不可拆: 整组放不下即截断
                let tokH = CGFloat(tok.text.count) * charSize * 0.55
                if cumH + tokH > nameAvailH { truncated = true; break }
                drawn.append(DrawnToken(type: .latin, text: tok.text, h: tokH, size: charSize))
                cumH += tokH
            case .punct:
                for ch in tok.text {
                    let chW = charSize * 0.5
                    if cumH + chW > nameAvailH { truncated = true; break }
                    drawn.append(DrawnToken(type: .punct, text: String(ch), h: chW, size: charSize))
                    cumH += chW
                }
            }
        }

        // 截断后腾省略号高度: 从尾部逐字移除直到 … 放得下
        var showEllipsis = truncated
        if truncated {
            while !drawn.isEmpty && cumH + ellipsisH > nameAvailH {
                cumH -= drawn.removeLast().h
            }
            if drawn.isEmpty { showEllipsis = false }  // 一个字都放不下 → 不画…
        }
        // v22: 极端矮卡 — 缩放首字字号至刚好填满 nameAvailH
        if drawn.isEmpty && !tokens.isEmpty {
            let tinySize = min(max(nameAvailH, 1), charSize)
            let first = String(tokens[0].text.first!)
            drawn.append(DrawnToken(type: .cjk, text: first, h: tinySize, size: tinySize))
            cumH = tinySize
            showEllipsis = false
        }
        if showEllipsis {
            drawn.append(DrawnToken(type: .cjk, text: "…", h: ellipsisH, size: charSize))
        }
        return drawn.map { NameToken(type: $0.type, text: $0.text, h: $0.h, size: $0.size) }
    }
}

struct WeekGridWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekGridWidgetV19", provider: WeekGridWidgetProvider()) { entry in
            WeekGridWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.format("widget_week_grid_label"))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
