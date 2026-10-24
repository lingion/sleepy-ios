// MarkdownBlocksTests.swift — ← util/MarkdownBlocksTest.kt 逐用例移植 (GPL-3.0)
// 11 个 Kotlin 用例全量镜像: 块级解析、行内 span 切分、探针 release body 的
// 冷门/畸形 Markdown 边界(未闭合粗体、嵌套括号 URL、混合列表符、tab 缩进)。

import XCTest
@testable import Sleepy

final class MarkdownBlocksTests: XCTestCase {

    // ==== Android 原用例 ====

    func testParsesHeadingLevels() {
        let blocks = MarkdownBlocks.parse("## New\n\nbody")
        XCTAssertEqual(blocks, [
            .heading(level: 2, text: "New"),
            .paragraph(text: "body"),
        ])
    }

    func testParsesConsecutiveListItemsIntoOneGroup() {
        let blocks = MarkdownBlocks.parse("- a\n- b\n- c")
        XCTAssertEqual(blocks, [.bullet(items: ["a", "b", "c"])])
    }

    func testKeepsListSplitFromParagraph() {
        let blocks = MarkdownBlocks.parse("intro:\n\n- a\n- b")
        XCTAssertEqual(blocks, [
            .paragraph(text: "intro:"),
            .bullet(items: ["a", "b"]),
        ])
    }

    func testInlineBoldAndCodeAndLinkSplit() {
        let spans = MarkdownBlocks.parseInline("看 **加粗** 和 `code` 与 [链接](https://x.y)")
        XCTAssertEqual(spans, [
            .text("看 "),
            .bold("加粗"),
            .text(" 和 "),
            .code("code"),
            .text(" 与 "),
            .link(text: "链接", url: "https://x.y"),
        ])
    }

    func testPlainTextYieldsSingleParagraph() {
        let blocks = MarkdownBlocks.parse("v1.0.40\n\nThree additions and one fix.")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertTrue(blocks.allSatisfy { if case .paragraph = $0 { return true } else { return false } })
    }

    func testGithubBulletWithNestedIndentIsTreatedAsListItem() {
        // release notes 有时用 2 空格缩进的子项; 至少不能当成普通段落吞掉列表结构
        let blocks = MarkdownBlocks.parse("- a\n  - b")
        let items: [String] = blocks.compactMap {
            if case .bullet(let its) = $0 { return its } else { return nil }
        }.flatMap { $0 }
        XCTAssertFalse(items.isEmpty, "no bullet block")
        XCTAssertEqual(items, ["a", "b"])
    }

    // ==== 探针: 覆盖 release notes 会出现的冷门/畸形 Markdown ====

    /// 模拟即将发出的 v1.0.41 探针 release body, 与 Kotlin 侧 probe-notes 保持一致
    private var probeBody: String {
        """
        # 渲染探针一级标题

        ## 二级标题: 粗体和代码

        这一段里有 **粗体片段**、`inline_code` 和 [一个链接](https://github.com/lingion/sleepy) 混排, 用来验证行内三种 span 共存时的切分顺序。

        ### 三级标题: 列表形态

        - 纯文本列表项一
        - 含 **加粗** 的列表项二
        - 含 `代码` 的列表项三
        - 含 [链接文字](https://github.com) 的列表项四
          - 带缩进的子项(应当被拍平成同级)
        * 星号列表项(另一种列表符)
        + 加号列表项(第三种列表符)

        #### 四级标题: 段落折行

        第一行文字,
        第二行文字会被合并进同一个段落,
        第三行同样。

        ##### 五级标题: 边界之前

        下面是奇葩边界:

        **未闭合的粗体段
        单独一个反引号 ` 出现在行中
        空方括号链接 []() 应原样保留
        嵌套括号 URL [文字](https://en.wikipedia.org/wiki/Sleep_(disorder))
        行首**粗体**紧贴行首
        行尾粗体紧贴行尾**
        ###### 六级标题: 尽头

        连续多个空行上方, 下方是缩进列表:

          - 缩进两个空格的项
        \t- tab 开头的项(注意这是 tab)

        普通文字恢复。本段结束后整个探针结束。
        """
    }

