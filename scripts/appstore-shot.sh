#!/bin/bash
# shot.sh — headless 模拟器 App Store 截图(simctl launch + io screenshot)
# 前置: 模拟器已 boot + status_bar override 9:41; app 已 install
set -uo pipefail
DEV="${SHOT_DEV:-78B92966-0C7B-4FB7-81CC-F50D7CE4CA7E}"
BUNDLE=com.lingion.sleepy
OUT="${SHOT_OUT:-/tmp/appstore-shots}"
APP=$(find ~/sleepy-ios/build/sim-dd/Build/Products/Debug-iphonesimulator -maxdepth 1 -name "Sleepy.app" | head -1)
rm -rf "$OUT"; mkdir -p "$OUT"
xcrun simctl install "$DEV" "$APP" || exit 1

wait_ready() {
  for i in $(seq 1 24); do
    out=$(xcrun simctl listapps "$DEV" 2>/dev/null | head -c 10)
    [ -n "$out" ] && return 0
    sleep 5
  done
  return 1
}
launch_heal() { # args...; 45s 看门狗, 挂则 reboot 重试, 再挂 erase 重试
  local attempt
  for attempt in 1 2 3; do
    xcrun simctl launch "$DEV" "$BUNDLE" "$@" >/tmp/shot-launch.out 2>&1 &
    local LP=$!; local hung=0
    for i in $(seq 1 9); do sleep 5; kill -0 $LP 2>/dev/null || break; done
    if kill -0 $LP 2>/dev/null; then hung=1; kill $LP 2>/dev/null; wait $LP 2>/dev/null; fi
    [ $hung -eq 0 ] && return 0
    echo "  launch hung (attempt $attempt), healing..." >&2
    if [ $attempt -le 2 ]; then
      xcrun simctl shutdown "$DEV" 2>/dev/null; sleep 4; xcrun simctl boot "$DEV" 2>/dev/null
    else
      xcrun simctl shutdown "$DEV" 2>/dev/null; sleep 3; xcrun simctl erase "$DEV" 2>/dev/null; sleep 3
      xcrun simctl boot "$DEV" 2>/dev/null
      wait_ready
      xcrun simctl install "$DEV" "$APP" 2>/dev/null
    fi
    wait_ready
  done
  return 1
}
shoot() { # name, extra args...
  local name="$1"; shift
  xcrun simctl terminate "$DEV" "$BUNDLE" 2>/dev/null
  launch_heal -SLEEPY_UI_TEST_SEED -AppleLanguages "(${SHOT_LANG:-zh-Hans})" -AppleLocale "${SHOT_LOCALE:-zh_CN}" "$@" || { echo "shot: $name FAILED"; return 1; }
  sleep "${SHOT_SLEEP:-6}"
  xcrun simctl io "$DEV" screenshot "$OUT/$name.png" >/dev/null 2>&1
  echo "shot: $name ($(sips -g pixelWidth -g pixelHeight "$OUT/$name.png" 2>/dev/null | tr '\n' ' '))"
}

shoot 01-week -SLEEPY_SHOT_VIEW=full
shoot 02-grid -SLEEPY_SHOT_VIEW=cards
shoot 03-today -SLEEPY_SHOT_TAB=today
shoot 04-mine -SLEEPY_SHOT_TAB=mine
xcrun simctl terminate "$DEV" "$BUNDLE" 2>/dev/null
ls -la "$OUT"
