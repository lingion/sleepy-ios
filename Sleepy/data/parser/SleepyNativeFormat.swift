// SleepyNativeFormat.swift — ← data/parser/SleepyNativeFormat.kt (逐行翻译, GPL-3.0)
// Sleepy iOS — sleepy-v1 原生格式 纯函数层(规范: sleepy-v1-终稿规范.md §2/§3/§5/§6.1)。
//
// 行式竖线分列: magic 行 `#sleepy-v1` + T(表) / N(作息) / Nd(预设) / C(课程, 恒10列, 可选第11列=课程别名 issue#26) / z(校验) 行。
// 本 enum 只放无状态的常量与纯函数; 解析见 SleepyNativeParser, 导出见 SleepyNativeExporter。

import Foundation

enum SleepyNativeFormat {

    // MARK: - Java/Kotlin 标准库语义 helper(跨端一致性口径)

    /// Kotlin String.trim()/isBlank 的绑定口径 = Kotlin 标准库 Char.isWhitespace
    /// = `java.lang.Character.isWhitespace(c) || java.lang.Character.isSpaceChar(c)`(JDK Zs 类并入)。
    /// 逐码点实测于项目锁定版 kotlin-stdlib 2.1.10(gradle/libs.versions.toml, 反射 StringsKt.trim/isBlank):
    /// \t\n\v\f\r、U+001C-001F、空格、U+1680、U+2000-200A、U+2028/2029、U+205F、U+3000,
    /// **外加 U+00A0(NBSP)/U+2007/U+202F**(Zs 但 Java isWhitespace=false → Kotlin 仍剥)。
    /// 不含 U+200B、不含 NEL U+0085、不含 U+000E-001B(那是 JDK String.trim 的 code<=0x20 口径,
    /// Kotlin 不在此口径 — Android 侧 `line.trim()` 走的是 Kotlin stdlib, 非 JDK 成员)。issue#F051-3
    /// (审计原述「Android 不剥 NBSP」系按 JDK 口径误判, 实测反证后本集合按 Kotlin 真口径修正。)
    static let JAVA_WHITESPACE: CharacterSet = {
        var cs = CharacterSet()
        for (lo, hi) in [(0x0009, 0x000D), (0x001C, 0x001F), (0x2000, 0x2006),
                         (0x2008, 0x200A), (0x2028, 0x2029)] {
            cs.insert(charactersIn: Unicode.Scalar(UInt32(lo))!...Unicode.Scalar(UInt32(hi))!)
        }
        for u in [0x0020, 0x00A0, 0x1680, 0x2007, 0x202F, 0x205F, 0x3000] {
            cs.insert(Unicode.Scalar(UInt32(u))!)
        }
        return cs
    }()

    /// Kotlin String.trim() 等价(按 Kotlin Char.isWhitespace 口径: \n/\r 剥, NBSP 亦剥, NEL 不剥)。
    private static func trimJava(_ s: String) -> String {
        s.trimmingCharacters(in: JAVA_WHITESPACE)
    }

    /// Kotlin lineSequence() 等价: 只按 \n / \r\n / \r 断行;
    /// U+0085/U+2028/U+2029 **不**断行(Swift .newlines 会断 → 两端切行不一致的根因。issue#F051-2)
    private static func linesJava(_ s: String) -> [String] {
        var lines: [String] = []
        var cur = ""
        let scalars = Array(s.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let v = scalars[i].value
            if v == 0x0A || v == 0x0D {
                lines.append(cur)
                cur = ""
                i += 1
                if v == 0x0D, i < scalars.count, scalars[i].value == 0x0A { i += 1 }
            } else {
                cur.unicodeScalars.append(scalars[i])
                i += 1
            }
        }
        lines.append(cur)  // 末段可为空串; 空行与 Kotlin 一致被 isBlank 跳过
        return lines
    }

