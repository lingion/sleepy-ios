#!/usr/bin/env python3
"""Partition UI classes once, preserving automatic coverage of new test methods."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXED = {
    "unit-drag": {"CourseDragUITests"},
    "ui-settings": {"MineSettingsUITests", "UIElementAuditUITests", "WatchTimeStripSettingsUITests"},
    "ui-secondary": {"SecondarySettingsCaptureUITests", "SecondaryWorkflowCaptureUITests", "SheetPlatformUITests"},
    "ui-editor": {"CourseEditorUITests", "EditTableHolidayUITests", "QuickAddCourseUITests",
                  "RangeSliderUITests", "TableEditUITests", "TableSwitchUITests", "SwipeBackGestureUITests"},
}
classes = set()
for source in sorted((ROOT / "SleepyUITests").glob("*.swift")):
    classes.update(re.findall(r"\bclass\s+(\w+)\s*:\s*XCTestCase\b", source.read_text()))
if not classes:
    raise SystemExit("No UI test classes discovered")
assigned = [name for group in FIXED.values() for name in group]
if len(assigned) != len(set(assigned)):
    raise SystemExit("A UI class is assigned to multiple suites")
if set(assigned) - classes:
    raise SystemExit("Unknown UI classes: " + ", ".join(sorted(set(assigned) - classes)))
suites = {**FIXED, "ui-workflows": classes - set(assigned)}
if set.union(*suites.values()) != classes or sum(map(len, suites.values())) != len(classes):
    raise SystemExit("UI suite coverage must include each class exactly once")
if len(sys.argv) != 2 or sys.argv[1] not in {*suites, "--check"}:
    raise SystemExit("Usage: ci-ui-test-selectors.py " + "|".join([*suites, "--check"]))
if sys.argv[1] == "--check":
    for suite, names in suites.items():
        print(f"{suite}: {len(names)} UI classes")
    print(f"Verified {len(classes)} UI classes, each assigned exactly once")
else:
    for name in sorted(suites[sys.argv[1]]):
        print(f"-only-testing:SleepyUITests/{name}")
