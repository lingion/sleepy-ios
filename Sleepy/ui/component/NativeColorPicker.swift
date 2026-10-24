// NativeColorPicker.swift — ← ColorPickerDialog HSV 自制色盘
// 原生化: 用 UIColorPickerViewController (iOS 14+) 替代 AddCourseScreen 自制 HSV 色盘。
// iOS 14+ 原生控件:完整色盘 + EyeDropper(吸管, 真机上可从屏幕取色)+ 最近历史色 + 色板管理。
// 自制版 ~188 行 (SVPanel + HueSlider + HSV 转换 + 预览/确认按钮) 完全删除。
//
// 集成:
//   AddCourseScreen.showColorPicker: false → sheet → NativeColorPicker(initialHex, onSelect)
//   onSelect hex 写入 courseColor → 自动关闭。

import SwiftUI
import UIKit

struct NativeColorPicker: View {
    @Environment(\.dismiss) private var dismiss
    let initialHex: String
    let onSelect: (String) -> Void

    var body: some View {
        NavigationView {
            NativeColorPickerRepresentable(initialHex: initialHex) { hex in
                onSelect(hex)
                dismiss()
            }
            .navigationTitle(L10n.format("course_color"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.format("cancel")) { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

private struct NativeColorPickerRepresentable: UIViewControllerRepresentable {
    let initialHex: String
    let onColorSelected: (String) -> Void

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.selectedColor = UIColor(hex: initialHex) ?? UIColor(hex: "6750A4")!  // ← ColorPickerDialog.kt:58 getOrDefault(0xFF6750A4); 非法/缺省回退品牌紫
        picker.supportsAlpha = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIColorPickerViewController, context: Context) {
        // 仅在 selectedColor 与初始色不同时更新,避免每次 rebuild 重置 picker 状态
        let current = vc.selectedColor.hexString
        if current != initialHex, !context.coordinator.didSelect {
            vc.selectedColor = UIColor(hex: initialHex) ?? UIColor(hex: "6750A4")!  // ← ColorPickerDialog.kt:58 同 makeUIViewController
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onColorSelected: onColorSelected)
    }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        let onColorSelected: (String) -> Void
        var didSelect = false

        init(onColorSelected: @escaping (String) -> Void) {
            self.onColorSelected = onColorSelected
        }

        func colorPickerViewControllerDidSelectColor(_ vc: UIColorPickerViewController) {
            guard !didSelect else { return }
            didSelect = true
            onColorSelected(vc.selectedColor.hexString)
        }

        func colorPickerViewControllerDidFinish(_ vc: UIColorPickerViewController) {
            // 取消/未选色直接关闭 = Android onDismissRequest(kotlin:71/129): 永不发 onConfirm ← F056 对齐
        }
    }
}

// ← UIColor ↔ "#AARRGGBB" 转换
private extension UIColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#FF%02X%02X%02X",
                      Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }

    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8 else { return nil }
        var rgb: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&rgb) else { return nil }
        if s.count == 6 { rgb |= 0xFF000000 }
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8) & 0xFF) / 255
        let b = CGFloat(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}