import XCTest
import GRDB
@testable import Sleepy

final class JwCourseUpdateSubmissionTests: XCTestCase {
    override func tearDown() {
        Sleepy.UndoManager.shared.clear()
        super.tearDown()
    }

    private func course(_ tableId: Int64, room: String = "A101") -> CourseEntity {
        CourseEntity(groupId: "math", tableId: tableId, courseName: "Math", room: room,
            day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 16, color: "#FF6750A4")
    }

    func testReviewedUpdateUsesInjectedRepositoryAndPublishesCommittedData() throws {
        let repository = ScheduleRepository(try AppDatabase.inMemory())
        let target = try repository.insertTable(TimeTableEntity(name: "Target", startDate: "2026-09-07"))
        let other = try repository.insertTable(TimeTableEntity(name: "Other", startDate: "2026-09-07"))
        _ = try repository.insertCourse(course(target))
        _ = try repository.insertCourse(course(other))
        let before = try repository.getCourses(target)
        let diff = diffImportedCourses(existing: before, incoming: [course(target, room: "B202")])
        var committedRooms: [[String]] = []
        repository.onDataChangedHook = {
            committedRooms.append((try? repository.getCourses(target).map(\.room)) ?? [])
        }
        defer { repository.onDataChangedHook = nil }

        XCTAssertTrue(try JwCourseUpdateCommit(repository: repository).apply(tableId: target,
            diff: diff, incomingTimeJson: "", expectedCourses: before))

        XCTAssertEqual(committedRooms, [["B202"]], "The app callback must run after the injected database commit")
        XCTAssertEqual(try repository.getCourses(target).map(\.id), before.map(\.id))
        XCTAssertEqual(try repository.getCourses(other).map(\.room), ["A101"])
    }

    func testIdenticalImportDoesNotWriteNotifyOrConsumeUndo() throws {
        let database = try AppDatabase.inMemory()
        let repository = ScheduleRepository(database)
        let target = try repository.insertTable(TimeTableEntity(name: "Target", startDate: "2026-09-07"))
        _ = try repository.insertCourse(course(target))
        let before = try repository.getCourses(target)
        let diff = diffImportedCourses(existing: before, incoming: [course(target)])
        Sleepy.UndoManager.shared.clear()
        var notifications = 0
        repository.onDataChangedHook = { notifications += 1 }
        let writesBefore = try database.dbQueue.read { try Int.fetchOne($0, sql: "SELECT total_changes()") }

        XCTAssertFalse(JwCourseUpdateCommit.hasChanges(diff))
        XCTAssertFalse(try JwCourseUpdateCommit(repository: repository).apply(tableId: target,
            diff: diff, incomingTimeJson: "", expectedCourses: before))

        XCTAssertEqual(try repository.getCourses(target), before)
        XCTAssertEqual(try database.dbQueue.read { try Int.fetchOne($0, sql: "SELECT total_changes()") }, writesBefore)
        XCTAssertEqual(notifications, 0)
        XCTAssertFalse(repository.canUndo)
    }

    func testTargetImportDismissalLocksOnlyForSubmissionOrReport() {
        XCTAssertFalse(JwImportInteraction.locksDismissal(activeImport: false, isApplying: false, reportVisible: false))
        XCTAssertTrue(JwImportInteraction.locksDismissal(activeImport: false, isApplying: true, reportVisible: false),
            "Target imports have no draft lock, but an in-flight database write must prevent swipe dismissal")
        XCTAssertTrue(JwImportInteraction.locksDismissal(activeImport: false, isApplying: false, reportVisible: true))
        XCTAssertTrue(JwImportInteraction.locksDismissal(activeImport: true, isApplying: false, reportVisible: false))
    }
}
