#!/usr/bin/env python3
"""将静态校表与城市边界大体积资源压缩为系统原生可解包的 LZMA (.xz) 资产，并裁剪扩展/手表端所需的最小多语言集。"""

import glob
import gzip
import json
import lzma
import os
import re
import shutil
import struct
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Sleepy", "resources")
RES_EXT = os.path.join(ROOT, "Sleepy", "resources-ext")
SRC_RAW = os.path.join(ROOT, "Sleepy", "resources-src")


def write_lzma(raw_bytes: bytes, out_path: str) -> None:
    compressed = lzma.compress(raw_bytes, preset=9 | lzma.PRESET_EXTREME)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(compressed)
    print(f"Packed {os.path.relpath(out_path, ROOT)}: {len(raw_bytes):,} -> {len(compressed):,} bytes")


def build_trimmed_ext_lproj() -> None:
    swift_files = set()
    for root in [
        "SleepyWidget",
        "SleepyWatch",
        "SleepyWatchWidgets",
    ]:
        swift_files.update(glob.glob(os.path.join(ROOT, root, "**", "*.swift"), recursive=True))
    for single in [
        "Sleepy/widget/TodayWidgetView.swift",
        "Sleepy/widget/TwoDayWidgetView.swift",
        "Sleepy/widget/WeekGridWidgetView.swift",
        "Sleepy/widget/WeekGridWideWidgetView.swift",
        "Sleepy/widget/WeekListWidgetView.swift",
        "Sleepy/widget/WeekViewWidgetView.swift",
        "Sleepy/widget/LockScreenCourseWidget.swift",
        "Sleepy/widget/WatchAgendaCore.swift",
        "Sleepy/widget/WatchTimeStripCore.swift",
        "Sleepy/widget/WeekGridWideCore.swift",
        "Sleepy/widget/WidgetContent.swift",
        "Sleepy/widget/WidgetDataLoaders.swift",
        "Sleepy/widget/WidgetVariantInfo.swift",
        "Sleepy/widget/HolidayTransferHelper.swift",
        "Sleepy/widget/notification/NotificationScheduler.swift",
        "Sleepy/util/DateUtils.swift",
        "Sleepy/util/WeekDisplayResolver.swift",
        "Sleepy/util/L10n.swift",
    ]:
        swift_files.add(os.path.join(ROOT, single))

    keys = {
        "tab_schedule",
        "tab_today",
        "tab_mine",
        "today",
        "tomorrow",
        "loading",
        "ok",
        "cancel",
        "course",
        "week",
        "no_course",
        "day_names",
        "week_range",
        "manage_current_table",
        "unit_minutes",
        "unit_periods",
        "course_count_format",
        "course_node_format",
        "course_period_range",
        "course_field_teacher",
        "course_field_room",
        "course_field_note",
        "course_field_week",
        "semester_not_started",
        "semester_ended",
        "date_long_format",
        "month_day_format",
        "today_today",
        "today_no_course",
        "today_rest",
        "schedule_current_week",
        "schedule_no_course_today",
        "schedule_nearest_busy_day",
        "schedule_week_prefix",
        "more_sections",
        "n_course_periods",
        "reminder_before_class_title",
        "reminder_before_minutes_label",
        "reminder_class_dnd_title",
        "reminder_daily_title",
        "agenda_more",
        "agenda_source_count",
        "agenda_table_unknown",
        "agenda_time_unknown",
        "live_activity_title",
        "live_activity_stale",
        "live_activity_starts",
        "live_activity_ends",
        "live_activity_next",
        "live_activity_open_to_refresh",
    }
    for path in sorted(swift_files):
        txt = open(path, encoding="utf-8", errors="ignore").read()
        keys.update(re.findall(r'L10n\.(?:t|format)\(\s*"([^"]+)"', txt))
        for m in re.findall(r'"((?:widget_|watch_|notif_|holiday_)[a-z0-9_]+)"', txt):
            keys.add(m)

    prefixes = (
        "weekday_",
        "day_",
        "month_",
        "array_day_names_",
        "watch_",
        "notif_",
    )

    if os.path.exists(RES_EXT):
        shutil.rmtree(RES_EXT)
    total_raw = 0
    for lang_dir in sorted(glob.glob(os.path.join(RES, "*.lproj"))):
        strings_path = os.path.join(lang_dir, "Localizable.strings")
        if not os.path.exists(strings_path):
            continue
        kept_lines = []
        for line in open(strings_path, encoding="utf-8"):
            m = re.match(r'^\s*"([^"]+)"\s*=', line)
            if m:
                k = m.group(1)
                if k in keys or k.startswith(prefixes):
                    kept_lines.append(line)
        out_dir = os.path.join(RES_EXT, os.path.basename(lang_dir))
        os.makedirs(out_dir, exist_ok=True)
        out_bytes = "".join(kept_lines).encode("utf-8")
        total_raw += len(out_bytes)
        with open(os.path.join(out_dir, "Localizable.strings"), "wb") as f:
            f.write(out_bytes)
    print(f"Generated trimmed resources-ext/*.lproj: total raw strings = {total_raw:,} bytes")


