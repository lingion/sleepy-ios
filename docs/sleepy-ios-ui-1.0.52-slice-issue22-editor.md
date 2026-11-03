# Slice — issue#22 编辑器 + 数据层 (1.0.52 对齐)

对齐 原 commit fe389b4 (1.0.52) 的 issue#22「同名课程多地点」编辑器改造。
Android 源: `git -C ~/sleepy show fe389b4:app/src/main/java/com/lingion/sleepy/ui/screen/edit/AddCourseScreen.kt`

## 已入库 commit 0c0ebf8 (数据层, 3 files +149)

- 新增 `Sleepy/data/diff/RowKeyDiffer.swift` — RowKey/DiffResult/RowKeyDiffer 三类合一 1:1 翻译。
  RowKey = (day, startNode, step, startWeek, endWeek, type, room, teacher);
  colorMode/color/note 不进 key(改颜色=原地 update, 不删+插)。
  groupId="" 兜底: draft 全 insert, server 全 delete(契约一保护)。
  GRDB 适配点: `Dictionary.Keys` 不支持 `+` → 两次 for-in 保留序去重;
  `WHERE id IN (?)` 不接受数组绑定 → 占位符手工展开 + `StatementArguments(ids)`。
  CourseDao.deleteByIds 空数组防御: SQL 展开空 `IN ()` 会产生非法 SQL —
  但 applyDiff 与 RowKeyDiffer 已保证 toDelete 非空才调, 与 原语义一致。
  [注] deleteByIds 自身没有空数组短路 — applyDiff 的 `if !diff.toDelete.isEmpty` 承担了这层防御,
  Android 侧由 Room 的 `IN (:ids)` 绑定处理空列表, 语义等价。
- `CourseDao` +`updateAll`(@Update 批量, 保留行 id) / +`deleteByIds`(IN 展开)。
- `ScheduleRepository` +`applyDiff(tableId, diff)`: 内部 `try captureForUndo()`
  (Android 要求调用方先捕获; iOS captureForUndo 是 private → 内部等价捕获, 注释注明分叉),
  顺序 delete → update → insert → onDataChanged。
- xcodegen generate 已跑(RowKeyDiffer.swift 进入 pbxproj — 该改动随本次 commit 入库)。

## 工作区(未提交) — Sleepy/ui/screen/edit/AddCourseScreen.swift

编辑器侧 issue#22 改造已完成并通过 BUILD SUCCEEDED, 但该文件同时含用户未提交的
1.0.51 对齐工作(冲突明细弹窗/每时段周次/单双周/clamp 提示/apply_to_all_slots/maxNode 校验),
且 issue#22 的 hunks 语义上构建在这些工作之上(buildCourseEntity 读 block.startWeek/weekType,
MeetingBlockEditor 的插入点在用户重构后的编辑器里)。两套工作无法拆开提交 —
提交任何一半都会得到编译不过的 commit。按规约「用户 dirty 文件 hunks 不代提交」,
AddCourseScreen 保持工作区状态, 等用户先提交自己的工作后可直接 `git add` 一并入库。

工作区含的 issue#22 hunks (对齐原实现 1.0.52):
- MeetingBlockDraft + room/teacher/note/color/colorMode (默认 ""/GROUP)
- 顶层 @State teacher/room/note/courseColor/showColorPicker 删除
- basicInfoCard 只剩 courseName
- 顶层 NativeColorPicker sheet 删除(Android 注释: 颜色按 block 独立弹窗)
- loadIfNeeded: 顶层赋值删除; 分组 key += room/teacher; block 回填携带四字段+colorMode;
  initialMeetingBlock 同步回填
- save(): buildCourseEntity 新形态; 编辑分支 getGroupCourses→RowKeyDiffer.diff→applyDiff
- buildCourseEntity(tableId,groupId,courseName,day,block): finalColor 三态
  (CUSTOM→color.ifBlank{"#FF6750A4"} / AUTO→"" / GROUP→color.ifBlank{sentinel}),
  teacher/room/note 从 block trim, entity.colorMode = block.colorMode
- MeetingBlockEditor: 老师/地点/备注 FieldTextField/MultilineFieldCompat + ColorSection
  (Group 包一层 — ViewBuilder 单容器 10 子视图上限, iOS 15.6 目标无 variadic ViewBuilder)
- ColorSection 三态(GROUP 跟组色 / AUTO 黄金角散色 / CUSTOM 固定 hex):
  Toggle OFF=GROUP, ON→AUTO; ON 后 AutoColorDot/CustomColorDot + hex 标签;
  per-block NativeColorPicker sheet, onConfirm 落 CUSTOM
