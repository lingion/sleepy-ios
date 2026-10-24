import Foundation

/**
 * 更新日志 Markdown 解析 — 纯 Swift, 无 UIKit/SwiftUI 依赖, 可 XCTest 单测。
 *
 * Android MarkdownBlocks.kt 1:1 移植: 取代第三方 MarkdownText 黑盒,
 * 上一版用 compose-markdown(Markwon)渲染真机标题/列表/粗体与普通正文无视觉差异
 * 且行为不可控。解析出确定性的块结构 Block + 行内结构 Inline, 由 UpdateChangelogDialog
 * 显式排版 — 每种块的实际视觉结果由本仓库代码决定, 不依赖第三方隐式行为。
 * 同理 iOS 侧禁用 AttributedString(markdown:) 渲染行内语法: Apple 的 CommonMark
 * 是黑盒(嵌套括号 URL 平衡进链接、try? 失败静默降级), 与本文件确定性 span 切分不一致。
 *
 * 覆盖 release notes 实际用到的语法: # 标题、- 列表、**粗体**、`代码`、
 * [文字](链接)、普通段落。其余 Markdown 语法按普通文本原样显示(安全兜底)。
 *
 * 本文件是 MarkdownBlocks 的唯一实现(原 UpdateManager.swift:138-187 的块级
 * 临时副本由集成者删除; 旧 MarkdownBlocksLegacy/MarkdownInline 死代码已移除)。
 */
enum MarkdownBlocks {

    /// 块级元素
    enum Block: Equatable {
        /// ATX 标题, level 1-6
        case heading(level: Int, text: String)
        /// 连续列表项合为一组
        case bullet(items: [String])
        /// 普通段落(可能多行, 已合并为单串)
        case paragraph(text: String)
    }

    /// 行内元素
    enum Inline: Equatable {
        case text(String)
        case bold(String)
        case code(String)
        case link(text: String, url: String)
    }

    static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var listItems: [String] = []
        var paragraphLines: [String] = []

        func flushList() {
            if !listItems.isEmpty {
                blocks.append(.bullet(items: listItems))
                listItems = []
            }
        }
        func flushParagraph() {
            if !paragraphLines.isEmpty {
                // ← Android L47: paragraphLines.joinToString(" ").trim()
                blocks.append(.paragraph(text: paragraphLines.joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)))
                paragraphLines = []
            }
        }
        func flushAll() { flushList(); flushParagraph() }

        for rawLine in markdown.components(separatedBy: .newlines) {
            // Android rawLine.trimEnd() 后再 line.trim(): 对按换行拆出的单行等价于一次全 trim
            let t = rawLine.trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                // 空行 = 块边界
                flushAll()
            } else if let g = captureGroups(headingRegex, t) {
                // ATX 标题: #..###### + 空格 + 内容
                flushAll()
                blocks.append(.heading(level: g[0].count,
                                       text: g[1].trimmingCharacters(in: .whitespaces)))
            } else if let item = captureGroups(bulletRegex, t)?.first {
                // 列表项: - / * / + + 空格; 容忍嵌套缩进(拍平)
                flushParagraph()
                listItems.append(item.trimmingCharacters(in: .whitespaces))
            } else {
                flushList()
                paragraphLines.append(t)
            }
        }
        flushAll()
        return blocks
    }

    /// 行内解析: **粗体**、`代码`、[文字](链接) → 有序 span 列表
    /// ← Android MarkdownBlocks.kt:81-114 — 一趟扫描, 三种模式按出现位置取最早,
    ///   同为最早起点时按 bold/code/link 声明顺序优先。
    static func parseInline(_ text: String) -> [Inline] {
        let ns = text as NSString
        var spans: [Inline] = []
        let patterns = [boldRegex, codeRegex, linkRegex]
        var i = 0
        while i < ns.length {
            var bestMatch: NSTextCheckingResult?
            var bestKind = -1
            for (kind, p) in patterns.enumerated() {
                guard let m = p.firstMatch(in: text,
                                           range: NSRange(location: i, length: ns.length - i)) else { continue }
                if bestMatch == nil || m.range.location < bestMatch!.range.location {
                    bestMatch = m
                    bestKind = kind
                }
            }
            guard let bm = bestMatch else {
                spans.append(.text(ns.substring(with: NSRange(location: i, length: ns.length - i))))
                break
            }
            if bm.range.location > i {
                spans.append(.text(ns.substring(with: NSRange(location: i, length: bm.range.location - i))))
            }
            switch bestKind {
            case 0:
                spans.append(.bold(ns.substring(with: bm.range(at: 1))))
            case 1:
                spans.append(.code(ns.substring(with: bm.range(at: 1))))
            default:
                spans.append(.link(text: ns.substring(with: bm.range(at: 1)),
                                   url: ns.substring(with: bm.range(at: 2))))
            }
            i = NSMaxRange(bm.range)
        }
        return spans.filter {
            if case .text(let t) = $0 { return !t.isEmpty }
            return true
        }
    }

    // MARK: - 内部正则(与 Kotlin 逐字对齐)

    private static let headingRegex = try! NSRegularExpression(pattern: "^(#{1,6})\\s+(.*)$")
    private static let bulletRegex = try! NSRegularExpression(pattern: "^[-*+]\\s+(.*)$")
    private static let boldRegex = try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*")
    private static let codeRegex = try! NSRegularExpression(pattern: "`([^`]+)`")
    private static let linkRegex = try! NSRegularExpression(pattern: "\\[([^\\]]+)]\\(([^)]+)\\)")

    /// 正则捕获组(不含整串匹配), 无匹配返回 nil
    private static func captureGroups(_ regex: NSRegularExpression, _ line: String) -> [String]? {
        let ns = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2 else { return nil }
        return (1..<m.numberOfRanges).map { ns.substring(with: m.range(at: $0)) }
    }
}
