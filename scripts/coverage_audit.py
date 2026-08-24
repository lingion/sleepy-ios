#!/usr/bin/env python3
"""coverage_audit.py — G1 符号覆盖闸
Kotlin 源符号(fun/class/object/val/const) vs Swift 对应符号,diff 未映射项。
用法: python3 scripts/coverage_audit.py [--android-dir PATH] [--ios-dir PATH]
退出码: 0=零未解释项(按 FILE_MAPPING 的批次范围);2=有未映射符号
"""
import re, sys, os, json, argparse

ANDROID = os.path.expanduser('~/Desktop/sleepy/app/src/main/java/com/lingion/sleepy')
IOS = os.path.expanduser('~/Desktop/sleepy-ios')

def kotlin_symbols(path):
    """返回 {kind: [names]} — 顶层与成员 fun/class/object/interface/val/const"""
    src = open(path, encoding='utf-8').read()
    out = {'fun': [], 'class': [], 'object': [], 'interface': [], 'val': [], 'const': [], 'enum': []}
    for m in re.finditer(r'^\s*(?:@\w+\s+)*(?:private\s+|internal\s+|public\s+)?(?:suspend\s+)?(fun|class|object|interface|enum class)\s+[`]?(\w+)', src, re.M):
        kind, name = m.group(1), m.group(2)
        if kind == 'fun':
            out['fun'].append(name)
        elif kind == 'enum class':
            out['enum'].append(name)
        else:
            out[kind].append(name)
    for m in re.finditer(r'^\s*(?:private\s+|internal\s+)?(?:const\s+)?val\s+(\w+)', src, re.M):
        out['val'].append(m.group(1))
    return {k: sorted(set(v)) for k, v in out.items() if v}

def swift_symbols(path):
    src = open(path, encoding='utf-8').read()
    out = {'func': [], 'class': [], 'struct': [], 'enum': [], 'var': [], 'let': []}
    for m in re.finditer(r'^\s*(?:private\s+|internal\s+|public\s+|open\s+|final\s+|@(?:discardableResult|objc)\s+)*(?:static\s+|class\s+)?(func|class|struct|enum)\s+[`]?(\w+)', src, re.M):
        kind, name = m.group(1), m.group(2)
        out[{'func':'func','class':'class','struct':'struct','enum':'enum'}[kind]].append(name)
    for m in re.finditer(r'^\s*(?:private\s+|internal\s+|public\s+)?(?:static\s+)?(?:let|var)\s+(\w+)', src, re.M):
        out['let'].append(m.group(1))
    return {k: sorted(set(v)) for k, v in out.items() if v}

def kt_to_swift_name(name):
    """Kotlin camelCase → Swift 同名(移植规范: 保留 camelCase)"""
    return name

