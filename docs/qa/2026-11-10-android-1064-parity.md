# iOS / Android 1.0.64 parity

Reference: Android tag `v1.0.64`, commit `77b878fd5c8903a3f201ea938b3b152de4c4fbc0`.
iOS implementation base: `f36fddf31ea69c2b9c6ed69cba7b52addf2e5959`; includes master documentation update `ba01f833b105799e8e7cb30707d080f7481dfc4f`.
App version/build: `1.0.64` / `64`. Deployment target remains iOS 15.6.

## Behavior and presentation

| Area | Implementation |
| --- | --- |
| Timetable data | Nullable reminder override and opaque import source metadata survive storage, backup, JSON and native sharing. Automatic reminder scope follows the default timetable; the first manual edit freezes the effective set. Appending a backup preserves existing default and reminder choices. |
| Import refresh | Review exact matches before the unique name/day fallback, preserve local course presentation, reject stale previews and foreign IDs, and replace rows atomically with undo support. Confirmation retains dated courses, term weeks and captured source periods. |
| Course editing | Collapsible meeting cards, occurrence-only room changes, and named timetable copies with blank/duplicate validation. |
| Bell schedules | Strict row identities, clock order, overlap and missing-course-node validation; row diagnostics and conflict banners. Render-only sanitization keeps persisted source data intact. EffectivePeriodResolver provides strict date-rule resolution without adding an unsupported configuration screen. |
| Academic imports | Align declared and generic parser routes, capture scripts, source diagnostics and recent school suggestions with the fixed Android source. Catalogue has 4,140 identities and 2,881 entry URLs; supported, unverified and pending remain separate statuses. |
| Shared controls | Independent Classic/Liquid Glass choice and aligned settings organization. Liquid Glass uses system buttons, switches, sliders, segmented pickers and date/time controls. Independent icon actions explicitly use circular system borders, with an actual 44pt native button inside a 48pt slot; text and grouped actions use capsules. Classic icon slots follow the corresponding Android dimensions, including theme editing, meeting deletion/expansion, bell schedules, academic login and widget actions. Calendar destination/range selectors use native menu pickers. Range endpoints use two native sliders with stable full-domain tracks and integer/non-crossing constraints. |
| Schedule layout | Classic retains staged gap/action compression. Liquid Glass measures native group sizes and scales all three groups together while keeping week navigation centered. Normal paging constructs heavy content for the selected week and neighbors. A UIKit 500ms long press accepts only current-week course-card geometry, leaving ordinary button taps independent. Covered pages propagate their disabled state into the root gesture recognizer, preventing overlay touches from moving hidden courses. During dragging, the source paging subtree stays mounted and destination grids preload within its host; edge paging waits for target geometry and a 500ms dwell interval. Cancellation restores scroll state without moving an occurrence. Drag edge detection includes the card center; pinch scaling preserves the content under the finger midpoint. |
| Widgets | Five gallery groups, sixteen family cards, bound-source previews and independent wide grid original/vertical/horizontal modes. Small week list and week view retain three date columns. Small grid uses the Today face. |
| Two-day widget | A real central separator slot reserves 6pt on each side. Equal-width columns clip their own content, keeping course cards clear of the divider at phone, tablet and gallery sizes. |
| Source attribution | Import the pinned Android attribution manifest and recent contribution records while keeping platform dependency disclosures accurate. |

Native source metadata preserves escaped pipes, full-width identifiers and U+0085/U+2028/U+2029 without treating them as record separators. Wide widget preview excludes future fixed-date courses from recurring week-one previews while preserving actual and transferred occurrences. Malformed wide-widget clocks remain unresolved and cannot advance the rolling window.

## Verification

The all-target simulator test build after the overlay-isolation repair (`build31-overlay-isolation-1064.log`, Xcode 27.2 / iOS 26.5 Simulator) succeeded. Its unit/integration run (`unit31-ipad-1064.xcresult`) executed 2,477 tests: all passed, zero skipped, and zero failed. This includes the foreground key-window lifecycle check.

Control checks cover all eight Classic switch combinations of on/off, left-to-right/right-to-left, and enabled/disabled, including the 52 × 32pt track, thumb geometry and colors. They also check real UISwitch hierarchies in both layout directions and enabled/disabled states, a real UISegmentedControl hierarchy, resolved native button-style environment propagation, and rendered pixels proving a circular native icon button with clear bounding-box corners and a real 44pt touch target.

Before the overlay-specific repair, the complete phone drag run (`phone29-drag-all-1064.xcresult`) passed all seven cases with zero skips or failures. These cover horizontal movement, stationary hold, hovered destinations, outside-grid cancellation, both stationary edges, ordinary detail taps, undo/redo and persistence. The same source's iPad run (`ipad29-editor-settings-adaptation-1064.xcresult`) passed all 40 cases with zero skips or failures: ten course-editor, eight device-adaptation and 22 settings cases. The checked simulator models were iPhone SE (3rd generation), 375 × 667pt, and iPad mini (A17 Pro).

The added covered-course gesture test failed on the unrepaired build (`phone30-overlay-red-1064.xcresult`): dragging over Create Course moved the hidden course. With disabled-state propagation applied, that exact test passed in the source31 phone run, checking the original frame, occurrence day/node/week range, absent undo/redo, and unchanged data after relaunch. The original seven drag cases were retained without weaker assertions.

PR acceptance repeats the build and all 2,477 unit/integration tests plus all 182 UI cases on GitHub's Xcode 26.3 toolchain. Three independent simulator jobs cover eight drag cases, 65 settings/control cases and 109 remaining UI cases; test execution within each simulator remains serial. The PR checks report the outcome for their exact candidate revision.

## Platform validation boundary

Simulator builds and production-view image rendering do not validate signed App Groups, actual Home Screen WidgetKit placement/refresh, device notification delivery, ActivityKit, a paired Watch, authenticated school accounts, or iOS 15.6 runtime behavior. Phone/tablet rotation tests do not cover Stage Manager or every split-view size. Selected large-text cases do not establish whole-app maximum-text or VoiceOver coverage.

WidgetKit configuration is stored per widget kind in this implementation; Android stores per widget instance. Liquid Glass controls use iOS system glass styles on iOS 26, native bordered styles on iOS 17–25, and explicit circular material compatibility surfaces for icon actions on iOS 15/16. The older runtime branches compile but were not exercised on an installed older runtime. Android-only background reliability/DND/system services retain their iOS platform counterparts.
