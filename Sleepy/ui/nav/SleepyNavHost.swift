// Native full-screen navigation, shared by root routes and local child pages.
import SwiftUI
import Combine
import UIKit

/// Tabs replace their content directly; pushed pages use UIKit's own transition.
struct SleepyNavigationContent<Key: Hashable, Page: View>: View {
    let selection: Key
    @ViewBuilder var page: (Key) -> Page
    var body: some View { page(selection).id(selection) }
}

struct SleepyNativeNavigationEntry {
    let id: AnyHashable
    let content: AnyView
    let onPop: () -> Void
}

/// One native stack keeps its covered pages and their editing state alive.
struct SleepyNativeNavigationHost<Root: View>: View {
    let pages: [SleepyNativeNavigationEntry]
    @ViewBuilder let root: () -> Root

    var body: some View {
        SleepyNativeNavigationController(pages: pages, root: root).ignoresSafeArea(.container)
    }
}

private struct SleepyNativeNavigationController<Root: View>: UIViewControllerRepresentable {
    let pages: [SleepyNativeNavigationEntry]
    @ViewBuilder let root: () -> Root

    func makeCoordinator() -> SleepyNativeNavigationCoordinator { SleepyNativeNavigationCoordinator() }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = UINavigationController()
        controller.setNavigationBarHidden(true, animated: false)
        controller.delegate = context.coordinator
        context.coordinator.navigationController = controller
        context.coordinator.update(root: AnyView(root()), pages: pages, environment: context.environment)
        return controller
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {
        context.coordinator.update(root: AnyView(root()), pages: pages, environment: context.environment)
    }

    static func dismantleUIViewController(_ controller: UINavigationController,
                                          coordinator: SleepyNativeNavigationCoordinator) {
        coordinator.invalidate()
        controller.delegate = nil
    }
}

private enum SleepyNativeRootID: Hashable { case root }

private struct SleepyNativeNavigationContext {
    weak var coordinator: SleepyNativeNavigationCoordinator?
    let parentID: AnyHashable
}

private struct SleepyNativeNavigationContextKey: EnvironmentKey {
    static let defaultValue: SleepyNativeNavigationContext? = nil
}

private extension EnvironmentValues {
    var sleepyNativeNavigationContext: SleepyNativeNavigationContext? {
        get { self[SleepyNativeNavigationContextKey.self] }
        set { self[SleepyNativeNavigationContextKey.self] = newValue }
    }
}

private struct SleepyNavigationBackDisabledKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// Reconcile only after UIKit completes its current push or interactive pop.
/// Programmatic completions never repeat the model's already-applied back action.
final class SleepyNativeNavigationCoordinator: NSObject, UINavigationControllerDelegate, UIGestureRecognizerDelegate {
    weak var navigationController: UINavigationController?
    private let rootID = AnyHashable(SleepyNativeRootID.root)
    private var root = AnyView(EmptyView())
    private var pages: [SleepyNativeNavigationEntry] = []
    private var environment = EnvironmentValues()
    private var hosts: [AnyHashable: PageHost] = [:]
    private var entries: [AnyHashable: SleepyNativeNavigationEntry] = [:]
    private var registrations: [UUID: LocalRegistration] = [:]
    private var localDismissals: [AnyHashable: () -> Void] = [:]
    private var backDisabled: [AnyHashable: Bool] = [:]
    private var blockedLocalIDs = Set<AnyHashable>()
    private var suppressedGlobalIDs = Set<AnyHashable>()
    private var settledIDs: [AnyHashable] = []
    private var activationOrder: UInt = 0
    private var globalOrders: [AnyHashable: UInt] = [:]
    private var revision: UInt = 0
    private var desiredIDs: [AnyHashable] = []
    private var transition: Transition?
    private var drainScheduled = false
    private var awaitingUIKitCompletion = false
    private var active = true
    private var popGestureDelegates: [ObjectIdentifier: SleepyNativePopGestureDelegateProxy] = [:]

    private struct LocalRegistration {
        let parentID: AnyHashable
        var entry: SleepyNativeNavigationEntry?
        let order: UInt
    }
    private struct Transition {
        let id = UUID()
        let sourceIDs: [AnyHashable]
        let revision: UInt
        let programmatic: Bool
    }

