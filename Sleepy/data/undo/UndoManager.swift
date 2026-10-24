// UndoManager.swift — ← data/undo/UndoManager.kt (逐行翻译, GPL-3.0)
// Sleepy iOS — 100% port of sleepy Android

import Foundation
import SwiftUI

/// 改动前的全库快照 — periodTables+tables+courses+默认表 id (issue#40 起含独立时间节次表)。
struct UndoSnapshot {
    /// 独立时间节次表快照(issue#40)。默认空数组且允许缺省传参 —
    /// 旧三参数构造 `UndoSnapshot(tables:courses:defaultTableId:)` 不经修改继续编译。
    var periodTables: [PeriodTableEntity] = []
    let tables: [TimeTableEntity]
    let courses: [CourseEntity]
    let defaultTableId: Int64?
}

/**
 * 单级撤回的快照槽(进程内单例)。
 *
 * repo 写方法执行前 capture(), 用户点撤回时 poll() 取走并清空 —
 * 单级语义: 撤回不可再撤回; App 进程被杀快照即失效(不落盘)。
 *
 * beginBatch() 支持复合动作(如导入=建表+插课+设默认):
 * 批内多次 capture 只保留第一次, 保证整个动作回退到同一时点;
 * 不在批内时每次 capture 都覆盖槽(单写动作语义)。
 *
 * v7.10.16w 撤回锚定修复(用户 2026-09-10 报"复制课表后追加导入, 撤回把整个
 * 副本撤没了"): 批内首拍原本只在"槽为空"时生效 — 上一动作(如复制课表)留下的
 * 旧快照会被本批误当成动作起点, 撤回跳过本动作直接回到更早, 副本被连根拔。
 * 现在 beginBatch 时把旧快照过期: 本动作首拍必落到"本动作开始前"的库态。
 * 每个用户动作的撤回点 = 该动作自己开始前 — 动作链上不跳步。
 *
 * restoring 抑制恢复动作自身的捕获, 防止 undo 生成新的 undo。
 *
 * 2026-09-21 用户令: 单级 redo — 撤回后可"取消撤回"一次; 任何新写动作清空 redo,
 * 历史不分支。undo/redo 槽互斥有值: 撤回把 undo 槽搬到 redo 槽, 取消撤回反向搬运。
 *
 * Compose mutableStateOf → SwiftUI ObservableObject:
 * 视图订阅 hasSnapshot/hasRedoSnapshot, 撤回/取消撤回按钮随槽有无快照显隐
 * (用户 2026-09-03; redo 槽 2026-09-21 同款订阅)。
 */
final class UndoManager: ObservableObject {
    static let shared = UndoManager()

    /// 槽本体 — 同步读写(语义对齐 Kotlin mutableStateOf: capture 立即可见)。
    /// objectWillChange 手动在主线程发, 供 SwiftUI 按钮显隐订阅。
    private var slotStorage: UndoSnapshot? = nil
    /// 单级 redo 槽 — 与 undo 槽互斥有值(2026-09-21 用户令)
    private var redoSlotStorage: UndoSnapshot? = nil
    private let lock = NSLock()
    private var batchDepth: Int = 0
    /// 本批首拍是否已落: 批内多次 capture 只保第一次 — 但锚定的是本批开始前(非旧快照)
    private var batchCaptured: Bool = false
    /// 恢复动作进行中标记(语义同 Kotlin @Volatile 单开关)
    var restoring: Bool = false

    var hasSnapshot: Bool {
        lock.lock(); defer { lock.unlock() }
        return slotStorage != nil
    }

    var hasRedoSnapshot: Bool {
        lock.lock(); defer { lock.unlock() }
        return redoSlotStorage != nil
    }

    private init() {}

    func beginBatch() {
        batchDepth += 1
        // 批边界 = 新用户动作开始 — 旧动作的快照对新动作是过期锚点, 立即作废。
        // 若真要嵌套批(当前无此用法), 内层 begin 不清 batchCaptured(只在 0→1 清)。
        if batchDepth == 1 { batchCaptured = false }
    }

    func endBatch() { batchDepth = max(batchDepth - 1, 0) }

    func capture(
        tables: [TimeTableEntity],
        courses: [CourseEntity],
        defaultTableId: Int64?,
        periodTables: [PeriodTableEntity] = []
    ) {
        if restoring { return }
        lock.lock()
        // 新用户动作 = 历史从 redo 分叉 — redo 立即作废(标准 undo/redo 语义)。
        // restore 期间捕获本就被抑制, 这里只管非 restore 的正常写路径。
        redoSlotStorage = nil
        if batchDepth > 0 {
            if batchCaptured {
                lock.unlock()
                notifyChange() // redo 槽已作废, 订阅方需刷新(批内后续写不再动 undo 槽)
                return // 批内已有本动作快照 — 保动作链起点
            }
            batchCaptured = true
        }
        slotStorage = UndoSnapshot(periodTables: periodTables, tables: tables, courses: courses, defaultTableId: defaultTableId)
        lock.unlock()
        notifyChange()
    }

    @discardableResult
    func poll() -> UndoSnapshot? {
        lock.lock()
        let s = slotStorage
        slotStorage = nil
        lock.unlock()
        notifyChange()
        return s
    }

    /// 撤回执行时: 当前库态(= 被撤回动作的结果)整体成为 redo 快照。
    func recordRedo(_ snap: UndoSnapshot) {
        lock.lock()
        redoSlotStorage = snap
        lock.unlock()
        notifyChange()
    }

    /// 取消撤回时取走 redo 快照(取走即清, 与 poll 同语义)。
    @discardableResult
    func pollRedo() -> UndoSnapshot? {
        lock.lock()
        let s = redoSlotStorage
        redoSlotStorage = nil
        lock.unlock()
        notifyChange()
        return s
    }

    /// redo 成功后重填 undo 槽。capture 在 restore 抑制下不会自己写槽 —
    /// 但 redo 也是一次"回到过去"的恢复, 用户随后点撤回应能撤掉它。
    /// [snap] = redo 前的库态, 直接重挂回 undo 槽(绕过批/抑制逻辑, 槽内即此值)。
    func reinsertForRedoSymmetry(_ snap: UndoSnapshot) {
        lock.lock()
        slotStorage = snap
        lock.unlock()
        notifyChange()
    }

    func clear() {
        lock.lock()
        slotStorage = nil
        redoSlotStorage = nil
        lock.unlock()
        notifyChange()
    }

    /// SwiftUI 订阅通知必须在主线程发(Combine 要求); 槽写入本身保持同步
    private func notifyChange() {
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
}
