// HueSlider.swift — ← ui/component/ColorPickerDialog.kt 的 internal fun HueSlider
// 360° 彩虹水平色相条。
//
// 与 Android 的差异(平台差异表「自绘控件」类):
//   Android 用 Compose Canvas 画渐变 + 两个 Circle 指示器;
//   iOS 用 LinearGradient(7 段色标同 Android 的 0/60/120/180/240/300/360)
//   + SwiftUI 圆形指示器, 交互用 DragGesture(minimumDistance:0) 一次覆盖
//   「拖动」与「点按」两条通道 —— iOS 的 minimumDistance:0 让点按也走同一手势,
//   无需 Android 那套 detectDragGestures + detectTapGestures 双通道。
//
// 语义对齐(Android 注释原文):
//   - onHueChange 逐帧回调(拖动跟手)
//   - onHueCommit 松手/点按各回调一次 —— 供「拖动只动本地值, 松手才落库重算」的
//     调用方(外观页课程配色种子)节流; 默认空实现。
//   - 拖动未超过 touch slop 时 Android 的 detectDragGestures 不触发(点按走 tap 通道);
//     iOS 侧 minimumDistance:0 下点按直接触发 change, 与 Android 点按结果一致。

import SwiftUI

struct HueSlider: View {
    /// 当前色相 0..360
    let hue: Float
    /// 拖动跟手回调(逐帧)
    let onHueChange: (Float) -> Void
    /// 松手/点按提交回调(一次)
    var onHueCommit: (Float) -> Void = { _ in }

    /// Android 7 段色标(HSV(0/60/120/180/240/300/360, 1, 1))
    private static let stops: [Color] = [0, 60, 120, 180, 240, 300, 360].map { h in
        Color(hue: Double(h) / 360.0, saturation: 1.0, brightness: 1.0)
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let clamped = ((hue.truncatingRemainder(dividingBy: 360)) + 360)
                .truncatingRemainder(dividingBy: 360)
            let cx = CGFloat(clamped / 360.0) * width

            ZStack {
                LinearGradient(gradient: Gradient(colors: Self.stops),
                               startPoint: .leading, endPoint: .trailing)
                // 指示器 — Android drawCircle(白 r=10) + drawCircle(当前色 r=8)
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .position(x: cx, y: geo.size.height / 2)
                Circle()
                    .fill(Color(hue: Double(clamped) / 360.0, saturation: 1.0, brightness: 1.0))
                    .frame(width: 16, height: 16)
                    .position(x: cx, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = min(max(value.location.x / width, 0), 1)
                        onHueChange(Float(x * 360))
                    }
                    .onEnded { value in
                        let x = min(max(value.location.x / width, 0), 1)
                        onHueCommit(Float(x * 360))
                    }
            )
        }
        .accessibilityIdentifier("hue_slider")
        .accessibilityLabel(L10n.format("course_color_seed_label"))
        .accessibilityValue("\(Int(hue.rounded()))°")
    }
}