    func update(root: AnyView, pages: [SleepyNativeNavigationEntry], environment: EnvironmentValues) {
        guard active else { return }
        self.root = root
        self.pages = pages
        // Keep an accepted native pop authoritative while its model callback is
        // waiting for SwiftUI to deliver the next route snapshot.
        suppressedGlobalIDs.formIntersection(Set(pages.map(\.id)))
        self.environment = environment
        for page in pages {
            entries[page.id] = page
            if globalOrders[page.id] == nil {
                activationOrder &+= 1
                globalOrders[page.id] = activationOrder
            }
        }
        reconcileDesiredPath()
        refreshHosts()
        drain()
    }

    fileprivate func register(_ scope: UUID, parentID: AnyHashable,
                              entry: SleepyNativeNavigationEntry?, onDismiss: @escaping () -> Void) {
        guard active else { return }
        let old = registrations[scope]
        var order = old?.order ?? 0
        if old == nil || old?.entry?.id != entry?.id {
            activationOrder &+= 1
            order = activationOrder
        }
        registrations[scope] = LocalRegistration(parentID: parentID, entry: entry, order: order)
        if let entry {
            entries[entry.id] = entry
            localDismissals[entry.id] = onDismiss
        } else if let previousID = old?.entry?.id {
            blockedLocalIDs.remove(previousID)
        }
        reconcileDesiredPath()
        // A registration originates in this source host's render pass. Updating
        // every host again here would feed the registration back into itself.
        if let entry, let host = hosts[entry.id] { host.rootView = content(for: entry.id) }
        scheduleDrain()
    }

    fileprivate func isCurrentRegistration(_ scope: UUID, entryID: AnyHashable) -> Bool {
        active && registrations[scope]?.entry?.id == entryID
    }

    fileprivate func unregister(_ scope: UUID) {
        guard active, registrations.removeValue(forKey: scope) != nil else { return }
        reconcileDesiredPath()
        scheduleDrain()
    }

    private func reconcileDesiredPath() {
        // Global routes and local flows share an activation order. A fresh root
        // import can cover an unsaved editor, and a later deep link can cover
        // that import without destroying either covered host's editing state.
        var candidates: [(id: AnyHashable, parent: AnyHashable, order: UInt)] = []
        var previousGlobal = rootID
        for page in pages.prefix(while: { !suppressedGlobalIDs.contains($0.id) }) {
            candidates.append((page.id, previousGlobal, globalOrders[page.id] ?? 0))
            previousGlobal = page.id
        }
        for registration in registrations.values {
            if let entry = registration.entry, !blockedLocalIDs.contains(entry.id) {
                candidates.append((entry.id, registration.parentID, registration.order))
            }
        }
        var path = [rootID]
        while let index = candidates.indices
            .filter({ path.contains(candidates[$0].parent) })
            .min(by: { candidates[$0].order < candidates[$1].order }) {
            let candidate = candidates.remove(at: index)
            if !path.contains(candidate.id) { path.append(candidate.id) }
        }
        if desiredIDs != path { revision &+= 1; desiredIDs = path }
    }

    private var actualIDs: [AnyHashable] {
        navigationController?.viewControllers.compactMap { ($0 as? PageHost)?.entryID } ?? []
    }

    private func refreshHosts() {
        guard let navigationController else { return }
        let background = UIColor(environment.localWakeUpColors.background)
        navigationController.view.backgroundColor = background
        navigationController.setNavigationBarHidden(true, animated: false)
        for (id, host) in hosts {
            if id == rootID || entries[id] != nil { host.rootView = content(for: id) }
            host.view.backgroundColor = background
        }
        updatePopGesture()
    }

