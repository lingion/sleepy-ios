# Sleepy iOS — v1.0.60 Replication Recon

## Status as of 2026-10-13

### Branch: `rebuild/align-sleepy-1.0.60` in `~/Desktop/sleepy-ios-wt/align-1.0.60`

### Commits delivered (12 since baseline 63ed008 / v1.0.55)

| hash | summary |
|------|---------|
| 1aefef9 | feat(strings): 补齐 v1.0.60 新增 305 个字符串键 ×5 语言 |
| 29f1c2b | feat(schools): schools.json 对齐 v1.0.60 — 185 → 348 所 (+163) |
| 998bbc4 | feat(data): 对齐 v1.0.60 数据层 — DB v6→v10 + 三张新表 + issue#40 节次表绑定状态机 |
| f0de650 | feat(util): 对齐 v1.0.60 util 层 — 10 个策略/解析文件 + 假期提醒门控 + 周显示解析 |
| 2dfc8e5 | feat(jw): 移植 v1.0.60 12 个教务协议解析器 |
| 95d328a | feat(jw): 移植 v1.0.60 9 个 fetch JS (NEU/NUIT/KUST/YETHAN/CHAOXING/WHUT/EAMS5/EAMS5_AHU/BJTU) + CfNew 协议 |
| 02c9b21 | feat(diag): 移植 v1.0.60 排查诊断层 — frame capture + JS 诊断集 + 会话记录 |
| 4c8bdb0 | feat(diag): 移植 v1.0.60 排查全量包 — JwCaptureDump zip dump + ZIPFoundation |
| a995a31 | chore(replica): 写 v1.0.60 复刻进度卡 — features.csv + recon.md |
| 4006916 | feat(data): 全量迁移包 WIP — Migration* 五件套 + DAO 保留原 ID 直插 |
| ff5d516 | feat(migration): 移植 v1.0.60 .sleepybackup 全量迁移层(构建修复: init 标签/协议提级/CourseDao.insertInDb) |

### Test gate

- xcodebuild build: **SUCCEEDED** (sleepy 1.0.60 baseline)
- SleepyTests: **532/0 (9.201s)** on iPhone 14 Pro simulator (iOS 16.4)

## File-level gap (original v1.0.60 main sources → iOS current)

- **171** original main-source files in v1.0.60 delta (v1.0.55..v1.0.60)
- **85** ported (basename match) — 49.7%
- **86** missing — 50.3%

Full breakdown: `replica/features.csv`

## Missing area distribution (top 15 by count)

| area | missing |
|------|---------|
| widget | 24 |
| notification | 13 |
| mine | 11 |
| jw | 7 |
| imports | 6 |
| component | 6 |
| migration | 5 |
| util | 4 |
| nav | 4 |
| theme | 1 |
| sleepy | 1 |
| schedule | 1 |
| repository | 1 |
| data | 1 |
| calendar | 1 |

## What's covered

- **strings**: full v1.0.60 key set × 5 languages (zh-Hans / zh-Hant / en / es / ja)
- **schools**: 348 supported schools, json sync with v1.0.60
- **data layer**: AppDatabase migrated v6→v10 with new tables (ImportDraft, CalendarImportRecord, PeriodTable, TimeTable)
- **util layer**: 10 strategy/parse files + holiday reminder gating + week display parse
- **jw parsers**: 12 protocol parsers (CF_NEW, CHAOXING, CLASSIC_EAMS, EAMS5, KUST, NEU, NEW_ZF, NUIT, WUKEEP_COMPAT, YETHAN + others)
- **jw fetch JS**: 9 fetch enums + CfNew deep-frame variant + 2 dispatch entries
- **diagnostic**: JwWebViewFrameCapture + JwDiagnosticJs + JwDiagnosticSession
- **capture dump**: JwCaptureDump with ZIPFoundation, 1:1 against Android
- **dep added**: ZIPFoundation 0.9.20 (gh.qdp mirror)

## What's NOT covered (priority-ordered backlog)

### 1. migration/ — 5 files
- MigrationBackup.kt
- MigrationDatabaseCodec.kt
- MigrationExecutor.kt
- MigrationPackageCodec.kt
- MigrationPrefsCodec.kt
**Why high value:** foundational for upgrade-in-place from v1.0.55 to v1.0.60 — without it, users can't carry their courses over.

### 2. jw/ — 7 files (parsers + import-draft)
- JwImportDraft.kt
- JwImportViewModel.kt
- JwParserRegistry.kt
- JwProtocol.kt (constant updates)
- OfflineSchoolCityIndex.kt
- SchoolCityIndex.kt
- SchoolCityLocator.kt
- SchoolLocationLookup.kt
- SchoolLocationPolicy.kt
- school_cities.json (asset)
**Why high value:** JwParserRegistry orchestrates all 12 parsers; SchoolCityIndex drives "nearby schools" feature.

### 3. data/calendar/ — 4 files
- CalendarImportRecordEntity.kt
- CalendarImportRecordDao.kt
- SystemCalendarManager.kt
- CalendarImportDialog.kt
**Why high value:** EventKit integration — students push courses into iOS Calendar.

### 4. data/notification/ — ~6 files
- ClassDndScheduler.kt
- CourseNotificationScheduler.kt
- ReminderRescheduler.kt
- BackgroundReliabilityProbe.kt
- BackgroundReliabilitySnapshot.kt
- BatteryOptimizationIntents.kt
**Why high value:** "上课自动勿扰" + "课程提醒" — feature-promised to students.

### 5. widget/ — 24 files (most under widget/ subpkg)
- Today widgets, schedule cells, compact windows, refresh logic
**Why high value:** widget is the entry point. iOS widget exists but lacks the v1.0.60 polish.

### 6. ui/screen/imports/ — 6 files
- CalendarImportDialog
- DiagDumpProgress
- ExitDraftState
- ImportDraftSheet
- ImportSheet
- (others)
**Why high value:** import flow UI is the primary user journey.

### 7. ui/screen/mine/ — 11 files
- Settings UI
**Why medium value:** settings screens, fewer consumers.

### 8. ui/component/ — 6 files
- CourseDetailSheet, PeriodTableShareSheet, ShareScheduleSheet, etc.
**Why medium value:** shared UI components.

### 9. ui/nav/ — 4 files
- SleepyMaterialTransition, SleepyNavHost, SleepyNavigator, SleepyRoutes
**Why medium value:** navigation graph.

## Constraints observed

- **No push** (release-sop §6 user-approval gate)
- **No Co-Authored-By: Claude** in commit trailers
- **No Fixes:/Closes:/Resolves: #N** in commit messages
- **No brew** anywhere
- **Always gh.qdp.qzz.io** for non-cached remote
- **Author = lingion@hrbeu.edu.cn** on every commit
- **iOS私有不入库,本地保留** — no specs pushed

## Next step

Resume with the highest-value remaining slice. The user's standing goal (`/goal 安装完之后用这个skill 把sleepy 1.0.60 严格复制到sleepy-iOS 已有仓库`) requires 1:1 port of v1.0.60. The pragmatic next slice is **migration/** (5 files, ~640 lines) because it gives users a real upgrade path; the iOS side is currently at v1.0.55 schema.
