import XCTest
@testable import Sleepy

final class WatchTransferDeletionTests: XCTestCase {
    func testFullSnapshotWithoutTransfersClearsAnExistingTableMapping() throws {
        let suite = "transfer-deletion-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = AppPrefs(defaults: defaults)
        let transfer = HolidayTransferEntry(sourceDate: try XCTUnwrap(DateUtils.parseDate("2026-11-02")),
            targetDate: try XCTUnwrap(DateUtils.parseDate("2026-11-03")), segmentId: "test")
        WatchSyncSnapshot.applyTransfers([7: HolidayTransferOps.encodeTransfers([transfer])], tableIds: [7], prefs: prefs)
        XCTAssertEqual(prefs.getHolidayTransfers(7), [transfer])
        WatchSyncSnapshot.applyTransfers([:], tableIds: [7], prefs: prefs)
        XCTAssertTrue(prefs.getHolidayTransfers(7).isEmpty)
    }
}