    private func content(for id: AnyHashable) -> AnyView {
        let page = id == rootID ? root : entries[id]?.content ?? AnyView(EmptyView())
        // Copy public app/layout values, never SwiftUI's private presentation state.
        return AnyView(page
            .environment(\.localWakeUpColors, environment.localWakeUpColors)
            .environment(\.localCoursePalette, environment.localCoursePalette)
            .environment(\.sleepyUIStyle, environment.sleepyUIStyle)
            .environment(\.sleepyNativeButtonSurface, environment.sleepyNativeButtonSurface)
            .environment(\.systemColorSnapshot, environment.systemColorSnapshot)
            .environment(\.localNavExtraBottomPadding, id == rootID ? environment.localNavExtraBottomPadding : 0)
            .environment(\.colorScheme, environment.colorScheme)
            .environment(\.layoutDirection, environment.layoutDirection)
            .environment(\.sizeCategory, environment.sizeCategory)
            .environment(\.dynamicTypeSize, environment.dynamicTypeSize)
            .environment(\.legibilityWeight, environment.legibilityWeight)
            .environment(\.displayScale, environment.displayScale)
            .environment(\.horizontalSizeClass, environment.horizontalSizeClass)
            .environment(\.verticalSizeClass, environment.verticalSizeClass)
            .environment(\.locale, environment.locale)
            .environment(\.calendar, environment.calendar)
            .environment(\.timeZone, environment.timeZone)
            .environment(\.scenePhase, environment.scenePhase)
            .environment(\.isEnabled, environment.isEnabled)
            .environment(\.sleepyNativeNavigationContext,
                         SleepyNativeNavigationContext(coordinator: self, parentID: id))
            .tint(environment.localWakeUpColors.primary)
            .background(environment.localWakeUpColors.background.ignoresSafeArea())
            .onPreferenceChange(SleepyNavigationBackDisabledKey.self) { [weak self] disabled in
                guard let self, self.active, self.backDisabled[id] != disabled else { return }
                self.backDisabled[id] = disabled
                self.updatePopGesture()
            })
    }

    private func host(for id: AnyHashable) -> PageHost {
        if let host = hosts[id] { return host }
        let host = PageHost(entryID: id, rootView: content(for: id))
        host.view.backgroundColor = UIColor(environment.localWakeUpColors.background)
        hosts[id] = host
        return host
    }

