import SwiftUI

// NoRippleClickable — 原版本 ui/theme/NoRippleClickable.kt → iOS 映射记录.
//
// 原版本 侧: 全 app 自定义可点面 (Box/Row/Text 上的 clickable) 唯一入口 —
// noRippleClickable / noRippleClickable(enabled:) 两个 Modifier 扩展,
// clickable(interactionSource = remember{}, indication = null) 去涟漪.
// 视觉策略: 自定义表面不渲染涟漪, 涟漪反馈只保留给 M3 标准组件.
//
// iOS 映射 (SwiftUI 本身无 ripple 概念, 本文件为记录映射, 无实现缺口):
//
//   原版本                                iOS 等价
//   ─────────────────────────────────────────────────────
//   noRippleClickable { onClick }          Button(action:) 默认即无涟漪;
//                                          自定义表面一律用 Button / .onTapGesture,
//                                          🚫 自造点击修饰符
//   noRippleClickable(enabled: x) { ... }  Button(...).disabled(!x)
//                                          (禁用态不响应点击, 语义 1:1)
//   "自定义表面不渲染涟漪" 视觉策略          成立 — SwiftUI 原生点击无视觉涟漪反馈,
//                                          该策略在 iOS 侧为天然满足, 无需实现

/// 禁用门控点击 — 原版本 noRippleClickable(enabled:) 的 iOS 等价语义速记.
/// 现状: 全 app 点击面已走 Button/.onTapGesture, 本扩展仅作映射锚点, 无需调用.
extension View {
    /// 对应 原版本 Modifier.noRippleClickable(enabled:enabled, onClick:) —
    /// 禁用时不响应点击 (= .disabled 语义).
    func noRippleClickable(_ enabled: Bool, perform action: @escaping () -> Void) -> some View {
        Button(action: action) {
            self
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// 对应 原版本 Modifier.noRippleClickable(onClick:) — 常使能变体.
    func noRippleClickable(perform action: @escaping () -> Void) -> some View {
        noRippleClickable(true, perform: action)
    }
}
