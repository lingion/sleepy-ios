import Foundation

/// The editor owns a fixed table identity; changing the main tab's selection cannot
/// redirect a deep-linked course, an add-to-table request or a quick-add draft.
struct CourseEditorContext {
    let table: TimeTableEntity
    let editingCourse: CourseEntity?
    let groupCourses: [CourseEntity]

    static func load(editingCourse: CourseEntity?, targetTableId: Int64? = nil,
                     initialSlot: CourseAddSlot? = nil, selectedTableId: Int64?,
                     repository: ScheduleRepository) throws -> CourseEditorContext? {
        if editingCourse == nil, let targetTableId, let initialSlot, targetTableId != initialSlot.tableId {
            throw ScheduleRepository.TableEditSaveError.invalidCourseDraft
        }
        guard let tableId = editingCourse?.tableId ?? targetTableId ?? initialSlot?.tableId ?? selectedTableId else {
            return nil // A first manual course may create a table when saved.
        }
        guard let rawTable = try repository.getTable(tableId) else {
            throw ScheduleRepository.TableEditSaveError.missingTable
        }
        let period: PeriodTableEntity?
        if let periodId = rawTable.periodTableId {
            guard let found = try repository.getPeriodTable(periodId) else {
                throw ScheduleRepository.TableEditSaveError.missingPeriodTable
            }
            period = found
        } else {
            period = nil
        }
        let storedCourse: CourseEntity?
        let groupCourses: [CourseEntity]
        if let editingCourse {
            guard let stored = try repository.getCourse(editingCourse.id),
                  stored.tableId == tableId, stored.groupId == editingCourse.groupId,
                  !stored.groupId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ScheduleRepository.TableEditSaveError.invalidCourseDraft
            }
            storedCourse = stored
            groupCourses = try repository.getGroupCourses(tableId, stored.groupId)
            guard !groupCourses.isEmpty else { throw ScheduleRepository.TableEditSaveError.invalidCourseDraft }
        } else {
            storedCourse = nil
            groupCourses = []
        }
        return CourseEditorContext(table: rawTable.hydratedWith(period),
                                   editingCourse: storedCourse, groupCourses: groupCourses)
    }

    private func validateEditingSource(in repository: ScheduleRepository) throws {
        guard try repository.getTable(table.id) != nil else {
            throw ScheduleRepository.TableEditSaveError.missingTable
        }
        if let editingCourse {
            guard let current = try repository.getCourse(editingCourse.id),
                  current.tableId == table.id, current.groupId == editingCourse.groupId else {
                throw ScheduleRepository.TableEditSaveError.invalidCourseDraft
            }
        }
    }

    func save(drafts: [CourseEntity], timeChange: ScheduleRepository.CourseTimeChange? = nil,
              repository: ScheduleRepository) throws {
        try validateEditingSource(in: repository)
        let ownedDrafts = drafts.map { draft -> CourseEntity in
            var copy = draft
            copy.tableId = table.id
            if let editingCourse { copy.groupId = editingCourse.groupId }
            return copy
        }
        try repository.saveCourseDrafts(tableId: table.id, editingGroupId: editingCourse?.groupId,
                                         drafts: ownedDrafts, timeChange: timeChange,
                                         editingCourseId: editingCourse?.id)
    }

    func deleteGroup(repository: ScheduleRepository) throws {
        try validateEditingSource(in: repository)
        guard let editingCourse else { throw ScheduleRepository.TableEditSaveError.invalidCourseDraft }
        try repository.deleteCourseGroup(table.id, editingCourse.groupId)
    }

    func setGroupColor(_ hex: String, repository: ScheduleRepository) throws -> String {
        try validateEditingSource(in: repository)
        guard let editingCourse else { throw ScheduleRepository.TableEditSaveError.invalidCourseDraft }
        try repository.setGroupSourceColor(table.id, editingCourse.groupId, hex)
        return CourseColorUtil.groupSourceColorHex(try repository.getGroupCourses(table.id, editingCourse.groupId))
    }
}
