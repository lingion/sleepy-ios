# TEST_INFRA — Educational Import Modal & Interaction Polish Test Architecture

**Project:** sleepy-ios  
**Scope:** Educational Import Modal Gesture Support & Interaction Polish  
**Reference Document:** `ORIGINAL_REQUEST.md`, `PROJECT.md`  
**Test Integrity Standard:** Independent, self-contained, reproducible tests across 4 Tiers.

---

## 1. Executive Summary & Test Infrastructure Overview

This document specifies the automated testing infrastructure and test suite architecture for the `sleepy-ios` educational import modal (`JwImportFlow`, `SchoolSelectScreen`, `JwWebViewLoginScreen`, `ExitDraftState`, `AlphabetIndexBar`).

### Test Targets & Frameworks
- **Unit & Logic Integration Testing (`SleepyTests/`)**:
  - Framework: `XCTest`
  - Target: `SleepyTests` (iOS Unit Test Bundle hosted by `Sleepy.app`)
  - Execution Command:
    ```bash
    xcodebuild test -project Sleepy.xcodeproj -scheme Sleepy \
      -destination 'platform=iOS Simulator,name=iPhone 17' \
      -only-testing:SleepyTests/<TestSuiteName> \
      -derivedDataPath build/DerivedData \
      CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO
    ```
- **UI & Gesture Interaction Testing (`SleepyUITests/`)**:
  - Framework: `XCTest` (`XCUIApplication`, `XCUICoordinate`)
  - Target: `SleepyUITests` (iOS UI Test Bundle)
  - Execution Command:
    ```bash
    xcodebuild test -project Sleepy.xcodeproj -scheme Sleepy \
      -destination 'platform=iOS Simulator,name=iPhone 17' \
      -only-testing:SleepyUITests/<TestSuiteName> \
      -derivedDataPath build/DerivedData \
      CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO
    ```

---

## 2. 4-Tier Test Architecture

```
+-------------------------------------------------------------------------+
|                  Tier 4: Real-World User Scenarios                     |
|  - Casual browsing & cancel       - Interrupted login & recovery        |
|  - Wrong school step-back         - Alphabet jump & scroll dismiss      |
|  - Full capture & draft protection                                      |
+-------------------------------------------------------------------------+
|                Tier 3: Cross-Feature Combinations (Pairwise)             |
|  - F1 x F4 (Dismiss x State Reset)  - F2 x F8 (Intercept x Back Nav)    |
|  - F5 x F1 (IndexBar x Pull Down)   - F6 x F1 (Keyboard x Dismiss)      |
|  - F7 x F2 (Transition x Intercept) - F3 x F1/F2 (Drag Indicator x Flow) |
+-------------------------------------------------------------------------+
|               Tier 2: Boundary, Edge & Corner Cases                     |
|  - Clamped coordinates (Y < 0, Y > H)   - Zero/single letter sets       |
|  - Extreme search strings (>500 chars)   - Rapid repetitive gestures     |
|  - Concurrent transitions & mutations   - Memory leak / lifecycle safety|
+-------------------------------------------------------------------------+
|                     Tier 1: Feature Coverage                            |
|  - >=5 Test Cases per Feature (Features 1 through 9)                    |
|  - Happy-path validation of state machine transitions & UI affordance   |
+-------------------------------------------------------------------------+
```

---

## 3. Tier 1: Feature Coverage (>=5 Test Cases per Feature)

### Feature 1: Swipe-Down Dismissal in No-Progress Stage (`selectSchool`)
*Authoritative Source: ORIGINAL_REQUEST §R1, PROJECT.md Feature 1*

| Test ID | Name | Preconditions | Input / Action | Expected Output |
|---|---|---|---|---|
| `F1-T1-01` | Initial state allows direct exit | Flow launched at `.selectSchool` | Call `reduceExitDraftState(initialState, .requestExit)` | `outcome == .finishDirectly`, `confirmationVisible == false` |
| `F1-T1-02` | `onActiveImportChanged` reports inactive | Initial stage `.selectSchool` | Inspect published `activeImport` binding | `activeImport == false`, sheet allows interactive dismiss |
| `F1-T1-03` | Sheet interactive dismiss disabled flag is false | `jwActiveImport == false` | Inspect `.interactiveDismissDisabled` parameter | Parameter evaluates to `false` |
| `F1-T1-04` | Close button in `selectSchool` triggers exit | User in `selectSchool` | Tap header close button (`xmark`) | `requestExit()` called, flow terminates directly |
| `F1-T1-05` | Downward swipe dismisses modal | Sheet presented at `selectSchool` | User performs swipe-down drag on sheet top | Sheet dismisses smoothly, `onFinish()` called |

