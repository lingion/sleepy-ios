// NativeColorPicker.swift — ← ColorPickerDialog HSV 自制色盘
// 原生化: 用 UIColorPickerViewController (iOS 14+) 替代 AddCourseScreen 自制 HSV 色盘。
// iOS 14+ 原生控件:完整色盘 + EyeDropper(吸管, 真机上可从屏幕取色)+ 最近历史色 + 色板管理。
// 自制版 ~188 行 (SVPanel + HueSlider + HSV 转换 + 预览/确认按钮) 完全删除。
//
// 课程编辑仍在选色后立即返回。自定义主题等待明确确认，取消时不修改草稿。

import SwiftUI
import UIKit

struct NativeColorPicker: View {
    @Environment(\.dismiss) private var dismiss
    let initialHex: String
    var requiresConfirmation = false
    let onSelect: (String) -> Void
    @State private var draftHex: String?
    @State private var completed = false

    var body: some View {
        NavigationView {
            NativeColorPickerRepresentable(initialHex: initialHex, tracksContinuousSelection: requiresConfirmation) { hex in
                if requiresConfirmation {
                    draftHex = hex
                } else {
                    commit(hex)
                }
            }
            .navigationTitle(L10n.format("course_color"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.format("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if requiresConfirmation {
                        Button(L10n.format("action_confirm")) {
                            commit(draftHex ?? initialColor(initialHex).hexString)
                        }
                            .accessibilityIdentifier("theme_color_confirm")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func commit(_ hex: String) {
        guard !completed else { return }
        completed = true
        onSelect(hex)
        dismiss()
    }
}

private struct NativeColorPickerRepresentable: UIViewControllerRepresentable {
    let initialHex: String
    let tracksContinuousSelection: Bool
    let onColorSelected: (String) -> Void

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.supportsAlpha = false
        picker.selectedColor = initialColor(initialHex)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIColorPickerViewController, context: Context) {
        // Keep the UIKit selection alive while SwiftUI updates the draft and toolbar.
        context.coordinator.onColorSelected = onColorSelected
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(tracksContinuousSelection: tracksContinuousSelection, onColorSelected: onColorSelected)
    }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        let tracksContinuousSelection: Bool
        var onColorSelected: (String) -> Void

        init(tracksContinuousSelection: Bool, onColorSelected: @escaping (String) -> Void) {
            self.tracksContinuousSelection = tracksContinuousSelection
            self.onColorSelected = onColorSelected
        }

        func colorPickerViewController(_ vc: UIColorPickerViewController, didSelect color: UIColor,
                                       continuously: Bool) {
            guard tracksContinuousSelection || !continuously else { return }
            onColorSelected(color.hexString)
        }
    }
}

private func initialColor(_ hex: String) -> UIColor {
    UIColor(hex: hex) ?? UIColor(red: 103 / 255, green: 80 / 255, blue: 164 / 255, alpha: 1)
}

// ← UIColor ↔ "#AARRGGBB" 转换
private extension UIColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ value: CGFloat) -> Int { Int(round(min(max(value, 0), 1) * 255)) }
        return String(format: "#FF%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8 else { return nil }
        var rgb: UInt64 = 0
        let scanner = Scanner(string: s)
        guard scanner.scanHexInt64(&rgb), scanner.isAtEnd else { return nil }
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8) & 0xFF) / 255
        let b = CGFloat(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
