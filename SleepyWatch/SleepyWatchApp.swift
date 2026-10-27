// SleepyWatchApp.swift — Sleepy watchOS 伴侣 App 入口 (2026-10)。
// 职责: WCSession 激活 + 镜像库启动接线 + UN delegate 注册 (通知到货重查复用共享实现)。
// 数据通道: iPhone 经 applicationContext 推全量快照 (WatchSyncCoordinator),
// 手表 WatchSyncReceiver 收到 → WatchStore 全量重建本地 GRDB 镜像 + prefs 落盘
// — 载荷是唯一真源, 手表只读镜像 + 本地调度通知, 不反向写。
//
// 共享源复用: Sleepy/data + util + theme + widget(通知/纯计算层) + sync/契约
// 经 project.yml excludes 直接编进本 target (同 SleepyWidget 手法);
// 本目录只放 watch-only 层 (入口/Store/视图/接收端)。

import SwiftUI
import UserNotifications
import WatchConnectivity

@main
struct SleepyWatchApp: App {
    @StateObject private var store = WatchStore.shared

    init() {
        // ← AppDelegate 职责对位: WCSession 激活 (接收端回调含冷启动代存载荷)
        WCSession.default.delegate = WatchSyncReceiver.shared
        WCSession.default.activate()
        // 通知到货重查/00:05 载体 delegate = 共享 SleepyNotificationDelegate
        // (仅依赖 UN + AppPrefs; DND/BGTask 分支已按 WATCH_APP 裁掉)。
        UNUserNotificationCenter.current().delegate = SleepyNotificationDelegate.shared
        // 调度器 repo 接线 (delegate 到货 handleDailyResync 冷启动即需,
        // 不等首次 applySnapshot)
        store.prepareScheduler()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(store)
        }
    }
}
