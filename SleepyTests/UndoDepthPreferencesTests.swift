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

    func testSignedStoredDepthMapsToThreeNativeModesWithoutChangingTheValue() throws {
        let suite = "UndoDepthModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = AppPrefs(defaults: defaults)
        for (depth, mode) in [(0, UndoDepthMode.off), (1, .limited), (5, .limited),
                              (999999, .limited), (-1, .unlimited), (-17, .unlimited),
                              (Int.min, .unlimited)] {
            prefs.setUndoDepth(depth)
            XCTAssertEqual(AppPrefs(defaults: defaults).getUndoDepth(), depth)
            XCTAssertEqual(UndoDepthMode(depth: prefs.getUndoDepth()), mode, "depth \(depth)")
        }
        XCTAssertEqual(UndoDepthMode.off.storedDepth, 0)
        XCTAssertEqual(UndoDepthMode.limited.storedDepth, 5)
        XCTAssertEqual(UndoDepthMode.unlimited.storedDepth, -1)
    }

    func testLimitedInputAcceptsOnlyUpToSixDigitsAndPersistsOnlyPositiveIntegers() throws {
        for (text, expected) in [("", nil), ("0", nil), ("00", nil), ("5", 5),
                                 ("000005", 5), ("999999", 999999), ("1000000", nil)] {
            XCTAssertEqual(UndoDepthInput.accepts(text), text.count <= 6 && text.utf8.allSatisfy {
                (48...57).contains($0)
            }, text)
            XCTAssertEqual(UndoDepthInput.value(text), expected, text)
        }
        let suite = "UndoDepthLimitedInputTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = AppPrefs(defaults: defaults)
        prefs.setUndoDepth(7)
        for text in ["", "0", "00", "0.5", "-1", "+5", "1e3", " 5", "5\n", "abc",
                     "1000000", "999999999999999999999999", "５"] {
            if let value = UndoDepthInput.value(text) { prefs.setUndoDepth(value) }
            XCTAssertEqual(prefs.getUndoDepth(), 7, "非法或非正数量不能落库: \(text)")
        }
        if let value = UndoDepthInput.value("12") { prefs.setUndoDepth(value) }
        XCTAssertEqual(prefs.getUndoDepth(), 12)
    }
}
