// BatterySettingsLauncher.swift — ← widget/notification/BatteryOptimizationIntents.kt
// iOS 适配说明:
//   原版本 版是厂商省电页候选链(MIUI PowerKeeper/Huawei SystemManager/
//   ColorOS AppDetail/...)逐个 try-launch — iOS 无厂商省电页生态,
//   唯一系统入口是 app 自身设置页(含"后台 App 刷新"跳转提示)。
//
// 契约保留: launchBatterySettings() → Bool(命中返回 true, 调用方据此反馈)。
// 本文件从 widget extension target 排除(project.yml excludes —
// UIApplication.shared 在 extension 里编译报错, Swift 无 per-target 旗标)。

import Foundation
import UIKit

enum BatterySettingsLauncher {
    /// 打开本 app 的系统设置页(通知/后台刷新/电池都在此)。
    /// 主线程调用; 返回是否成功发起跳转。
    @MainActor
    static func launchBatterySettings() -> Bool {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return false }
        guard UIApplication.shared.canOpenURL(url) else { return false }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return true
    }
}
