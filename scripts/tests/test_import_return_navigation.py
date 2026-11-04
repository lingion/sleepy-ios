"""教务返回契约：纯 Swift 状态测试 + 真实入口接线检查，不启动 UI。"""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


def source(path):
    return (ROOT / "Sleepy" / path).read_text()


def declaration(text, marker):
    start = text.index(marker)
    opening = text.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


class ImportReturnNavigation(unittest.TestCase):
    def test_method_entry_is_preserved_until_jw_dismissal(self):
        text = source("ui/screen/imports/ImportSheet.swift")
        row = declaration(text, 'ImportMethodRow(id: "import_jw"')
        self.assertNotIn("onDismiss()", row)
        self.assertIn("jwPresentation = JwImportPresentation()", row)
        self.assertIn(".sheet(item: $jwPresentation, onDismiss: handleJwDismissed)", text)
        handler = declaration(text, "private func handleJwDismissed")
        self.assertIn("jwReturn.didDismiss()", handler)
        self.assertIn("onDismiss()", handler)
        self.assertIn(".interactiveDismissDisabled(jwActiveImport)", text)
        self.assertIn(".environment(\\.localWakeUpColors, colors)", text)

    def test_draft_box_finishes_dismissing_before_restore(self):
        text = source("ui/screen/imports/ImportSheet.swift")
        self.assertIn(".sheet(isPresented: $showDrafts, onDismiss: restoreSelectedDraft)", text)
        restore = declaration(text, "private func restoreSelectedDraft")
        self.assertIn("pendingRestoreDraftId = nil", restore)
        self.assertIn("JwImportPresentation(draftId: id)", restore)
        self.assertNotIn("asyncAfter", restore)

    def test_direct_host_has_no_return_to_methods_or_presentation_timer(self):
        app = source("SleepyApp.swift")
        self.assertNotIn("jwImportRequested", app)
        self.assertIn("JwImportReturnState(origin: .direct)", app)
        self.assertIn("jwReturn.didDismiss()", app)
        self.assertIn("jwImportActive = true", declaration(app, ".onChange(of: root.pendingDraftId)"))
        self.assertIn("SleepyThemeProvider(darkTheme: isDark", app)
        self.assertIn(".interactiveDismissDisabled(jwActiveImport)", app)
        manage = source("ui/screen/manage/ManagementPage.swift")
        self.assertNotIn("onJwImportRequested", manage)
        self.assertNotIn("onRestoreDraft", manage)

    def test_flow_distinguishes_success_and_exit_preserves_confirmation(self):
        flow = source("ui/screen/imports/JwImportFlow.swift")
        self.assertIn("let onFinish: (JwImportOutcome) -> Void", flow)
        finish = declaration(flow, "private func finishFlow")
        self.assertIn("guard !didFinishFlow else { return }", finish)
        self.assertIn("onFinish(importOutcome)", finish)
        success = declaration(flow, "private func finishOrReport")
        self.assertIn("importOutcome = .completed", success)
        request = declaration(flow, "private func requestExit")
        self.assertIn("if isApplying { return }", request)
        self.assertIn("reduceExitDraftState(exitDraftState, .requestExit)", request)
        self.assertNotIn("incomingDraftId == nil", request)
        choice = declaration(flow, "private func handleExitChoice")
        self.assertIn("reduceExitDraftState(exitDraftState, .choose(choice))", choice)

    def test_real_swift_cancel_success_and_single_consumption(self):
        flow = source("ui/screen/imports/JwImportFlow.swift")
        self.assertIn("struct JwImportReturnState", flow)
        parts = [declaration(flow, "enum JwImportOutcome"), declaration(flow, "struct JwImportReturnState")]
        parts.append('''
// 选校下滑/取消没有成功事件：保留原入口。
var methods = JwImportReturnState(origin: .importMethods)
assert(!methods.didDismiss())
methods.record(.cancelled)
assert(!methods.didDismiss())
// 成功通知不立即关闭父 sheet；dismiss 完成时才返回关闭动作。
methods.record(.completed)
assert(methods.didDismiss())
assert(!methods.didDismiss())
// 下一次恢复草稿/普通导入不会继承上次成功。
methods.record(.cancelled)
assert(!methods.didDismiss())
// 成功后迟到的取消不能将已落库结果降级。
methods.record(.completed)
methods.record(.cancelled)
assert(methods.didDismiss())
// 直接/外部草稿入口的取消和成功都不操作导入方式页。
var direct = JwImportReturnState(origin: .direct)
assert(!direct.didDismiss())
direct.record(.cancelled)
assert(!direct.didDismiss())
direct.record(.completed)
assert(!direct.didDismiss())
print("import return policy passed")
''')
        result = subprocess.run(["swift", "-"], input="\n".join(parts), text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_existing_exit_confirmation_reducer_still_blocks_progress_loss(self):
        text = source("ui/screen/imports/ExitDraftState.swift")
        names = ("enum ExitDraftChoice", "struct ExitDraftState", "enum ExitDraftEvent",
                 "enum ExitDraftOutcome", "struct ExitDraftReduction", "func reduceExitDraftState")
        parts = [declaration(text, name) for name in names]
        parts.append('''
let emptyExit = reduceExitDraftState(ExitDraftState(), .requestExit)
assert(emptyExit.outcome == .finishDirectly)
let progress = reduceExitDraftState(ExitDraftState(activeImport: true), .requestExit)
assert(progress.outcome == .none && progress.state.confirmationVisible)
let continued = reduceExitDraftState(progress.state, .choose(.continueImport))
assert(continued.outcome == .none && continued.state.activeImport && !continued.state.confirmationVisible)
assert(reduceExitDraftState(progress.state, .choose(.keepDraft)).outcome == .keepDraft)
assert(reduceExitDraftState(progress.state, .choose(.deleteDraft)).outcome == .deleteDraft)
''')
        result = subprocess.run(["swift", "-"], input="\n".join(parts), text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
