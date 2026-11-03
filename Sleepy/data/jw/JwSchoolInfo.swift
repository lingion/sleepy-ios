// JwSchoolInfo.swift — ← JwSchoolInfo.kt
// 学校信息(教务入口元数据)
//
// 字段含义:
//   - sortKey: 拼音首字母 / "#" 表示"我的学校"(最近用过)/ "通" 表示通用类型分组
//   - name: 学校名(用户可见)
//   - url: 教务入口 URL(WebView 直接打开此 URL)。待适配条目可以没有入口。
//   - type: 已声明的协议类型(见 JwProtocol)。未知协议为 nil。
//   - status: 支持状态 — "supported" 已实现 / "pending" 本科待适配 /
//     "grad_supported" 研究生已支持 / "grad_pending" 研究生待适配 /
//     "unverified" / "grad_unverified" 需用户确认后尝试 / "legacy" 旧条目
//   - catalogId: 目录条目的稳定身份(旧资产与草稿没有该字段 → 回落到 sortKey_name)

import Foundation

struct JwSchoolInfo: Equatable {
    let sortKey: String
    let name: String
    var url: String = ""
    var type: String? = nil
    var status: String = STATUS_SUPPORTED
    var aliases: [String] = []
    var sortKeyFull: String = ""
    /// T11 新增:该校是否启用 WebView 内 fetch 模式。默认 false 避免给未验证学校强行 fetch 出 0 课。
    var enableFetch: Bool = false
    /// Known home/campus cities, used only for the school picker recommendations.
    /// ← v1.0.60 同城推荐: 城市元数据与导入目录分离, 不影响 URL/协议。
    var cities: [String] = []
    /// 目录条目的稳定身份;旧资产与旧草稿为空 → stableKey 回落到 sortKey_name。
    var catalogId: String = ""

    /// 稳定身份 — 列表 ForEach 的 key、目录去重键都用它。
    /// ← 原 `stableKey`: catalogId 非空则用它, 否则 "\(sortKey)_\(name)"。
    var stableKey: String {
        let id = catalogId.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? "\(sortKey)_\(name)" : id
    }

    var isSupported: Bool {
        (status == Self.STATUS_SUPPORTED || status == Self.STATUS_GRAD_SUPPORTED)
            && !(type?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
    var isGrad: Bool { status == Self.STATUS_GRAD_SUPPORTED || status == Self.STATUS_GRAD_PENDING }

    /// T13: pending/grad_pending 状态 — 待适配(点行弹申请适配弹窗, 不进 WebView)
    var isPending: Bool { status == Self.STATUS_PENDING || status == Self.STATUS_GRAD_PENDING }

    /// 是否可以进入教务导入流程。
    /// ← 原版本 canImport: (已支持 或 (未验证 且 该协议有 parser)) 且 有可用 URL。
    var canImport: Bool {
        (isSupported || (isUnverified && JwParserRegistry.supports(type))) && hasUrl
    }

    /// T13: 是否配置了可打开的教务 URL。
    /// ← 原版本 hasUrl: URI 校验 — http/https 协议 + host 非空 + 不带 userInfo。
    var hasUrl: Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil
        else { return false }
        return true
    }

    /// 状态归一 — 缺省/未知值永不放行导入(fail-closed 到 pending)。
    /// ← 原版本 normalizeStatus(raw): null/"" → supported; 未知 → pending。
    static func normalizeStatus(_ raw: String?) -> String {
        switch raw {
        case nil, "", STATUS_SUPPORTED: return STATUS_SUPPORTED
        case STATUS_GRAD_SUPPORTED: return STATUS_GRAD_SUPPORTED
        case STATUS_GRAD_PENDING: return STATUS_GRAD_PENDING
        case STATUS_UNVERIFIED: return STATUS_UNVERIFIED
        case STATUS_GRAD_UNVERIFIED: return STATUS_GRAD_UNVERIFIED
        case STATUS_LEGACY: return STATUS_LEGACY
        default: return STATUS_PENDING
        }
    }

    static let STATUS_UNVERIFIED = "unverified"
    static let STATUS_GRAD_UNVERIFIED = "grad_unverified"
    static let STATUS_SUPPORTED = "supported"
    static let STATUS_PENDING = "pending"
    static let STATUS_GRAD_SUPPORTED = "grad_supported"
    static let STATUS_GRAD_PENDING = "grad_pending"
    static let STATUS_LEGACY = "legacy"
}
