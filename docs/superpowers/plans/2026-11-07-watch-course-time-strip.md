# Watch Course Time Strip Implementation Plan

> **Execution record:** Source and static-inspection steps are checked below. Checked boxes do not imply that XCTest, compilation, paired synchronization, or device acceptance have run; those limitations are recorded in the implementation status.

**Goal:** Add a seventh, rectangular-only Watch widget whose course and free-time segments move left at a fixed 90-minute scale on system timeline updates, with an iPhone-controlled tomorrow preview.

**Architecture:** A Foundation-only core clips occupied/free intervals into a fixed time window and chooses today or tomorrow-preview state. A dedicated WidgetKit provider precomputes a bounded 24-hour timeline from one loading pass over the Watch-local database. A small App Group preference snapshot carries the new option, app language and timetable transfer mappings from the existing WatchConnectivity snapshot to the independent widget process.

**Tech Stack:** Swift 5.8, SwiftUI, WidgetKit, WatchConnectivity, GRDB, XCTest, XcodeGen.

## Global Constraints

- watchOS deployment remains 10.0; iOS deployment remains 15.6.
- Keep all six existing Watch widget kinds and their behavior unchanged.
- User accepted system-scheduled updates on 2026-11-07; no perpetual animation, TimelineView animation loop or per-second reload requests.
- One full width always represents 90 minutes; durations do not rescale between classes. Gaps, including lunch, keep actual elapsed-time width.
- Add `WatchTimeStripWidget` only for `.accessoryRectangular`; no new app/extension target.
- iPhone setting defaults off and is specific to the new widget, separate from nearest-busy-day and reminder settings.
- Preserve existing calendar/dayItems semantics, including period-table resolution, custom times and transfer mappings.
- No local test suites, builds, simulators, package installations or >1 GB operations. Lightweight source checks and project generation only. Tests and device QA remain unverified until authorized CI/device execution.
- Do not commit, push, create a PR or alter another worktree without user authorization.
- No HTML prototype. Use existing native design vocabulary and system widget foreground/accent rendering, with shape/text distinctions rather than a new categorical palette.

## Product contract

- Live window is `[entry.date, entry.date + 90 minutes)`. Ended course portions disappear from the left. Future portions enter from the right.
- For a 90-minute class followed by a 30-minute gap, at +30 minutes the visible split is 60/30. For a 22-minute gap, the split is 60/22/8 when the next class immediately follows that gap.
- Courses are clipped at both boundaries. Partition overlapping course intervals into simultaneous-course segments, rather than double-counting occupied width or inventing gaps.
- Empty time between classes is a break; before the first class/after the last class it is free time. Tiny segments keep their true widths; omit visible text rather than imposing a minimum width. Accessibility retains names and time bounds.
- Before the first class, display real current time (no early-start illusion). With no classes, show a meaningful empty state. After the last class, default to “Today’s classes are finished.”
- If tomorrow display is enabled and today has finished (including an empty today), show the next calendar day only. No nearest-busy-day jumps. Empty tomorrow says “No classes tomorrow.”
- Tomorrow preview begins at its first course and advances one schedule minute per elapsed minute since today’s final class (or today’s midnight when today has no classes). It repeats from the first course after reaching tomorrow’s last end. The header always says tomorrow preview plus its date, and the footer shows the preview’s time window; it never says “Now.” Midnight returns to the new day’s live mode.
- Phone path: Me → Widgets → Apple Watch course time strip → Show tomorrow after today ends. Explain 90-minute width, system refresh and the distinct preview.
- Request five-minute entries plus course boundaries and local midnight; actual display timing remains controlled by WidgetKit. Build at most a 24-hour timeline; load current and following calendar days once, not once per entry. Timeline end requests replenishment.
- Apply the shared preference snapshot before reloading Watch timelines. New payload field is optional so already-installed phones without that field still decode and default off.

## File responsibilities

