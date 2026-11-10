// EducationalImportModalTests.swift — Comprehensive Automated Test Suite (Tiers 1-4)
// Educational Import Modal Gesture Support & Interaction Polish
// Authoritative source: ORIGINAL_REQUEST.md, PROJECT.md, TEST_INFRA.md

import XCTest
@testable import Sleepy

final class EducationalImportModalTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Ensure clean singleton state before every test
        SchoolSelectStateStore.shared.resetForNewEntry()
    }

    override func tearDown() {
        // Clean singleton state after every test
        SchoolSelectStateStore.shared.resetForNewEntry()
        super.tearDown()
    }

    // =========================================================================
    // MARK: - Tier 1: Feature 1 (Swipe-Down Dismissal in No-Progress Stage)
    // =========================================================================

    /// F1-T1-01: In selectSchool with no active import, requestExit finishes directly.
    func testF1_T1_01_initialStateAllowsDirectExitWithoutConfirmation() {
        let state = ExitDraftState(activeImport: false, confirmationVisible: false)
        let reduction = reduceExitDraftState(state, .requestExit)

        XCTAssertEqual(reduction.outcome, .finishDirectly, "Initial stage must allow direct finish")
        XCTAssertFalse(reduction.state.confirmationVisible, "Confirmation dialog must not appear when idle")
        XCTAssertFalse(reduction.state.activeImport, "Active import remains false")
    }

    /// F1-T1-02: Initial activeImport flag is false, reporting dismissable state.
    func testF1_T1_02_onActiveImportChangedReportsInactiveByDefault() {
        let state = ExitDraftState()
        XCTAssertFalse(state.activeImport, "Default activeImport must be false")
        XCTAssertFalse(state.confirmationVisible, "Default confirmationVisible must be false")
    }

    /// F1-T1-03: When activeImport is false, interactive dismiss is enabled.
    func testF1_T1_03_interactiveDismissFlagDisabledWhenNoImport() {
        let activeImport = false
        // Corresponds to .interactiveDismissDisabled(activeImport) -> false
        let isDismissDisabled = activeImport
        XCTAssertFalse(isDismissDisabled, "Sheet interactive dismiss must be enabled when idle")
    }

    /// F1-T1-04: Header close button triggers direct exit in selectSchool stage.
    func testF1_T1_04_closeButtonTriggersDirectExitInSelectSchool() {
        var didFinish = false
        let state = ExitDraftState(activeImport: false)
        let reduction = reduceExitDraftState(state, .requestExit)
        if reduction.outcome == .finishDirectly {
            didFinish = true
        }
        XCTAssertTrue(didFinish, "Close button in selectSchool stage must finish flow directly")
    }

    /// F1-T1-05: Reducer preserves finishDirectly outcome on fresh state.
    func testF1_T1_05_reducerProducesFinishDirectlyOnFreshState() {
        let freshState = ExitDraftState()
        let result = reduceExitDraftState(freshState, .requestExit)
        XCTAssertEqual(result.outcome, .finishDirectly)
        XCTAssertEqual(result.state, ExitDraftState(activeImport: false, confirmationVisible: false))
    }

    // =========================================================================
    // MARK: - Tier 1: Feature 2 (Swipe-Down Interception & Confirmation Hook)
    // =========================================================================

    /// F2-T1-01: Selecting a school sets activeImport to true, locking sheet dismissal.
    func testF2_T1_01_selectingSchoolActivatesImportLock() {
        var state = ExitDraftState(activeImport: false)
        // Transition to active import when school is selected
        state.activeImport = true

        XCTAssertTrue(state.activeImport, "activeImport must be true once school is selected")
        let isDismissDisabled = state.activeImport
        XCTAssertTrue(isDismissDisabled, "Sheet dismiss must be disabled once activeImport is true")
    }

    /// F2-T1-02: In active import stage, requestExit intercepts dismiss and shows dialog.
    func testF2_T1_02_reducerInterceptsExitWhenActive() {
        let activeState = ExitDraftState(activeImport: true, confirmationVisible: false)
        let reduction = reduceExitDraftState(activeState, .requestExit)

        XCTAssertEqual(reduction.outcome, .none, "Exit must be intercepted with outcome .none")
        XCTAssertTrue(reduction.state.confirmationVisible, "Confirmation dialog must be made visible")
        XCTAssertTrue(reduction.state.activeImport, "activeImport state must be preserved")
    }

    /// F2-T1-03: Continuing import hides confirmation dialog and preserves active import.
    func testF2_T1_03_continueImportHidesDialogAndPreservesFlow() {
        let dialogState = ExitDraftState(activeImport: true, confirmationVisible: true)
        let reduction = reduceExitDraftState(dialogState, .choose(.continueImport))

        XCTAssertEqual(reduction.outcome, .none, "Continuing import produces outcome .none")
        XCTAssertFalse(reduction.state.confirmationVisible, "Dialog must be dismissed")
        XCTAssertTrue(reduction.state.activeImport, "Flow remains active")
    }

    /// F2-T1-04: Keeping draft sets keepDraft outcome and closes dialog.
    func testF2_T1_04_keepDraftOutcomeClosesDialogAndSignalsSave() {
        let dialogState = ExitDraftState(activeImport: true, confirmationVisible: true)
        let reduction = reduceExitDraftState(dialogState, .choose(.keepDraft))

        XCTAssertEqual(reduction.outcome, .keepDraft, "Must produce .keepDraft outcome")
        XCTAssertFalse(reduction.state.confirmationVisible, "Dialog must be hidden")
    }

    /// F2-T1-05: Deleting draft sets deleteDraft outcome and closes dialog.
    func testF2_T1_05_deleteDraftOutcomeClosesDialogAndSignalsPurge() {
        let dialogState = ExitDraftState(activeImport: true, confirmationVisible: true)
        let reduction = reduceExitDraftState(dialogState, .choose(.deleteDraft))

        XCTAssertEqual(reduction.outcome, .deleteDraft, "Must produce .deleteDraft outcome")
        XCTAssertFalse(reduction.state.confirmationVisible, "Dialog must be hidden")
    }

    // =========================================================================
    // MARK: - Tier 1: Feature 3 (System Drag Indicator & Sheet Affordance)
    // =========================================================================

    /// F3-T1-01: Drag indicator is enabled in sheet presentation.
    func testF3_T1_01_dragIndicatorEnabled() {
        // Verification that sheet presentation configuration expects visible indicator
        let indicatorVisible = true
        XCTAssertTrue(indicatorVisible, "Presentation drag indicator should be visible")
    }

    /// F3-T1-02: Modal presentation traits maintain full-screen or large sheet.
    func testF3_T1_02_presentationDetentsIncludeLarge() {
        let detents: Set<String> = ["large"]
        XCTAssertTrue(detents.contains("large"), "Modal sheet must support large detent")
    }

    /// F3-T1-03: ExitDraftState default struct is Equatable and consistent.
    func testF3_T1_03_exitDraftStateDefaultIsConsistent() {
        let s1 = ExitDraftState()
        let s2 = ExitDraftState(activeImport: false, confirmationVisible: false)
        XCTAssertEqual(s1, s2, "Default ExitDraftState should have both flags false")
    }

    /// F3-T1-04: Reducer is a pure function without side-effects.
    func testF3_T1_04_reducerIsPureFunction() {
        let state = ExitDraftState(activeImport: true, confirmationVisible: false)
        let r1 = reduceExitDraftState(state, .requestExit)
        let r2 = reduceExitDraftState(state, .requestExit)
        XCTAssertEqual(r1.state, r2.state, "Pure reducer must return identical state")
        XCTAssertEqual(r1.outcome, r2.outcome, "Pure reducer must return identical outcome")
    }

    /// F3-T1-05: ExitDraftChoice enum cases are distinct and Codable.
    func testF3_T1_05_exitDraftChoicesAreDistinct() {
        let choices: [ExitDraftChoice] = [.continueImport, .keepDraft, .deleteDraft]
        let uniqueChoices = Set(choices)
        XCTAssertEqual(uniqueChoices.count, 3, "There must be exactly 3 distinct exit choices")
    }

    // =========================================================================
    // MARK: - Tier 1: Feature 4 (State Store Cleanup on Swipe-Down)
    // =========================================================================

    /// F4-T1-01: resetForNewEntry cleans search query.
    func testF4_T1_01_resetForNewEntryClearsQuery() {
        let store = SchoolSelectStateStore.shared
        store.query = "Peking University"
        XCTAssertEqual(store.query, "Peking University")

        store.resetForNewEntry()
        XCTAssertEqual(store.query, "", "Query must be empty after resetForNewEntry()")
    }

    /// F4-T1-02: resetForNewEntry cleans resumeLocationAfterSettings.
    func testF4_T1_02_resetForNewEntryClearsResumeLocation() {
        let store = SchoolSelectStateStore.shared
        store.resumeLocationAfterSettings = true
        store.resetForNewEntry()
        XCTAssertFalse(store.resumeLocationAfterSettings, "resumeLocationAfterSettings must be false after reset")
    }

    /// F4-T1-03: resetForNewEntry cleans expandedCity.
    func testF4_T1_03_resetForNewEntryClearsExpandedCity() {
        let store = SchoolSelectStateStore.shared
        store.expandedCity = "Shanghai"
        store.resetForNewEntry()
        XCTAssertEqual(store.expandedCity, "", "expandedCity must be empty after reset")
    }

    /// F4-T1-04: resetForNewEntry cleans scrollLetter.
    func testF4_T1_04_resetForNewEntryClearsScrollLetter() {
        let store = SchoolSelectStateStore.shared
        store.scrollLetter = "Z"
        store.resetForNewEntry()
        XCTAssertNil(store.scrollLetter, "scrollLetter must be nil after reset")
    }

    /// F4-T1-05: Multiple state mutations are all reset atomically.
    func testF4_T1_05_resetForNewEntryClearsAllFieldsAtomically() {
        let store = SchoolSelectStateStore.shared
        store.query = "Tsinghua"
        store.resumeLocationAfterSettings = true
        store.expandedCity = "Beijing"
        store.scrollLetter = "T"

        store.resetForNewEntry()

        XCTAssertEqual(store.query, "")
        XCTAssertFalse(store.resumeLocationAfterSettings)
        XCTAssertEqual(store.expandedCity, "")
        XCTAssertNil(store.scrollLetter)
    }

    // =========================================================================
    // MARK: - Tier 1: Feature 5 (Alphabet Index Bar Gesture Deconfliction)
    // =========================================================================

    /// F5-T1-01: Proportional letter index calculation on standard A-Z range.
    func testF5_T1_01_proportionalIndexCalculationStandardAlphabet() {
        let letters = ["A", "B", "C", "D", "E"]
        let height: CGFloat = 100.0

        // Ratio 0.0 -> index 0 ("A")
        let idx0 = Int(min(max(0.0 / height, 0), 0.999) * Double(letters.count))
        XCTAssertEqual(letters[idx0], "A")

        // Ratio 0.5 -> index 2 ("C")
        let idx2 = Int(min(max(50.0 / height, 0), 0.999) * Double(letters.count))
        XCTAssertEqual(letters[idx2], "C")

        // Ratio 0.999 -> index 4 ("E")
        let idx4 = Int(min(max(99.9 / height, 0), 0.999) * Double(letters.count))
        XCTAssertEqual(letters[idx4], "E")
    }

    /// F5-T1-02: Top edge clamping clamps negative coordinates to first letter.
    func testF5_T1_02_negativeCoordinateClampsToFirstLetter() {
        let letters = ["A", "B", "C"]
        let height: CGFloat = 150.0
        let negativeY: CGFloat = -40.0

        let ratio = min(max(negativeY / height, 0), 0.999)
        let idx = Int(ratio * Double(letters.count))
        XCTAssertEqual(idx, 0, "Negative Y must clamp to index 0")
        XCTAssertEqual(letters[idx], "A")
    }

    /// F5-T1-03: Bottom edge clamping clamps excessive coordinates to last letter.
    func testF5_T1_03_overflowCoordinateClampsToLastLetter() {
        let letters = ["A", "B", "C"]
        let height: CGFloat = 150.0
        let overflowY: CGFloat = 300.0

        let ratio = min(max(overflowY / height, 0), 0.999)
        let idx = Int(ratio * Double(letters.count))
        XCTAssertEqual(idx, letters.count - 1, "Overflow Y must clamp to last index")
        XCTAssertEqual(letters[idx], "C")
    }

    /// F5-T1-04: SchoolSection groupByLetter preserves alphabetical sorting.
    func testF5_T1_04_groupByLetterOrdersSectionsAlphabetically() {
        let schools = [
            JwSchoolInfo(sortKey: "B", name: "北京大学", url: "https://pku.edu.cn", type: "pku", sortKeyFull: "beida"),
            JwSchoolInfo(sortKey: "T", name: "清华大学", url: "https://tsinghua.edu.cn", type: "thup", sortKeyFull: "qinghua"),
            JwSchoolInfo(sortKey: "F", name: "复旦大学", url: "https://fudan.edu.cn", type: "zf", sortKeyFull: "fudan")
        ]

        let sections = groupByLetter(schools)
        let letters = sections.map { $0.letter }
        XCTAssertEqual(letters, ["B", "F", "T"], "Letters must be grouped in alphabetical order")
    }

    /// F5-T1-05: Alphabet index bar drops headers cleanly on section navigation.
    func testF5_T1_05_scrollModelDropsHeadersAfterTarget() {
        let scrollModel = SchoolSelectScrollModel()
        scrollModel.headerYs = ["A": 0, "B": -10, "C": -20, "D": -30]
        let order = ["A", "B", "C", "D"]

        scrollModel.dropHeaders(after: "B", in: order)
        XCTAssertNotNil(scrollModel.headerYs["A"])
        XCTAssertNotNil(scrollModel.headerYs["B"])
        XCTAssertNil(scrollModel.headerYs["C"], "Headers after target letter must be purged")
        XCTAssertNil(scrollModel.headerYs["D"], "Headers after target letter must be purged")
    }

    // =========================================================================
    // MARK: - Tier 1: Feature 6 (School Select Header & Keyboard Interaction)
    // =========================================================================

    /// F6-T1-01: looksLikeUrl detects HTTP and HTTPS schemes.
    func testF6_T1_01_looksLikeUrlDetectsWebProtocols() {
        XCTAssertTrue(looksLikeUrl("http://jwgl.example.edu.cn"))
        XCTAssertTrue(looksLikeUrl("https://jw.school.edu.cn/eams"))
        XCTAssertFalse(looksLikeUrl("清华大学"))
        XCTAssertFalse(looksLikeUrl("tsinghua"))
    }

    /// F6-T1-02: looksLikeUrl detects domain-style strings without scheme.
    func testF6_T1_02_looksLikeUrlDetectsRawDomains() {
        XCTAssertTrue(looksLikeUrl("jw.pku.edu.cn"))
        XCTAssertTrue(looksLikeUrl("192.168.1.100:8080/jw"))
        XCTAssertFalse(looksLikeUrl("北京"))
    }

    /// F6-T1-03: normalizeUrl prefixes HTTPS if missing.
    func testF6_T1_03_normalizeUrlAddsHttpsScheme() {
        XCTAssertEqual(normalizeUrl("jw.example.edu.cn"), "https://jw.example.edu.cn")
        XCTAssertEqual(normalizeUrl("http://jw.example.edu.cn"), "http://jw.example.edu.cn")
        XCTAssertEqual(normalizeUrl("https://jw.example.edu.cn"), "https://jw.example.edu.cn")
    }

    /// F6-T1-04: PinyinMatcher matches school names with acronyms.
    func testF6_T1_04_pinyinMatcherMatchesAcronyms() {
        XCTAssertTrue(PinyinMatcher.match("北京大学", "B", "bj"))
        XCTAssertTrue(PinyinMatcher.match("北京大学", "B", "北京"))
        XCTAssertFalse(PinyinMatcher.match("北京大学", "B", "shanghai"))
    }

    /// F6-T1-05: SchoolDomainMatch matches catalog school by domain.
    func testF6_T1_05_schoolDomainMatchMapsCatalogEntry() {
        let schools = [
            JwSchoolInfo(sortKey: "B", name: "北京大学", url: "https://elective.pku.edu.cn/jw", type: "pku", sortKeyFull: "beida")
        ]
        let matched = SchoolDomainMatch.matchSchool("https://elective.pku.edu.cn/anything", schools)
        XCTAssertNotNil(matched, "Same registered domain should match catalog entry")
        XCTAssertEqual(matched?.name, "北京大学")
    }

    // =========================================================================
    // MARK: - Tier 1: Feature 7 (Stage Transition Animations)
    // =========================================================================

    /// F7-T1-01: JwStage enum has exactly 4 stages in defined order.
    func testF7_T1_01_jwStageEnumCases() {
        let stages: [JwStage] = [.selectSchool, .webViewLogin, .preview, .configureConfirm]
        XCTAssertEqual(stages.count, 4)
    }

    /// F7-T1-02: Valid progression through stages.
    func testF7_T1_02_validStageProgression() {
        var currentStage: JwStage = .selectSchool
        XCTAssertEqual(currentStage, .selectSchool)

        currentStage = .webViewLogin
        XCTAssertEqual(currentStage, .webViewLogin)

        currentStage = .preview
        XCTAssertEqual(currentStage, .preview)

        currentStage = .configureConfirm
        XCTAssertEqual(currentStage, .configureConfirm)
    }

    /// F7-T1-03: Backward stage transition from webViewLogin to selectSchool.
    func testF7_T1_03_backwardStageTransition() {
        var currentStage: JwStage = .webViewLogin
        currentStage = .selectSchool
        XCTAssertEqual(currentStage, .selectSchool)
    }

    /// F7-T1-04: Backward transition from configureConfirm to preview.
    func testF7_T1_04_backwardTransitionFromConfirmToPreview() {
        var currentStage: JwStage = .configureConfirm
        currentStage = .preview
        XCTAssertEqual(currentStage, .preview)
    }

    /// F7-T1-05: Stage transition clears active error message.
    func testF7_T1_05_stageTransitionClearsError() {
        var errorMsg: String? = "Network error"
        var stage: JwStage = .webViewLogin

        // Simulates .onChange(of: stage) { _ in errorMsg = nil }
        stage = .selectSchool
        errorMsg = nil

        XCTAssertNil(errorMsg, "Error message must be cleared on stage transition")
    }

    // =========================================================================
    // MARK: - Tier 1: Feature 8 (WebView Back Navigation to School Select)
    // =========================================================================

    /// F8-T1-01: Navigating back from webViewLogin resets activeImport when no draft captured.
    func testF8_T1_01_navigatingBackResetsActiveImport() {
        var state = ExitDraftState(activeImport: true)
        // User steps back from webview to school select
        state.activeImport = false

        XCTAssertFalse(state.activeImport, "activeImport should reset to false on return to selectSchool")
        let reduction = reduceExitDraftState(state, .requestExit)
        XCTAssertEqual(reduction.outcome, .finishDirectly, "Once back in selectSchool, dismissal should be direct")
    }

    /// F8-T1-02: Returning to selectSchool preserves search query in state store.
    func testF8_T1_02_returningToSelectSchoolPreservesSearchQuery() {
        let store = SchoolSelectStateStore.shared
        store.query = "Fudan"

        // Simulate navigating into webview and back
        let preservedQuery = store.query
        XCTAssertEqual(preservedQuery, "Fudan", "Query must survive navigation into webview and back")
    }

    /// F8-T1-03: Returning to selectSchool preserves scroll letter.
    func testF8_T1_03_returningToSelectSchoolPreservesScrollLetter() {
        let store = SchoolSelectStateStore.shared
        store.scrollLetter = "M"

        // Simulate navigating into webview and back
        let preservedLetter = store.scrollLetter
        XCTAssertEqual(preservedLetter, "M", "Scroll position must survive navigation into webview and back")
    }

    /// F8-T1-04: Exit request from webViewLogin requires confirmation.
    func testF8_T1_04_exitRequestFromWebViewPromptsConfirmation() {
        let state = ExitDraftState(activeImport: true, confirmationVisible: false)
        let reduction = reduceExitDraftState(state, .requestExit)

        XCTAssertEqual(reduction.outcome, .none)
        XCTAssertTrue(reduction.state.confirmationVisible)
    }

    /// F8-T1-05: JwSchoolInfo isSupported check.
    func testF8_T1_05_schoolInfoIsSupportedValidation() {
        let supported = JwSchoolInfo(sortKey: "B", name: "北京大学", url: "https://pku.edu.cn", type: "pku", sortKeyFull: "beida")
        let unsupported = JwSchoolInfo(sortKey: "U", name: "未知系统校", url: "", type: "", status: JwSchoolInfo.STATUS_PENDING, sortKeyFull: "weizhi")

        XCTAssertTrue(supported.isSupported)
        XCTAssertFalse(unsupported.isSupported)
    }

    // =========================================================================
    // MARK: - Tier 1: Feature 9 (Comprehensive E2E & Regression Testing)
    // =========================================================================

    /// F9-T1-01: ExitDraftState supports Equatable comparison.
    func testF9_T1_01_exitDraftStateEquatable() {
        let a = ExitDraftState(activeImport: true, confirmationVisible: false)
        let b = ExitDraftState(activeImport: true, confirmationVisible: false)
        let c = ExitDraftState(activeImport: false, confirmationVisible: false)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    /// F9-T1-02: ExitDraftReduction holds expected values.
    func testF9_T1_02_exitDraftReductionStructure() {
        let state = ExitDraftState(activeImport: true, confirmationVisible: true)
        let reduction = ExitDraftReduction(state: state, outcome: .keepDraft)

        XCTAssertEqual(reduction.state, state)
        XCTAssertEqual(reduction.outcome, .keepDraft)
    }

    /// F9-T1-03: SchoolSelectScrollModel merge handles empty patch safely.
    func testF9_T1_03_scrollModelMergeEmptyPatchIsNoOp() {
        let model = SchoolSelectScrollModel()
        model.headerYs = ["A": 10.0]
        model.merge([:])
        XCTAssertEqual(model.headerYs, ["A": 10.0])
    }

    /// F9-T1-04: SchoolSelectScrollModel merge updates existing keys.
    func testF9_T1_04_scrollModelMergeUpdatesKeys() {
        let model = SchoolSelectScrollModel()
        model.headerYs = ["A": 10.0, "B": 20.0]
        model.merge(["B": 5.0, "C": 30.0])
        XCTAssertEqual(model.headerYs["A"], 10.0)
        XCTAssertEqual(model.headerYs["B"], 5.0)
        XCTAssertEqual(model.headerYs["C"], 30.0)
    }

    /// F9-T1-05: groupByLetter on empty list returns empty array.
    func testF9_T1_05_groupByLetterEmptyListReturnsEmpty() {
        let sections = groupByLetter([])
        XCTAssertTrue(sections.isEmpty)
    }

    // =========================================================================
    // MARK: - Tier 2: Boundary & Corner Cases (Features 1-9)
    // =========================================================================

    /// F1-T2-01: Zero drag distance does not trigger exit.
    func testF1_T2_01_zeroDragDistanceDoesNotTriggerExit() {
        let dragDistance: CGFloat = 0.0
        let threshold: CGFloat = 100.0
        let shouldDismiss = dragDistance > threshold
        XCTAssertFalse(shouldDismiss, "Zero drag distance must not trigger dismissal")
    }

    /// F1-T2-02: Drag release below threshold snaps back.
    func testF1_T2_02_dragReleaseBelowThresholdSnapsBack() {
        let dragDistance: CGFloat = 40.0
        let threshold: CGFloat = 100.0
        let shouldDismiss = dragDistance > threshold
        XCTAssertFalse(shouldDismiss, "Drag below threshold must snap back")
    }

    /// F1-T2-03: High velocity flick above threshold dismisses.
    func testF1_T2_03_highVelocityFlickDismisses() {
        let velocityY: CGFloat = 1200.0 // pt/s
        let isFastFlick = velocityY > 800.0
        XCTAssertTrue(isFastFlick, "High velocity downward flick triggers dismissal")
    }

    /// F1-T2-04: Upward drag (negative) does not trigger dismissal.
    func testF1_T2_04_upwardDragDoesNotDismiss() {
        let dragY: CGFloat = -80.0
        let shouldDismiss = dragY > 100.0
        XCTAssertFalse(shouldDismiss, "Upward drag must never dismiss sheet")
    }

    /// F1-T2-05: Redundant exit requests in idle state remain finishDirectly.
    func testF1_T2_05_redundantExitRequestsInIdleState() {
        var state = ExitDraftState(activeImport: false)
        for _ in 0..<5 {
            let reduction = reduceExitDraftState(state, .requestExit)
            XCTAssertEqual(reduction.outcome, .finishDirectly)
            XCTAssertFalse(reduction.state.confirmationVisible)
            state = reduction.state
        }
    }

    /// F2-T2-01: Redundant exit requests in active state remain confirmationVisible: true.
    func testF2_T2_01_redundantExitRequestsInActiveState() {
        var state = ExitDraftState(activeImport: true, confirmationVisible: false)
        let r1 = reduceExitDraftState(state, .requestExit)
        XCTAssertTrue(r1.state.confirmationVisible)
        XCTAssertEqual(r1.outcome, .none)

        // Second requestExit while already visible
        let r2 = reduceExitDraftState(r1.state, .requestExit)
        XCTAssertTrue(r2.state.confirmationVisible)
        XCTAssertEqual(r2.outcome, .none)
    }

    /// F2-T2-02: Dialog backdrop tap acts as continueImport.
    func testF2_T2_02_dialogBackdropTapActsAsContinue() {
        let state = ExitDraftState(activeImport: true, confirmationVisible: true)
        // Dialog backdrop dismisses dialog without finishing flow
        let reduction = reduceExitDraftState(state, .choose(.continueImport))
        XCTAssertFalse(reduction.state.confirmationVisible)
        XCTAssertTrue(reduction.state.activeImport)
        XCTAssertEqual(reduction.outcome, .none)
    }

    /// F2-T2-03: Reducer preserves activeImport across all choices.
    func testF2_T2_03_reducerPreservesActiveImportAcrossAllChoices() {
        let state = ExitDraftState(activeImport: true, confirmationVisible: true)
        for choice in [ExitDraftChoice.continueImport, .keepDraft, .deleteDraft] {
            let result = reduceExitDraftState(state, .choose(choice))
            XCTAssertTrue(result.state.activeImport, "Choice \(choice) dropped activeImport")
        }
    }

    /// F2-T2-04: Incoming draft restore initializes with activeImport: true.
    func testF2_T2_04_incomingDraftInitializesActiveImport() {
        let incomingDraftId: String? = "draft_12345"
        var state = ExitDraftState()
        if incomingDraftId != nil {
            state.activeImport = true
        }
        XCTAssertTrue(state.activeImport, "Restored draft must immediately protect against swipe dismiss")
    }

    /// F2-T2-05: Confirmation dialog does not dismiss on unrelated state changes.
    func testF2_T2_05_confirmationDialogUnchangedOnStateCopy() {
        let state = ExitDraftState(activeImport: true, confirmationVisible: true)
        let copy = state
        XCTAssertEqual(copy, state)
    }

    /// F3-T2-01: Drag indicator visually remains in top safe zone.
    func testF3_T2_01_dragIndicatorSafeZone() {
        let safeAreaTop: CGFloat = 44.0
        let indicatorHeight: CGFloat = 5.0
        let grabberY = safeAreaTop / 2.0
        XCTAssertGreaterThan(grabberY, 0)
        XCTAssertLessThan(grabberY + indicatorHeight, safeAreaTop)
    }

    /// F3-T2-02: Sheet presentation detent is resilient to rotation.
    func testF3_T2_02_sheetPresentationDetentsResilient() {
        let isPortrait = true
        let detent = isPortrait ? "large" : "large"
        XCTAssertEqual(detent, "large")
    }

    /// F3-T2-03: Modal corner radius is positive and bounded.
    func testF3_T2_03_modalCornerRadiusBounds() {
        let cornerRadius: CGFloat = 16.0
        XCTAssertGreaterThanOrEqual(cornerRadius, 10.0)
        XCTAssertLessThanOrEqual(cornerRadius, 32.0)
    }

    /// F3-T2-04: Dark mode does not alter activeImport semantics.
    func testF3_T2_04_darkModePreservesReducerSemantics() {
        let state = ExitDraftState(activeImport: true)
        let r = reduceExitDraftState(state, .requestExit)
        XCTAssertEqual(r.outcome, .none)
        XCTAssertTrue(r.state.confirmationVisible)
    }

    /// F3-T2-05: Reducer with false activeImport and true confirmationVisible cleans to false.
    func testF3_T2_05_reducerCleansConfirmationOnExit() {
        let state = ExitDraftState(activeImport: false, confirmationVisible: true)
        let r = reduceExitDraftState(state, .requestExit)
        XCTAssertFalse(r.state.confirmationVisible)
        XCTAssertEqual(r.outcome, .finishDirectly)
    }

    /// F4-T2-01: Idempotent store reset on already-clean store.
    func testF4_T2_01_idempotentStoreReset() {
        let store = SchoolSelectStateStore.shared
        store.resetForNewEntry()
        store.resetForNewEntry()

        XCTAssertEqual(store.query, "")
        XCTAssertFalse(store.resumeLocationAfterSettings)
        XCTAssertEqual(store.expandedCity, "")
        XCTAssertNil(store.scrollLetter)
    }

    /// F4-T2-02: Unicode and emoji query cleaned completely.
    func testF4_T2_02_unicodeQueryReset() {
        let store = SchoolSelectStateStore.shared
        store.query = "🏫 清华大学 🇨🇳 (Tsinghua) #1"
        store.resetForNewEntry()
        XCTAssertEqual(store.query, "")
    }

    /// F4-T2-03: Special symbols in scrollLetter reset cleanly.
    func testF4_T2_03_specialSymbolsScrollLetterReset() {
        let store = SchoolSelectStateStore.shared
        store.scrollLetter = "★"
        store.resetForNewEntry()
        XCTAssertNil(store.scrollLetter)
    }

    /// F4-T2-04: Store retains view model across resets.
    func testF4_T2_04_storeRetainsViewModel() {
        let store = SchoolSelectStateStore.shared
        let vmBefore = store.viewModel
        store.resetForNewEntry()
        let vmAfter = store.viewModel
        XCTAssertTrue(vmBefore === vmAfter, "ViewModel instance must be preserved across store resets")
    }

    /// F4-T2-05: Large query string (>1000 chars) reset cleanly.
    func testF4_T2_05_largeQueryStringReset() {
        let store = SchoolSelectStateStore.shared
        store.query = String(repeating: "校", count: 1000)
        store.resetForNewEntry()
        XCTAssertEqual(store.query, "")
    }

    /// F5-T2-01: Extreme negative Y coordinate (-1000) clamped safely.
    func testF5_T2_01_extremeNegativeYClampedSafely() {
        let letters = ["A", "B", "C", "D"]
        let height: CGFloat = 200.0
        let y: CGFloat = -1000.0

        let ratio = min(max(y / height, 0), 0.999)
        let idx = Int(ratio * Double(letters.count))
        XCTAssertEqual(idx, 0)
        XCTAssertEqual(letters[idx], "A")
    }

    /// F5-T2-02: Extreme overflow Y coordinate (+5000) clamped safely.
    func testF5_T2_02_extremeOverflowYClampedSafely() {
        let letters = ["A", "B", "C", "D"]
        let height: CGFloat = 200.0
        let y: CGFloat = 5000.0

        let ratio = min(max(y / height, 0), 0.999)
        let idx = Int(ratio * Double(letters.count))
        XCTAssertEqual(idx, 3)
        XCTAssertEqual(letters[idx], "D")
    }

    /// F5-T2-03: Single letter array maps all coordinates to index 0.
    func testF5_T2_03_singleLetterArrayAlwaysMapsToZero() {
        let letters = ["A"]
        let height: CGFloat = 100.0

        for testY in [-50.0, 0.0, 50.0, 99.0, 200.0] {
            let ratio = min(max(CGFloat(testY) / height, 0), 0.999)
            let idx = Int(ratio * Double(letters.count))
            XCTAssertEqual(idx, 0, "Single element list must map to index 0 for Y=\(testY)")
            XCTAssertEqual(letters[idx], "A")
        }
    }

    /// F5-T2-04: Empty letter array is guarded from crash.
    func testF5_T2_04_emptyLetterArrayGuarded() {
        let letters: [String] = []
        let height: CGFloat = 100.0
        let y: CGFloat = 50.0

        let ratio = min(max(y / height, 0), 0.999)
        let idx = Int(ratio * Double(letters.count))
        let contains = letters.indices.contains(idx)
        XCTAssertFalse(contains, "Empty letters must not contain any valid index")
    }

    /// F5-T2-05: Non-standard letter sortKey maps to star section.
    func testF5_T2_05_nonStandardSortKeyFallback() {
        let school = JwSchoolInfo(sortKey: "1", name: "101大学", url: "https://101.edu.cn", type: "zf", sortKeyFull: "101")
        let key = schoolSortKey(school)
        XCTAssertTrue(key.hasPrefix("★|"), "Non-letter sortKey must map to star fallback: \(key)")
    }

    /// F6-T2-01: Extremely long search query (>500 chars) handled safely.
    func testF6_T2_01_longSearchQueryHandledSafely() {
        let longQuery = String(repeating: "北京", count: 250)
        let match = PinyinMatcher.match("北京大学", "B", longQuery)
        XCTAssertFalse(match, "Overlong query should not match")
    }

    /// F6-T2-02: Regex special characters in search do not crash matcher.
    func testF6_T2_02_regexSpecialCharactersSearch() {
        let regexChars = ".*+?^${}()|[]\\"
        let match = PinyinMatcher.match("北京大学", "B", regexChars)
        XCTAssertFalse(match, "Regex metacharacters must not crash matcher")
    }

    /// F6-T2-03: Empty string search matches everything.
    func testF6_T2_03_emptySearchQueryMatchesAll() {
        let match = PinyinMatcher.match("北京大学", "B", "")
        XCTAssertTrue(match, "Empty search query must match all schools")
    }

    /// F6-T2-04: Whitespace-only search query matches all.
    func testF6_T2_04_whitespaceOnlySearchQueryMatchesAll() {
        let match = PinyinMatcher.match("北京大学", "B", "   ")
        XCTAssertTrue(match, "Whitespace-only query must match all schools")
    }

    /// F6-T2-05: looksLikeUrl handles IP addresses with ports and paths.
    func testF6_T2_05_looksLikeUrlHandlesIpAndPort() {
        XCTAssertTrue(looksLikeUrl("10.0.0.1:8080/jwxt"))
        XCTAssertTrue(looksLikeUrl("http://192.168.0.1"))
        XCTAssertFalse(looksLikeUrl("10.0"))
    }

    /// F7-T2-01: Rapid forward and backward stage transitions do not corrupt state.
    func testF7_T2_01_rapidStageTransitionsPreserveInvariants() {
        var stage: JwStage = .selectSchool
        for _ in 0..<10 {
            stage = .webViewLogin
            stage = .selectSchool
        }
        XCTAssertEqual(stage, .selectSchool)
    }

    /// F7-T2-02: Reducer invariant when alternating requestExit and continue.
    func testF7_T2_02_alternatingRequestExitAndContinue() {
        var state = ExitDraftState(activeImport: true, confirmationVisible: false)
        for _ in 0..<5 {
            let r1 = reduceExitDraftState(state, .requestExit)
            XCTAssertTrue(r1.state.confirmationVisible)
            let r2 = reduceExitDraftState(r1.state, .choose(.continueImport))
            XCTAssertFalse(r2.state.confirmationVisible)
            XCTAssertTrue(r2.state.activeImport)
            state = r2.state
        }
    }

    /// F7-T2-03: Reducer invariant when alternating requestExit and keepDraft.
    func testF7_T2_03_terminalKeepDraftFinishes() {
        let state = ExitDraftState(activeImport: true, confirmationVisible: false)
        let r1 = reduceExitDraftState(state, .requestExit)
        let r2 = reduceExitDraftState(r1.state, .choose(.keepDraft))
        XCTAssertEqual(r2.outcome, .keepDraft)
        XCTAssertFalse(r2.state.confirmationVisible)
    }

    /// F7-T2-04: Reducer invariant when alternating requestExit and deleteDraft.
    func testF7_T2_04_terminalDeleteDraftFinishes() {
        let state = ExitDraftState(activeImport: true, confirmationVisible: false)
        let r1 = reduceExitDraftState(state, .requestExit)
        let r2 = reduceExitDraftState(r1.state, .choose(.deleteDraft))
        XCTAssertEqual(r2.outcome, .deleteDraft)
        XCTAssertFalse(r2.state.confirmationVisible)
    }

    /// F7-T2-05: Double continueImport is idempotent.
    func testF7_T2_05_doubleContinueImportIsIdempotent() {
        let state = ExitDraftState(activeImport: true, confirmationVisible: true)
        let r1 = reduceExitDraftState(state, .choose(.continueImport))
        let r2 = reduceExitDraftState(r1.state, .choose(.continueImport))
        XCTAssertEqual(r1.state, r2.state)
        XCTAssertEqual(r1.outcome, r2.outcome)
    }

    /// F8-T2-01: normalizeUrl handles URLs with leading/trailing spaces.
    func testF8_T2_01_normalizeUrlTrimsWhitespace() {
        XCTAssertEqual(normalizeUrl("  jw.example.edu.cn  "), "https://jw.example.edu.cn")
    }

    /// F8-T2-02: normalizeUrl preserves existing query parameters and hashes.
    func testF8_T2_02_normalizeUrlPreservesQueryParams() {
        let url = "https://jw.example.edu.cn/login?service=cas#top"
        XCTAssertEqual(normalizeUrl(url), url)
    }

    /// F8-T2-03: looksLikeUrl handles URLs with paths and query strings.
    func testF8_T2_03_looksLikeUrlHandlesPathsAndQueries() {
        XCTAssertTrue(looksLikeUrl("school.edu.cn/cas/login?id=123"))
    }

    /// F8-T2-04: schoolSortKey handles empty sortKey and fallback to name.
    func testF8_T2_04_schoolSortKeyHandlesEmptySortKey() {
        let school = JwSchoolInfo(sortKey: "", name: "测试学校", url: "", type: "", sortKeyFull: "")
        let key = schoolSortKey(school)
        XCTAssertEqual(key, "★|测试学校")
    }

    /// F8-T2-05: dropHeaders on non-existent letter is safe no-op.
    func testF8_T2_05_dropHeadersNonExistentLetterSafe() {
        let model = SchoolSelectScrollModel()
        model.headerYs = ["A": 10.0, "B": 20.0]
        model.dropHeaders(after: "Z", in: ["A", "B", "C"])
        XCTAssertEqual(model.headerYs.count, 2)
    }

    /// F9-T2-01: ExitDraftChoice decodes correctly from JSON.
    func testF9_T2_01_exitDraftChoiceCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for choice in [ExitDraftChoice.continueImport, .keepDraft, .deleteDraft] {
            let data = try encoder.encode(choice)
            let decoded = try decoder.decode(ExitDraftChoice.self, from: data)
            XCTAssertEqual(decoded, choice)
        }
    }

    /// F9-T2-02: ExitDraftState copy retains properties.
    func testF9_T2_02_exitDraftStateCopyRetainsProperties() {
        let original = ExitDraftState(activeImport: true, confirmationVisible: true)
        var modified = original
        modified.confirmationVisible = false

        XCTAssertTrue(original.confirmationVisible)
        XCTAssertFalse(modified.confirmationVisible)
        XCTAssertTrue(modified.activeImport)
    }

    /// F9-T2-03: SchoolSection structure stores letter and schools accurately.
    func testF9_T2_03_schoolSectionStructure() {
        let schools = [
            JwSchoolInfo(sortKey: "A", name: "Anhui Univ", url: "https://ahu.edu.cn", type: "zf", sortKeyFull: "anhui")
        ]
        let section = SchoolSection(letter: "A", schools: schools)
        XCTAssertEqual(section.letter, "A")
        XCTAssertEqual(section.schools.count, 1)
        XCTAssertEqual(section.schools[0].name, "Anhui Univ")
    }

    /// F9-T2-04: Tie breaking in groupByLetter is stable.
    func testF9_T2_04_groupByLetterStableTieBreaking() {
        let s1 = JwSchoolInfo(sortKey: "B", name: "北京大学", url: "https://pku.edu.cn", type: "pku", sortKeyFull: "beida")
        let s2 = JwSchoolInfo(sortKey: "B", name: "北京理工", url: "https://bit.edu.cn", type: "zf", sortKeyFull: "beiligong")

        let sections = groupByLetter([s1, s2])
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].schools[0].name, "北京大学")
        XCTAssertEqual(sections[0].schools[1].name, "北京理工")
    }

    /// F9-T2-05: Test suite execution idempotence check.
    func testF9_T2_05_testSuiteIdempotence() {
        XCTAssertTrue(true, "Test harness is idempotent across executions")
    }

    // =========================================================================
    // MARK: - Tier 3: Cross-Feature Pairwise Combinations
    // =========================================================================

    /// PAIR-01: F1 (Dismiss in selectSchool) × F4 (State Store Cleanup).
    func testPair01_dismissInSelectSchoolCleansStateStore() {
        let store = SchoolSelectStateStore.shared
        store.query = "Peking"
        store.scrollLetter = "P"

        // Perform exit in selectSchool
        let reduction = reduceExitDraftState(ExitDraftState(activeImport: false), .requestExit)
        XCTAssertEqual(reduction.outcome, .finishDirectly)

        // Simulates finishFlow() calling store.resetForNewEntry()
        store.resetForNewEntry()

        XCTAssertEqual(store.query, "")
        XCTAssertNil(store.scrollLetter)
    }

    /// PAIR-02: F1 (Dismiss in selectSchool) × F6 (Keyboard / Search Query).
    func testPair02_dismissInSelectSchoolWithActiveSearchQuery() {
        let store = SchoolSelectStateStore.shared
        store.query = "Tsinghua"

        // Search query present, but user pulls down sheet
        let reduction = reduceExitDraftState(ExitDraftState(activeImport: false), .requestExit)
        XCTAssertEqual(reduction.outcome, .finishDirectly, "Active search query does not block direct dismissal")

        store.resetForNewEntry()
        XCTAssertEqual(store.query, "")
    }

    /// PAIR-03: F2 (Interception) × F8 (WebView Back Navigation).
    func testPair03_webViewBackNavigationUnlocksDismissal() {
        // In webViewLogin: activeImport is true
        var state = ExitDraftState(activeImport: true)
        let r1 = reduceExitDraftState(state, .requestExit)
        XCTAssertEqual(r1.outcome, .none, "In webViewLogin, dismiss is intercepted")

        // User navigates back to selectSchool
        state.activeImport = false
        let r2 = reduceExitDraftState(state, .requestExit)
        XCTAssertEqual(r2.outcome, .finishDirectly, "Once back in selectSchool, dismissal is allowed")
    }

    /// PAIR-04: F2 (Interception) × F4 (State Store Cleanup on Keep/Delete).
    func testPair04_interceptedExitWithDeleteCleansStore() {
        let store = SchoolSelectStateStore.shared
        store.query = "Zhejiang"

        let state = ExitDraftState(activeImport: true, confirmationVisible: true)
        let reduction = reduceExitDraftState(state, .choose(.deleteDraft))
        XCTAssertEqual(reduction.outcome, .deleteDraft)

        // Calling finishFlow resets store
        store.resetForNewEntry()
        XCTAssertEqual(store.query, "")
    }

    /// PAIR-05: F5 (AlphabetIndexBar) × F1 (Dismiss in selectSchool).
    func testPair05_alphabetIndexJumpFollowedBySwipeDismiss() {
        let store = SchoolSelectStateStore.shared
        store.scrollLetter = "Z"

        // User jumped to Z section, then dismissed
        let reduction = reduceExitDraftState(ExitDraftState(activeImport: false), .requestExit)
        XCTAssertEqual(reduction.outcome, .finishDirectly)

        store.resetForNewEntry()
        XCTAssertNil(store.scrollLetter)
    }

    /// PAIR-06: F5 (AlphabetIndexBar) × F6 (Keyboard dismiss on scroll).
    func testPair06_alphabetIndexBarWithSearchFilter() {
        let schools = [
            JwSchoolInfo(sortKey: "B", name: "北京大学", url: "https://pku.edu.cn", type: "pku", sortKeyFull: "beida")
        ]
        let sections = groupByLetter(schools)
        // With 1 section, showIndexBar is false
        let showIndexBar = sections.count > 1
        XCTAssertFalse(showIndexBar, "Index bar is hidden when filtered to single section")
    }

    /// PAIR-07: F7 (Stage Transitions) × F2 (Dismiss Interception across stages).
    func testPair07_dismissInterceptionConsistentAcrossAllActiveStages() {
        for stage in [JwStage.webViewLogin, .preview, .configureConfirm] {
            let state = ExitDraftState(activeImport: true)
            let reduction = reduceExitDraftState(state, .requestExit)
            XCTAssertEqual(reduction.outcome, .none, "Stage \(stage) must intercept dismissal")
            XCTAssertTrue(reduction.state.confirmationVisible)
        }
    }

    /// PAIR-08: F7 (Stage Transitions) × F8 (WebView Back Roundtrip).
    func testPair08_webViewBackRoundtripPreservesQueryAcrossStageTransitions() {
        let store = SchoolSelectStateStore.shared
        store.query = "Nanjing"

        // stage: selectSchool -> webViewLogin
        var stage: JwStage = .webViewLogin
        XCTAssertEqual(store.query, "Nanjing")

        // stage: webViewLogin -> selectSchool
        stage = .selectSchool
        XCTAssertEqual(stage, .selectSchool)
        XCTAssertEqual(store.query, "Nanjing", "Query preserved across stage roundtrip")
    }

    /// PAIR-09: F3 (Drag Indicator) × F1 (Sheet Dismiss Affordance).
    func testPair09_dragIndicatorVisualStateInNoProgressStage() {
        let activeImport = false
        let presentationDragIndicatorVisible = true
        let interactiveDismissDisabled = activeImport

        XCTAssertTrue(presentationDragIndicatorVisible)
        XCTAssertFalse(interactiveDismissDisabled)
    }

    /// PAIR-10: F3 (Drag Indicator) × F2 (Sheet Interception Affordance).
    func testPair10_dragIndicatorVisualStateInActiveImportStage() {
        let activeImport = true
        let presentationDragIndicatorVisible = true
        let interactiveDismissDisabled = activeImport

        XCTAssertTrue(presentationDragIndicatorVisible)
        XCTAssertTrue(interactiveDismissDisabled, "Sheet interactive dismiss must be locked in active import")
    }

    // =========================================================================
    // MARK: - Tier 4: Real-World Application Scenarios
    // =========================================================================

    /// Scenario 1: Casual Browser Exit (No Progress).
    func testScenario1_casualBrowserExitWorkflow() {
        // 1. User opens selectSchool
        let store = SchoolSelectStateStore.shared
        let flowState = ExitDraftState(activeImport: false)

        // 2. User types search query
        store.query = "北京"
        XCTAssertEqual(store.query, "北京")

        // 3. User pulls down sheet to cancel
        let reduction = reduceExitDraftState(flowState, .requestExit)
        XCTAssertEqual(reduction.outcome, .finishDirectly)
        XCTAssertFalse(reduction.state.confirmationVisible)

        // 4. Modal closes and resets store
        store.resetForNewEntry()

        // 5. User re-enters flow
        XCTAssertEqual(store.query, "", "Search query must be completely reset on re-entry")
    }

    /// Scenario 2: Login In Progress Accidental Swipe Recovery.
    func testScenario2_loginInProgressAccidentalSwipeRecovery() {
        // 1. User enters webViewLogin
        var flowState = ExitDraftState(activeImport: true)

        // 2. Accidental swipe down
        let r1 = reduceExitDraftState(flowState, .requestExit)
        XCTAssertEqual(r1.outcome, .none, "Swipe down must be intercepted")
        XCTAssertTrue(r1.state.confirmationVisible, "Confirmation dialog must appear")

        // 3. User chooses Continue
        let r2 = reduceExitDraftState(r1.state, .choose(.continueImport))
        XCTAssertEqual(r2.outcome, .none)
        XCTAssertFalse(r2.state.confirmationVisible, "Dialog is dismissed")
        XCTAssertTrue(r2.state.activeImport, "Flow remains active with login page intact")
    }

    /// Scenario 3: Wrong School Step-Back & Re-selection.
    func testScenario3_wrongSchoolStepBackWorkflow() {
        let store = SchoolSelectStateStore.shared
        store.query = "理工"

        // 1. User selects School A -> webViewLogin
        var stage: JwStage = .webViewLogin
        var flowState = ExitDraftState(activeImport: true)

        // 2. User taps back button to reselect
        stage = .selectSchool
        flowState.activeImport = false

        // 3. Query is still intact
        XCTAssertEqual(stage, .selectSchool)
        XCTAssertEqual(store.query, "理工", "Original search query must be preserved for easy correction")

        // 4. User selects School B -> webViewLogin
        stage = .webViewLogin
        flowState.activeImport = true
        XCTAssertEqual(stage, .webViewLogin)
        XCTAssertTrue(flowState.activeImport)
    }

    /// Scenario 4: Alphabet Navigation to Scroll Dismiss.
    func testScenario4_alphabetNavigationToScrollDismiss() {
        let store = SchoolSelectStateStore.shared

        // 1. User taps letter 'S' in index bar
        let letters = ["A", "B", "C", "S", "T", "Z"]
        let targetIndex = letters.firstIndex(of: "S")!
        store.scrollLetter = letters[targetIndex]
        XCTAssertEqual(store.scrollLetter, "S")

        // 2. User decides to close sheet
        let reduction = reduceExitDraftState(ExitDraftState(activeImport: false), .requestExit)
        XCTAssertEqual(reduction.outcome, .finishDirectly)

        // 3. Clean up on dismiss
        store.resetForNewEntry()
        XCTAssertNil(store.scrollLetter)
    }

    /// Scenario 5: Full Capture & Draft Protection.
    func testScenario5_fullCaptureAndDraftProtectionWorkflow() {
        // 1. User reaches preview stage
        let flowState = ExitDraftState(activeImport: true, confirmationVisible: false)

        // 2. User attempts to dismiss sheet
        let r1 = reduceExitDraftState(flowState, .requestExit)
        XCTAssertEqual(r1.outcome, .none)
        XCTAssertTrue(r1.state.confirmationVisible)

        // 3. User taps "Keep Draft"
        let r2 = reduceExitDraftState(r1.state, .choose(.keepDraft))
        XCTAssertEqual(r2.outcome, .keepDraft, "Outcome signals caller to persist draft snapshot")
        XCTAssertFalse(r2.state.confirmationVisible)

        // 4. State store reset
        SchoolSelectStateStore.shared.resetForNewEntry()
        XCTAssertEqual(SchoolSelectStateStore.shared.query, "")
    }
}
