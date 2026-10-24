// UpdateManagerDownloadFallbackTests.swift — ← UpdateManager.kt downloadApk 回退链的纯逻辑半边
// (F123 对齐: 空下载 URL 显式报错 + "direct == 原 URL 则不二次重试" 的判定, 均零网络可断言;
//  真实镜像→直连重试涉及 URLSession, 归集成测试, 此处不 mock)。

import XCTest
@testable import Sleepy

final class UpdateManagerDownloadFallbackTests: XCTestCase {

    /// 空 URL 必须显式报错(← Android URL("") MalformedURLException "no protocol",
    /// 而非 silently 404 下载)。链路: downloadOnce 先抛 .emptyDownload →
    /// toDirectGithubUrl("") == ""(非镜像前缀原样返回)→ direct == 原 URL → 抛主错误, 全程零网络。
    func testEmptyDownloadUrlThrowsExplicitErrorWithoutNetwork() async {
        let info = UpdateInfo(version: "1.0.99", changelog: "", downloadUrl: "", isUpdateAvailable: true)
        do {
            _ = try await UpdateManager.downloadIpa(info) { _ in }
            XCTFail("expected UpdateError.emptyDownload for empty url")
        } catch let error as UpdateManager.UpdateError {
            switch error {
            case .emptyDownload: break                       // ← 期望路径
            default: XCTFail("expected .emptyDownload, got \(error)")
            }
        } catch {
            XCTFail("expected UpdateError.emptyDownload, got \(error)")
        }
    }

    /// 回退判定的纯函数半边: GitHub 直连地址经 toDirectGithubUrl 幂等 →
    /// downloadIpa 中 direct == info.downloadUrl 成立 → 主错误直接上抛, 不重试第二次
    /// (← if (direct == info.downloadUrl) throw primary)。
    func testAlreadyDirectUrlIsNotRetriedBecauseFallbackYieldsSameUrl() {
        let direct = "https://github.com/lingion/sleepy-ios/releases/download/v1.0.99/Sleepy.ipa"
        XCTAssertEqual(direct, toDirectGithubUrl(direct))
        // 镜像地址才会产出不同的回退目标(重试路径)
        let mirror = "https://gh.qdp.qzz.io/lingion/sleepy-ios/releases/download/v1.0.99/Sleepy.ipa"
        XCTAssertEqual(direct, toDirectGithubUrl(mirror))
        XCTAssertNotEqual(mirror, toDirectGithubUrl(mirror))
    }
}
