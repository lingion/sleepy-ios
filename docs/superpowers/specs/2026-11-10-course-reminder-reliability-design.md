# Course reminder reliability

Approved scope: independent notification and Live Activity switches; occurrence-based notification planning; iOS 26 local Live Activity scheduling; conservative failure handling; accurate course cards and coverage information.

## Contracts

- Keep iOS 15.6 support, watchOS 10 support, and existing user data and signing configuration.
- Ordinary notifications remain enabled by default, including for legacy users who selected Live Activities without explicitly disabling notifications. Explicitly disabled channels remain disabled.
- Both channels consume the same dated occurrences, including semester bounds, odd/even weeks, fixed dates, holidays, transfers, per-table settings, and custom class times.
- Identify a course occurrence by table ID, course ID and absolute start time. Repeated occurrences must not replace one another.
- Only record successfully accepted notification requests. Bound scheduling to available application capacity and process nearest reminders first.
- Schedule a small bounded number of upcoming Live Activities on iOS 26 from the foreground, reuse matching requests, cancel obsolete requests, and retain ordinary notifications on failure. Older systems continue local foreground activities.
- Keep configured ordinary notifications after activity acceptance. Only suppress a matching foreground presentation while the scheduled activity is active. Possible duplicate background alerts are an explicit reliability tradeoff.
- Do not claim that a timer changes arbitrary view state, that staleDate ends an activity, or that background refresh runs on a deadline.
- Scheduled cards use fixed course times and system-managed countdown rendering. Mark expired content accurately; reconcile ending when execution is available.
- Expose accepted activity count and limited coverage. Do not promise unattended semester-long operation.
- Validate pure planning, migrations, failure paths, repeated occurrences, and both app/extension builds. Validate system behavior only as far as the available simulator/device actually demonstrates.

## Sources

- https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:style:alertconfiguration:start:)
- https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- https://developer.apple.com/documentation/widgetkit/displaying-dynamic-dates
- https://developer.apple.com/documentation/usernotifications/scheduling-and-handling-local-notifications

## Delivery

Implement and verify in an isolated worktree. Apply only this task's changes to the original working directory, preserving unrelated local changes. The user subsequently authorized creating and merging a PR on November 10, 2026. Publish the scoped topic branch and merge only after verification; preserve App Store signing.
