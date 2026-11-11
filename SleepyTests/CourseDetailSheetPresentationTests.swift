import XCTest
import SwiftUI
import UIKit
@testable import Sleepy

final class CourseDetailSheetPresentationTests: XCTestCase {
    @MainActor
    func testShortCourseDetailUsesContentHeightInsteadOfFullScreen() throws {
        let fixture = DetailFixtureModel()
        let host = try present(fixture)
        defer { host.window.isHidden = true }
        let sheet = try presentedSheet(in: host.controller)

        if #available(iOS 16.0, *) {
            XCTAssertLessThan(sheet.presentedViewController.view.bounds.height,
                              host.window.bounds.height * 0.65,
                              "A two-row detail should wrap its content, like Android's expanded bottom sheet")
        } else {
            XCTAssertEqual(sheet.detents.count, 2,
                           "iOS 15 must retain an expandable fallback")
        }
        XCTAssertTrue(sheet.prefersGrabberVisible)
        let scroll = try XCTUnwrap(detailScroll(in: sheet.presentedViewController.view))
        XCTAssertLessThanOrEqual(scroll.contentSize.height, scroll.bounds.height + 2)
    }

    @MainActor
    func testLongCourseDetailCapsAtAvailableHeightAndCanScrollToLastActions() throws {
        let fixture = DetailFixtureModel()
        fixture.note = String(repeating: "A long course note needs multiple lines. ", count: 140)
        let host = try present(fixture)
        defer { host.window.isHidden = true }
        let sheet = try presentedSheet(in: host.controller)
        let scroll = try XCTUnwrap(detailScroll(in: sheet.presentedViewController.view))

        XCTAssertLessThanOrEqual(sheet.presentedViewController.view.bounds.height, host.window.bounds.height)
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height + 200,
                             "Long details must stay in a scroll view rather than clip the edit action")
        let bottom = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
        XCTAssertEqual(scroll.contentOffset.y, bottom, accuracy: 1)
    }

    @MainActor
    func testPresentedDetailResizesWhenContentChanges() throws {
        guard #available(iOS 16.0, *) else { throw XCTSkip("Custom detents require iOS 16") }
        let fixture = DetailFixtureModel()
        let host = try present(fixture)
        defer { host.window.isHidden = true }
        let sheet = try presentedSheet(in: host.controller)
        let shortHeight = sheet.presentedViewController.view.bounds.height

        fixture.note = String(repeating: "Additional course information. ", count: 18)
        settle()
        XCTAssertGreaterThan(sheet.presentedViewController.view.bounds.height, shortHeight + 60)

        fixture.note = ""
        settle()
        XCTAssertEqual(sheet.presentedViewController.view.bounds.height, shortHeight, accuracy: 3)
    }

    @MainActor
    private func present(_ fixture: DetailFixtureModel) throws -> (window: UIWindow, controller: UIViewController) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let controller = UIHostingController(rootView: DetailFixture(model: fixture))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        settle()
        return (window, controller)
    }

    @MainActor
    private func presentedSheet(in controller: UIViewController) throws -> UISheetPresentationController {
        let presented = try XCTUnwrap(controller.presentedViewController)
        return try XCTUnwrap(presented.sheetPresentationController)
    }

    @MainActor
    private func detailScroll(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        for child in view.subviews {
            if let scroll = detailScroll(in: child) { return scroll }
        }
        return nil
    }

    @MainActor
    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    }
}

private final class DetailFixtureModel: ObservableObject {
    @Published var note = ""

    var course: CourseEntity {
        CourseEntity(groupId: "detail-presentation", tableId: 1, courseName: "Course",
                     note: note, day: 3, startNode: 1, step: 2, startWeek: 1,
                     endWeek: 16, color: "#6750A4", id: 1)
    }
}

private struct DetailFixture: View {
    @ObservedObject var model: DetailFixtureModel

    var body: some View {
        Color.clear.sheet(isPresented: .constant(true)) {
            CourseDetailSheet(course: model.course, timeString: "08:00–09:40", onEdit: { _ in })
                .environment(\.sleepyUIStyle, .classic)
        }
    }
}
