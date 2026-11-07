# v1.0.63 多步撤回交接

## 本代理写入的补丁

- `Sleepy/data/undo/UndoManager.swift`：独立 undo/redo 栈，默认 5、0 清空并禁用所有入栈、负数无限；立即裁剪两栈；嵌套批次只保首拍；新写清 redo；保留 Repository 的全部既有方法签名。
- `Sleepy/util/AppPrefs.swift`：`undo_depth`、`DEFAULT_UNDO_DEPTH = 5`、`getUndoDepth/setUndoDepth`。设置存储与 Android 同键，单例首次使用加载偏好，历史仍仅在内存。原文件其他已存在改动保留。
- `Sleepy/ui/screen/mine/GeneralSettingsScreen.swift`：实验室最后一行新增深度输入；最多六位数字与可选负号；空串/单负号为编辑中间态，不落库；完整整数即时持久化并 applyMaxDepth；键盘支持负号。
- 三个新增 XCTest 文件（见下）。既有测试不改。

## Repository 所有者必须合入的精确修改

当前 `restoreLastSnapshot` 与 `redoLastUndo` 在 `snapshotCurrent()` 前弹栈，读取或恢复失败都会丢历史。本代理未编辑 `ScheduleRepository.swift`。请用下列函数体替换同名函数（其余逻辑不动）：

```swift
@discardableResult
func restoreLastSnapshot() throws -> Bool {
    let history = UndoManager.shared
    guard history.hasSnapshot else { return false }
    // 当前态读取失败不动两栈。
    let redoSnap = try snapshotCurrent()
    guard let undoSnap = history.poll() else { return false }
    history.restoring = true
    defer { history.restoring = false }
    do {
        try applySnapshot(undoSnap)
    } catch {
        // applySnapshot 是 GRDB 写事务; 回滚 DB 后原位放回栈顶。
        // 禁止 capture 回填: capture 会清空已有 redo 并受批首拍过滤。
        history.reinsertForRedoSymmetry(undoSnap)
        throw error
    }
    history.recordRedo(redoSnap)
    onDataChanged()
    pruneDefaultTopPrefs()
    return true
}

@discardableResult
func redoLastUndo() throws -> Bool {
    let history = UndoManager.shared
    guard history.hasRedoSnapshot else { return false }
    let undoSnap = try snapshotCurrent()
    guard let redoSnap = history.pollRedo() else { return false }
    history.restoring = true
    defer { history.restoring = false }
    do {
        try applySnapshot(redoSnap)
    } catch {
        history.recordRedo(redoSnap)
        throw error
    }
    history.reinsertForRedoSymmetry(undoSnap)
    onDataChanged()
    pruneDefaultTopPrefs()
    return true
}
```

恢复仍沿用现有同步调用模型。UndoManager 的锁只保护历史内存，不跨越 DAO/GRDB 调用，避免与事务内 capture 形成锁序反转。并发的用户数据库写入仍需由 Repository 调用端串行化（现有单次方法锁不等于整次恢复事务锁）。

## 工程与 CI 接线（主会话）

以下新文件需要加入 **SleepyTests target**（本代理按边界未编辑工程/CI）：

1. `SleepyTests/UndoHistoryDepthTests.swift` — 10 个用例：默认五步、三步对称循环、双栈即时裁剪、零禁用、任意负数无限、嵌套批次首拍、分支失效、恢复抑制、失败回填、redo/symmetry 入栈上限。
2. `SleepyTests/UndoDepthPreferencesTests.swift` — 3 个用例：默认/存储重建、负数与中间态、非法输入不得落库。
3. `SleepyTests/UndoRepositoryHistoryTests.swift` — 6 个用例：真实数据库多步循环、新写分支、复合建表插课；undo/redo 写事务故障回滚与历史保留；undo/redo 读取快照故障保留。

建议 CI `-only-testing` 选择：

```text
SleepyTests/UndoHistoryDepthTests
SleepyTests/UndoDepthPreferencesTests
SleepyTests/UndoRepositoryHistoryTests
SleepyTests/UndoManagerTests
SleepyTests/UndoCaptureCoverageTests
SleepyTests/CourseOccurrenceMoveTests
```

`UndoRepositoryHistoryTests` 四个故障用例是 Repository 补丁的验收门槛；未合入上节修改时预期会失败，不能删改断言使其通过。真实恢复事务使用 SQLite `RAISE(ABORT)` 注入故障，在删除已发生后验证事务回滚和重试步序；读取故障通过临时重命名 `period_tables` 注入。

## 全局本地化待合并的三个 keys

UI 暂用当前语言 Bundle + 中文 fallback，不修改全局 localization。Android 五语原文位于 `app/src/main/res/values*/strings.xml`，可直接移入对应 iOS `.strings`：

| key | 中文 fallback | 英文参考 |
| --- | --- | --- |
| `settings_undo_depth` | 撤回保留步数 | Undo history depth |
| `settings_undo_depth_sub` | -1 为无限，0 为关闭撤回，其他数字保留相应步数。默认 5。历史仅存于内存，结束进程即清空。 | -1 for unlimited, 0 to disable undo, any other number keeps that many steps. Default 5. History lives in memory only and clears when the app process ends. |
| `settings_undo_depth_label` | 撤回保留步数输入框 | Undo history depth input |

UI 自动化标识：`general_undo_depth_field`。原生 UI 验收：通用设置 → 实验室，输入 `-1`/`0`/`2` 后离开再进，偏好保持；空串、单独负号不变更已保存值；undo/redo 按钮随深度 0 立即消失。

## 验证状态

按任务约束未执行本机编译、测试、模拟器或 swiftc，也未提交/推送。代码与调用签名作静态核对；`git diff --check`（新增文件以 `--no-index` 核对）未报告空白错误。是否编译通过、19 个新增 XCTest 是否通过及原生设置表现均待主会话线上 CI 验证。
