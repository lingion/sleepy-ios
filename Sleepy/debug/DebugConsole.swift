#if DEBUG && !WIDGET_EXT && !WATCH_APP
import Combine
import UIKit
import SwiftUI

/// AppDelegate 持有一个实例。Debug 自动 start；后台暂停，用户 stop 后前台也不复活。
@MainActor
final class DebugConsole: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var status = "已停用"
    @Published private(set) var listening = false
    private let router = ConsoleRouter()
    private lazy var listener = ConsoleListener(router: router)
    private let data: ConsoleDataHandlers
    private let ui: ConsoleUIHandlers
    private let triggers: ConsoleTriggerHandlers
    private let clockDidChange: () -> Void
    private let catalogConsumerWired: Bool
    private let nativeMockConsumerWired: Bool
    private var observers: [NSObjectProtocol] = []
    private var starting = false

    /// 两个教务开关只有在对应消费者补丁已接入时传 true；缺省不接受没有消费方的写命令。
    init(repository: ScheduleRepository, root: AppRootViewModel, clockDidChange: (() -> Void)? = nil,
         catalogConsumerWired: Bool = false, nativeMockConsumerWired: Bool = false) {
        data = ConsoleDataHandlers(repository: repository)
        ui = ConsoleUIHandlers(root: root)
        triggers = ConsoleTriggerHandlers(repository: repository, data: data)
        self.catalogConsumerWired = catalogConsumerWired
        self.nativeMockConsumerWired = nativeMockConsumerWired
        self.clockDidChange = clockDidChange ?? { [weak root] in
            root?.scheduleViewModel.recalculateWeekDisplay()
            root?.scheduleViewModel.objectWillChange.send()
            root?.objectWillChange.send()
        }
        listener.onReady = { [weak self] port in
            self?.starting = false
            self?.listening = true
            self?.status = "127.0.0.1:\(port)"
            ConsoleLogStore.shared.record(.started)
        }
        listener.onFailure = { [weak self] in
            guard let self else { return }
            self.router.stop()
            self.starting = false
            self.listening = false
            self.enabled = false
            AppClock.reset()
            self.clockDidChange()
            ConsoleCatalogStore.shared.setActive(false)
            ConsoleJWMockStore.shared.setActive(false)
            ConsoleLogStore.shared.record(.failed)
            self.status = "监听失败（端口可能已占用）"
        }
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.suspend() }
            })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.enabled, !self.listening else { return }
                    self.resume()
                }
            })
    }

    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }

    func start() {
        guard !enabled else { return }
        enabled = true
        if UIApplication.shared.applicationState == .background { status = "后台暂停" }
        else { resume() }
    }

    func stop() {
        enabled = false
        suspend()
        status = "已停用"
    }

    private func suspend() {
        listener.stop()
        router.stop()
        starting = false
        listening = false
        AppClock.reset()
        clockDidChange()
        ConsoleCatalogStore.shared.setActive(false)
        ConsoleJWMockStore.shared.setActive(false)
        ConsoleLogStore.shared.record(.stopped)
        status = enabled ? "后台暂停" : "已停用"
    }

    private func resume() {
        guard enabled, !starting, !listening else { return }
        starting = true
        listener.stop()
        router.stop()
        ConsoleCatalogStore.shared.setActive(catalogConsumerWired)
        ConsoleJWMockStore.shared.setActive(nativeMockConsumerWired)
        installRoutes()
        do {
            _ = try router.tokens.issue()
            router.active = true
            status = "正在监听…"
            try listener.start()
        } catch {
            router.stop()
            starting = false
            enabled = false
            listening = false
            ConsoleCatalogStore.shared.setActive(false)
            ConsoleJWMockStore.shared.setActive(false)
            ConsoleLogStore.shared.record(.failed)
            status = "监听失败"
        }
    }

    private func installRoutes() {
        router.register("POST", "/v1/hello") { [weak self] _ in
            guard let self else { throw ConsoleFailure(503, "console stopped") }
            return ["paths": self.router.paths, "debugBuild": true, "unlocked": false,
                    "active": self.router.active, "token": try self.router.tokens.issue(),
                    "platform": "ios", "capabilities": [
                        "clock": true, "nativeAccessibility": true,
                        "navigate": true, "coordinateGestures": false, "systemKeys": false,
                        "catalogOverride": self.catalogConsumerWired, "jwMock": false,
                        "jwMockNativeHTTP": self.nativeMockConsumerWired, "log": true,
                        "triggerTypes": ConsoleTriggerHandlers.supported,
                        "unsupportedTriggerTypes": ConsoleTriggerHandlers.unsupported]] as [String: Any]
        }
        router.register("POST", "/v1/enable") { request in
            _ = try ConsoleJSON.string(request.object(), "passphrase")
            return ["result": "ALREADY_ACTIVE"]
        }
        router.register("GET", "/v1/clock") { _ in AppClock.snapshot() }
        router.register("POST", "/v1/clock") { [weak self] request in
            guard let self else { throw ConsoleFailure(503, "console stopped") }
            let result = try AppClock.apply(request.object())
            self.clockDidChange()
            ConsoleLogStore.shared.record(.clockChanged)
            return result
        }
        router.register("POST", "/v1/session/reset") { [weak self] _ in
            guard let self else { throw ConsoleFailure(503, "console stopped") }
            try ConsoleCatalogStore.shared.clear()
            try ConsoleJWMockStore.shared.clear()
            var result = try self.data.resetSession() as! [String: Any]
            result["catalogCleared"] = true
            result["mockRulesCleared"] = true
            self.clockDidChange()
            ConsoleLogStore.shared.record(.reset)
            return result
        }
        router.register("GET", "/v1/log") { request in
            ConsoleLogStore.shared.snapshot(limit: request.query["limit"].flatMap(Int.init))
        }
        router.registerAsync("POST", "/v1/trigger") { [weak self] request in
            guard let self else { throw ConsoleFailure(503, "console stopped") }
            return try await self.triggers.handle(request.object())
        }
        router.register("GET", "/v1/jw/mock") { [weak self] _ in
            ["rules": ConsoleJWMockStore.shared.list().map(\.json),
             "replayScope": self?.nativeMockConsumerWired == true ? "UcasDetailFetch only" : "unwired",
             "webViewHTTPIntercept": false] as [String: Any]
        }
        router.register("POST", "/v1/jw/mock") { [weak self] request in
            guard self?.nativeMockConsumerWired == true else { throw ConsoleFailure(501, "native HTTP mock consumer not wired") }
            let result = try ConsoleJWMockStore.shared.put(request.object())
            ConsoleLogStore.shared.record(.mock)
            return result
        }
        router.register("DELETE", "/v1/jw/mock") { request in
            let result = try ConsoleJWMockStore.shared.delete(request.object())
            ConsoleLogStore.shared.record(.mock)
            return result
        }
        data.install(on: router, catalogConsumerWired: catalogConsumerWired)
        ui.install(on: router)
    }
}

/// GeneralSettingsScreen 在 #if DEBUG 下放入此 Section；状态来自实际 listener.ready。
@MainActor
struct DebugConsoleSettingsSection: View {
    @ObservedObject var console: DebugConsole

    var body: some View {
        Section(header: Text("Debug Console")) {
            Toggle("启用本机调试控制台", isOn: Binding(get: { console.enabled }, set: { enabled in
                if enabled { console.start() } else { console.stop() }
            }))
            Text(console.status).font(.caption).foregroundColor(.secondary)
            if console.listening {
                Text("仅回环地址。POST /v1/hello 获取本次内存 token；后台暂停会撤销 token。")
                    .font(.caption)
            }
        }
    }
}
#endif
