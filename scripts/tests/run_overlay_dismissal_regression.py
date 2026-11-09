#!/usr/bin/env python3
"""Run the production overlay dismissal state and its XCTest cases without an app build."""

from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "Sleepy/ui/nav/OverlayDismissalState.swift"
TESTS = ROOT / "SleepyTests/OverlayDismissalStateTests.swift"


def main() -> None:
    platform = Path(subprocess.check_output(
        ["xcrun", "--sdk", "macosx", "--show-sdk-platform-path"], text=True
    ).strip())
    frameworks = platform / "Developer/Library/Frameworks"
    libraries = platform / "Developer/usr/lib"
    source = "\n".join(
        [
            HELPER.read_text(),
            TESTS.read_text(),
            "let suite = XCTestSuite(forTestCaseClass: OverlayDismissalStateTests.self)",
            "suite.run()",
            "guard let run = suite.testRun, run.executionCount == 6, run.failureCount == 0 else { fatalError(\"Overlay dismissal regression failed\") }",
        ]
    )
    with tempfile.TemporaryDirectory(prefix="sleepy-overlay-dismissal-") as directory:
        script = Path(directory) / "main.swift"
        script.write_text(source)
        subprocess.run(
            ["swift", "-F", str(frameworks), "-I", str(libraries), "-L", str(libraries),
             "-lXCTestSwiftSupport", "-D", "OVERLAY_DISMISSAL_STANDALONE", str(script)],
            check=True,
        )


if __name__ == "__main__":
    main()
