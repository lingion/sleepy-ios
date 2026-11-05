#if DEBUG && !WIDGET_EXT && !WATCH_APP
import Foundation
import Network

/// 所有状态和命令在 main queue 串行处理；停用后排队的旧连接不能执行命令。
@MainActor
final class ConsoleListener {
    private final class Client {
        let connection: NWConnection
        var parser = ConsoleHTTPParser()
        var responding = false
        var task: Task<Void, Never>?
        var timeout: DispatchWorkItem?
        let deadline: TimeInterval
        init(_ connection: NWConnection, timeout: TimeInterval) {
            self.connection = connection
            deadline = ProcessInfo.processInfo.systemUptime + timeout
        }
    }

    private var listener: NWListener?
    private var clients: [UUID: Client] = [:]
    private var generation = UUID()
    private let router: ConsoleRouter
    private let requestTimeout: TimeInterval
    var onReady: ((UInt16) -> Void)?
    var onFailure: (() -> Void)?

    init(router: ConsoleRouter, requestTimeout: TimeInterval = 10) {
        self.router = router
        self.requestTimeout = requestTimeout
    }

    deinit {
        listener?.cancel()
        for client in clients.values {
            client.timeout?.cancel()
            client.task?.cancel()
            client.connection.cancel()
        }
    }

    func start(port: UInt16 = 3737) throws {
        stop()
        let parameters = NWParameters.tcp
        // requiredLocalEndpoint 而非单纯 requiredInterfaceType：不能监听 0.0.0.0。
        let endpointPort: NWEndpoint.Port = port == 0 ? .any : NWEndpoint.Port(rawValue: port)!
        // 绑定 127.0.0.1 已把可达面限定为本机回环。不设 acceptLocalOnly: iOS 26
        // 模拟器上它会在 newConnectionHandler 之前拒掉回环连接(客户端 -1005)。
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: endpointPort)
        let next = try NWListener(using: parameters)
        listener = next
        let session = generation
        next.stateUpdateHandler = { [weak self, weak next] state in
            DispatchQueue.main.async {
                guard let self, self.generation == session else { return }
                switch state {
                case .ready:
                    if let port = next?.port { self.onReady?(port.rawValue) }
                case .failed:
                    self.stop()
                    self.onFailure?()
                default: break
                }
            }
        }
        next.newConnectionHandler = { [weak self] connection in
            DispatchQueue.main.async {
                guard let self, self.generation == session, self.clients.count < 8 else {
                    connection.cancel(); return
                }
                self.accept(connection, session: session)
            }
        }
        next.start(queue: .main)
    }

    func stop() {
        generation = UUID()
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        for id in Array(clients.keys) { close(id) }
    }

    private func accept(_ connection: NWConnection, session: UUID) {
        let id = UUID()
        let client = Client(connection, timeout: requestTimeout)
        clients[id] = client
        // 固定总时限，分片到达不续期，避免慢速连接永久占位。
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.generation == session else { return }
            self.close(id)
        }
        client.timeout = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + requestTimeout, execute: deadline)
        connection.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self, self.generation == session else { return }
                switch state {
                case .failed, .cancelled: self.close(id)
                default: break
                }
            }
        }
        connection.start(queue: .main)
        receive(id, session: session)
    }

    private func receive(_ id: UUID, session: UUID) {
        guard let client = clients[id], !client.responding else { return }
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            DispatchQueue.main.async {
                guard let self, self.generation == session, let client = self.clients[id], !client.responding else { return }
                guard ProcessInfo.processInfo.systemUptime < client.deadline else { self.close(id); return }
                do {
                    if let data, let request = try client.parser.append(data) {
                        client.responding = true
                        let paths = self.router.paths
                        client.task = Task { @MainActor [weak self] in
                            guard let self, self.generation == session, !Task.isCancelled else { return }
                            guard let current = self.clients[id], ProcessInfo.processInfo.systemUptime < current.deadline else {
                                self.close(id); return
                            }
                            let response = await self.router.dispatchAsync(request)
                            ConsoleLogStore.shared.recordRequest(request, status: response.status, knownPaths: paths)
                            guard self.generation == session, !Task.isCancelled else { return }
                            self.respond(id, response, session: session)
                        }
                    } else if complete || error != nil {
                        self.close(id)
                    } else {
                        self.receive(id, session: session)
                    }
                } catch let failure as ConsoleFailure {
                    self.respond(id, .error(failure.code, failure.message), session: session)
                } catch {
                    self.respond(id, .error(400, "invalid request"), session: session)
                }
            }
        }
    }

    private func respond(_ id: UUID, _ response: ConsoleResponse, session: UUID) {
        guard let client = clients[id] else { return }
        client.responding = true
        client.connection.send(content: response.wireData, completion: .contentProcessed { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == session else { return }
                self.close(id)
            }
        })
    }

    private func close(_ id: UUID) {
        guard let client = clients.removeValue(forKey: id) else { return }
        client.timeout?.cancel()
        client.task?.cancel()
        client.connection.stateUpdateHandler = nil
        client.connection.cancel()
    }
}
#endif
