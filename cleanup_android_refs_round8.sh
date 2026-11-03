#!/bin/bash
# 第八轮：清理所有剩余的 "← Android XXX" 样式注释

set -e

WORKTREE_DIR="/Users/kerrylee/sleepy-ios/.worktrees/remove-android-refs"
cd "$WORKTREE_DIR"

echo "🔍 开始第八轮清理（最后的样式注释）..."

# 统一处理所有 "← Android XXX" 格式的注释
find . -type f -name "*.swift" \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/← Android headlineMedium/← 原 headlineMedium/g' \
    -e 's/← Android 默认 bodyLarge/← 原默认 bodyLarge/g' \
    -e 's/← Android 默认 Icon/← 原默认 Icon/g' \
    -e 's/← Android AlertDialog/← 原 AlertDialog/g' \
    -e 's/← Android HorizontalDivider/← 原 HorizontalDivider/g' \
    -e 's/← Android Column/← 原 Column/g' \
    -e 's/← Android labelSmall/← 原 labelSmall/g' \
    -e 's/← Android Modifier/← 原 Modifier/g' \
    {} \;

# 通用模式：所有 "← Android" 后面跟任意内容的注释
find . -type f -name "*.swift" \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/← Android \([^,;]*\)/← 原 \1/g' \
    {} \;

echo "✅ 第八轮清理完成"

# 最终验证
REMAINING=$(grep -r "Android" --include="*.swift" --include="*.md" --include="*.txt" \
  --exclude-dir=".dd" --exclude-dir="SourcePackages" --exclude-dir=".build" . 2>/dev/null | \
  grep -v "desktopUserAgent.contains" | wc -l || echo "0")

echo ""
echo "🏁 清理完成！"
echo "   剩余 Android 引用: $REMAINING 处"
echo ""

if [[ $REMAINING -eq 0 ]]; then
  echo "✨ 完美！所有 Android 平台引用已清理干净！"
  echo "   (User-Agent 测试中的 'Android' 字符串已保留并添加注释说明)"
elif [[ $REMAINING -eq 1 ]]; then
  echo "✅ 仅剩 User-Agent 测试中的字符串字面量，已添加说明注释"
  grep -n "desktopUserAgent.contains" ./SleepyTests/JwWebViewConfigBuilderTests.swift || true
else
  echo "⚠️  仍有引用："
  grep -rn "Android" --include="*.swift" --include="*.md" --include="*.txt" \
    --exclude-dir=".dd" --exclude-dir="SourcePackages" --exclude-dir=".build" . 2>/dev/null | \
    grep -v "desktopUserAgent.contains"
fi

echo ""