    private func drain() {
        guard active, transition == nil, let navigationController else { return }
        // didShow normally clears this before the scheduled drain. A completion
        // still unwinding UIKit must not start a second stack mutation.
        if let coordinator = navigationController.transitionCoordinator {
            guard !awaitingUIKitCompletion else { return }
            awaitingUIKitCompletion = true
            let retry: () -> Void = { [weak self] in
                guard let self else { return }
                self.awaitingUIKitCompletion = false
                self.scheduleDrain()
            }
            if !coordinator.animate(alongsideTransition: nil, completion: { _ in retry() }) {
                // UIKit can retain a coordinator briefly after its completion
                // callbacks stop accepting work. Resume once it unwinds.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: retry)
            }
            return
        }
        let current = actualIDs
        guard current != desiredIDs else { prune(); updatePopGesture(); return }
        let wanted = desiredIDs
        let animated = !current.isEmpty && navigationController.view.window != nil
            && !environment.accessibilityReduceMotion
        let pending = Transition(sourceIDs: current, revision: revision, programmatic: true)
        transition = pending
        updatePopGesture()
        if !current.isEmpty, current.count < wanted.count,
           Array(wanted.prefix(current.count)) == current {
            navigationController.pushViewController(host(for: wanted[current.count]), animated: animated)
        } else if current.count > wanted.count, Array(current.prefix(wanted.count)) == wanted,
                  let last = wanted.last, let destination = hosts[last] {
            navigationController.popToViewController(destination, animated: animated)
        } else {
            navigationController.setViewControllers(wanted.map { host(for: $0) }, animated: animated)
        }
        if !animated { finish(pending.id) }
        else if let coordinator = navigationController.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.finish(pending.id) }
        } else {
            DispatchQueue.main.async { [weak self] in self?.finish(pending.id) }
        }
    }

    private func scheduleDrain() {
        guard active, !drainScheduled else { return }
        drainScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.drainScheduled = false
            self.drain()
        }
    }

    private func finish(_ id: UUID) {
        guard active, let pending = transition, pending.id == id else { return }
        transition = nil
        let now = actualIDs
        settledIDs = now
        let removed = pending.sourceIDs.filter { !now.contains($0) }
        if !pending.programmatic, pending.revision == revision,
           now.count + 1 == pending.sourceIDs.count,
           Array(pending.sourceIDs.prefix(now.count)) == now,
           let popped = removed.last, let entry = entries[popped] {
            // Block stale model snapshots before asking the source to redraw.
            // A canceled gesture removes nothing and invokes nothing.
            if pages.contains(where: { $0.id == popped }) {
                suppressedGlobalIDs.insert(popped)
            } else {
                blockedLocalIDs.insert(popped)
            }
            reconcileDesiredPath()
            entry.onPop()
        }
        for removedID in removed.reversed() where !desiredIDs.contains(removedID) {
            if let callback = localDismissals.removeValue(forKey: removedID) { callback() }
        }
        prune()
        updatePopGesture()
        scheduleDrain()
    }

    private func prune() {
        let retained = Set(actualIDs + desiredIDs + (transition?.sourceIDs ?? []))
        hosts = hosts.filter { retained.contains($0.key) }
        entries = entries.filter { retained.contains($0.key) }
        backDisabled = backDisabled.filter { retained.contains($0.key) }
        localDismissals = localDismissals.filter { retained.contains($0.key) }
        registrations = registrations.filter { retained.contains($0.value.parentID) }
        blockedLocalIDs.formIntersection(Set(registrations.values.compactMap { $0.entry?.id }))
        let globalIDs = Set(pages.map(\.id))
        suppressedGlobalIDs.formIntersection(globalIDs)
        globalOrders = globalOrders.filter { globalIDs.contains($0.key) }
    }

    private var popGestures: [UIGestureRecognizer] {
        guard let navigationController else { return [] }
        var gestures = [navigationController.interactivePopGestureRecognizer].compactMap { $0 }
        if #available(iOS 26.0, *),
           let content = navigationController.interactiveContentPopGestureRecognizer {
            gestures.append(content)
        }
        return gestures
    }

    private func popGestureDelegate(for gesture: UIGestureRecognizer) -> SleepyNativePopGestureDelegateProxy {
        let key = ObjectIdentifier(gesture)
        if let proxy = popGestureDelegates[key] {
            // UIKit may install a fresh native delegate after a transition.
            // Capture that replacement before reinstalling our stable proxy.
            if gesture.delegate !== proxy { proxy.originalDelegate = gesture.delegate }
            return proxy
        }
        let proxy = SleepyNativePopGestureDelegateProxy(
            gestureRecognizer: gesture, originalDelegate: gesture.delegate, coordinator: self)
        popGestureDelegates[key] = proxy
        return proxy
    }

    private func updatePopGesture() {
        guard active, let navigationController else { return }
        let gestures = popGestures
        // UIKit coordinates edge and content pans. Keep both native recognizers
        // under the same back policy, and never reset one during an active pan.
        guard transition?.programmatic != false,
              !gestures.contains(where: { $0.state == .began || $0.state == .changed }) else { return }
        let enabled = navigationController.viewControllers.count > 1 && transition == nil
            && !(actualIDs.last.flatMap { backDisabled[$0] } ?? false)
        for gesture in gestures {
            gesture.delegate = popGestureDelegate(for: gesture)
            gesture.isEnabled = enabled
        }
    }

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController,
                              animated: Bool) {
        navigationController.setNavigationBarHidden(true, animated: false)
        if transition == nil {
            transition = Transition(sourceIDs: settledIDs.isEmpty ? actualIDs : settledIDs,
                                    revision: revision, programmatic: false)
        }
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController,
                              animated: Bool) {
        if let pending = transition { finish(pending.id) }
        else { settledIDs = actualIDs }
        updatePopGesture()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard active, transition == nil, let navigationController,
              navigationController.viewControllers.count > 1,
              navigationController.presentedViewController == nil,
              !(actualIDs.last.flatMap { backDisabled[$0] } ?? false),
              let top = navigationController.topViewController else { return false }
        return !containsNestedNavigationWithBackPage(top)
    }

    private func containsNestedNavigationWithBackPage(_ controller: UIViewController) -> Bool {
        if let child = controller as? UINavigationController, child !== navigationController,
           child.viewControllers.count > 1 { return true }
        return controller.children.contains { containsNestedNavigationWithBackPage($0) }
    }

    func invalidate() {
        for proxy in popGestureDelegates.values {
            if let gesture = proxy.gestureRecognizer, gesture.delegate === proxy {
                gesture.delegate = proxy.originalDelegate
            }
        }
        popGestureDelegates.removeAll()
        active = false
        registrations.removeAll()
        localDismissals.removeAll()
        hosts.removeAll()
        entries.removeAll()
        blockedLocalIDs.removeAll()
        suppressedGlobalIDs.removeAll()
        settledIDs.removeAll()
        globalOrders.removeAll()
        transition = nil
    }

    private final class PageHost: UIHostingController<AnyView> {
        let entryID: AnyHashable
        init(entryID: AnyHashable, rootView: AnyView) {
            self.entryID = entryID
            super.init(rootView: rootView)
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    }
}

