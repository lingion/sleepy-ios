// LocaleHelper.swift — ← LocaleHelper.kt
// Android: ContextWrapper 注入 locale → iOS: 每语言独立 .lproj + Bundle 定向 + AppleLanguages
//
// iOS 无"给 Context 换 Configuration"机制;等价物:
//  1) App 内所有字符串走 L10n(已支持 bundle 定向) → 运行时切语言不重启
//  2) UserDefaults "AppleLanguages" 写入 → 下次启动系统级生效(WebView 等系统控件)
//  3) 语义化 locale: 首选语言特性(iOS16 AppIntents 之外的语言匹配由 Bundle 处理)

import Foundation

enum LocaleHelper {

    /// ← getLocale: langCode → Locale
    static func locale(for langCode: String) -> Locale {
        switch langCode {
        case "zh-CN": return Locale(identifier: "zh-Hans")
        case "zh-TW": return Locale(identifier: "zh-Hant")
        case "en": return Locale(identifier: "en")
        case "ja": return Locale(identifier: "ja")
        case "es": return Locale(identifier: "es")
        default: return Locale.current
        }
    }

    /// iOS 专属: langCode → lproj 目录名(资源定位用)
    static func lprojName(for langCode: String) -> String {
        switch langCode {
        case "zh-CN": return "zh-Hans"
        case "zh-TW": return "zh-Hant"
        default: return langCode
        }
    }

    /// ← wrap: 返回注入了指定语言的新"资源上下文" — iOS 等价 = 定向 Bundle
    /// 用法: LocaleHelper.bundle(for: lang).string(key) / L10n 走它
    static func bundle(for langCode: String) -> Bundle {
        let name = lprojName(for: langCode)
        if let path = Bundle.main.path(forResource: name, ofType: "lproj"),
           let b = Bundle(path: path) {
            return b
        }
        return .main // 找不到(如 default→系统语言)回退 main
    }

    /// ← wrapDefault: 从 AppPrefs 读取当前语言并定向
    /// iOS 语义: 返回当前应用语言 bundle;额外把语言写进 AppleLanguages,
    /// 使系统控件(WebView/系统弹窗)在下次启动跟随。无论哪种语言都强制写,防止系统 locale 覆盖。
    static func currentBundle() -> Bundle {
        let lang = AppPrefs.shared.getLanguage()
        return bundle(for: lang)
    }

    /// 切语言: 写 AppPrefs + AppleLanguages(下次启动全系统生效)+ 立即返回新 bundle
    static func applyLanguage(_ langCode: String) -> Bundle {
        AppPrefs.shared.setLanguage(langCode)
        UserDefaults.standard.set([lprojName(for: langCode)], forKey: "AppleLanguages")
        return bundle(for: langCode)
    }

    /// App 启动时调用一次 ← wrapDefault 的 attachBaseContext 位置
    static func attachOnLaunch() {
        _ = currentBundle() // 读取并固定(AppPrefs 异常时默认 zh-CN 由 AppPrefs 自身默认值兜底)
    }
}