    /// Unicode Nd 类 BMP 区间(每段 10 个连续码点)。Java Character.isDigit(char) ≡ category==Nd,
    /// 逐 UTF-16 code unit 判定 — 代理半区恒 false, 故补充平面数字经 `length==1`/单位数关都不命中。
    /// 区间表由 UCD 生成, 与 JDK Character.isDigit 逐码点一致(37 段, 含 ASCII 与全角 0xFF10-0xFF19)。
    private static let JAVA_DIGIT_RANGES: [ClosedRange<UInt16>] = [
        0x0030...0x0039, 0x0660...0x0669, 0x06F0...0x06F9, 0x07C0...0x07C9, 0x0966...0x096F,
        0x09E6...0x09EF, 0x0A66...0x0A6F, 0x0AE6...0x0AEF, 0x0B66...0x0B6F, 0x0BE6...0x0BEF,
        0x0C66...0x0C6F, 0x0CE6...0x0CEF, 0x0D66...0x0D6F, 0x0DE6...0x0DEF, 0x0E50...0x0E59,
        0x0ED0...0x0ED9, 0x0F20...0x0F29, 0x1040...0x1049, 0x1090...0x1099, 0x17E0...0x17E9,
        0x1810...0x1819, 0x1946...0x194F, 0x19D0...0x19D9, 0x1A80...0x1A89, 0x1A90...0x1A99,
        0x1B50...0x1B59, 0x1BB0...0x1BB9, 0x1C40...0x1C49, 0x1C50...0x1C59, 0xA620...0xA629,
        0xA8D0...0xA8D9, 0xA900...0xA909, 0xA9D0...0xA9D9, 0xA9F0...0xA9F9, 0xAA50...0xAA59,
        0xABF0...0xABF9, 0xFF10...0xFF19
    ]

    /// 逐 UTF-16 code unit 的 Java Character.isDigit 等价。
    private static func javaIsDigit(_ unit: UInt16) -> Bool {
        JAVA_DIGIT_RANGES.contains { $0.contains(unit) }
    }

    /// Java Character.digit(c, 10) 的 BMP 等价: Nd 码点 → 其十进制位值(0..9)。
    /// 所有 Nd 数字块都是 0x?0..0x?9 连续 10 码点(JDK 17 全 BMP 扫描实测, 见 JAVA_DIGIT_RANGES),
    /// 故 digit = unit - 块首。非 Nd → nil(代理半区恒 nil, 与 char 级 Character.digit 一致)。
    private static func javaDigitValue(_ unit: UInt16) -> Int? {
        for r in JAVA_DIGIT_RANGES where r.contains(unit) { return Int(unit - r.lowerBound) }
        return nil
    }

    /// Java Integer.parseInt / Kotlin toIntOrNull 语义: 可选 +/-、十进制位、Int32 范围;
    /// 空串/仅符号/非数字/超 Int32 → nil。
    /// 关键: JDK parseInt 对 [0-9] 快路径之外的字符走 Character.digit(c,10) — **接受全 BMP 的
    /// Unicode Nd 数字**(实测 parseInt("１")=1、parseInt("١٢")=12), Kotlin toIntOrNull 同 JVM。
    /// 例: Android `parseNodeSpan("１") = (1,1)`、`colorFromToken("１") = 调色板1`;
    /// iOS 旧实现 ASCII-only → nil, 微信转发课表(全角数字常见)两端导入结果不同(issue#F051 补充)。
    /// (Swift Int() 另有 64 位与下划线分叉: "1_0"→10、"3000000000"→成功, Kotlin/JVM 均为 null)
    private static func kotlinInt(_ s: String) -> Int? {
        let units = Array(s.utf16)
        var i = 0
        var negative = false
        if let f = units.first, f == 0x2B || f == 0x2D {  // '+' / '-'
            negative = f == 0x2D
            i = 1
        }
        guard i < units.count else { return nil }
        var acc = 0
        while i < units.count {
            let u = units[i]
            let digit: Int
            if u >= 0x30 && u <= 0x39 { digit = Int(u - 0x30) }
            else if let d = javaDigitValue(u) { digit = d }
            else { return nil }
            acc = acc * 10 + digit
            if acc > 2_147_483_648 { return nil }  // 幅值早封顶(64 位下 acc*10 不会溢出)
            i += 1
        }
        let v = negative ? -acc : acc
        guard v >= -2_147_483_648 && v <= 2_147_483_647 else { return nil }
        return v
    }

