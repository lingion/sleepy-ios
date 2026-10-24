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

/// 镜像下载前缀 — 目录结构与 github.com 1:1, 直接字符串替换即可改写。 ← MIRROR_HOST/GITHUB_DOWNLOAD_HOST
private let MIRROR_HOST = "https://gh.qdp.qzz.io"
private let GITHUB_DOWNLOAD_HOST = "https://github.com"
/// Android 侧发布仓库是 lingion/sleepy;iOS 分发走 lingion/sleepy-ios
/// (与 UpdateManager.GITHUB_API/MIRROR_PREFIX 同源), 改写路径按 iOS 仓库作用域。
private let GITHUB_DOWNLOAD_PREFIX = "https://github.com/lingion/sleepy-ios/releases/download/"
private let MIRROR_DOWNLOAD_PREFIX = "https://gh.qdp.qzz.io/lingion/sleepy-ios/releases/download/"

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
    return UpdateInfo(version: version, changelog: body,
                      downloadUrl: downloadUrl.toMirrorDownloadUrl(), isUpdateAvailable: isUpdateAvailable)
}

extension String {
    /// github.com 下载地址 → 镜像地址; 非下载路径原样返回。 ← String.toMirrorDownloadUrl
    fileprivate func toMirrorDownloadUrl() -> String {
        guard hasPrefix(GITHUB_DOWNLOAD_PREFIX) else { return self }
        return MIRROR_HOST + dropFirst(GITHUB_DOWNLOAD_HOST.count)
    }
}

/// 镜像下载地址 → github.com 直连(下载失败的回退); 其余原样返回。 ← toDirectGithubUrl
func toDirectGithubUrl(_ url: String) -> String {
    guard url.hasPrefix(MIRROR_DOWNLOAD_PREFIX) else { return url }
    return GITHUB_DOWNLOAD_HOST + url.dropFirst(MIRROR_HOST.count)
}

///
/// 从镜像 release 页 HTML 提取 changelog,转成 Markdown。 ← parseMirrorPage
///
/// GitHub release 页把正文放在 <div class="markdown-body ..."> 里(渲染后的 HTML)。
/// 取第一个 markdown-body 块,做块级/行内两级转换回 Markdown。
/// 找不到块(页面 404/结构变化)返回空串,调用方回退到"看不到更新内容"而不是崩。
///
/// 已知局限:markdown-body 内嵌套 <div>(如 <details>)会在第一个 </div> 被截断。
/// 纯文本+列表的 release notes(本项目的情况)不受影响。
func parseMirrorPage(_ pageHtml: String, tag: String) -> String {
    // 只认含 markdown-body 的 div 开标签(GitHub 固定写法,前面可能带 data-* 属性)
    guard let openRange = pageHtml.range(
        of: #"<div\b[^>]*class="[^"]*markdown-body[^"]*"[^>]*>"#,
        options: .regularExpression
    ) else { return "" }
    let rest = String(pageHtml[openRange.upperBound...])
    guard let close = rest.range(of: "</div>")?.lowerBound else { return "" }
    let block = String(rest[..<close])
    return htmlToMarkdown(block).trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 块级 + 行内两级 HTML→Markdown。只覆盖 GitHub release notes 用到的标签。 ← htmlToMarkdown
private func htmlToMarkdown(_ html: String) -> String {
    // ← RegexOption.DOT_MATCHES_ALL
    let all: NSRegularExpression.Options = .dotMatchesLineSeparators
    var s = html
    // 块级:标题、列表项、段落 → 前缀 + 换行
    s = replaceMatches(#"<h([1-6])[^>]*>(.*?)</h\1>"#, in: s, options: all) { g in
        let hashes = String(repeating: "#", count: Int(g[1]) ?? 1)
        return "\n\n\(hashes) \(g[2].trimmed())\n\n"
    }
    s = replaceMatches(#"<li[^>]*>(.*?)</li>"#, in: s, options: all) { g in
        "\n- \(g[1].trimmed())"
    }
    s = replaceMatches(#"</?[uo]l[^>]*>"#, in: s) { _ in "\n" }
    s = replaceMatches(#"<p[^>]*>(.*?)</p>"#, in: s, options: all) { g in
        "\n\n\(g[1].trimmed())\n\n"
    }
    // 行内:加粗、斜体、代码、链接(链接必须在其它行内标签之后,避免 href 里的 ** 被误转)
    s = replaceMatches(#"<(strong|b)[^>]*>(.*?)</\1>"#, in: s, options: all) { g in
        "**\(g[2].trimmed())**"
    }
    s = replaceMatches(#"<(em|i)[^>]*>(.*?)</\1>"#, in: s, options: all) { g in
        "*\(g[2].trimmed())*"
    }
    s = replaceMatches(#"<code[^>]*>(.*?)</code>"#, in: s, options: all) { g in
        "`\(g[1].trimmed())`"
    }
    s = replaceMatches(#"<a\b[^>]*href="([^"]*)"[^>]*>(.*?)</a>"#, in: s, options: all) { g in
        "[\(g[2].trimmed())](\(g[1]))"
    }
    // 剥掉剩余任何标签(div/span/hr/br/img/svg...),保留文本
    s = replaceMatches(#"<[^>]+>"#, in: s) { _ in "" }
    s = decodeEntities(s)
    // 压掉多余空行(转换产生的 \n\n\n... 收敛到最多两个)
    return replaceMatches(#"\n{3,}"#, in: s) { _ in "\n\n" }
}

/// 正则全量替换,替换值来自捕获组计算(Kotlin Regex.replace{ m -> } 语义:
/// 结果文本中的 $ 等不参与模板展开)。组号 1..n, 组 0 = 整段匹配。
private func replaceMatches(
    _ pattern: String, in text: String,
    options: NSRegularExpression.Options = [],
    _ transform: ([String]) -> String
) -> String {
    guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
    let ns = text as NSString
    let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
    guard !matches.isEmpty else { return text }
    let out = NSMutableString(string: text)
    for m in matches.reversed() {
        let groups = (0..<m.numberOfRanges).map { i -> String in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
        out.replaceCharacters(in: m.range, with: transform(groups))
    }
    return out as String
}

private extension String {
    /// ← Kotlin String.trim()
    func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// ← decodeEntities
private func decodeEntities(_ s: String) -> String {
    var out = s
    for (entity, value) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
                            ("&nbsp;", " ")] {
        out = out.replacingOccurrences(of: entity, with: value)
    }
    return out
}
