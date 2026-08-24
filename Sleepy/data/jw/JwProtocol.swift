// JwProtocol.swift — ← JwProtocol.kt
// 教务系统协议类型枚举。
//
// 基于 dIT8Zv/WakeupSchedule_BUPT (Apache-2.0) 的 Common.kt 协议类型常量
// 简化而来,保留 sleepy v1.0.8 实际用到的子集:
//   - QZ 强智 5 变体(HEU 用 QZ_CRAZY)
//   - ZF 正方 3 变体
//   - URP 2 变体
//   - PKU 北大 / CF 青果 / BNUZ 北师珠
//   - HELP / LOGIN / MAINTAIN 标记
//
// 完整 17 类 + 强智变体的语义见 https://github.com/dIT8Zv/WakeupSchedule_BUPT
// 中 `app/src/main/java/com/suda/yzune/wakeupschedule/schedule_import/Common.kt`。

enum JwProtocol {
    static let TYPE_HELP = "help"
    static let TYPE_ZF = "zf"
    static let TYPE_ZF_1 = "zf_1"
    static let TYPE_ZF_NEW = "zf_new"
    static let TYPE_URP = "urp"
    static let TYPE_URP_NEW = "urp_new"
    static let TYPE_QZ = "qz"
    static let TYPE_QZ_OLD = "qz_old"
    static let TYPE_QZ_CRAZY = "qz_crazy"
    static let TYPE_QZ_BR = "qz_br"
    static let TYPE_QZ_WITH_NODE = "qz_with_node"
    static let TYPE_CF = "cf"
    static let TYPE_PKU = "pku"
    static let TYPE_BNUZ = "bnuz"
    static let TYPE_LOGIN = "login"
    static let TYPE_MAINTAIN = "maintain"

    /// 金智 Wisedu jwapp 微应用平台(JSON API 直连,非 HTML 解析)。如:哈尔滨工程大学 jwgl.hrbeu.edu.cn
    static let TYPE_WISEDU = "wisedu"

    /// 协议显示名(用于 UI 提示) ← displayName
    static func displayName(_ type: String?) -> String {
        switch type {
        case TYPE_QZ, TYPE_QZ_OLD, TYPE_QZ_CRAZY, TYPE_QZ_BR, TYPE_QZ_WITH_NODE:
            return "强智教务"
        case TYPE_ZF, TYPE_ZF_1, TYPE_ZF_NEW:
            return "正方教务"
        case TYPE_URP, TYPE_URP_NEW:
            return "URP 教务"
        case TYPE_CF:
            return "青果教务"
        case TYPE_PKU:
            return "北京大学"
        case TYPE_BNUZ:
            return "北师珠"
        case TYPE_WISEDU:
            return "金智教务(直连)"
        case TYPE_LOGIN:
            return "特殊登录(v1 暂不支持)"
        case TYPE_HELP:
            return "如何选择教务类型"
        case TYPE_MAINTAIN:
            return "维护中"
        default:
            return type ?? ""
        }
    }

    /// 协议大类,用于 WebViewLogin UI 上的提示文案分类 ← category
    static func category(_ type: String?) -> String {
        switch type {
        case TYPE_QZ, TYPE_QZ_OLD, TYPE_QZ_CRAZY, TYPE_QZ_BR, TYPE_QZ_WITH_NODE:
            return "qz"
        case TYPE_ZF, TYPE_ZF_1, TYPE_ZF_NEW:
            return "zf"
        case TYPE_URP, TYPE_URP_NEW:
            return "urp"
        case TYPE_WISEDU:
            return "wisedu"
        default:
            return "other"
        }
    }
}
