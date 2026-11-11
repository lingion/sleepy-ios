# THU 部分课程跳过提示对齐

日期：2026-11-11。Android 固定基线为 `v1.0.64` 解引用后的 commit `77b878fd5c8903a3f201ea938b3b152de4c4fbc0`。`89ea1a1962132e1433549f6c95a614778ad80aec` 是 annotated tag 对象，不是源码 commit。以下固定版本证据均通过 `git show 77b878fd…:<path>` 读取。

Android `JwImportActivity.kt:955–958` 从 THU parser attempt 的既有 `thu:skipped-unsupported=N` 特征获取数量，在 `:652–653` 传入 Preview 的 `parserWarning`，在 `:705–710` 的 Configure 内用 errorContainer 提示核对教务课表并手动补录；`:968–969` 在课程全部被跳过的空结果分支中也使用此提示。`ImportSheet.kt:1110–1112` 渲染 Preview 提示。当前 Android 修复工作树保留同一诊断和提示通路。

iOS `JwThuparser.matchedFeatureList` 已生成该特征；此前成功解析后的 UI 没有消费它。本次只在 `JwImportFlow` 将 THU attempt 的正整数数量转换为本地化警告，随现有 `ScheduleParser.ParseResult.warnings` 进入共享加课 Preview/Confirm，并在 JW Preview、Configure 和手动更新 Preview 展示。每次成功解析重新生成，正常完整导入不会保留前次警告。没有修改 parser、抓取脚本、课程、来源元数据或草稿契约。

五语 `jw_thu_skipped_courses` 原文取自该固定 commit 的 `app/src/main/res/{values,values-zh-rTW,values-en,values-ja,values-es}/strings.xml`。iOS 全部课程跳过时复用同一 UI 映射显示数量和手动补录建议；没有该 THU 正整数诊断时仍使用既有 `DiagMapper` 空解析错误分流。解析异常路径保持既有错误处理。

`JwImportParserWarningTests` 的五个用例通过实际 THU fixture 和生产 parse dispatch 覆盖一条不支持的周次被跳过、完整五条课程无警告、五条安排全部因不支持周次被跳过后显示数量且无诊断时回到原错误；另覆盖协议及正整数诊断边界、五语精确文案。实施代理仅做 Swift 解析、字符串资源语法和 diff 检查，构建与运行结果由根任务统一记录。
