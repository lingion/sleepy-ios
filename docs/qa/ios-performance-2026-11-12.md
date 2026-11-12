# iOS performance verification — 2026-11-12

The changes remove repeated date formatting, course projection, holiday preference decoding, theme derivation and state publication from the launch/render/navigation paths. Layout, transitions, theme interpolation and course gestures retain their existing behavior.

## App measurements

Baseline production: `2c77f5ba`. Final candidate production: `ce102ec6`. The same UI measurement harness was compiled into both builds. Xcode 27.2, Debug, iPhone 17 simulator running iOS 27.0, one simulator and serial execution. Each test seeds five courses once, removes the seed launch argument, then records five iterations. Paging uses the cards grid and classic theme, English, Asia/Shanghai. These are light UI fixtures, not a 252-course stress test.

| Workload, per iteration | Baseline mean | Candidate mean | Change |
| --- | ---: | ---: | ---: |
| Four weeks forward and four back, App CPU | 2.341 s | 1.712 s | −26.9% |
| Same paging, retired instructions | 23,943,486 kI | 21,086,721 kI | −11.9% |
| Tab/settings round trip, App CPU | 1.166 s | 1.075 s | −7.8% |
| Same navigation, retired instructions | 9,844,974 kI | 8,282,013 kI | −15.9% |
| Paging, peak physical memory | 102,370 kB | 101,764 kB | Within observed noise |
| Navigation, peak physical memory | 78,944 kB | 78,125 kB | Within observed noise |

These measurements cover app-process work during automated interactions. They do not measure tap-to-frame latency. CPU totals cannot establish FPS or hitch rate. `XCTHitchMetric` was requested but returned no numeric result. There is no supported claim of 60/120 FPS, and no Release or physical-device performance comparison in this report.

Launch-to-responsive was unstable between runs:

| Run | Mean | XCTest relative standard deviation |
| --- | ---: | ---: |
| Initial baseline | 9.817 s | 17.4% |
| Initial candidate | 7.952 s | 17.7% |
| Final candidate after full test suite | 19.190 s | 42.2% |
| Subsequent baseline control, preserved baseline binary | 12.011 s | 12.7% |
| Immediately following final candidate control | 10.571 s | 5.7% |

The control pair did not reproduce the large final-suite slowdown. It also does not justify a stable launch speedup percentage: host/simulator effects and the inconsistent earlier run remain. A partial launch trace contained 560 main-thread samples, 417 in simulator pre-main dynamic loading; it contains no recorded first-frame/first-responsive endpoint and cannot explain the complete launch interval. Database migration and required initialization were retained. A longer all-process paging trace failed to save after disk exhaustion and is excluded from the evidence.

Raw per-iteration app samples, including the slow launch run, are in `ios-performance-2026-11-12-metrics.json`. Initial/final UI workload comparisons are one before/after group; they cannot attribute a percentage to an individual optimization.

## Component evidence and bounds

| Change | Measurement | Scope |
| --- | --- | --- |
| Fixed civil-day formatters and loop invariants | Dense three-week/252-course/12-transfer Foundation projection: about 194–215 → 0.734–0.759 ms across reversed A/B run order | Standalone `swiftc -O` helper, not app UI timing; output digests match in Shanghai and Los Angeles |
| Separate fixed short/full display formatters | 16,000 concurrent calls: 694 wrong-format results → 0; alternating-format median 477.629 → 357.006 ms over seven batches of 600,000 calls | Repeated short-date timing was within noise; no speed claim for it |
| Theme endpoint/vector reuse | Final same-process system terminal vector: 50.911 → 2.860 µs; custom original derivation/vector path: 105.865 → 3.950 µs | Warm endpoints only; interpolation still runs normally |
| Batched state publication | Initial load 10 → 2 publications; week change 2 → 1; repeated selected week → 0 | Complete state snapshots; table selection still replaces its course subscription |
| Week projection reuse | 252-course, three-page warm cache: 0.855 → 0.000808 ms/page | Cache hit only, not first projection, layout, or FPS |
| Holiday batching | Entire 21-day viewport: 7.190 → 0.174 ms | Old per-day calls versus one batch; all eight preference combinations agree |
| Entity equality for drag-source changes | 64 passes over 42 unchanged cards: JSON comparison 14.306 → direct equality 0.032 ms | Standalone helper; metadata edits still detected |
| Native Tab appearance | Repeating the same theme 100 times adds no appearance assignment; a changed theme/system reset still applies | Actual UIKit state is checked; transparent transition canvas retained |

Theme caches hold at most 16 endpoints/vectors. The custom-document cache holds one document up to 32 KiB; larger imports bypass it. Week projection holds four pages with complete input equality. Holiday work is restricted to current/adjacent weeks plus a pinned drag source, at most four weeks. Editing course contents, dates, timetable/time slots, transfers, holiday preferences/data or theme seeds invalidates the corresponding input; cancellation and stale holiday responses are guarded.

An extra provider-level system/preset scheme cache was tried and removed after it added lock overhead to preset resolution. Presets now return their existing static scheme directly. No cache stores animation intermediates.

## Verification and reproduction

- Final production build-for-testing succeeded; 2,652 unit tests and three opt-in app performance tests passed with zero failures.
- Three existing navigation tests passed with zero failures: classic and native Tab/settings round trips, ordinary week buttons and stationary long press. Video review is recorded separately from the comparative performance run.
- The new performance UI suite refuses physical-device execution. It is opt-in; ordinary CI skips its measurements. A separate default-environment run confirmed 12 timing tests skipped and six theme correctness tests passed, with zero failures. Timing probes have no absolute latency assertions in correctness CI.
- The measurement fixture clears courses/timetables and changes preferences in its test app container. Use a dedicated disposable simulator. It is not a fully isolated preference reset, so reuse the same prepared simulator for A/B comparisons.
- Existing date, theme, stale-data, selection/clamping, holiday and projection tests cover correctness independently of timing.
- Complex drag, cross-week move and resize acceptance remains manual; it was not automated during this work.

To reproduce, duplicate the local `Sleepy` scheme, disable the debugger for its Test action, and set `SLEEPY_RUN_PERFORMANCE_TESTS=1` in that action's environment. A variable exported only in the invoking shell does not reliably configure the XCTest runner. Keep the same build configuration, simulator, fixtures, preferences and five iterations for both revisions, and do not record video or profile during comparative measurements.

```sh
xcodebuild test -project Sleepy.xcodeproj -scheme 'Sleepy Performance' \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SLEEPY_PERF_SIMULATOR_ID" \
  -parallel-testing-enabled NO \
  -only-testing:SleepyUITests/InteractionPerformanceUITests \
  -resultBundlePath /tmp/sleepy-performance.xcresult

xcrun xcresulttool get test-results metrics \
  --path /tmp/sleepy-performance.xcresult --compact
```

The local performance scheme is deliberately not committed. Component probes in `ThemeCacheProbeTests`, `HolidayViewportTests` and `WeekProjectionCacheTests` use the same opt-in variable. Default CI remains a correctness check and does not impose a simulator timing gate.