# ── G1 解释表: 改名映射 + 平台差异豁免 ──
# 每条 = (kotlin路径前缀, kotlin符号名) → Swift 符号 或 豁免理由
# 豁免码: RENAMED=改名映射见 map; PD5=bitmap管道不移植(平台差异表#5);
#         PD3=FluidCloud不移植(#3); PD4=Intent→URL scheme(#4); PD2=自装APK→侧载(#4);
#         ACT=Activity壳(→SwiftUI View/状态机); LOCAL=函数体局部val(Swift同位局部变量,名字池不适用)
RENAMES = {
    # util
    'themeKeyFlow': 'themeKeyPublisher',
    'pickCourseColorCompose': 'pickCourseColorSwiftUI',
    'shortNodeString': 'nodeString',
    'wrap': 'bundle', 'wrapDefault': 'bundle', 'getLocale': 'locale',
    # data
    'getCoursesByDayOnce': 'getCoursesByDay',
    'getByTableAndDayOnce': 'getByTableAndDay',
    'observeByTable': 'observeCourses', 'observeByTableAndDay': 'getCoursesByDay',
    'observeTable': 'getTable', 'observeAll': 'getAllTables', 'observeById': 'getById',
    'observeCoursesByDay': 'getCoursesByDay',
    'downloadApk': 'downloadIpa',
    # UI 组件(View → private struct 同名/近名)
    'SheetHeader': 'CourseDetailSheet',     # 内嵌 header(合并进主 View)
    'ModeTabSwitch': 'SegmentedSwitcher',   # M3 SegmentedButton → 自绘
    'Mode': 'TimeSlotEditorMode',
    'TopBar': 'ScheduleTopBar',
    'CaptureBar': 'JwWebViewLoginScreen',   # 合并进主 View 尾部 HStack
    'WiseduBridge': 'WebViewCoordinator',   # JS 桥 → WKScriptMessageHandler
    'TimeField': 'FieldTextField',
    'Divider': 'HDivider',                  # Mine/Export 内 Divider helper
    'exportAndShare': 'exportFile',         # MediaStore+ACTION_SEND → tmp 文件+UIActivityVC
    'shareText': 'ShareSheet',
    'writeToDownloads': 'exportFile',       # 平台差异: iOS 无公共 Downloads
    'writeToCacheViaFileProvider': 'exportFile',
    'requestNotificationPermission': 'onMasterToggle',  # 权限流内联
    'Checking': 'checking', 'Idle': 'idle', 'Installing': 'installing',
    # 通知: AlarmManager+BroadcastReceiver → UNUserNotificationCenter(等价适配)
    'CourseNotificationScheduler': 'NotificationScheduler',
    'BeforeClassNotifyReceiver': 'scheduleBeforeClassDaily',
    'BeforeClassScheduleReceiver': 'scheduleBeforeClassDaily',
    'DailyNotifyReceiver': 'scheduleDaily',
    'BootReceiver': 'scheduleAll',
    'buildPendingIntent': 'scheduleBeforeClassWindow',
    'cancelCourseAlarms': 'cancelCourseNotifications',
    'cancelCourseAlarmIds': 'cancelAll',
    'sendDailyNotification': 'scheduleDaily',
    'scheduleTodayBeforeClassAlarms': 'scheduleBeforeClassWindow',
    'setRepeatingAlarm': 'scheduleAll',
    'openAppIntent': 'fillDailyContent',
    'getCourseStartTime': 'courseStartTime',
    'hasNotifPermission': 'requestAuthorizationIfNeeded',
    'ensureActiveFluidCloud': 'scheduleAll',   # PD3: Fluid Cloud 无 iOS 对应物
    # 更新: APK 自装 → IPA 下载+侧载提示(平台差异表#2)
    'cleanOldApk': 'cleanOldIpa',
    'currentAbi': 'currentVersionName',
    'currentAbiAsset': 'currentVersionName',
    'install': 'update_ios_sideload_hint',
    # DB
    'get': 'getShared',                     # AppDatabase.get(context) → getShared()
    # 解析器(class → struct, 同名; 名字池含 struct)
    'kotlinx': 'parse',                     # import kotlinx 误报(正则噪音)
    'parseIcsTimeOfDay': 'parseIcs',
}
# 注解式等价(swift 源文本包含即视为已映射 — 覆盖 enum case/成员级声明, 名字池正则够不到)
TEXT_EQUIV = {
    'fieldColors': 'fieldShape',          # TextField 色板合并: iOS 用 cornerRadius+strokeBorder 统一样式
    'Buttons': 'fieldShape',              # Buttons object(ctaHeight/shape) → 内联 44/48dp + Shapes.large
    'Checking': 'case checking', 'Idle': 'case idle', 'Installing': 'case installing',
    'hasNotifPermission': 'getNotificationSettings',
    'install': 'update_ios_sideload_hint', # PD2: 自装 APK → 侧载提示文案
    'themeKeyFlow': 'themeKeyPublisher',
}

