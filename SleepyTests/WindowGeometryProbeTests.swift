import XCTest
import UIKit
@testable import Sleepy

final class WindowGeometryProbeTests: XCTestCase {
    @MainActor
    func testReportsWindowBoundsRatherThanOversizedChildBounds() async {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = UIViewController()
        window.isHidden = false
        defer { window.isHidden = true }
        let probe = WindowGeometryProbeView(frame: CGRect(x: 0, y: 0, width: 1000, height: 500))
        let portrait = expectation(description: "actual portrait window")
        probe.onChange = { size in
            XCTAssertEqual(size, CGSize(width: 400, height: 800))
            portrait.fulfill()
        }
        window.rootViewController!.view.addSubview(probe)
        await fulfillment(of: [portrait], timeout: 2)
        let landscape = expectation(description: "rotated window")
        probe.onChange = { size in
            XCTAssertEqual(size, CGSize(width: 800, height: 400))
            landscape.fulfill()
        }
        window.frame.size = CGSize(width: 800, height: 400)
        probe.reportSize()
        await fulfillment(of: [landscape], timeout: 2)
    }
}
