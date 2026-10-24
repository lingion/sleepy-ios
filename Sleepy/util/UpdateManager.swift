// UpdateManager.swift — ← UpdateManager.kt
// 拉 GitHub/镜像 release 信息、下载 IPA、清理旧 IPA。不含 UI 状态。
//
// 平台差异表#2: Android REQUEST_INSTALL_PACKAGES 自装 APK →
// iOS 无自装;iOS 端 = 检查更新 + 展示 changelog + 下载 IPA 到本地(供 AltStore 侧载/隔空投送),
// 安装动作降级为「提示重新侧载」(由 UpdateChangelogDialog 移植体承担,见 SPEC 平台差异表)。

import Foundation
import Combine

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
        // 主站: Android runCatching{ } 同时包住读取与 JSON 解析 — 读到坏 JSON 也落到镜像回退,
        // 所以这里先验 JSON 是对象,不合格不 return(← org.json.JSONObject(json) 抛异常语义)
        if let json = try? await readText(GITHUB_API),
           let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
           obj is [String: Any] {
            return parseReleaseJson(json, currentVersion: currentVersionName, abi: "ios")
        }
        // 镜像回退:正则取 tag,changelog 从页面 markdown-body 块提取 ← parseMirrorPage(page, tag)
        let page = try await readText(MIRROR_RELEASE)
        guard let tag = firstMatch(of: #"/lingion/sleepy-ios/releases/tag/(v[0-9A-Za-z.+_-]+)"#, in: page) else {
            throw UpdateError.noVersionFound
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        // 镜像 HTML 不暴露 asset 列表 → 拼 asset 名 HEAD 探测,取 200..299 的那条(Android 侧是
        // candidatesFor(abi) 三候选; iOS 分发为 AltStore 单 IPA, 名固定 "Sleepy.ipa" — 平台差异表#2)。
        // 探测失败 → 空串下载 URL: Android 让空串触发 no-protocol 错误, iOS 侧由 downloadIpa
        // 走 UpdateError.emptyDownload — 都是显式报错而非 silently 404 下载(2026-09-05 语义)。
        let asset = "\(MIRROR_PREFIX)\(tag)/Sleepy.ipa"
        let url = await headOk(asset) ? asset : ""
        let isUpdate = VersionUtils.compare(version, currentVersionName) > 0
        return UpdateInfo(version: version, changelog: parseMirrorPage(page, tag: tag),
                          downloadUrl: url, isUpdateAvailable: isUpdate)
    }

    /// 下载 IPA 到 cachesDirectory,带进度回调(0-100)。cancel 时删半截文件。 ← downloadApk
    static func downloadIpa(_ info: UpdateInfo, onProgress: @escaping (Int) -> Void) async throws -> URL {
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("sleepy-update-Sleepy.ipa")
        do {
            try await downloadOnce(info.downloadUrl, to: target, onProgress: onProgress)
        } catch {
            // ← if (primary is CancellationException) throw primary
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            // 镜像下载失败 → GitHub 直连回退 (信息源/下载源各回退一次, 用户 2026-09-05 令)
            let direct = toDirectGithubUrl(info.downloadUrl)
            if direct == info.downloadUrl { throw error }
            try? FileManager.default.removeItem(at: target)
            try await downloadOnce(direct, to: target, onProgress: onProgress)
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: target.path)
        let size = attrs?[.size] as? Int ?? 0
        if size == 0 { throw UpdateError.emptyDownload }
        return target
    }

    /// 单次下载 ← downloadOnce。空 URL 触发显式错误(← Android URL("") MalformedURLException "no protocol")。
    private static func downloadOnce(
        _ urlString: String, to target: URL, onProgress: @escaping (Int) -> Void
    ) async throws {
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            throw UpdateError.emptyDownload
        }
        let request = URLRequest(url: url)
        var total = max(await contentLength(of: urlString) ?? 1, 1)
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

    /// HEAD 探测 200..299。← headOk (connectTimeout/readTimeout = 8_000ms)
    private static func headOk(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)   // ← responseCode in 200..299
        } catch {
            return false                                    // ← catch(_:Exception){ false }
        }
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


