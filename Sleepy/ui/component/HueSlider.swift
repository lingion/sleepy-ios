// HueSlider.swift — ← ui/component/ColorPickerDialog.kt HueSlider (v1.0.62 B1)
//
// 色相滑条：360° 彩虹水平条。
//   onHueChange 逐帧回调(拖动跟手), onHueCommit 松手/点按各回调一次 —
//   供「拖动只动本地值, 松手才落库重算」的调用方(外观页课程配色种子)节流。
//
//   initialHue 幽灵 (spec §3.1 色相变体):
//     拖离基线 (调用点传打开/进编辑区时刻的色相, nil = 不接) → 基线刻度出现一条细条;
//     拖回基线 → 消失。纯装饰。

import SwiftUI

struct HueSlider: View {
    let hue: Float
    let onHueChange: (Float) -> Void
    var onHueCommit: (Float) -> Void = { _ in }
    var initialHue: Float? = nil

    private var rainbow: LinearGradient {
        LinearGradient(
            stops: stride(from: 0, through: 360, by: 60).map {
                .init(color: Color(hue: Double($0) / 360, saturation: 1, brightness: 1),
                      location: Double($0) / 360)
            },
            startPoint: .leading, endPoint: .trailing
        )
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let clamped = min(max(hue, 0), 360)
            let knobX = w * CGFloat(clamped / 360)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: SleepyShapes.large)
                    .fill(rainbow)

                // 幽灵基线
                if let baseline = initialHue, abs(baseline - clamped) > 0.5 {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white)
                        .frame(width: 2)
                        .overlay(RoundedRectangle(cornerRadius: 1).stroke(Color.black.opacity(0.5), lineWidth: 1))
                        .offset(x: w * CGFloat(min(max(baseline, 0), 360) / 360) - 1)
                }

                // 滑块
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
                    .shadow(radius: 1)
                    .offset(x: knobX - 10)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = min(max(value.location.x / w, 0), 1)
                        onHueChange(Float(x) * 360)
                    }
                    .onEnded { value in
                        let x = min(max(value.location.x / w, 0), 1)
                        onHueCommit(Float(x) * 360)
                    }
            )
        }
    }
}
