import SwiftUI

/// Measure the scroll content so short sheets wrap and long sheets remain scrollable.
struct ContentFittingSheet<Content: View>: View {
    private let content: Content
    @State private var contentHeight: CGFloat = 0

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 24)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: SheetContentHeightKey.self, value: geometry.size.height)
                })
        }
        .onPreferenceChange(SheetContentHeightKey.self) { height in
            guard height.isFinite, height > 0, abs(height - contentHeight) > 0.5 else { return }
            contentHeight = height
        }
        .modifier(ContentFittingDetents(height: contentHeight))
    }
}

private struct SheetContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ContentFittingDetents: ViewModifier {
    let height: CGFloat
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            // The system clamps a height detent to the available presentation space.
            content.presentationDetents([.height(max(1, height))]).presentationDragIndicator(.visible)
        } else {
            content.sheetDetents([.medium, .large]).sheetDragIndicator(.visible)
        }
    }
}
