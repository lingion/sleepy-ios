import Foundation

/// 共用业务现在时（原 Debug Console 虚拟时间入口已随调试台下线移除，恒为真实时间）。
enum AppClock {
    static var now: Date { Date() }
}
