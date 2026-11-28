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

    func testLegacySafeAreaPolyfillClearsSafeAreaInsetsAndAllowsDeallocation() async throws {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        weak var weakHost: UIViewController?
        weak var weakView: UIView?
        do {
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 414, height: 736))
            window.frame = CGRect(x: 0, y: 0, width: 414, height: 736)
            let host = UIHostingController(rootView: AnyView(
                GeometryReader { _ in
                    ScrollView(.vertical) {
                        Color.yellow.frame(height: 900)
                    }
                    .padding(8)
                }
                .background(Color.gray)
            ))
            SleepyLegacyHostingSafeArea.disable(for: host.view)
            SleepyLegacyHostingSafeArea.disable(for: host.view) // Idempotent when called twice.
            weakHost = host
            weakView = host.view
            window.rootViewController = host
            window.isHidden = false
            for _ in 0..<10 {
                await flushMainQueue()
                RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            }
            XCTAssertEqual(host.view.safeAreaInsets, .zero)
            func firstScrollView(in view: UIView) -> UIScrollView? {
                if let s = view as? UIScrollView { return s }
                return view.subviews.lazy.compactMap { firstScrollView(in: $0) }.first
            }
            let scroll = try XCTUnwrap(firstScrollView(in: host.view))
            XCTAssertEqual(scroll.convert(scroll.bounds, to: host.view).minY, 8, accuracy: 1)
            XCTAssertEqual(scroll.bounds.height, host.view.bounds.height - 16, accuracy: 1)
            window.isHidden = true
            window.rootViewController = nil
        }
        await flushMainQueue()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertNil(weakHost)
        XCTAssertNil(weakView)
    }

    func testPagingControllerPreservesTopOriginAndQueueScrollBehaviorDuringTransition() async throws {
        let db = try AppDatabase.inMemory()
        var t = TimeTableEntity(name: "PagerTable", startDate: "2026-11-02", maxWeek: 20)
        t.id = try db.timeTableDao.insert(t)
        try db.timeTableDao.setDefault(t.id)
        try db.courseDao.insert(CourseEntity(groupId: "g1", tableId: t.id, courseName: "高数",
            day: 1, startNode: 1, step: 2, startWeek: 1, endWeek: 20, type: 0, color: "#FF6750A4"))
        let repo = ScheduleRepository(db)
        let rootVM = AppRootViewModel(repository: repo)
        rootVM.scheduleViewMode = .cards
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 414, height: 736))
        window.frame = CGRect(x: 0, y: 0, width: 414, height: 736)
        let rootHost = UIHostingController(rootView: AppRoot().environmentObject(rootVM))
        window.rootViewController = rootHost
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        func findPager(_ v: UIView) -> UIPageViewController? {
            if let pvc = v.next as? UIPageViewController { return pvc }
            for c in v.subviews { if let p = findPager(c) { return p } }
            return nil
        }
        for _ in 0..<40 {
            await flushMainQueue()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if rootVM.scheduleViewModel.state.tables.count == 1,
               let pvc = findPager(window),
               let cur = pvc.viewControllers?.first,
               pvc.dataSource?.pageViewController(pvc, viewControllerAfter: cur) != nil {
                break
            }
        }
        let pvc = try XCTUnwrap(findPager(window))
        XCTAssertFalse(pvc.automaticallyAdjustsScrollViewInsets)
        let queueScroll = try XCTUnwrap(pvc.view.subviews.compactMap { $0 as? UIScrollView }.first)
        XCTAssertEqual(queueScroll.contentInsetAdjustmentBehavior, .never)
        XCTAssertFalse(queueScroll.alwaysBounceVertical)
        XCTAssertEqual(queueScroll.contentOffset.y, 0, accuracy: 0.5)
        XCTAssertEqual(queueScroll.contentInset.top, 0, accuracy: 0.5)

        let cur = try XCTUnwrap(pvc.viewControllers?.first)
        func firstScrollView(in view: UIView) -> UIScrollView? {
            if let s = view as? UIScrollView { return s }
            return view.subviews.lazy.compactMap { firstScrollView(in: $0) }.first
        }
        let curScroll = try XCTUnwrap(firstScrollView(in: cur.view))
        XCTAssertEqual(curScroll.convert(curScroll.bounds, to: cur.view).minY, 8, accuracy: 1)
        XCTAssertEqual(curScroll.bounds.height, cur.view.bounds.height - 16, accuracy: 1)
        XCTAssertEqual(curScroll.adjustedContentInset, .zero)

        let ds = try XCTUnwrap(pvc.dataSource)
        let nextVC = try XCTUnwrap(ds.pageViewController(pvc, viewControllerAfter: cur))
        pvc.delegate?.pageViewController?(pvc, willTransitionTo: [nextVC])
        pvc.setViewControllers([nextVC], direction: .forward, animated: true, completion: nil)
        for _ in 0..<12 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.04))
            XCTAssertEqual(queueScroll.contentOffset.y, 0, accuracy: 0.5)
            XCTAssertEqual(queueScroll.contentInset.top, 0, accuracy: 0.5)
            XCTAssertEqual(nextVC.view.safeAreaInsets.top, 0, accuracy: 0.5)
            if let nextScroll = firstScrollView(in: nextVC.view) {
                XCTAssertEqual(nextScroll.convert(nextScroll.bounds, to: nextVC.view).minY, 8, accuracy: 1)
                XCTAssertEqual(nextScroll.bounds.height, nextVC.view.bounds.height - 16, accuracy: 1)
                XCTAssertEqual(nextScroll.adjustedContentInset, .zero)
            }
        }
    }

    func testNavigationHostKeepsNavigationBarHiddenAcrossHostingBarRequestsAndPaging() async throws {
        let db = try AppDatabase.inMemory()
        var t = TimeTableEntity(name: "NavBarTable", startDate: "2026-11-02", maxWeek: 20)
        t.id = try db.timeTableDao.insert(t)
        try db.timeTableDao.setDefault(t.id)
        try db.courseDao.insert(CourseEntity(groupId: "g1", tableId: t.id, courseName: "高数",
            day: 1, startNode: 1, step: 2, startWeek: 1, endWeek: 20, type: 0, color: "#FF6750A4"))
        let repo = ScheduleRepository(db)
        let rootVM = AppRootViewModel(repository: repo)
        rootVM.scheduleViewMode = .cards
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 414, height: 736))
        window.frame = CGRect(x: 0, y: 0, width: 414, height: 736)
        let rootHost = UIHostingController(rootView: AppRoot().environmentObject(rootVM))
        window.rootViewController = rootHost
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        func find<T>(_ type: T.Type, in view: UIView) -> T? {
            if let match = view.next as? T { return match }
            for child in view.subviews {
                if let match = find(type, in: child) { return match }
            }
            return nil
        }

        for _ in 0..<40 {
            await flushMainQueue()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if rootVM.scheduleViewModel.state.tables.count == 1,
               find(UIPageViewController.self, in: window)?.viewControllers?.first != nil,
               find(UINavigationController.self, in: window) != nil {
                break
            }
        }
        let nav = try XCTUnwrap(find(UINavigationController.self, in: window))
        let pvc = try XCTUnwrap(find(UIPageViewController.self, in: window))
        let baselineTop = pvc.view.convert(pvc.view.bounds, to: window).minY

        // Simulate iOS 15 UIHostingController pushing its default navigationBarHidden=false onto ancestor UINavigationController.
        nav.setNavigationBarHidden(false, animated: true)
        nav.isNavigationBarHidden = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertTrue(nav.isNavigationBarHidden,
                      "SleepyNativeNavigationHost must keep UINavigationBar hidden even when a child hosting controller attempts to show it")
        XCTAssertEqual(pvc.view.convert(pvc.view.bounds, to: window).minY, baselineTop, accuracy: 0.5)
    }
}
