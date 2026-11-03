# iOS / original 1.0.51 UI alignment matrix

Baseline: [`sleepy-ios-ui-1.0.51-baseline.md`](sleepy-ios-ui-1.0.51-baseline.md)

Status values: `pending` means source comparison is still required; `in-progress` means the current worktree already contains a related change; `verified` requires source comparison plus a successful iOS build.

| Priority | iOS surface | iOS source | original 1.0.51 source | Current status | Alignment focus |
|---|---|---|---|---|---|
| P0 | Root navigation / dock | `Sleepy/SleepyApp.swift`, `ui/component/PillNavigationBar.swift` | `MainActivity.kt`, `ui/component/PillNavigationBar.kt` | verified | selected state timing, docked/floating geometry, background continuity, bottom inset |
| P0 | Schedule | `ui/screen/schedule/ScheduleScreen.swift`, `ScheduleViewModel.swift` | `ui/screen/schedule/ScheduleScreen.kt`, `ScheduleViewModel.kt` | verified | toolbar, week display, grid, empty/loading states, conflict layout |
| P0 | Today | `ui/screen/today/TodayScreen.swift` | `ui/screen/today/TodayScreen.kt` | verified | course cards, conflict presentation, date/week controls, detail sheet |
| P0 | Mine | `ui/screen/mine/MineScreen.swift` | `ui/screen/mine/MineScreen.kt` | verified | page title typography aligned; section hierarchy, row controls, icons, navigation destinations remain |
| P1 | Manage | `ui/screen/manage/ManagementPage.swift` | `ui/screen/manage/ManagementPage.kt` | verified | page title and table-name typography aligned; import/add cards and action semantics remain |
| P1 | Conflict card | `ui/component/ConflictCard.swift` | `ui/component/ConflictCard.kt` | verified | three conflict styles, selection, spacing, semantic controls |
| P1 | Segmented switcher | `ui/component/SegmentedSwitcher.swift` | `ui/component/SegmentedSwitcher.kt` | verified | thumb geometry, animation, selected semantics |
| P1 | Theme | `theme/Theme.swift`, `theme/ThemePresets.swift` | `ui/theme/Theme.kt`, `ThemePresets.kt`, `res/values/colors.xml` | verified | Material roles, light/dark values, shapes, typography aligned; custom presets confirmed matching |
| P1 | All tables | `ui/screen/mine/AllTablesScreen.swift` | `ui/screen/mine/AllTablesScreen.kt` | verified | current table, duplicate/edit/delete actions, row hit areas |
| P1 | Edit/add table | `ui/screen/mine/EditTableScreen.swift` | `ui/screen/mine/EditTableScreen.kt` | verified | form sections, save/delete, native inputs |
| P1 | Add course | `ui/screen/edit/AddCourseScreen.swift` | `ui/screen/edit/AddCourseScreen.kt` | verified | per-slot weeks/type, complete slot grouping, timetable-derived node bounds, conflict confirmation, native controls; custom-week list semantics remain documented |
| P1 | Appearance | `ui/screen/mine/AppearanceScreen.swift` | `ui/screen/mine/AppearanceScreen.kt` | verified | theme/display controls, high refresh, nav mode |
| P1 | General settings | `ui/screen/mine/GeneralSettingsScreen.swift` | `ui/screen/mine/GeneralSettingsScreen.kt` | verified | visible days, switches, native controls, constraints; Android-only grid/week scale controls documented as an iOS contract gap |
| P1 | Import flow | `ui/screen/imports/*.swift` | `ui/screen/imports/*.kt` | verified | school selection, import sheet, login states, errors, ConfigureConfirm dialog; behavior-layer items (WebView fetch/timeout, frame retry, DiagMapper, parse warnings) documented as out-of-scope |
| P2 | Holiday / reminder | `HolidaySettingsScreen.swift`, `ReminderScreen.swift` | matching `*.kt` | verified | toggles, date/location controls, permission states |
| P2 | Export/share | `ExportScreen.swift`, `ShareScheduleSheet.swift` | matching `*.kt` | verified | format selection, share actions, empty/error states; sleepy-v1 native export row documented as a data-layer gap pending `SleepyNativeExporter` port |
| P2 | About/license | `AboutScreen.swift`, `LicenseScreen.swift` | matching `*.kt` | verified | version/about content, feedback entries (GitHub Issue + email), two-tier acknowledgements with expandable per-school cards, localization; UpdateNotifier banner + auto-check toggle documented as a behavior-layer gap (new preference + launch-time network check outside the UI contract) |
| P2 | Shared sheets/editors | `CourseDetailSheet.swift`, `DateTimePickers.swift`, `SmartPeriodEditor.swift`, `TimeSlotEditor.swift`, `SettingsCards.swift` | matching component sources | verified | sheet detents, controls, spacing, typography; SettingsCards no-drift confirmed, whole-card tap documented as iOS adaptation, M3 56dp field height documented as app-wide iOS field height |
| P3 | Localization/layout stress | all user-visible SwiftUI strings | 原 locale resources | verified | 431 keys + dynamic format_* expansions present in all 5 locales; lineLimit↔maxLines audit (1 fix); 原 contentDescription coverage mirrored to accessibilityLabel; AddCourseScreen delete_slot documented as deferred (user-dirty file) |

## Rules

- A row becomes `verified` only after its 原 source and iOS source have been read, the minimal implementation diff is applied, and the relevant generic iOS build passes.
- Parser, DAO, repository, widget, and preference-default changes are outside this matrix.
- Existing worktree changes are evidence to preserve, not permission to overwrite.
