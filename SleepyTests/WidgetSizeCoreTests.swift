// WidgetSizeCoreTests.swift — ← Android app/src/test/java/com/lingion/sleepy/widget/WidgetSizeSelectionTest.kt
// 纯逻辑测试: WidgetSizeCore — OPTION_APPWIDGET_SIZES 的定向选择与回退语义。
//
// 背景 (resize 稳定性根因之一): API31+ SIZES 列表在横竖双向 widget 上含两份
// portrait/landscape 尺寸。旧代码 maxByOrNull{面积} 在"横宽大 vs 竖高更大"时
// 挑的不是当前方向 — shell bitmap 按错误方向画, fitXY 强拉 → 顶栏下内容变形。
//
// 策略 (不依赖方向监听, 保持 launcher 兼容): SIZES 多份时按方向契约定向选择;
// 回退路径不再混拼 MIN_W×MAX_H 两个语义不同的边界, 而是优先 MIN 同源边界,
// 并把所有候选钳制到正数。
//
// ★ 平台差异: iOS WidgetKit 无 launcher 多候选协议, 本核心当前不被 UI 消费
//   (见 WidgetSizeCore.swift 头注), 逐用例保留验证两端逻辑一致。

import XCTest
@testable import Sleepy

final class WidgetSizeCoreTests: XCTestCase {

    private func sizeDp(_ w: CGFloat, _ h: CGFloat) -> WidgetSizeDp {
        WidgetSizeDp(w: w, h: h)
    }

    // ---- 单份 SIZES: 原样采用 ----

    func testSingleSizeEntryIsUsedAsIs() {
        XCTAssertEqual(
            WidgetSizeCore.pickSizeDp([sizeDp(80, 60)]),
            WidgetSizeDp(w: 80, h: 60)
        )
    }

    // ---- 多份 SIZES: 定向选择 (portrait/landscape 两份) ----

    func testNoHintDefaultsToPortraitEntryForGenuineOrientationPairs() {
        // 竖 120x300 vs 横 320x140 = 真方向对 (宽度不接近): 旧"宽度优先"契约返回横份,
        // 但竖放 (常态) 的实际 cell 是竖份 — shell 按横份画 → launcher fitXY 强拉变形。
        // 无摆放 hint 时默认竖放, 取竖态 (h>=w) 份。
        let picked = WidgetSizeCore.pickSizeDp([sizeDp(120, 300), sizeDp(320, 140)])
        XCTAssertEqual(picked, WidgetSizeDp(w: 120, h: 300))
    }

    func testTiesOnWidthPreferSmallerHeightWithScrollFallback() {
        // 同宽 200x100 vs 200x200 = 同方向镜像尺寸 → 高度小者;
        // 内容真有 200dp 高时滚动分支兜底, 比把短内容画成长图再压扁安全。
        XCTAssertEqual(
            WidgetSizeCore.pickSizeDp([sizeDp(200, 100), sizeDp(200, 200)]),
            WidgetSizeDp(w: 200, h: 100)
        )
    }

    func testNonPositiveEntriesAreIgnored() {
        // launcher 偶发塞 0/负值 (半墙 OEM bug 见 memory) — 只挑正数项
        XCTAssertEqual(
            WidgetSizeCore.pickSizeDp([sizeDp(0, 0), sizeDp(80, 60), sizeDp(-5, 10)]),
            WidgetSizeDp(w: 80, h: 60)
        )
    }

    func testEmptyOrAllInvalidSizesYieldNil() {
        XCTAssertNil(WidgetSizeCore.pickSizeDp([]))
        XCTAssertNil(WidgetSizeCore.pickSizeDp([sizeDp(0, 0)]))
    }

    // ---- 摆放 hint (OPTION_APPWIDGET_MIN_WIDTH/HEIGHT 口径) 定向 ----

    func testHintPortraitPicksPortraitEntryFromGenuineOrientationPair() {
        // MIN_W×MIN_H = 竖放 cell (80x250): 竖 120x300 才是当前方向, 横 320x140 丢弃
        XCTAssertEqual(
            WidgetSizeCore.pickSizeDp([sizeDp(120, 300), sizeDp(320, 140)],
                                      hint: sizeDp(80, 250)),
            WidgetSizeDp(w: 120, h: 300)
        )
    }

