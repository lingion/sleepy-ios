import XCTest
import SwiftUI
import UIKit
@testable import Sleepy

final class NativeSelectionThemeParityTests: XCTestCase {
    @MainActor
    func testNativeSegmentUsesExactMaterialSelectedBackgroundAndTitleColors() throws {
        for scheme in [lightScheme, darkScheme] {
            let host = try hosted(SegmentedSwitcher(options: [(0, "One"), (1, "Two")], selected: 1,
                onSelect: { _ in }).environment(\.localWakeUpColors, scheme)
                .environment(\.sleepyUIStyle, .liquidGlass)
                .accessibilityIdentifier("theme_segment"), size: CGSize(width: 240, height: 64))
            defer { host.window.isHidden = true }
            let controls: [UISegmentedControl] = descendants(host.controller.view)
            XCTAssertEqual(controls.count, 1)
            let control = try XCTUnwrap(controls.first)
            assertColor(try XCTUnwrap(control.selectedSegmentTintColor), UIColor(scheme.secondaryContainer))
            let selected = try XCTUnwrap(control.titleTextAttributes(for: .selected)?[.foregroundColor] as? UIColor)
            assertColor(selected, UIColor(scheme.onSecondaryContainer))
            let normal = try XCTUnwrap(control.titleTextAttributes(for: .normal)?[.foregroundColor] as? UIColor)
            assertColor(normal, UIColor(scheme.onSurfaceVariant))
            XCTAssertEqual(control.selectedSegmentIndex, 1)
            XCTAssertEqual(control.titleForSegment(at: 0), "One")
            attach(host.controller.view, name: "native-segment-\(schemeName(scheme))")
        }
    }

    @MainActor
    func testNativeSegmentRetainsLogicalSelectionRTLDisabledEventsAndChildIdentifiers() throws {
        for rtl in [false, true] {
            for enabled in [true, false] {
                var selection: Int?
                let host = try hosted(SegmentedSwitcher(options: [(4, "One"), (9, "Two")], selected: 9,
                    onSelect: { selection = $0 }).environment(\.sleepyUIStyle, .liquidGlass)
                    .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
                    .disabled(!enabled).accessibilityIdentifier("native_segment_contract"),
                    size: CGSize(width: 240, height: 64))
                defer { host.window.isHidden = true }
                let control = try XCTUnwrap((descendants(host.controller.view) as [UISegmentedControl]).first)
                XCTAssertEqual(control.isEnabled, enabled)
                XCTAssertEqual(control.selectedSegmentIndex, 1)
                XCTAssertEqual(control.effectiveUserInterfaceLayoutDirection, rtl ? .rightToLeft : .leftToRight)
                var identifiers: [String] = []
                for index in 0..<control.numberOfSegments {
                    let element = try XCTUnwrap(control.accessibilityElement(at: index) as? NSObject)
                    let identity = try XCTUnwrap(element as? UIAccessibilityIdentification)
                    identifiers.append(try XCTUnwrap(identity.accessibilityIdentifier))
                }
                XCTAssertEqual(Set(identifiers), Set(["seg_One", "seg_Two"]))
                control.selectedSegmentIndex = 0
                control.sendActions(for: .valueChanged)
                XCTAssertEqual(selection, enabled ? 4 : nil)
            }
        }
    }

    @MainActor
    func testNativePillAndRailRenderSelectedContentUsingMatchingMaterialTokens() throws {
        let scheme = lightScheme
        let items = [PillNavItemData(id: "today", icon: "sun.max", label: "Today", selected: true, onClick: {}),
                     PillNavItemData(id: "manage", icon: "square.grid.2x2", label: "Manage", selected: false, onClick: {})]
        for floating in [false, true] {
            let content = PillNavigationBar(items: items, dockStyle: floating ? .floating : .docked)
                .environment(\.localWakeUpColors, scheme).environment(\.sleepyUIStyle, .liquidGlass)
                .background(Color.white)
            let host = try hosted(content, size: CGSize(width: 280, height: 130))
            defer { host.window.isHidden = true }
            let picture = attach(host.controller.view, name: "native-pill-\(floating ? "floating" : "docked")")
            XCTAssertGreaterThan(try countPixels(in: picture, matching: UIColor(scheme.onSecondaryContainer)), 8,
                                 "The selected native icon and title must use the Material foreground")
        }
        for pinned in [false, true] {
            let content = NavigationRailBar(rightTabs: items, selectedTab: .today, motionSelectedTab: .today,
                scheduleIcon: "calendar", scheduleIsPinned: pinned)
                .environment(\.localWakeUpColors, scheme).environment(\.sleepyUIStyle, .liquidGlass)
                .background(Color.white)
            let host = try hosted(content, size: CGSize(width: 100, height: 240))
            defer { host.window.isHidden = true }
            let picture = attach(host.controller.view, name: "native-rail-\(pinned ? "combined" : "plain")")
            XCTAssertGreaterThan(try countPixels(in: picture, matching: UIColor(scheme.onPrimaryContainer)), 8,
                                 "The native rail selected icon must use the Material foreground")
        }
    }

