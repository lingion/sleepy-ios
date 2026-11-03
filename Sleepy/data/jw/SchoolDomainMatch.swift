// SchoolDomainMatch.swift — ← SchoolDomainMatch.kt
//
// issue #25 — 把 typed URL 映射回 schools.json 目录条目。
//
// 失败链:
//   1. 用户输入 https://one.hfut.edu.cn/ (HFUT 统一信息门户, 非教务)
//   2. SchoolSelectScreen.UrlDirectRow 命中 → 创建自定义条目 type=nil
//   3. WebView 跳到门户 → 通用抓取 → 0 课
//
// 修复:
//   解析 typed URL 的 host, 取注册域, 在目录条目中查找相同注册域的 supported+有 URL 条目。
//   命中后用目录条目替代自定义条目 (拿到权威 URL + 协议 type)。
//
// 命名: 与 JwWebViewLoginScreen 的 SslBypassRegistry 一致, 委托同一 registrableDomain 实现
// (避免两个独立实现飘移)。

import Foundation

enum SchoolDomainMatch {

    // MARK: - URI 解析

    /// URL 结构解析结果 —— 对应 原版本 的 java.net.URI。
    /// 原版本 用 java.net.URI(value.trim()), 因此无 scheme 的字符串解析失败 → nil。
    struct ParsedURL: Equatable {
        let scheme: String        // 小写
        let host: String
        let port: Int             // 未显式指定时为 -1 (对应 java.net.URI.port)
        let path: String          // 原始路径 (未指定时 "")
        let query: String?        // 原始 query (无则 nil)
        let fragment: String?     // 原始 fragment (无则 nil)

        /// 有效端口 — 未指定时按 scheme 补 443/80 (原 sameEntry 同逻辑)。
        var effectivePort: Int {
            if port >= 0 { return port }
            return scheme == "https" ? 443 : 80
        }
    }

