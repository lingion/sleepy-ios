import SwiftUI
import UIKit
import XCTest
@testable import Sleepy

@MainActor
final class NativeWeekPagerTests: XCTestCase {
    func testRapidRequestsFinishAtLatestWeekWithoutPublishingIntermediateSelections() async {
        let harness = Harness()
        defer { harness.close() }
        harness.update(1)
        await flushMainQueue()

        harness.update(2)
        harness.update(5)
        harness.update(9)
        XCTAssertEqual(harness.controller.requests.count, 2)
        XCTAssertEqual(harness.controller.pendingCount, 1)
        XCTAssertTrue(harness.controller.requests.last!.animated)
        XCTAssertTrue(harness.selections.isEmpty)

        harness.controller.finishTransition()
        await flushMainQueue()
        XCTAssertEqual(harness.controller.requests.count, 3)
        XCTAssertEqual(harness.displayedWeek, 9)
        XCTAssertTrue(harness.selections.isEmpty)

        harness.controller.finishTransition()
        await flushMainQueue()
        XCTAssertEqual(harness.controller.requests.count, 3)
        XCTAssertEqual(harness.displayedWeek, 9)
        XCTAssertTrue(harness.selections.isEmpty)
    }

    func testShorterSemesterClampsQueuedSelectionAfterAnOldLongWeekFinishes() async {
        let harness = Harness()
        defer { harness.close() }
        harness.update(1)
        await flushMainQueue()

        harness.update(20)
        harness.update(20, maxWeek: 3)
        XCTAssertEqual(harness.controller.requests.count, 2)
        harness.controller.finishTransition()
        await flushMainQueue()

        XCTAssertEqual(harness.controller.requests.count, 3)
        XCTAssertEqual(harness.displayedWeek, 3)
        XCTAssertEqual(harness.controller.requests.last!.direction, .reverse)
        harness.controller.finishTransition()
        await flushMainQueue()
        XCTAssertEqual(harness.controller.requests.count, 3)
        XCTAssertTrue(harness.selections.isEmpty)
    }

    func testInvalidationStopsBothOldCompletionsAndAlreadyScheduledPaging() async {
        for invalidateBeforeCompletion in [true, false] {
            let harness = Harness()
            defer { harness.close() }
            harness.update(1)
            await flushMainQueue()
            harness.update(2)
            harness.update(9)

            if invalidateBeforeCompletion { harness.coordinator.invalidate() }
            harness.controller.finishTransition()
            if !invalidateBeforeCompletion { harness.coordinator.invalidate() }
            await flushMainQueue()
            harness.update(10)

            XCTAssertEqual(harness.controller.requests.count, 2)
            XCTAssertTrue(harness.selections.isEmpty)
        }
    }

    private func flushMainQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @MainActor private final class TrackingPageController: UIPageViewController {
        struct Request {
            let direction: NavigationDirection
            let animated: Bool
        }
        var requests: [Request] = []
        private var completions: [(Bool) -> Void] = []
        var pendingCount: Int { completions.count }

        override func setViewControllers(_ viewControllers: [UIViewController]?, direction: NavigationDirection,
                                         animated: Bool, completion: ((Bool) -> Void)? = nil) {
            requests.append(Request(direction: direction, animated: animated))
            // Install real page content immediately. Hold only the completion so
            // tests can interleave model changes without wall-clock animation waits.
            super.setViewControllers(viewControllers, direction: direction, animated: false, completion: nil)
            if animated, let completion { completions.append(completion) }
            else { completion?(true) }
        }

        func finishTransition() {
            XCTAssertFalse(completions.isEmpty)
            guard !completions.isEmpty else { return }
            completions.removeFirst()(true)
        }

        func clearTransitions() { completions.removeAll() }
    }

    private struct PageMarker: UIViewRepresentable {
        let week: Int
        func makeUIView(context: Context) -> UILabel { UILabel() }
        func updateUIView(_ view: UILabel, context: Context) {
            view.text = String(week)
            view.accessibilityIdentifier = "native-week-pager-test-page"
        }
    }

    @MainActor private final class Harness {
        typealias Pager = NativeWeekPager<PageMarker>
        let controller = TrackingPageController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        let coordinator = Pager.Coordinator()
        private let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        var selections: [Int] = []

        init() {
            coordinator.controller = controller
            controller.delegate = coordinator
            controller.dataSource = coordinator
            window.rootViewController = controller
            // This dedicated window must never become the app's key window.
            window.isHidden = false
            controller.view.layoutIfNeeded()
        }

        func update(_ week: Int, maxWeek: Int = 20) {
            coordinator.update(Pager(selection: week, maxWeek: maxWeek,
                onSelect: { [weak self] in self?.selections.append($0) },
                content: { PageMarker(week: $0) }), environment: EnvironmentValues())
        }

        var displayedWeek: Int? {
            guard let host = controller.viewControllers?.first else { return nil }
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            func marker(in view: UIView) -> UILabel? {
                if let label = view as? UILabel,
                   label.accessibilityIdentifier == "native-week-pager-test-page" { return label }
                return view.subviews.lazy.compactMap { marker(in: $0) }.first
            }
            return marker(in: host.view)?.text.flatMap(Int.init)
        }

        func close() {
            coordinator.invalidate()
            controller.delegate = nil
            controller.dataSource = nil
            controller.clearTransitions()
            window.isHidden = true
            window.rootViewController = nil
        }
    }
}
