# Slice: Import flow — original 1.0.51 UI alignment

Commit `1670e68` · files: SchoolSelectScreen.swift, ImportSheet.swift,
JwImportFlow.swift, JwWebViewLoginScreen.swift, DateTimePickers.swift,
Localizable.strings ×5

## What changed

- SchoolSelectScreen: pinyin hint to M3 supporting-text form (bodySmall 12,
  32/16 inset); empty state bodyLarge 16; school icon to outline
  `graduationcap` (Android Icons.Outlined.School); URL row detected/auto
  lines labelSmall 11 regular.
- ImportSheet: method-row trailing chevron 24dp default; format info icon
  16dp onSurfaceVariant; preview metric/info labels labelSmall 11 **Medium**
  (SleepyTypography labelSmall weight=Medium); dropped-lines title
  titleSmall 14 Medium; conflict list capped at 3 with >3 more-count
  (Android prefix(3)); preview cancel to TextButton form (40dp,
  explicit onSurfaceVariant per original source); confirm dialog title
  headlineSmall 24 regular (M3 AlertDialog title slot), table-name field
  fillMaxWidth and only when import-as-new/append-as-new
  (`showTableName`), back/confirm default TextButton primary labelLarge
  14 Medium — also fixes the confirm label rendered onPrimary (invisible
  on surface).
- JwImportFlow ConfigureConfirm: title headlineSmall 24 regular; field
  order date before table name (Android order); label to
  `jw_table_name_label` (Android key, "课表名称" — was `import_table_name`
  "导入后课表名"); fillMaxWidth on both fields; back/confirm TextButton
  primary labelLarge 40dp.
- JwWebViewLoginScreen: capture-bar import button gains disabled state
  (M3 disabled: container onSurface 12%, content onSurface 38%) when no
  WebView coordinator.
- DateTimePickers: DatePickerField gains `fillsWidth` param mirroring
  原 `fillMaxWidth()` call sites (TimePickerField already had it).
- Localization: new key `jw_table_name_label` in zh-Hans/zh-Hant/en/es/ja
  (values copied from original locales).

## Scope notes (UI-only per user direction)

Behavior-layer import gaps stay out of scope (matrix-excluded, same
treatment as UpdateNotifier / sleepy-v1 export): WebView timeout &
protocol fetch JS, frame-capture retry, DiagMapper diagnostics,
parseResult.warnings section, WHUT/CHAOXING/EAMS5/zf_new fetch JS.

## Verification

- `xcodebuild -scheme Sleepy -destination 'generic/platform=iOS' build`
  → **BUILD SUCCEEDED** (after all slice edits).
- `rg 'onTapGesture|TODO|FIXME' Sleepy/ui Sleepy/theme` → 0 hits;
  `git diff --check` clean.
- Staging preserved the user's pre-existing Localizable.strings lines
  (apply_to_all_slots / settings_start_view blocks) via index-blob
  staging; they remain uncommitted in the worktree.

