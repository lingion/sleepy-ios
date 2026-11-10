import XCTest
import SwiftUI
import UIKit
@testable import Sleepy

final class SleepyControlsGeometryTests: XCTestCase {
    private struct ButtonSurfaceProbe: UIViewRepresentable {
        @Environment(\.sleepyNativeButtonSurface) private var nativeSurface
        let observe: (Bool) -> Void
        func makeUIView(context: Context) -> UIView { UIView() }
        func updateUIView(_ uiView: UIView, context: Context) { observe(nativeSurface) }
    }

    @MainActor
    func testPlatformButtonInstallsResolvedNativeStyleOnItsLabel() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        for style: SleepyUIStyle in [.classic, .liquidGlass] {
            for prominent in [false, true] {
                var observed: Bool?
                let content = Button(action: {}) {
                    Text("Action")
                        .background(ButtonSurfaceProbe { observed = $0 })
                        .padding(8)
                }
                .buttonStyle(SleepyPlatformButtonStyle(prominent: prominent))
                .environment(\.sleepyUIStyle, style)
                .padding(16).frame(width: 240, height: 80).ignoresSafeArea()
                let window = UIWindow(windowScene: scene)
                let host = UIHostingController(rootView: content)
                window.rootViewController = host
                window.frame = CGRect(x: 0, y: 0, width: 240, height: 80)
                window.isHidden = false
                defer { window.isHidden = true }
                host.view.frame = window.bounds
                host.view.layoutIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                XCTAssertEqual(observed, style == .liquidGlass,
                               "Nested styles must receive the resolved material and suppress duplicate label surfaces")
                if style == .liquidGlass {
                    let picture = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                        host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                    }
                    let attachment = XCTAttachment(image: picture)
                    attachment.name = "native-button-\(prominent ? "prominent" : "regular")"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    @MainActor
    func testNativeIconButtonRendersAsADiscWithinItsTouchSlot() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Native glass requires iOS 26") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        var buttonSize: CGSize = .zero
        let content = Button(action: {}) {
            AndroidMaterialIcon(name: .add, size: 20).foregroundColor(.white)
        }
        .buttonStyle(SleepyActionButtonStyle(prominent: true, compact: true, shape: .circle))
        .tint(.red)
        .background(GeometryReader { geometry in
            Color.clear.onAppear { buttonSize = geometry.size }
        })
        .frame(width: 48, height: 48)
        .environment(\.sleepyUIStyle, .liquidGlass)
        .environment(\.colorScheme, .light)
        .frame(width: 96, height: 96)
        .background(Color.white)
        .ignoresSafeArea()
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: content)
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 96, height: 96)
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        // The native style has asymmetric layout insets around a circular optical disc.
        // Validate its actual pixels below rather than equating its layout box with its border.
        XCTAssertGreaterThanOrEqual(min(buttonSize.width, buttonSize.height), 28)
        XCTAssertGreaterThanOrEqual(min(buttonSize.width, buttonSize.height), 44,
                                    "The native action retains a real 44-point touch target")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let picture = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: picture)
        attachment.name = "native-circular-icon-button"
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = try XCTUnwrap(picture.cgImage)
        var bytes = [UInt8](repeating: 0, count: 96 * 96 * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 96, height: 96,
                bitsPerComponent: 8, bytesPerRow: 96 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 96, height: 96))
        }
        let red = (0..<96).flatMap { y in
            (0..<96).compactMap { x -> CGPoint? in
                let offset = (y * 96 + x) * 4
                return Int(bytes[offset]) - Int(bytes[offset + 1]) > 80
                    && Int(bytes[offset]) - Int(bytes[offset + 2]) > 80
                    ? CGPoint(x: CGFloat(x), y: CGFloat(y)) : nil
            }
        }
        let minX = try XCTUnwrap(red.map(\.x).min())
        let maxX = try XCTUnwrap(red.map(\.x).max())
        let minY = try XCTUnwrap(red.map(\.y).min())
        let maxY = try XCTUnwrap(red.map(\.y).max())
        let width = maxX - minX + 1
        let height = maxY - minY + 1
        XCTAssertEqual(width, height, accuracy: 1)
        XCTAssertGreaterThanOrEqual(width, 43)
        XCTAssertLessThanOrEqual(width, 48)
        let corner = red.filter { point in
            (point.x < minX + width * 0.10 || point.x > maxX - width * 0.10)
                && (point.y < minY + height * 0.10 || point.y > maxY - height * 0.10)
        }
        XCTAssertTrue(corner.isEmpty, "A circular glass disc leaves all four bounding-box corners clear")
    }

    @MainActor
    func testGlassSegmentedPickerUsesNativeSegmentedControl() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let content = SegmentedSwitcher(options: [(0, "One"), (1, "Two")], selected: 1, onSelect: { _ in })
            .environment(\.sleepyUIStyle, .liquidGlass)
            .padding(8).frame(width: 240, height: 64).ignoresSafeArea()
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: content)
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 240, height: 64)
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        func find(in view: UIView) -> [UISegmentedControl] {
            (view as? UISegmentedControl).map { [$0] } ?? view.subviews.flatMap { find(in: $0) }
        }
        let controls = find(in: host.view)
        XCTAssertEqual(controls.count, 1)
        let control = try XCTUnwrap(controls.first)
        XCTAssertEqual(control.numberOfSegments, 2)
        XCTAssertEqual(control.selectedSegmentIndex, 1)
        XCTAssertEqual(control.titleForSegment(at: 0), "One")
    }

    @MainActor
    func testGlassToggleUsesNativeSwitchForBothDirectionsAndDisabledStates() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        for on in [false, true] {
            for direction: LayoutDirection in [.leftToRight, .rightToLeft] {
                for enabled in [true, false] {
                    let content = Toggle("Switch", isOn: .constant(on))
                        .toggleStyle(SleepyToggleStyle(showsLabel: true))
                        .environment(\.sleepyUIStyle, .liquidGlass)
                        .environment(\.layoutDirection, direction)
                        .environment(\.colorScheme, .light)
                        .disabled(!enabled)
                        .padding(8)
                        .frame(width: 240, height: 64)
                        .background(Color.white)
                        .ignoresSafeArea()
                    let window = UIWindow(windowScene: scene)
                    let host = UIHostingController(rootView: content)
                    window.rootViewController = host
                    window.frame = CGRect(x: 0, y: 0, width: 240, height: 64)
                    window.isHidden = false
                    defer { window.isHidden = true }
                    host.view.frame = window.bounds
                    host.view.setNeedsLayout()
                    host.view.layoutIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                    func nativeSwitches(in view: UIView) -> [UISwitch] {
                        (view as? UISwitch).map { [$0] } ?? view.subviews.flatMap { nativeSwitches(in: $0) }
                    }
                    let switches = nativeSwitches(in: host.view)
                    XCTAssertEqual(switches.count, 1, "The platform owns the complete switch instead of a custom lens")
                    let control = try XCTUnwrap(switches.first)
                    XCTAssertEqual(control.isOn, on)
                    XCTAssertEqual(control.isEnabled, enabled)
                    XCTAssertGreaterThan(control.bounds.width, 40)
                    XCTAssertGreaterThan(control.bounds.height, 20)
                    if enabled {
                        let picture = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                        }
                        let attachment = XCTAttachment(image: picture)
                        attachment.name = "native-switch-\(on ? "on" : "off")-\(direction == .rightToLeft ? "rtl" : "ltr")"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                }
            }
        }
    }

    @MainActor
    func testClassicToggleRendersMaterialTrackAndThumbInBothDirections() throws {
        for on in [false, true] {
            for direction: LayoutDirection in [.leftToRight, .rightToLeft] {
                for enabled in [true, false] {
                    let state = "\(on ? "on" : "off")-\(direction == .rightToLeft ? "rtl" : "ltr")-\(enabled ? "enabled" : "disabled")"
                    let pixels = try renderClassicToggle(on: on, direction: direction, enabled: enabled)
                    let colored = (0..<64).flatMap { y in
                        (0..<96).compactMap { x -> CGPoint? in
                            let pixel = pixels[y * 96 + x]
                            return max(255 - pixel.0, 255 - pixel.1, 255 - pixel.2) > 8
                                ? CGPoint(x: CGFloat(x), y: CGFloat(y)) : nil
                        }
                    }
                    let minX = try XCTUnwrap(colored.map(\.x).min())
                    let maxX = try XCTUnwrap(colored.map(\.x).max())
                    let minY = try XCTUnwrap(colored.map(\.y).min())
                    let maxY = try XCTUnwrap(colored.map(\.y).max())
                    XCTAssertEqual(maxX - minX + 1, 52, accuracy: 1, state)
                    XCTAssertEqual(maxY - minY + 1, 32, accuracy: 1, state)

                    let thumbX = direction == .rightToLeft ? (on ? 38 : 58) : (on ? 58 : 38)
                    let thumb: (Int, Int, Int) = enabled
                        ? (on ? (255, 255, 255) : (121, 116, 126))
                        : (on ? (254, 247, 255) : (169, 163, 170))
                    let thumbPixels = (19...44).filter { y in
                        let pixel = pixels[y * 96 + thumbX]
                        return abs(pixel.0 - thumb.0) <= 2 && abs(pixel.1 - thumb.1) <= 2 && abs(pixel.2 - thumb.2) <= 2
                    }
                    XCTAssertEqual(Double(thumbPixels.count), on ? 24 : 16, accuracy: 2,
                                   "\(state): Material changes the resting thumb size and mirrors its position in RTL")
                    let track = pixels[32 * 96 + 48]
                    let expectedTrack: (Int, Int, Int) = enabled
                        ? (on ? (103, 80, 164) : (230, 224, 233))
                        : (on ? (227, 221, 228) : (251, 244, 252))
                    // The center is covered by the selected thumb; the opposite side stays track.
                    let clearTrack = pixels[32 * 96 + (thumbX == 58 ? 29 : 67)]
                    let actualTrack = on ? clearTrack : track
                    XCTAssertLessThanOrEqual(abs(actualTrack.0 - expectedTrack.0), 2, state)
                    XCTAssertLessThanOrEqual(abs(actualTrack.1 - expectedTrack.1), 2, state)
                    XCTAssertLessThanOrEqual(abs(actualTrack.2 - expectedTrack.2), 2, state)
                }
            }
        }
    }

    @MainActor
    func testClassicToggleRespectsMaterialDisabledBorderOverride() throws {
        for opacity in [0.38, 0.12] {
            let pixels = try renderClassicToggle(on: false, direction: .leftToRight,
                                                enabled: false, disabledBorderOpacity: opacity)
            let border = pixels[32 * 96 + 23]
            let expected = opacity == 0.38 ? (169, 163, 170) : (227, 221, 228)
            XCTAssertLessThanOrEqual(abs(border.0 - expected.0), 2)
            XCTAssertLessThanOrEqual(abs(border.1 - expected.1), 2)
            XCTAssertLessThanOrEqual(abs(border.2 - expected.2), 2)
        }
    }

    @MainActor
    private func renderClassicToggle(on: Bool, direction: LayoutDirection, enabled: Bool,
                                     disabledBorderOpacity: Double = 0.38) throws -> [(Int, Int, Int)] {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let content = Toggle("Switch", isOn: .constant(on))
            .toggleStyle(SleepyToggleStyle(disabledUncheckedBorderOpacity: disabledBorderOpacity))
            .environment(\.sleepyUIStyle, .classic)
            .environment(\.localWakeUpColors, lightScheme)
            .environment(\.layoutDirection, direction)
            .environment(\.colorScheme, .light)
            .disabled(!enabled)
            .frame(width: 96, height: 64)
            .background(Color.white)
            .ignoresSafeArea()
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: content)
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 96, height: 64)
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let picture = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: picture)
        attachment.name = "classic-switch-\(on ? "on" : "off")-\(direction == .rightToLeft ? "rtl" : "ltr")-\(enabled ? "enabled" : "disabled")-border\(disabledBorderOpacity)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = try XCTUnwrap(picture.cgImage)
        var bytes = [UInt8](repeating: 0, count: 96 * 64 * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 96, height: 64,
                bitsPerComponent: 8, bytesPerRow: 96 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 96, height: 64))
        }
        return stride(from: 0, to: bytes.count, by: 4).map {
            (Int(bytes[$0]), Int(bytes[$0 + 1]), Int(bytes[$0 + 2]))
        }
    }
}
