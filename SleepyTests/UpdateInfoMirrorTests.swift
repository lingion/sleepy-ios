// UpdateInfoMirrorTests.swift — ← UpdateInfoParseTest.kt 中 iOS 侧此前未覆盖的用例组
// (镜像改写 / 直连回退 / 镜像页 changelog 提取), 逐用例对齐。
// ABI 挑 asset 的双命名用例(picks_correct_abi_asset 等)为 Android APK 专有,
// iOS 单 IPA 语义已在 VersionAndUpdateTests.swift 等价覆盖,此处不重复。

import XCTest
@testable import Sleepy

// MARK: - ← 下载地址镜像改写(2026-09-05 用户令: api.github.com 可达 ≠ github.com 资产可达)

final class UpdateInfoMirrorRewriteTests: XCTestCase {

    // iOS 分发仓库 = lingion/sleepy-ios(与 UpdateInfo.swift 内前缀常量同源)
    func testGithubAssetUrlIsRewrittenToMirror() {  // ← github_asset_url_is_rewritten_to_mirror
        let body = """
        {"tag_name":"v1.0.47","body":"x","assets":[
            {"name":"Sleepy.ipa","browser_download_url":"https://github.com/lingion/sleepy-ios/releases/download/v1.0.47/Sleepy.ipa"}]}
        """
        let info = parseReleaseJson(body, currentVersion: "1.0.46", abi: "ios")
        XCTAssertEqual(
            "https://gh.qdp.qzz.io/lingion/sleepy-ios/releases/download/v1.0.47/Sleepy.ipa",
            info.downloadUrl
        )
    }

    func testNonGithubAssetUrlPassesThroughUntouched() {  // ← non_github_asset_url_passes_through_untouched
        let foreign = """
        {"tag_name":"v1.0.47","body":"x","assets":[
            {"name":"Sleepy.ipa","browser_download_url":"https://example.com/a.ipa"}]}
        """
        let info = parseReleaseJson(foreign, currentVersion: "1.0.46", abi: "ios")
        XCTAssertEqual("https://example.com/a.ipa", info.downloadUrl)
    }

    func testGithubDirectUrlIsDerivedFromMirrorUrlForFallback() {  // ← github_direct_url_is_derived_from_mirror_url_for_fallback
        // 下载失败时的回退对: 镜像地址 → 原始 GitHub 直连地址
        let mirror = "https://gh.qdp.qzz.io/lingion/sleepy-ios/releases/download/v1.0.47/Sleepy.ipa"
        let direct = "https://github.com/lingion/sleepy-ios/releases/download/v1.0.47/Sleepy.ipa"
        XCTAssertEqual(direct, toDirectGithubUrl(mirror))
        // 已是直连则原样返回(幂等)
        XCTAssertEqual(direct, toDirectGithubUrl(direct))
        // 非下载路径不改写
        XCTAssertEqual("https://gh.qdp.qzz.io/other/page", toDirectGithubUrl("https://gh.qdp.qzz.io/other/page"))
    }
}

// MARK: - ← 镜像页 changelog 提取

final class UpdateInfoMirrorPageTests: XCTestCase {

    private let mirrorPage = """
    <html><head><title>Release v1.0.39</title></head><body>
    <div data-pjax="true" data-test-selector="body-content" data-view-component="true" class="markdown-body tmp-my-3"><h2>v1.0.39</h2>
    <p>Two changes: bug reported in <a class="issue-link" href="https://github.com/lingion/sleepy/issues/5">#5</a> is fixed.</p>
    <h3>New</h3>
    <p><strong>Each time slot keeps its own week range</strong></p>
    <ul>
    <li>Every time slot carries its own start week.</li>
    <li>Slots that share a day stay separate.</li>
    </ul>
    <h3>Fixes</h3>
    <ul>
    <li><strong>Weekday header wrong date</strong> is fixed.</li>
    </ul>
    </div>
    </body></html>
    """

    func testMirrorPageExtractsMarkdownBodyBlock() {  // ← mirrorPage_extracts_markdown_body_block
        let md = parseMirrorPage(mirrorPage, tag: "v1.0.39")
        XCTAssertTrue(md.contains("Each time slot keeps its own week range"))
        XCTAssertTrue(md.contains("start week"))
    }

    func testMirrorPageConvertsHeadingsListsBoldLinks() {  // ← mirrorPage_converts_headings_lists_bold_links
        let md = parseMirrorPage(mirrorPage, tag: "v1.0.39")
        XCTAssertTrue(md.contains("## v1.0.39"))
        XCTAssertTrue(md.contains("### New"))
        XCTAssertTrue(md.contains("### Fixes"))
        XCTAssertTrue(md.contains("- Every time slot carries its own start week."))
        XCTAssertTrue(md.contains("**Each time slot keeps its own week range**"))
        XCTAssertTrue(md.contains("[#5](https://github.com/lingion/sleepy/issues/5)"))
    }

    func testMirrorPageStripsUnsafeTagsAndKeepsText() {  // ← mirrorPage_strips_unsafe_tags_and_keeps_text
        let md = parseMirrorPage(mirrorPage, tag: "v1.0.39")
        XCTAssertFalse(md.contains("<div"))
        XCTAssertFalse(md.contains("class="))
        XCTAssertFalse(md.contains("data-pjax"))
    }

    func testMirrorPageNoMarkdownBodyReturnsEmpty() {  // ← mirrorPage_no_markdown_body_returns_empty
        XCTAssertEqual("", parseMirrorPage("<html><body>404</body></html>", tag: "v1.0.39"))
    }

    func testMirrorPageMultipleMarkdownBodiesUsesFirst() {  // ← mirrorPage_multiple_markdown_bodies_uses_first
        let two = mirrorPage.replacingOccurrences(
            of: "</body>",
            with: "<div class=\"markdown-body\"><h2>comment</h2></div></body>"
        )
        let md = parseMirrorPage(two, tag: "v1.0.39")
        XCTAssertTrue(md.contains("Each time slot keeps its own week range"))
        XCTAssertFalse(md.contains("comment"))
    }

    func testMirrorPageHandlesMultilineDivWithoutRegexGreed() {  // ← mirrorPage_handles_multiline_div_without_regex_greed
        // .*? 非贪婪在多 markdown-body 时必须停在第一个闭合 div,而不是吞掉后半页
        let md = parseMirrorPage(mirrorPage, tag: "v1.0.39")
        XCTAssertFalse(md.contains("</body>"))
        XCTAssertFalse(md.contains("</html>"))
    }
}
