// GlobalWidgetCompatibility.swift — ← widget/GlobalWidgetCompatibility.kt
//
// APK-side compatibility boundary for 原 launchers worldwide.
//
// Every 原版本-compatible vendor in this registry consumes the public
// AppWidget provider contract. Private negative-one-screen cards are recorded
// as platform-bound capabilities, not guessed manifest extensions.
//
// ★ 平台差异: 本枚举是 原版本 启动器全量表, iOS WidgetKit 仅走系统标准通道,无
//   厂商私有协议分流。逐项保留供管理页/诊断页未来扩展;UI 端不消费此表。
//   WidgetManagementScreen 仅 1:1 显示 kind + family 列表, 启动器等级概念由
//   WidgetVendorActions (← .miui.appwidget.action.APPWIDGET_UPDATE) 兜底。

import Foundation

enum WidgetIntegrationTier {
    case standardAppWidget
    case publicVendorExtension
    case platformBound
}

struct GlobalWidgetVendor {
    let id: String
    let displayName: String
    let tier: WidgetIntegrationTier
    let standardAppWidgetSupported: Bool
    let privateSurface: String?
}

let globalWidgetVendors: [GlobalWidgetVendor] = [
    GlobalWidgetVendor(id: "google", displayName: "Google Pixel / AOSP", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "samsung", displayName: "Samsung Galaxy / One UI", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "sony", displayName: "Sony Xperia", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "motorola", displayName: "Motorola / Lenovo", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "asus", displayName: "ASUS Zenfone / ROG", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "nothing", displayName: "Nothing", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "hmd", displayName: "HMD / Nokia", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "tecno", displayName: "TECNO", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "infinix", displayName: "Infinix", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "itel", displayName: "itel", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "zte", displayName: "ZTE", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "tcl", displayName: "TCL", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "sharp", displayName: "Sharp", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "fujitsu", displayName: "Fujitsu", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "panasonic", displayName: "Panasonic", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "kyocera", displayName: "Kyocera", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "cat", displayName: "CAT", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "unihertz", displayName: "Unihertz", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "doogee", displayName: "DOOGEE", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "ulefone", displayName: "Ulefone", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "blackview", displayName: "Blackview", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "vivo", displayName: "vivo / OriginOS", tier: .publicVendorExtension, standardAppWidgetSupported: true, privateSurface: "OriginOS atomic component review"),
    GlobalWidgetVendor(id: "xiaomi", displayName: "Xiaomi / HyperOS", tier: .publicVendorExtension, standardAppWidgetSupported: true, privateSurface: "AppVault exposure and store review"),
    GlobalWidgetVendor(id: "oppo", displayName: "OPPO / ColorOS", tier: .platformBound, standardAppWidgetSupported: true, privateSurface: "Pantanal / UPK authorization"),
    GlobalWidgetVendor(id: "honor", displayName: "HONOR / MagicOS", tier: .platformBound, standardAppWidgetSupported: true, privateSurface: "YOYO / MagicOS card authorization"),
    GlobalWidgetVendor(id: "huawei", displayName: "Huawei EMUI", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: nil),
    GlobalWidgetVendor(id: "harmonyos-next", displayName: "Huawei HarmonyOS NEXT", tier: .platformBound, standardAppWidgetSupported: false, privateSurface: "Native service card HAP / ArkTS"),
    GlobalWidgetVendor(id: "meizu", displayName: "Meizu / Flyme", tier: .standardAppWidget, standardAppWidgetSupported: true, privateSurface: "No public Aicy card protocol"),
    GlobalWidgetVendor(id: "snapdragon-spaces", displayName: "Qualcomm Snapdragon Spaces", tier: .platformBound, standardAppWidgetSupported: false, privateSurface: "Separate XR platform")
]

/// ← standardWidgetVendors(): 仅 standardAppWidgetSupported = true 列表
func standardWidgetVendors() -> [GlobalWidgetVendor] {
    globalWidgetVendors.filter { $0.standardAppWidgetSupported }
}