    /// Kotlin `t.length == 1 && t[0].isDigit()` → `t[0] - '0'` 的等价:
    /// 仅当串恰为 1 个 UTF-16 code unit 且该 unit 属 Nd 时, 返回 (unit - 0x30)。
    /// 关键: 用码点减法而非 wholeNumberValue, 逐值复刻 Android 的越界上报行为 —
    /// 裸全角`３`(U+FF13) → 0xFF13-0x30 = 65251(交调用方钳制/上报), 而非静默 3;
    /// `²`(No 类) → nil(Android isDigit=false; iOS isNumber=true 旧行为分叉)。issue#F051-1
    private static func singleJavaDigitValue(_ s: String) -> Int? {
        let units = Array(s.utf16)
        guard units.count == 1, javaIsDigit(units[0]) else { return nil }
        return Int(units[0]) - 0x30
    }

    // MARK: - magic 识别 (§6.1)

    /// 行首锚定: ≤4 字符引用/空白前缀 + 1-2 个井号(半/全角) + sleepy + 可选拼缝 + v + 数字。
    /// 整模式大小写不敏感(#SLEEPY-V1 命中且版本=1)。行尾多余内容由 $ 前的宽容处理忽略——
    /// 我们用 find + 范围前缀判定而非严格 fullMatch, 允许尾随标点(§6.3-M「#sleepy-v1。」)。
    /// `\s`/`\d` 按 Android 侧 Kotlin Regex(仅 IGNORE_CASE、无 UNICODE_CHARACTER_CLASS)展开为
    /// Java 默认 ASCII 口径 `[ \t\n\x0B\f\r]`/`[0-9]`: ICU `\s` 含 NBSP/U+3000、`\d` 含全角位,
    /// 不展开会出现「Android 不命中 / iOS 命中」(magic 行以 NBSP 分隔)或「iOS 捕获组吞全角位 →
    /// Int() 失败 -1 / Android 压根不匹配」的两端分叉。
    private static let MAGIC_PATTERN =
        "^[>[ \\t\\n\\u000B\\u000C\\r]]{0,4}[#＃]{1,2}[ \\t\\n\\u000B\\u000C\\r]*"
        + "sleepy[ \\t\\n\\u000B\\u000C\\r\\-_－]*v([0-9]+)"

    /// magic 必须位于前 32 个非空行之一(微信长转发头)
    static let MAGIC_WINDOW = 32

    private static let MAGIC_TEST_RE = try! NSRegularExpression(
        pattern: MAGIC_PATTERN,
        options: [.caseInsensitive])

    /// 识别 sleepy-v* 家族。返回版本号(1=本格式), 未命中 -1。作用于归一后的 trimmed 文本。
    static func detectVersion(_ trimmed: String) -> Int {
        var seen = 0
        for line in linesJava(trimmed) {
            if line.trimmingCharacters(in: JAVA_WHITESPACE).isEmpty { continue }  // Kotlin isBlank
            seen += 1
            if seen > MAGIC_WINDOW { return -1 }
            let t = trimJava(line)  // Kotlin line.trim().trimEnd('\r'); \r 已含于 trim 口径, 二次剥无副作用
            let tns = t as NSString
            let full = NSRange(location: 0, length: tns.length)
            guard let m = MAGIC_TEST_RE.firstMatch(in: t, range: full),
                  m.range(at: 1).location != NSNotFound else { continue }
            return kotlinInt(tns.substring(with: m.range(at: 1))) ?? -1
        }
        return -1
    }

