// ← WakeUpShareClient.kt / 拾光 GLOBAL_TOOLS/wake_up.js (GPL-3.0)
import Foundation

struct WakeUpShareHTTPResponse {
    let status: Int
    let body: Data
}

/// 测试注入点; fixture transport 必须完全替代真实网络。
protocol WakeUpShareTransport {
    func send(_ request: URLRequest) async throws -> WakeUpShareHTTPResponse
}

final class WakeUpShareURLSessionTransport: WakeUpShareTransport {
    static let maximumResponseBytes = 4 * 1024 * 1024
    private let session: URLSession
    private let ownsSession: Bool

    init(session: URLSession? = nil) {
        ownsSession = session == nil
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 15
            config.httpShouldSetCookies = false
            config.urlCache = nil
            self.session = URLSession(configuration: config, delegate: WakeUpShareRedirectPolicy(), delegateQueue: nil)
        }
    }

    deinit { if ownsSession { session.invalidateAndCancel() } }

    func send(_ request: URLRequest) async throws -> WakeUpShareHTTPResponse {
        try Task.checkCancellation()
        // async bytes 支持 Task 取消, 并在接收阶段限制响应大小。
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else { throw WakeUpShareError.invalidResponse }
        guard (200...299).contains(response.statusCode) else { throw WakeUpShareError.http(response.statusCode) }
        guard response.expectedContentLength <= Int64(Self.maximumResponseBytes) else { throw WakeUpShareError.responseTooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < Self.maximumResponseBytes else { throw WakeUpShareError.responseTooLarge }
            if data.count % 65536 == 0 { try Task.checkCancellation() }
            data.append(byte)
        }
        try Task.checkCancellation()
        return WakeUpShareHTTPResponse(status: response.statusCode, body: data)
    }
}

private final class WakeUpShareRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        let allowed = request.url?.scheme == "https" && request.url?.host == "api.wakeup.fun"
        completionHandler(allowed ? request : nil)
    }
}

/// 网络只获取 shareData, 不修改本地课表。请求 body/口令/token/签名不记日志。
struct WakeUpShareClient {
    private let transport: WakeUpShareTransport
    private let nowMs: () -> Int64
    private let random: () -> String

    init(transport: WakeUpShareTransport = WakeUpShareURLSessionTransport(),
         nowMs: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
         random: @escaping () -> String = { WakeUpShareProtocol.generateRand10() }) {
        self.transport = transport
        self.nowMs = nowMs
        self.random = random
    }

    static func looksLikeShareCode(_ text: String) -> Bool { WakeUpShareProtocol.looksLikeShareCode(text) }

    func fetchScheduleJson(_ input: String, device: WakeUpShareProtocol.Device = .init()) async throws -> String {
        let raw = try await fetchRawShareData(input, device: device)
        try Task.checkCancellation()
        return try WakeUpShareProtocol.buildScheduleJson(WakeUpShareProtocol.parseRawScheduleData(raw))
    }

    func fetchRawShareData(_ input: String, device: WakeUpShareProtocol.Device = .init()) async throws -> String {
        try Task.checkCancellation()
        let code = try WakeUpShareProtocol.validatedKey(input)
        let nonce = random()
        let signA = try WakeUpShareProtocol.makeSignA(cuid: device.cuid, rand10: nonce)
        let antispam = try await post(path: WakeUpShareProtocol.V6170.antispamPath,
                                      body: WakeUpShareProtocol.antispamBody(signA: signA, device: device), device: device)
        try Task.checkCancellation()
        guard let signB = WakeUpShareProtocol.extractSignB(antispam) else { throw WakeUpShareError.missingSignature }
        let token = try WakeUpShareProtocol.tokenFromSignB(signB, rand10: nonce)
        let share = try WakeUpShareProtocol.buildShareRequest(code: code, token: token, device: device, nowMs: nowMs())
        let response = try await post(path: WakeUpShareProtocol.V6170.sharePath, body: share.body, device: device)
        try Task.checkCancellation()
        return try WakeUpShareProtocol.decodeSharePayload(response, rc4Key: share.rc4Key)
    }

    private func post(path: String, body: String, device: WakeUpShareProtocol.Device) async throws -> [String: Any] {
        guard let url = URL(string: WakeUpShareProtocol.V6170.host + path) else { throw WakeUpShareError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("wakeup", forHTTPHeaderField: "na__zyb_source__")
        request.setValue(device.cuid, forHTTPHeaderField: "zyb-cuid")
        request.setValue(device.adid, forHTTPHeaderField: "zyb-adid")
        if !device.did.isEmpty { request.setValue(device.did, forHTTPHeaderField: "zyb-did") }
        let response: WakeUpShareHTTPResponse
        do { response = try await transport.send(request) }
        catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw error
        }
        try Task.checkCancellation()
        guard (200...299).contains(response.status) else { throw WakeUpShareError.http(response.status) }
        guard response.body.count <= WakeUpShareURLSessionTransport.maximumResponseBytes else { throw WakeUpShareError.responseTooLarge }
        guard let json = try? JSONSerialization.jsonObject(with: response.body),
              let root = json as? [String: Any] else { throw WakeUpShareError.invalidResponse }
        // 非零业务错误不能被 200 或残留 data 当成成功。
        if let code = WakeUpShareProtocol.int(root["errNo"]), code != 0 { throw WakeUpShareError.service(code) }
        return root
    }
}
