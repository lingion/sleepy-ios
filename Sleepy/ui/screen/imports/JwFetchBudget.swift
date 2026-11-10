import Foundation

final class JwFetchBudget {
    private let now: () -> TimeInterval
    private(set) var captureId: String?
    private var remaining: TimeInterval = 0
    private var runningSince: TimeInterval?
    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) { self.now = now }
    func begin(id: String, timeout: TimeInterval) {
        precondition(timeout > 0)
        captureId = id; remaining = timeout; runningSince = now()
    }
    func remainingSeconds(id: String) -> TimeInterval? {
        guard captureId == id, let started = runningSince else { return nil }
        return max(0, remaining - max(0, now() - started))
    }
    func setWaiting(id: String, waiting: Bool) {
        guard captureId == id else { return }
        if waiting && runningSince != nil { remaining = remainingSeconds(id: id) ?? remaining; runningSince = nil }
        else if !waiting && runningSince == nil { runningSince = now() }
    }
    @discardableResult func complete(id: String) -> Bool {
        guard captureId == id else { return false }; cancel(); return true
    }
    func cancel() { captureId = nil; runningSince = nil; remaining = 0 }
}

func scopeJwFetchScript(_ script: String, captureId: String) -> String {
    let quoted = (try? JwSgSourceMetadata.stringify([captureId])).map { String($0.dropFirst().dropLast()) } ?? "\"\""
    return """
    (function(__sleepyNativeBridge){
      var __sleepyCaptureBridge={postMessage:function(message){
        var payload;
        try{payload=JSON.parse(message.json);}catch(e){payload={ok:false,err:'教务响应格式无效'};}
        if(!payload||typeof payload!=='object'||Array.isArray(payload))payload={ok:false,err:'教务响应格式无效'};
        payload.captureId=\(quoted);
        __sleepyNativeBridge.postMessage({json:JSON.stringify(payload)});
      }};
      \(script.replacingOccurrences(of: "window.webkit.messageHandlers.__sleepyBridge", with: "__sleepyCaptureBridge"))
    })(window.webkit.messageHandlers.__sleepyBridge);
    """
}
