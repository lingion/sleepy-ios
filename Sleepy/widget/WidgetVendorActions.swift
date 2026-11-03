// WidgetVendorActions.swift — ← widget/WidgetVendorActions.kt
//
// OEM widget broadcasts that are public compatibility extensions of AppWidget.
//
// ★ 平台差异: iOS WidgetKit 没有 OEM 厂商品牌广播(只有 reloadTimelines 标准通道)。
//   本文件作为 1:1 对位保留文档契约, 接收动作 = WidgetCenter.shared.reloadAllTimelines
//   (等价 原 dispatchXiaomiUpdate → onUpdate 重渲染管线)。未来若遇到厂商私有
//   行为不一致, 改动点集中在此。
//
// 原版本 原文: XIAOMI_UPDATE_ACTION = "miui.appwidget.action.APPWIDGET_UPDATE"
// → onUpdate(context, AppWidgetManager, ids) 重用同一渲染管线, 不引入厂商品牌渲染器。

import Foundation
import WidgetKit

enum WidgetVendorActions {

    /// MIUI/HyperOS widget 重绘广播(在 原版本 同名常量)。
    static let XIAOMI_UPDATE_ACTION = "miui.appwidget.action.APPWIDGET_UPDATE"

    /// 重用标准刷新管线: 通知 WidgetKit 全量重载 (dispatchXiaomiUpdate → onUpdate)。
    /// 厂商品牌无 iOS 等价私有协议,降级为统一 reloadAllTimelines。
    static func dispatchXiaomiUpdate() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