- `Sleepy/widget/WatchTimeStripCore.swift`: pure geometry, day selection, preview offset, entry date generation.
- `Sleepy/widget/WatchTimeStripPreferences.swift`: one-key, App Group-backed Codable settings snapshot; injectable UserDefaults for tests.
- `Sleepy/widget/WatchAgendaCore.swift`: overload accepting explicit display mode and transfer mappings; existing overload forwards its existing settings.
- `SleepyWatchWidgets/WatchTimeStripProvider.swift`: load local schedule once and convert future dates to entries.
- `SleepyWatchWidgets/WatchTimeStripView.swift`: compact header, proportional strip, time labels, empty states, VoiceOver description.
- `SleepyWatchWidgets/WatchWidgets.swift`: register the seventh widget.
- `Sleepy/util/AppPrefs.swift`: new phone option key and getter/setter.
- `Sleepy/sync/WatchSyncSnapshot.swift`: optional payload field, capture and application into shared store.
- `Sleepy/ui/screen/mine/WidgetSettingsScreen.swift`: native settings section and explicit Watch sync trigger.
- Five `Sleepy/resources/*.lproj/Localizable.strings`: new feature and settings copy in each supported language.
- `SleepyTests/WatchTimeStripCoreTests.swift`, `WatchTimeStripPreferencesTests.swift`: deterministic geometry, timeline, preferences, compatibility tests.
- `SleepyUITests/WatchTimeStripSettingsUITests.swift`: settings discoverability and persisted toggle behavior.
- `Sleepy.xcodeproj/project.pbxproj`: generated registrations for new files, no unrelated project changes.

### Task 1: Geometry and timeline

**Interfaces:**
- Consumes `[WatchAgendaCore.ClassItem]` with concrete start/end dates.
- Produces `WatchTimeStripCore.snapshot(now:today:tomorrow:showsTomorrow:calendar:) -> Snapshot`.
- `Snapshot` carries `state`, `day`, `windowStart`, `segments`, and `items`; `windowEnd` derives from the fixed window duration.
- `Segment` carries `start`, `end`, `courses`, and `isBreak`; fractions come from `(clippedDate - windowStart) / windowDuration`.
- Produces `timelineDates(now:courseBoundaries:calendar:) -> [Date]`, strictly increasing and bounded to 24 hours.

- [x] Write tests first for full first class, 60/30, 60/22/8, last-class completion, clipping, unsorted/invalid inputs, overlap union, true long gaps, tomorrow opt-in/off/empty/repeat, midnight and five-minute timeline bounds.

```swift
let snapshot = WatchTimeStripCore.snapshot(
    now: date(8, 30), today: [item("A", 480, 570), item("B", 600, 690)],
    tomorrow: [], showsTomorrow: false)
XCTAssertEqual(snapshot.segments.map { $0.end.timeIntervalSince($0.start) / 60 }, [60, 30])
XCTAssertEqual(snapshot.windowEnd.timeIntervalSince(snapshot.windowStart), 90 * 60)
```

- [x] Implement interval sweep: filter invalid dates, sort; clip class starts/ends into the window, partition unique boundaries, select all active courses per subinterval, and label empty subintervals as breaks only between the first start and last end.

```swift
let start = max(item.startDate, windowStart)
let end = min(item.endDate, windowEnd)
if start < end { boundaries.formUnion([start, end]) }
```

- [x] Implement exact calendar-day transitions and a deterministic preview offset using elapsed time modulo the next-day course span. No persistent animation counters.

```swift
let offset = max(0, now.timeIntervalSince(previewAnchor))
    .truncatingRemainder(dividingBy: lastEnd.timeIntervalSince(firstStart))
let previewStart = firstStart.addingTimeInterval(offset)
```

- [x] Add one-day timeline dates at five-minute increments, all valid course boundaries in that interval, midnight and horizon. Deduplicate/sort; no timer tasks.
- [x] Inspect new tests against the product examples; record that RED/GREEN execution is deferred, not passed.

### Task 2: Phone option and shared Watch state

**Interfaces:**
- `AppPrefs.isWatchTimeStripTomorrow() -> Bool`, `setWatchTimeStripTomorrow(_:)`.
- `WatchSyncSnapshot.PrefsSnapshot.timeStripTomorrow: Bool? = nil`; missing means false at the use site.
- `WatchTimeStripPreferences` has `showsTomorrow`, `language`, `transfers`.
- `WatchTimeStripPreferencesStore(defaults:)`, `.shared`, `load()`, `save(_:)`, `apply(_ snapshot: WatchSyncSnapshot.PrefsSnapshot)`.
- Explicit agenda overload: `dayItems(table:courses:date:displayMode:transfers:)`.

- [x] Write isolated UserDefaults tests for default false, persisted true/false, two independent suite instances, replaced mappings/language, malformed shared data, and old payload missing the new field.

```swift
var prefs = WatchSyncSnapshot.PrefsSnapshot()
prefs.timeStripTomorrow = true
store.apply(prefs)
XCTAssertTrue(reader.load().showsTomorrow)
```