### Feature 2: Swipe-Down Interception & Attempt-to-Dismiss Hook
*Authoritative Source: ORIGINAL_REQUEST §R1, PROJECT.md Feature 2*

| Test ID | Name | Preconditions | Input / Action | Expected Output |
|---|---|---|---|---|
| `F2-T1-01` | Selecting school activates import lock | School chosen in `selectSchool` | Transition to `.webViewLogin` | `activeImport == true`, `onActiveImportChanged(true)` emitted |
| `F2-T1-02` | Reducer intercepts exit when active | `activeImport == true` | `.requestExit` action | `outcome == .none`, `confirmationVisible == true` |
| `F2-T1-03` | Confirmation dialog presents 3 options | `confirmationVisible == true` | Inspect dialog action buttons | Options: Continue (`continueImport`), Keep Draft (`keepDraft`), Delete Draft (`deleteDraft`) |
| `F2-T1-04` | Dismiss attempt in `preview` stage intercepts | Flow in `.preview` stage | Swipe-down gesture or dismiss attempt | Sheet stays open, confirmation dialog appears |
| `F2-T1-05` | Dismiss attempt in `configureConfirm` stage intercepts | Flow in `.configureConfirm` stage | Swipe-down gesture or dismiss attempt | Sheet stays open, confirmation dialog appears |

### Feature 3: System Drag Indicator & Sheet Affordance
*Authoritative Source: ORIGINAL_REQUEST §R1, R2, PROJECT.md Feature 3*

| Test ID | Name | Preconditions | Input / Action | Expected Output |
|---|---|---|---|---|
| `F3-T1-01` | Presentation drag indicator configured visible | Sheet presented | Check `.presentationDragIndicator(.visible)` | Drag indicator visible at sheet top grabber bar |
| `F3-T1-02` | Drag indicator stays visible across stages | Flow transitions `.selectSchool` -> `.webViewLogin` | Inspect top grabber | Drag indicator remains visible and consistent |
| `F3-T1-03` | Modal sheet presentation detent set to large | Modal presented | Check presentation detent configuration | Large detent active, standard iOS sheet presentation |
| `F3-T1-04` | Sheet corner radius matches iOS HIG | Sheet displayed | Inspect view frame and corner styling | Smooth rounded sheet corners (10-12pt radius) |
| `F3-T1-05` | Sheet affordance does not occlude top navigation items | Sheet presented | Inspect top bar vertical spacing | Header elements clear system grabber area |

### Feature 4: State Store Cleanup on Swipe-Down
*Authoritative Source: PROJECT.md Feature 4, Survey Finding*

| Test ID | Name | Preconditions | Input / Action | Expected Output |
|---|---|---|---|---|
| `F4-T1-01` | Query resets on `resetForNewEntry()` | Store contains `query = "Peking"` | Call `store.resetForNewEntry()` | `store.query == ""` |
| `F4-T1-02` | `resumeLocationAfterSettings` resets | Flag set to `true` | Call `store.resetForNewEntry()` | `store.resumeLocationAfterSettings == false` |
| `F4-T1-03` | `expandedCity` resets | String set to `"Beijing"` | Call `store.resetForNewEntry()` | `store.expandedCity == ""` |
| `F4-T1-04` | `scrollLetter` resets | Letter set to `"B"` | Call `store.resetForNewEntry()` | `store.scrollLetter == nil` |
| `F4-T1-05` | Sheet `onDismiss` triggers store reset | Sheet dismissed via swipe down | Trigger `finishFlow()` | Store cleared for subsequent presentations |

### Feature 5: Alphabet Index Bar Gesture Deconfliction
*Authoritative Source: ORIGINAL_REQUEST §R2, PROJECT.md Feature 5*

