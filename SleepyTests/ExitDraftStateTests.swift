// ExitDraftStateTests.swift — ← ui/screen/imports/JwImportExitStateTest.kt
// 教务导入退出确认 reducer 的 4 个契约用例逐一对应移植:
//   1. 无活动导入 → RequestExit 直接完成 (FinishDirectly, 不弹确认)
//   2. 有活动导入 → RequestExit 打开确认 (None, confirmationVisible=true)
//   3. 继续 → 关确认不退出 (None, 导入态保留)
//   4. 留草稿 / 删除草稿 = 不同终局 (KeepDraft vs DeleteDraft, 均关确认)
// reducer 纯逻辑: 不存不删, 副作用归调用方 — 用例只锁 state/outcome 转移.

import XCTest
@testable import Sleepy

final class ExitDraftStateTests: XCTestCase {

    // `request exit finishes directly when no import is active`
    func testRequestExitFinishesDirectlyWhenNoImportActive() {
        let result = reduceExitDraftState(ExitDraftState(), .requestExit)

        XCTAssertEqual(result.outcome, .finishDirectly)
        XCTAssertFalse(result.state.confirmationVisible)
    }

    // `request exit opens confirmation while import is active`
    func testRequestExitOpensConfirmationWhileImportActive() {
        let result = reduceExitDraftState(
            ExitDraftState(activeImport: true),
            .requestExit)

        XCTAssertEqual(result.outcome, .none)
        XCTAssertTrue(result.state.confirmationVisible)
    }

    // `continue closes confirmation without completing exit`
    func testContinueClosesConfirmationWithoutCompletingExit() {
        let result = reduceExitDraftState(
            ExitDraftState(activeImport: true, confirmationVisible: true),
            .choose(.continueImport))

        XCTAssertEqual(result.outcome, .none)
        XCTAssertFalse(result.state.confirmationVisible)
        XCTAssertTrue(result.state.activeImport)
    }

    // `keep draft and delete draft are distinct terminal choices`
    func testKeepDraftAndDeleteDraftAreDistinctTerminalChoices() {
        let keep = reduceExitDraftState(
            ExitDraftState(activeImport: true, confirmationVisible: true),
            .choose(.keepDraft))
        let delete = reduceExitDraftState(
            ExitDraftState(activeImport: true, confirmationVisible: true),
            .choose(.deleteDraft))

        XCTAssertEqual(keep.outcome, .keepDraft)
        XCTAssertEqual(delete.outcome, .deleteDraft)
        XCTAssertFalse(keep.state.confirmationVisible)
        XCTAssertFalse(delete.state.confirmationVisible)
    }

    // 附加: reducer 不产生副作用 — activeImport 在所有终局里原样透传
    // (Android data class 语义: copy 只动 confirmationVisible).
    func testReducerPreservesActiveImportAcrossAllChoices() {
        for choice in [ExitDraftChoice.continueImport, .keepDraft, .deleteDraft] {
            let result = reduceExitDraftState(
                ExitDraftState(activeImport: true, confirmationVisible: true),
                .choose(choice))
            XCTAssertTrue(result.state.activeImport, "choice \(choice) dropped activeImport")
        }
    }
}
