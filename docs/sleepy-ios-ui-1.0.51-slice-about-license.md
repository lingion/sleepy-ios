# Slice — About/License parity

## Comparison

Compared `Sleepy/ui/screen/mine/AboutScreen.swift` and
`Sleepy/ui/screen/mine/LicenseScreen.swift` against original 1.0.51
(`AboutScreen.kt`, `LicenseScreen.kt`) and the 原 locale resources.

## Implemented

### AboutScreen

- **Feedback card** (new): bug icon + title/detail + two trailing actions —
  GitHub Issue (opens `FeedbackComposer.githubIssueUrl` with the
  `bug_report.yml` template and a diagnostic block) and email (opens the
  localized mailto URI; a `canOpenURL` check shows the
  `about_feedback_no_mail_app` snackbar when no mail client is installed).
  Diagnostic = version/build, iOS version, Apple/model, pixel resolution,
  locale, debug flag — the iOS counterpart of the original's
  `FeedbackComposer.Diagnostic` fill.
- **App title**: text-only, 28pt bold (original headlineMedium); the 96pt
  logo block was an iOS-only addition — removed for parity.
- **License entry row**: 原 has no leading icon; the `doc.text` icon
  was removed and the trailing chevron resized 14→20pt to match original implementation's
  20dp ChevronRight.

### LicenseScreen

original 1.0.50/1.0.51 reorganized acknowledgements into two tiers;
iOS carried the old flat 14-entry list. Now ported 1:1:

- 9 foundational (cross-school) cards: title + license meta + usage note,
  not expandable.
- 32 per-school cards: title + expand chevron; expanded shows the
  school's referenced repos line-by-line (usage split on `\n`). Expansion
  state is keyed by card id and survives re-renders, mirroring Kotlin's
  `mutableStateMapOf`.
- Collapsible intro card: collapsed shows section title + note; expanded
  appends the full `about_license_body` text.
- Local section headers for `license_foundational_section` /
  `license_perschool_section`.
- Card geometry follows the original's explicit `LicenseCard` (padding 16,
  radius 20) rather than the About page's shared 20/24 card.

### Strings

- `about_feedback_*` (7 keys) + `license_foundational_section` /
  `license_perschool_section` added to all five locales, values pulled
  mechanically from the 原 baseline XML.
- `about_license_body` updated in all five locales to the 1.0.51 two-tier
  attribution text (was the stale GPL paragraph).
- en `about_license_detail` / `license_page_title` spelling aligned to
  Android ("Acknowledgements").

## Known gap (documented, not shipped)

original 1.0.51 About also carries an **update-check toggle** card and the
**"new version available" top banner**. Both are driven by an
`UpdateNotifier` (launch-time GitHub check, cached state flow, preference
`updateCheckEnabled`, cache clear on disable). That is behavior/preference
layer — a new stored preference plus a network check at cold start — which
the matrix excludes ("Parser, DAO, repository, widget, and
preference-default changes are outside this matrix"). Same precedent as
the sleepy-v1 export gap: documented here rather than shipped as a
half-working UI row; `about_update_check*` / `about_update_available`
strings intentionally not added while no row uses them.

## Verification

- `xcodebuild -scheme Sleepy -destination 'generic/platform=iOS' build`
  -> ** BUILD SUCCEEDED **
- `rg -n 'onTapGesture|TODO|FIXME' Sleepy/ui` -> 0 hits
- `git diff --check` -> clean
- Strings staged line-filtered (59 changed lines keyed to slice keys);
  pre-existing uncommitted strings work (AddCourse conflict/weeks,
  `settings_start_view`) stays uncommitted (83 lines dropped from the
  staging patch, still in the worktree).

## Scope

Files touched:

- `Sleepy/ui/screen/mine/AboutScreen.swift`
- `Sleepy/ui/screen/mine/LicenseScreen.swift`
- 5 × `Sleepy/resources/*.lproj/Localizable.strings`

No parser, DAO, repository, widget, or preference-default changes.
Existing unrelated dirty work remains in the worktree, untouched.
