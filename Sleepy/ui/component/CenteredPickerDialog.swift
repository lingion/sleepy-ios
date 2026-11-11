import SwiftUI
import UIKit

/// A compact picker dialog with a bounded, naturally sized list.
struct CenteredPickerDialog<Content: View>: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    var titleIdentifier: String? = nil
    var maxContentHeight: CGFloat = 360
    let onDismiss: () -> Void
    var footer: AnyView? = nil
    @ViewBuilder let content: () -> Content
    @State private var measuredHeight: CGFloat = 0
    @State private var titleHeight: CGFloat = 32
    @State private var footerHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.32).ignoresSafeArea()
                    .contentShape(Rectangle()).onTapGesture(perform: onDismiss)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 16) {
                    Text(title).font(SleepyTypography.titleLarge).foregroundColor(colors.onSurface)
                        .accessibilityIdentifier(titleIdentifier ?? "")
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { proxy in
                            Color.clear
                                .onAppear { titleHeight = proxy.size.height }
                                .onChange(of: proxy.size.height) { titleHeight = $0 }
                        })
                    ScrollView {
                        content().frame(maxWidth: .infinity)
                            .fixedSize(horizontal: false, vertical: true)
                            .background(GeometryReader { proxy in
                                Color.clear
                                    .onAppear { measuredHeight = proxy.size.height }
                                    .onChange(of: proxy.size.height) { measuredHeight = $0 }
                            })
                    }
                    .scrollDismissesKeyboardImmediatelyCompat()
                    .frame(height: min(measuredHeight > 0 ? measuredHeight : maxContentHeight,
                                       min(maxContentHeight, max(0, geometry.size.height - 96 - titleHeight
                                           - (footer == nil ? 16 : 32) - footerHeight))))
                    if let footer {
                        footer.fixedSize(horizontal: false, vertical: true)
                            .background(GeometryReader { proxy in
                                Color.clear
                                    .onAppear { footerHeight = proxy.size.height }
                                    .onChange(of: proxy.size.height) { footerHeight = $0 }
                            })
                    }
                }
                .padding(24)
                .frame(width: min(360, max(0, geometry.size.width - 48)), alignment: .leading)
                .background(colors.surfaceContainerHigh)
                .cornerRadius(28)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("centered_picker_dialog")
                .accessibilityAction(.escape, onDismiss)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea(.container)
    }
}

extension View {
    /// Present relative to the owning window, including layouts with a sidebar or bottom bar.
    func centeredDialog<Dialog: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Dialog) -> some View {
        modifier(CenteredDialogModifier(isPresented: isPresented, dialog: content))
    }
}

private struct CenteredDialogModifier<Dialog: View>: ViewModifier {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var direction
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @Binding var isPresented: Bool
    let dialog: () -> Dialog

    func body(content: Content) -> some View {
        content.background(CenteredDialogPresenter(isPresented: isPresented, content: AnyView(
            dialog()
                .environment(\.localWakeUpColors, colors)
                .environment(\.sleepyUIStyle, style)
                .environment(\.layoutDirection, direction)
                .environment(\.sizeCategory, sizeCategory)
                .environment(\.locale, locale)
                .environment(\.calendar, calendar)
                .environment(\.timeZone, timeZone)
                .preferredColorScheme(colorScheme)
        )))
    }
}

private struct CenteredDialogPresenter: UIViewControllerRepresentable {
    let isPresented: Bool
    let content: AnyView

    func makeUIViewController(context: Context) -> DialogPresenterController { DialogPresenterController() }
    func updateUIViewController(_ controller: DialogPresenterController, context: Context) {
        controller.wanted = isPresented
        controller.dialog = content
        controller.reconcile()
    }
    static func dismantleUIViewController(_ controller: DialogPresenterController, coordinator: ()) {
        controller.tearDown()
    }
}

private final class DialogPresenterController: UIViewController {
    var wanted = false {
        didSet { if wanted != oldValue { retries = 0 } }
    }
    var dialog = AnyView(EmptyView())
    private var host: UIHostingController<AnyView>?
    private var scheduled = false
    private var retryScheduled = false
    private var transitioning = false
    private var tornDown = false
    private var retries = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        retries = 0
        reconcile()
    }
    func reconcile() {
        guard !tornDown, !scheduled, !transitioning else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scheduled = false
            guard !self.tornDown else { return }
            if self.wanted {
                if let host = self.host {
                    host.rootView = self.dialog
                    return
                }
                var presenter: UIViewController = self
                while let parent = presenter.parent { presenter = parent }
                guard self.view.window != nil, presenter.presentedViewController == nil,
                      !presenter.isBeingPresented, !presenter.isBeingDismissed else {
                    self.retryPresentation()
                    return
                }
                let host = UIHostingController(rootView: self.dialog)
                host.view.backgroundColor = .clear
                host.view.accessibilityViewIsModal = true
                host.modalPresentationStyle = .overFullScreen
                host.modalTransitionStyle = .crossDissolve
                self.host = host
                self.transitioning = true
                presenter.present(host, animated: true) { [weak self, weak host] in
                    guard let self, !self.tornDown else {
                        host?.dismiss(animated: false)
                        return
                    }
                    self.transitioning = false
                    if host?.presentingViewController == nil { self.host = nil }
                    self.reconcile()
                }
            } else if let host = self.host {
                self.transitioning = true
                host.dismiss(animated: true) { [weak self, weak host] in
                    guard let self else { return }
                    if self.host === host { self.host = nil }
                    self.transitioning = false
                    self.reconcile()
                }
            }
        }
    }

    func tearDown() {
        tornDown = true
        wanted = false
        host?.dismiss(animated: false)
        host = nil
    }

    private func retryPresentation() {
        guard wanted, !tornDown, !retryScheduled else { return }
        retries += 1
        retryScheduled = true
        // Native document/permission controllers can outlive their completion
        // callback. Keep waiting without stealing their presentation delegate.
        let delay: TimeInterval = retries < 10 ? 0.05 : 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.retryScheduled = false
            self.reconcile()
        }
    }
}
