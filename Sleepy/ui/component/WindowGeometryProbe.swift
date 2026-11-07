import SwiftUI
import UIKit

/// Read the owning window, not a child whose intrinsic size can retain the previous layout.
struct WindowGeometryProbe: UIViewRepresentable {
    let onChange: (CGSize) -> Void

    func makeUIView(context: Context) -> WindowGeometryProbeView {
        let view = WindowGeometryProbeView()
        view.isUserInteractionEnabled = false
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: WindowGeometryProbeView, context: Context) {
        view.onChange = onChange
        view.reportSize()
    }
}

final class WindowGeometryProbeView: UIView {
    var onChange: ((CGSize) -> Void)?
    private var lastSize = CGSize.zero

    override func didMoveToWindow() {
        super.didMoveToWindow()
        lastSize = .zero
        reportSize()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportSize()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        reportSize()
    }

    func reportSize() {
        guard let window, window.bounds.width > 0, window.bounds.height > 0,
              lastSize != window.bounds.size else { return }
        lastSize = window.bounds.size
        // Avoid publishing SwiftUI state during a UIKit layout pass; reread bounds after rotation settles.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            self.lastSize = window.bounds.size
            self.onChange?(window.bounds.size)
        }
    }
}