| Test ID | Name | Preconditions | Input / Action | Expected Output |
|---|---|---|---|---|
| `F5-T1-01` | Letter tap calls `onLetterTap` | `letters = ["A", "B", "C"]` | Tap letter "B" coordinate | `onLetterTap("B")` invoked |
| `F5-T1-02` | Continuous drag calculates proportional letter index | Height 260pt, 26 letters | Drag to Y = 100pt (ratio ~0.38) | Maps accurately to letter "J" (`Int(0.38 * 26) = 9`) |
| `F5-T1-03` | Touch target confined to right strip | Width 32pt index bar | Drag gesture on left 90% of screen | Index bar does not capture or intercept touch |
| `F5-T1-04` | List vertical scrolling works without index bar hijacking | School list displayed | Swipe vertically on center list | List scrolls smoothly, no letter jump triggered |
| `F5-T1-05` | Sheet pull-down gesture enabled outside index bar | Sheet at top scroll position | Pull down from main screen area | Triggers sheet dismissal rather than index scrub |

### Feature 6: School Select Header & Keyboard Interaction
*Authoritative Source: ORIGINAL_REQUEST §R2, PROJECT.md Feature 6*

| Test ID | Name | Preconditions | Input / Action | Expected Output |
|---|---|---|---|---|
| `F6-T1-01` | Header uses modal close icon | In `selectSchool` header | Inspect leading button icon | Displays `xmark` (modal close) rather than navigation chevron |
| `F6-T1-02` | Close button action calls `onDismiss` | In `selectSchool` header | Tap leading close button | `onDismiss()` invoked |
| `F6-T1-03` | Search input filters school names | School list with 145 schools | Type `"清华"` | Filtered list contains Tsinghua University |
| `F6-T1-04` | List scroll dismisses keyboard | Keyboard active for search | Drag school list vertically | Keyboard dismisses (`.scrollDismissesKeyboard`) |
| `F6-T1-05` | Clearing search input restores full list | Search filtered to 1 school | Delete search text to `""` | All 145 schools restored with alphabet groupings |

### Feature 7: Stage Transition Animations
*Authoritative Source: ORIGINAL_REQUEST §R2, PROJECT.md Feature 7*

| Test ID | Name | Preconditions | Input / Action | Expected Output |
|---|---|---|---|---|
| `F7-T1-01` | Stage transition executes spring animation | At `.selectSchool` | Select valid school | Smooth transition to `.webViewLogin` |
| `F7-T1-02` | Back transition executes spring animation | At `.webViewLogin` | Tap back button | Smooth transition back to `.selectSchool` |
| `F7-T1-03` | Capture success transitions to preview | At `.webViewLogin` | HTML capture delivers courses | Smooth transition to `.preview` |
| `F7-T1-04` | Apply mode transitions to configureConfirm | At `.preview` | Select `.importAsNew` | Smooth transition to `.configureConfirm` |
| `F7-T1-05` | Error message cleared on stage change | `errorMsg != nil` at current stage | Change `stage` | `errorMsg` reset to `nil` |

### Feature 8: WebView Back Navigation to School Select
*Authoritative Source: ORIGINAL_REQUEST §R2, PROJECT.md Feature 8*

| Test ID | Name | Preconditions | Input / Action | Expected Output |
|---|---|---|---|---|
| `F8-T1-01` | Top bar provides back navigation | At `.webViewLogin` | Inspect navigation bar | Back button is visible and hittable |
| `F8-T1-02` | Back button returns to school select | At `.webViewLogin`, cannot go back in webview | Tap back button | Stage transitions to `.selectSchool` |
| `F8-T1-03` | Returning to school select resets `activeImport` if uncaptured | Returned from `.webViewLogin` without draft | Check `exitDraftState.activeImport` | `activeImport == false`, swipe-down re-enabled |
| `F8-T1-04` | Returning to school select preserves search query | Query was `"Fudan"` before selecting | Return to `.selectSchool` | `SchoolSelectStateStore.shared.query == "Fudan"` |
| `F8-T1-05` | Exit button in WebView prompts confirmation | At `.webViewLogin` | Tap close / exit action | Confirmation dialog displayed |

### Feature 9: Comprehensive E2E & Regression Testing
*Authoritative Source: ORIGINAL_REQUEST §Acceptance Criteria, PROJECT.md Feature 9*

| Test ID | Name | Preconditions | Input / Action | Expected Output |
|---|---|---|---|---|
| `F9-T1-01` | Automated test suite executes cleanly | iOS Simulator iPhone 17 | `xcodebuild test` for `SleepyTests` | All test cases pass with 0 failures |
| `F9-T1-02` | No uncaught exceptions or force unwrap crashes | All unit tests | Execute test suite | 0 crashes, 0 fatal errors |
| `F9-T1-03` | Test suite runs under 60 seconds | Clean test execution | Measure execution duration | Total execution time within budget |
| `F9-T1-04` | Independent state per test case | Run tests in reverse order | Verify isolation | Tests pass in any execution order |
| `F9-T1-05` | UI test launch stability | `app.sleepyLaunch()` | Cold launch app in test | App launches within timeout without hang |