/// Keep UIKit's gesture arbitration while overriding only the app's back gate.
/// A separate proxy for each recognizer preserves its own original delegate.
/// No targets, thresholds, failure requirements or gesture states are changed.
private final class SleepyNativePopGestureDelegateProxy: NSObject, UIGestureRecognizerDelegate {
    weak var gestureRecognizer: UIGestureRecognizer?
    weak var originalDelegate: UIGestureRecognizerDelegate?
    weak var coordinator: SleepyNativeNavigationCoordinator?

    init(gestureRecognizer: UIGestureRecognizer,
         originalDelegate: UIGestureRecognizerDelegate?,
         coordinator: SleepyNativeNavigationCoordinator) {
        self.gestureRecognizer = gestureRecognizer
        self.originalDelegate = originalDelegate
        self.coordinator = coordinator
        super.init()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // The app uses a custom toolbar and hides UINavigationBar. Its existing
        // gate remains authoritative instead of inheriting a hidden-bar veto.
        coordinator?.gestureRecognizerShouldBegin(gestureRecognizer) ?? false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        let allowed = originalDelegate?.gestureRecognizer?(
            gestureRecognizer, shouldRecognizeSimultaneouslyWith: otherGestureRecognizer) ?? false
        return allowed
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        let required = originalDelegate?.gestureRecognizer?(
            gestureRecognizer, shouldRequireFailureOf: otherGestureRecognizer) ?? false
        return required
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        let required = originalDelegate?.gestureRecognizer?(
            gestureRecognizer, shouldBeRequiredToFailBy: otherGestureRecognizer) ?? false
        return required
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let allowed = originalDelegate?.gestureRecognizer?(gestureRecognizer, shouldReceive: touch) ?? true
        return allowed
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
        originalDelegate?.gestureRecognizer?(gestureRecognizer, shouldReceive: press) ?? true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive event: UIEvent) -> Bool {
        originalDelegate?.gestureRecognizer?(gestureRecognizer, shouldReceive: event) ?? true
    }
}

private struct SleepyLocalNavigationID: Hashable {
    let scope: UUID
    let item: AnyHashable
    let session: UUID
}

/// Navigation values have to notify UIKit even while their SwiftUI source is
/// covered by another hosting controller. Binding alone has no change publisher.
@propertyWrapper
struct SleepyNavigationState<Value>: DynamicProperty {
    @StateObject private var storage: SleepyNavigationStorage<Value>

    init(wrappedValue: Value) {
        _storage = StateObject(wrappedValue: SleepyNavigationStorage(wrappedValue))
    }

    var wrappedValue: Value {
        get { storage.value }
        nonmutating set { storage.set(newValue) }
    }

    var projectedValue: Binding<Value> {
        let storage = storage
        return Binding(get: { storage.value }, set: { storage.set($0) })
    }

    var changes: AnyPublisher<Void, Never> { storage.changes.eraseToAnyPublisher() }
}

private final class SleepyNavigationStorage<Value>: ObservableObject {
    @Published private(set) var value: Value
    let changes = PassthroughSubject<Void, Never>()

    init(_ value: Value) { self.value = value }

    func set(_ value: Value) {
        self.value = value
        // Publish after assignment: reconciliation must read the latest value.
        changes.send()
    }
}

private final class SleepyNavigationRegistration: ObservableObject {
    let scope = UUID()
    weak var coordinator: SleepyNativeNavigationCoordinator?
    private(set) var registeredItemID: AnyHashable?
    private(set) var session = UUID()
    private var observation: AnyCancellable?
    private var refresh: (() -> Void)?
    private var refreshScheduled = false

