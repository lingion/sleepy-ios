#!/bin/bash
# 第七轮：处理 UI 尺寸和样式注释中的 Android 引用

set -e

WORKTREE_DIR="/Users/kerrylee/sleepy-ios/.worktrees/remove-android-refs"
cd "$WORKTREE_DIR"

echo "🔍 开始第七轮清理（UI 尺寸注释）..."

# 1. 处理 "← Android XXX 14" "← Android Icon 24dp" 这样的尺寸注释
find . -type f -name "*.swift" \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/← Android Snackbar/← 原 Snackbar/g' \
    -e 's/← Android Icon/← 原 Icon/g' \
    -e 's/← Android Icon 默认/← 原 Icon 默认/g' \
    {} \;

# 2. 处理 "镜像 Android" "基准高沿用 Android" 这样的描述
find . -type f -name "*.swift" \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/镜像 Android/镜像原实现/g' \
    -e 's/基准高沿用 Android/基准高沿用原实现/g' \
    -e 's/沿用 Android/沿用原实现/g' \
    {} \;

# 3. 处理 "(Android (colW−8)*density px 同式)" 这样的公式注释
find . -type f -name "*.swift" \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/(Android (/(原 (/g' \
    -e 's/ (Android / (原 /g' \
    {} \;

# 4. 处理 "即 Android" 这样的表述
find . -type f -name "*.swift" \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/即 Android$/即原实现/g' \
    -e 's/即 Android /即原实现 /g' \
    {} \;

# 5. 处理 "AndroidBeforeClassDataSource" 这样的类名引用
find . -type f -name "*.swift" \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/AndroidBeforeClassDataSource/原BeforeClassDataSource/g' \
    {} \;

# 6. 再次处理 AppPrefs.swift（如果上一轮没处理干净）
if [[ -f "./Sleepy/util/AppPrefs.swift" ]]; then
  sed -i '' \
    -e 's/Android 读侧不钳制/原实现读侧不钳制/g' \
    "./Sleepy/util/AppPrefs.swift"
fi

echo "✅ 第七轮清理完成"

# 最终统计
REMAINING=$(grep -r "Android" --include="*.swift" --include="*.md" --include="*.txt" \
  --exclude-dir=".dd" --exclude-dir="SourcePackages" --exclude-dir=".build" . 2>/dev/null | \
  grep -v "desktopUserAgent.contains" | wc -l || echo "0")

echo ""
echo "🏁 最终统计："
echo "   剩余 Android 引用: $REMAINING 处"
echo ""

if [[ $REMAINING -gt 0 ]]; then
  echo "📋 剩余引用："
  grep -rn "Android" --include="*.swift" --include="*.md" --include="*.txt" \
    --exclude-dir=".dd" --exclude-dir="SourcePackages" --exclude-dir=".build" . 2>/dev/null | \
    grep -v "desktopUserAgent.contains"
  echo ""
else
  echo "🎉 清理完成！除 User-Agent 字符串测试外，所有 Android 引用已清理！"
fi

echo ""
