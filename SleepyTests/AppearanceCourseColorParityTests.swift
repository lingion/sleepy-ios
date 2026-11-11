import XCTest
import SwiftUI
@testable import Sleepy

final class AppearanceCourseColorParityTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var prefs: AppPrefs!
    private var db: AppDatabase!
    private let gids = ["math", "physics", "language"]

    override func setUpWithError() throws {
        suite = "appearance-colors-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        prefs = AppPrefs(defaults: defaults)
        db = try AppDatabase.inMemory()
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testFirstCustomSelectionSeedsCurrentPrimaryAndPersistsAllGroupHues() throws {
        let primary = Color(red: 0, green: 1, blue: 0)
        XCTAssertEqual(AppearanceColorActions.selectMode(AppPrefs.COURSE_COLOR_MODE_CUSTOM,
            primary: primary, prefs: prefs, dao: db.courseColorDao, gids: gids), 3)
        XCTAssertEqual(prefs.getCourseColorSeedHue(), 120, accuracy: 0.01)
        XCTAssertEqual(try db.courseColorDao.getHueMap(CourseColorEntity.globalTableKey),
                       CourseColorUtil.planHuesForGroups(anchor: 120, existingHues: [], gids: gids))
        // A later visit must retain the user's chosen seed.
        prefs.setCourseColorSeedHue(42)
        AppearanceColorActions.selectMode(AppPrefs.COURSE_COLOR_MODE_CLASSIC,
            primary: .blue, prefs: prefs, dao: db.courseColorDao, gids: gids)
        AppearanceColorActions.selectMode(AppPrefs.COURSE_COLOR_MODE_CUSTOM,
            primary: .blue, prefs: prefs, dao: db.courseColorDao, gids: gids)
        XCTAssertEqual(prefs.getCourseColorSeedHue(), 42)
    }

    func testFollowThemeSelectionAndThemeChangeBothPersistCurrentAnchor() throws {
        XCTAssertEqual(AppearanceColorActions.selectMode(AppPrefs.COURSE_COLOR_MODE_FOLLOW_THEME,
            primary: .blue, prefs: prefs, dao: db.courseColorDao, gids: gids), 3)
        let before = try db.courseColorDao.getHueMap(CourseColorEntity.globalTableKey)
        let oldAnchor = CourseColorWriteGlue.resolveAnchor(mode: prefs.getCourseColorMode(), prefs: prefs)!
        let key = ThemePresets.all.first {
            prefs.setThemeKey($0.key)
            return abs(CourseColorWriteGlue.resolveAnchor(mode: prefs.getCourseColorMode(), prefs: prefs)! - oldAnchor) > 20
        }!.key
        prefs.setThemeKey(key)
        XCTAssertEqual(AppearanceColorActions.themeDidChange(prefs: prefs, dao: db.courseColorDao, gids: gids), 3)
        let anchor = CourseColorWriteGlue.resolveAnchor(mode: prefs.getCourseColorMode(), prefs: prefs)!
        let after = try db.courseColorDao.getHueMap(CourseColorEntity.globalTableKey)
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(after, CourseColorUtil.planHuesForGroups(anchor: anchor, existingHues: [], gids: gids))
    }

    func testColorlessAndUnchangedModePreserveHuesAndClassicDoesNotWrite() throws {
        AppearanceColorActions.selectMode(AppPrefs.COURSE_COLOR_MODE_CUSTOM,
            primary: .blue, prefs: prefs, dao: db.courseColorDao, gids: gids)
        let before = try db.courseColorDao.getHueMap(CourseColorEntity.globalTableKey)
        XCTAssertEqual(AppearanceColorActions.selectMode(-1, primary: .green,
            prefs: prefs, dao: db.courseColorDao, gids: gids), 0)
        XCTAssertTrue(prefs.isCourseColorless())
        XCTAssertEqual(prefs.getCourseColorMode(), AppPrefs.COURSE_COLOR_MODE_CUSTOM)
        XCTAssertEqual(AppearanceColorActions.selectMode(AppPrefs.COURSE_COLOR_MODE_CUSTOM, primary: .green,
            prefs: prefs, dao: db.courseColorDao, gids: gids), 0)
        XCTAssertFalse(prefs.isCourseColorless())
        prefs.setThemeKey(ThemePresets.KEY_SYSTEM)
        XCTAssertEqual(AppearanceColorActions.themeDidChange(prefs: prefs, dao: db.courseColorDao, gids: gids), 0)
        XCTAssertEqual(AppearanceColorActions.selectMode(AppPrefs.COURSE_COLOR_MODE_CLASSIC, primary: .green,
            prefs: prefs, dao: db.courseColorDao, gids: gids), 0)
        XCTAssertEqual(try db.courseColorDao.getHueMap(CourseColorEntity.globalTableKey), before)
    }

    func testExplicitDarkModeRecalculatesFollowThemeAnchor() throws {
        prefs.setThemeKey(ThemePresets.ocean.key)
        prefs.setThemeMode(AppPrefs.THEME_MODE_LIGHT)
        AppearanceColorActions.selectMode(AppPrefs.COURSE_COLOR_MODE_FOLLOW_THEME, primary: .blue,
            prefs: prefs, dao: db.courseColorDao, gids: gids)
        let before = try db.courseColorDao.getHueMap(CourseColorEntity.globalTableKey)
        prefs.setThemeMode(AppPrefs.THEME_MODE_DARK)
        XCTAssertEqual(AppearanceColorActions.themeDidChange(prefs: prefs, dao: db.courseColorDao, gids: gids), 3)
        let after = try db.courseColorDao.getHueMap(CourseColorEntity.globalTableKey)
        XCTAssertNotEqual(before, after)
        let anchor = CourseColorWriteGlue.resolveAnchor(mode: prefs.getCourseColorMode(), prefs: prefs)!
        XCTAssertEqual(after, CourseColorUtil.planHuesForGroups(anchor: anchor, existingHues: [], gids: gids))
    }
}
