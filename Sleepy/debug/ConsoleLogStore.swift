#if DEBUG && !WIDGET_EXT && !WATCH_APP
import Foundation

/// 双内存环。app 记录已接入的原生控制台业务事件，不冒充 NSLog/系统日志全集。
@MainActor
final class ConsoleLogStore {
    static let shared = ConsoleLogStore()
    private let capacity: Int
    private var app: [[String: Any]] = []
    private var audit: [[String: Any]] = []
    init(capacity: Int = 200) { self.capacity = max(1, capacity) }

    enum Event: String {
        case started = "listener ready", stopped = "listener stopped", failed = "listener failed"
        case dataChanged = "repository operation completed", prefsChanged = "preferences applied"
        case clockChanged = "business clock changed", trigger = "native trigger completed"
        case catalog = "catalog override saved", mock = "mock rules changed", reset = "session reset completed"
    }

    func record(_ event: Event) {
        app.append(["level": event == .failed ? "E" : "I", "tag": "SleepyConsole",
                    "message": event.rawValue, "epochMs": Int64(Date().timeIntervalSince1970 * 1000)])
        if app.count > capacity { app.removeFirst(app.count - capacity) }
    }

    func recordRequest(_ request: ConsoleRequest, status: Int, knownPaths: [String]) {
        // 不记录 token（连后四位也省略）、body、query 或未知路径里的任意用户输入。
        audit.append(["kind": "audit", "ts": Int64(Date().timeIntervalSince1970 * 1000),
                      "method": request.method, "path": knownPaths.contains(request.path) ? request.path : "[unknown]",
                      "code": status, "ok": (200...299).contains(status)])
        if audit.count > capacity { audit.removeFirst(audit.count - capacity) }
    }

    func snapshot(limit: Int? = nil) -> [String: Any] {
        let count = limit.flatMap { $0 > 0 ? min($0, capacity) : nil } ?? capacity
        return ["app": Array(app.suffix(count)), "audit": Array(audit.suffix(count)),
                "appScope": "instrumented console lifecycle/data/clock/trigger events; not all NSLog"]
    }
}
#endif
