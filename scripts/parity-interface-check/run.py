#!/usr/bin/env python3
"""无 xcodebuild；独立目录、离线 GRDB、单 job 编译。临时副本不改已有测试。"""
import os
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
scratch = Path(os.environ['PARITY_CHECK_DIR']).resolve()
grdb = Path(os.environ['GRDB_SOURCE']).resolve()
scratch.mkdir(parents=True, exist_ok=True)
sources = scratch / 'Sources' / 'Sleepy'
tests = scratch / 'Tests' / 'SleepyTests'
sources.mkdir(parents=True, exist_ok=True)
tests.mkdir(parents=True, exist_ok=True)
for relative in ['util/AppPrefs.swift', 'util/CourseColorUtil.swift', 'util/CourseColorWriteGlue.swift',
                 'util/CourseHueStore.swift', 'data/entity/CourseEntity.swift',
                 'data/entity/CourseColorEntity.swift', 'data/dao/CourseColorDao.swift']:
    shutil.copy2(root / 'Sleepy' / relative, sources / Path(relative).name)
shutil.copy2(Path(__file__).with_name('Support.swift'), sources / 'Support.swift')
for name in ['CourseColorWriteGlueTests.swift', 'ParityInterfaceCompatibilityTests.swift',
             'CourseColorCommitBoundaryTests.swift', 'PeriodHeaderTimeAlignmentPrefsTests.swift']:
    shutil.copy2(root / 'SleepyTests' / name, tests / name)
# 只选择偏好测试类；同文件的 repository 类依赖整个 App，此 target 不伪造其实现。
mode = (root / 'SleepyTests/ReminderModeAndTableReminderTests.swift').read_text()
mode = mode[:mode.index('/// 每课表提醒开关')]
(tests / 'BeforeClassModePrefsTests.swift').write_text(mode)
(scratch / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ParityInterfaceCheck", platforms: [.macOS(.v13)],
    dependencies: [.package(path: "%s")],
    targets: [
        .target(name: "Sleepy", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "SleepyTests", dependencies: ["Sleepy", .product(name: "GRDB", package: "GRDB.swift")])
    ], swiftLanguageVersions: [.v5])
''' % str(grdb))
sys.exit(subprocess.call(['swift', 'test', '--package-path', str(scratch), '--jobs', '1',
                          '-Xswiftc', '-j1']))