---

## 4. Tier 2: Boundary, Edge & Corner Cases (>=5 Test Cases per Feature)

### Feature 1: Swipe-Down Dismissal Boundary Cases
| Test ID | Name | Boundary Condition | Expected Behavior |
|---|---|---|---|
| `F1-T2-01` | Zero drag distance | User touches sheet top but does not move (drag distance 0) | Sheet snaps back to fully open position |
| `F1-T2-02` | Drag release below dismiss threshold | Downward drag distance < 30% of sheet height then released | Sheet snaps back to expanded state |
| `F1-T2-03` | Rapid flick dismissal | High velocity downward flick with small translation | Sheet completes dismissal via velocity inertia |
| `F1-T2-04` | Upward drag at top of sheet | Upward drag beyond sheet bounds | Rubber-banding resistance, no dismiss |
| `F1-T2-05` | Simultaneous swipe down and list scroll | Finger drag across boundary of header and scroll view | Scroll view offset respected; dismiss only if at offset 0 |

### Feature 2: Swipe-Down Interception Corner Cases
| Test ID | Name | Boundary Condition | Expected Behavior |
|---|---|---|---|
| `F2-T2-01` | Dismiss attempt during active HTML capture | User swipes down while `JwWebViewFrameCapture` is running | Dismiss blocked; confirmation dialog queues cleanly |
| `F2-T2-02` | Multiple rapid dismiss attempts | User swipes down repeatedly in rapid succession | Only 1 confirmation dialog presented, no duplicate views |
| `F2-T2-03` | Dialog backdrop dismiss | Tap outside confirmation dialog cards on dark scrim | Equivalent to `continueImport`: dialog hides, flow preserved |
| `F2-T2-04` | Restore incoming draft with corrupt payload | `incomingDraftId` points to deleted / corrupt row | Graceful fallback without crash, exit handling remains secure |
| `F2-T2-05` | Reducer invariance under duplicate `.requestExit` | Consecutive `.requestExit` actions dispatched | State remains `confirmationVisible == true`, outcome `.none` |

### Feature 3: Drag Indicator & Sheet Affordance Boundary Cases
| Test ID | Name | Boundary Condition | Expected Behavior |
|---|---|---|---|
| `F3-T2-01` | Compact vs Regular horizontal size class | App running on iPad or split-screen | Sheet modal adapts to form factor without clipping grabber |
| `F3-T2-02` | Extreme dynamic type scale (accessibility XXXL) | Large text font size enabled in system | Grabber bar does not overlap oversized header text |
| `F3-T2-03` | Dark mode high contrast | System high contrast enabled | Drag indicator remains visibly contrasted against sheet background |
| `F3-T2-04` | Device rotation during sheet drag | Device rotated while finger is dragging sheet | Sheet resizes cleanly without layout crash |
| `F3-T2-05` | Safe area insets with notch / dynamic island | Top safe area inset varies across devices | Drag indicator positioned below island/notch with proper margin |

### Feature 4: State Store Cleanup Boundary Cases
| Test ID | Name | Boundary Condition | Expected Behavior |
|---|---|---|---|
| `F4-T2-01` | Store reset called when already clean | Redundant `resetForNewEntry()` on empty store | Idempotent operation, no crash or side effects |
| `F4-T2-02` | Special unicode characters in query | `query = "🎓 Peking 123 🇨🇳"` | Cleans completely to `""` |
| `F4-T2-03` | Location permission settings roundtrip | User goes to Settings, toggles permission, returns | `resumeLocationAfterSettings` flags processed cleanly |
| `F4-T2-04` | Deep scroll state preservation | `scrollLetter = "Z"` | Cleared to `nil` on dismiss; preserved across WebView roundtrip |
| `F4-T2-05` | Memory footprint after store reset | Store reset after heavy search operations | No retained closures or memory leaks |

