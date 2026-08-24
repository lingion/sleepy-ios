// L10n.swift — ← R.string 访问的 Swift 等价
// Android: context.getString(R.string.key, args...) → iOS: NSLocalizedString + String(format:)

import Foundation

enum L10n {
    /// L10n.t("key") — 无参
    static func t(_ key: String) -> String {
        NSLocalizedString(key, bundle: .main, comment: "")
    }

    /// L10n.format("key", args...) — Android context.getString(key, args) 等价
    /// 注: strings 已迁移为 %1$@ / %1$d 位置参数格式
    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: NSLocalizedString(key, bundle: .main, comment: ""), locale: Locale.current, arguments: args)
    }

    /// day_names 数组键(移植自 <string-array name="day_names">)
    static func dayName(_ index: Int) -> String {
        t("array_day_names_\(index)")
    }
}