// ===== 1.0.51 移植: 自动检查更新开关持久化 ← AppPrefs.setUpdateCheckEnabled =====
// key 与 Android 完全一致; 未设置时默认开(← getBoolean(KEY_UPDATE_CHECK_ENABLED, true))

enum UpdateCheckPrefs {
    private static let key = "update_check_enabled"

    static var isEnabled: Bool {
        let d = UserDefaults.standard
        return d.object(forKey: key) == nil ? true : d.bool(forKey: key)
    }

    static func setEnabled(_ v: Bool) {
        UserDefaults.standard.set(v, forKey: key)
    }
}

// ===== 1.0.51 移植: 冷启动检查更新 ← util/UpdateNotifier.kt =====
// 语义同 Android: 关开关→直接返回(不占一次性名额); 在途或已缓存→跳过(进程内只查一次);
// 失败静默(cache 保持 nil, 下次可再查); 关开关清缓存→横幅/高亮立即消失并取消在途请求。
// Android 在 MainActivity.onCreate 触发, iOS 无法改 App 入口, 由 AboutScreen.task 触发。

/// 纯版本级关闭规则, 各更新提醒界面共用 ← util/UpdateNoticeCore.kt (v1.0.60 对齐)
enum UpdateNoticeCore {
    static func isVisible(_ update: UpdateInfo?, _ dismissedVersion: String?) -> Bool {
        update?.isUpdateAvailable == true &&
        !(update?.version.isBlank ?? true) &&
        update?.version != dismissedVersion
    }
}

final class UpdateNotifier: ObservableObject {
    static let shared = UpdateNotifier()

    @Published private(set) var updateAvailable: UpdateInfo?
    /// 所有更新提醒 UI 共用的可见状态; dismiss 按版本记忆 ← noticeVisible (v1.0.60 对齐)
    @Published private(set) var noticeVisible: Bool = false
    private var inFlight: Task<Void, Never>?

    private static let dismissedKey = "update_notice_dismissed_version"

    func loadDismissedVersion() {
        objectWillChange.send()
        refreshNoticeVisible()
    }

    func dismissedVersion() -> String {
        UserDefaults.standard.string(forKey: Self.dismissedKey) ?? ""
    }

    /// dismiss 按版本持久化; 新版本自然重新显示 ← dismiss(version)
    func dismiss(version: String) {
        if version.isBlank { return }
        UserDefaults.standard.set(version, forKey: Self.dismissedKey)
        refreshNoticeVisible()
    }

    /// Debug-only visual fixture; production callers must use maybeCheckOnStart ← showMockUpdate
    func showMockUpdate() {
        self.updateAvailable = UpdateInfo(
            version: "1.0.58",
            changelog: "## Mock update\n\n- 新版本提醒预览\n- 课程表显示优化",
            downloadUrl: "https://example.invalid/mock.apk",
            isUpdateAvailable: true
        )
        refreshNoticeVisible()
    }

    private func refreshNoticeVisible() {
        noticeVisible = UpdateNoticeCore.isVisible(updateAvailable, dismissedVersion())
    }

    func maybeCheckOnStart() {
        guard UpdateCheckPrefs.isEnabled else { return }
        guard updateAvailable == nil, inFlight == nil else { return }
        inFlight = Task {
            do {
                let info = try await UpdateManager.fetchUpdateInfo()
                await MainActor.run {
                    self.inFlight = nil
                    if info.isUpdateAvailable { self.updateAvailable = info }
                    self.refreshNoticeVisible()
                }
            } catch {
                // 失败静默 ← runCatching { }: 用户没要求弹错
                await MainActor.run { self.inFlight = nil }
            }
        }
    }

    /// 用户在「关于」底部 Toggle 关闭后清空缓存, 立即消失横幅/高亮 ← clearCache()
    func clearCache() {
        inFlight?.cancel()
        inFlight = nil
        updateAvailable = nil
        noticeVisible = false
    }
}
