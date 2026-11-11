#!/bin/bash
# build-ipa.sh — 无签名 IPA 构建(AltStore 免费账号重签用)
# 用法: ./scripts/build-ipa.sh [configuration] → build/Sleepy-unsigned.ipa
set -euo pipefail
ipa_repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$ipa_repo_root"

ipa_config="${1:-Release}"
case "$ipa_config" in
  Release|Debug) ;;
  *) echo "Expected Release or Debug configuration" >&2; exit 2 ;;
esac
ipa_export_dir="$ipa_repo_root/build/export"
ipa_archive="$ipa_export_dir/Sleepy.xcarchive"
ipa_file="$ipa_repo_root/build/Sleepy-unsigned.ipa"

echo "▸ xcodegen generate"
xcodegen generate

echo "▸ xcodebuild archive (unsigned)"
mkdir -p "$ipa_export_dir"
rm -rf "$ipa_archive"
xcodebuild archive \
  -project Sleepy.xcodeproj \
  -scheme Sleepy \
  -configuration "$ipa_config" \
  -destination "generic/platform=iOS" \
  -archivePath "$ipa_archive" \
  CODE_SIGNING_ALLOWED=NO \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  2>&1 | tee "$ipa_repo_root/build/ipa-build.log"

echo "▸ 打包 IPA"
ipa_app="$ipa_archive/Products/Applications/Sleepy.app"
if [ ! -d "$ipa_app" ]; then echo "✗ 未找到归档中的 Sleepy.app" >&2; exit 1; fi
rm -rf "$ipa_export_dir/Payload"
rm -f "$ipa_file"
mkdir -p "$ipa_export_dir/Payload"
cp -R "$ipa_app" "$ipa_export_dir/Payload/"
(cd "$ipa_export_dir" && zip -qry "$ipa_file" Payload)
echo "✓ $ipa_file"
ls -lh "$ipa_file"
