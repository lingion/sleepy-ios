import SwiftUI
import UIKit
import XCTest
@testable import Sleepy

final class ImportPresentationLifecycleTests: XCTestCase {
    func testActiveMethodsPreserveIdentityUntilActualDismissal() {
        var state = ImportPresentationState()
        XCTAssertTrue(state.begin(.methods))
        XCTAssertFalse(state.begin(.methods))
        XCTAssertFalse(state.begin(.jw))
        XCTAssertEqual(state.active, .methods)
        XCTAssertTrue(state.didDismiss(.methods))
        XCTAssertTrue(state.begin(.methods))
    }

    func testDirectJWSerializesDeferredDocumentThroughDismissal() {
        var state = ImportPresentationState()
        XCTAssertTrue(state.begin(.jw))
        // An onFinish toggling a presentation binding is not a dismissal callback.
        XCTAssertFalse(state.begin(.methods))
        XCTAssertTrue(state.didDismiss(.jw))
        XCTAssertTrue(state.begin(.methods))
    }

    func testUnrelatedDismissCallbackCannotReleaseCurrentPresentation() {
        var state = ImportPresentationState()
        XCTAssertTrue(state.begin(.methods))
        XCTAssertFalse(state.didDismiss(.jw))
        XCTAssertFalse(state.begin(.jw))
        XCTAssertTrue(state.didDismiss(.methods))
        XCTAssertTrue(state.begin(.jw))
        XCTAssertFalse(state.didDismiss(.methods))
        XCTAssertEqual(state.active, .jw)
    }
}

extension ImportPresentationLifecycleTests {
    @MainActor
    func testNativeBooleanNavigationTracksStateAcrossRepeatedPresentations() async throws {
        let harness = NativeNavigationHarness()
        defer { harness.close() }
        try await harness.waitUntil("The native root and its state setter must appear") {
            harness.probe.setPresented != nil && harness.isSettled(at: 1)
        }

        for attempt in 1...3 {
            harness.probe.setPresented?(true)
            try await harness.waitUntil("Presentation \(attempt) must push its native page") {
                harness.isSettled(at: 2)
            }
            harness.probe.setPresented?(false)
            try await harness.waitUntil("Dismissal \(attempt) must remove its native page exactly once") {
                harness.isSettled(at: 1) && harness.probe.dismissals == attempt
            }
        }
        XCTAssertEqual(harness.probe.dismissals, 3)
    }

    @MainActor
    func testNativeBooleanReopenDuringPopKeepsTheNewPresentationAlive() async throws {
        guard UIView.areAnimationsEnabled, !UIAccessibility.isReduceMotionEnabled else {
            throw XCTSkip("This regression requires an actual UIKit pop animation")
        }
        let harness = NativeNavigationHarness()
        defer { harness.close() }
        try await harness.waitUntil("The native root and its state setter must appear") {
            harness.probe.setPresented != nil && harness.isSettled(at: 1)
        }
        harness.probe.setPresented?(true)
        try await harness.waitUntil("The first presentation must finish pushing") {
            harness.isSettled(at: 2)
        }
        let oldPage = try XCTUnwrap(harness.navigationController?.topViewController)

        harness.probe.setPresented?(false)
        try await harness.waitUntil("Observe the old page's animated pop before reopening") {
            guard let navigation = harness.navigationController else { return false }
            return navigation.viewControllers.count == 1 && navigation.transitionCoordinator != nil
        }
        harness.probe.setPresented?(true)
        try await harness.waitUntil("A new Bool activation must survive the old pop completion") {
            guard let navigation = harness.navigationController else { return false }
            return harness.isSettled(at: 2) && navigation.topViewController !== oldPage
        }
        // Give delayed registration and dismissal callbacks time to run. They
        // must not turn the new true value back to false or reuse the old host.
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(harness.isSettled(at: 2))
        XCTAssertTrue(harness.navigationController?.topViewController !== oldPage)
        XCTAssertEqual(harness.probe.dismissals, 0,
                       "An obsolete session must not deliver the new session's dismissal callback")

        harness.probe.setPresented?(false)
        try await harness.waitUntil("The new session must still dismiss normally exactly once") {
            harness.isSettled(at: 1) && harness.probe.dismissals == 1
        }
    }

