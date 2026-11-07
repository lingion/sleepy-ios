import XCTest
import GRDB
@testable import Sleepy

final class CourseColorCommitBoundaryTests: XCTestCase {
    @MainActor
    func testRecalcWithInjectedPrefsRefreshesCommittedCache() async throws {
        let suite = "color-commit-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = AppPrefs(defaults: defaults)
        prefs.setCourseColorMode(AppPrefs.COURSE_COLOR_MODE_CUSTOM)
        prefs.setCourseColorSeedHue(120)
        let db = try AppDatabase.inMemory()
        let gid = UUID().uuidString
        let refreshed = expectation(description: "提交后使用注入模式刷新缓存")
        let observer = NotificationCenter.default.addObserver(
            forName: .courseHueStoreChanged, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                if CourseHueStore.shared.hueMap[gid] != nil { refreshed.fulfill() }
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let count = CourseColorWriteGlue.recalcAll(dao: db.courseColorDao, gids: [gid], prefs: prefs)
        XCTAssertEqual(count, 1)
        await fulfillment(of: [refreshed], timeout: 2)
        XCTAssertEqual(CourseHueStore.shared.hueMap, try db.courseColorDao.getHueMap(CourseColorEntity.globalTableKey))
    }
}
