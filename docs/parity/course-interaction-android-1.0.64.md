# 课程浮层、翻周和新建课表对照

参考：Android `0978eceb`，iOS 修复基线 `501de474`。本记录只覆盖下面列出的交互链，不代表整个应用已经验收。

## 逐项实现

| 触发 | Android 源码与行为 | iOS 承接 |
| --- | --- | --- |
| 普通点击 | `CourseTableView.kt` / `ScheduleScreen.kt`：打开整门课程详情；没有单次操作入口 | `CourseDetailSheet`；单次操作只在长按浮层/周视图长按入口 |
| 原地长按 | `continuousFloatLift` / `liftCourse`：整格浮卡、上下把手、调整/删除浮框；网格模糊20dp与0.12遮罩 | `CourseDragContext`、`CourseFloatingPreviewView`、`CourseDragBackdrop`；纯长按松手保留浮层 |
| 连续拖动或再次抓取 | `continuousFloatLift`使用两倍touchSlop防轻抖；进入dragging后撤模糊和菜单，只灰显原周原卡；卡按实际中心投影，150ms跳格 | 长按后16pt独立防抖；`beginMovement`、`movementAnchor`、`CourseDragSourceDim`、`placePreview`；重抓读取presentation位置 |
| 自定义时间课浮起 | `liftCourse`：浮起后按完整节次栅格；`FloatOccurrenceHandler`换格使用目标节次起止时刻 | 浮卡和落点统一按渲染节次；提交当前跨度，原位结束不改原分钟时间 |
| 左右驻边 | `EdgePeek.kt` / `CourseTableView.kt`：10dp外缘、8dp水平位移、500ms一周；35%进度起淡入预览，学期边界低透明度示形 | `CourseDragEdgePaging` / `CourseDragEdgePeek`，同一计时真源驱动提示与触发 |
| 驻边翻周 | `animateScrollToPage`：300ms、曲线(0.1,0.1,0,1)，浮卡反平移固定在手指下 | `WeekPager`保留起拖页，目标周独立滑动；UIKit浮卡在window上，不随页移动；落点用目标周实测网格 |
| 纵向驻边 | `CourseTableView.kt`：50ms采样，48dp/至多视口1/3边缘区，按越界深度3–14dp滚动；长卡按最近方向仲裁 | `CourseDragScrollProbe` / `autoScroll`，每周真实UIScrollView锁定及程序滚动，结束恢复 |
| 合法落点松手 | `commitFloatDrop`：水平方向无条件钳首/末列（含卡中心出屏）；卡停吸附格，退出驻边计时；确认后才保存单次课 | 松手独立横向钳位；`finishDrag(commit:)`只暂存，保留浮卡；`ScheduleViewModel`审批后事务保存 |
| 原位拖回/取消 | 真拖后回原位直接收层；非法落点/确认取消弹回并继续浮着 | `releaseFloating`区分纯长按与真拖；`returnToOrigin`保留会话与弹簧归位 |
| 上下拉伸 | `applyFloatResize`：只改抓取边，另一边固定，按连续节点吸附；松手不写库 | `CourseFloatResizePolicy`、`resizeFloating`保留待确认范围，允许连续边缘节次，不跨缺号 |
| 拉伸后点击空白 | `confirmPendingResizeBeforeDismiss`：确认持续节次；同意保存并收层，取消恢复跨度并继续浮起 | `dismissFloating`提交resize意图；确认回调控制保存/恢复 |
| 拉伸后继续移动 | 移动与当前跨度一起审批并只改这一次，撤销恢复原学期记录 | `stageDraggedOccurrence`捕获当前跨度；写库快照校验与一次撤销 |
| 普通翻周 | `ScheduleScreen.kt`监听selectedWeek并动画滚动 | `WeekPager`对按钮/跳周/回本周的selection变化提供动画；手势翻页继续由原生pager处理 |
| 二级页面进退 | `SleepyNavHost`的forward/pop内容转场 | `PresentOverlay`给child route实际identity并使用动画事务，不再直接替换无转场 |
| 新建课表 | 默认名、上周一、首表默认；新草稿不切当前表；返回丢弃，保存回来源 | 保留已一致的VM数据语义；创建失败不进空编辑器；删除编辑页多余教务更新行 |
| 导入方式与手动编辑 | Android均为全屏导航page，返回保持方式页草稿 | `sleepyNavigationPage`保留父页状态及逐层返回；关闭动画后消费导入队列 |

## 文案与桌面网格

- 编辑课表沿用 Android 的“课表名称”“总周数”标题。有值时显示浮动标题，不能只剩默认的 `20`。
- 我的页面入口使用 `settings_holidays`（节假日与调休），不再误用灰显开关的 `settings_holiday_title`；“外观与主题”“作息表”等同页面文案按五种语言的 Android 资源核对。
- 按 2026-11-12 的后续要求，Android 和 iOS 的 4×2 周视图只保留两个独立注册的小组件：竖向 7 天、横向 3 天。删除旧 4×2 组件注册及其原有完整网格模式，管理页不再提供布局模式切换；独立的大尺寸完整网格保留。
- 竖向组件按节次推进；横向组件显示从今天起三个自然日与全部节次。两种组件各有独立绑定和设置入口，画廊直接展示对应布局。
- 显式绑定独立作息的小组件通过 `WidgetTableResolver` 水合节次；不再从课表兼容列读取过期的时间。
- iOS 主 App 的偏好仍保存在原 standard 域，扩展改从 App Group 读渲染偏好。旧用户启动时自动发布已有值；统一底色、主题、别名、节次表头和备份恢复使用同一共享链路，扩展不会反向覆盖主 App。
- 完整网格统一底色和压缩色带改用 Android 相同的 `secondaryContainer`，普通课程不透明，灰显透明度为 153/255。纯文字周视图保持原有语义。
- 旧 4×2 注册已删除，原桌面实例需要重新添加新组件；独立完整网格仅保留小号和大号，系统选择器不再出现第三种中号完整网格。

## 验证边界

- 纯逻辑和数据库测试覆盖驻边计时/反馈、连续节点范围、单次保存、调休、冲突审批、过期快照与撤销。
- 模拟器仅验证普通点击、原地长按、翻周、新建表/返回、输入草稿保留和转场录屏。
- 复杂课程拖动、连续跨周拖动、上下把手拉伸由用户手动验收；没有把这些流程的自动化执行列为通过。
- 本轮不使用物理手机，不上传App Store。
- 2026-11-12：iOS 最新小组件与课程逻辑/数据库/生产渲染共 251 项测试通过；两个独立组件的课程、教室、节次轴、推进窗口及六类带色课程小组件的统一底色均通过像素验证。App Group 用三个隔离 UserDefaults 域验证共享行为，没有把它称为 WidgetKit 宿主两进程实测。
- 最后一次小组件改动完成后，相关 7 个测试类 126 项通过，画廊、共享课表显示全屏往返、两种独立组件编辑页的 3 项普通 UI 测试通过；预览外层卡、固定形态标题与画廊首排顶部对齐已逐图核对。
- 普通翻周录屏出现连续位移；前台翻周与原地浮起区间 172 帧未检出黑边。复杂拖动与拉伸仍由用户手动验收。
