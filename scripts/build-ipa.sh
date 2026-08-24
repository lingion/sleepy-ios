#!/bin/bash
# build-ipa.sh — 无签名 IPA 构建(AltStore 免费账号重签用)
# 用法: ./scripts/build-ipa.sh [configuration] → build/Sleepy-unsigned.ipa
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-Release}"
SCHEME="Sleepy"
DERIVED="build/derived"
EXPORT_DIR="build/export"
IPA="build/Sleepy-unsigned.ipa"

echo "▸ xcodegen generate"
xcodegen generate

echo "▸ xcodebuild archive (unsigned)"
mkdir -p "$DERIVED" "$EXPORT_DIR"
rm -rf "$EXPORT_DIR/Sleepy.xcarchive"
xcodebuild archive \
  -project Sleepy.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "$EXPORT_DIR/Sleepy.xcarchive" \
  CODE_SIGNING_ALLOWED=NO \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  | xcbeautify 2>/dev/null || xcodebuild archive \
  -project Sleepy.xcodeproj -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "$EXPORT_DIR/Sleepy.xcarchive" CODE_SIGNING_ALLOWED=NO

echo "▸ 打包 IPA"
APP=$(find "$EXPORT_DIR/Sleepy.xcarchive" -name "*.app" -maxdepth 4 -type d | head -1)
if [ -z "$APP" ]; then echo "✗ 未找到 .app"; exit 1; fi
rm -rf "$EXPORT_DIR/Payload" "$IPA"
mkdir -p "$EXPORT_DIR/Payload"
cp -R "$APP" "$EXPORT_DIR/Payload/"
(cd "$EXPORT_DIR" && zip -qry "$(pwd)/../../$(basename "$IPA" .ipa)" Payload 2>/dev/null || zip -qry ../Sleepy-unsigned.ipa Payload)
# 上面 zip 目标混乱风险,简化:统一在项目根 zip
rm -f "$IPA"
(cd "$EXPORT_DIR" && zip -qry "$OLDPWD/$IPA" Payload)
echo "✓ $IPA"
ls -lh "$IPA"
