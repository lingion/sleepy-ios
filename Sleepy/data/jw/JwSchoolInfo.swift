// JwSchoolInfo.swift — ← JwSchoolInfo.kt
// 学校信息(教务入口元数据)
//
// 字段含义:
//   - sortKey: 拼音首字母 / "#" 表示"我的学校"(最近用过)/ "通" 表示通用类型分组
//   - name: 学校名(用户可见)
//   - url: 教务入口 URL(WebView 直接打开此 URL)。status != "supported" 时为空
//   - type: 协议类型(见 JwProtocol)。status != "supported" 时为 nil
//   - status: 支持状态 — "supported" 已实现 / "pending" 本科待适配 / "grad_supported" 研究生已支持 / "grad_pending" 研究生待适配 / "legacy" 旧条目

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

    var isSupported: Bool { status == Self.STATUS_SUPPORTED || status == Self.STATUS_GRAD_SUPPORTED }
    var isGrad: Bool { status == Self.STATUS_GRAD_SUPPORTED || status == Self.STATUS_GRAD_PENDING }

    /// T13: pending/grad_pending 状态 — 待适配(点行弹申请适配弹窗, 不进 WebView)
    var isPending: Bool { status == Self.STATUS_PENDING || status == Self.STATUS_GRAD_PENDING }

    /// T13: 是否配置了可打开的教务 URL
    var hasUrl: Bool { !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    static let STATUS_SUPPORTED = "supported"
    static let STATUS_PENDING = "pending"
    static let STATUS_GRAD_SUPPORTED = "grad_supported"
    static let STATUS_GRAD_PENDING = "grad_pending"
    static let STATUS_LEGACY = "legacy"
}
