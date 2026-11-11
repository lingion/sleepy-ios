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

        // Appearance's four localized course-color labels exceed a small phone's
        // width. Check the UIKit surface itself, rather than its SwiftUI frame.
        let longLabels = ["Solid color", "Don't follow theme color", "Follow theme", "Custom"]
        for width: CGFloat in [240, 343] {
            let narrowContent = ScrollView {
                VStack {
                    Text("Appearance & display")
                    SegmentedSwitcher(options: longLabels.enumerated().map { ($0.offset, $0.element) },
                        selected: 1, onSelect: { _ in })
                }
                .padding(8)
            }
            .environment(\.sleepyUIStyle, .liquidGlass)
            .frame(width: width, height: 100).ignoresSafeArea()
            let narrowWindow = UIWindow(windowScene: scene)
            let narrowHost = UIHostingController(rootView: narrowContent)
            narrowWindow.rootViewController = narrowHost
            narrowWindow.frame = CGRect(x: 0, y: 0, width: width, height: 100)
            narrowWindow.isHidden = false
            defer { narrowWindow.isHidden = true }
            narrowHost.view.frame = narrowWindow.bounds
            narrowHost.view.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            let narrowControls = find(in: narrowHost.view)
            XCTAssertEqual(narrowControls.count, 1)
            let narrowControl = try XCTUnwrap(narrowControls.first)
            let renderedFrame = narrowControl.convert(narrowControl.bounds, to: narrowHost.view)
            XCTAssertEqual(renderedFrame.minX, 8, accuracy: 1)
            XCTAssertEqual(renderedFrame.width, width - 16, accuracy: 1,
                           "Long native segment labels must fit the proposed scroll-content width")
            XCTAssertLessThanOrEqual(renderedFrame.maxX, width - 8 + 1)
            XCTAssertEqual(narrowControl.numberOfSegments, longLabels.count)
            XCTAssertEqual(narrowControl.selectedSegmentIndex, 1)
            for (index, label) in longLabels.enumerated() {
                XCTAssertEqual(narrowControl.titleForSegment(at: index), label)
            }
        }
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
                    let colored = (0..<pixels.height).flatMap { y in
                        (0..<pixels.width).compactMap { x -> CGPoint? in
                            let pixel = pixels[x, y]
                            return max(255 - pixel.0, 255 - pixel.1, 255 - pixel.2) > 8
                                ? CGPoint(x: CGFloat(x), y: CGFloat(y)) : nil
                        }
                    }
                    let minX = try XCTUnwrap(colored.map(\.x).min())
                    let maxX = try XCTUnwrap(colored.map(\.x).max())
                    let minY = try XCTUnwrap(colored.map(\.y).min())
                    let maxY = try XCTUnwrap(colored.map(\.y).max())
                    XCTAssertEqual((maxX - minX + 1) / pixels.scale, 52, accuracy: 1, state)
                    XCTAssertEqual((maxY - minY + 1) / pixels.scale, 32, accuracy: 1, state)

                    let leftToRightX = Int(CGFloat(on ? 58 : 38) * pixels.scale)
                    let thumbX = direction == .rightToLeft ? pixels.width - 1 - leftToRightX : leftToRightX
                    let thumb: (Int, Int, Int) = enabled
                        ? (on ? (255, 255, 255) : (121, 116, 126))
                        : (on ? (254, 247, 255) : (169, 163, 170))
                    let actualThumb = pixels[thumbX, Int(32 * pixels.scale)]
                    XCTAssertLessThanOrEqual(abs(actualThumb.0 - thumb.0), 2, state)
                    XCTAssertLessThanOrEqual(abs(actualThumb.1 - thumb.1), 2, state)
                    XCTAssertLessThanOrEqual(abs(actualThumb.2 - thumb.2), 2, state)
                    let track = pixels.atPoint(x: 48, y: 32)
                    let expectedTrack: (Int, Int, Int) = enabled
                        ? (on ? (103, 80, 164) : (230, 224, 233))
                        : (on ? (227, 221, 228) : (251, 244, 252))
                    // The center is covered by the selected thumb; the opposite side stays track.
                    let clearTrack = pixels.atPoint(x: CGFloat(thumbX) / pixels.scale > 48 ? 29 : 67, y: 32)
                    let actualTrack = on ? clearTrack : track
                    XCTAssertLessThanOrEqual(abs(actualTrack.0 - expectedTrack.0), 2, state)
                    XCTAssertLessThanOrEqual(abs(actualTrack.1 - expectedTrack.1), 2, state)
                    XCTAssertLessThanOrEqual(abs(actualTrack.2 - expectedTrack.2), 2, state)

                    // Geometry uses the half-contrast contour. Requiring every
                    // edge pixel to equal the fill RGB measures its flat core,
                    // not its diameter, after drawHierarchy antialiasing.
                    let delta = (Double(actualThumb.0 - actualTrack.0),
                                 Double(actualThumb.1 - actualTrack.1),
                                 Double(actualThumb.2 - actualTrack.2))
                    let contrast = delta.0 * delta.0 + delta.1 * delta.1 + delta.2 * delta.2
                    XCTAssertGreaterThan(contrast, 0, state)
                    let thumbPixels = (Int(19 * pixels.scale)..<Int(45 * pixels.scale)).filter { y in
                        let pixel = pixels[thumbX, y]
                        let projection = Double(pixel.0 - actualTrack.0) * delta.0
                            + Double(pixel.1 - actualTrack.1) * delta.1
                            + Double(pixel.2 - actualTrack.2) * delta.2
                        return projection >= contrast * 0.5
                    }
                    XCTAssertEqual(CGFloat(thumbPixels.count) / pixels.scale, on ? 24 : 16, accuracy: 2,
                                   "\(state): Material changes the resting thumb size and mirrors its position in RTL")
                }
            }
        }
    }

    @MainActor
    func testClassicToggleRespectsMaterialDisabledBorderOverride() throws {
        for opacity in [0.38, 0.12] {
            let pixels = try renderClassicToggle(on: false, direction: .leftToRight,
                                                enabled: false, disabledBorderOpacity: opacity)
            let border = pixels.atPoint(x: 23, y: 32)
            let expected = opacity == 0.38 ? (169, 163, 170) : (227, 221, 228)
            XCTAssertLessThanOrEqual(abs(border.0 - expected.0), 2)
            XCTAssertLessThanOrEqual(abs(border.1 - expected.1), 2)
            XCTAssertLessThanOrEqual(abs(border.2 - expected.2), 2)
        }
    }

    @MainActor
    private func renderClassicToggle(on: Bool, direction: LayoutDirection, enabled: Bool,
                                     disabledBorderOpacity: Double = 0.38) throws -> ToggleRaster {
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
        // Capture at the display scale: a 2pt stroke needs interior pixels.
        // Reducing the screen hierarchy to 1x bakes ringing into every stroke.
        format.scale = window.screen.scale
        format.preferredRange = .standard
        let picture = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: picture)
        attachment.name = "classic-switch-\(on ? "on" : "off")-\(direction == .rightToLeft ? "rtl" : "ltr")-\(enabled ? "enabled" : "disabled")-border\(disabledBorderOpacity)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = try XCTUnwrap(picture.cgImage)
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let values = stride(from: 0, to: bytes.count, by: 4).map {
            (Int(bytes[$0]), Int(bytes[$0 + 1]), Int(bytes[$0 + 2]))
        }
        return ToggleRaster(width: width, height: height, scale: picture.scale, values: values)
    }

    private struct ToggleRaster {
        let width: Int
        let height: Int
        let scale: CGFloat
        let values: [(Int, Int, Int)]

        subscript(x: Int, y: Int) -> (Int, Int, Int) { values[y * width + x] }
        func atPoint(x: CGFloat, y: CGFloat) -> (Int, Int, Int) {
            self[Int(x * scale), Int(y * scale)]
        }
    }
}
