import XCTest
import UIKit
@testable import Sleepy

final class GridPinchAttachmentTests: XCTestCase {
    @MainActor
    func testRecognizerAttachesToScrollHostAndCleansUp() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let root = UIViewController()
        window.rootViewController = root
        window.isHidden = false
        defer { window.isHidden = true }
        let scroll = UIScrollView(frame: window.bounds)
        root.view.addSubview(scroll)
        let bridge = GridPinchResizeUIView(frame: CGRect(x: 0, y: 0, width: 300, height: 500))
        bridge.enabled = true
        scroll.addSubview(bridge)
        XCTAssertEqual(scroll.gestureRecognizers?.filter { $0.name == "sleepy.gridRowPinch" }.count, 1)
        bridge.enabled = false
        XCTAssertEqual(scroll.gestureRecognizers?.filter { $0.name == "sleepy.gridRowPinch" }.count ?? 0, 0)
        bridge.enabled = true
        bridge.removeFromSuperview()
        XCTAssertEqual(scroll.gestureRecognizers?.filter { $0.name == "sleepy.gridRowPinch" }.count ?? 0, 0)
    }
}
