import SwiftUI

/// Preference changes and persisted course hues must commit together from every appearance entry.
enum AppearanceColorActions {
    @discardableResult
    static func selectMode(_ mode: Int, primary: Color, prefs: AppPrefs,
                           dao: CourseColorDao, gids: [String]) -> Int {
        guard mode != -1 else {
            prefs.setCourseColorless(true)
            return 0
        }
        let changed = mode != prefs.getCourseColorMode()
        prefs.setCourseColorless(false)
        if mode == AppPrefs.COURSE_COLOR_MODE_CUSTOM && prefs.getCourseColorSeedHue() < 0 {
            prefs.setCourseColorSeedHue(CourseColorUtil.hueOf(primary))
        }
        prefs.setCourseColorMode(mode)
        return changed ? CourseColorWriteGlue.recalcAll(dao: dao, gids: gids, prefs: prefs) : 0
    }

    @discardableResult
    static func themeDidChange(prefs: AppPrefs, dao: CourseColorDao, gids: [String]) -> Int {
        guard prefs.getCourseColorMode() == AppPrefs.COURSE_COLOR_MODE_FOLLOW_THEME else { return 0 }
        return CourseColorWriteGlue.recalcAll(dao: dao, gids: gids, prefs: prefs)
    }
}
