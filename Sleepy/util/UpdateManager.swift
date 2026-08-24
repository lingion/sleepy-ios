// UpdateManager.swift — ← UpdateManager.kt
// 拉 GitHub/镜像 release 信息、下载 IPA、清理旧 IPA。不含 UI 状态。
//
// 平台差异表#2: Android REQUEST_INSTALL_PACKAGES 自装 APK →
// iOS 无自装;iOS 端 = 检查更新 + 展示 changelog + 下载 IPA 到本地(供 AltStore 侧载/隔空投送),
// 安装动作降级为「提示重新侧载」(由 UpdateChangelogDialog 移植体承担,见 SPEC 平台差异表)。

import Foundation

enum UpdateManager {
    private static let GITHUB_API = "https://api.github.com/repos/lingion/sleepy-ios/releases/latest"
    private static let MIRROR_RELEASE = "https://gh.qdp.qzz.io/lingion/sleepy-ios/releases/latest"
    private static let MIRROR_PREFIX = "https://gh.qdp.qzz.io/lingion/sleepy-ios/releases/download/"

    /// 当前 App 版本(= Android BuildConfig.VERSION_NAME;iOS = CFBundleShortVersionString)
    static var currentVersionName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }

    /// 只拉 release 信息,不下载。GitHub 不通回退镜像。 ← fetchUpdateInfo
    static func fetchUpdateInfo() async throws -> UpdateInfo {
        // 主站
        if let json = try? await readText(GITHUB_API) {
            return parseReleaseJson(json, currentVersion: currentVersionName, abi: "ios")
        }
        // 镜像回退:正则取 tag,body 取不到
        let page = try await readText(MIRROR_RELEASE)
        guard let tag = firstMatch(of: #"/lingion/sleepy-ios/releases/tag/(v[0-9A-Za-z.+_-]+)"#, in: page) else {
            throw UpdateError.noVersionFound
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let url = "\(MIRROR_PREFIX)\(tag)/Sleepy.ipa"
        let isUpdate = VersionUtils.compare(version, currentVersionName) > 0
        return UpdateInfo(version: version, changelog: "", downloadUrl: url, isUpdateAvailable: isUpdate)
    }

    /// 下载 IPA 到 cachesDirectory,带进度回调(0-100)。cancel 时删半截文件。 ← downloadApk
    static func downloadIpa(_ info: UpdateInfo, onProgress: @escaping (Int) -> Void) async throws -> URL {
        guard !info.downloadUrl.isEmpty else { throw UpdateError.emptyDownload }
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("sleepy-update-Sleepy.ipa")
        // ← conn.contentLengthLong(HEAD 先探)
        var request = URLRequest(url: URL(string: info.downloadUrl)!)
        var total = max(await contentLength(of: info.downloadUrl) ?? 1, 1)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse,
           let len = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init), len > 0 {
            total = len
        }
        do {
            var data = Data()
            data.reserveCapacity(min(Int(total), 64 * 1024 * 1024))
            var downloaded = 0
            // ← while(true) { coroutineContext.ensureActive(); input.read(buf) }
            for try await b in bytes {
                try Task.checkCancellation()
                data.append(b)
                downloaded += 1
                onProgress(Int(min(Double(downloaded) * 100.0 / Double(total), 100.0)))
            }
            try data.write(to: target)
        } catch {
            // ← catch { target.delete(); throw }
            try? FileManager.default.removeItem(at: target)
            throw error
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: target.path)
        let size = attrs?[.size] as? Int ?? 0
        if size == 0 { throw UpdateError.emptyDownload }
        return target
    }

    /// 启动时清理 cachesDirectory 中旧安装包。 ← cleanOldApk
    static func cleanOldIpa() {
        let dir = FileManager.default.temporaryDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.lastPathComponent.hasPrefix("sleepy-update-") {
            try? FileManager.default.removeItem(at: f)
        }
    }

    // ===== 网络底层 ← readText/request =====

    private static func readText(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw UpdateError.http(-1) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Sleepy/\(currentVersionName)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json,text/html,*/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw UpdateError.http(http.statusCode)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func contentLength(of urlString: String) async -> Int? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse,
           let len = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init), len > 0 {
            return len
        }
        return nil
    }

    /// ← Regex(...).find(page)?.groupValues?.get(1)
    private static func firstMatch(of pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    enum UpdateError: LocalizedError {
        case noVersionFound   // ← error_no_version_found
        case emptyDownload    // ← error_empty_download
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .noVersionFound: return L10n.t("error_no_version_found")
            case .emptyDownload: return L10n.t("error_empty_download")
            case .http(let code): return "HTTP \(code)"
            }
        }
    }
}