    /// 单行 magic 判定(parser 内层用): 该行本身是否为 magic 行。
    /// = Android parser 的 `private fun isMagicLine(line) = SleepyNativeFormat.detectVersion(line) >= 1`
    /// (v0 不算 magic — 按 Kotlin 口径对齐; 行首尾空白按 Java trim 剥掉后判 ^ 锚定)。
    static func isMagicLine(_ line: String) -> Bool {
        return detectVersion(line) >= 1
    }

    // MARK: - 转义 (§3.3)

    static let RESERVED: Set<Character> = ["\\", "|", "\"", "\n", "\t", "<", "{", "("]

    /// Kotlin `for (c in s)`/`s.none { it in RESERVED }` 均逐 UTF-16 code unit 迭代;
    /// Swift Character 是字素簇 — 反斜杠+结合记号(如 "\"+U+0301)在 Swift 是 1 个字素
    /// 且不等于 "\\"(实测), Kotlin 则拆开判 0x5C。字素口径会让保留字符(尤其 "|")
    /// 后跟结合记号时**漏转义**, 导出物列分隔符裸出 → 两端解析/校验分叉。
    /// (issue#F051 补充: 与 singleJavaDigitValue 同源的单位数口径)
    private static let RESERVED_UNITS: Set<UInt16> = [0x5C, 0x7C, 0x22, 0x0A, 0x09, 0x3C, 0x7B, 0x28]

    /// 导出端转义 8 字符: \ | " \n \t < { ( — 逐 UTF-16 码元(Kotlin String 迭代口径)。
    static func escape(_ s: String) -> String {
        let units = Array(s.utf16)
        if !units.contains(where: { RESERVED_UNITS.contains($0) }) { return s }
        var out: [UInt16] = []
        out.reserveCapacity(units.count + 8)
        for u in units {
            switch u {
            case 0x5C: out.append(contentsOf: [0x5C, 0x5C])   // \\
            case 0x7C: out.append(contentsOf: [0x5C, 0x7C])   // \|
            case 0x22: out.append(contentsOf: [0x5C, 0x22])   // \"
            case 0x0A: out.append(contentsOf: [0x5C, 0x6E])   // \n → 字面 "\n" 两字符
            case 0x09: out.append(contentsOf: [0x5C, 0x74])   // \t
            case 0x3C, 0x7B, 0x28: out.append(contentsOf: [0x5C, u])  // \< \{ \(
            default: out.append(u)
            }
        }
        return String(decoding: out, as: UTF16.self)
    }

    /// 导入端: \n→换行 \t→制表; 其余 \x → 字面 x; 尾部孤立 \ → 字面 \
    /// (同样逐 UTF-16 码元, 复刻 Kotlin `s[i]` 索引语义)
    static func unescape(_ s: String) -> String {
        let units = Array(s.utf16)
        if !units.contains(0x5C) { return s }
        var out: [UInt16] = []
        out.reserveCapacity(units.count)
        var i = 0
        while i < units.count {
            let c = units[i]
            if c == 0x5C, i + 1 < units.count {
                switch units[i + 1] {
                case 0x6E: out.append(0x0A)  // n → 换行
                case 0x74: out.append(0x09)  // t → 制表
                default: out.append(units[i + 1])
                }
                i += 2
            } else {
                out.append(c)
                i += 1
            }
        }
        return String(decoding: out, as: UTF16.self)
    }

    // MARK: - 调色板 (§3.2, 9 色冻结 8 位规范形)

    static let AUTO_COLOR = "#FF6750A4"

    static let PALETTE: [Int: String] = [
        1: "#FFEADDFF", 2: "#FFFFD8E4", 3: "#FFFFDCC4",
        4: "#FFFFF2B8", 5: "#FFD4F7C5", 6: "#FFC5F2E3",
        7: "#FFC9E8FF", 8: "#FFCDD7FF", 9: "#FFF2C4DE"
    ]

    private static let PALETTE_BY_VALUE: [String: Int] = {
        var m: [String: Int] = [:]
        for (k, v) in PALETTE { m[v.uppercased()] = k }
        return m
    }()

