# sleepy→iOS 移植风险矩阵(risk-based-testing 六相输出)

评分轴: Impact(1-5 失败多糟) × Probability(1-5 移植中多可能失败) → 区(CRITICAL 15-25 / HIGH 10-14 / MEDIUM 5-9 / LOW 1-4)
概率依据: 代码量×复杂度×Android/iOS 语义差异度。测试密度按区配,不撒胡椒面。

## Phase 2 风险分类表

| # | 模块/链 | Impact | Prob | 分 | 区 | 测试密度 |
|---|---|---|---|---|---|---|
| R1 | 教务导入链(14协议×WebView登录×cookie×抓取) | 5 | 4 | 20 | CRITICAL | 单元(Jw*Test 全用例)+fixture HTML 全链+真站冒烟 |
| R2 | 周次/日期计算(DateUtils 语义:开学日/单双周/跨年) | 5 | 3 | 15 | CRITICAL | DateUtilsTest 全用例+G4链①断言三视图一致 |
| R3 | 数据层迁移(Room→GRDB: schema/类型亲和/事务) | 5 | 3 | 15 | CRITICAL | database-testing parity+ln-25 审计+roundtrip |
| R4 | 文本格式解析(WakeUp/ICS/CSV/HTML/纯文本 738行) | 4 | 4 | 16 | CRITICAL | Parser 全用例+六格式 G4 链② |
| R5 | 导出三格式(JSON/分享文本/ICS)+roundtrip | 4 | 3 | 12 | HIGH | ExportImportRoundTrip+G4 链③ |
| R6 | Widget 数据同步(App Group/共享DB/5类渲染) | 4 | 4 | 16 | CRITICAL | T7.0 对抗审查+gallery 渲染断言+真机复测 |
| R7 | 通知调度(AlarmManager→UNUserNotification 语义) | 3 | 4 | 12 | HIGH | 单测时间计算+模拟器触发断言+真机收包 |
| R8 | 主题(5预设×2模式+HSV+跟随系统) | 2 | 3 | 6 | MEDIUM | 色值 hex 对齐测试+Preview |
| R9 | UI 屏幕(19屏 SwiftUI 还原) | 3 | 3 | 9 | MEDIUM | XCUITest 冒烟+D8 截屏对照 |
| R10 | 字符串/本地化(389×5) | 2 | 2 | 4 | LOW | G3 parity 机械跑 |
| R11 | PinyinMatcher(311行数据表搬运) | 2 | 3 | 6 | MEDIUM | 移植其 Android 测试若有+抽查 |
| R12 | 版本/更新(VersionUtils+UpdateManager) | 2 | 2 | 4 | LOW | 两个原测试文件 |
| R13 | 无签名 IPA→AltStore 重签装机链 | 4 | 3 | 12 | HIGH | T8.2 真机实测(模拟器不可代) |

## Phase 3 失败模式分析(≥10 分项,五字段)

### R1 教务导入链(20)
- 失败模式1: WebView 登录 cookie 未随 API 请求带上 → 抓课表 401
  - 触发: WKHTTPCookieStore 异步性与 Android CookieManager 同步语义差异
  - 波及: 全部 14 协议直连导入不可用
  - 检测: fixture 服务器断言请求带 cookie;真站冒烟
  - 现缓解: T6.5b fixture 全链
  - 缺口: 真站(验证码/UA 检测)只能冒烟一次
- 失败模式2: HTML/JSON 解析逐字符对不上 → 课表空
  - 触发: Kotlin 字符串处理与 Swift Foundation 差异(正则/编码)
  - 检测: JwParserTest 13 用例(3文件)喂真实快照
  - 缺口: 快照覆盖 4 主协议,余 10 变体靠构造样本

### R2 周次计算(15)
- 失败模式: 单双周过滤错位 → 显示错周课程
  - 触发: 起始周=周一 vs 周日语义、闰年、LocalDate vs Date 边界
  - 检测: DateUtilsTest 全用例+G4链①(建表→加课→跨周查询)
  - 缺口: 时区切换场景(自用场景风险低,接受)

### R3 数据层(15)
- 失败模式: GRDB 类型映射错(如 Int 回退 null/默认值) → 课程字段静默丢失
  - 检测: database-testing parity(逐列 roundtrip)+ln-25 审计
  - 缺口: 无 Android 数据直接迁移需求(自用新建),迁移场景不做

### R6 Widget 同步(16)
- 失败模式: 免费重签 App Group 不生效 → widget 读不到课程
  - 检测: T7.0 对抗审查先行+真机 devicectl 实测
  - 兜底: widget 直读 DB 文件路径;仍败→ask 付费账号

## Phase 4 热图落点

```
            P1  P2  P3  P4  P5
I5          R2  R3      R1
I4                  R5  R4 R6
I3              R7  R9
I2          R12 R10 R8/R11
```

## Phase 5 覆盖对齐

| 区 | 要求 | 现状 | 缺口→任务 |
|---|---|---|---|
| CRITICAL×4 | 单元+链条+fixture链+真机 | 0 | T1/T2/T3/T6.5b/T7.0/T8.2 |
| HIGH×2 | 单测+模拟器断言+真机复测 | 0 | T7.4/T8.2 |
| MEDIUM×3 | 单测+Preview | 0 | T1.3/T4/T6 |
| LOW×2 | 原 Android 测试移植 | 0 | T1.5/T1.6 |

## Phase 6 重评触发
- 每批 checkpoint 重跑本表概率列(实现中发现语义差异→升 P)
- 任何闸红 ≥2 次同类 → 该模块 P+1
- 真机验收逃逸缺陷 → 48h 内重评
