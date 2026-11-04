import XCTest
import UIKit
import SwiftUI
@testable import Sleepy

final class SystemColorProbeTests: XCTestCase {
    @MainActor
    func testActiveKeyWindowOwnershipForegroundRefreshAndSharedDeduplication() throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            throw XCTSkip("此 CI 宿主没有 foregroundActive UIWindowScene；需原生生命周期验收")
        }
        let suite = "SystemColorWindowOwnership.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let previousKey = scene.windows.first(where: \.isKeyWindow)
        let a = UIWindow(windowScene: scene), b = UIWindow(windowScene: scene)
        a.rootViewController = UIViewController()
        b.rootViewController = UIViewController()
        a.tintColor = .red
        b.tintColor = .blue
        let first = SystemColorProbeView(), second = SystemColorProbeView()
        var published: [SystemColorSnapshot] = []
        let publish: (SystemColorSnapshot) -> Void = { value in
            if SystemColorSeedStore.write(value, to: defaults) { published.append(value) }
        }
        first.publishShared = publish
        second.publishShared = publish
        defer {
            first.stop(); second.stop()
            a.isHidden = true; b.isHidden = true
            previousKey?.makeKey()
            defaults.removePersistentDomain(forName: suite)
        }
        a.addSubview(first)
        b.addSubview(second)
        a.makeKeyAndVisible()
        first.refresh()
        first.refresh()
        XCTAssertEqual(published.count, 1)
        b.makeKeyAndVisible()
        second.refresh()
        let blue = try XCTUnwrap(published.last)
        first.refresh()
        XCTAssertEqual(published.count, 2)
        XCTAssertEqual(SystemColorSeedStore.read(from: defaults), blue)
        // 外窗 key 通知不能令 first 争抢共享所有权。
        NotificationCenter.default.post(name: UIWindow.didBecomeKeyNotification, object: b)
        first.refresh()
        XCTAssertEqual(published.count, 2)
        a.makeKey()
        first.refresh()
        XCTAssertEqual(published.count, 3)
        XCTAssertEqual(published.last?.seed, SystemSeedRGB(red: 255, green: 0, blue: 0))
        NotificationCenter.default.post(name: UIScene.didActivateNotification, object: scene)
        first.refresh()
        second.refresh()
        XCTAssertEqual(published.count, 3, "前台重采样相同值不重复写入")
        a.tintColor = .green
        NotificationCenter.default.post(name: UIScene.didActivateNotification, object: scene)
        first.refresh()
        XCTAssertEqual(published.last?.seed, SystemSeedRGB(red: 0, green: 255, blue: 0))
        XCTAssertEqual(published.count, 4)
    }

    @MainActor
    func testSamplesOwnWindowAndNeverTheGeneratedChildTint() throws {
        let a = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let b = UIWindow(frame: a.frame)
        a.tintColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        b.tintColor = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
        let generatedContainer = UIView()
        generatedContainer.tintColor = .green
        let probe = SystemColorProbeView()
        var publications: [SystemColorSnapshot] = []
        var sharedPublications = 0
        probe.onSnapshot = { publications.append($0) }
        probe.publishShared = { _ in sharedPublications += 1 }
        defer { probe.stop() }
        a.addSubview(generatedContainer)
        generatedContainer.addSubview(probe)
        probe.refresh()
        XCTAssertEqual(publications.last?.seed, SystemSeedRGB(red: 255, green: 0, blue: 0))
        let first = try XCTUnwrap(publications.last)
        probe.refresh()
        generatedContainer.tintColor = .yellow
        probe.refresh()
        XCTAssertEqual(publications.count, 1, "自己生成的 tint 不应反馈为新 seed")
        b.addSubview(probe)
        probe.refresh()
        XCTAssertEqual(publications.last?.seed, SystemSeedRGB(red: 0, green: 0, blue: 255))
        XCTAssertNotEqual(publications.last?.windowID, first.windowID)
        XCTAssertEqual(sharedPublications, 0, "非 active key window 不应覆盖共享快照")
    }

    @MainActor
    func testDimmingRetainsStableSampleAndRestoringPublishesNewTint() throws {
        let window = UIWindow(frame: .zero)
        window.tintColor = .red
        let probe = SystemColorProbeView()
        probe.publishShared = { _ in XCTFail("无 active scene 的窗口不得发布") }
        var values: [SystemColorSnapshot] = []
        probe.onSnapshot = { values.append($0) }
        defer { probe.stop() }
        window.addSubview(probe)
        probe.refresh()
        let stable = try XCTUnwrap(values.last)
        window.tintAdjustmentMode = .dimmed
        window.tintColor = .blue
        probe.refresh()
        XCTAssertEqual(values.last, stable)
        XCTAssertEqual(values.count, 1)
        window.tintAdjustmentMode = .normal
        probe.refresh()
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(values.last?.seed, SystemSeedRGB(red: 0, green: 0, blue: 255))
    }

    @MainActor
    func testDetachInvalidColorAndStopHaveExplicitSemantics() {
        let window = UIWindow(frame: .zero)
        window.tintColor = UIColor.white.withAlphaComponent(0.2)
        let probe = SystemColorProbeView()
        var values: [SystemColorSnapshot] = []
        probe.onSnapshot = { values.append($0) }
        window.addSubview(probe)
        probe.refresh()
        XCTAssertEqual(values.last?.fallbackReason, .invalidColor)
        probe.removeFromSuperview()
        probe.refresh()
        XCTAssertEqual(values.last?.fallbackReason, .noWindow)
        let count = values.count
        probe.stop()
        probe.refresh()
        XCTAssertEqual(values.count, count)
    }

    @MainActor
    func testPublicColorResolutionRespectsTraitsAndSRGB() throws {
        let dynamic = UIColor { traits in traits.userInterfaceStyle == .dark ? .white : .black }
        let window = UIWindow(frame: .zero)
        window.tintColor = dynamic
        window.overrideUserInterfaceStyle = .dark
        XCTAssertEqual(SystemColorProbeView.sample(window: window)?.seed,
                       SystemSeedRGB(red: 255, green: 255, blue: 255))
        window.overrideUserInterfaceStyle = .light
        XCTAssertEqual(SystemColorProbeView.sample(window: window)?.seed,
                       SystemSeedRGB(red: 0, green: 0, blue: 0))
        let neutral = try XCTUnwrap(SystemColorProbeView.rgb(UIColor(white: 0.5, alpha: 1)))
        XCTAssertEqual(neutral.red, neutral.green)
        XCTAssertEqual(neutral.green, neutral.blue)
        XCTAssertNotNil(SystemColorProbeView.rgb(UIColor(displayP3Red: 1, green: 0.2, blue: 0, alpha: 1)))
    }
}