### Feature 5: Alphabet Index Bar Corner Cases
| Test ID | Name | Boundary Condition | Expected Behavior |
|---|---|---|---|
| `F5-T2-01` | Negative Y coordinate (above bar) | Touch drag coordinate `y = -50.0` | Clamped to index 0 (first letter) without underflow |
| `F5-T2-02` | Overflow Y coordinate (below bar) | Touch drag coordinate `y = height + 100.0` | Clamped to index `letters.count - 1` without overflow |
| `F5-T2-03` | Empty letter array | `letters = []` (no schools match) | Zero division guarded: no crash, no callback |
| `F5-T2-04` | Single letter array | `letters = ["A"]` | Ratio 0.0 to 0.999 maps strictly to index 0 |
| `F5-T2-05` | Rapid jitter drag | 100 drag updates per second across 2 adjacent letters | Debounced or stable callback without UI freeze |

### Feature 6: School Select Header & Keyboard Corner Cases
| Test ID | Name | Boundary Condition | Expected Behavior |
|---|---|---|---|
| `F6-T2-01` | Query with 1000 characters | Very long string typed into search | Handled safely, does not overflow UI or freeze thread |
| `F6-T2-02` | Query with regex meta-characters | `.*+?^${}()|[]\\` entered in search | Literal search without regex parser crash |
| `F6-T2-03` | Rapid typing while scrolling | Keyboard typing while user simultaneously scrolls list | Focus and scroll state remain synchronized |
| `F6-T2-04` | Hardware keyboard Return key | User presses hardware keyboard Return / Escape | Keyboard dismissed or modal dismissed cleanly |
| `F6-T2-05` | Zero matching schools | Search string matches no schools | Displays empty state prompt; close button still responsive |

### Feature 7: Stage Transition Edge Cases
| Test ID | Name | Boundary Condition | Expected Behavior |
|---|---|---|---|
| `F7-T2-01` | Rapid back-and-forth stage transitions | User rapidly toggles between selectSchool and webViewLogin | State machine remains consistent, no orphaned views |
| `F7-T2-02` | Nil school in configureConfirm | `stage == .configureConfirm` but `parsedSchool == nil` | Graceful fallback to `webViewLogin` without blank screen |
| `F7-T2-03` | Empty parsed courses in preview | `stage == .preview` but `parsedCourses.isEmpty` | Graceful fallback to `webViewLogin` without blank screen |
| `F7-T2-04` | Error banner visible during stage transition | `errorMsg != nil` when user changes stage | Error cleared automatically on transition |
| `F7-T2-05` | Accessibility Reduce Motion enabled | System setting `accessibilityReduceMotion == true` | Animations fallback to instant or zero-duration transitions |

### Feature 8: WebView Back Navigation Edge Cases
| Test ID | Name | Boundary Condition | Expected Behavior |
|---|---|---|---|
| `F8-T2-01` | Web history has 5 internal pages | User navigates multiple pages in CAS SSO | Webview back pops internal history before exiting to school list |
| `F8-T2-02` | Webview crashes (WebContent process terminated) | Webview process terminates in background | Flow recovers gracefully; user can navigate back to search |
| `F8-T2-03` | Back navigation during active redirect | Redirect chain in progress when back tapped | Load canceled, navigation back to search succeeds |
| `F8-T2-04` | Back navigation with uncaptured login credentials | User typed password in webview and taps back | Webview tears down session securely |
| `F8-T2-05` | URL direct entry school back navigation | School was entered via direct URL input | Back returns to search with URL retained in query field |

### Feature 9: Comprehensive E2E Test Suite Boundary Cases
| Test ID | Name | Boundary Condition | Expected Behavior |
|---|---|---|---|
| `F9-T2-01` | Simulator under memory pressure | Run test suite while system memory is constrained | Tests complete without jetsam kill |
| `F9-T2-02` | Dark and Light color scheme switching | Run assertions under both light and dark scheme | Assertion invariants hold identically in both |
| `F9-T2-03` | English vs Chinese localization | Run test suite with en_US and zh_CN locales | Matchers succeed across all localized label variants |
| `F9-T2-04` | Concurrent database access during draft save/delete | Multiple repository operations during exit choice | Thread-safe GRDB transactions, no database locks |
| `F9-T2-05` | Test suite idempotence | Execute entire test suite 3 times consecutively | 100% pass rate on all iterations |

---

## 5. Tier 3: Cross-Feature Combinations (Pairwise Matrix)