    /// Kotlin `hex.all { it.isDigit() || it in 'A'..'F' }` 的 UTF-16 码元等价:
    /// isDigit = Unicode Nd(含全角/阿拉伯数字, 不含 ² 类 No), 'A'..'F' 为 ASCII 大写。
    private static func kotlinHexCharPredicate(_ hex: String) -> Bool {
        for u in hex.utf16 {
            if javaIsDigit(u) { continue }
            if u >= 0x41 && u <= 0x46 { continue }  // 'A'...'F'
            return false
        }
        return true
    }

    /// 导出: 课程色 → token。自动色哨兵→空; 调色板命中→索引; FF alpha 其他→#RRGGBB; 非 FF→#AARRGGBB; 垃圾→空
    static func colorToToken(_ color: String) -> String {
        guard let norm = normalizeColor(color) else { return "" }
        if norm == AUTO_COLOR.uppercased() { return "" }
        if let idx = PALETTE_BY_VALUE[norm] { return String(idx) }
        return norm.hasPrefix("#FF") ? "#" + String(norm.dropFirst(3)) : norm
    }

    /// 导入: token → 课程色。索引→规范形; #6 位→补 FF; #9 位→原样; 空/非法→自动色
    static func colorFromToken(_ token: String) -> String {
        let t = trimJava(token)
        if t.isEmpty { return AUTO_COLOR }
        if let idx = kotlinInt(t) { return PALETTE[idx] ?? AUTO_COLOR }
        if t.hasPrefix("#") {
            let hex = String(t.dropFirst()).uppercased()
            switch hex.utf16.count {  // Kotlin hex.length = UTF-16 码元数
            case 6: return "#FF\(hex)"  // Android 6 位分支不校验字符, 原样补 FF
            case 8 where kotlinHexCharPredicate(hex): return "#\(hex)"
            default: return AUTO_COLOR
            }
        }
        return AUTO_COLOR
    }

    /// 归一为 8 位 #AARRGGBB 大写; 非法 → nil
    private static func normalizeColor(_ color: String) -> String? {
        let t = trimJava(color).uppercased()
        guard t.hasPrefix("#") else { return nil }
        let hex = String(t.dropFirst())
        if hex.utf16.contains(where: { !javaIsDigit($0) && !($0 >= 0x41 && $0 <= 0x46) }) { return nil }
        switch hex.utf16.count {  // Kotlin when (hex.length) — UTF-16 码元数
        case 6: return "#FF\(hex)"
        case 8: return "#\(hex)"
        default: return nil
        }
    }

    // MARK: - lenient 基元解析 (§2 文法, §7 容错)

    /// `H:mm` / `HH:mm` / 全角冒号 → (h, min); 越界/非法 → nil
    /// `\d` 按 Java 默认 ASCII 口径写死 [0-9](Android Regex 未开 UNICODE_CHARACTER_CLASS)。
    /// `$` 保留(非 `\z`): JDK17 实测 Java 非 MULTILINE 的 `$` 也命中「末尾行终止符之前」
    /// (NEL U+0085/U+2028 尾缀 find=true), ICU `$` 同构 → 两端一致; `\z` 反而制造分叉。
    static func parseClock(_ s: String) -> (h: Int, min: Int)? {
        let t = trimJava(s).replacingOccurrences(of: "：", with: ":")
        guard let m = t.range(of: "^([0-9]{1,2}):([0-9]{2})$", options: .regularExpression) else { return nil }
        let parts = t[m].components(separatedBy: ":")
        guard let h = Int(parts[0]), let min = Int(parts[1]), (0...23).contains(h), (0...59).contains(min) else { return nil }
        return (h, min)
    }

    private static let DATE_RE = try! NSRegularExpression(pattern: "^([0-9]{4})[-/.]?([0-9]{1,2})[-/.]?([0-9]{1,2})$")

