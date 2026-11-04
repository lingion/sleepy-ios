#!/usr/bin/env python3
"""真实持久化源码 + macOS XCTest，离线 GRDB、独立 scratch、单 job。"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
scratch = Path(os.environ['OCCURRENCE_CHECK_DIR']).resolve()
grdb = Path(os.environ['GRDB_SOURCE']).resolve()
if scratch == root or root in scratch.parents:
    raise SystemExit('scratch 必须位于工作树之外')
scratch.mkdir(parents=True, exist_ok=True)
sources = scratch / 'Sources' / 'Sleepy'
tests = scratch / 'Tests' / 'SleepyTests'
sources.mkdir(parents=True, exist_ok=True)
tests.mkdir(parents=True, exist_ok=True)
files = sorted((root / 'Sleepy/data/entity').glob('*.swift'))
files += sorted((root / 'Sleepy/data/dao').glob('*.swift'))
files += [root / 'Sleepy' / name for name in [
    'data/AppDatabase.swift', 'data/repository/ScheduleRepository.swift',
    'data/repository/CourseOccurrenceDestination.swift', 'data/repository/NewTableImport.swift',
    'data/repository/ImportRoster.swift', 'data/undo/UndoManager.swift',
    'data/diff/RowKeyDiffer.swift', 'util/TimeTableUtils.swift',
]]
manifest = {}
for source in files:
    shutil.copy2(source, sources / source.name)
    manifest[str(source.relative_to(root))] = hashlib.sha256(source.read_bytes()).hexdigest()
shutil.copy2(Path(__file__).with_name('Support.swift'), sources / 'Support.swift')
for source in sorted((root / 'SleepyTests').glob('CourseOccurrenceMove*Tests.swift')):
    shutil.copy2(source, tests / source.name)
    manifest[str(source.relative_to(root))] = hashlib.sha256(source.read_bytes()).hexdigest()
(scratch / 'source-sha256.json').write_text(json.dumps(manifest, indent=2) + '\n')
(scratch / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "OccurrenceMoveCheck", platforms: [.macOS(.v13)],
    dependencies: [.package(path: %s)],
    targets: [
        .target(name: "Sleepy", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "SleepyTests", dependencies: ["Sleepy", .product(name: "GRDB", package: "GRDB.swift")])
    ], swiftLanguageVersions: [.v5])
''' % json.dumps(str(grdb)))
sys.exit(subprocess.call(['nice', '-n', '15', 'swift', 'test', '--package-path', str(scratch),
                          '--jobs', '1', '-Xswiftc', '-j1', '--filter', 'CourseOccurrenceMove']))