| Pair ID | Features Combined | Scenario Description | Expected Outcome |
|---|---|---|---|
| `PAIR-01` | **F1 (Dismiss in selectSchool) × F4 (State Store Cleanup)** | User types query `"Peking"`, scrolls down list, then swipes down to dismiss. | Sheet dismisses smoothly; re-opening sheet shows empty query and reset scroll. |
| `PAIR-02` | **F1 (Dismiss in selectSchool) × F6 (Keyboard Interaction)** | User focuses search field (keyboard pops up), then drags sheet down from top header. | Keyboard dismisses first or simultaneously as sheet smoothly slides down to dismiss. |
| `PAIR-03` | **F2 (Interception) × F8 (WebView Back Navigation)** | User in `webViewLogin` taps top-left back button to return to `selectSchool`, then from `selectSchool` swipes down. | Back navigation returns to `selectSchool`; once back, swipe-down is allowed and dismisses directly. |
| `PAIR-04` | **F2 (Interception) × F4 (State Store Cleanup on Keep/Delete)** | User in `preview` stage swipes down, dialog appears, user taps "Delete Draft". | Draft is purged from repository; sheet dismisses; `SchoolSelectStateStore` is reset cleanly. |
| `PAIR-05` | **F5 (AlphabetIndexBar) × F1 (Dismiss in selectSchool)** | User drags finger down `AlphabetIndexBar` to letter 'Z', lifts finger, then pulls down from sheet top. | Index jump navigates to 'Z'; subsequent downward drag on top header dismisses sheet without gesture lock. |
| `PAIR-06` | **F5 (AlphabetIndexBar) × F6 (Keyboard Dismiss on Scroll)** | User enters search field, clears it, scrolls list or touches index bar. | Index bar touches jump to section; scrolling list dismisses keyboard; no touch deadlocks. |
| `PAIR-07` | **F7 (Stage Transitions) × F2 (Dismiss Interception)** | User transitions from `webViewLogin` to `preview` to `configureConfirm`, attempting dismiss in each stage. | Every active stage (`webViewLogin`, `preview`, `configureConfirm`) intercepts dismissal with confirmation dialog. |
| `PAIR-08` | **F7 (Stage Transitions) × F8 (WebView Back Roundtrip)** | User goes `selectSchool` -> `webViewLogin` -> back to `selectSchool` -> `webViewLogin`. | State store query preserved; transitions animate with spring physics; no memory leak or view duplication. |
| `PAIR-09` | **F3 (Drag Indicator) × F1 (Sheet Dismiss Affordance)** | User visually observes drag indicator in `selectSchool` and drags directly from it. | Drag indicator moves with sheet; sheet dismisses smoothly. |
| `PAIR-10` | **F3 (Drag Indicator) × F2 (Sheet Interception Affordance)** | User observes drag indicator in `webViewLogin` and drags down from it. | Drag indicator provides elastic resistance, dismiss is intercepted, and confirmation dialog appears. |

---

## 6. Tier 4: Real-World Application Scenarios

### Scenario 1: Casual Browser Exit (No Progress)
*Journey:*  
1. User taps "Manage" -> "Import" -> "Connect to School" (`manage_import` -> `import_jw`).
2. Modal sheet slides up displaying `selectSchool` stage with search bar and drag indicator.
3. User types `"北京"` in search bar, views matching universities.
4. User decides not to import now, drags down on sheet from the top.
5. **Verification Point:** Modal dismisses directly and smoothly without confirmation dialog.
6. User taps `import_jw` again.
7. **Verification Point:** Search query is empty, full school list is displayed fresh.

### Scenario 2: Login In Progress Accidental Swipe Recovery
*Journey:*  
1. User enters JW import flow and selects "Tsinghua University".
2. Stage transitions smoothly to `webViewLogin`, loading the campus login page.
3. While typing credentials, user's finger slips downward from near top edge.
4. **Verification Point:** Modal does NOT dismiss. `ExitDraftConfirmationDialog` appears with "Continue", "Keep Draft", and "Delete Draft".
5. User taps "Continue" (or taps outside dialog).
6. **Verification Point:** Dialog disappears; login page remains loaded with credentials intact.

### Scenario 3: Wrong School Step-Back & Re-selection
*Journey:*  
1. User searches for `"理工"` in `selectSchool` and clicks a school row.
2. Webview opens. User notices wrong campus system.
3. User taps back button in top navigation bar.
4. **Verification Point:** Stage transitions smoothly back to `selectSchool`.
5. **Verification Point:** Search box still contains `"理工"`, avoiding tedious retyping.
6. User clicks the correct university row and proceeds to login.

