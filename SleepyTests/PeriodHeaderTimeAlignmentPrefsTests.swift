import XCTest
@testable import Sleepy

final class PeriodHeaderTimeAlignmentPrefsTests: XCTestCase {
    func testDefaultReadDoesNotWritePreference() {
        let suite = "header-alignment-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = AppPrefs(defaults: defaults)
        XCTAssertEqual(AppPrefs.KEY_PERIOD_HEADER_TIME_ALIGNMENT, "period_header_time_alignment")
        XCTAssertEqual(prefs.getPeriodHeaderTimeAlignment(), "dash")
        XCTAssertNil(defaults.object(forKey: AppPrefs.KEY_PERIOD_HEADER_TIME_ALIGNMENT))
    }

    func testLegalValuesPersistInInjectedStoreAcrossReconstruction() {
        let suite = "header-alignment-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = AppPrefs(defaults: defaults)
        for value in ["center", "dash"] {
            prefs.setPeriodHeaderTimeAlignment(value)
            XCTAssertEqual(defaults.string(forKey: AppPrefs.KEY_PERIOD_HEADER_TIME_ALIGNMENT), value)
            XCTAssertEqual(AppPrefs(defaults: defaults).getPeriodHeaderTimeAlignment(), value)
        }
    }

    func testInvalidStoredValueFallsBackWithoutRewritingStorage() {
        let suite = "header-alignment-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = AppPrefs(defaults: defaults)
        for value in ["", "legacy", "CENTER", " center "] {
            defaults.set(value, forKey: AppPrefs.KEY_PERIOD_HEADER_TIME_ALIGNMENT)
            XCTAssertEqual(prefs.getPeriodHeaderTimeAlignment(), "dash")
            XCTAssertEqual(defaults.string(forKey: AppPrefs.KEY_PERIOD_HEADER_TIME_ALIGNMENT), value)
        }
    }
}
