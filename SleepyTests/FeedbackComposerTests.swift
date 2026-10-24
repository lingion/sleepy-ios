// FeedbackComposerTests.swift — ← util/FeedbackComposerTest.kt 逐用例移植
// Android 7 个用例全量镜像: GitHub Issue URL 前缀与参数、template 先于 title、
// mailto 地址与字段编码、诊断块字段与构建类型、Release 标记、Markdown 注入转义、
// URL 末尾无裸 '&'。编码断言按 URLEncoder 语义(空格 '+', ':' %3A)对齐。

import XCTest
@testable import Sleepy

final class FeedbackComposerTests: XCTestCase {

    private let diagnostic = FeedbackComposer.Diagnostic(
        versionName: "1.0.42",
        versionCode: 42,
        osVersion: "16.4",
        deviceBrand: "Google",
        deviceModel: "Pixel 7",
        resolution: "1080x2400",
        locale: "zh-CN",
        isDebug: true
    )

    // ==== Android 原用例 1: githubUrl_encodesTitleBodyAndAppendsDiagnostics ====
    func testGithubUrlEncodesTitleBodyAndAppendsDiagnostics() {
        let result = FeedbackComposer.githubIssueUrl(
            title: "Bug: 中文 & 符号",
            body: "描述\n含 & 符号",
            diag: diagnostic)
        XCTAssertTrue(result.hasPrefix("https://github.com/lingion/sleepy/issues/new?"))
        XCTAssertTrue(result.contains("title="))
        XCTAssertTrue(result.contains("body="))
        XCTAssertFalse(result.contains(" "))
        XCTAssertTrue(result.contains("VersionCode%3A"))
        XCTAssertTrue(result.contains("iOS%3A"))
    }

    // ==== Android 原用例 2: githubUrl_includesTemplateBeforeTitle ====
    func testGithubUrlIncludesTemplateBeforeTitle() {
        let result = FeedbackComposer.githubIssueUrl(
            title: "Test",
            body: "Desc",
            diag: diagnostic,
            template: "bug_report")
        let templateIndex = result.range(of: "template=")!.lowerBound
        let titleIndex = result.range(of: "title=")!.lowerBound
        XCTAssertLessThan(templateIndex, titleIndex)
    }

    // ==== Android 原用例 3: mailtoUri_usesConfirmedAddressAndEncodesFields ====
    func testMailtoUriUsesConfirmedAddressAndEncodesFields() {
        let result = FeedbackComposer.mailtoUri(
            subject: "中文标题",
            body: "内容\n和&符号",
            diag: diagnostic)
        XCTAssertTrue(result.hasPrefix("mailto:lingion@hrbeu.edu.cn?subject="))
        XCTAssertTrue(result.contains("body="))
        XCTAssertFalse(result.contains(" "))
        XCTAssertTrue(result.contains("VersionCode%3A"))
    }

    // ==== Android 原用例 4: diagnosticBlock_containsAllFieldsAndBuildType ====
    func testDiagnosticBlockContainsAllFieldsAndBuildType() {
        let block = FeedbackComposer.formatDiagnostic(diagnostic)
        XCTAssertTrue(block.contains("**Version:** 1.0.42"))
        XCTAssertTrue(block.contains("**VersionCode:** 42"))
        XCTAssertTrue(block.contains("**iOS:** 16.4"))
        XCTAssertTrue(block.contains("**Device:** Google Pixel 7"))
        XCTAssertTrue(block.contains("**Resolution:** 1080x2400"))
        XCTAssertTrue(block.contains("**Locale:** zh-CN"))
        XCTAssertTrue(block.contains("**Build:** Debug"))
    }

    // ==== Android 原用例 5: diagnosticBlock_releaseBuild_isMarkedRelease ====
    func testDiagnosticBlockReleaseBuildIsMarkedRelease() {
        let release = FeedbackComposer.Diagnostic(
            versionName: diagnostic.versionName,
            versionCode: diagnostic.versionCode,
            osVersion: diagnostic.osVersion,
            deviceBrand: diagnostic.deviceBrand,
            deviceModel: diagnostic.deviceModel,
            resolution: diagnostic.resolution,
            locale: diagnostic.locale,
            isDebug: false)
        let block = FeedbackComposer.formatDiagnostic(release)
        XCTAssertTrue(block.contains("**Build:** Release"))
        XCTAssertFalse(block.contains("**Build:** Debug"))
    }

    // ==== Android 原用例 6: diagnosticBlock_escapesMarkdownCharacters ====
    func testDiagnosticBlockEscapesMarkdownCharacters() {
        let injected = FeedbackComposer.Diagnostic(
            versionName: "**injected**",
            versionCode: diagnostic.versionCode,
            osVersion: diagnostic.osVersion,
            deviceBrand: diagnostic.deviceBrand,
            deviceModel: diagnostic.deviceModel,
            resolution: diagnostic.resolution,
            locale: diagnostic.locale,
            isDebug: diagnostic.isDebug)
        let block = FeedbackComposer.formatDiagnostic(injected)
        XCTAssertTrue(block.contains("\\*\\*injected\\*\\*"))
    }

    // ==== Android 原用例 7: urls_haveNoTrailingAmpersand ====
    func testUrlsHaveNoTrailingAmpersand() {
        XCTAssertFalse(FeedbackComposer.githubIssueUrl(
            title: "Test", body: "Desc", diag: diagnostic).hasSuffix("&"))
        XCTAssertFalse(FeedbackComposer.mailtoUri(
            subject: "Test", body: "Desc", diag: diagnostic).hasSuffix("&"))
    }

    // ==== 补充: enc() 与 Android URLEncoder 字节级对齐回归 ====
    func testEncMatchesURLEncoderByteSemantics() {
        // 空格 → '+'; 非 ASCII → UTF-8 大写十六进制百分号编码; '*' '.' '-' '_' 字面保留; '~' 编码。
        let result = FeedbackComposer.githubIssueUrl(
            title: "a b", body: "x", diag: diagnostic)
        XCTAssertTrue(result.contains("title=a+b"))
        let mailto = FeedbackComposer.mailtoUri(
            subject: "中文", body: "x", diag: diagnostic)
        XCTAssertTrue(mailto.contains("subject=%E4%B8%AD%E6%96%87"))
    }
}
