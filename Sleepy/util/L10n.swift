// L10n.swift — ← R.string 访问的 Swift 等价
// 原版本: context.getString(R.string.key, args...) → iOS: NSLocalizedString + String(format:)
// 语言切换: 原版本 wrap(ContextWrapper) + Activity.recreate() → iOS 定向 Bundle + 重建通知。
// 全部访问走 LocaleHelper.currentBundle()(AppPrefs 当前语言),切语言后 post
// L10n.didChangeNotification → AppRoot 全树重建(等价 Activity.recreate)。

import Foundation

enum L10n {
    /// 语言变更通知 — AppRoot 监听后整树重建(Activity.recreate())
    static let didChangeNotification = Notification.Name("L10n.didChange")

    private struct TemplateKey: Hashable {
        let lang: String
        let key: String
    }
    private static let cacheLock = NSLock()
    private static var templateCache: [TemplateKey: String] = [:]

    private static func localizedTemplate(for key: String, lang: String) -> String {
        let cacheKey = TemplateKey(lang: lang, key: key)
        cacheLock.lock()
        if let hit = templateCache[cacheKey] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()
        let value = NSLocalizedString(key, bundle: LocaleHelper.bundle(for: lang), comment: "")
        cacheLock.lock()
        if templateCache.count >= 2048 { templateCache.removeAll(keepingCapacity: true) }
        templateCache[cacheKey] = value
        cacheLock.unlock()
        return value
    }

    /// L10n.t("key") — 无参
    static func t(_ key: String) -> String {
        localizedTemplate(for: key, lang: AppPrefs.shared.getLanguage())
    }

    /// L10n.format("key", args...) — 原版本 context.getString(key, args) 等价
    /// 注: strings 已迁移为 %1$@ / %1$d 位置参数格式
    static func format(_ key: String, _ args: CVarArg...) -> String {
        let lang = AppPrefs.shared.getLanguage()
        return String(format: localizedTemplate(for: key, lang: lang),
                      locale: LocaleHelper.locale(for: lang), arguments: args)
    }

    /// 复数格式(原 plurals 等价) — .stringsdict 走 localizedStringWithFormat 展开;
    /// 只有普通 .strings 键时退化为 format(城市在前, 数量在后)。
    static func plural(_ key: String, _ count: Int, _ args: CVarArg...) -> String {
        String.localizedStringWithFormat(
            localizedTemplate(for: key, lang: AppPrefs.shared.getLanguage()),
            args[0], count)
    }

    /// day_names 数组键(移植自 <string-array name="day_names">)
    static func dayName(_ index: Int) -> String {
        t("array_day_names_\(index)")
    }

    /// key 是否存在(缺失时 NSLocalizedString 返回 key 本身 → 判不等即可)
    static func has(_ key: String) -> Bool {
        let v = t(key)
        return !v.isEmpty && v != key
    }
}
