#!/bin/bash
# 第三轮：精确处理最后的残留引用

set -e

WORKTREE_DIR="/Users/kerrylee/sleepy-ios/.worktrees/remove-android-refs"
cd "$WORKTREE_DIR"

echo "🔍 开始第三轮精确清理..."

# 1. 处理文件头部的 "Android XXX.kt 1:1 移植" 模式
find . -type f -name "*.swift" \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/Android [A-Za-z]*\.kt 1:1 移植/原版本 1:1 移植/g' \
    {} \;

# 2. 处理 "与 Android Migrations.kt 一一对应"
find . -type f -name "*.swift" \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/与 Android Migrations\.kt 一一对应/与原迁移脚本一一对应/g' \
    -e 's/与 Android [A-Za-z]*\.kt 一一对应/与原实现一一对应/g' \
    {} \;

# 3. 处理 "AndroidLocalCalendarStore.kt" 这样的文件名引用
find . -type f -name "*.swift" \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/AndroidLocalCalendarStore\.kt/原日历存储实现/g' \
    -e 's/AndroidLocalCalendarStore/原日历存储/g' \
    {} \;

# 4. 处理 "← Android" 开头的注释
find . -type f -name "*.swift" \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/← Android:/← 原实现:/g' \
    -e 's/(← Android$/(← 原实现/g' \
    -e 's/(← Android /(← 原实现 /g' \
    {} \;

# 5. 处理 "与 Android" 结尾的注释（断行情况）
find . -type f -name "*.swift" \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/与 Android$/与原实现/g' \
    -e 's/— 与 Android$/— 与原实现/g' \
    {} \;

# 6. 处理 CHANGELOG 中的 "Android 25c943f0" 这样的 commit 引用
if [[ -f "./CHANGELOG.md" ]]; then
  sed -i '' \
    -e 's/Android [0-9a-f]\{7,\}/原版本 commit/g' \
    "./CHANGELOG.md"
fi

# 7. 处理 sample.html 文件（如果需要的话）
find . -type f -name "*.html" \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/— 与 Android/— 与原版本/g' \
    -e 's/与 Android/与原版本/g' \
    {} \; 2>/dev/null || true

echo "✅ 第三轮清理完成"

# 最终统计
REMAINING=$(grep -r "Android" --include="*.swift" --include="*.md" --include="*.txt" --include="*.html" \
  --exclude-dir=".dd" --exclude-dir="SourcePackages" --exclude-dir=".build" . 2>/dev/null | wc -l || echo "0")

echo ""
echo "📊 最终统计："
echo "   剩余 Android 引用: $REMAINING 处"
echo ""

if [[ $REMAINING -gt 0 ]]; then
  echo "📋 剩余引用列表："
  grep -rn "Android" --include="*.swift" --include="*.md" --include="*.txt" --include="*.html" \
    --exclude-dir=".dd" --exclude-dir="SourcePackages" --exclude-dir=".build" . 2>/dev/null || true
else
  echo "🎉 所有 Android 引用已清理完毕！"
fi

echo ""
echo "✨ 清理任务完成"
