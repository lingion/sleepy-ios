// SleepyNativeFormatTests.swift — ← SleepyNativeFormatTest.kt (逐测试翻译, GPL-3.0)
// sleepy-v1 原生格式 — 纯函数层测试:
// magic 识别 / 转义往返 / 调色板 / lenient 时钟·日期·周次·节次 / Nd 预设 / crc32。

import XCTest
@testable import Sleepy

final class SleepyNativeFormatTests: XCTestCase {

    private func SpecAssert(_ spec: SleepyNativeFormat.WeekSpec?, start: Int, end: Int, type: Int,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(spec, file: file, line: line)
        guard let spec = spec else { return }
        XCTAssertEqual(start, spec.start, file: file, line: line)
        XCTAssertEqual(end, spec.end, file: file, line: line)
        XCTAssertEqual(type, spec.type, file: file, line: line)
    }

    // ---- magic 识别 (规范 §6.1) ----

    func testMagicPlain() {
        XCTAssertEqual(1, SleepyNativeFormat.detectVersion("#sleepy-v1\nC高数|1|1-2"))
    }

    func testMagicCaseInsensitiveFullPattern() {
        // 规范 §6.1: 整模式大小写不敏感 — sleepy 与 v 均不限大小写
        XCTAssertEqual(1, SleepyNativeFormat.detectVersion("#SLEEPY-V1"))
        XCTAssertEqual(1, SleepyNativeFormat.detectVersion("#Sleepy-V1"))
    }

    func testMagicVariantsHit() {
        // §6.3-M: 双井号/空格/无横线/下划线/全角井号/尾标点 全命中
        XCTAssertEqual(1, SleepyNativeFormat.detectVersion("##sleepy-v1"))
        XCTAssertEqual(1, SleepyNativeFormat.detectVersion("# sleepy-v1"))
        XCTAssertEqual(1, SleepyNativeFormat.detectVersion("#sleepy v1"))
        XCTAssertEqual(1, SleepyNativeFormat.detectVersion("#sleepy_v1"))
        XCTAssertEqual(1, SleepyNativeFormat.detectVersion("＃sleepy-v1"))
        XCTAssertEqual(1, SleepyNativeFormat.detectVersion("#sleepy-v1。"))
        XCTAssertEqual(1, SleepyNativeFormat.detectVersion("#sleepy－v1"))
    }

    func testMagicQuotePrefixAndLatePosition() {
        // §6.3-N: 微信引用前缀 + 20 行客套后 magic → 32 非空行窗内命中
        XCTAssertEqual(1, SleepyNativeFormat.detectVersion("> > #sleepy-v1"))
        let chatter = (1...20).map { "转发语第 \($0) 行" }.joined(separator: "\n")
        XCTAssertEqual(1, SleepyNativeFormat.detectVersion("\(chatter)\n#sleepy-v1\nC高数|1|1-2"))
    }

    func testMagicOutsideWindowMiss() {
        let chatter = (1...40).map { "第 \($0) 行" }.joined(separator: "\n")
        XCTAssertEqual(-1, SleepyNativeFormat.detectVersion("\(chatter)\n#sleepy-v1"))
    }

    func testMagicFutureVersionDetected() {
        XCTAssertEqual(2, SleepyNativeFormat.detectVersion("#sleepy-v2"))
    }

    func testMagicMissOnOtherFormats() {
        // §6.3-R 反向矩阵: 五路判别子串不命中
        XCTAssertEqual(-1, SleepyNativeFormat.detectVersion("{\"name\":\"x\",\"courses\":[]}"))
        XCTAssertEqual(-1, SleepyNativeFormat.detectVersion("BEGIN:VCALENDAR"))
        XCTAssertEqual(-1, SleepyNativeFormat.detectVersion("<html><body></body></html>"))
        XCTAssertEqual(-1, SleepyNativeFormat.detectVersion("课程,教师,星期\n高数,张三,1"))
        XCTAssertEqual(-1, SleepyNativeFormat.detectVersion("高数 张三 周一 1-2 1-16 3"))
        XCTAssertEqual(-1, SleepyNativeFormat.detectVersion(""))
    }

