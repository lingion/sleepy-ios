"""真实 Foundation lookup 回归，不构建主 target。

运行：python3 scripts/tests/test_weekday_lookup.py
编译完整生产 L10n / LocaleHelper / DateUtils，资源原样放入临时 app bundle。
仅用内存 AppPrefs 隔离持久化和 WidgetKit；不替换本地化 lookup。
"""
import json
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
EXPECTED = {
    "en": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
    "zh-CN": ["周一", "周二", "周三", "周四", "周五", "周六", "周日"],
    "zh-TW": ["週一", "週二", "週三", "週四", "週五", "週六", "週日"],
    "ja": ["月", "火", "水", "木", "金", "土", "日"],
    "es": ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"],
}

HARNESS = r'''
import Foundation

final class AppPrefs {
    static let shared = AppPrefs()
    private var language = "en"
    func getLanguage() -> String { language }
    func setLanguage(_ language: String) { self.language = language }
}

var results: [[String: Any]] = []
for language in CommandLine.arguments.dropFirst() {
    AppPrefs.shared.setLanguage(language)
    let bundle = LocaleHelper.currentBundle()
    results.append([
        "language": language,
        "bundle": bundle.bundleURL.lastPathComponent,
        "array": (0...6).map { L10n.dayName($0) },
        "header": (1...7).map { DateUtils.localizedDay($0) },
        "invalid": [0, 8, -1].map { DateUtils.localizedDay($0) },
        "exists": (0...6).map { L10n.has("array_day_names_\($0)") },
        "tailExists": L10n.has("watch_open_on_phone")
    ])
}
let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
'''


class WeekdayLookupRegression(unittest.TestCase):
    def test_five_languages_and_switch_back_use_real_bundle_lookup(self):
        with tempfile.TemporaryDirectory(prefix="sleepy-weekday-") as directory:
            temporary = pathlib.Path(directory)
            contents = temporary / "WeekdayLookup.app" / "Contents"
            resources = contents / "Resources"
            executable = contents / "MacOS" / "WeekdayLookup"
            resources.mkdir(parents=True)
            executable.parent.mkdir()
            (contents / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": "test.sleepy.weekday-lookup",
                "CFBundleExecutable": executable.name,
                "CFBundlePackageType": "APPL",
                "CFBundleDevelopmentRegion": "en",
            }))
            for localized in (ROOT / "Sleepy/resources").glob("*.lproj"):
                shutil.copytree(localized, resources / localized.name)
            harness = temporary / "main.swift"
            harness.write_text(HARNESS)
            sources = [ROOT / "Sleepy/util" / name for name in (
                "L10n.swift", "LocaleHelper.swift", "DateUtils.swift"
            )]
            compiled = subprocess.run(
                ["swiftc", *map(str, sources), str(harness), "-o", str(executable)],
                capture_output=True, text=True, timeout=120,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            # 同进程切五语言再切回英文，验证 currentBundle 没有缓存首选语言。
            result = subprocess.run(
                [str(executable), *EXPECTED, "en"],
                capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            results = json.loads(result.stdout)
            self.assertEqual(len(results), 6)
            for lookup in results:
                language = lookup["language"]
                with self.subTest(language=language):
                    lproj = {"zh-CN": "zh-Hans", "zh-TW": "zh-Hant"}.get(language, language)
                    self.assertEqual(lookup["bundle"], lproj + ".lproj")
                    self.assertEqual(lookup["array"], EXPECTED[language])
                    self.assertEqual(lookup["header"], EXPECTED[language])
                    self.assertEqual(lookup["exists"], [True] * 7)
                    self.assertEqual(lookup["invalid"], [""] * 3)
                    self.assertTrue(lookup["tailExists"], "字符串表尾部也必须能加载")


if __name__ == "__main__":
    unittest.main(verbosity=2)
