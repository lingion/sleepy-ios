// UpdateInfo.swift — ← UpdateInfo.kt
// 远端 release 信息(纯数据,不含平台依赖,可单测)。
//
// [isUpdateAvailable] 由 [parseReleaseJson] 根据版本比较 + force flag 算出。
// 调用方(UpdateManager)据它决定弹窗 vs Toast。

import Foundation

struct UpdateInfo: Equatable {
    let version: String
    let changelog: String
    let downloadUrl: String
    let isUpdateAvailable: Bool
}

private let FORCE_FLAG = "SLEEPY_FORCE_UPDATE=true"

/// 解析 GitHub releases/latest 的 JSON 为 [UpdateInfo](纯函数,无 IO)。 ← parseReleaseJson
///
/// [abi] Android 侧形如 "arm64-v8a"(挑对应 APK asset);iOS 分发为 AltStore 单 IPA,
/// asset 名固定 "Sleepy.ipa"(见平台差异表#2: 安装动作改为提示重新侧载)。
/// 找不到对应 asset 时 downloadUrl 返回空串(调用方走镜像回退)。
func parseReleaseJson(_ json: String, currentVersion: String, abi: String) -> UpdateInfo {
    // ← org.json.JSONObject;iOS 16 用 JSONSerialization(保持无第三方依赖)
    guard let data = json.data(using: .utf8),
          let release = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        // JSON 坏 → Android optString 语义 = 空串 → version "0" → 恒非更新
        return UpdateInfo(version: "", changelog: "", downloadUrl: "", isUpdateAvailable: false)
    }
    let tag = release["tag_name"] as? String ?? ""
    let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    let body = release["body"] as? String ?? ""
    // Android: app-$abi-release.apk;iOS: Sleepy.ipa(abi 参数保留以对齐签名,忽略值)
    let assetName = abi.isEmpty ? "Sleepy.ipa" : "Sleepy.ipa"
    var downloadUrl = ""
    if let assets = release["assets"] as? [[String: Any]] {
        downloadUrl = assets.first(where: { ($0["name"] as? String) == assetName })?["browser_download_url"] as? String ?? ""
    }
    let force = body.contains(FORCE_FLAG)
    let isUpdateAvailable = force ||
        VersionUtils.compare(version.isEmpty ? "0" : version, currentVersion) > 0
    return UpdateInfo(version: version, changelog: body, downloadUrl: downloadUrl, isUpdateAvailable: isUpdateAvailable)
}