    func observe(_ changes: AnyPublisher<Void, Never>, refresh: @escaping () -> Void) {
        self.refresh = refresh
        if observation == nil {
            observation = changes.sink { [weak self] _ in self?.scheduleRefresh() }
        }
        refresh()
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        // Leave SwiftUI's render pass before mutating a hosting controller.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refresh?()
        }
    }

    /// Bool presentations reuse an item ID, but each activation owns its callbacks.
    func synchronize(itemID: AnyHashable?) {
        if let itemID, registeredItemID != itemID { session = UUID() }
        registeredItemID = itemID
    }

    func accepts(session: UUID) -> Bool { self.session == session }

    deinit {
        let scope = scope
        let coordinator = coordinator
        DispatchQueue.main.async { [weak coordinator] in coordinator?.unregister(scope) }
    }
}

/// Keep the API usable in a sheet: only trees without a context create a stack.
private struct SleepyNavigationPage<Item: Identifiable, Page: View, Canvas: View>: ViewModifier {
    @Environment(\.sleepyNativeNavigationContext) private var navigation
    @Binding var item: Item?
    let changes: AnyPublisher<Void, Never>
    let onDismiss: () -> Void
    @ViewBuilder var canvas: () -> Canvas
    @ViewBuilder var page: (Item) -> Page

    func body(content: Content) -> some View {
        if navigation?.coordinator != nil {
            registered(content)
        } else {
            SleepyNativeNavigationHost(pages: []) { registered(content) }
        }
    }

    private func registered(_ content: Content) -> some View {
        content.modifier(SleepyNavigationPageRegistration(item: $item, changes: changes,
                                                         onDismiss: onDismiss, canvas: canvas, page: page))
    }
}

private struct SleepyNavigationPageRegistration<Item: Identifiable, Page: View, Canvas: View>: ViewModifier {
    @Environment(\.sleepyNativeNavigationContext) private var navigation
    @Binding var item: Item?
    let changes: AnyPublisher<Void, Never>
    let onDismiss: () -> Void
    @ViewBuilder let canvas: () -> Canvas
    @ViewBuilder let page: (Item) -> Page
    @StateObject private var registration = SleepyNavigationRegistration()

    func body(content: Content) -> some View {
        let registration = registration
        let binding = $item
        let navigation = navigation
        let page = page
        let canvas = canvas
        let onDismiss = onDismiss
        content.background(SleepyNavigationRegistrationUpdate(update: {
            guard let navigation, let coordinator = navigation.coordinator else { return }
            registration.coordinator = coordinator
            registration.observe(changes) { [weak registration, weak coordinator] in
                guard let registration, let coordinator else { return }
                Self.update(binding: binding, registration: registration, coordinator: coordinator,
                            parentID: navigation.parentID, onDismiss: onDismiss, canvas: canvas, page: page)
            }
        }).frame(width: 0, height: 0))
    }

    private static func update(binding: Binding<Item?>, registration: SleepyNavigationRegistration,
                               coordinator: SleepyNativeNavigationCoordinator, parentID: AnyHashable,
                               onDismiss: @escaping () -> Void, canvas: @escaping () -> Canvas,
                               page: @escaping (Item) -> Page) {
        // Queued render updates and direct notifications both use the live value.
        let live = binding.wrappedValue
        registration.synchronize(itemID: live.map { AnyHashable($0.id) })
        let session = registration.session
        let entry = live.map { value in
            let entryID = AnyHashable(SleepyLocalNavigationID(scope: registration.scope,
                                                             item: AnyHashable(value.id), session: session))
            return SleepyNativeNavigationEntry(
                id: entryID,
                content: AnyView(page(value).frame(maxWidth: .infinity, maxHeight: .infinity).background(canvas())),
                onPop: {
                    guard registration.accepts(session: session),
                          coordinator.isCurrentRegistration(registration.scope, entryID: entryID),
                          binding.wrappedValue?.id == value.id else { return }
                    registration.synchronize(itemID: nil)
                    binding.wrappedValue = nil
                })
        }
        let presentedID = live?.id
        let presentedEntryID = entry?.id
        coordinator.register(registration.scope, parentID: parentID, entry: entry, onDismiss: {
            // A previous pop must not clear a new Bool activation, even before
            // that activation's queued registration reaches the coordinator.
            guard registration.accepts(session: session) else { return }
            if let current = binding.wrappedValue {
                guard current.id == presentedID,
                      registration.registeredItemID == AnyHashable(current.id),
                      let presentedEntryID,
                      coordinator.isCurrentRegistration(registration.scope, entryID: presentedEntryID) else { return }
                registration.synchronize(itemID: nil)
                binding.wrappedValue = nil
            }
            onDismiss()
        })
    }
}

