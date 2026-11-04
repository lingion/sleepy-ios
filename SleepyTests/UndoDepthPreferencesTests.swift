import XCTest
@testable import Sleepy

final class UndoDepthPreferencesTests: XCTestCase {
    func testDefaultAndSavedDepthSurvivePreferencesRecreation() throws {
        let suite = "UndoDepthPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = AppPrefs(defaults: defaults)
        XCTAssertEqual(prefs.getUndoDepth(), 5)
        XCTAssertEqual(AppPrefs.KEY_UNDO_DEPTH, "undo_depth")
        for depth in [0, -1, -7, 1, 5, 999999] {
            prefs.setUndoDepth(depth)
            let reopened = AppPrefs(defaults: defaults)
            XCTAssertEqual(reopened.getUndoDepth(), depth)
            let history = Sleepy.UndoManager(maxDepth: reopened.getUndoDepth())
            XCTAssertEqual(history.maxDepth, depth)
            history.capture(tables: [], courses: [], defaultTableId: 1)
            XCTAssertEqual(history.hasSnapshot, depth != 0)
        }
    }

    func testInputAcceptsSignedSixDigitIntegersAndIncompleteDrafts() {
        for (text, expected) in [("0", 0), ("5", 5), ("-1", -1), ("-23", -23),
                                 ("999999", 999999), ("-999999", -999999), ("000005", 5)] {
            XCTAssertTrue(UndoDepthInput.accepts(text), text)
            XCTAssertEqual(UndoDepthInput.value(text), expected, text)
        }
        for text in ["", "-"] {
            XCTAssertTrue(UndoDepthInput.accepts(text))
            XCTAssertNil(UndoDepthInput.value(text), "编辑中不能将深度误设为 0")
        }
    }

    func testInvalidDepthInputCannotChangeStoredPreference() throws {
        let suite = "UndoDepthInputTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = AppPrefs(defaults: defaults)
        prefs.setUndoDepth(5)
        for text in ["", "-", "--1", "1-", "+5", "1.5", "1e3", " 5", "5\n", "abc",
                     "1000000", "-1000000", "999999999999999999999999", "５"] {
            if let value = UndoDepthInput.value(text) { prefs.setUndoDepth(value) }
            XCTAssertEqual(prefs.getUndoDepth(), 5, text)
        }
    }
}