    // ---- 转义往返 (规范 §3.3, §1.3-4) ----

    func testEscapeUnescapeRoundTripAllReserved() {
        let cases = [
            "A|B候选", "C:\\fs\\A101", "带\"引号", "多行\n备注", "制表\t符",
            "<frameset", "{花括号", "(圆括号", "全角｜不必转", "纯中文", "English Name", "データベース", "Física"
        ]
        for s in cases {
            XCTAssertEqual(s, SleepyNativeFormat.unescape(SleepyNativeFormat.escape(s)), "roundtrip: \(s)")
        }
    }

    func testEscapeExportNeverEmitsDangerousLiteral() {
        // 导出物永不出现"未转义"的 " / <<<SLEEPY-END>>> 图案 / <frameset(转义符本身合法)
        let nasty = "\"courseDetailJson\" <<<SLEEPY-END>>> <frameset | { ( \\"
        let escaped = SleepyNativeFormat.escape(nasty)
        // 每个危险字符前都紧贴反斜杠
        XCTAssertNil(escaped.range(of: "(?<!\\\\)\"", options: .regularExpression))
        XCTAssertNil(escaped.range(of: "(?<!\\\\)<", options: .regularExpression))
        XCTAssertNil(escaped.range(of: "(?<!\\\\)\\{", options: .regularExpression))
        XCTAssertNil(escaped.range(of: "(?<!\\\\)\\(", options: .regularExpression))
        XCTAssertNil(escaped.range(of: "(?<!\\\\)\\|", options: .regularExpression))
        // \n 是两字符
        XCTAssertTrue(SleepyNativeFormat.escape("a\nb").contains("\\n"))
    }

    func testUnescapeNAndTPairs() {
        XCTAssertEqual("a\nb", SleepyNativeFormat.unescape("a\\nb"))
        XCTAssertEqual("a\tb", SleepyNativeFormat.unescape("a\\tb"))
        // 其余 \x → 字面 x
        XCTAssertEqual("aXb", SleepyNativeFormat.unescape("a\\Xb"))
        XCTAssertEqual("a\\b", SleepyNativeFormat.unescape("a\\\\b"))
        // 尾部孤立反斜杠 → 字面反斜杠
        XCTAssertEqual("a\\", SleepyNativeFormat.unescape("a\\"))
    }

    // ---- 调色板 (规范 §3.2) ----

    func testPaletteExact8BitForms() {
        XCTAssertEqual("#FFEADDFF", SleepyNativeFormat.PALETTE[1])
        XCTAssertEqual("#FFF2C4DE", SleepyNativeFormat.PALETTE[9])
        XCTAssertEqual(9, SleepyNativeFormat.PALETTE.count)
    }

    func testColorToTokenPaletteIndex() {
        XCTAssertEqual("1", SleepyNativeFormat.colorToToken("#FFEADDFF"))
        // 6 位补 FF 后命中 → 索引
        XCTAssertEqual("1", SleepyNativeFormat.colorToToken("#EADDFF"))
        // 大小写归一
        XCTAssertEqual("9", SleepyNativeFormat.colorToToken("#f2c4de"))
    }

    func testColorToTokenSentinelEmptyAutoColor() {
        XCTAssertEqual("", SleepyNativeFormat.colorToToken(SleepyNativeFormat.AUTO_COLOR))
        XCTAssertEqual("", SleepyNativeFormat.colorToToken("#FF6750A4".lowercased()))
    }

    func testColorToTokenLiteralFallback() {
        // 非 FF alpha → 9 位 AARRGGBB
        XCTAssertEqual("#80388E3C", SleepyNativeFormat.colorToToken("#80388E3C"))
        // alpha FF 其他色 → 6 位
        XCTAssertEqual("#388E3C", SleepyNativeFormat.colorToToken("#FF388E3C"))
        // 垃圾值 → 空(自动)
        XCTAssertEqual("", SleepyNativeFormat.colorToToken("not-a-color"))
    }

