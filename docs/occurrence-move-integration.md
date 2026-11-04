# 单次课程移动：持久化集成验证

## 范围与来源

- 目标：`.worktrees/integration-parity-v1063`；源：同级 `parity-v1063`。
- `SleepyTests/CourseOccurrenceMoveTests.swift` 原样迁入，共 27 个 XCTest 方法，全部断言保留。
- 源/目标测试文件 SHA-256：`32f8babcabecbf84ad4c2072a0a108cea7818660587fbe9f5de82d626b50412c`。
- 主 agent 已追加的 `CourseOccurrenceMoveError`、`moveCourseOccurrence`、`occurrenceRange` 与源对应连续切片逐字一致。本切片先验证已有实现。
- 目标树及其父目录未发现适用的 `AGENTS.md`，也未发现 `.agents/qa-project-context.md`；按本任务显式范围执行。

## 独立 harness

入口：`scripts/occurrence-move-check/run.py`。使用 macOS SwiftPM/XCTest，离线引用 DerivedData 中已有 GRDB 源码。编译和测试使用 `nice -n 15`、`--jobs 1`、`-Xswiftc -j1`，不启用并行测试。

本次 GRDB revision：`2cf6c756e1e5ef6901ebae16576a7e4e4b834622`。

直接逐文件复制生产源码到独立 scratch 后编译，不裁剪、不替换被测方法：

- 完整 `ScheduleRepository.swift`、`CourseOccurrenceDestination.swift`；
- 完整 `AppDatabase.swift` 及实际 v1–v12 迁移；
- 全部实体、全部 DAO；
- 完整 `UndoManager.swift`、`TimeTableUtils.swift`；
- 编译依赖 `NewTableImport.swift`、`ImportRoster.swift`、`RowKeyDiffer.swift`。

每次运行生成 `source-sha256.json`，记录生产源码和测试副本的校验值。测试文件不做平台化替换。

### 明确隔离的外部边界

`Support.swift` 只承担独立 target 无法直接引入的应用外部依赖：

- App Group 路径：调用即失败；测试仅使用显式内存库和临时文件库。
- 系统通知、UI 本地化、非空冲突置顶偏好清理：调用即失败。
- 冲突置顶偏好读取固定空字典，避免触碰用户 UserDefaults；真实 undo/redo 仍执行完整数据库恢复。
- 新增组配色胶水：调用即失败；移动路径保留 groupId，不应进入导入/新组配色路径。真实 `CourseColorDao` 和表迁移仍编译。
- `String.isBlank` 与生产 `HolidayManager.swift` 中实现一致，只提供该基础扩展，避免引入节假日 UI/应用依赖。

没有替代 Repository、DAO、数据库建表、UndoManager、TimeTableUtils 或目标时间解析算法。

## 执行命令

```sh
OCCURRENCE_CHECK_DIR=/private/var/folders/z3/7cz1vccj2g1clmqqqqh5x4y00000gn/T/opencode/occurrence-move-20261103 \
GRDB_SOURCE=/Users/kerrylee/Library/Developer/Xcode/DerivedData/Sleepy-bpxdesqglphdejahuqvhenxrheak/SourcePackages/checkouts/GRDB.swift \
nice -n 15 python3 scripts/occurrence-move-check/run.py
```

日志：`/private/var/folders/z3/7cz1vccj2g1clmqqqqh5x4y00000gn/T/opencode/occurrence-move-20261103.log`。

## 覆盖与结果

已有测试覆盖：每周/单双周/显式周区间拆分，首尾及唯一实例，无 phantom 区间，同位置跨周与目标已有课并存，过期重放，非法时间/节次，批操作首快照，no-op 保留 redo，SQLite INSERT 失败与延迟外键 COMMIT 失败回滚，跨表 undo/redo，绑定作息，自定义时间/非常规时间与秒级时长，分数行显式时间，以及文件库关闭重开后的持久化。

2026-11-03 21:47（本机时间）实际执行结果：

```text
Build complete! (145.71秒)
Test Suite 'CourseOccurrenceMoveTests' passed
Executed 27 tests, with 0 failures (0 unexpected) in 0.385 (0.389) seconds
```

编译完成且 27/27 全绿，包括真实 SQLite trigger 注入的 INSERT 失败、延迟外键 COMMIT 失败、磁盘库关闭重开。源测试逐字比较一致；没有修改任何旧断言。代码核对与本轮测试未发现需要修复的移动持久化缺陷，因此没有追加生产代码修改或新回归测试。

编译输出有既有未使用变量/结果和 GRDB watchOS 最低版本声明警告，不影响本轮 macOS 编译与测试。

测试完成后校验 `source-sha256.json`：全部被编译生产文件与测试均与目标工作树一致，无并行 agent 修改导致的源码漂移；Python harness 语法检查和 `git diff --check` 通过。

注：第一次后台启动误设 1 秒工具超时，在产生编译输出前被终止；随后取消该超时，独立完整运行得到以上结果。没有把被终止尝试计作验收。

## 验收边界

本验证证明持久化切片的实际 SQLite/GRDB 行为；不替代 iOS 工程构建、模拟器 UI 拖放、VM/policy/identity/parser 集成或系统通知/Widget 验收。工程文件与其余验收由主 agent 负责。