- [x] Add key/getter/setter and optional snapshot field, populate capture, and apply to the shared store before the existing WatchStore timeline reload.
- [x] Preserve existing agenda callers; make the new overload receive transferred mappings explicitly instead of reading the extension’s unrelated standard defaults.
- [x] Add the phone settings card with a semantic native Toggle, stable accessibility identifier and existing theme colors. On change persist and call `WatchSyncCoordinator.shared.scheduleSync()`.
- [x] Add localized strings in all five locales and a UI persistence test. Never treat local state alone as proof the Watch received the option.

### Task 3: Widget integration

**Interfaces:**
- `WatchTimeStripEntry: TimelineEntry` contains the snapshot and language.
- `WatchTimeStripProvider: TimelineProvider` creates entries from local GRDB and shared preference state.
- `WatchTimeStripView(entry:)` renders the snapshot only, with no fetches or writes.

- [x] Add provider with actual example placeholder, one data-loading pass per timeline, day-indexed agendas, five-minute/boundary entries, and `.atEnd` replenishment.
- [x] Add native rectangular view. Block x/width derive only from normalized intervals; clipping and strokes remain inside those bounds. Course blocks are solid/accented; free/break blocks outlined, with text when space permits.
- [x] Use entry language for localized widget copy, explicit date label for tomorrow, fixed window time labels, full accessible interval descriptions, and existing `sleepy://watch?tab=today` deep link.
- [x] Add new `StaticConfiguration` and bundle member; retain existing six configurations untouched.
- [x] Generate project using existing XcodeGen, retain only new file registrations, and verify target membership (shared core/store in all relevant targets, UI/provider only Watch widget, tests only tests).

### Task 4: Evidence and review

- [x] Run `git diff --check`, plist/string syntax validation and lightweight Swift parse-only checks; no build/type-check/test claim.
- [x] Check localized-key coverage and generated project references with bounded text/static inspection.
- [x] Read-only review focused on geometry, class/preview transitions, stale timelines, cross-process settings and old-payload decoding; repair confirmed issues.
- [x] Document exact unverified checks: XCTest, iOS and Watch compilation, paired sync while disconnected/reconnected, full-color/accented/Always On rendering, narrow segment clipping and system-controlled refresh.
- [x] Show source diff and deliver a concise status. No push or commit in this task without another user instruction.

## Implementation status

Source implementation is on `feat/watch-course-time-strip`, based on upstream `9f0cf9f`, split into geometry/agenda, preference synchronization, and widget integration commits. Initial verification below was source-only; runtime CI results are recorded on the pull request rather than inferred from these checks.

- The new kind is registered without changing the six existing configurations.
- The phone option, optional sync field, shared settings blob, explicit agenda transfer mapping, and extension rendering are wired.
- Added 33 XCTest/UI test methods across four files; these were authored but not executed. No RED/GREEN claim is made.
- Independent source review completed and identified one defect: live windows crossing midnight omitted the following day's intersecting classes. The core now includes only those intersecting next-day intervals, without changing the end-of-today opt-in rule. Three regression cases cover the crossing window, out-of-window tomorrow data, and the final-class transition. Updated core/test sources passed parse-only checks after this change.
- `xcodegen generate --spec project.yml` succeeded; its only tracked project change is 44 added file-registration lines.
- Swift frontend parse-only checks succeeded for all changed/new Swift files, including a separate `WATCH_APP` conditional-compilation pass. This does not establish type correctness or a successful build.
- `plutil -lint` succeeded for the generated project and five localization files. All five locales contain the same 14 new unique keys.
- Static project inspection confirms all eight new source/test files are in their expected targets; `git diff --check` and new-file whitespace checks are clean.
- Full compile, XCTest, UI execution, paired WatchConnectivity delivery, watch-face/Smart Stack visual acceptance, and actual refresh timing remain unverified under the machine-resource restriction.

## Authorized CI/device verification (not run locally)

Existing `.github/workflows/ios-build.yml` regenerates the project, builds app/extensions/test bundles, runs `SleepyTests`, then native UI acceptance. New XCTest/UI files join those targets automatically. When CI is authorized, run that complete gate; also verify the Watch target in a paired environment because iOS unit tests cannot prove WidgetKit rendering or WatchConnectivity delivery. Check the 90/30 and 90/22 examples on an actual rectangular widget, turn tomorrow off/on in the phone, disconnect/reconnect, advance through the final class and midnight, and inspect empty tomorrow and overlapping courses.

## Sources

- Apple: https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
- Apple: https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities
- Apple: https://developer.apple.com/documentation/widgetkit/widgetfamily/accessoryrectangular