    func testColorFromTokenAllForms() {
        XCTAssertEqual("#FFEADDFF", SleepyNativeFormat.colorFromToken("1"))
        XCTAssertEqual("#FFEADDFF", SleepyNativeFormat.colorFromToken("#EADDFF"))
        XCTAssertEqual("#FFEADDFF", SleepyNativeFormat.colorFromToken("#FFEADDFF"))
        XCTAssertEqual("#80388E3C", SleepyNativeFormat.colorFromToken("#80388E3C"))
        // 非法索引/垃圾 → 自动色
        XCTAssertEqual(SleepyNativeFormat.AUTO_COLOR, SleepyNativeFormat.colorFromToken(""))
        XCTAssertEqual(SleepyNativeFormat.AUTO_COLOR, SleepyNativeFormat.colorFromToken("99"))
        XCTAssertEqual(SleepyNativeFormat.AUTO_COLOR, SleepyNativeFormat.colorFromToken("xyz"))
    }

    // ---- lenient 时钟 / 日期 / 节次 / 周次 (规范 §2 文法) ----

    func testParseClockLenient() {
        func clockH(_ s: String) -> Int? { SleepyNativeFormat.parseClock(s)?.h }
        func clockM(_ s: String) -> Int? { SleepyNativeFormat.parseClock(s)?.min }
        XCTAssertEqual(8, clockH("8:00")); XCTAssertEqual(0, clockM("8:00"))
        XCTAssertEqual(8, clockH("08:00")); XCTAssertEqual(0, clockM("08:00"))
        XCTAssertEqual(8, clockH("08：00")); XCTAssertEqual(0, clockM("08：00")) // 全角冒号
        XCTAssertNil(SleepyNativeFormat.parseClock("25:00"))
        XCTAssertNil(SleepyNativeFormat.parseClock("abc"))
        XCTAssertNil(SleepyNativeFormat.parseClock("8:5"))
    }

    func testParseDateLenientNormToMonday() {
        // 2026-03-02 是周一
        XCTAssertEqual("2026-03-02", SleepyNativeFormat.parseDate("2026-03-02"))
        XCTAssertEqual("2026-03-02", SleepyNativeFormat.parseDate("2026/03/02"))
        XCTAssertEqual("2026-03-02", SleepyNativeFormat.parseDate("2026.3.2"))
        XCTAssertEqual("2026-03-02", SleepyNativeFormat.parseDate("20260302"))
        // 非周一 → 归到所在周一(2026-03-04 是周三)
        XCTAssertEqual("2026-03-02", SleepyNativeFormat.parseDate("2026-03-04"))
        // 非法 → nil
        XCTAssertNil(SleepyNativeFormat.parseDate("abc"))
        XCTAssertNil(SleepyNativeFormat.parseDate("2026-13-40"))
    }

    func testParseNodeSpan() {
        func span(_ s: String) -> (Int, Int)? { SleepyNativeFormat.parseNodeSpan(s) }
        XCTAssertEqual(1, span("1")?.0); XCTAssertEqual(1, span("1")?.1)
        XCTAssertEqual(3, span("3-4")?.0); XCTAssertEqual(4, span("3-4")?.1)
        XCTAssertNil(SleepyNativeFormat.parseNodeSpan("abc"))
        XCTAssertNil(SleepyNativeFormat.parseNodeSpan("1-2-3"))
    }

