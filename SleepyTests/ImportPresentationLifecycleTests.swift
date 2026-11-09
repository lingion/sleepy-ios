import XCTest
@testable import Sleepy

final class ImportPresentationLifecycleTests: XCTestCase {
    func testActiveMethodsPreserveIdentityUntilActualDismissal() {
        var state = ImportPresentationState()
        XCTAssertTrue(state.begin(.methods))
        XCTAssertFalse(state.begin(.methods))
        XCTAssertFalse(state.begin(.jw))
        XCTAssertEqual(state.active, .methods)
        XCTAssertTrue(state.didDismiss(.methods))
        XCTAssertTrue(state.begin(.methods))
    }

    func testDirectJWSerializesDeferredDocumentThroughDismissal() {
        var state = ImportPresentationState()
        XCTAssertTrue(state.begin(.jw))
        // An onFinish toggling a presentation binding is not a dismissal callback.
        XCTAssertFalse(state.begin(.methods))
        XCTAssertTrue(state.didDismiss(.jw))
        XCTAssertTrue(state.begin(.methods))
    }

    func testUnrelatedDismissCallbackCannotReleaseCurrentPresentation() {
        var state = ImportPresentationState()
        XCTAssertTrue(state.begin(.methods))
        XCTAssertFalse(state.didDismiss(.jw))
        XCTAssertFalse(state.begin(.jw))
        XCTAssertTrue(state.didDismiss(.methods))
        XCTAssertTrue(state.begin(.jw))
        XCTAssertFalse(state.didDismiss(.methods))
        XCTAssertEqual(state.active, .jw)
    }
}
