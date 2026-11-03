#!/bin/bash
# 最终轮：精确清理测试和注释，保留第三方仓库名

set -e

WORKTREE_DIR="/Users/kerrylee/sleepy-ios/.worktrees/remove-android-refs"
cd "$WORKTREE_DIR"

echo "🔍 开始最终轮清理..."

# 1. 处理测试文件标题注释中的 "移植 Android"
find ./SleepyTests -type f -name "*.swift" \
  -exec sed -i '' \
    -e 's/移植 Android$/移植自原版本/g' \
    -e 's/— 1:1 移植 Android$/— 1:1 移植自原版本/g' \
    {} \;

# 2. 处理测试中的 "回灌 Android 后" 这样的描述
find ./SleepyTests -type f -name "*.swift" \
  -exec sed -i '' \
    -e 's/回灌 Android 后/回灌原平台后/g' \
    -e 's/Android→iOS→原版本/原版本→iOS→原版本/g' \
    -e 's/与 Android sorted/与原 sorted/g' \
    {} \;

# 3. 处理测试函数名
find ./SleepyTests -type f -name "*.swift" \
  -exec sed -i '' \
    -e 's/MatchAndroidProtocol/MatchOriginalProtocol/g' \
    -e 's/AlignAndroid/AlignOriginal/g' \
    -e 's/AndCapMatchAndroid/AndCapMatchOriginal/g' \
    {} \;

# 4. 处理注释中的 "(Android 无 0→1 哨兵)" 这样的说明
find ./SleepyTests -type f -name "*.swift" \
  -exec sed -i '' \
    -e 's/(Android 无 0→1 哨兵)/(原实现无 0→1 哨兵)/g' \
    -e 's/在 Android$/在原平台/g' \
    -e 's/(对应 Android$/(对应原实现/g' \
    {} \;

# 5. 处理 UI 组件注释
find ./Sleepy/ui -type f -name "*.swift" \
  -exec sed -i '' \
    -e 's/Android getOrDefault/原 getOrDefault/g' \
    -e 's/(int)(255\*v\+0\.5) = 原版本/(int)(255*v+0.5) = 原实现/g' \
    -e 's/Android ExportItem/原 ExportItem/g' \
    -e 's/(= Android$/(= 原实现/g' \
    -e 's/Android 独占暂缓/原平台独占暂缓/g' \
    -e 's/Android 用自由文本/原实现用自由文本/g' \
    -e 's/与 Android 校验路径/与原实现校验路径/g' \
    -e 's/等价 Android 的/等价原实现的/g' \
    -e 's/iOS 惯用 chevron, Android 用 ArrowBack/iOS 惯用 chevron, 原平台用 ArrowBack/g' \
    {} \;

# 6. 处理 PhoneAndroid 图标名（这是 Material Design 图标名，保留）但改注释
find ./Sleepy/ui -type f -name "*.swift" \
  -exec sed -i '' \
    -e 's/PhoneAndroid$/PhoneMobile/g' \
    -e 's/→ PhoneAndroid$/→ PhoneMobile/g' \
    {} \;

# 7. 处理 Reminder 相关注释
find ./Sleepy/ui -type f -name "*.swift" \
  -exec sed -i '' \
    -e 's/= Android$/= 原实现/g' \
    {} \;

# 8. License 列表保留不动（第三方仓库名）
# 这些是引用第三方开源项目的列表，不应该修改

echo "✅ 最终轮清理完成"

# 最终统计（排除 License 列表和 User-Agent）
REMAINING=$(grep -r "Android" --include="*.swift" --include="*.md" --include="*.txt" \
  --exclude-dir=".dd" --exclude-dir="SourcePackages" --exclude-dir=".build" . 2>/dev/null | \
  grep -v "desktopUserAgent.contains" | \
  grep -v "LicenseScreen.swift.*Android" | \
  wc -l || echo "0")

echo ""
echo "🏁 清理完成"
echo "   剩余 Android 引用: $REMAINING 处"
echo "   (不含 User-Agent 测试和第三方许可证列表)"
echo ""

if [[ $REMAINING -gt 0 ]] && [[ $REMAINING -lt 10 ]]; then
  echo "📋 剩余引用："
  grep -rn "Android" --include="*.swift" --include="*.md" --include="*.txt" \
    --exclude-dir=".dd" --exclude-dir="SourcePackages" --exclude-dir=".build" . 2>/dev/null | \
    grep -v "desktopUserAgent.contains" | \
    grep -v "LicenseScreen.swift" || true
fi

echo ""
