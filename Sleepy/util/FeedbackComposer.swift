import Foundation

/**
 * 反馈工具类:拼装 GitHub 新 Issue URL 和 mailto: 链接,
 * 在关于页面供用户跳出去提反馈。
 *
 * Android FeedbackComposer.kt 1:1 移植。
 *
 * 设计原则:
 * - 应用不调用 GitHub API,只构造 URL 让系统浏览器或邮件客户端打开。
 * - 诊断信息只包含版本/系统/设备/分辨率/语言/构建类型,不含课表内容、文件、账号、位置等隐私数据。
 * - 所有用户可控字符串都做 URL 编码,防止 ?title= 等被注入额外参数。
 */
public enum FeedbackComposer {

    public static let githubRepo = "lingion/sleepy"
    public static let fallbackEmail = "lingion@hrbeu.edu.cn"
    private static let newIssuePath = "/issues/new"

    /// 诊断数据快照。iOS 上由调用方填实。
    public struct Diagnostic {
        public let versionName: String
        public let versionCode: Int
        public let osVersion: String       // iOS 16.4
        public let deviceBrand: String     // "Apple"
        public let deviceModel: String     // "iPhone"
        public let resolution: String      // "750x1334"
        public let locale: String          // "zh-Hans"
        public let isDebug: Bool

        public init(versionName: String, versionCode: Int, osVersion: String,
                    deviceBrand: String, deviceModel: String, resolution: String,
                    locale: String, isDebug: Bool) {
            self.versionName = versionName
            self.versionCode = versionCode
            self.osVersion = osVersion
            self.deviceBrand = deviceBrand
            self.deviceModel = deviceModel
            self.resolution = resolution
            self.locale = locale
            self.isDebug = isDebug
        }
    }

    /**
     * 构造 GitHub 新 Issue URL。
     * 参数顺序: ?template= → ?title= → ?body=, 保证 GitHub 优先识别模板并把诊断信息落到 body。
     */
    public static func githubIssueUrl(
        title: String,
        body: String,
        diag: Diagnostic,
        template: String? = nil
    ) -> String {
        let encodedTitle = enc(title)
        let encodedBody = enc("\(body)\n\n\(formatDiagnostic(diag))")
        var params: [String] = []
        if let t = template, !t.isEmpty {
            params.append("template=\(enc(t))")
        }
        params.append("title=\(encodedTitle)")
        params.append("body=\(encodedBody)")
        return "https://github.com/\(githubRepo)\(newIssuePath)?\(params.joined(separator: "&"))"
    }

    /// 构造 mailto: URI
    public static func mailtoUri(
        subject: String,
        body: String,
        diag: Diagnostic,
        email: String = fallbackEmail
    ) -> String {
        let encodedSubject = enc(subject)
        let encodedBody = enc("\(body)\n\n\(formatDiagnostic(diag))")
        return "mailto:\(email)?subject=\(encodedSubject)&body=\(encodedBody)"
    }

    /// 渲染诊断信息块, 作为 Issue / 邮件 body 的一部分
    public static func formatDiagnostic(_ d: Diagnostic) -> String {
        return """
        ---
        **Version:** \(escapeMd(d.versionName))
        **VersionCode:** \(d.versionCode)
        **iOS:** \(escapeMd(d.osVersion))
        **Device:** \(escapeMd(d.deviceBrand)) \(escapeMd(d.deviceModel))
        **Resolution:** \(escapeMd(d.resolution))
        **Locale:** \(escapeMd(d.locale))
        **Build:** \(d.isDebug ? "Debug" : "Release")
        """
    }

    // MARK: - 内部

    private static func enc(_ s: String) -> String {
        // 与 Android java.net.URLEncoder.encode(s, "UTF-8") 逐字节对齐:
        // 字面保留 [A-Za-z0-9] . - * _ ; 空格转 '+' ; 其余(含非 ASCII、'~'、'/'、'+' 等)
        // 按 UTF-8 字节做大写十六进制百分号编码。全量编码包括 `/` `+` 等避免语义出错。
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-*")
        let encoded = s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        // URLEncoder 用 '+' 表示空格; 输入里的字面 "%20" 已被编码为 "%2520",替换安全。
        return encoded.replacingOccurrences(of: "%20", with: "+")
    }

    /**
     * 把字面意义上有破坏性的 Markdown 字符转义成反斜杠前缀
     * 仅转义 * _ ` [ ] ( ),足以拦住注入而不影响普通文本。
     */
    private static func escapeMd(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        for c in s {
            if c == "*" || c == "_" || c == "`" || c == "[" || c == "]" || c == "(" || c == ")" {
                result.append("\\")
            }
            result.append(c)
        }
        return result
    }
}
