#!/bin/bash
# 第六轮：处理最后的边角情况

set -e

WORKTREE_DIR="/Users/kerrylee/sleepy-ios/.worktrees/remove-android-refs"
cd "$WORKTREE_DIR"

echo "🔍 开始第六轮清理（最后的边角）..."

# 1. 处理 "← Android XXXX" 格式的映射注释
find . -type f -name "*.swift" \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/← Android NOTIFICATION_PERMISSION_REQUIRED/← 原 NOTIFICATION_PERMISSION_REQUIRED/g' \
    -e 's/← Android SETTINGS_REQUIRED/← 原 SETTINGS_REQUIRED/g' \
    -e 's/← Android NOT_SUPPORTED/← 原 NOT_SUPPORTED/g' \
    -e 's/← Android y+=/← 原 y+=/g' \
    -e 's/← Android :/← 原:/g' \
    {} \;

# 2. 处理 "Android 侧现无调用方" 这样的句子
find . -type f -name "*.swift" \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/Android 侧现无调用方/原实现侧现无调用方/g' \
    -e 's/Android 侧/原实现侧/g' \
    {} \;

# 3. 处理 "Android 函数名:行号" 格式的引用
find . -type f -name "*.swift" \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/← Android \([a-zA-Z]*\):\([0-9]*\)/← 原 \1:\2/g' \
    {} \;

# 4. 处理 AppPrefs.swift 中的最后一处
if [[ -f "./Sleepy/util/AppPrefs.swift" ]]; then
  sed -i '' \
    -e 's/(Android 读侧不钳制)/(原实现读侧不钳制)/g' \
    "./Sleepy/util/AppPrefs.swift"
fi

echo "✅ 第六轮清理完成"

# 最终统计（排除 User-Agent 字符串测试）
REMAINING=$(grep -r "Android" --include="*.swift" --include="*.md" --include="*.txt" \
  --exclude-dir=".dd" --exclude-dir="SourcePackages" --exclude-dir=".build" . 2>/dev/null | \
  grep -v "desktopUserAgent.contains" | wc -l || echo "0")

echo ""
echo "🎯 最终清理结果："
echo "   剩余 Android 引用: $REMAINING 处"
echo ""

if [[ $REMAINING -gt 0 ]]; then
  echo "📋 剩余引用列表："
  grep -rn "Android" --include="*.swift" --include="*.md" --include="*.txt" \
    --exclude-dir=".dd" --exclude-dir="SourcePackages" --exclude-dir=".build" . 2>/dev/null | \
    grep -v "desktopUserAgent.contains" || true
  echo ""
  echo "注：User-Agent 字符串测试中的 'Android' 是被测试的字符串内容，非平台引用"
else
  echo "🎉 完美！所有 Android 平台引用已清理完毕！"
  echo "注：User-Agent 测试中的 'Android' 是被测试的字符串字面量，已添加注释说明"
fi

echo ""
