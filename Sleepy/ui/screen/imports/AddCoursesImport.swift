import Foundation

struct ImportCourseGroup: Identifiable {
    let id: String
    let courseName: String
    let teacher: String
    let rooms: [String]
    let rows: [CourseEntity]
}

struct CourseImportDecision {
    var backupOriginal = true
    var appendConflicts = false
}

/// Shared by every batch source in the explicit-target Add Courses flow.
enum AddCoursesImport {
    enum ValidationError: LocalizedError {
        case empty, emptySelection, missingTarget, invalidSource
        var errorDescription: String? {
            switch self {
            case .empty: return L10n.format("import_content_empty")
            case .emptySelection: return L10n.format("import_selection_empty")
            case .missingTarget, .invalidSource: return L10n.format("manage_no_table")
            }
        }
    }

    static func groupKey(_ course: CourseEntity) -> String {
        if !course.groupId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return course.groupId }
        return "name:" + course.courseName.trimmingCharacters(in: .whitespacesAndNewlines)
            + "|" + course.teacher.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func groups(_ courses: [CourseEntity]) -> [ImportCourseGroup] {
        Dictionary(grouping: courses, by: groupKey).map { id, rows in
            ImportCourseGroup(id: id, courseName: rows[0].courseName, teacher: rows[0].teacher,
                              rooms: Set(rows.map { $0.room.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }).sorted(), rows: rows)
        }.sorted {
            let order = $0.courseName.caseInsensitiveCompare($1.courseName)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    static func validate(_ result: ScheduleParser.ParseResult) throws {
        guard !result.courses.isEmpty else { throw ValidationError.empty }
    }

    static func filtered(_ result: ScheduleParser.ParseResult, selectedKeys: Set<String>) throws -> ScheduleParser.ParseResult {
        let courses = result.courses.filter { selectedKeys.contains(groupKey($0)) }
        guard !courses.isEmpty else { throw ValidationError.emptySelection }
        return ScheduleParser.ParseResult(tableName: result.tableName, startDate: result.startDate, courses: courses,
                                          timeJson: result.timeJson, nodesPerDay: result.nodesPerDay,
                                          droppedLines: result.droppedLines, warnings: result.warnings,
                                          maxWeek: result.maxWeek, groupIdsAuthoritative: result.groupIdsAuthoritative,
                                          periodTable: result.periodTable)
    }

    static func target(repository: ScheduleRepository, tableId: Int64) throws -> TimeTableEntity {
        guard tableId > 0, let table = try repository.getTable(tableId) else { throw ValidationError.missingTarget }
        return table.hydratedWith(try repository.effectivePeriodTable(tableId: tableId))
    }

    static func source(repository: ScheduleRepository, sourceTableId: Int64, targetTableId: Int64) throws -> ScheduleParser.ParseResult {
        _ = try target(repository: repository, tableId: targetTableId)
        guard sourceTableId != targetTableId else { throw ValidationError.invalidSource }
        let source = try target(repository: repository, tableId: sourceTableId)
        let courses = try repository.getCourses(sourceTableId)
        let result = ScheduleParser.ParseResult(tableName: source.name, startDate: source.startDate, courses: courses,
                                               timeJson: source.timeJson, nodesPerDay: source.nodesPerDay,
                                               maxWeek: source.maxWeek, groupIdsAuthoritative: true)
        try validate(result)
        return result
    }
}
