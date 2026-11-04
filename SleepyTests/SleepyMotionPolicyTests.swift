import XCTest
import UIKit
@testable import Sleepy

final class SleepyMotionPolicyTests: XCTestCase {
    func testReducedMotionRemovesSpatialChangesButKeepsEffects() {
        let motion = SleepyMotionPolicy(reduceMotion: true)
        XCTAssertEqual(motion.popupScale, 1)
        XCTAssertEqual(motion.contentScale, 1)
        XCTAssertEqual(motion.pressScale(pressed: true), 1)
        XCTAssertNil(motion.fastSpatial)
        XCTAssertNil(motion.defaultSpatial)
        XCTAssertNil(motion.thumb)
    }

    func testPressExcludesDisabledAndDragSources() {
        let motion = SleepyMotionPolicy(reduceMotion: false)
        XCTAssertEqual(motion.pressScale(pressed: true), 0.98, accuracy: 0.0001)
        XCTAssertEqual(motion.pressScale(pressed: false), 1)
        XCTAssertEqual(motion.pressScale(pressed: true, enabled: false), 1)
        XCTAssertEqual(motion.pressScale(pressed: true, dragSource: true), 1)
    }

    @MainActor
    func testGhostRemovalRetainsLastBaselineInsteadOfJumpingToCurrentValue() {
        let view = BaselineSliderView(frame: CGRect(x: 0, y: 0, width: 300, height: 44))
        view.slider.value = 0.9
        view.updateGhost(baseline: 0.3, visible: true, reduceMotion: false)
        view.updateGhost(baseline: nil, visible: false, reduceMotion: false)
        XCTAssertEqual(view.ghost.value, 0.3, accuracy: 0.0001)
        XCTAssertTrue(view.ghost.isHidden)
        XCTAssertFalse(view.ghost.isUserInteractionEnabled)
        XCTAssertTrue(view.ghost.accessibilityElementsHidden)
    }

    @MainActor
    func testGhostReappearsAtNewBaselineAndReduceMotionSnaps() {
        let view = BaselineSliderView(frame: CGRect(x: 0, y: 0, width: 300, height: 44))
        view.updateGhost(baseline: 0.3, visible: true, reduceMotion: true)
        view.updateGhost(baseline: nil, visible: false, reduceMotion: true)
        view.updateGhost(baseline: 0.7, visible: true, reduceMotion: true)
        XCTAssertEqual(view.ghost.value, 0.7, accuracy: 0.0001)
        XCTAssertFalse(view.ghost.isHidden)
        XCTAssertTrue(view.ghostVisible)
        XCTAssertEqual(view.ghost.transform, .identity)
        XCTAssertEqual(view.ghost.alpha, 0.35, accuracy: 0.0001)
    }

    @MainActor
    func testGhostLayoutKeepsNativeTrackGeometry() {
        let view = BaselineSliderView(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        view.layoutIfNeeded()
        XCTAssertEqual(view.slider.bounds, view.ghost.bounds)
        XCTAssertEqual(view.slider.center, view.ghost.center)
        view.bounds.size.width = 480
        view.setNeedsLayout()
        view.layoutIfNeeded()
        XCTAssertEqual(view.slider.bounds, view.ghost.bounds)
        XCTAssertEqual(view.slider.center, view.ghost.center)
    }

    @MainActor
    func testInterruptedGhostExitCannotHideNewBaseline() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        let controller = UIViewController()
        window.rootViewController = controller
        let view = BaselineSliderView(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        controller.view.addSubview(view)
        window.isHidden = false
        defer { window.isHidden = true }
        view.layoutIfNeeded()
        view.updateGhost(baseline: 0.2, visible: true, reduceMotion: false)
        view.updateGhost(baseline: nil, visible: false, reduceMotion: false)
        view.updateGhost(baseline: 0.8, visible: true, reduceMotion: false)
        let settled = expectation(description: "被打断的退场回调不能隐藏新 ghost")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertFalse(view.ghost.isHidden)
            XCTAssertEqual(view.ghost.value, 0.8, accuracy: 0.0001)
            XCTAssertEqual(view.ghost.alpha, 0.35, accuracy: 0.0001)
            settled.fulfill()
        }
        wait(for: [settled], timeout: 2)
    }
}
