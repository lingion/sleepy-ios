import XCTest
#if !OVERLAY_DISMISSAL_STANDALONE
@testable import Sleepy
#endif

final class OverlayDismissalStateTests: XCTestCase {
    func testCurrentDismissalRunsOnlyOnce() {
        let state = OverlayDismissalState()
        let ticket = state.beginDismissal()
        var backCalls = 0

        XCTAssertTrue(state.completeDismissal(ticket) { backCalls += 1 })
        XCTAssertFalse(state.completeDismissal(ticket) { backCalls += 1 })
        XCTAssertEqual(backCalls, 1)
    }

    func testOpeningAnotherRouteCancelsTheOldCloseAction() {
        let state = OverlayDismissalState()
        var route: String? = "general"
        let ticket = state.beginDismissal()

        route = "allTables"
        state.navigationChanged()
        XCTAssertFalse(state.completeDismissal(ticket) { route = nil })
        XCTAssertEqual(route, "allTables")
    }

    func testAgendaDeepLinkSurvivesThePreviousAnimationCompletion() {
        let state = OverlayDismissalState()
        var route: String? = "periodEdit"
        let ticket = state.beginDismissal()

        route = "dailyAgenda/2026-11-10"
        state.navigationChanged()
        XCTAssertFalse(state.completeDismissal(ticket) { route = nil })
        XCTAssertEqual(route, "dailyAgenda/2026-11-10")
    }

    func testOldHandleBackCannotDiscardANewTableInTheSameEditorRoute() {
        let state = OverlayDismissalState()
        var route: String? = "editTable"
        var pendingNewTableID: Int? = 41
        var discardedIDs: [Int] = []
        let ticket = state.beginDismissal()

        // A second new table reuses .editTable; enum equality cannot identify navigation.
        pendingNewTableID = 42
        state.navigationChanged()
        XCTAssertFalse(state.completeDismissal(ticket) {
            if let id = pendingNewTableID { discardedIDs.append(id) }
            pendingNewTableID = nil
            route = nil
        })
        XCTAssertEqual(route, "editTable")
        XCTAssertEqual(pendingNewTableID, 42)
        XCTAssertTrue(discardedIDs.isEmpty)
    }

    func testSupersededCompletionDoesNotConsumeTheNewDismissal() {
        let state = OverlayDismissalState()
        let oldTicket = state.beginDismissal()
        state.navigationChanged()
        let newTicket = state.beginDismissal()
        var completed: [String] = []

        XCTAssertFalse(state.completeDismissal(oldTicket) { completed.append("old") })
        XCTAssertTrue(state.completeDismissal(newTicket) { completed.append("new") })
        XCTAssertEqual(completed, ["new"])
    }

    func testCompletionCanNavigateAndScheduleAnotherDismissal() {
        let state = OverlayDismissalState()
        let ticket = state.beginDismissal()
        var nextTicket: OverlayDismissalState.Ticket?
        var backCalls = 0

        XCTAssertTrue(state.completeDismissal(ticket) {
            backCalls += 1
            state.navigationChanged()
            nextTicket = state.beginDismissal()
        })
        XCTAssertFalse(state.completeDismissal(ticket) { backCalls += 1 })
        guard let nextTicket else { return XCTFail("The callback must be able to schedule the next dismissal") }
        XCTAssertTrue(state.completeDismissal(nextTicket) { backCalls += 1 })
        XCTAssertEqual(backCalls, 2)
    }
}
