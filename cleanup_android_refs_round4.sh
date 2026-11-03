#!/bin/bash
# 第四轮：清理 PlatformParityNotes.swift 和其他特殊文件中的 Android 引用

set -e

WORKTREE_DIR="/Users/kerrylee/sleepy-ios/.worktrees/remove-android-refs"
cd "$WORKTREE_DIR"

echo "🔍 开始第四轮清理（平台对等性说明）..."

# 1. 处理 PlatformParityNotes.swift 中的 "Android:" 开头的说明
sed -i '' \
  -e 's/Android:/原平台:/g' \
  -e 's/Android 用窗口级/原平台用窗口级/g' \
  -e 's/Android MainActivity/原 MainActivity/g' \
  -e 's/Android 需要显式禁用/原平台需要显式禁用/g' \
  -e 's/Android 侧/原平台侧/g' \
  -e 's/Android 25c943f0/原版本 commit/g' \
  "./Sleepy/util/PlatformParityNotes.swift"

# 2. 处理 AppPrefs.swift 中的 "← AppPrefs.KEY Android" 模式
sed -i '' \
  -e 's/← AppPrefs\.KEY_[A-Z_]* Android/← 原 AppPrefs.KEY/g' \
  -e 's/← Android b0f8280/← 原版本/g' \
  -e 's/(Android 读侧不钳制)/(原实现读侧不钳制)/g' \
  "./Sleepy/util/AppPrefs.swift" 2>/dev/null || true

# 3. 处理 ConflictLayoutEngine.swift 中的 commit 引用
sed -i '' \
  -e 's/← Android 25c943f0/← 原版本 commit/g' \
  "./Sleepy/util/ConflictLayoutEngine.swift" 2>/dev/null || true

# 4. 全局再扫一遍，处理任何 "Android <7位hex>" 格式的 commit 引用
find . -type f \( -name "*.swift" -o -name "*.md" -o -name "*.txt" \) \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/Android [0-9a-f]\{7\}/原版本 commit/g' \
    {} \;

# 5. 处理任何 "Android XXX.kt" 格式的文件引用
find . -type f \( -name "*.swift" -o -name "*.md" -o -name "*.txt" \) \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/Android [A-Za-z]*\.kt/原文件/g' \
    {} \;

echo "✅ 第四轮清理完成"

# 最终统计
REMAINING=$(grep -r "Android" --include="*.swift" --include="*.md" --include="*.txt" --include="*.html" \
  --exclude-dir=".dd" --exclude-dir="SourcePackages" --exclude-dir=".build" . 2>/dev/null | wc -l || echo "0")

echo ""
echo "🎯 最终结果："
echo "   剩余 Android 引用: $REMAINING 处"
echo ""

if [[ $REMAINING -gt 0 ]]; then
  echo "📋 剩余引用（如有）："
  grep -rn "Android" --include="*.swift" --include="*.md" --include="*.txt" --include="*.html" \
    --exclude-dir=".dd" --exclude-dir="SourcePackages" --exclude-dir=".build" . 2>/dev/null | head -20 || true
else
  echo "🎉 完美！所有 Android 引用已清理完毕！"
fi

echo ""