    @MainActor
    func testNativeTabViewUsesExactMaterialSelectionRolesForEveryAppearance() throws {
        for scheme in [lightScheme, darkScheme] {
            let state = NativeTabThemeState(colors: scheme)
            let host = try hosted(NativeTabThemeHarness(state: state), size: CGSize(width: 390, height: 844))
            defer { host.window.isHidden = true }
            let controllers: [UITabBarController] = descendantControllers(host.controller)
            XCTAssertEqual(controllers.count, 1, "The production modifier must keep the native TabView controller")
            let controller = try XCTUnwrap(controllers.first)
            XCTAssertEqual(controller.tabBar.items?.count, 2)
            XCTAssertEqual(controller.selectedIndex, 1)
            try assertNativeTabBar(controller.tabBar, uses: scheme)
            attach(host.controller.view, name: "native-tab-view-\(schemeName(scheme))")
        }
    }

    @MainActor
    func testNativeTabViewUpdatesThemeWithoutReplacingControllerOrSelection() throws {
        let state = NativeTabThemeState(colors: lightScheme)
        let host = try hosted(NativeTabThemeHarness(state: state), size: CGSize(width: 390, height: 844))
        defer { host.window.isHidden = true }
        let controller = try XCTUnwrap((descendantControllers(host.controller) as [UITabBarController]).first)
        try assertNativeTabBar(controller.tabBar, uses: lightScheme)

        state.colors = darkScheme
        waitForUpdates {
            guard let color = controller.tabBar.standardAppearance.selectionIndicatorTintColor else { return false }
            return colorsMatch(color, UIColor(darkScheme.secondaryContainer))
        }
        let updatedController = try XCTUnwrap((descendantControllers(host.controller) as [UITabBarController]).first)
        XCTAssertTrue(updatedController === controller)
        XCTAssertEqual(controller.selectedIndex, 1)
        XCTAssertEqual(state.selection, 1)
        try assertNativeTabBar(controller.tabBar, uses: darkScheme)

        state.selection = 0
        waitForUpdates { controller.selectedIndex == 0 }
        XCTAssertTrue((descendantControllers(host.controller) as [UITabBarController]).first === controller)
        try assertNativeTabBar(controller.tabBar, uses: darkScheme)
    }

    @MainActor
    func testNativeBaselineSliderUsesExactMaterialPrimaryForTrackAndBaseline() throws {
        for scheme in [lightScheme, darkScheme] {
            let state = NativeTabThemeState(colors: scheme)
            let host = try hosted(NativeSliderThemeHarness(state: state), size: CGSize(width: 280, height: 64))
            defer { host.window.isHidden = true }
            let view = try XCTUnwrap((descendants(host.controller.view) as [BaselineSliderView]).first)
            assertColor(try XCTUnwrap(view.slider.tintColor), UIColor(scheme.primary))
            assertColor(try XCTUnwrap(view.ghost.tintColor), UIColor(scheme.primary))
            assertColor(try XCTUnwrap(view.ghost.thumbTintColor), UIColor(scheme.primary))
            XCTAssertEqual(view.slider.value, 0.7, accuracy: 0.001)
            XCTAssertEqual(view.ghost.value, 0.3, accuracy: 0.001)
            XCTAssertTrue(view.ghostVisible)
        }
    }

    @MainActor
    func testNativeBaselineSliderUpdatesMaterialThemeWithoutReplacingControls() throws {
        let state = NativeTabThemeState(colors: lightScheme)
        let host = try hosted(NativeSliderThemeHarness(state: state), size: CGSize(width: 280, height: 64))
        defer { host.window.isHidden = true }
        let view = try XCTUnwrap((descendants(host.controller.view) as [BaselineSliderView]).first)
        let slider = view.slider
        let ghost = view.ghost
        state.colors = darkScheme
        waitForUpdates { self.colorsMatch(slider.tintColor, UIColor(darkScheme.primary)) }
        let updated = try XCTUnwrap((descendants(host.controller.view) as [BaselineSliderView]).first)
        XCTAssertTrue(updated === view)
        XCTAssertTrue(updated.slider === slider)
        XCTAssertTrue(updated.ghost === ghost)
        assertColor(try XCTUnwrap(slider.tintColor), UIColor(darkScheme.primary))
        assertColor(try XCTUnwrap(ghost.thumbTintColor), UIColor(darkScheme.primary))
        XCTAssertEqual(slider.value, 0.7, accuracy: 0.001)
        XCTAssertEqual(ghost.value, 0.3, accuracy: 0.001)
    }

