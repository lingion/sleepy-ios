// SleepyUITests 占位 — G5 冒烟自动化于 D6.6 落地
import XCTest

final class SleepyUITests: XCTestCase {
    func testLaunch() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.exists)
    }
}
