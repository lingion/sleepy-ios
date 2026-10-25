// DialogButtonsLayoutPolicyTests.swift — ← util/DialogButtonsLayoutPolicyTest.kt 8 用例逐字对齐 (GPL-3.0)
// Sleepy iOS — 100% port of sleepy Android

import XCTest
@testable import Sleepy

/// 用户反馈 2026-09-16 (第二轮): 弹窗三键排一行后文字被截断
/// ("退出并保留草稿" 7 个 CJK 字, 三等分每键 ~88dp 放不下 → 显示不全)。
///
/// 用户优先级明确: ①文字精炼 ②文字完整展示 ③然后才是一排美观。
/// "不是一定要一排, 最好是一排" — 一排放不下就换竖排, 文字必须完整。
///
/// 本文件锁布局降级策略(纯函数): 行宽够 → 一行; 不够 → 竖排。
final class DialogButtonsLayoutPolicyTests: XCTestCase {

    /// labelLarge 14sp 下一个 CJK 字 ≈ 14dp + 按钮左右内边距 32dp (M3 Button contentPadding)。
    private static let fontDpPerCjkChar: CGFloat = 14
    private static let fontDpPerChar: CGFloat = 14
    private static let buttonHPaddingDp: CGFloat = 32
    private static let rowGapDp: CGFloat = 8

    private func btnTextWidth(_ label: String) -> CGFloat {
        CGFloat(label.count) * Self.fontDpPerCjkChar + Self.buttonHPaddingDp
    }

    /// 退化场景(用户报障原样): 三键 4/7/7 字, 弹窗内容区 280dp。
    func testThreeLongLabels280dpRowFallsBackToVertical() {
        let fits = DialogButtonsLayoutPolicy.fitsInRow(
            labels: ["继续导入", "退出并保留草稿", "退出并删除草稿"],
            availableWidthDp: 280,
            fontDpPerChar: Self.fontDpPerCjkChar,
            buttonHPaddingDp: Self.buttonHPaddingDp,
            rowGapDp: Self.rowGapDp
        )
        XCTAssertFalse(fits, "88dp×3 + 2×8dp gap = 280dp 恰好挤爆, 7 字键必须竖排")
    }

    /// 两键短标签("删除/取消"类)在同样宽度下一行放得下 → 保持一行。
    func testTwoShortLabels280dpRowStaysHorizontal() {
        let fits = DialogActionsLayoutPolicyBridge.fit(
            labels: ["取消", "删除"],
            availableWidthDp: 280
        )
        XCTAssertTrue(fits, "两键短标签必须保住一行布局")
    }

    /// 精炼后的三键(4/4/4 字)重新放进一行 — 文案瘦身直接救回一行布局。
    func testThreeConciseLabelsAfterCopyDietFitRow() {
        let fits = DialogActionsLayoutPolicyBridge.fit(
            labels: ["继续导入", "保留草稿", "删除草稿"],
            availableWidthDp: 280
        )
        XCTAssertTrue(fits, "精炼后 3×(4×14+32)+16 = 232dp ≤ 280dp → 一行")
    }

    /// 竖排策略下按钮全宽: 任意长度标签都可完整展示 — 策略输出竖排时调用方不再截断。
    func testVerticalFallbackAlwaysShowsFullTextNoTruncation() {
        let veryLong = ["继续导入当前教务系统", "退出并保留当前草稿", "退出并删除所有草稿数据"]
        let fitsInRow = DialogActionsLayoutPolicyBridge.fit(
            labels: veryLong, availableWidthDp: 280)
        XCTAssertFalse(fitsInRow, "超长标签必须触发竖排")
        // 竖排 = 每键独占一行(全宽), 只要窗口 ≥ 最长标签宽即可完整显示
        let widest = veryLong.map {
            DialogButtonsLayoutPolicy.buttonTextWidth($0, Self.fontDpPerCjkChar, Self.buttonHPaddingDp)
        }.max() ?? 0
        XCTAssertTrue(280 >= widest, "竖排全宽按钮 280dp ≥ 最长标签 142dp → 无截断")
    }

    /// 单键弹窗永不受影响 — 恒一行。
    func testSingleButtonAlwaysFits() {
        let fits = DialogActionsLayoutPolicyBridge.fit(
            labels: ["确定"], availableWidthDp: 100)
        XCTAssertTrue(fits)
    }

    /// 等宽假设: 文字宽度按字符数线性估算 — 精确策略对 CJK 是准确的(等宽), 对拉丁是保守近似。
    func testButtonTextWidthLinearInCjkChars() {
        let w4 = DialogButtonsLayoutPolicy.buttonTextWidth("保留草稿", Self.fontDpPerCjkChar, Self.buttonHPaddingDp)
        let w7 = DialogButtonsLayoutPolicy.buttonTextWidth("退出并保留草稿", Self.fontDpPerCjkChar, Self.buttonHPaddingDp)
        XCTAssertEqual(4 * Self.fontDpPerCjkChar + Self.buttonHPaddingDp, w4, accuracy: 0.01)
        XCTAssertEqual(7 * Self.fontDpPerCjkChar + Self.buttonHPaddingDp, w7, accuracy: 0.01)
    }

    /// 横排不能再等分: 长标签必须得到更多宽度, 否则 Text 会自动换行。
    func testHorizontalWeightsAreProportionalToRequiredButtonWidths() {
        let widths = DialogButtonsLayoutPolicy.requiredButtonWidths(
            labels: ["知道了", "导出排查全量包"],
            fontDpPerChar: Self.fontDpPerCjkChar,
            buttonHPaddingDp: Self.buttonHPaddingDp
        )
        XCTAssertTrue(widths[1] > widths[0], "长按钮必须比短按钮获得更大 weight")
        XCTAssertEqual(3 * Self.fontDpPerCjkChar + Self.buttonHPaddingDp, widths[0], accuracy: 0.01)
        XCTAssertEqual(7 * Self.fontDpPerChar + Self.buttonHPaddingDp, widths[1], accuracy: 0.01)
    }

    /// 权重必须按需求宽度归一化, 供 HStack Spacer/weight 使用。
    func testHorizontalWeightsSumToOneAndPreserveRatio() {
        let weights = DialogButtonsLayoutPolicy.normalizedWeights(
            labels: ["知道了", "导出排查全量包"],
            fontDpPerChar: Self.fontDpPerChar,
            buttonHPaddingDp: Self.buttonHPaddingDp
        )
        XCTAssertEqual(1, weights.reduce(0, +), accuracy: 0.001)
        XCTAssertEqual(
            (3 * Self.fontDpPerChar + Self.buttonHPaddingDp) /
            (7 * Self.fontDpPerChar + Self.buttonHPaddingDp),
            weights[0] / weights[1], accuracy: 0.001)
    }
}
