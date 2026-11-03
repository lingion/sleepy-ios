#!/bin/bash
# App Store watchOS 截图管线 (2026-10-30 修)
# 教训: 有配对的 watch 设备 install 走 AppConduit 死锁 → 用无配对的 46mm, 完全不碰 iPhone。
# (旧版"关机所有 Booted iPhone"会误杀并行测试的手机, 已改为只关真正配对的那台)
# 授权弹窗已由 WatchStore shotMode 旁路掐掉; 这里再叠一层 simctl privacy 兜底。
set -u
DEV="${SHOT_WATCH:-7BAA7874-12A9-48C3-B693-183604166361}"   # Apple Watch Series 12 (46mm, 无配对)
BUNDLE="com.lingion.sleepy.watch"
APP=$(find ~/sleepy-ios/build/watchsim/Build/Products/Debug-watchsimulator -maxdepth 1 -name "SleepyWatch.app" | head -1)
[ -d "$APP" ] || { echo "找不到 SleepyWatch.app, 先编 -scheme 'Sleepy Watch' -destination 'generic/platform=watchOS Simulator'"; exit 1; }
OUT="${SHOT_OUT:-/tmp/appstore-shots-watch}"
mkdir -p "$OUT"; rm -f "$OUT"/*.png

# 仅当所选设备真有配对 iPhone 时才关它 (防 AppConduit 死锁); 无配对则什么都不关
xcrun simctl list pairs -j | python3 -c "
import json,sys
pairs=json.load(sys.stdin).get('pairs',{})
def uids(o,acc):
    if isinstance(o,dict):
        for k,v in o.items():
            if k.lower()=='udid' and isinstance(v,str): acc.add(v)
            else: uids(v,acc)
    elif isinstance(o,list):
        for i in o: uids(i,acc)
for k,v in pairs.items():
    s=json.dumps(v)
    if '$DEV' in s:
        acc=set(); uids(v,acc); acc.discard('$DEV')
        print('\n'.join(acc)); break
" | while read -r phone; do
  [ -n "$phone" ] && xcrun simctl shutdown "$phone" 2>/dev/null && echo "配对手机 $phone 已关机 (防 AppConduit 死锁)"
done

# 已 Booted 就跳过 boot (旧版 bootstatus -b 对已开机设备会误报失败)
STATE=$(xcrun simctl list devices -j | python3 -c "
import json,sys
for devs in json.load(sys.stdin)['devices'].values():
    for x in devs:
        if x['udid']=='$DEV': print(x['state'])")
if [ "$STATE" != "Booted" ]; then
  xcrun simctl boot "$DEV" 2>/dev/null || true
  xcrun simctl bootstatus "$DEV" -b >/dev/null 2>&1 || { echo "boot 失败 (state=$STATE)"; exit 1; }
fi
xcrun simctl privacy "$DEV" deny notifications 2>/dev/null || true
sleep 3
xcrun simctl install "$DEV" "$APP" || { echo "install 失败"; exit 1; }

shoot() {
  local name="$1" tab="$2"
  xcrun simctl terminate "$DEV" "$BUNDLE" 2>/dev/null
  if ! xcrun simctl launch "$DEV" "$BUNDLE" -SLEEPY_UI_TEST_SEED \
    -AppleLanguages "(${SHOT_LANG:-zh-Hans})" -AppleLocale "${SHOT_LOCALE:-zh_CN}" \
    "-SLEEPY_SHOT_TAB=$tab" >/dev/null 2>&1; then
    echo "shot $name: launch 失败, 重装重试一次"
    xcrun simctl install "$DEV" "$APP" 2>/dev/null || { echo "shot $name: 重装失败"; return 1; }
    xcrun simctl launch "$DEV" "$BUNDLE" -SLEEPY_UI_TEST_SEED \
      -AppleLanguages "(${SHOT_LANG:-zh-Hans})" -AppleLocale "${SHOT_LOCALE:-zh_CN}" \
      "-SLEEPY_SHOT_TAB=$tab" >/dev/null || { echo "shot $name: 仍失败"; return 1; }
  fi
  sleep "${SHOT_SLEEP:-12}"
  xcrun simctl io "$DEV" screenshot "$OUT/$name.png" >/dev/null 2>&1
  local sz; sz=$(stat -f%z "$OUT/$name.png" 2>/dev/null || echo 0)
  # 空白表盘约 9KB, 有内容 25KB+; 低于 15KB 判定没拍到
  if [ "$sz" -lt 15000 ]; then echo "⚠️ $name 疑似空白表盘 ($sz bytes)"; else echo "shot: $name OK ($sz bytes)"; fi
}
shoot watch-today    today
shoot watch-schedule schedule
shoot watch-mine     mine
xcrun simctl terminate "$DEV" "$BUNDLE" 2>/dev/null
ls -la "$OUT"
