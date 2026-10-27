// WatchSyncReceiver.swift — 手表侧 WCSession 接收端 (2026-10 watch 伴侣 App)
// applicationContext 到达 → 解码全量快照 → WatchStore.applySnapshot 重建镜像。
// 冷启动亦回调本 delegate (系统代存的最后载荷) — 离线重连自动追平, 无轮询。

import Foundation
import WatchConnectivity

final class WatchSyncReceiver: NSObject, WCSessionDelegate {
    static let shared = WatchSyncReceiver()

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // 激活完成即消费已代存上下文 + 主动补拉一次 (iPhone 在跑则秒回)
        ingest(session.applicationContext)
        if activationState == .activated {
            Task { @MainActor in WatchStore.shared.requestSync() }
        }
    }

    func session(_ session: WCSession, didUpdateApplicationContext context: [String: Any]) {
        ingest(context)
    }

    /// 载荷 → apply; 非本契约格式 (旧版/空) 直接忽略。
    /// 旧载荷防御: sentAt 早于已应用值 → 丢弃 (系统重放/乱序)。
    private func ingest(_ context: [String: Any]) {
        guard let body = WatchSyncSnapshot.decode(from: context) else { return }
        Task { @MainActor in
            if let last = WatchStore.shared.lastSyncDate,
               body.sentAt > 0, Int64(last.timeIntervalSince1970 * 1000) >= body.sentAt {
                return
            }
            WatchStore.shared.applySnapshot(body)
        }
    }
}
