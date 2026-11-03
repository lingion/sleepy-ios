// BatteryOptimizationIntents.swift — ← BatteryOptimizationIntents.kt
// 电池/后台管理引导入口。原版本: 厂商耗电页(MIUI/HW/HONOR/OPPO/vivo 组件名, 社区逆向证据 B)
// → "忽略电池优化"弹窗 → 原生列表页, 逐个 try-launch。
//
// 平台映射(no-analog 记录, 禁止 silent skip):
// - iOS 单一系统厂商, 不存在厂商定制省电页 → vendorBatterySpecs 逐厂商候选表整体 no-analog
// - ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS / ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
//   → iOS 无电池优化白名单机制 → no-analog
// - iOS 等价引导 = 唯一候选: 本 App 系统设置页(UIApplication.openSettingsURLString),
//   用户可在其中管理通知/后台刷新; 原 launchBatterySettings 的 Boolean 返回语义保留:
//   canOpenURL 失败 = false(调用方静默放弃, 对齐 原版本 全败落空)

// 注: 本文件同时被 Sleepy(app) 与 SleepyWidget(extension) 共源编译,
//     UIApplication.shared/open 仅限 app 进程, 用 APPLICATION_EXTENSION_API_ONLY 区分。

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum BatteryOptimizationIntents {
    /// 本 App 系统设置页 URL(唯一候选, ≙ vendorBatterySpecs().first)
    static func appSettingsURL() -> URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    /// ← launchBatterySettings(context): 打开设置页; opener 可注入供单测/扩展复用
    @discardableResult
    static func openAppSettings(opener: ((URL) -> Void)? = nil) -> Bool {
        guard let url = appSettingsURL() else { return false }
        if let opener {
            opener(url)
            return true
        }
        #if WIDGET_EXT
        return false // widget 扩展进程无 URL 打开能力(平台事实, 非 silent skip)
        #else
        guard UIApplication.shared.canOpenURL(url) else { return false }
        UIApplication.shared.open(url)
        return true
        #endif
    }
}
