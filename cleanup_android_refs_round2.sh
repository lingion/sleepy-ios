#!/bin/bash
# 第二轮清理：处理残留的 Android 引用
# 针对特殊场景和上下文

set -e

WORKTREE_DIR="/Users/kerrylee/sleepy-ios/.worktrees/remove-android-refs"
cd "$WORKTREE_DIR"

echo "🔍 开始第二轮清理..."

# 处理 "与 Android" 开头的句子
find . -type f \( -name "*.swift" -o -name "*.md" -o -name "*.txt" \) \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/与 Android 一致/与原实现一致/g' \
    -e 's/与 Android 分叉/与原实现分叉/g' \
    -e 's/与 Android 的差异/与原实现的差异/g' \
    -e 's/对齐 Android/对齐原实现/g' \
    -e 's/Android→iOS→原版本/原版本→iOS→原版本/g' \
    -e 's/iOS→Android/iOS→原版本/g' \
    {} \;

# 处理 "Android 语义" 这类表述
find . -type f \( -name "*.swift" -o -name "*.md" -o -name "*.txt" \) \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/Android 语义/原语义/g' \
    -e 's/Android DEFAULT/原 DEFAULT/g' \
    -e 's/Android check/原 check/g' \
    -e 's/Android 同路径/原同路径/g' \
    -e 's/Android 实断言/原实断言/g' \
    -e 's/Android 6 位分支/原 6 位分支/g' \
    -e 's/Android 不/原实现不/g' \
    {} \;

# 处理测试函数名中的 Android
find . -type f -name "*.swift" \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/MatchesAndroidBaseline/MatchesOriginalBaseline/g' \
    -e 's/MatchesAndroid/MatchesOriginal/g' \
    -e 's/PinnedToAndroid/PinnedToOriginal/g' \
    -e 's/testAndroid/testOriginal/g' \
    {} \;

# 处理文档/注释中的 "Android 版本" "AndroidViewModel" 等
find . -type f \( -name "*.swift" -o -name "*.md" -o -name "*.txt" \) \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/AndroidViewModel/原 ViewModel/g' \
    -e 's/Android 期望/原期望/g' \
    -e 's/iOS 侧无对应 Android/iOS 特有实现/g' \
    -e 's/无对应 Android/iOS 特有/g' \
    {} \;

# 处理 "与 Kotlin" 这样的引用（保留 Kotlin，但如果前面有 Android 上下文则改写）
find . -type f -name "*.swift" \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/语义与 Kotlin/语义与原实现/g' \
    {} \;

# 处理 sample 文件中的 Android 标记（如果是注释）
find . -type f -name "*.html" -o -name "*.sample.*" \
  ! -path "*/.dd/*" ! -path "*/SourcePackages/*" ! -path "*/.build/*" \
  -exec sed -i '' \
    -e 's/— 与 Android/— 与原版本/g' \
    {} \; 2>/dev/null || true

# 统计剩余
REMAINING=$(grep -r "Android" --include="*.swift" --include="*.md" --include="*.txt" \
  --exclude-dir=".dd" --exclude-dir="SourcePackages" --exclude-dir=".build" . 2>/dev/null | wc -l || echo "0")

echo ""
echo "📈 第二轮清理结果："
echo "   剩余 Android 引用: $REMAINING 处"
echo ""

if [[ $REMAINING -gt 0 ]]; then
  echo "⚠️  仍有引用残留，列出全部："
  grep -rn "Android" --include="*.swift" --include="*.md" --include="*.txt" \
    --exclude-dir=".dd" --exclude-dir="SourcePackages" --exclude-dir=".build" . 2>/dev/null
fi

echo ""
echo "✨ 第二轮清理完毕"
