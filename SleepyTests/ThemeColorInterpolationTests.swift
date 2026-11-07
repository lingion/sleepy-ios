import XCTest
import SwiftUI
import UIKit
@testable import Sleepy

final class ThemeColorInterpolationTests: XCTestCase {
    // 独立列举契约，避免生产 slots/scheme 同时漏槽仍能自证通过。
    private let roles: [KeyPath<WakeUpColorScheme, Color>] = [
        \.primary, \.onPrimary, \.primaryContainer, \.onPrimaryContainer,
        \.secondary, \.onSecondary, \.secondaryContainer, \.onSecondaryContainer,
        \.tertiary, \.onTertiary, \.tertiaryContainer, \.onTertiaryContainer,
        \.background, \.onBackground, \.surface, \.onSurface, \.surfaceVariant, \.onSurfaceVariant,
        \.surfaceContainerLowest, \.surfaceContainerLow, \.surfaceContainer,
        \.surfaceContainerHigh, \.surfaceContainerHighest, \.outline, \.outlineVariant, \.scrim,
        \.error, \.onError, \.errorContainer, \.onErrorContainer
    ]

    func testAllThirtySlotsPreserveEndpointsAndRGBAAtMidpoint() {
        let start = ThemeColorVector(components: (0..<120).map { 0.1 + Double($0) / 200 })
        let end = ThemeColorVector(components: start.components.map { 1 - $0 })
        var delta = end - start
        delta.scale(by: 0.5)
        let middle = start + delta
        for vector in [start, middle, end] {
            for (slot, key) in roles.enumerated() {
                let actual = rgba(vector.scheme[keyPath: key])
                for channel in 0..<4 {
                    XCTAssertEqual(actual[channel], vector.components[slot * 4 + channel], accuracy: 0.0001)
                }
            }
            let roundTrip = ThemeColorVector(scheme: vector.scheme, dark: false, increasedContrast: false)
            for (actual, expected) in zip(roundTrip.components, vector.components) {
                XCTAssertEqual(actual, expected, accuracy: 0.0001)
            }
        }
        XCTAssertTrue(middle.components.allSatisfy { abs($0 - 0.5) < 0.0001 })
    }

    func testVectorZeroAndRetargetingFromPresentationValue() {
        let start = ThemeColorVector(scheme: lightScheme, dark: false, increasedContrast: false)
        let end = ThemeColorVector(scheme: darkScheme, dark: true, increasedContrast: false)
        XCTAssertEqual(start + .zero, start)
        XCTAssertEqual(start - start, .zero)
        XCTAssertEqual(ThemeColorVector.zero.components.count, 120)
        var delta = end - start
        delta.scale(by: 0.4)
        let presentation = start + delta
        var modifier = InterpolatedThemeColors(vector: end)
        modifier.animatableData = presentation
        XCTAssertEqual(modifier.vector, presentation)
        var reverse = start - modifier.animatableData
        reverse.scale(by: 0.5)
        let resumed = modifier.animatableData + reverse
        for i in 0..<120 {
            XCTAssertEqual(resumed.components[i], (presentation.components[i] + start.components[i]) / 2,
                           accuracy: 0.000001)
        }
        XCTAssertGreaterThan((end - start).magnitudeSquared, 0)
    }

    func testReduceMotionAlwaysUsesTargetEvenWithAnInheritedAnimation() {
        let target = ThemeColorVector(scheme: darkScheme, dark: true, increasedContrast: false)
        var modifier = InterpolatedThemeColors(vector: target, reduceMotion: true)
        modifier.animatableData = .zero
        XCTAssertEqual(modifier.vector, target)
        XCTAssertEqual(modifier.animatableData, .zero)
    }

    func testDynamicEndpointResolvesExplicitAppearanceAndContrast() {
        let dynamic = UIColor { traits in
            if traits.accessibilityContrast == .high { return .red }
            return traits.userInterfaceStyle == .dark ? .white : .black
        }
        let scheme = lightScheme.replacing(primary: Color(uiColor: dynamic))
        let light = ThemeColorVector(scheme: scheme, dark: false, increasedContrast: false)
        let dark = ThemeColorVector(scheme: scheme, dark: true, increasedContrast: false)
        let high = ThemeColorVector(scheme: scheme, dark: false, increasedContrast: true)
        for i in 0..<3 {
            XCTAssertEqual(light.components[i], 0, accuracy: 0.0001)
            XCTAssertEqual(dark.components[i], 1, accuracy: 0.0001)
            XCTAssertEqual(high.components[i], i == 0 ? 1 : 0, accuracy: 0.0001)
        }
    }