    /// 解析 URL → nil 表示不是可用的 http/https 入口。
    /// ← 原版本 parsed(): scheme 必须是 http/https + host 非空 + 无 userInfo。
    static func parsed(_ value: String) -> ParsedURL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil
        else { return nil }
        return ParsedURL(
            scheme: scheme,
            host: host,
            port: components.port ?? -1,
            path: components.percentEncodedPath,
            query: components.percentEncodedQuery,
            fragment: components.percentEncodedFragment
        )
    }

    /// 两个 URL 是否指向同一入口 (scheme + host + 有效端口 + 路径 + query + fragment)。
    /// ← 原版本 sameEntry(): 路径缺省都算 "/"。
    static func sameEntry(_ a: ParsedURL, _ b: ParsedURL) -> Bool {
        let pathA = a.path.isEmpty ? "/" : a.path
        let pathB = b.path.isEmpty ? "/" : b.path
        return a.scheme == b.scheme
            && a.host.lowercased() == b.host.lowercased()
            && a.effectivePort == b.effectivePort
            && pathA == pathB
            && a.query == b.query
            && a.fragment == b.fragment
    }

    /// UI 选择边界: 精确已知的 URL 保留其状态(包括 pending)。
    /// 共享 URL 返回全部候选让用户选, 绝不静默替用户选一个。
    /// 只有未知 URL 才可能变成自定义条目或走 supported-only 的注册域兜底。
    ///
    /// ← 原版本 selectionsForUrl()
    static func selectionsForUrl(_ url: String,
                                 _ catalog: [JwSchoolInfo],
                                 protocolType: String?,
                                 customName: String) -> [JwSchoolInfo] {
        let target = parsed(url)
        let exact: [JwSchoolInfo]
        if let target = target {
            exact = catalog.filter { school in
                guard let entry = parsed(school.url) else { return false }
                return sameEntry(entry, target)
            }
        } else {
            exact = []
        }
        if !exact.isEmpty { return exact }
        return [matchSchool(url, catalog) ?? JwSchoolInfo(
            sortKey: "",
            name: customName,
            url: url,
            type: protocolType,
            status: JwSchoolInfo.STATUS_SUPPORTED
        )]
    }

    // MARK: - 域名启发式

    /// 注册域启发式 — 与 SslBypassRegistry.registrableDomain 一致。
    /// 取末两段 (edu.cn / edu.hk / ac.uk / edu.tw / edu.jp 等多段后缀取末三段)。
    static func registrableDomain(_ host: String) -> String {
        let h = host.lowercased().trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if h.isEmpty { return "" }
        let parts = h.split(separator: ".").map(String.init)
        if parts.count <= 2 { return h }
        let secondLevel = parts[parts.count - 2]
        let tld = parts.last ?? ""
        if (tld == "cn" || tld == "hk" || tld == "uk" || tld == "tw" || tld == "jp"),
           ["edu", "ac", "gov", "org"].contains(secondLevel) {
            return parts.suffix(3).joined(separator: ".")
        }
        return parts.suffix(2).joined(separator: ".")
    }

    /// 抽 host: 处理 https?:// 前缀、尾部 /path、空白。空返回空串。
    static func hostOf(_ url: String) -> String {
        var u = url.trimmingCharacters(in: .whitespaces)
        if u.isEmpty { return "" }
        let schemeEnd: String.Index
        if let r = u.range(of: "://") {
            schemeEnd = r.upperBound
        } else {
            schemeEnd = u.startIndex
        }
        let rest = String(u[schemeEnd...])
        let hostAndPort: String
        if let slash = rest.firstIndex(of: "/") {
            hostAndPort = String(rest[..<slash])
        } else {
            hostAndPort = rest
        }
        if let colon = hostAndPort.firstIndex(of: ":") {
            return String(hostAndPort[..<colon])
        }
        return hostAndPort
    }

    /// 是否 WebVPN 重写 host (不可见原 host, 不可参与目录映射)。
    static func isVpnRewrite(_ host: String) -> Bool {
        if host.isEmpty { return false }
        return host.contains("/webvpn/")
            || host.contains(".webvpn.")
            || host.hasPrefix("webvpn.")
    }

    // MARK: - 目录匹配

    /// 在 catalog 中查找: 同注册域, supported (含 grad_supported), 有 URL。
    /// WebVPN / 未知域 / 空白 host → nil。
    ///
    /// ← 原版本 matchSchool(): 三级递进 (精确条目 → 同 host+port → 同注册域),
    /// 每级都要求**唯一**命中且该条目 isSupported && canImport。
    /// Pending / unverified 条目永远不自动改写用户输入的 URL。
    static func matchSchool(_ url: String, _ catalog: [JwSchoolInfo]) -> JwSchoolInfo? {
        guard let target = parsed(url) else { return nil }
        let host = target.host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if isVpnRewrite(host) { return nil }

        let candidates: [(JwSchoolInfo, ParsedURL)] = catalog.compactMap { school in
            guard let entry = parsed(school.url) else { return nil }
            return (school, entry)
        }
        // 唯一性要求: 多条候选 → 不自动选 (原版本 singleOrNull)
        func supportedSingle(_ matches: [(JwSchoolInfo, ParsedURL)]) -> JwSchoolInfo? {
            guard matches.count == 1 else { return nil }
            let school = matches[0].0
            return (school.isSupported && school.canImport) ? school : nil
        }

        let exact = candidates.filter { sameEntry($0.1, target) }
        if !exact.isEmpty { return supportedSingle(exact) }

        let sameHost = candidates.filter { $0.1.host.lowercased() == host && $0.1.port == target.port }
        if !sameHost.isEmpty { return supportedSingle(sameHost) }

        let domain = registrableDomain(host)
        let sameDomain = candidates.filter { registrableDomain($0.1.host) == domain }
        return supportedSingle(sameDomain)
    }
}
