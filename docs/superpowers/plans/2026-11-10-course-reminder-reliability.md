# Course Reminder Reliability Implementation Plan

> **For agentic workers:** Execute this plan inline using executing-plans. The user explicitly requires single concurrency; do not dispatch subagents.

**Goal:** Make Sleepy course reminders reliable across independent notification and Live Activity channels without a server.

**Architecture:** Build dated reminder occurrences once and feed notifications and activities from that source. Reconcile accepted system requests instead of assuming a foreground timer or local notification can wake the app.

**Tech Stack:** Swift 5, SwiftUI, UserNotifications, ActivityKit, XCTest; installed iPhoneOS 27.2 SDK, iOS 26.5 simulator.

## Global Constraints

- iOS deployment target remains 15.6; watchOS remains 10.0.
- Single concurrency, preserve explicit channel choices and unrelated local changes.
- iOS 26 scheduling requires AlertConfiguration; pending activities count toward the system limit.
- Keep configured ordinary notifications even after activity acceptance; no silent-audio or background-mode workarounds.

### Task 1: Independent preferences

Files: AppPrefs.swift, ReminderScreen.swift, ClassDayActivityCore.swift, ReminderModeAndTableReminderTests.swift.

- [x] Add an independent persisted activity boolean with legacy fallback; remove UI mutual exclusion.
- [x] Keep explicit banner=false; otherwise default banner=true. Keep legacy mode adapters for compatibility.
- [x] Test independent round trips and migrations, including both channels disabled and legacy fluid selection.

### Task 2: Dated occurrences and accepted notification ledger

Files: new widget/notification/CourseReminderOccurrence.swift, NotificationScheduler.swift, NotificationSchedulerTests.swift.

- [x] Move date/holiday/transfer/time resolution into the common occurrence loader.
- [x] Generate identifiers from table ID, course ID and start epoch, and sort by reminder time.
- [x] Make the notification port await acceptance, enforce an explicit capacity budget, and write only accepted IDs.
- [x] Remove legacy course-only IDs and the ineffective midnight local-notification wake-up anchor.
- [x] Test transfer duplicates, fixed dates, ordering/capacity, add failure, deletion, and repeated synchronization.

### Task 3: Reconcile scheduled activities

Files: ClassDayActivityManager.swift, ClassDayActivityCore.swift, SleepyClassActivityAttributes.swift, SleepyClassLiveActivity.swift, SleepyApp.swift; new activity plan tests.

- [x] Use the common occurrence list and a bounded nearest-first activity plan.
- [x] Reuse pending requests on iOS 26; request future activities with start:, .standard, and an alert configuration.
- [x] Keep older-system foreground starts, guard .stale with iOS 16.2 availability, and cancel removed/expired requests.
- [x] Preserve queued notifications even after an activity is accepted. Suppress only duplicate foreground presentation while the matching scheduled activity is active; accept possible background duplicate alerts to protect the fallback.
- [x] Render fixed start/end times with a stable countdown; do not depend on Date() branches for phase transitions.
- [x] Expose request coverage/errors without claiming automatic ending or semester coverage.

### Task 4: Verification and delivery

- [x] Generate project entries for new files, inspect generated project changes, run focused unit tests with parallel testing disabled.
- [x] Run app and widget simulator builds and applicable watch compatibility checks.
- [x] Exercise independent toggles and a short scheduled activity in the simulator when supported; record unsupported behavior accurately.
- [x] Review diffs for failed-request loss, stale pending activities, migration regressions and data/signing changes.
- [x] Apply only task edits to the original directory and verify the integrated build.
- [x] Save a concise verification report including exact results and remaining physical-device limitations.

## Verified delivery

- Worktree full unit suite: 2099 tests, 8 pre-existing resource-related skips, 0 failures.
- Integrated original checkout full unit suite: 2099 tests, the same 8 skips, 0 failures; two real ActivityKit scheduling tests passed without skips.
- Integrated reminder UI suite: all 5 tests passed. The separate notification-denied UI test also passed.
- App, iPhone widget, Watch app and Watch widget compiled and linked.
- UI test repairs cover localized permission alerts, partially clipped switches, animation completion and launch readiness.
- Original Watch scheme and all 34 pre-existing untracked files preserved; project source additions merged incrementally.
- No physical-device force-quit, long-lock or low-power claims. No commits or publishing to the original branch.

## PR integration on current master

- User authorized PR creation and merge on November 10, 2026. The publishing branch is isolated from the dirty original checkout.
- Integrated against upstream `ba01f83` (code baseline `f36fddf`; the later commit changes distribution documentation only). Retained the upstream FIFO notification gate, injected daily-summary seams, and setting rechecks across asynchronous work.
- Updated the serialization regression port for accepted request results and occurrence identifiers. Its five tests passed.
- Complete simulator unit suite: **2295 tests, 0 failures, no skipped tests**. Both real ActivityKit scheduling tests passed.
- Simulator app, iPhone widget, Watch app, Watch widget and both test bundles built successfully.
- Notification-permission-denied UI regression: **1 test, 0 failures, no skip**.
- Validation used iOS 26.5 and disabled test parallelism with one Xcode job. The local unsigned XCTest host failed to connect; simulator-only ad hoc signing restored injection without changing source or release signing settings.
- Added compile-time protection for Xcode 16.4 / Swift 6.1: SDKs before Swift 6.2 keep foreground activities, and do not parse iOS 26 scheduling symbols. After this change the complete unit suite again passed **2295/2295**, including both real ActivityKit tests without skips.
- Final combined regression after toolchain protection: **2295 unit tests + 5 reminder UI tests, 0 failures** (`xcodebuild test`, one job, parallel testing disabled). The notification-denied UI test passed separately.
