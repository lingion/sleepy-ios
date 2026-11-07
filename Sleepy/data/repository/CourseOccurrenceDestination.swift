import Foundation

/// 拖放预览与持久化共用的目标范围；table 必须已 hydratedWith 绑定作息。
/// step 是目标实际覆盖节数，仅供布局；持久化应保留原行 step 元数据。
struct CourseOccurrenceDestination: Equatable {
    enum ResolutionError: Error {
        case invalidDestination
        case invalidTime
    }

    let startNode: Int
    let endNode: Int
    let startTime: String
    let endTime: String
    let usesOwnTime: Bool
    var step: Int { endNode - startNode + 1 }

    /// nil 吸附节次起点；横移传原时刻，保持分数行及秒级时长。
    static func resolve(source: CourseEntity, targetNode: Int,
                        table: TimeTableEntity, targetStartTime: String? = nil) throws -> CourseOccurrenceDestination {
        guard targetNode >= 1, targetNode <= table.nodesPerDay else {
            throw ResolutionError.invalidDestination
        }
        let parsed = TimeTableUtils.parseNodes(table.timeJson)
        guard !parsed.isEmpty, Set(parsed.map { $0.node }).count == parsed.count else {
            throw ResolutionError.invalidDestination
        }
        let rows = TimeTableUtils.parseTimeSlotRows(table.timeJson)
            .filter { $0.node >= 1 && $0.node <= table.nodesPerDay }
            .sorted { $0.node < $1.node }
        guard rows.count == table.nodesPerDay else { throw ResolutionError.invalidDestination }
        var slots: [(start: Int, end: Int)] = []
        for (index, row) in rows.enumerated() {
            guard row.node == index + 1,
                  let start = TimeTableUtils.hmToSeconds(row.start),
                  let end = TimeTableUtils.hmToSeconds(row.end), end > start,
                  slots.last.map({ $0.end <= start }) ?? true else {
                throw ResolutionError.invalidDestination
            }
            slots.append((start, end))
        }
        let usesOwnTime = source.ownTime || source.isIrregularTime
        let targetStart: Int
        if let targetStartTime {
            guard usesOwnTime,
                  let explicitStart = TimeTableUtils.hmToSeconds(targetStartTime) else {
                throw ResolutionError.invalidTime
            }
            guard let mappedIndex = slots.lastIndex(where: { $0.start <= explicitStart }),
                  mappedIndex + 1 == targetNode else {
                throw ResolutionError.invalidDestination
            }
            targetStart = explicitStart
        } else {
            targetStart = slots[targetNode - 1].start
        }
        let targetEnd: Int
        let endNode: Int
        if usesOwnTime {
            guard let start = TimeTableUtils.hmToSeconds(source.startTime),
                  let end = TimeTableUtils.hmToSeconds(source.endTime), end > start else {
                throw ResolutionError.invalidTime
            }
            targetEnd = targetStart + end - start
            guard let last = slots.last, targetEnd < 24 * 60 * 60, targetEnd <= last.end else {
                throw ResolutionError.invalidTime
            }
            endNode = (slots.lastIndex(where: { $0.start < targetEnd }) ?? (targetNode - 1)) + 1
        } else {
            guard source.step > 0, source.step <= table.nodesPerDay - targetNode + 1 else {
                throw ResolutionError.invalidDestination
            }
            endNode = targetNode + source.step - 1
            targetEnd = slots[endNode - 1].end
        }
        return CourseOccurrenceDestination(startNode: targetNode, endNode: endNode,
            startTime: timeString(targetStart), endTime: timeString(targetEnd), usesOwnTime: usesOwnTime)
    }

    private static func timeString(_ seconds: Int) -> String {
        let hm = String(format: "%02d:%02d", seconds / 3600, seconds / 60 % 60)
        return seconds % 60 == 0 ? hm : hm + String(format: ":%02d", seconds % 60)
    }
}
