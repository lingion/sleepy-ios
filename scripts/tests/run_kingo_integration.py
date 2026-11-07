#!/usr/bin/env python3
"""真实 SwiftSoup 的教务独立 XCTest；本轮仅供线上 CI 执行，不启动 Xcode。

python3 scripts/tests/run_kingo_integration.py --swiftsoup /path/to/SwiftSoup \
    --package-dir /path/to/new-owned-package [--filter JwKingoHTMLRegressionTests]
仅临时测试副本将 Bundle(for:) 转为 SwiftPM 的 Bundle.module；断言不变。
"""
import argparse
import json
import pathlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swiftsoup", required=True, type=pathlib.Path)
    parser.add_argument("--package-dir", required=True, type=pathlib.Path)
    parser.add_argument("--filter")
    parser.add_argument("--home-dispatch", action="store_true",
                        help="额外编译真实纯解析分派入口与 jw_home 回归")
    parser.add_argument("--catalog", action="store_true",
                        help="包含 home/拾光桥/三校 fixture/目录与状态契约（供线上 macOS CI）")
    args = parser.parse_args()
    if args.catalog:
        args.home_dispatch = True
    soup = args.swiftsoup.resolve()
    package = args.package_dir.resolve()
    if not (soup / "Package.swift").is_file():
        parser.error("--swiftsoup 必须指向真实 SwiftSoup package")
    owner = package / ".kingo-integration-owner"
    if package.exists():
        if not owner.is_file() or owner.read_text() != str(ROOT):
            parser.error("拒绝覆盖非本脚本、非当前工作树的 package")
    else:
        package.mkdir(parents=True)
        owner.write_text(str(ROOT))
    sources = package / "Sources/Sleepy"
    tests = package / "Tests/SleepyTests"
    sources.mkdir(parents=True, exist_ok=True)
    tests.mkdir(parents=True, exist_ok=True)
    jw = ROOT / "Sleepy/data/jw"
    files = set(jw.glob("*Parser*.swift"))
    files.update(jw / name for name in [
        "Eams5PathPrefix.swift", "JwCourse.swift", "JwParity.swift",
        "JwProtocol.swift", "JwSchoolInfo.swift", "JwParseDiagnostics.swift",
        "JwQzVariants.swift", "JwThuparser.swift",
        "JwSgAssetBridge.swift", "JwClassicEamsFetch.swift", "JwImportDraft.swift",
    ])
    files.add(ROOT / "Sleepy/ui/screen/imports/JwWebViewFrameCapture.swift")
    for file in sorted(files):
        shutil.copy2(file, sources / file.name)
    if args.home_dispatch:
        vm = (jw / "JwImportViewModel.swift").read_text()
        start = vm.index("    static func parseHtml(")
        end = vm.index("    /// 未知协议时,尝试所有 parser", start)
        dispatch = vm[vm.index("enum JwParseDispatch {"):]
        # 只去掉依赖 UI/DB 的 VM 外壳；两个完整纯函数和分派 enum 保持生产字节。
        (sources / "ProductionParseDispatch.swift").write_text(
            "import Foundation\nenum JwImportViewModel {\n" + vm[start:end] + "}\n" + dispatch)
    compatibility = sources / "StandaloneNwpuKeyCompatibility.swift"
    # 清除本脚本旧版在专属包生成的适配；生产 NWPU 已修复，必须原样编译。
    if compatibility.exists():
        compatibility.unlink()
    names = ["JwKingoHTMLRegressionTests", "JwKingoZxParserTests", "JwWakeUpCompatParserTests",
             "JwNwpuPostParserRegressionTests"]
    if args.home_dispatch:
        names.append("JwHomeDispatchRegressionTests")
    if args.catalog:
        names.extend(["JwSgAssetParserTests", "JwSgAssetBridgeTests", "JwCatalogMigrationTests",
                      "JwClassicEamsRegressionTests", "JwSchoolStatusRegressionTests"])
    # 同一个专属包切换开关时不遗留上一次的可选测试/分派代码。
    for name in ["JwHomeDispatchRegressionTests", "JwSgAssetParserTests", "JwSgAssetBridgeTests",
                 "JwCatalogMigrationTests", "JwClassicEamsRegressionTests", "JwSchoolStatusRegressionTests"]:
        stale = tests / f"{name}.swift"
        if name not in names and stale.exists():
            stale.unlink()
    if not args.home_dispatch:
        (sources / "ProductionParseDispatch.swift").unlink(missing_ok=True)
    for name in names:
        text = (ROOT / f"SleepyTests/{name}.swift").read_text()
        if name in ("JwKingoZxParserTests", "JwHomeDispatchRegressionTests",
                    "JwCatalogMigrationTests", "JwClassicEamsRegressionTests"):
            original = f"Bundle(for: {name}.self)"
            assert text.count(original) == 1
            text = text.replace(original, "Bundle.module")
        (tests / f"{name}.swift").write_text(text)
    resources = tests / "resources"
    resources.mkdir(exist_ok=True)
    shutil.copy2(ROOT / "SleepyTests/resources/kingo_zx_sample.html", resources)
    if args.catalog:
        shutil.copytree(ROOT / "SleepyTests/resources/classic_eams", resources / "classic_eams", dirs_exist_ok=True)
        shutil.copytree(ROOT / "Sleepy/resources/third_party", tests / "third_party", dirs_exist_ok=True)
        shutil.copy2(ROOT / "Sleepy/resources/schools.json", tests)
        shutil.copy2(ROOT / "docs/catalog-v1063-candidates.json", tests)
    resource_declarations = ['.copy("resources")']
    if args.catalog:
        resource_declarations.extend(['.copy("third_party")', '.copy("schools.json")',
                                      '.copy("catalog-v1063-candidates.json")'])
    (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "KingoIntegration", platforms: [.macOS(.v13)],
    dependencies: [.package(path: SOUP_PATH)],
    targets: [
        .target(name: "Sleepy", dependencies: [.product(name: "SwiftSoup", package: "SwiftSoup")]),
        .testTarget(name: "SleepyTests", dependencies: ["Sleepy"], resources: [RESOURCE_DECLARATIONS])
    ])
'''.replace("SOUP_PATH", json.dumps(str(soup))).replace("RESOURCE_DECLARATIONS", ", ".join(resource_declarations)))
    command = ["nice", "-n", "15", "swift", "test", "--package-path", str(package),
               "--build-system", "native", "-j", "1", "-Xswiftc", "-j1"]
    if args.filter:
        command.extend(["--filter", args.filter])
    print("执行：", " ".join(command), flush=True)
    return subprocess.run(command, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