def encode_scb2(raw: bytes) -> bytes:
    """Losslessly re-encode SCB1 big-endian boundaries into SCB2 delta+zigzag varints."""
    pos = 0

    def read_i32() -> int:
        nonlocal pos
        val = struct.unpack_from(">i", raw, pos)[0]
        pos += 4
        return val

    def put_uv(n: int, out: bytearray) -> None:
        while n >= 0x80:
            out.append((n & 0x7F) | 0x80)
            n >>= 7
        out.append(n)

    def put_sv(n: int, out: bytearray) -> None:
        put_uv(((n << 1) ^ (-1 if n < 0 else 0)) & 0xFFFFFFFF, out)

    if read_i32() != 0x53434231:
        raise ValueError("Expected SCB1 header")
    out = bytearray(b"SCB2")
    area_count = read_i32()
    put_uv(area_count, out)
    for _ in range(area_count):
        name_len = read_i32()
        put_uv(name_len, out)
        out.extend(raw[pos : pos + name_len])
        pos += name_len
        poly_count = read_i32()
        put_uv(poly_count, out)
        for _ in range(poly_count):
            ring_count = read_i32()
            put_uv(ring_count, out)
            for _ in range(ring_count):
                pt_count = read_i32()
                put_uv(pt_count, out)
                px = py = 0
                for _ in range(pt_count):
                    x = read_i32()
                    y = read_i32()
                    put_sv(x - px, out)
                    put_sv(y - py, out)
                    px, py = x, y
    if pos != len(raw):
        raise ValueError("Unexpected trailing SCB1 bytes")
    return bytes(out)


def main() -> None:
    # 1. schools.json -> schools.json.lzma (minified JSON)
    with open(os.path.join(RES, "schools.json"), "rb") as f:
        schools_min = json.dumps(
            json.loads(f.read()), ensure_ascii=False, separators=(",", ":")
        ).encode("utf-8")
    write_lzma(schools_min, os.path.join(RES, "schools.json.lzma"))

    # 2. school_cities.json -> SchoolCity/school_cities.json.lzma (only runtime "schools" map; drops dev _cityEvidence/_citySources)
    with open(os.path.join(RES, "SchoolCity", "school_cities.json"), "rb") as f:
        cities_obj = json.loads(f.read())
    cities_runtime = {"schools": cities_obj["schools"]}
    cities_min = json.dumps(cities_runtime, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    write_lzma(cities_min, os.path.join(RES, "SchoolCity", "school_cities.json.lzma"))

    # 3. school_city_boundaries.bin.gz -> SCB2 lossless delta+zigzag varint -> SchoolCity/school_city_boundaries.bin.lzma
    with gzip.open(os.path.join(RES, "SchoolCity", "school_city_boundaries.bin.gz"), "rb") as f:
        boundaries_raw = f.read()
    write_lzma(encode_scb2(boundaries_raw), os.path.join(RES, "SchoolCity", "school_city_boundaries.bin.lzma"))

    # 4. third_party/shiguang -> Sleepy/resources-src/shiguang + third_party/shiguang.pack.lzma
    sg_bundle_dir = os.path.join(RES, "third_party", "shiguang")
    sg_src_dir = os.path.join(SRC_RAW, "shiguang")
    if os.path.exists(os.path.join(sg_bundle_dir, "manifest.json")):
        if os.path.exists(sg_src_dir):
            shutil.rmtree(sg_src_dir)
        os.makedirs(SRC_RAW, exist_ok=True)
        shutil.move(sg_bundle_dir, sg_src_dir)
        os.makedirs(sg_bundle_dir, exist_ok=True)
        shutil.copy2(
            os.path.join(sg_src_dir, "LICENSE-MIT.txt"),
            os.path.join(sg_bundle_dir, "LICENSE-MIT.txt"),
        )

    esbuild = "/Users/lingion_k/freellmapi/node_modules/.bin/esbuild"
    has_esbuild = os.path.exists(esbuild)
    entries = []
    for p in sorted(glob.glob(os.path.join(sg_src_dir, "**", "*"), recursive=True)):
        if os.path.isfile(p):
            rel = "third_party/shiguang/" + os.path.relpath(p, sg_src_dir).replace(os.sep, "/")
            with open(p, "rb") as f:
                body = f.read()
            if p.endswith("manifest.json"):
                manifest_obj = json.loads(body)
                slim_manifest = {
                    "schools": [
                        {
                            "sgName": school["sgName"],
                            **({"sgId": school["sgId"]} if school.get("sgId") is not None else {}),
                            "adapters": [
                                {
                                    k: adapter[k]
                                    for k in ("adapterId", "adapterName", "category", "jsPath", "importUrl")
                                    if k in adapter
                                }
                                for adapter in school.get("adapters", [])
                            ],
                        }
                        for school in manifest_obj.get("schools", [])
                    ]
                }
                body = json.dumps(
                    slim_manifest, ensure_ascii=False, separators=(",", ":")
                ).encode("utf-8")
            elif has_esbuild and p.endswith(".js"):
                proc = subprocess.run(
                    [esbuild, "--loader=js", "--minify-whitespace", "--minify-syntax"],
                    input=body,
                    capture_output=True,
                )
                if proc.returncode == 0 and proc.stdout:
                    body = proc.stdout
            entries.append((rel.encode("utf-8"), body))
    chunks = [b"SGP1", len(entries).to_bytes(4, "little")]
    for rel_b, body_b in entries:
        chunks.append(len(rel_b).to_bytes(2, "little"))
        chunks.append(rel_b)
        chunks.append(len(body_b).to_bytes(4, "little"))
        chunks.append(body_b)
    pack_bytes = b"".join(chunks)
    write_lzma(pack_bytes, os.path.join(RES, "third_party", "shiguang.pack.lzma"))

    # 5. Trim Widget/Watch .lproj bundles
    build_trimmed_ext_lproj()


if __name__ == "__main__":
    main()
