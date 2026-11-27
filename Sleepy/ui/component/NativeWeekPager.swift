import SwiftUI
import UIKit

/// Keep native swipe paging and make programmatic week changes explicitly animated.
/// The parent owns week selection; intermediate animation completions never publish it.
struct NativeWeekPager<Content: View>: UIViewControllerRepresentable {
    let selection: Int
    let maxWeek: Int
    var animationsEnabled = true
    let onSelect: (Int) -> Void
    @ViewBuilder let content: (Int) -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(transitionStyle: .scroll,
            navigationOrientation: .horizontal)
        controller.view.backgroundColor = .clear
        controller.view.isOpaque = false
        controller.view.clipsToBounds = true
        controller.view.accessibilityIdentifier = "schedule_week_pager"
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        context.coordinator.controller = controller
        if let scrollView = controller.view.subviews.compactMap({ $0 as? UIScrollView }).first {
            context.coordinator.attachFallbackPan(to: controller, scrollView: scrollView)
        }
        context.coordinator.update(self, environment: context.environment)
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.update(self, environment: context.environment)
    }

    static func dismantleUIViewController(_ controller: UIPageViewController, coordinator: Coordinator) {
        coordinator.invalidate()
        controller.delegate = nil
        controller.dataSource = nil
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        weak var controller: UIPageViewController?
        private weak var pagerScrollView: UIScrollView?
        private weak var fallbackPan: PagerFallbackPanGestureRecognizer?
        private var parent: NativeWeekPager?
        private var environment = EnvironmentValues()
        private var hosts: [Int: PageHost] = [:]
        private var requestedWeek = 1
        private var weekCount = 1
        private var selectionRevision: UInt = 0
        private var interactiveRevision: UInt?
        private var transitionSource: Int?
        private var transitionTarget: Int?
        private var transitioning = false
        private var drainScheduled = false
        private var active = true

        private var displayedWeek: Int? {
            (controller?.viewControllers?.first as? PageHost)?.week
        }

        func attachFallbackPan(to controller: UIPageViewController, scrollView: UIScrollView) {
            pagerScrollView = scrollView
            let pan = PagerFallbackPanGestureRecognizer(target: self, action: #selector(handleFallbackPan(_:)))
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            pan.delegate = self
            pan.require(toFail: scrollView.panGestureRecognizer)
            controller.view.addGestureRecognizer(pan)
            fallbackPan = pan
        }

        func update(_ parent: NativeWeekPager, environment: EnvironmentValues) {
            guard active else { return }
            let count = max(1, parent.maxWeek)
            let requested = min(max(1, parent.selection), count)
            if requested != requestedWeek || count != weekCount { selectionRevision &+= 1 }
            self.parent = parent
            self.environment = environment
            weekCount = count
            requestedWeek = requested
            if let visible = controller?.viewControllers?.first as? PageHost {
                hosts[visible.week] = visible
            }
            // Updating a root retains each page's SwiftUI identity and scroll state.
            for host in Array(hosts.values) { host.rootView = rootView(for: host.week) }
            drain()
            prune()
        }

        func invalidate() {
            active = false
            parent = nil
            hosts.removeAll()
        }

        private func rootView(for week: Int) -> AnyView {
            guard let parent else { return AnyView(EmptyView()) }
            // Copy public app/layout values, not container internals: copying
            // the whole environment can replay ancestor overlays inside each page.
            return AnyView(parent.content(week)
                .environment(\.localWakeUpColors, environment.localWakeUpColors)
                .environment(\.localCoursePalette, environment.localCoursePalette)
                .environment(\.localNavExtraBottomPadding, environment.localNavExtraBottomPadding)
                .environment(\.sleepyUIStyle, environment.sleepyUIStyle)
                .environment(\.sleepyNativeButtonSurface, environment.sleepyNativeButtonSurface)
                .environment(\.systemColorSnapshot, environment.systemColorSnapshot)
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
                .tint(environment.localWakeUpColors.primary))
        }

        private func host(for week: Int) -> PageHost {
            if let host = hosts[week] { return host }
            let host = PageHost(week: week, rootView: rootView(for: week))
            host.view.backgroundColor = .clear
            host.view.isOpaque = false
            host.view.clipsToBounds = true
            if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
            hosts[week] = host
            return host
        }

        private func drain() {
            guard active, !transitioning, let controller, let parent else { return }
            let current = displayedWeek
            guard current != requestedWeek else { prune(); return }
            let target = requestedWeek
            let destination = host(for: target)
            transitioning = true
            transitionSource = current
            transitionTarget = target
            let direction: UIPageViewController.NavigationDirection = target < (current ?? target) ? .reverse : .forward
            let animated = current != nil && parent.animationsEnabled
                && !environment.accessibilityReduceMotion && controller.view.window != nil
            controller.setViewControllers([destination], direction: direction, animated: animated) { [weak self] _ in
                guard let self, self.active else { return }
                self.transitioning = false
                self.transitionSource = nil
                self.transitionTarget = nil
                self.prune()
                self.scheduleDrain()
            }
            prune()
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

        private func prune() {
            guard let current = transitionSource ?? displayedWeek else { return }
            let anchor = min(max(current, 1), weekCount)
            var retained = Set(max(1, anchor - 1)...min(weekCount, anchor + 1))
            retained.insert(current)
            if let target = transitionTarget { retained.insert(target) }
            // Current + two neighbors + an in-flight destination: at most four.
            hosts = hosts.filter { retained.contains($0.key) }
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard active, let page = viewController as? PageHost, page.week > 1,
                  page.week - 1 <= weekCount else { return nil }
            let previous = host(for: page.week - 1)
            prune()
            return previous
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard active, let page = viewController as? PageHost,
                  page.week < weekCount else { return nil }
            let next = host(for: page.week + 1)
            prune()
            return next
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                willTransitionTo pendingViewControllers: [UIViewController]) {
            guard active, !transitioning else { return }
            transitioning = true
            interactiveRevision = selectionRevision
            transitionSource = displayedWeek
            if let pending = pendingViewControllers.first as? PageHost {
                pending.rootView = rootView(for: pending.week)
                hosts[pending.week] = pending
                transitionTarget = pending.week
            }
            prune()
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard active, let revision = interactiveRevision else { return }
            interactiveRevision = nil
            transitioning = false
            transitionSource = nil
            transitionTarget = nil
            if completed, revision == selectionRevision, let week = displayedWeek,
               (1...weekCount).contains(week) {
                requestedWeek = week
                parent?.onSelect(week)
            }
            prune()
            scheduleDrain()
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === fallbackPan,
                  let pan = gestureRecognizer as? PagerFallbackPanGestureRecognizer,
                  active, !transitioning, weekCount > 1,
                  let view = controller?.view, view.window != nil,
                  let scroll = pagerScrollView, scroll.isScrollEnabled, scroll.panGestureRecognizer.isEnabled,
                  scroll.panGestureRecognizer.state != .began, scroll.panGestureRecognizer.state != .changed,
                  !scroll.isDragging, !scroll.isDecelerating,
                  !hasActiveDragGesture(from: view),
                  !hasActiveDescendantScroll(in: scroll) else { return false }
            let d = pan.displacement
            return abs(d.x) > abs(d.y) * 1.25 && abs(d.x) >= 6
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === fallbackPan else { return false }
            if otherGestureRecognizer.name == "sleepy.courseDrag"
                || otherGestureRecognizer.name == "sleepy.gridRowPinch"
                || otherGestureRecognizer is UIPinchGestureRecognizer {
                return false
            }
            if let otherPan = otherGestureRecognizer as? UIPanGestureRecognizer, otherPan.view is UIScrollView {
                return false
            }
            return true
        }

        @objc private func handleFallbackPan(_ sender: UIPanGestureRecognizer) {
            guard let pan = sender as? PagerFallbackPanGestureRecognizer,
                  pan.state == .ended, active, !transitioning,
                  let controller, let view = controller.view, view.window != nil,
                  let parent else { return }
            let d = pan.displacement
            let vel = pan.velocity(in: view)
            guard abs(d.x) > abs(d.y),
                  abs(d.x) >= 24 || abs(vel.x) >= 250 else { return }
            let current = displayedWeek ?? requestedWeek
            let horizontal = abs(d.x) >= 24 ? d.x : vel.x
            let target = current + (horizontal > 0 ? -1 : 1)
            guard (1...weekCount).contains(target), target != current else { return }
            let destination = host(for: target)
            let swipeRevision = selectionRevision
            transitioning = true
            transitionSource = current
            transitionTarget = target
            let direction: UIPageViewController.NavigationDirection = target < current ? .reverse : .forward
            let animated = parent.animationsEnabled && !environment.accessibilityReduceMotion
            controller.setViewControllers([destination], direction: direction, animated: animated) { [weak self] _ in
                guard let self, self.active else { return }
                self.transitioning = false
                self.transitionSource = nil
                self.transitionTarget = nil
                if swipeRevision == self.selectionRevision,
                   let week = self.displayedWeek,
                   (1...self.weekCount).contains(week) {
                    self.requestedWeek = week
                    self.parent?.onSelect(week)
                }
                self.prune()
                self.scheduleDrain()
            }
            prune()
        }

        private func hasActiveDragGesture(from view: UIView) -> Bool {
            var cur: UIView? = view
            while let v = cur {
                if (v.gestureRecognizers ?? []).contains(where: {
                    $0.name == "sleepy.courseDrag" && ($0.state == .began || $0.state == .changed)
                }) {
                    return true
                }
                cur = v.superview
            }
            return false
        }

        private func hasActiveDescendantScroll(in view: UIView) -> Bool {
            for child in view.subviews {
                if let scroll = child as? UIScrollView,
                   scroll.isDragging || scroll.panGestureRecognizer.state == .began || scroll.panGestureRecognizer.state == .changed {
                    return true
                }
                if hasActiveDescendantScroll(in: child) { return true }
            }
            return false
        }

        private final class PageHost: UIHostingController<AnyView> {
            let week: Int
            init(week: Int, rootView: AnyView) {
                self.week = week
                super.init(rootView: rootView)
            }
            @available(*, unavailable)
            required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        }
    }
}

private final class PagerFallbackPanGestureRecognizer: UIPanGestureRecognizer {
    private var startLocation: CGPoint?
    private var latestLocation: CGPoint?

    var displacement: CGPoint {
        guard let startLocation, let latestLocation else { return .zero }
        return CGPoint(x: latestLocation.x - startLocation.x, y: latestLocation.y - startLocation.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first {
            let point = touch.location(in: view)
            startLocation = point
            latestLocation = point
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first {
            latestLocation = touch.location(in: view)
        }
        super.touchesMoved(touches, with: event)
    }

    override func reset() {
        startLocation = nil
        latestLocation = nil
        super.reset()
    }
}
