// L10n.swift — ← R.string 访问的 Swift 等价
// Android: context.getString(R.string.key, args...) → iOS: NSLocalizedString + String(format:)
// 语言切换: Android wrap(ContextWrapper) + Activity.recreate() → iOS 定向 Bundle + 重建通知。
// 全部访问走 LocaleHelper.currentBundle()(AppPrefs 当前语言),切语言后 post
// L10n.didChangeNotification → AppRoot 全树重建(等价 Activity.recreate)。

import Foundation

enum L10n {
    /// 语言变更通知 — AppRoot 监听后整树重建(← Android Activity.recreate())
    static let didChangeNotification = Notification.Name("L10n.didChange")

    /// L10n.t("key") — 无参
    static func t(_ key: String) -> String {
        NSLocalizedString(key, bundle: LocaleHelper.currentBundle(), comment: "")
    }

    /// L10n.format("key", args...) — Android context.getString(key, args) 等价
    /// 注: strings 已迁移为 %1$@ / %1$d 位置参数格式
    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: NSLocalizedString(key, bundle: LocaleHelper.currentBundle(), comment: ""),
               locale: LocaleHelper.locale(for: AppPrefs.shared.getLanguage()), arguments: args)
    }

    /// day_names 数组键(移植自 <string-array name="day_names">)
    static func dayName(_ index: Int) -> String {
        t("array_day_names_\(index)")
    }

    /// key 是否存在(缺失时 NSLocalizedString 返回 key 本身 → 判不等即可)
    static func has(_ key: String) -> Bool {
        let v = NSLocalizedString(key, bundle: LocaleHelper.currentBundle(), comment: "")
        return !v.isEmpty && v != key
    }
}
