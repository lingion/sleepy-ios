// QqJoin.swift — ← util/QqJoin.kt 逐行翻译 (GPL-3.0)
// QQ 加群拉起链路(纯 URI 字符串构造, 便于单测; 拉起时序见 AboutScreen.joinQqGroup)。
// iOS 侧拉起通道: UIApplication.open(URL) — mqqapi:// scheme 需装 QQ 才有 handler,
// canOpen 判定 + web 兜底由调用方(AboutScreen)执行, 与 原版本 try-catch ActivityNotFound 同语义。

import Foundation

enum QqJoin {
    static let SCHEME_MAIN = "mqqapi"
    static let CARD_TYPE_GROUP = "card_type=group"

    static func groupCardUri(_ groupNumber: String) -> String {
        "mqqapi://card/show_pslcard?src_type=internal&version=1&card_type=group&uin=\(groupNumber)"
    }

    static func groupCardUriAlt(_ groupNumber: String) -> String {
        "mqqapi://card/show_pslg?src_type=internal&version=1&groupuin=\(groupNumber)"
    }

    /// 官方加群组件, 需要群主在 qun.qq.com 生成的 key;
    /// 没有 key 时返回 nil(旧实现凭空拼这个 URL 正是"点了没反应"的根因)
    static func officialJoinComponentUri(_ groupNumber: String, _ key: String?) -> String? {
        guard let key, !key.isBlank else { return nil }
        let inner = "https://qm.qq.com/cgi-bin/qm/qr?from=app&p=android&jump_from=webapi&k=\(key)"
        return "mqqopensdkapi://bizAgent/qm/qr?url=\(urlEncode(inner))"
    }

    /// Swift percent-encode(与 android.net.Uri.encode 同保留集), 单测可验证
    static func urlEncode(_ s: String) -> String {
        let keep = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-!.~'()*"
        var out = ""
        for b in s.utf8 {
            let c = Character(UnicodeScalar(b))
            if keep.contains(c) {
                out.append(c)
            } else {
                out += String(format: "%%%02X", b)
            }
        }
        return out
    }

    static func webFallbackUri(_ groupNumber: String) -> String {
        "https://qm.qq.com/cgi-bin/qm/qr?from=app&jump_from=webapi&href=\(groupNumber)"
    }
}