    func testHintLandscapePicksLandscapeEntry() {
        // MIN_W×MIN_H = 横放 cell (300x100): 横份才对
        XCTAssertEqual(
            WidgetSizeCore.pickSizeDp([sizeDp(120, 300), sizeDp(320, 140)],
                                      hint: sizeDp(300, 100)),
            WidgetSizeDp(w: 320, h: 140)
        )
    }

    func testMirrorPairIgnoresHintAndKeepsSmallerHeightTieBreak() {
        // 宽度接近 (±2dp) = 同方向 OEM 镜像: 与旧契约一致取高度小者, hint 不扰动
        XCTAssertEqual(
            WidgetSizeCore.pickSizeDp([sizeDp(200, 100), sizeDp(200, 200)],
                                      hint: sizeDp(200, 100)),
            WidgetSizeDp(w: 200, h: 100)
        )
        // ±2dp 容差边界: 201 vs 199 差 2dp 仍算镜像 → 高度小者 (100)
        XCTAssertEqual(
            WidgetSizeCore.pickSizeDp([sizeDp(201, 100), sizeDp(199, 200)],
                                      hint: sizeDp(199, 200)),
            WidgetSizeDp(w: 201, h: 100)
        )
    }

    // ---- >2 份 SIZES (折叠态/多 cell launcher 会塞 3+ 份) ----

    func testMoreThanTwoEntriesPicksBestForHintNotBlindTop2() {
        // 4 份: 竖两档 + 横两档。hint=竖放 cell → 落与 cell 最贴合的竖档 (100x220 距
        // (80,250) 最近), 旧 top-2-of-width-sort 直接取横 320x140 (sort 后前二都是横份)。
        let sizes = [sizeDp(120, 300), sizeDp(100, 220), sizeDp(320, 140), sizeDp(240, 110)]
        XCTAssertEqual(
            WidgetSizeCore.pickSizeDp(sizes, hint: sizeDp(80, 250)),
            WidgetSizeDp(w: 100, h: 220)
        )
        XCTAssertEqual(
            WidgetSizeCore.pickSizeDp(sizes, hint: sizeDp(300, 100)),
            WidgetSizeDp(w: 320, h: 140)
        )
    }

    func testMoreThanTwoEntriesWithoutHintDefaultsToPortraitEntry() {
        // 无 hint 默认竖放: 取 h>=w 份里与"典型竖放"最贴合者 — 契约: 禁盲取宽度冠军
        let sizes = [sizeDp(120, 300), sizeDp(100, 220), sizeDp(320, 140)]
        let picked = WidgetSizeCore.pickSizeDp(sizes)
        XCTAssertNotNil(picked)
        XCTAssertTrue(
            picked!.h >= picked!.w,
            "无 hint 时须取竖态 (h>=w) 份, 实取 \(String(describing: picked))"
        )
    }

    // ---- 回退: API<31 或 launcher 未给 SIZES ----

    func testFallbackUsesMinWidthWithMinHeightNotMaxHeight() {
        // 契约: MIN_W × MIN_H — MIN_H 是"当前高度下界", MAX_H 是"能拖到的最大高度"
        // (API29/30 javadoc), 用 MAX_H 会把 1 行 widget 画成 5 行长图再 fitXY 压扁。
        let fb = WidgetSizeCore.fallbackSizeDp(minW: 80, minH: 60, maxW: 320, maxH: 580)
        XCTAssertEqual(fb.w, 80)
        XCTAssertEqual(fb.h, 60)
    }

    func testFallbackClampsNonPositiveInputsToSafeDefaults() {
        let fb = WidgetSizeCore.fallbackSizeDp(minW: 0, minH: 0, maxW: 0, maxH: 0)
        XCTAssertEqual(fb.w, 250)
        XCTAssertEqual(fb.h, 100)
    }

    func testFallbackUsesMaxBoundsOnlyWhenMinBoundsAreAbsent() {
        // MIN 缺失但 MAX 在 (部分 OEM 只写一半): 用 MAX 而不是默认值硬猜
        let fb = WidgetSizeCore.fallbackSizeDp(minW: 0, minH: 0, maxW: 320, maxH: 580)
        XCTAssertEqual(fb.w, 320)
        XCTAssertEqual(fb.h, 580)
    }
}