    /// `YYYY-MM-DD`(/ . 或紧凑) → 归一到所在周一的 `YYYY-MM-DD`; 非法 → nil
    static func parseDate(_ s: String) -> String? {
        let t = trimJava(s)
        let ns = t as NSString
        guard let m = DATE_RE.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) else { return nil }
        guard let y = Int(ns.substring(with: m.range(at: 1))),
              let mo = Int(ns.substring(with: m.range(at: 2))),
              let d = Int(ns.substring(with: m.range(at: 3))),
              1 <= mo && mo <= 12, 1 <= d && d <= 31,
              let date = dateFrom(y: y, mo: mo, d: d) else { return nil }
        return mondayOf(date)
    }

    private static func dateFrom(y: Int, mo: Int, d: Int) -> Date? {
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d
        let cal = Calendar(identifier: .gregorian)
        guard let date = cal.date(from: comps) else { return nil }
        // LocalDate.of 语义: 溢出日期(2/30 等)抛异常 → null
        var probe = DateComponents()
        probe.year = y; probe.month = mo; probe.day = 1
        guard let first = cal.date(from: probe),
              cal.component(.month, from: date) == mo else { return nil }
        _ = first
        return date
    }

    private static func mondayOf(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        // DayOfWeek.MONDAY 语义: ISO, 周一=1; 找到本周或上周一
        let wd = cal.component(.weekday, from: date)  // 1=Sunday ... 7=Saturday
        let daysBack = (wd + 5) % 7  // Sunday(1)→6, Monday(2)→0, ... Saturday(7)→5
        let monday = cal.date(byAdding: .day, value: -daysBack, to: date)!
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: monday)
    }

    /// `S` / `S-E` → (startNode, endNode); 形状非法 → nil
    static func parseNodeSpan(_ s: String) -> (Int, Int)? {
        let t = trimJava(s)
        if t.isEmpty { return nil }
        let parts = t.components(separatedBy: "-")
        switch parts.count {
        case 1: return kotlinInt(parts[0]).map { ($0, $0) }
        case 2:
            guard let a = kotlinInt(parts[0]), let b = kotlinInt(parts[1]) else { return nil }
            return (a, b)
        default: return nil
        }
    }

    // MARK: - 周次

    /// 周次五形态 + 容忍后缀 → WeekSpec; 形状非法 → nil。反写区间 (E<S) 交调用方钳制。
    struct WeekSpec { let start: Int; let end: Int; let type: Int }

    private static let WEEK_SPEC_RE = try! NSRegularExpression(
        pattern: "^([0-9]+)(?:([-~–—〜至])([0-9]+))?(单|双|定|散|奇|偶|o|odd|e|even)?$")

    static func parseWeekSpec(_ s: String) -> WeekSpec? {
        let t = trimJava(s)
        if t.isEmpty { return nil }
        let ns = t as NSString
        guard let m = WEEK_SPEC_RE.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) else { return nil }
        guard let start = kotlinInt(ns.substring(with: m.range(at: 1))) else { return nil }
        let hasEnd = m.range(at: 3).location != NSNotFound
        let end = hasEnd ? (kotlinInt(ns.substring(with: m.range(at: 3))) ?? start) : start
        // 参与组判定: 未参与返回 NSNotFound(等价 Kotlin 空串语义)
        let suffix = m.range(at: 4).location != NSNotFound ? ns.substring(with: m.range(at: 4)) : ""
        let type: Int
        switch suffix {
        case "", "null":
            type = hasEnd ? 0 : 3  // 裸单数字=只上这周; 区间无后缀=每周
        case "单", "奇", "o", "odd": type = 1
        case "双", "偶", "e", "even": type = 2
        case "定", "散": type = 3
        default: return nil
        }
        return WeekSpec(start: start, end: end, type: type)
    }

    // MARK: - 周次导出(§4 规范形)

    /// (S,E,type) → 规范形 token。type 0 恒带横线(8-8); type 3 恒带后缀(单值写 S定)。
    static func weekSpecToToken(_ startWeek: Int, _ endWeek: Int, _ type: Int) -> String {
        let range = "\(startWeek)-\(endWeek)"
        switch type {
        case 1: return range + "单"
        case 2: return range + "双"
        case 3: return startWeek == endWeek ? "\(startWeek)定" : range + "定"
        default: return range
        }
    }

    // MARK: - 星期 (§3.1 day 列)

    private static let DAY_NAMES: [String: Int] = [
        "一": 1, "二": 2, "三": 3, "四": 4,
        "五": 5, "六": 6, "日": 7, "天": 7
    ]

    /// `1..7` / `周X` / `星期X` / `礼拜X` / 裸`三`; 非法形状 → nil。
    /// 越界单数字(0/8/9 及非 ASCII Nd 全角数字)交调用方钳制 — 数字判定 =
    /// Kotlin `length==1 && t[0].isDigit()` → `t[0]-'0'`(Nd 类逐码元 + 码点减法):
    /// `周３` → 65251(与 Android 相同的越界上报, 不再 wholeNumberValue 静默 3), `²` → nil。
    static func parseDay(_ s: String) -> Int? {
        let t = trimJava(s)
        if t.isEmpty { return nil }
        // §2 文法 day = DIGIT{1}|周X…: 形状层只认单数字, 多位(13/2026)属形状非法
        if let v = singleJavaDigitValue(t) { return v }
        var stripped = Substring(t)
        for p in ["礼拜", "星期", "周"] where stripped.hasPrefix(p) { stripped = stripped.dropFirst(p.count) }
        if let v = DAY_NAMES[String(stripped)] { return v }
        // 周X/星期X 后跟单数字 (§2: ...|"天"|DIGIT{1}) — 同 Java 口径
        return singleJavaDigitValue(String(stripped))
    }

    // MARK: - Nd 冻结预设 (§5; 规范常量而非应用当前默认)

    /// (start, end) 对, 节号 = 下标 + 1。与 TimeTableUtils.DEFAULT_TIME_JSON 逐值一致(测试锁定)。
    static let ND_PRESET: [(Int, Int)] = [
        (8 * 60 + 0, 8 * 60 + 45), (8 * 60 + 55, 9 * 60 + 40),
        (10 * 60 + 0, 10 * 60 + 45), (10 * 60 + 55, 11 * 60 + 40),
        (14 * 60 + 0, 14 * 60 + 45), (14 * 60 + 55, 15 * 60 + 40),
        (16 * 60 + 0, 16 * 60 + 45), (16 * 60 + 55, 17 * 60 + 40),
        (19 * 60 + 0, 19 * 60 + 45), (19 * 60 + 55, 20 * 60 + 40),
        (20 * 60 + 50, 21 * 60 + 35), (21 * 60 + 45, 22 * 60 + 30)
    ]

    /// 作息逐值等于冻结预设? (导出端决定写 Nd 还是逐节 N 行)
    static func matchesNdPreset(_ timeJson: String) -> Bool {
        let nodes = TimeTableUtils.parseNodes(timeJson)
        if nodes.count != ND_PRESET.count { return false }
        let cal = Calendar(identifier: .gregorian)
        for (i, n) in nodes.enumerated() {
            if n.node != i + 1 { return false }
            let sm = cal.component(.hour, from: n.start) * 60 + cal.component(.minute, from: n.start)
            let em = cal.component(.hour, from: n.end) * 60 + cal.component(.minute, from: n.end)
            if sm != ND_PRESET[i].0 || em != ND_PRESET[i].1 { return false }
        }
        return true
    }

    /// HH:mm
    static func fmtTime(h: Int, min: Int) -> String {
        String(format: "%02d:%02d", h, min)
    }

    // MARK: - crc32 (§8.1-3, 8 位小写 hex)

    /// 标准 CRC-32 (IEEE 802.3, 多项式 0xEDB88320 反射) — 与 java.util.zip.CRC32 逐位一致
    static func crc32(_ data: Data) -> String {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1
            }
        }
        crc = ~crc
        return String(format: "%08x", crc)
    }
}
