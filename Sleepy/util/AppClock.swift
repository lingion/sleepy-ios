import Foundation

/// 共用业务现在时；Release/widget/watch 只有真实时间读取，调试写入口不参与编译。
enum AppClock {
    static var now: Date {
        #if DEBUG && !WIDGET_EXT && !WATCH_APP
        return Date().addingTimeInterval(debugOffset / 1000)
        #else
        return Date()
        #endif
    }

    #if DEBUG && !WIDGET_EXT && !WATCH_APP
    private static let lock = NSLock()
    private static var offsetMs: Double = 0
    static let didChange = Notification.Name("Sleepy.DebugClock.didChange")
    static var debugOffset: Double {
        lock.lock(); defer { lock.unlock() }
        return offsetMs
    }

    static func reset() {
        lock.lock(); offsetMs = 0; lock.unlock()
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func snapshot(realNow: Date = Date()) -> [String: Any] {
        let real = realNow.timeIntervalSince1970 * 1000
        let offset = debugOffset
        return ["virtualNowEpochMs": real + offset, "offsetMs": offset, "realNowEpochMs": real]
    }

    @discardableResult
    static func apply(_ object: [String: Any], realNow: Date = Date()) throws -> [String: Any] {
        let mode = try ConsoleJSON.string(object, "mode")
        let real = realNow.timeIntervalSince1970 * 1000
        let next: Double
        switch mode {
        case "reset": next = 0
        case "offset", "absolute":
            let amount: Double
            if object[mode == "offset" ? "deltaMs" : "epochMs"] != nil {
                amount = Double(try ConsoleJSON.integer(object, mode == "offset" ? "deltaMs" : "epochMs"))
            } else {
                amount = Double(try ConsoleJSON.integer(object, "dayOffset")) * 86_400_000
            }
            if mode == "offset" { next = debugOffset + amount }
            else { next = object["epochMs"] != nil ? amount - real : amount }
        default: throw ConsoleFailure("mode must be offset|absolute|reset")
        }
        // Foundation/业务 Calendar 的可用范围；拒绝巨大输入溢出后影响课表派生。
        guard next.isFinite, (0...253_402_214_400_000).contains(real + next) else {
            throw ConsoleFailure("virtual time outside supported range")
        }
        lock.lock(); offsetMs = next; lock.unlock()
        NotificationCenter.default.post(name: didChange, object: nil)
        return snapshot(realNow: realNow)
    }
    #endif
}
