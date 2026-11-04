// UndoManager.swift — ← data/undo/UndoManager.kt (GPL-3.0)
// v1.0.63: 进程内多步撤回/重做, 两栈末元素为最近一步。

import Foundation
import SwiftUI

/// 改动前的全库快照。保留旧三参数构造和 capture 调用兼容。
struct UndoSnapshot {
    var periodTables: [PeriodTableEntity] = []
    let tables: [TimeTableEntity]
    let courses: [CourseEntity]
    let defaultTableId: Int64?
}

/// 每个写动作压入一个起点; 复合动作(含嵌套批次)只记录最外层批次的首拍。
/// 恢复期间不捕获, 新写清空 redo。快照不落盘, 进程结束即清空。
final class UndoManager: ObservableObject {
    static let DEFAULT_MAX_DEPTH = AppPrefs.DEFAULT_UNDO_DEPTH
    // 首次使用即恢复偏好, 无需依赖某个页面出现或额外的 App 启动接线。
    static let shared = UndoManager(maxDepth: AppPrefs.shared.getUndoDepth())

    private var undoStack: [UndoSnapshot] = []
    private var redoStack: [UndoSnapshot] = []
    private let lock = NSLock()
    private var depthLimit: Int
    private var batchDepth = 0
    private var batchCaptured = false
    private var isRestoring = false

    /// 内部构造器供独立历史会话/测试使用, 不污染进程单例。
    init(maxDepth: Int = UndoManager.DEFAULT_MAX_DEPTH) {
        depthLimit = maxDepth
    }

    var restoring: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return isRestoring
        }
        set {
            lock.lock(); defer { lock.unlock() }
            isRestoring = newValue
        }
    }

    /// 0 禁用, 正数保留最近 N 步, 任意负数无限。赋值立即裁剪两栈。
    var maxDepth: Int {
        get {
            lock.lock(); defer { lock.unlock() }
            return depthLimit
        }
        set { applyMaxDepth(newValue) }
    }

    var hasSnapshot: Bool {
        lock.lock(); defer { lock.unlock() }
        return !undoStack.isEmpty
    }

    var hasRedoSnapshot: Bool {
        lock.lock(); defer { lock.unlock() }
        return !redoStack.isEmpty
    }

    func beginBatch() {
        lock.lock(); defer { lock.unlock() }
        batchDepth += 1
        if batchDepth == 1 { batchCaptured = false }
    }

    func endBatch() {
        lock.lock(); defer { lock.unlock() }
        batchDepth = max(batchDepth - 1, 0)
    }

    func capture(
        tables: [TimeTableEntity],
        courses: [CourseEntity],
        defaultTableId: Int64?,
        periodTables: [PeriodTableEntity] = []
    ) {
        lock.lock()
        guard !isRestoring, depthLimit != 0 else { lock.unlock(); return }
        redoStack.removeAll()
        if batchDepth > 0 {
            if batchCaptured {
                lock.unlock()
                notifyChange()
                return
            }
            batchCaptured = true
        }
        undoStack.append(UndoSnapshot(periodTables: periodTables, tables: tables,
                                     courses: courses, defaultTableId: defaultTableId))
        Self.trim(&undoStack, to: depthLimit)
        lock.unlock()
        notifyChange()
    }

    /// 取走最近一步。Repository 恢复失败时须 reinsertForRedoSymmetry 回填此快照。
    @discardableResult
    func poll() -> UndoSnapshot? {
        lock.lock()
        let snapshot = undoStack.popLast()
        lock.unlock()
        if snapshot != nil { notifyChange() }
        return snapshot
    }

    /// undo 成功后压入撤回前的库态; redo 失败也用本方法回填原 redo 栈顶。
    func recordRedo(_ snapshot: UndoSnapshot) {
        lock.lock()
        guard depthLimit != 0 else { lock.unlock(); return }
        redoStack.append(snapshot)
        Self.trim(&redoStack, to: depthLimit)
        lock.unlock()
        notifyChange()
    }

    @discardableResult
    func pollRedo() -> UndoSnapshot? {
        lock.lock()
        let snapshot = redoStack.popLast()
        lock.unlock()
        if snapshot != nil { notifyChange() }
        return snapshot
    }

    /// redo 成功后压入重做前的库态; undo 失败则回填原 undo 栈顶。
    /// 绕过 capture 的批首拍/restoring 过滤, 且不清空另一条栈。
    func reinsertForRedoSymmetry(_ snapshot: UndoSnapshot) {
        lock.lock()
        guard depthLimit != 0 else { lock.unlock(); return }
        undoStack.append(snapshot)
        Self.trim(&undoStack, to: depthLimit)
        lock.unlock()
        notifyChange()
    }

    func applyMaxDepth(_ value: Int) {
        lock.lock()
        depthLimit = value
        Self.trim(&undoStack, to: value)
        Self.trim(&redoStack, to: value)
        lock.unlock()
        notifyChange()
    }

    func clear() {
        lock.lock()
        undoStack.removeAll()
        redoStack.removeAll()
        lock.unlock()
        notifyChange()
    }

    private static func trim(_ stack: inout [UndoSnapshot], to depth: Int) {
        if depth == 0 { stack.removeAll() }
        else if depth > 0 && stack.count > depth { stack.removeFirst(stack.count - depth) }
    }

    /// 状态同步写入, SwiftUI 订阅通知在主线程发送。
    private func notifyChange() {
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
}