    @MainActor
    private func hosted<Content: View>(_ content: Content, size: CGSize) throws -> (window: UIWindow, controller: UIViewController) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let controller = UIHostingController(rootView: content.frame(width: size.width, height: size.height).ignoresSafeArea())
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.frame = CGRect(origin: .zero, size: size)
        window.isHidden = false
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        return (window, controller)
    }

    @MainActor
    private func descendants<T: UIView>(_ view: UIView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0) }
    }

    @MainActor
    private func descendantControllers<T: UIViewController>(_ controller: UIViewController) -> [T] {
        let matches = (controller as? T).map { [$0] } ?? []
        return matches + controller.children.flatMap { descendantControllers($0) }
    }

    @MainActor
    private func assertNativeTabBar(_ tabBar: UITabBar, uses scheme: WakeUpColorScheme,
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        assertColor(try XCTUnwrap(tabBar.tintColor, file: file, line: line), UIColor(scheme.onSecondaryContainer), file: file, line: line)
        assertColor(try XCTUnwrap(tabBar.unselectedItemTintColor, file: file, line: line), UIColor(scheme.onSurfaceVariant), file: file, line: line)
        XCTAssertNil(tabBar.selectionIndicatorImage, "Keep the native selection indicator", file: file, line: line)
        let scrollEdge = try XCTUnwrap(tabBar.scrollEdgeAppearance, file: file, line: line)
        for appearance in [tabBar.standardAppearance, scrollEdge] {
            assertColor(try XCTUnwrap(appearance.selectionIndicatorTintColor, file: file, line: line),
                        UIColor(scheme.secondaryContainer), file: file, line: line)
            XCTAssertNil(appearance.selectionIndicatorImage, "Keep the native selection indicator", file: file, line: line)
            for item in [appearance.stackedLayoutAppearance,
                         appearance.inlineLayoutAppearance,
                         appearance.compactInlineLayoutAppearance] {
                assertColor(try XCTUnwrap(item.selected.iconColor, file: file, line: line),
                            UIColor(scheme.onSecondaryContainer), file: file, line: line)
                assertColor(try XCTUnwrap(item.selected.titleTextAttributes[.foregroundColor] as? UIColor, file: file, line: line),
                            UIColor(scheme.onSecondaryContainer), file: file, line: line)
                assertColor(try XCTUnwrap(item.normal.iconColor, file: file, line: line),
                            UIColor(scheme.onSurfaceVariant), file: file, line: line)
                assertColor(try XCTUnwrap(item.normal.titleTextAttributes[.foregroundColor] as? UIColor, file: file, line: line),
                            UIColor(scheme.onSurfaceVariant), file: file, line: line)
            }
        }
    }

    @MainActor
    private func waitForUpdates(file: StaticString = #filePath, line: UInt = #line, until predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(1)
        while !predicate(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(predicate(), "The hosted native control did not finish updating", file: file, line: line)
    }

    private func schemeName(_ scheme: WakeUpColorScheme) -> String {
        UIColor(scheme.primary) == UIColor(lightScheme.primary) ? "light" : "dark"
    }

    private func assertColor(_ actual: UIColor, _ expected: UIColor, file: StaticString = #filePath, line: UInt = #line) {
        for (a, e) in zip(components(actual), components(expected)) { XCTAssertEqual(a, e, accuracy: 0.002, file: file, line: line) }
    }

    private func components(_ color: UIColor) -> [CGFloat] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
    }

    private func colorsMatch(_ actual: UIColor, _ expected: UIColor) -> Bool {
        zip(components(actual), components(expected)).allSatisfy { abs($0 - $1) <= 0.002 }
    }

    @MainActor @discardableResult
    private func attach(_ view: UIView, name: String) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let picture = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: picture)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return picture
    }

    private func countPixels(in image: UIImage, matching color: UIColor) throws -> Int {
        let source = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: source.width * source.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: source.width, height: source.height,
                bitsPerComponent: 8, bytesPerRow: source.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        }
        let target = components(color).prefix(3).map { Int(($0 * 255).rounded()) }
        return stride(from: 0, to: bytes.count, by: 4).filter { offset in
            (0..<3).allSatisfy { abs(Int(bytes[offset + $0]) - target[$0]) <= 8 }
        }.count
    }
}

@MainActor
private final class NativeTabThemeState: ObservableObject {
    @Published var colors: WakeUpColorScheme
    @Published var selection = 1

    init(colors: WakeUpColorScheme) { self.colors = colors }
}

private struct NativeTabThemeHarness: View {
    @ObservedObject var state: NativeTabThemeState

    var body: some View {
        TabView(selection: $state.selection) {
            Color.clear
                .modifier(NativeScreenModifier(extraBottom: 92))
                .tabItem { Image(systemName: "calendar"); Text("Schedule") }
                .tag(0)
            Color.clear
                .modifier(NativeScreenModifier(extraBottom: 92))
                .tabItem { Image(systemName: "sun.max"); Text("Today") }
                .tag(1)
        }
        .modifier(NativeTabSelectionTint())
        .ignoresSafeArea(.container, edges: .bottom)
        .environment(\.localWakeUpColors, state.colors)
    }
}

private struct NativeSliderThemeHarness: View {
    @ObservedObject var state: NativeTabThemeState

    var body: some View {
        NativeBaselineSlider(value: 0.7, range: 0...1, baseline: 0.3,
            label: "Theme slider", valueText: "70%", onValueChange: { _ in }, onFinished: {})
            .environment(\.localWakeUpColors, state.colors)
            .accentColor(.green)
    }
}
