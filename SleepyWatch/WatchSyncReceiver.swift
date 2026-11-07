// WatchSyncReceiver.swift — 手表侧 WCSession 接收端 (2026-10 watch 伴侣 App)
// applicationContext 到达 → 解码全量快照 → WatchStore.applySnapshot 重建镜像。
// 冷启动亦回调本 delegate (系统代存的最后载荷) — 离线重连自动追平, 无轮询。

import Foundation
import WatchConnectivity

final class WatchSyncReceiver: NSObject, WCSessionDelegate {
    static let shared = WatchSyncReceiver()

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // 激活完成即消费已代存上下文 + 主动补拉一次 (iPhone 在跑则秒回)
        ingest(session.receivedApplicationContext, fromDelegate: false)
        if activationState == .activated {
            Task { @MainActor in WatchStore.shared.requestSync() }
        }
    }

    // 回调名必须是 didReceiveApplicationContext — WCSessionDelegate 协议里没有
    // didUpdateApplicationContext; 签名不匹配时系统记「does not implement」并丢弃推送 (模拟器实测发现)。
    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        ingest(context, fromDelegate: true)
    }

    /// 载荷 → apply; 非本契约格式 (旧版/空) 直接忽略。
    /// 旧载荷防御 (sentAt 早于已应用值 → 丢弃) 只用于代存/补拉路径:
    /// delegate 回调是系统刚送达的推送, 语义上即最新; 若对它去重, 重发相同 payload
    /// (delegate 不触发) + 重启应用 (仅走代存路径) 的组合会把合法更新静默吞掉。
    private func ingest(_ context: [String: Any], fromDelegate: Bool) {
        guard let body = WatchSyncSnapshot.decode(from: context) else { return }
        Task { @MainActor in
            if !fromDelegate,
               let last = WatchStore.shared.lastSyncDate,
               body.sentAt > 0, Int64(last.timeIntervalSince1970 * 1000) >= body.sentAt {
                return
            }
            WatchStore.shared.applySnapshot(body)
        }
    }
}