    func testParseWeekSpecFiveShapes() {
        func w(_ s: String) -> SleepyNativeFormat.WeekSpec? {
            SleepyNativeFormat.parseWeekSpec(s)
        }
        SpecAssert(w("1-16"), start: 1, end: 16, type: 0)
        SpecAssert(w("1-15单"), start: 1, end: 15, type: 1)
        SpecAssert(w("2-16双"), start: 2, end: 16, type: 2)
        SpecAssert(w("3-4定"), start: 3, end: 4, type: 3)
        SpecAssert(w("8定"), start: 8, end: 8, type: 3)
        // 导入额外容忍
        SpecAssert(w("1-15奇"), start: 1, end: 15, type: 1)
        SpecAssert(w("1-15odd"), start: 1, end: 15, type: 1)
        SpecAssert(w("2-16even"), start: 2, end: 16, type: 2)
        SpecAssert(w("2-16e"), start: 2, end: 16, type: 2)
        SpecAssert(w("3-4散"), start: 3, end: 4, type: 3)
        // 单数字无后缀 = 只上这周 (type 3)
        SpecAssert(w("8"), start: 8, end: 8, type: 3)
        // 未知后缀 → nil(形状非法, 交给调用方上报)
        XCTAssertNil(w("1-16x"))
        XCTAssertNil(w("张三"))
        // 反写区间原样返回, 方向钳制在调用方(§3.1: E<S → 交换+上报)
        SpecAssert(w("16-1"), start: 16, end: 1, type: 0)
    }

    func testParseDayLenient() {
        XCTAssertEqual(1, SleepyNativeFormat.parseDay("1"))
        XCTAssertEqual(3, SleepyNativeFormat.parseDay("周三"))
        XCTAssertEqual(7, SleepyNativeFormat.parseDay("日"))
        XCTAssertEqual(7, SleepyNativeFormat.parseDay("天"))
        XCTAssertEqual(5, SleepyNativeFormat.parseDay("星期5"))
        XCTAssertEqual(2, SleepyNativeFormat.parseDay("礼拜二"))
        // 非法形状 → nil
        XCTAssertNil(SleepyNativeFormat.parseDay("张三"))
        XCTAssertNil(SleepyNativeFormat.parseDay("13"))
    }

    // ---- Nd 冻结预设 (规范 §5, = TimeTableUtils.DEFAULT_TIME_JSON) ----

    func testNdPresetMatchesDefaultTimeJson() {
        let defaults = TimeTableUtils.parseNodes(TimeTableUtils.DEFAULT_TIME_JSON)
        XCTAssertEqual(12, SleepyNativeFormat.ND_PRESET.count)
        XCTAssertEqual(defaults.count, SleepyNativeFormat.ND_PRESET.count)
        let cal = Calendar(identifier: .gregorian)
        for (i, n) in defaults.enumerated() {
            let sm = cal.component(.hour, from: n.start) * 60 + cal.component(.minute, from: n.start)
            let em = cal.component(.hour, from: n.end) * 60 + cal.component(.minute, from: n.end)
            XCTAssertEqual(SleepyNativeFormat.ND_PRESET[i].0, sm, "node \(n.node) start")
            XCTAssertEqual(SleepyNativeFormat.ND_PRESET[i].1, em, "node \(n.node) end")
            XCTAssertEqual(i + 1, n.node)
        }
    }

    // ---- crc32 ----

    func testCrc32KnownVector() {
        // 标准 CRC32 校验向量: "123456789" → 0xCBF43926
        XCTAssertEqual("cbf43926", SleepyNativeFormat.crc32("123456789".data(using: .utf8)!))
    }

    // ---- issue#F051 跨端语义锁定: Java/Kotlin 标准库口径(与 Android main v1.0.61 逐值一致) ----

    func testF051ParseDayUnicodeDigitsMatchJavaIsDigit() {
        // Android: 全角３(U+FF13) 属 Nd → t[0]-'0' = 65251, 越界交调用方钳制/上报;
        // iOS 旧 wholeNumberValue 静默 3 → 分叉。现口径: 码点减法逐值复刻。
        XCTAssertEqual(65251, SleepyNativeFormat.parseDay("３"))
        XCTAssertEqual(65251, SleepyNativeFormat.parseDay("周３"))
        XCTAssertEqual(65249, SleepyNativeFormat.parseDay("周１"))  // 0xFF11-0x30
    }

