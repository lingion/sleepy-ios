"""独立编译真实 Swift 几何，复用 XCTest 用例的断言；不构建 App。"""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from test_course_occurrence_identity import declaration, entity_fields

ROOT = Path(__file__).resolve().parents[2]


def source(relative):
    return (ROOT / relative).read_text()


class CourseDropCandidateGeometryRegression(unittest.TestCase):
    def test_swift_geometry_regressions(self):
        entity = source("Sleepy/data/entity/CourseEntity.swift")
        entity = entity[entity.index("struct CourseEntity:"):entity.index("    /// GRDB: 自增主键插入后回填")]
        entity = entity.replace("Codable, FetchableRecord, MutablePersistableRecord, Identifiable", "Codable, Identifiable") + "}\n"
        # 保留实体真正的 normalizeNode/inWeek，移除数据库协议适配。
        entity += "extension CourseEntity {" + source("Sleepy/data/entity/CourseEntity.swift").split("extension CourseEntity {", 1)[1]
        view = source("Sleepy/ui/component/CourseTableView.swift")
        render = view[view.index("struct TimeSlot {"):view.index("// MARK: - 实验室开关读取")]
        test_sources = []
        calls = []
        for suite in ["CourseDropCandidateGeometryTests", "CourseCustomTimeContractTests", "CourseDragPolicyTests"]:
            tests = source(f"SleepyTests/{suite}.swift").replace("@testable import Sleepy", "")
            test_sources.append(tests)
            calls.append(f'let suite_{suite} = {suite}.defaultTestSuite; suite_{suite}.run(); precondition(suite_{suite}.testRun!.executionCount > 0 && suite_{suite}.testRun!.hasSucceeded); print("PASS {suite}: \\(suite_{suite}.testRun!.executionCount) tests")')
        tests = "\n".join(test_sources)
        runner = "\n".join(calls)
        # 直接编译 View 的真实分支条件，验证单卡/簇锚点接线，无需构建 SwiftUI App。
        conditions = [(binding, parameter, re.search(rf"let {binding} = (.+)\n", view).group(1))
                      for binding, parameter in [("anchorFrac", "anchor"), ("frac", "course")]]
        conflict = source("Sleepy/ui/component/ConflictCard.swift")
        conditions.append(("conflictSpan", "c", re.search(r"if (.+!c\.endTime\.isEmpty),", conflict).group(1)))
        for binding, parameter, condition in conditions:
            runner += f'''
func accepts_{binding}(_ {parameter}: CourseEntity) -> Bool {{ {condition} }}
var probe_{binding} = CourseEntity(groupId: "probe", tableId: 1, courseName: "probe", day: 1,
    startNode: 1, step: 1, startWeek: 1, endWeek: 1, color: "#123456",
    isIrregularTime: true, startTime: "08:00", endTime: "08:20")
precondition(accepts_{binding}(probe_{binding}))
probe_{binding}.isIrregularTime = false
precondition(!accepts_{binding}(probe_{binding}))
probe_{binding}.ownTime = true
precondition(accepts_{binding}(probe_{binding}))
probe_{binding}.startTime = ""
precondition(!accepts_{binding}(probe_{binding}))
print("PASS actual View {binding} custom-time gate")
'''
        stubs = '''
import Foundation
import XCTest
import Combine
enum L10n {
    static func format(_ key: String, _ values: CVarArg...) -> String { key }
    static func dayName(_ index: Int) -> String { fatalError("unused localization") }
}
extension String { var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
'''
        swift = "\n".join([stubs, entity, render,
            entity_fields("Sleepy/data/entity/TimeTableEntity.swift", "TimeTableEntity"),
            source("Sleepy/util/DateUtils.swift"),
            source("Sleepy/util/HolidayReminderPolicy.swift").split("// MARK: - HolidayReminderPolicy", 1)[0],
            declaration(source("Sleepy/ui/screen/schedule/ScheduleScreen.swift"), "func renderCoursesForWeek("),
            source("Sleepy/data/repository/CourseOccurrenceIdentity.swift"),
            source("Sleepy/util/TimeTableUtils.swift"),
            source("Sleepy/data/entity/SmartPeriodConfig.swift"),
            source("Sleepy/util/TimetableViewportPolicy.swift"),
            source("Sleepy/util/MealBreakDetector.swift"),
            source("Sleepy/data/repository/CourseOccurrenceDestination.swift"),
            declaration(source("Sleepy/ui/component/NativeCourseDrag.swift"), "private func traceCourseDrag("),
            "@MainActor " + declaration(source("Sleepy/ui/component/NativeCourseDrag.swift"), "final class CourseDragContext:"),
            declaration(source("Sleepy/ui/component/NativeCourseDrag.swift"), "extension CourseDropGrid {"),
            source("Sleepy/ui/component/CourseDragPolicy.swift"), tests, runner])
        temp_root = Path("/private/var/folders/z3/7cz1vccj2g1clmqqqqh5x4y00000gn/T/opencode")
        with tempfile.TemporaryDirectory(prefix="course-drop-geometry-", dir=temp_root) as temp:
            path = Path(temp)
            (path / "main.swift").write_text(swift)
            developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
            frameworks = developer / "Platforms/MacOSX.platform/Developer/Library/Frameworks"
            libraries = developer / "Platforms/MacOSX.platform/Developer/usr/lib"
            built = subprocess.run(["nice", "-n", "15", "xcrun", "swiftc", "-j", "1", "-num-threads", "1",
                                    "-F", str(frameworks), "-I", str(libraries), "-L", str(libraries),
                                    "-Xlinker", "-rpath", "-Xlinker", str(frameworks),
                                    "-Xlinker", "-rpath", "-Xlinker", str(libraries),
                                    str(path / "main.swift"), "-o", str(path / "tests")],
                                   text=True, capture_output=True)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            ran = subprocess.run([str(path / "tests")], text=True, capture_output=True)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            print(ran.stdout)


if __name__ == "__main__":
    unittest.main()