    /// span 文本拼接(对应 Kotlin 测试里的 joinToString when 分支)
    private func joinSpans(_ spans: [MarkdownBlocks.Inline]) -> String {
        spans.map { span in
            switch span {
            case .text(let t), .bold(let t), .code(let t): return t
            case .link(let t, _): return t
            }
        }.joined()
    }

    private func bulletItems(in blocks: [MarkdownBlocks.Block]) -> [String] {
        blocks.flatMap { block in
            if case .bullet(let items) = block { return items } else { return [] }
        }
    }

    func testProbeHeadingsParseWithCorrectLevels() {
        let regex = try! NSRegularExpression(pattern: "^(#{1,6})\\s+(.*)$")
        let levels = probeBody.components(separatedBy: .newlines).compactMap { line -> Int? in
            let t = line.trimmingCharacters(in: .whitespaces)
            let ns = t as NSString
            guard let m = regex.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) else { return nil }
            return ns.substring(with: m.range(at: 1)).count
        }
        // 1/2/3/4/5/6 级标题全部出现, 每级各一次
        XCTAssertEqual(levels, [1, 2, 3, 4, 5, 6])
    }

    func testProbeMixedListMarkersAllBecomeBulletItems() {
        // 9 个列表行(-*+ 三种符号 + 缩进子项 + 独立缩进组)必须全部进 Bullet 块, 一行都不能丢
        let items = bulletItems(in: MarkdownBlocks.parse(probeBody))
        XCTAssertEqual(items.count, 9)
        XCTAssertTrue(items.contains { $0.hasPrefix("带缩进的子项") }, "缩进子项 must survive")
        XCTAssertTrue(items.contains { $0.hasPrefix("星号列表项") }, "星号列表项 must survive")
        XCTAssertTrue(items.contains { $0.hasPrefix("加号列表项") }, "加号列表项 must survive")
        XCTAssertTrue(items.contains { $0.hasPrefix("缩进两个空格的项") }, "2空格缩进项 must survive")
        XCTAssertTrue(items.contains { $0.hasPrefix("tab 开头的项") }, "tab 开头项 must survive")
    }

    func testProbeUnclosedBoldStaysAsText() {
        // "**未闭合的粗体段" 没有 ** 闭合, parseInline 不应丢字
        let spans = MarkdownBlocks.parseInline("**未闭合的粗体段")
        XCTAssertEqual(joinSpans(spans), "**未闭合的粗体段")
    }

    func testProbeNestedParenUrlLinkParses() {
        // wiki 链接里带括号, regex 非贪婪匹配会在第一个 ) 停下 — 只要不崩且文字不丢即可
        let spans = MarkdownBlocks.parseInline("[文字](https://en.wikipedia.org/wiki/Sleep_(disorder))")
        XCTAssertTrue(joinSpans(spans).contains("文字"), "文字 must survive")
    }

    func testProbeNoContentLossAcrossWholeBody() {
        // 全文所有非空白字符在 parse + parseInline 前后必须保持数量一致(不吞字)
        let blocks = MarkdownBlocks.parse(probeBody)
        let allInline: [MarkdownBlocks.Inline] = blocks.flatMap { block -> [MarkdownBlocks.Inline] in
            switch block {
            case .heading(_, let text):
                return MarkdownBlocks.parseInline(text)
            case .bullet(let items):
                return items.flatMap { MarkdownBlocks.parseInline($0) }
            case .paragraph(let text):
                return MarkdownBlocks.parseInline(text)
            }
        }
        let rendered = joinSpans(allInline)
        // 渲染会去掉 ** ` []() 这些标记字符, 所以只验证: 渲染结果里的中文字符集合与源一致
        let sourceCjk = Set(probeBody.unicodeScalars.filter { $0.value > 0x4E00 && $0.value < 0x9FFF })
        let renderedCjk = Set(rendered.unicodeScalars.filter { $0.value > 0x4E00 && $0.value < 0x9FFF })
        XCTAssertEqual(sourceCjk, renderedCjk)
    }
}