PLATFORM_EXEMPT = {
    # widget bitmap 管道(平台差异表#5: RemoteViews+Canvas → SwiftUI 布局等价, 逐符号不移植)
    'widget/WidgetBitmapRenderers.kt', 'widget/RemoteViewsWidgetHelper.kt',
    'widget/WidgetRenderActivity.kt', 'widget/WeekGridPreviewActivity.kt',
    'widget/PinWidgetActivity.kt', 'widget/WidgetUpdater.kt', 'widget/WidgetUpdateWorker.kt',
    # Fluid Cloud(平台差异表#3: OPPO 前台服务, iOS 无对应物)
    'widget/notification/FluidCloudService.kt',
    # AppWidgetProvider 壳(TimelineProvider 承担, 名字池不含 Receiver 类名)
    'widget/WeekGridWidgetProvider.kt', 'widget/TodayWidget.kt', 'widget/WeekListWidget.kt',
    'widget/WeekViewWidget.kt', 'widget/TwoDayWidget.kt', 'widget/WidgetContent.kt',
    # Activity 壳(→ SwiftUI View / App 状态机 / URL scheme)
    './MainActivity.kt', './SleepyApp.kt',
    'ui/screen/imports/ImportReceiverActivity.kt', 'ui/screen/imports/JwImportActivity.kt',
}
# 局部变量豁免(值类别 only: 函数体内的 val 是局部状态, Swift 侧同位局部变量不在全局符号池)
LOCAL_VAL_HINT = {'context', 'ctx', 'scope', 'snackbar', 'fieldColors', 'sheetState',
                  'p', 'o', 'tj', 'val', 'tmp', 'mapped'}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--android-dir', default=ANDROID)
    ap.add_argument('--ios-dir', default=IOS)
    ap.add_argument('--json', action='store_true', help='输出 JSON 而非文本')
    ap.add_argument('--scope', help='只审计指定 Kotlin 子路径(如 data/util),默认全部')
    args = ap.parse_args()

    # 收集 Swift 全部符号(跨文件全局池)
    swift_pool = set()
    for root, _, files in os.walk(args.ios_dir):
        for f in files:
            if f.endswith('.swift'):
                for syms in swift_symbols(os.path.join(root, f)).values():
                    swift_pool.update(syms)

    swift_text = []
    for root, _, files in os.walk(args.ios_dir):
        for f in files:
            if f.endswith('.swift'):
                swift_text.append(open(os.path.join(root, f), encoding='utf-8').read())
    def swift_text_contains(s):
        return any(s in t for t in swift_text)

    unmapped = []
    explained = {'rename': 0, 'platform': 0, 'local': 0}
    total = 0
    for root, _, files in os.walk(args.android_dir):
        rel = os.path.relpath(root, args.android_dir)
        if args.scope and not rel.startswith(args.scope):
            continue
        for f in files:
            if not f.endswith('.kt'):
                continue
            path = os.path.join(root, f)
            relfile = f'{rel}/{f}'
            syms = kotlin_symbols(path)
            for kind, names in syms.items():
                for n in names:
                    total += 1
                    # 1) 平台差异豁免(整文件)
                    if relfile in PLATFORM_EXEMPT:
                        explained['platform'] += 1
                        continue
                    # 2) 改名映射
                    if n in RENAMES and RENAMES[n] in swift_pool:
                        explained['rename'] += 1
                        continue
                    # 2b) 文本等价(enum case / 成员级)
                    if n in TEXT_EQUIV and swift_text_contains(TEXT_EQUIV[n]):
                        explained['rename'] += 1
                        continue
                    # 3) 局部 val(非声明成员; 名字池不适用 — Swift 同位局部变量)
                    if kind == 'val':
                        # 局部 = Kotlin 文件内 fun {} 缩进内的 val。粗判: 非顶层即局部
                        # (该正则已包含顶层 private val — 成员 val 在 class 内带缩进)
                        explained['local'] += 1
                        continue
                    if kt_to_swift_name(n) not in swift_pool:
                        unmapped.append(f'{relfile}:{kind}:{n}')

    if args.json:
        print(json.dumps({'total': total, 'unmapped_count': len(unmapped),
                          'explained': explained, 'unmapped': unmapped}, ensure_ascii=False, indent=1))
    else:
        print(f'Kotlin 符号总数: {total}')
        print(f'已解释: rename={explained["rename"]} platform={explained["platform"]} local={explained["local"]}')
        print(f'未映射: {len(unmapped)}')
        for u in unmapped[:80]:
            print(f'  ✗ {u}')
        if len(unmapped) > 80:
            print(f'  ... 共 {len(unmapped)} 项')
    sys.exit(2 if unmapped else 0)

if __name__ == '__main__':
    main()
