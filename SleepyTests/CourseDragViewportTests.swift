import XCTest
@testable import Sleepy

final class CourseDragViewportTests: XCTestCase {
    private let viewport = CGRect(x: 0, y: 164, width: 402, height: 710)

    private func grid(x: CGFloat = 8) -> CourseDropGrid {
        CourseDropGrid(frame: CGRect(x: x, y: 228, width: 386, height: 208),
            days: [2, 4, 7], timeWidth: 70, columnWidth: 100, gap: 4,
            rows: [.init(node: 1, top: 0, bottom: 48),
                   .init(node: 2, top: 52, bottom: 100),
                   .init(node: 3, top: 104, bottom: 152),
                   .init(node: 4, top: 156, bottom: 204)])
    }

    func testPagingGridUsesViewportXAndKeepsMeasuredRowsAndY() throws {
        // 失败日志中的新页 x=398 / 旧页 x=-4；不能拿动画中横坐标命中。
        for x: CGFloat in [398, -4, 8] {
            let positioned = grid(x: x).positioned(in: viewport)
            let target = try XCTUnwrap(positioned.target(at: CGPoint(x: 393, y: 278),
                step: 2, grabOffsetY: 50, viewport: viewport, edgeDirection: 1))
            XCTAssertEqual(target.day, 7)
            XCTAssertEqual(target.node, 1)
            XCTAssertEqual(target.rect, CGRect(x: 290, y: 228, width: 100, height: 100))
        }
    }

    func testLeftEdgeMapsToFirstVisibleDayWithoutChangingGrabOffset() throws {
        let target = try XCTUnwrap(grid().target(at: CGPoint(x: 9, y: 382), step: 2,
            grabOffsetY: 50, viewport: viewport, edgeDirection: -1))
        XCTAssertEqual(target.day, 2, "隐藏周一时使用首个可见星期，不硬编码周一")
        XCTAssertEqual(target.node, 3)
        XCTAssertEqual(target.rect, CGRect(x: 82, y: 332, width: 100, height: 100))
    }

    func testViewportOriginIsNotAssumedToBeWindowOrigin() throws {
        let insetViewport = viewport.offsetBy(dx: 50, dy: 0)
        let target = try XCTUnwrap(grid(x: -354).positioned(in: insetViewport).target(
            at: CGPoint(x: 443, y: 278), step: 2, grabOffsetY: 50,
            viewport: insetViewport, edgeDirection: 1))
        XCTAssertEqual(target.day, 7)
        XCTAssertEqual(target.rect, CGRect(x: 340, y: 228, width: 100, height: 100))
    }

    func testTimeAxisOutsidePagingStripStillRejectsDrop() {
        XCTAssertNil(grid().target(at: CGPoint(x: 40, y: 278), step: 2,
            grabOffsetY: 50, viewport: viewport, edgeDirection: 0))
        XCTAssertNil(grid().target(at: CGPoint(x: 9, y: 278), step: 2,
            grabOffsetY: 50, viewport: viewport, edgeDirection: 0))
    }

    func testEdgeDoesNotClampVerticalOverflowOrOutsideViewport() {
        for point in [CGPoint(x: -1, y: 278), CGPoint(x: 9, y: 220),
                      CGPoint(x: 393, y: 450), CGPoint(x: 403, y: 278)] {
            XCTAssertNil(grid().target(at: point, step: 2, grabOffsetY: 50,
                viewport: viewport, edgeDirection: point.x < 200 ? -1 : 1))
        }
        XCTAssertNil(grid().target(at: CGPoint(x: 9, y: 420), step: 2,
            viewport: viewport, edgeDirection: -1), "多节课程仍不可溢出最后一节")
    }

    func testLeftDwellRepeatsAndStopsAtFirstWeek() {
        var paging = CourseDragEdgePaging()
        XCTAssertNil(paging.update(direction: -1, now: 0, week: 3, maxWeek: 20))
        XCTAssertEqual(paging.update(direction: -1, now: 0.5, week: 3, maxWeek: 20), 2)
        XCTAssertEqual(paging.update(direction: -1, now: 1, week: 2, maxWeek: 20), 1)
        XCTAssertNil(paging.update(direction: -1, now: 1.5, week: 1, maxWeek: 20))
    }
}
