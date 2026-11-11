import SwiftUI

/// Holiday presentation belongs to schedule settings; mappings and shared dates have their own page.
struct HolidayDisplaySettings: View {
    @Environment(\.localWakeUpColors) private var colors
    @State private var holidayGrey = AppPrefs.shared.isHolidayGreyHoliday()
    @State private var weekendGrey = AppPrefs.shared.isHolidayGreyWeekend()
    @State private var ignoreWorkday = AppPrefs.shared.isHolidayIgnoreWorkday()
    @State private var style = AppPrefs.shared.getHolidayStyle()
    private let prefs = AppPrefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingToggleRow(label: L10n.format("settings_holiday_holiday"),
                             subtitle: L10n.format("settings_holiday_holiday_sub"), checked: holidayGrey) {
                holidayGrey = $0; prefs.setHolidayGreyHoliday($0)
            }
            .accessibilityIdentifier("holiday_display_holiday")
            SettingToggleRow(label: L10n.format("settings_holiday_weekend"),
                             subtitle: L10n.format("settings_holiday_weekend_sub"), checked: weekendGrey) {
                weekendGrey = $0; prefs.setHolidayGreyWeekend($0)
            }
            .accessibilityIdentifier("holiday_display_weekend")
            if weekendGrey {
                SettingToggleRow(label: L10n.format("settings_appearance_workday_visible"),
                                 subtitle: L10n.format("settings_holiday_workday_sub"), checked: ignoreWorkday) {
                    ignoreWorkday = $0; prefs.setHolidayIgnoreWorkday($0)
                }
                .accessibilityIdentifier("holiday_display_workday")
            }
            Text(L10n.format("settings_holiday_style"))
                .font(.system(size: 14))
                .foregroundColor(colors.onSurface)
            SegmentedSwitcher(options: [("grey", L10n.format("settings_holiday_style_grey")),
                                        ("strikethrough", L10n.format("settings_holiday_style_strikethrough"))],
                              selected: style, onSelect: {
                                  style = $0; prefs.setHolidayStyle($0)
                              }, containerColor: colors.surfaceContainerHighest)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
        .accessibilityIdentifier("holiday_display_settings")
    }
}
