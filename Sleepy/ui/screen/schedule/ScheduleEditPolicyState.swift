// ScheduleEditPolicyState.swift — ← ui/screen/schedule/ScheduleEditPolicyState.kt
// 甲案 (设计文档 §2.1) — 编辑课表时绑定了共享作息表情况下, 用户对作息改动的处置选择。
//
// 平台映射: Kotlin MutableStateFlow/StateFlow → @Published (只读对外,
// 写入走方法, 与 asStateFlow() 语义一致)。纯逻辑 reducer, 零 UI 依赖,
// 直接构造即可测 (ScheduleEditPolicyStateTests 锁 7 条不变量中的 1/3/4/5/6 + null 自洽)。

import Foundation
import Combine

/// 甲案 (设计文档 §2.1) — 处置选择枚举。
/// - none:        未发生 / 已清空 — 默认状态, 也用于"取消"和"选择后再次改作息"。
/// - detachCopy:  改本表作息: 用 draftEffectiveSchedule 写本表内置作息 + 解绑共享表。
/// - createNew:   以 draftEffectiveSchedule 新建同名独立作息表 + 改绑到新表。
/// - sync:        把 draftEffectiveSchedule 写回共享作息表 (影响所有绑定它的课表)。
///
/// 不变量 7: 三个选项始终显示 (不隐藏), 影响数量仅用于提示文案。
enum SchedulePolicy: Equatable {
    case none
    case detachCopy
    case createNew
    case sync
}

/// 设计文档 §2.1 — 单张课表编辑会话的状态容器:
///
/// - originalEffectiveSchedule: 进入编辑页时实际生效的作息 (含绑定水合结果)。
/// - draftEffectiveSchedule:    用户当前正在编辑的作息草稿; 改作息时由 UI 写入。
/// - pendingSchedulePolicy:     弹窗选择结果, 数据库写入必须等待再次保存 + 此策略仍生效。
///
/// 7 条不变量 (§2.2) 全部在此容器内闭环:
///   1. 未改作息 → hasScheduleChanged=false
///   3. selectPolicy 只登记策略, 不动 draft
///   5. updateDraft 后若 draft ≠ original → pendingSchedulePolicy 自动归零 (旧策略失效)
///   6. cancelPolicy → draft 恢复 original, 策略归零
///
/// 独立 holder (← Kotlin 注释: 不依赖 ScheduleViewModel 字段初始化器, 纯测可构造)。
/// 原 data class equals → PeriodTableEntity 全字段值等价 (见下方 Equatable 扩展)。
final class ScheduleEditPolicyState: ObservableObject {
    let tableId: Int64
    private let originalEffectiveSchedule: PeriodTableEntity?

    @Published private(set) var draftEffectiveSchedule: PeriodTableEntity?
    @Published private(set) var pendingSchedulePolicy: SchedulePolicy = .none

    init(tableId: Int64, originalEffectiveSchedule: PeriodTableEntity?) {
        self.tableId = tableId
        self.originalEffectiveSchedule = originalEffectiveSchedule
        self.draftEffectiveSchedule = originalEffectiveSchedule
    }

    /// 设计文档 §2.2 不变量 1 — 草稿与原值不相等即视为改了作息。
    /// 用全字段值等价: 任一字段变化 (timeJson/nodesPerDay/smartConfigJson/name …) 都触发。
    func hasScheduleChanged() -> Bool {
        draftEffectiveSchedule != originalEffectiveSchedule
    }

    /// UI 节次编辑区提交草稿。设计文档 §2.2 不变量 5: 改了就让旧策略失效, 下一次保存重新弹三选项。
    func updateDraft(_ draft: PeriodTableEntity?) {
        draftEffectiveSchedule = draft
        if draft != originalEffectiveSchedule && pendingSchedulePolicy != .none {
            pendingSchedulePolicy = .none
        }
    }

    /// 设计文档 §2.2 不变量 3 — 只登记, 不动草稿; 真正的写入仍要等再次保存。
    func selectPolicy(_ policy: SchedulePolicy) {
        pendingSchedulePolicy = policy
    }

    /// 设计文档 §2.2 不变量 6 — 弹窗取消: 草稿恢复 original + 策略清零。
    /// 取消仅影响作息相关改动, 不影响其他字段 (课程行/名称/日期等) — 那些由 UI 自留草稿。
    func cancelPolicy() {
        draftEffectiveSchedule = originalEffectiveSchedule
        pendingSchedulePolicy = .none
    }
}

// ← Kotlin data class 自动 equals → Swift 结构体无合成 ==, 按全字段补值等价
//   (id/createdAt/updatedAt 也在 原 equals 内, 一并比较保持语义 1:1)。
extension PeriodTableEntity: Equatable {
    static func == (lhs: PeriodTableEntity, rhs: PeriodTableEntity) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.nodesPerDay == rhs.nodesPerDay
            && lhs.timeJson == rhs.timeJson
            && lhs.smartConfigJson == rhs.smartConfigJson
            && lhs.createdAt == rhs.createdAt
            && lhs.updatedAt == rhs.updatedAt
    }
}
