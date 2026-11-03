#!/bin/bash
# 批量清理 Android 引用脚本
# App Store 审核要求删除所有 Android 相关文本

set -e

WORKTREE_DIR="/Users/kerrylee/sleepy-ios/.worktrees/remove-android-refs"
cd "$WORKTREE_DIR"

echo "🔍 开始清理 Android 引用..."

# 查找所有需要处理的文件（排除特定目录）
find . -type f \( -name "*.swift" -o -name "*.md" -o -name "*.txt" \) \
  ! -path "*/.dd/*" \
  ! -path "*/SourcePackages/*" \
  ! -path "*/.build/*" \
  > /tmp/files_to_process.txt

echo "📊 找到 $(wc -l < /tmp/files_to_process.txt) 个文件待处理"

# 对每个文件应用替换规则
while IFS= read -r file; do
  # 跳过二进制文件或空文件
  [[ ! -f "$file" ]] && continue
  
  # 使用 sed 进行替换（macOS 需要 -i '' 语法）
  sed -i '' \
    -e 's/← Android 版本/← 原版本/g' \
    -e 's/← Android version/← original version/g' \
    -e 's/与 Android 一致/与原实现一致/g' \
    -e 's/match Android/match original implementation/g' \
    -e 's/Android 原版本/原版本/g' \
    -e 's/Android original version/original version/g' \
    -e 's/Android original/original version/g' \
    -e 's/移植 Android /移植自原版本 /g' \
    -e 's/ported from Android/ported from original/g' \
    -e 's/port of Android/port of original/g' \
    -e 's/from Android/from original/g' \
    -e 's/Android JwQz\([A-Za-z]*\)Test/原 JwQz\1Test/g' \
    -e 's/Android Jw\([A-Za-z]*\)Test/原 Jw\1Test/g' \
    -e 's/Android \([A-Za-z]*\)Test/原 \1Test/g' \
    -e 's/(← Android /(/g' \
    -e 's/ (← Android)//g' \
    -e 's/sleepy Android/原版本/g' \
    -e 's/Sleepy Android/原版本/g' \
    -e 's/Android 版本/原版本/g' \
    -e 's/Android version/original version/g' \
    -e 's/Android 实现/原实现/g' \
    -e 's/Android implementation/original implementation/g' \
    -e 's/Android 同值/原同值/g' \
    -e 's/Android NotificationManager/原 NotificationManager/g' \
    -e 's/Android `\([^`]*\)`/原 `\1`/g' \
    -e 's/Android 破损/原破损/g' \
    -e 's/Android 用例/原用例/g' \
    -e 's/Android test/original test/g' \
    -e 's/Android isNotBlank/原 isNotBlank/g' \
    -e 's/Android substringBefore/原 substringBefore/g' \
    -e 's/Android \([a-z][a-zA-Z]*\) /原 \1 /g' \
    -e 's/100% port of sleepy Android/移植自原版本/g' \
    "$file"
done < /tmp/files_to_process.txt

echo "✅ 第一轮通用替换完成"

# 特殊处理：删除 llms.txt 中提到 Android 仓库的完整句子
if [[ -f "./llms.txt" ]]; then
  echo "🔧 处理 llms.txt..."
  sed -i '' \
    -e '/Android.*仓库/d' \
    -e '/Android.*repository/d' \
    -e '/https:\/\/github\.com\/.*sleepy-android/d' \
    "./llms.txt"
fi

# 特殊处理：删除 README 中的 Android 链接
if [[ -f "./README.md" ]]; then
  echo "🔧 处理 README.md..."
  sed -i '' \
    -e '/\[.*Android.*\](http/d' \
    -e '/Android.*github\.com/d' \
    "./README.md"
fi

# 清理残留的独立 "Android" 词（在注释中）
while IFS= read -r file; do
  [[ ! -f "$file" ]] && continue
  
  # 只处理注释行中的独立 "Android"
  sed -i '' \
    -e 's|^\([[:space:]]*//.*\)Android\([^A-Za-z]\)|\1原版本\2|g' \
    -e 's|^\([[:space:]]*///.*\)Android\([^A-Za-z]\)|\1原版本\2|g' \
    "$file"
done < /tmp/files_to_process.txt

echo "✅ 第二轮独立词清理完成"

# 统计剩余引用
REMAINING=$(grep -r "Android" --include="*.swift" --include="*.md" --include="*.txt" \
  --exclude-dir=".dd" --exclude-dir="SourcePackages" --exclude-dir=".build" . 2>/dev/null | wc -l || echo "0")

echo ""
echo "📈 清理结果："
echo "   剩余 Android 引用: $REMAINING 处"
echo ""

if [[ $REMAINING -gt 0 ]]; then
  echo "⚠️  仍有引用残留，列出前 20 个："
  grep -rn "Android" --include="*.swift" --include="*.md" --include="*.txt" \
    --exclude-dir=".dd" --exclude-dir="SourcePackages" --exclude-dir=".build" . 2>/dev/null | head -20
fi

# 清理临时文件
rm -f /tmp/files_to_process.txt

echo ""
echo "✨ 清理脚本执行完毕"
