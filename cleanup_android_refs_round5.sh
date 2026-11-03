#!/bin/bash
# 第五轮：处理测试文件中的 Android 引用（保留逻辑测试，只改注释）

set -e

WORKTREE_DIR="/Users/kerrylee/sleepy-ios/.worktrees/remove-android-refs"
cd "$WORKTREE_DIR"

echo "🔍 开始第五轮清理（测试文件）..."

# 1. 处理测试注释中的 "Android return@withTransaction" 等表述
find ./SleepyTests -type f -name "*.swift" \
  -exec sed -i '' \
    -e 's/Android return@withTransaction/原 return@withTransaction/g' \
    -e 's/(Android 无此 key)/(原实现无此 key)/g' \
    -e 's/Android 拒绝/原实现拒绝/g' \
    -e 's/Android 接受/原实现接受/g' \
    -e 's/Android org\.json/原 org.json/g' \
    {} \;

# 2. 处理测试函数名中的 "AndroidByteIdentical" 等
find ./SleepyTests -type f -name "*.swift" \
  -exec sed -i '' \
    -e 's/IsAndroidByteIdentical/IsOriginalByteIdentical/g' \
    -e 's/LikeAndroid/LikeOriginal/g' \
    -e 's/skippedLikeOriginal/skipped_原实现同/g' \
    {} \;

# 3. 特殊处理：JwWebViewConfigBuilderTests.swift 中的 User-Agent 测试
# 这个测试的是 desktopUserAgent 不包含 "Android" 字符串，这是实际的逻辑断言
# 我们在注释中说明这是在测试 UA 字符串内容，而不是引用 Android 平台
if [[ -f "./SleepyTests/JwWebViewConfigBuilderTests.swift" ]]; then
  # 在这行前面加上注释说明
  sed -i '' \
    '/XCTAssertFalse(JwWebViewClientBuilder.desktopUserAgent.contains("Android"))/i\
        // 测试桌面 User-Agent 不包含移动平台标识\
' \
    "./SleepyTests/JwWebViewConfigBuilderTests.swift"
fi

echo "✅ 第五轮清理完成"

# 最终统计（排除 User-Agent 测试那行）
REMAINING=$(grep -r "Android" --include="*.swift" --include="*.md" --include="*.txt" \
  --exclude-dir=".dd" --exclude-dir="SourcePackages" --exclude-dir=".build" . 2>/dev/null | \
  grep -v "desktopUserAgent.contains" | wc -l || echo "0")

echo ""
echo "🎯 清理结果："
echo "   剩余 Android 引用: $REMAINING 处"
echo "   (不含 User-Agent 字符串测试)"
echo ""

if [[ $REMAINING -gt 0 ]]; then
  echo "📋 剩余引用："
  grep -rn "Android" --include="*.swift" --include="*.md" --include="*.txt" \
    --exclude-dir=".dd" --exclude-dir="SourcePackages" --exclude-dir=".build" . 2>/dev/null | \
    grep -v "desktopUserAgent.contains" || true
else
  echo "🎉 所有非逻辑性 Android 引用已清理完毕！"
fi

echo ""
