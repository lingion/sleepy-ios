# Sleepy iOS a.v.1.0.43 — Conflict styles, undo, 184 schools, synced with the original v1.0.51/52

## What's New

### Conflict courses, three ways to render them

Overlapping courses used to stack into an unreadable pile. The grid now renders the cluster as one unit, and you pick the style in Settings → Conflict course style:

- **Layered**: cards overlap with an offset you set with a slider.
- **Right inset**: later courses give up width on the right edge.
- **Folded corner**: corner fold, amplitude adjustable.

The Today page splits a conflict into side-by-side columns. Tap a cluster to choose which course stays pinned on top.

### Undo

The top bar has an undo button. Moving, editing, deleting, importing — ten write paths snapshot before they change anything, and one tap puts it back. Single level, same as Android. With nothing to undo, the tap shows a toast instead.

### Top bar rework

- Tap the logo to switch timetables. The popup shows which timetables have copies plus each one's import time, and deleting the last timetable is now allowed.
- Add-course and share buttons sit on the right. The undo button appears only when there is something to undo.

### Schools: 146 → 184

The school list grew by 38, including 12 from the 985 batch and Linyi University; the rest came from syncing the list with the Android repo. The protocol layer underneath grew too: a parser registry aligned with the original, new protocol support for UCAS and qz_ieas, twelve previously missing parsers, six more from the 985 batch, and direct WebView import for CQU's portal.

### Bind a widget to a timetable

Home-screen widgets can pin to one timetable instead of following whatever the app has open. The widget manage and edit screens handle the binding, and each widget can use its own course aliases.

### Sleepy native format (sleepy-v1)

A fourth row on the export page. The format keeps everything the app knows — colors, irregular periods, smart periods — and imports back without loss. Import gained options for clashing timetables: force-append the conflicting courses, append as a new timetable, or merge periods losslessly. The preview flags courses that would land in more than one location, and you can name a timetable before importing it.

### About page

Update banner with auto-check, and the changelog renders in-app. A new license page lists the GPL license plus the 14 open-source projects this app builds on, with contributor credits.

### Gestures and native controls

- Swipe back works everywhere, including pages drawn with custom overlays. Nine full-screen pages were re-hosted as native tabs so the gesture works there natively.
- The system color picker replaces the hand-built HSV wheel. Week jump uses the system wheel picker. Five dialogs and eight sub-pages moved to native sheets, and half-height sheets work on iOS 15 too.
- The bottom bar comes in two placements, docked or floating, and the highlight follows your finger.

### UI checked screen by screen against Android

Grid column widths, row heights, and font scaling now use the same formulas as Android, and the theme tokens were re-based on the original platform's. Today, Schedule, Mine, table management, appearance, general, holiday, reminder, export, about, license, import, and school selection were each checked against Android v1.0.51/52. The string tables gained 68 missing keys across all five languages.

## Fixes

- Picking a theme color applies immediately; follow-system mode actually follows the system.
- Opening a course detail no longer leaves courses from other weeks floating over the grid as ghosts.
- iPhone 6s Plus: removed the blank strip above the schedule and the page-top blank on every screen.
- The bottom bar highlight no longer lags a beat behind, and the floating bar stops colliding with scrolling content.
- Today page node text no longer gets cut mid-line.
- The JW import sheet keeps dark-mode colors instead of flashing light.

## Known Limitations

- The IPA is unsigned. Re-sign it with AltStore or Sideloadly before installing.
- Undo keeps a single level, matching Android.
- There is no refresh-rate setting on iOS: the system exposes no public API for it, so iOS schedules refresh rates itself.

## Verification

- Unit tests: 363 passed, 0 failed (iPhone 14 Pro simulator).
- Version 1.0.43, build 36.
- Asset: Sleepy.ipa, 8,350,121 bytes, SHA-256 `7738e13a3745288cba995249d8d9b97110808153f33096b24865fe5d5c8070ed`.

