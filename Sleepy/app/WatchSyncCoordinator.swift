// WatchSyncCoordinator.swift — iPhone 侧 WCSession 发送端 (2026-10 watch 伴侣 App)
// ← 原版本 WearableListenerService 的 iOS 对位 (sendDataMessage → applicationContext 全量快照)。
//
// 触发面 (对齐既有 refresh 总线, 不新增数据变更钩子):
//   1. repository.onDataChangedHook — 课表任何写入 (导入/编辑/删表) 后 debounce 推送;
//   2. sessionDidBecomeActive / 配对状态转 reachable — 补推 (手机改完表手表离线,
//      重连即拿最新);
//   3. applicationDidBecomeActive 兜底重推 (watchOS 侧补拉失败时的对位);
//   4. 手表 requestContents → 立即回全量 (冷启动补拉)。
//
// applicationContext = "最近意图" 语义, 系统自行送达/重试, 无需 transferFile 队列。

import Foundation
import WatchConnectivity

final class WatchSyncCoordinator: NSObject, WCSessionDelegate {
    static let shared = WatchSyncCoordinator()

    private var debounceTask: Task<Void, Never>?
    private let lock = NSLock()
    /// 仅主 App 激活 (AppDelegate.init 调 start); widget extension 进程不接
    /// (WCSession 在非主 app 进程激活无意义, 且 excludes 已把本目录裁掉)。

    // MARK: - 生命周期

    func start() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    // MARK: - 推送

    /// 数据变更入口 — debounce 1s 合并连续写入 (整表导入=多次 onDataChanged)。
    func scheduleSync() {
        lock.lock(); defer { lock.unlock() }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.syncNow()
        }
    }

    /// 立即组装并发送全量快照。
    func syncNow() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        // 未配对/未装手表 App (watchAppInstalled=false) → 无可投递对象;
        // reachable 只影响即时性, applicationContext 对离线手表也会代存最后一次值,
        // 故仅在「装了 App」时无条件更新上下文 (上表/删表离线也须记账)。
        guard s.isWatchAppInstalled else { return }
        let body = WatchSyncSnapshot.capture(repo: ScheduleRepository(AppDatabase.getShared()))
        var ctx = WatchSyncSnapshot.encodeToApplicationContext(body)
        // applicationContext 上限 256KB; 超限按课程截断 (保表结构完整, 课程留最前列),
        // 记日志可排查。实测全校课表 JSON 几十 KB, 正常不触发。
        if approxSize(ctx) > Self.contextBudget {
            var trimmed = body
            while trimmed.courses.count > 50, approxSize(WatchSyncSnapshot.encodeToApplicationContext(trimmed)) > Self.contextBudget {
                trimmed.courses.removeLast(trimmed.courses.count / 4)
            }
            ctx = WatchSyncSnapshot.encodeToApplicationContext(trimmed)
            WidgetArchiveLog.append(kind: "watchsync", family: "ctx",
                                    result: "oversize courses \(body.courses.count)→\(trimmed.courses.count)")
        }
        try? s.updateApplicationContext(ctx)
    }

    private func approxSize(_ ctx: [String: Any]) -> Int {
        (try? JSONSerialization.data(withJSONObject: ctx).count) ?? 0
    }

    /// applicationContext 软上限 256KB, 留 1/8 余量
    private static let contextBudget = 224 * 1024

    // MARK: - WCSessionDelegate

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // 激活完成即补推一次 (冷启动/重启后手表等最新)
        if activationState == .activated { syncNow() }
    }

    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {
        // 换 paired watch 等场景: 重新 activate 继续服务
        WCSession.default.activate()
    }

    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // 手表冷启动补拉: requestContents → 回全量
        if message[WatchSyncSnapshot.keyRequestContents] as? Bool == true {
            syncNow()
        }
    }

    /// 手表 → iPhone 反向 context: 目前唯一载荷 = 已应用回执 (watchAck = sentAt ms)。
    /// **键分离纪律**: 手机 context 只读 `sync` (手表侧 Receiver 已隐式过滤非
    /// watchAck 键), 手表 context 只读 `watchAck` — 两端各写各键互不覆盖
    /// (updateApplicationContext 是整包替换, 靠各自只处理自家键达成共存)。
    /// 消费: 存 AppPrefs → debounce 补推一次, 快照把 ackSentAt 镜像回手表
    /// (手表设置页「手表已同步」与 iPhone 提醒页同源显示)。
    public func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let ms = context[WatchSyncSnapshot.keyAckPayload] as? Int64, ms > 0 else { return }
        AppPrefs.shared.setWatchAckSentAt(ms)
        scheduleSync()
    }

    /// 手表 → iPhone transferUserInfo 回写通道 (WatchCommand 信封)。
    /// 与 didReceiveApplicationContext 的「最近意图」语义不同: transferUserInfo
    /// 是系统队列保序 + 断连重投, 适合需「每条都到、不丢、不重」的命令。
    /// 幂等: WatchCommandConsumer 按信封 id 去重 — 断连重发的同 id 命令只消费
    /// 一次。V1 仅接通入口 + 去重闸; requestContents/syncAck 仍各走既有通道
    /// (sendMessage / context), 真实命令分派留二期 (决策 2: 编辑只在手机)。
    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let cmd = WatchCommand.from(userInfo: userInfo) else { return }
        guard WatchCommandConsumer.shared.consume(cmd) else { return }  // 重复 id 跳过
        // V1: 信封入口已接通 + 幂等生效; 按 type 分派留二期。
        // 此处仅记录, 不触发任何数据修改 (零编辑纪律)。
        WidgetArchiveLog.append(kind: "watch", family: "cmd",
                                result: "recv \(cmd.type.rawValue) id=\(cmd.id.prefix(8))")
    }

    // MARK: - 可达性 / 配对状态变化

    /// 手表可达性变化 (真实回调名, WCSessionDelegate 协议)。
    public func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { syncNow() }
    }

    /// iPhone 侧配对/安装等手表状态属性变化的合并回调
    /// (sessionWatchStateDidChange — WCSession 无更细分的 install/pairing 事件):
    /// unpaired→paired、手表 App 装/卸都会到这里, 一律补推 (isWatchAppInstalled
    /// 守卫在 syncNow 内)。
    public func sessionWatchStateDidChange(_ session: WCSession) {
        syncNow()
    }
}
