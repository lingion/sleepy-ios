import XCTest
@testable import Sleepy

final class WeekProjectionCacheTests: XCTestCase {
    private var table: TimeTableEntity {
        TimeTableEntity(name: "Cache", startDate: "2026-09-07", id: 919)
    }
    private func course(_ id: Int64 = 1) -> CourseEntity {
        CourseEntity(groupId: "g", tableId: table.id, courseName: "Lesson", room: "Original",
                     day: 1, startNode: 1, step: 2, startWeek: 1, endWeek: 20,
                     color: "#FF6750A4", id: id)
    }
    private func reference(_ table: TimeTableEntity, week: Int, courses: [CourseEntity],
                           transfers: [HolidayTransferEntry], timeJson: String?) -> [CourseEntity] {
        (1...7).flatMap { day in
            guard let date = CourseOccurrences.date(startDate: table.startDate, week: week, day: day) else {
                return [CourseEntity]()
            }
            return HolidayTransferOps.coursesForDate(date, startDate: table.startDate,
                maxWeek: table.maxWeek, courses: courses, transfers: transfers).map { course in
                    var projected = course
                    projected.day = day
                    if let timeJson { projected = projected.normalizeNode(timeJson: timeJson) }
                    return projected
                }
        }
    }

    func testSameIDCourseEditsAndTimetableInputsNeverReturnOldProjection() throws {
        var table = self.table
        var lesson = course()
        let transfer = HolidayTransferEntry(sourceDate: try XCTUnwrap(DateUtils.parseDate("2026-09-07")),
            targetDate: try XCTUnwrap(DateUtils.parseDate("2026-09-19")), segmentId: "holiday")
        func verify(_ transfers: [HolidayTransferEntry] = [], _ timeJson: String? = nil) {
            for week in [1, 2, 3, 1] {
                XCTAssertEqual(renderCoursesForWeek(table, week: week, courses: [lesson],
                    transfers: transfers, timeJson: timeJson),
                    reference(table, week: week, courses: [lesson], transfers: transfers, timeJson: timeJson))
            }
        }
        verify()
        lesson.room = "New room"; lesson.alias = "New alias"; lesson.color = "#FF00FF00"
        verify()
        lesson.day = 2; lesson.startWeek = 2; lesson.type = 2
        verify()
        lesson.fixedDate = "2026-09-19"
        verify([transfer])
        lesson.fixedDate = nil; lesson.day = 1; lesson.type = 0; lesson.startWeek = 1
        verify([transfer])
        table.startDate = "2026-09-14"; table.maxWeek = 1
        verify([transfer])
        lesson.ownTime = true; lesson.startTime = "10:00"; lesson.endTime = "10:45"
        verify([], #"[{"node":1,"start":"10:00","end":"10:45"}]"#)
        verify([], #"[{"node":2,"start":"10:00","end":"10:45"}]"#)
    }

    func testEvictionAndConcurrentTablesKeepResultsIsolated() {
        let cache = WeekCourseProjectionCache(capacity: 2)
        let values = (1...12).map { index -> WeekCourseProjectionCache.Input in
            .init(tableId: Int64(index), startDate: table.startDate, maxWeek: 20, week: index,
                  courses: [course(Int64(index))], transfers: [], timeJson: nil, calendar: nil)
        }
        DispatchQueue.concurrentPerform(iterations: 48) { index in
            let input = values[index % values.count]
            let result = cache.value(for: input) { input.courses }
            XCTAssertEqual(result, input.courses)
        }
        for input in values.reversed() {
            XCTAssertEqual(cache.value(for: input) { input.courses }, input.courses)
        }
    }

    func testBenchmarkWarmThreePageProjectionAgainstUncachedPath() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SLEEPY_RUN_PERFORMANCE_TESTS"] == "1")
        let courses = (0..<252).map { index -> CourseEntity in
            var result = course(Int64(index + 1))
            result.groupId = "group-\(index % 8)"
            result.day = index % 7 + 1
            result.startNode = index % 12 + 1
            return result
        }
        let table = self.table
        let timeJson = table.timeJson
        var checksum = 0
        func sample(_ name: String, _ operation: (Int) -> [CourseEntity]) {
            for i in 0..<3 { checksum &+= operation(i + 1).count }
            var samples: [Double] = []
            for _ in 0..<7 {
                let start = DispatchTime.now().uptimeNanoseconds
                for i in 0..<30 { checksum &+= operation(i % 3 + 1).count }
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 30 / 1_000_000)
            }
            print("PROJECTION_BENCH \(name) ms_per_page=\(samples) median=\(samples.sorted()[3]) checksum=\(checksum)")
        }
        sample("uncached") { reference(table, week: $0, courses: courses, transfers: [], timeJson: timeJson) }
        sample("cached") { renderCoursesForWeek(table, week: $0, courses: courses, transfers: [], timeJson: timeJson) }
    }
}
