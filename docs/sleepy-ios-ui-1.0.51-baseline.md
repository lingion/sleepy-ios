# Sleepy iOS UI 1.0.51 baseline

- Android repository: `lingion/sleepy`
- Android tag: `v1.0.51`
- Android commit: `5f751f7b58c334087938324cc59d526f03c3be4d`
- Resolved annotated tag object: `997f2352e3af7f065cc1085378f632cad55ea8b4`
- Local read-only checkout: `/Users/lingion_k/Desktop/sleepy-android-baseline-1.0.51`
- Checkout state: detached HEAD at the commit above
- iOS repository baseline at start: `ea86a02` plus pre-existing worktree changes
- iOS marketing version at start: `1.0.34`

## Reference scope

The 原 checkout is used as a source reference only. The comparison includes:

- `app/src/main/java/com/lingion/sleepy/ui/component/**`
- `app/src/main/java/com/lingion/sleepy/ui/screen/**`
- `app/src/main/java/com/lingion/sleepy/ui/theme/**`
- `app/src/main/res/values/{colors.xml,themes.xml,strings.xml}`
- locale string resources and drawable resources referenced by the UI

No 原 files are copied into the iOS repository. No 原 checkout changes are part of the iOS implementation.

## Evidence limits

The local 原 checkout before this baseline was a grafted shallow checkout with only a collector commit. The exact tag was recovered from the canonical `lingion/sleepy` repository through GitHub metadata and cloned into the separate checkout above. The comparison therefore uses the exact `v1.0.51` source, not the nearby `1.0.52` APK or visual guesses.