private struct SleepyNavigationRegistrationUpdate: UIViewRepresentable {
    let update: () -> Void
    func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }
    func updateUIView(_ view: UIView, context: Context) { DispatchQueue.main.async(execute: update) }
}

private struct SleepyNavigationPageToken: Identifiable {
    let id = 0
}

extension View {
    func sleepyNavigationBackDisabled(_ disabled: Bool) -> some View {
        preference(key: SleepyNavigationBackDisabledKey.self, value: disabled)
    }

    func sleepyNavigationPage<Item: Identifiable, Page: View, Canvas: View>(
        item: Binding<Item?>, changes: AnyPublisher<Void, Never>, onDismiss: @escaping () -> Void = {},
        @ViewBuilder canvas: @escaping () -> Canvas,
        @ViewBuilder content: @escaping (Item) -> Page
    ) -> some View {
        modifier(SleepyNavigationPage(item: item, changes: changes, onDismiss: onDismiss,
                                      canvas: canvas, page: content))
    }

    func sleepyNavigationPage<Page: View, Canvas: View>(
        isPresented: Binding<Bool>, changes: AnyPublisher<Void, Never>, onDismiss: @escaping () -> Void = {},
        @ViewBuilder canvas: @escaping () -> Canvas,
        @ViewBuilder content: @escaping () -> Page
    ) -> some View {
        sleepyNavigationPage(item: Binding(
            get: { isPresented.wrappedValue ? SleepyNavigationPageToken() : nil },
            set: { isPresented.wrappedValue = $0 != nil }), changes: changes, onDismiss: onDismiss,
            canvas: canvas, content: { _ in content() })
    }
}

extension AppRootViewModel {
    /// 路由 → iOS 导航态 单点入口 (原版本 SleepyNavigator.openXxx 的 VM 直驱版).
    /// 未落地路由在此集中留痕, 避免散落的 no-op.
    @discardableResult
    func navigate(to route: SleepyRoute) -> Bool {
        guard route.isIOSPorted else { return false }
        switch route {
        case .main:
            break
        case .addCourse:
            initialCourseSlot = nil
            pushOverlay(.addCourse)
        case .allTables:
            pushOverlay(.allTables)
        case .editTable(let tableId, let pendingNew, let prevDefault):
            editTableId = (tableId == SleepyRoute.NO_ID) ? nil : tableId
            pendingNewTableId = (pendingNew == SleepyRoute.NO_ID) ? nil : pendingNew
            previousDefaultTableId = (prevDefault == SleepyRoute.NO_ID) ? nil : prevDefault
            pushOverlay(.editTable)
        case .appearance:
            pushOverlay(.theme)
        case .scheduleDisplay:
            pushOverlay(.scheduleDisplay)
        case .general:
            pushOverlay(.general)
        case .export:
            pushOverlay(.export)
        case .reminder:
            pushOverlay(.reminder)
        case .about:
            pushOverlay(.about)
        case .license:
            pushOverlay(.license)
        case .courseList:
            pushOverlay(.courseList)
        case .periodTables:
            pushOverlay(.periodTables)
        case .periodEdit(let periodId, let isNew):
            // 绑定 = 生产 onOpenPeriodEdit 同式 (SleepyApp PresentOverlay 接线) —
            // facade 桥接收编于此, 单一真源恢复。
            periodEditId = periodId
            pendingNewPeriodTableId = isNew ? periodId : nil
            pushOverlay(.periodEdit)
        case .periodHeaderSettings:
            pushOverlay(.periodHeaderSettings)
        default:
            return false
        }
        return true
    }
}