    @MainActor
    func testProviderKeepsFormStateAndSingleAppearanceAcrossThemeInputs() async throws {
        let recorder = ThemeHostRecorder()
        var input = ThemeHostInput()
        input.revision = -1
        let host = UIHostingController(rootView: ThemeHost(input: input, recorder: recorder))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.rootViewController = host
        window.isHidden = false
        defer { recorder.onSample = nil; window.isHidden = true; window.rootViewController = nil }

        for step in 0..<5 {
            input.revision = step
            switch step {
            case 1: input.key = ThemePresets.KEY_OCEAN
            case 2: input.dark = true
            case 3: input.key = ThemePresets.KEY_SYSTEM
            case 4:
                input.version = "same-id-invalidation"
                input.snapshot = .init(seed: .init(red: 20, green: 180, blue: 60),
                    systemDark: true, increasedContrast: false, windowID: "host")
            default: break
            }
            let expected = SleepyThemeProvider.resolve(themeKey: input.key, dark: input.dark,
                snapshot: input.snapshot, increasedContrast: false)
            let expectedRGB = rgba(expected.primary)
            let ready = expectation(description: "theme endpoint \(step)")
            var completed = false
            recorder.onSample = { revision, token, draft, color in
                guard !completed, revision == step, draft == "unsaved edit" else { return }
                let actual = self.rgba(color)
                guard zip(actual, expectedRGB).allSatisfy({ abs($0 - $1) < 0.001 }) else { return }
                completed = true
                if let previous = recorder.token { XCTAssertEqual(previous, token) }
                recorder.token = token
                ready.fulfill()
            }
            host.rootView = ThemeHost(input: input, recorder: recorder)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            await fulfillment(of: [ready], timeout: 3)
            XCTAssertEqual(recorder.appearances, 1)
        }
    }

    private func rgba(_ color: Color) -> [Double] {
        let cg = UIColor(color).cgColor
        let space = CGColorSpace(name: CGColorSpace.extendedSRGB)!
        guard let components = cg.converted(to: space, intent: .relativeColorimetric, options: nil)?.components,
              components.count == 4 else { XCTFail("无法解析测试颜色"); return [0, 0, 0, 0] }
        return components.map { Double($0) }
    }
}

private struct ThemeHostInput {
    var key = ThemePresets.KEY_DEFAULT
    var dark = false
    var version = ""
    var revision = 0
    var snapshot = SystemColorSnapshot.fallback(.noWindow)
}

private final class ThemeHostRecorder {
    var appearances = 0
    var token: UUID?
    var onSample: ((Int, UUID, String, Color) -> Void)?
}

private struct ThemeHost: View {
    let input: ThemeHostInput
    let recorder: ThemeHostRecorder
    var body: some View {
        ThemeStatefulForm(revision: input.revision, recorder: recorder)
            .modifier(SleepyThemeProvider(darkTheme: input.dark, themeKey: input.key,
                                          customThemeVersion: input.version))
            .environment(\.systemColorSnapshot, input.snapshot)
            // colorSchemeContrast and accessibilityReduceMotion are read-only in iOS 26+ / Xcode 16.4+
            // Tests assume system defaults (.standard contrast, motion enabled)
    }
}

private struct ThemeStatefulForm: View {
    @Environment(\.localWakeUpColors) private var colors
    @State private var token = UUID()
    @State private var draft = ""
    let revision: Int
    let recorder: ThemeHostRecorder
    var body: some View {
        TextField("Draft", text: $draft)
            .foregroundColor(colors.primary)
            .background(ThemeHostSample(revision: revision, token: token, draft: draft,
                                        color: colors.primary, recorder: recorder))
            .onAppear { recorder.appearances += 1; draft = "unsaved edit" }
    }
}

private struct ThemeHostSample: UIViewRepresentable {
    let revision: Int
    let token: UUID
    let draft: String
    let color: Color
    let recorder: ThemeHostRecorder
    func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }
    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async { recorder.onSample?(revision, token, draft, color) }
    }
}
