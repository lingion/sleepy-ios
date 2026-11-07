#!/usr/bin/env python3
"""串行独立运行同一份 XCTest，使用真实日期/调休/渲染函数，无 Xcode 工程构建。

仅剥离实体的 GRDB 持久化接口；未调用的 UI 本地化/节次归一化边界显式 trap。
测试均传 timeJson=nil，不替换任何身份映射、日期算法、单双周或渲染逻辑。
"""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


def declaration(source, signature):
    """提取现有完整声明；所选声明无包含不配对花括号的字符串。"""
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def entity_fields(path, name):
    source = read(path)
    fields = source.split(f"struct {name}:", 1)[1].split("{", 1)[1]
    fields = fields.split("    /// GRDB: 自增主键插入后回填", 1)[0]
    return f"struct {name}: Codable, Identifiable {{\n{fields}\n}}\n"


def main():
    tests = read("SleepyTests/CourseOccurrenceIdentityTests.swift")
    course = read("Sleepy/data/entity/CourseEntity.swift")
    holiday = read("Sleepy/util/HolidayReminderPolicy.swift").split("// MARK: - HolidayReminderPolicy", 1)[0]
    renderer = declaration(read("Sleepy/ui/screen/schedule/ScheduleScreen.swift"), "func renderCoursesForWeek(")
    # 表的默认 timeJson 只服务实体构造；这些测试从不启用时间归一化分支。
    boundaries = '''
    enum TimeTableUtils { static let DEFAULT_TIME_JSON = "" }
    enum L10n { static func dayName(_ index: Int) -> String { fatalError("unused localization") } }
    extension CourseEntity {
        func normalizeNode(timeJson: String) -> CourseEntity { fatalError("tests require timeJson=nil") }
    }
    '''
    parts = ["import Foundation", "import XCTest", boundaries,
             entity_fields("Sleepy/data/entity/CourseEntity.swift", "CourseEntity"),
             entity_fields("Sleepy/data/entity/TimeTableEntity.swift", "TimeTableEntity"),
             "extension CourseEntity {" + declaration(course, "func inWeek(") + "}",
             read("Sleepy/util/DateUtils.swift"), holiday, renderer]
    helper = ROOT / "Sleepy/data/repository/CourseOccurrenceIdentity.swift"
    if helper.exists():
        parts.append(helper.read_text())
    parts.append(tests)
    parts.append('''
    let suite = CourseOccurrenceIdentityTests.defaultTestSuite
    suite.run()
    guard let result = suite.testRun, result.executionCount > 0 else { fatalError("no tests ran") }
    exit(result.hasSucceeded ? 0 : 1)
    ''')
    developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
    frameworks = developer / "Platforms/MacOSX.platform/Developer/Library/Frameworks"
    libraries = developer / "Platforms/MacOSX.platform/Developer/usr/lib"
    temporary = Path(tempfile.gettempdir()) / "opencode"
    with tempfile.TemporaryDirectory(prefix="course-identity-", dir=temporary if temporary.is_dir() else None) as work:
        source = Path(work) / "main.swift"
        source.write_text("\n".join(parts))
        executable = Path(work) / "identity-tests"
        subprocess.run(["nice", "-n", "15", "xcrun", "swiftc", "-j", "1", "-num-threads", "1",
                        "-F", str(frameworks), "-Xlinker", "-rpath", "-Xlinker", str(frameworks),
                        "-I", str(libraries), "-L", str(libraries),
                        "-Xlinker", "-rpath", "-Xlinker", str(libraries),
                        "-D", "OCCURRENCE_IDENTITY_STANDALONE", str(source), "-o", str(executable)], check=True)
        for zone in ["Asia/Shanghai", "UTC", "America/Los_Angeles"]:
            print(f"\n=== DateUtils calendar environment: TZ={zone} ===", flush=True)
            subprocess.run([str(executable)], env={**os.environ, "TZ": zone}, check=True)


if __name__ == "__main__":
    main()
