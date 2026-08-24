# Tasks(symlink 到 plan 内任务;勾选状态唯一事实源)

## D0
- [x] T0.1 工程骨架 — ✅ xcodegen 2.38 源码编译装 ~/bin;三 target(app+widget+tests+uitests 实为4)BUILD SUCCEEDED;五语言 389键+day_names 已迁(63处格式占位符转 %1$@)
- [x] T0.2 构建链+G1闸 — ✅ build-ipa.sh/coverage_audit.py 落盘(基线 1878 符号);GRDB.swift v6.29.3 经镜像 resolve 成功(仓库2026改名,旧路径404是假故障);xctest target plist 缺 CFBundleVersion 已修;simctl install+launch 验证通过;单测 1/1 绿
- [x] T0.3 风险矩阵+环境定盘 — ✅ risk-matrix.md 13 项评分(R1教务链20/R2周次15/R3数据层15/R4解析16/R6widget16=CRITICAL)+失败模式五字段;fixture 服务器四协议链路实测通(login 200→302→cookie→kb 200;端口 8791)
- [ ] CP-D0 检查点(IPA✓三target✓矩阵落盘+ln-11复审+**用户过目**)

## D1
- [ ] T1.1 entity 3 文件+GRDB映射
- [ ] T1.2 dao+AppDatabase(SQL语义逐条)
- [ ] T1.3 DateUtils/TimeTableUtils/CourseColorUtil+2测试
- [ ] T1.4 AppPrefs/LocaleHelper+1测试
- [ ] T1.5 VersionUtils/UpdateInfo/UpdateManager+2测试
- [ ] T1.5b G4链①前半: 课程链条(DAO→周次→查询)内存全链测试
- [ ] T1.6 PinyinMatcher+389键×5语言+StringsKeyParityTest
- [ ] CP-D1(7测试绿+G1零缺+G4链①绿+database-testing+ln-25审计)

## D2
- [ ] T2.1 jw 协议+小解析器 7 文件
- [ ] T2.2 jw 大解析器 3 文件(NewUrp/NewZf/Wisedu)
- [ ] T2.3 JwImportViewModel+3测试文件全用例(G2)
- [ ] CP-D2(jw测试绿+G1/G2)

## D3
- [ ] T3.1 ScheduleParser 738行六格式
- [ ] T3.2 ScheduleExporter+ScheduleRepository+往返测试
- [ ] T3.3 G4链②③: 导入链+导出链内存全链测试
- [ ] CP-D3(往返绿+G4链②③绿+ln-23测试审计)

## D4
- [ ] T4.1 Theme+ThemePresets(5预设×2+HSV逐hex)

## D5
- [ ] T5.1 小组件 4
- [ ] T5.2 CourseTableView 716行
- [ ] T5.3 SmartPeriodEditor+TimeSlotEditor
- [ ] CP-D5(Preview全渲染+零警告)

## D6
- [ ] T6.1 ScheduleScreen+ViewModel+TodayScreen
- [ ] T6.2 AddCourseScreen 1258行
- [ ] T6.3 Mine/AllTables/EditTable/Management
- [ ] T6.4 设置 6 屏
- [ ] T6.5 导入流程 5 文件(WKWebView)
- [ ] T6.5b 教务fixture链: 四协议HTML快照+XCUITest全链+真站冒烟一次(账号输入留用户)
- [ ] T6.6 G4链①后半+G5: VM接线链测+XCUITest UI冒烟自动化+探索测试
- [ ] CP-D6(XCUITest冒烟+教务链全绿+G4三链绿)

## D7
- [ ] T7.0 doubt-driven: App Group 对抗审查
- [ ] T7.1 widget 数据层+共享实测
- [ ] T7.2 小 widget 3
- [ ] T7.3 大 widget 2+gallery
- [ ] T7.4 通知调度器+联测
- [ ] CP-D7(gallery 5 widget+通知触发,XCUITest断言)

## D8
- [ ] T8.1 壳+联调+G1终审(76文件)
- [ ] T8.2 真机验收(agent驱动): devicectl调试版全项自动化→AltStore装机复测→ln-42验收矩阵
- [ ] CP-D8(矩阵全PASS+release-readiness→用户签收)