### Scenario 4: Alphabet Navigation to Scroll Dismiss
*Journey:*  
1. User opens `selectSchool` with full catalog (145 schools).
2. User touches the letter 'S' in `AlphabetIndexBar` on the right margin.
3. School list scrolls immediately to section 'S'.
4. User swipes up on the list to browse through schools.
5. User pulls down on the header to exit.
6. **Verification Point:** Touch gestures on index bar, scroll view, and sheet dismissal execute without collision or freeze.

### Scenario 5: Full Capture & Draft Protection
*Journey:*  
1. User completes login, schedule HTML is captured, transitions to `preview` stage.
2. User views preview of courses.
3. Before confirming import into active schedule, user needs to check personal calendar and swipes down to exit.
4. **Verification Point:** Dismissal is intercepted. User chooses "Keep Draft".
5. Flow terminates. Draft snapshot is saved to `ImportDraftRepository`.
6. User returns later to Manage tab.
7. **Verification Point:** Saved draft is available in draft list with school and course metadata preserved.

---

## 7. Traceability Matrix

| Feature | Requirement Source | Tier 1 Tests | Tier 2 Tests | Tier 3 Pairs | Tier 4 Scenarios |
|---|---|---|---|---|---|
| **1. Swipe-down in no-progress** | `ORIGINAL_REQUEST §R1` | `F1-T1-01..05` | `F1-T2-01..05` | `PAIR-01, 02, 05, 09` | Scenario 1, 4 |
| **2. Interception & confirm dialog** | `ORIGINAL_REQUEST §R1` | `F2-T1-01..05` | `F2-T2-01..05` | `PAIR-03, 04, 07, 10` | Scenario 2, 5 |
| **3. Drag indicator affordance** | `ORIGINAL_REQUEST §R1, R2` | `F3-T1-01..05` | `F3-T2-01..05` | `PAIR-09, 10` | Scenario 1, 2 |
| **4. State store cleanup** | `PROJECT.md Feature 4` | `F4-T1-01..05` | `F4-T2-01..05` | `PAIR-01, 04` | Scenario 1, 3, 5 |
| **5. Alphabet index bar deconfliction** | `ORIGINAL_REQUEST §R2` | `F5-T1-01..05` | `F5-T2-01..05` | `PAIR-05, 06` | Scenario 4 |
| **6. Header & keyboard interaction** | `ORIGINAL_REQUEST §R2` | `F6-T1-01..05` | `F6-T2-01..05` | `PAIR-02, 06` | Scenario 1, 4 |
| **7. Stage transition animations** | `ORIGINAL_REQUEST §R2` | `F7-T1-01..05` | `F7-T2-01..05` | `PAIR-07, 08` | Scenario 2, 3 |
| **8. WebView back navigation** | `ORIGINAL_REQUEST §R2` | `F8-T1-01..05` | `F8-T2-01..05` | `PAIR-03, 08` | Scenario 3 |
| **9. Comprehensive test suite & QA** | `ORIGINAL_REQUEST §Verification` | `F9-T1-01..05` | `F9-T2-01..05` | All Pairs | Scenarios 1-5 |

---

## 8. Test Execution Commands & Verification Guide

### Unit & Integration Tests (SleepyTests)
Run all educational import modal tests:
```bash
xcodebuild test -project Sleepy.xcodeproj -scheme Sleepy \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SleepyTests/ExitDraftStateTests \
  -only-testing:SleepyTests/JwImportFlowTests \
  -only-testing:SleepyTests/EducationalImportModalTests \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO
```

### UI Tests (SleepyUITests)
Run UI automation tests:
```bash
xcodebuild test -project Sleepy.xcodeproj -scheme Sleepy \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SleepyUITests/SchoolSelectUITests \
  -only-testing:SleepyUITests/EducationalImportModalUITests \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO
```

### Quality Gates
- **Gate 1 (Compilation):** Zero build errors, zero Swift compiler warnings in test targets.
- **Gate 2 (Unit Pass Rate):** 100% pass across all unit and reducer test cases.
- **Gate 3 (State Safety):** Zero shared-singleton state leakage between test executions.
- **Gate 4 (Regression Prevention):** All existing 96 unit test suites and 22 UI test suites remain green.