---

# Sleepy iOS a.v.1.0.43 — 冲突三样式、撤回、184 所学校,与安卓 v1.0.51/52 同步

## 新功能

### 冲突课程三种样式

课表里两门课撞在一起,以前是直接叠成一团,看不清。现在网格把冲突的课当一个整体渲染,样式在 设置 → 冲突课程样式 里选:

- **叠层**:课卡错开叠加,偏移量用拖杆调。
- **右缘让宽**:后面的课在右侧让出宽度。
- **折角**:折角样式,幅度可调。

今日页把冲突课分成左右两栏。点冲突簇可以选默认置顶哪门课。

### 撤回

顶栏多了撤回按钮。移动、编辑、删除、导入,十个写路径动手前先存快照,点一下就回去。单级,和安卓一致。没有可撤回的东西时,点了弹 toast 提示。

### 顶栏重排

- 点 logo 切换课表。弹层里标出哪些课表有副本、各自的导入时间,最后一张课表也允许删了。
- 右侧是加课和分享按钮。撤回按钮只在该出现的时候出现。

### 学校 146 → 184

学校列表加了 38 所,含 985 批次 12 所和临沂大学,其余与安卓主仓名单同步。协议层也跟着长:parser 注册表与安卓看齐,新增 UCAS、qz_ieas 协议,补上 12 个缺失解析器,再加 985 批次 6 个,重庆大学门户走 WebView 直接抓。

### 小组件绑定课表

桌面小组件可以钉在某一张课表上,不再跟着 App 里当前打开的表走。小组件管理和编辑页负责绑定,每个小组件还能用自己的课程别名。

### Sleepy 原生格式(sleepy-v1)

导出页第 4 行。这个格式保留 App 知道的所有东西——配色、不规则时段、智能时段,导回去不丢。导入时遇到和现有课表冲突的,现在有三种选择:带着冲突直接追加、追加成新课表、无损合并作息。预览会标出会落在多个位置的课程,导入前也能自己给课表起名。

### 关于页

更新横幅、自动检查更新,更新日志直接在 App 里渲染。新增许可页:GPL 协议加上这个 App 用到的 14 个开源项目,带贡献者名单。

### 手势与原生控件

- 右滑返回哪儿都能用了,包括自绘浮层的页面;九个全屏页改成原生承载,手势原生生效。
- 取色换成系统取色盘,跳周换成系统滚轮,五个弹窗和八个子页改成原生 sheet,iOS 15 也有半屏 sheet。
- 底栏两种形态,停靠或悬浮,高亮跟手。

### 界面逐屏核对安卓

网格列宽、行高、字号缩放公式和安卓同源,主题色板按安卓重校。今天、课表、我的、课表管理、外观、通用、节假日、提醒、导出、关于、许可、导入、选校,每一屏都和安卓 v1.0.51/52 核过。五种语言补了 68 个缺失文案。

## 修复

- 选主题颜色立刻生效;跟随系统这次真的跟随系统。
- 打开课程详情,其他周次的课不会再以幽灵图层浮在网格上。
- iPhone 6s Plus:课表顶上的空白条和全 App 页面顶部的空白都清掉了。
- 底栏高亮不再慢半拍,悬浮栏不再和滚动内容顶在一起。
- 今日页节点文字不再被截成半截。
- 教务导入弹层在深色模式下不再闪回浅色。

## 已知边界

- IPA 未签名,安装前需用 AltStore / Sideloadly 重签。
- 撤回只有一级,与安卓一致。
- iOS 没有高刷新率开关:系统不提供公开 API,刷率由系统自行调度。

## 验证

- 单元测试:363 通过 / 0 失败(iPhone 14 Pro 模拟器)。
- 版本 1.0.43,build 36。
- 资产:Sleepy.ipa,8,350,121 字节,SHA-256 `7738e13a3745288cba995249d8d9b97110808153f33096b24865fe5d5c8070ed`。
