#!/usr/bin/env python3
"""低负载离线状态测试：真实 Registry/模型/草稿 codec，解析器实体仅占位，不执行解析。"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
base = Path(os.environ.get("TMPDIR", "/private/var/folders/z3/7cz1vccj2g1clmqqqqh5x4y00000gn/T/opencode"))
scratch = Path(tempfile.mkdtemp(prefix="jw-school-status-", dir=base))
print(f"Harness: {scratch}", flush=True)
sources = scratch / "Sources/Sleepy"
tests = scratch / "Tests/SleepyTests"
sources.mkdir(parents=True)
tests.mkdir(parents=True)
jw = root / "Sleepy/data/jw"
for name in ["JwSchoolInfo.swift", "JwImportDraft.swift", "JwCourse.swift", "JwParserRegistry.swift"]:
    shutil.copy2(jw / name, sources / name)
shutil.copy2(root / "SleepyTests/JwSchoolStatusRegressionTests.swift", tests)

# 保留完整真实 Registry，而不是把 supports 实现替换成测试白名单。
# 只生成其依赖的协议常量、解析器类型及诊断结构；不加载 SwiftSoup/平台 UI。
registry = (jw / "JwParserRegistry.swift").read_text()
protocol = (jw / "JwProtocol.swift").read_text()
constants = re.findall(r'static let (TYPE_\w+)\s*=\s*"([^"]+)"', protocol)
factory = registry.split("static func factoryFor(", 1)[1].split("/// 静态候选", 1)[0]
cases = re.findall(r'case JwProtocol\.(TYPE_\w+): return \{ (Jw\w+)\(\$0(?:, oldType: [01])?\) \}', factory)
assert len(cases) == factory.count("case "), "Registry 工厂形态变化，请审查 harness"
values = dict(constants)
test_source = (root / "SleepyTests/JwSchoolStatusRegressionTests.swift").read_text()
expected_block = test_source.split("let expected: Set<String> = [", 1)[1].split("]", 1)[0]
expected = set(re.findall(r'"([^"]+)"', expected_block))
assert {values[key] for key, _ in cases} == expected, "实际 Registry 支持集合偏离审计清单"
print(f"Verified actual Registry factory set: {len(expected)} types", flush=True)
support = """
protocol JwParser { func generateCourseList() throws -> [JwCourse] }
class UnusedParser: JwParser {
    let oldType: Int
    var oldQzType: Int { 0 }
    init(_ source: String, oldType: Int = 0) {
        self.oldType = oldType
        fatalError("状态测试不得构造或执行解析器")
    }
    func generateCourseList() throws -> [JwCourse] { fatalError("不得执行解析器") }
}
enum JwParseDiagnostics {
    struct ParserAttempt {
        let parserName: String
        let courseCount: Int
        let exception: String?
    }
}
enum JwProtocol {
"""
support += "\n".join(f'    static let {key} = "{value}"' for key, value in constants) + "\n}\n"
support += "\n".join(f"final class {name}: UnusedParser {{}}" for name in sorted({name for _, name in cases}))
(sources / "ParserTypeSupport.swift").write_text(support)
(scratch / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "JwSchoolStatusCheck", platforms: [.macOS(.v13)],
    targets: [.target(name: "Sleepy"), .testTarget(name: "SleepyTests", dependencies: ["Sleepy"])],
    swiftLanguageVersions: [.v5])
''')
sys.exit(subprocess.call(["/usr/bin/nice", "-n", "19", "swift", "test", "--build-system", "native", "--package-path", str(scratch),
                          "--jobs", "1", "-Xswiftc", "-j1", "--filter", "JwSchoolStatusRegressionTests"]))