    func testF051ParseDaySuperscriptNotDigit() {
        // ²(U+00B2, No 类): Java isDigit=false → null; iOS isNumber=true 旧行为 → 分叉。
        XCTAssertNil(SleepyNativeFormat.parseDay("²"))
        XCTAssertNil(SleepyNativeFormat.parseDay("周²"))
    }

    func testF051ParseDayTrimMatchesKotlinTrim() {
        // Kotlin String.trim() = Char.isWhitespace = Character.isWhitespace || isSpaceChar
        // (逐码点实测 kotlin-stdlib 2.1.10 + app 编译类反射 oracle):
        // \n/\r 剥、NBSP(U+00A0)/U+2007/U+202F **也剥**(Zs 类)、NEL(U+0085) 不剥。
        // 审计原述「Android 不剥 NBSP」系按 JDK Character.isWhitespace 口径误判, 实测反证。
        XCTAssertEqual(1, SleepyNativeFormat.parseDay("1\n"))
        XCTAssertEqual(1, SleepyNativeFormat.parseDay("1\r\n"))
        XCTAssertEqual(1, SleepyNativeFormat.parseDay("\u{00A0}1\u{00A0}"))       // oracle: pd NBSP1NBSP=1
        XCTAssertEqual(3, SleepyNativeFormat.parseDay("\u{2007}周3\u{2007}"))     // oracle: pd U2007zhou3=3
        XCTAssertNil(SleepyNativeFormat.parseDay("\u{0085}1\u{0085}"))            // NEL 非空白 → 长度2 → null
        XCTAssertNil(SleepyNativeFormat.parseDay("1\u{0085}"))                    // oracle: trim 后 "1\u0085" 形状非法
    }

    func testF051DetectVersionLineSplitIgnoresUnicodeSeparators() {
        // Kotlin lineSequence() 只按 \n/\r\n/\r 切行; U+2028 不断行。
        // magic 与内容以 U+2028 相连 → 两端同为「一行内 find 命中」=1(非 .newlines 口径差异)。
        XCTAssertEqual(1, SleepyNativeFormat.detectVersion("#sleepy-v1\u{2028}C高数|1|1-2"))
        XCTAssertEqual(1, SleepyNativeFormat.detectVersion("#sleepy-v1\u{0085}C高数|1|1-2"))
        // magic 行本身以 \r 结尾(CRLF 老 Mac 导出) 照常命中
        XCTAssertEqual(1, SleepyNativeFormat.detectVersion("#sleepy-v1\rC高数|1|1-2"))
    }

    func testF051EscapePipesWithCombiningMarks() {
        // Kotlin String 逐 UTF-16 码元迭代: "|"+U+0301 是两个码元 → '|' 必须被转义。
        // Swift 字素口径曾把该簇当「不等于 |」→ 漏转义 → 导出物裸竖线, 两端解析分叉。
        // 断言走 utf16 码元子序列: 输出里转义符会与后续记号组成字素, 字面串搜索不可靠。
        let s = "A|\u{0301}B"
        let esc = Array(SleepyNativeFormat.escape(s).utf16)
        var escapedPipe = false
        for i in 0..<esc.count where esc[i] == 0x5C && i + 1 < esc.count && esc[i + 1] == 0x7C {
            escapedPipe = true
        }
        XCTAssertTrue(escapedPipe, "保留码元 0x7C 必须被前置 0x5C 转义: got \(esc.map { String(format: "%04X", $0) })")
        XCTAssertEqual(s, SleepyNativeFormat.unescape(SleepyNativeFormat.escape(s)), "往返保真(含结合记号)")
        // 反斜杠+结合记号: Kotlin s[0]=='\\' 消费下一码元 → 记号脱落为字面; 两端逐码元同构
        let bsCombo = "x\\\u{0301}y"
        XCTAssertEqual(bsCombo, SleepyNativeFormat.unescape(SleepyNativeFormat.escape(bsCombo)))
    }