    @MainActor
    func testReplacingOptionalNavigationItemDoesNotDismissItsReplacement() async throws {
        let harness = NativeNavigationHarness(itemFixture: true)
        defer { harness.close() }
        try await harness.waitUntil("The optional item fixture must expose its setter") {
            harness.probe.setItem != nil && harness.isSettled(at: 1)
        }
        harness.probe.setItem?(NativeNavigationTestItem(id: 1))
        try await harness.waitUntil("The first item must finish pushing") {
            harness.isSettled(at: 2) && harness.probe.appearedItemID == 1
        }
        let oldPage = try XCTUnwrap(harness.navigationController?.topViewController)

        // Replace the item while its source controller is covered. Removing
        // item 1 must never run a dismissal that clears the live item 2 binding.
        harness.probe.setItem?(NativeNavigationTestItem(id: 2))
        try await harness.waitUntil("The replacement item must own a new native page") {
            guard let navigation = harness.navigationController else { return false }
            return harness.isSettled(at: 2) && navigation.topViewController !== oldPage
                && harness.probe.appearedItemID == 2
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(harness.isSettled(at: 2))
        XCTAssertTrue(harness.navigationController?.topViewController !== oldPage)
        XCTAssertEqual(harness.probe.appearedItemID, 2)
        XCTAssertEqual(harness.probe.dismissals, 0,
                       "The old item's dismissal must not clear or dismiss its replacement")

        harness.probe.setItem?(nil)
        try await harness.waitUntil("The replacement item must still dismiss normally exactly once") {
            harness.isSettled(at: 1) && harness.probe.dismissals == 1
        }
    }
}

@MainActor
private final class NativeNavigationProbe {
    // Deliberately not ObservableObject: the production change publisher must
    // deliver across hosting controllers without incidental test rerenders.
    var setPresented: ((Bool) -> Void)?
    var setItem: ((NativeNavigationTestItem?) -> Void)?
    var appearedItemID: Int?
    var dismissals = 0
}

@MainActor
private struct NativeBooleanNavigationFixture: View {
    let probe: NativeNavigationProbe
    @SleepyNavigationState private var presented = false

    var body: some View {
        SleepyNativeNavigationHost(pages: []) {
            Button("Present native page") { presented = true }
                .onAppear {
                    // Expose only a setter. Cross-host navigation changes must
                    // arrive through the state publisher, without a probe read
                    // or observed test object accidentally rerendering the source.
                    probe.setPresented = { presented = $0 }
                }
                .sleepyNavigationPage(isPresented: $presented, changes: _presented.changes, onDismiss: {
                    probe.dismissals += 1
                    presented = false
                }, canvas: { Color.white }) {
                    Button("Dismiss native page") { presented = false }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
        }
    }
}

private struct NativeNavigationTestItem: Identifiable {
    let id: Int
}

@MainActor
private struct NativeOptionalNavigationFixture: View {
    let probe: NativeNavigationProbe
    @SleepyNavigationState private var item: NativeNavigationTestItem? = nil

    var body: some View {
        SleepyNativeNavigationHost(pages: []) {
            Button("Present first native item") { item = NativeNavigationTestItem(id: 1) }
                .onAppear { probe.setItem = { item = $0 } }
                .sleepyNavigationPage(item: $item, changes: _item.changes, onDismiss: {
                    probe.dismissals += 1
                    item = nil
                }, canvas: { Color.white }) { value in
                    Text("Native item \(value.id)")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear { probe.appearedItemID = value.id }
                }
        }
    }
}

@MainActor
private final class NativeNavigationHarness {
    let probe = NativeNavigationProbe()
    private let window: UIWindow
    private let hosting: UIHostingController<AnyView>

    init(itemFixture: Bool = false) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
            window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        }
        let fixture = itemFixture
            ? AnyView(NativeOptionalNavigationFixture(probe: probe))
            : AnyView(NativeBooleanNavigationFixture(probe: probe))
        hosting = UIHostingController(rootView: fixture)
        window.rootViewController = hosting
        // Keep the app's existing key window unchanged. UIKit still performs
        // actual navigation animations in this separate visible test window.
        window.isHidden = false
        hosting.view.layoutIfNeeded()
    }

    var navigationController: UINavigationController? {
        func find(in controller: UIViewController) -> UINavigationController? {
            if let navigation = controller as? UINavigationController { return navigation }
            for child in controller.children {
                if let navigation = find(in: child) { return navigation }
            }
            return nil
        }
        return find(in: hosting)
    }

    func isSettled(at count: Int) -> Bool {
        guard let navigation = navigationController else { return false }
        return navigation.viewControllers.count == count && navigation.transitionCoordinator == nil
            && navigation.topViewController?.view.window === window
    }

    func waitUntil(_ message: String, timeout: TimeInterval = 4,
                   file: StaticString = #filePath, line: UInt = #line,
                   _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            hosting.view.layoutIfNeeded()
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let details = "count=\(navigationController?.viewControllers.count ?? -1); transition=\(navigationController?.transitionCoordinator != nil); topWindow=\(navigationController?.topViewController?.view.window === window); dismissals=\(probe.dismissals)"
        throw NativeNavigationTimeout(message: "\(message) (\(file):\(line)); \(details)")
    }

    func close() {
        probe.setPresented = nil
        probe.setItem = nil
        window.isHidden = true
        window.rootViewController = nil
    }
}

private struct NativeNavigationTimeout: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
