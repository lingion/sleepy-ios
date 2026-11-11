#!/usr/bin/env python3
"""Validate one real XCTest class/method before starting an expensive UI build."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if len(sys.argv) != 2:
    raise SystemExit('Expected SleepyUITests/Class[/testMethod]')
selector = sys.argv[1]
match = re.fullmatch(r'SleepyUITests/(\w+)(?:/(test\w+))?', selector)
if not match:
    raise SystemExit('Choose one UI class or method; a whole-target run is not supported')
class_name, method = match.groups()
bodies = []
for path in (ROOT / 'SleepyUITests').glob('*.swift'):
    source = path.read_text()
    # XCTestCase declarations are top-level; a file can contain several classes.
    classes = list(re.finditer(r'(?m)^(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\b', source))
    for index, declaration in enumerate(classes):
        if declaration.group(1) == class_name:
            end = classes[index + 1].start() if index + 1 < len(classes) else len(source)
            bodies.append(source[declaration.end():end])
if len(bodies) != 1:
    raise SystemExit('Unknown or ambiguous UI test class: ' + class_name)
if method and not re.search(r'\bfunc\s+' + re.escape(method) + r'\s*\(\s*\)', bodies[0]):
    raise SystemExit('Unknown UI test method: ' + method)
print('-only-testing:' + selector)