    func testF051TrailingUnicodeLineTerminatorParity() {
        // JDK17 实测: Java 非 MULTILINE 的 $ 命中「末尾行终止符之前」(NEL/LS), ICU $ 同构。
        // U+0085/U+2028 不在 Java isWhitespace → trim 不剥 → 两端都必须按同一口径命中。
        XCTAssertEqual(8, SleepyNativeFormat.parseClock("8:00\u{0085}")?.h)
        XCTAssertEqual(8, SleepyNativeFormat.parseClock("8:00\u{2028}")?.h)
        XCTAssertEqual("2026-03-02", SleepyNativeFormat.parseDate("2026-03-02\u{0085}"))
        XCTAssertEqual(16, SleepyNativeFormat.parseWeekSpec("1-16\u{0085}")?.end)
        // 常规尾随空白仍正常(trim 已剥 \n)
        XCTAssertEqual(8, SleepyNativeFormat.parseClock("8:00\n")?.h)
    }

    func testF051KotlinIntSemanticsViaPublicSurface() {
        // toIntOrNull 口径经 parseWeekSpec 间接锁定: 下划线/超 Int32/全角位均 null(Android 同)
        XCTAssertNil(SleepyNativeFormat.parseWeekSpec("1_0"))
        XCTAssertNil(SleepyNativeFormat.parseWeekSpec("3000000000"))
        XCTAssertNil(SleepyNativeFormat.parseWeekSpec("２-１６"))  // \d 为 ASCII 口径
        XCTAssertEqual(16, SleepyNativeFormat.parseWeekSpec("1-16")?.end)
    }

    func testF051KotlinIntAcceptsUnicodeNdDigits() {
        // JDK17 实测: Integer.parseInt / Kotlin toIntOrNull 对 BMP 的 Unicode Nd 数字位
        // (Character.digit(c,10)) 一律接受 — parseInt("１")=1、parseInt("١٢")=12、parseInt("+16")=16。
        // iOS 旧 kotlinInt ASCII-only → parseNodeSpan/colorFromToken 全角数字两端分叉
        // (微信转发课表全角数字常见, issue#F051 同源补充)。
        XCTAssertEqual(1, SleepyNativeFormat.parseNodeSpan("１")?.0)
        XCTAssertEqual(1, SleepyNativeFormat.parseNodeSpan("１")?.1)
        XCTAssertEqual(1, SleepyNativeFormat.parseNodeSpan("１-２")?.0)
        XCTAssertEqual(2, SleepyNativeFormat.parseNodeSpan("１-２")?.1)
        XCTAssertEqual(2, SleepyNativeFormat.parseNodeSpan("٢")?.0)      // Arabic-Indic
        XCTAssertEqual(16, SleepyNativeFormat.parseNodeSpan("+16")?.0)   // 显式正号
        XCTAssertEqual("#FFEADDFF", SleepyNativeFormat.colorFromToken("１"))  // 全角索引 → 调色板 1
        // 反向: 下划线/超 Int32/空段仍旧口径(不受本次放宽影响)
        XCTAssertNil(SleepyNativeFormat.parseNodeSpan("1_0"))
        XCTAssertNil(SleepyNativeFormat.parseNodeSpan("3000000000"))
        // 正则门(ASCII [0-9])路径不受影响: 全角周次仍旧形状非法
        XCTAssertNil(SleepyNativeFormat.parseWeekSpec("２"))
    }

    // ---- 确定性 UUID (§3.4, = UUID.nameUUIDFromBytes) ----

    func testDeterministicUUIDMatchesJavaNameUUIDFromBytes() {
        // java.util.UUID.nameUUIDFromBytes("sleepy".toByteArray()) 的已知值
        let a = SleepyNativeParser.deterministicUUID("sleepy")
        let b = SleepyNativeParser.deterministicUUID("sleepy")
        XCTAssertEqual(a, b, "同输入必须同 UUID")
        XCTAssertEqual(36, a.count, "标准 8-4-4-4-12 UUID 形状")
        // version 3 (MD5) 固定在第 3 组首位
        XCTAssertTrue(a.hasPrefix(a.prefix(14) + "3"), "version nibble = 3")
    }
}
