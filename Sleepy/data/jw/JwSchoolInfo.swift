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

    var isSupported: Bool { status == Self.STATUS_SUPPORTED || status == Self.STATUS_GRAD_SUPPORTED }
    var isGrad: Bool { status == Self.STATUS_GRAD_SUPPORTED || status == Self.STATUS_GRAD_PENDING }

    static let STATUS_SUPPORTED = "supported"
    static let STATUS_PENDING = "pending"
    static let STATUS_GRAD_SUPPORTED = "grad_supported"
    static let STATUS_GRAD_PENDING = "grad_pending"
    static let STATUS_LEGACY = "legacy"
}
