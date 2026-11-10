# 最小小组件复核与修正（2026-11-10）

Android最小周列表显示三列。此前把Android可拉伸SMALL receiver的150dp升档门槛直接套用到iOS最小family，导致158pt的systemSmall错误显示整周；此前149/150/158pt切脸结论不再适用。

## 对齐规则

精确基准仍为Android `v1.0.63` / `b16aa84d11c250acdf644cd8b7812ab27d03dc6a`。Android `WidgetVariantInfo.kt`及三种small provider XML声明110×110dp、2×2、允许拉伸；`WidgetBitmapRenderers.kt`的WeekList/WeekView仅SMALL且宽<150dp走compact，拉宽后才升整周。`WeekGridWidgetProvider.kt`的默认小档复用Today。iOS按所选WidgetFamily承接这些默认档位，不以相同数值的dp/pt区分。

| iOS类型 | systemSmall | systemMedium/systemLarge |
| --- | --- | --- |
| WeekList（周列表） | 最多三天列，保留课程颜色胶囊 | 按显示星期设置展示完整周 |
| WeekView（周视图） | 最多三天列，保留文字课程样式 | 按显示星期设置展示完整周 |
| WeekGrid（周网格） | Today今日课程脸及对应课后刷新边界 | 完整周网格 |
| Today（今日课程） | 原有单日课程窗口 | 原有单日课程窗口 |
| TwoDay（两日课程） | 原有两列课程窗口 | 原有两列课程窗口 |

周列表/周视图默认窗口为今日、明日、后日；今日居第二位时为昨日、今日、明日。窗口按自然日期跨周，不跳过无课日；显示星期设置可能使列数少于三。无compactWindow数据时才用原有今天邻域后备策略。

## 三天窗口取课修正

`WidgetCompactWindow.build`由全表数据按真实源日反查调休课程，星期标题仍使用展示日自然星期，跨周单双周随源日计算。定日课只出现在自己的自然日，不随调休搬移，也不按元数据星期重复。补班日可在学期范围外承接学期内课程；未搬移的学期前日期保留第一周常规课预习，排除未来定日课。比较自然日而非Date时分，覆盖12:34时间线日期。

## 实际证据

- 先冻结视图/刷新测试：旧实现3项测试均失败，共35个断言，150–200pt错误分支被真实生产视图像素对照击中。
- 修family后，`WidgetFaceGeometryTests` 10/10与`WidgetSemanticsTests` 50/50通过；110/141/149/150/158/170/180/200pt的三类小脸对照覆盖；另输出五类×小中大共15张生产脸供目检。
- 数据层新增12项真实内存仓库回归。fixture的tableDao编译错误先改为timeTableDao后，旧生产实现2项控制通过、10项失败，共12个断言；该RED不含编译失败批次。
- 数据回归单独提交后冻结，修复期间三份测试SHA保持不变，未跳过/放宽断言。
- 最终全目标 `widget-small-final-build` 构建成功；`widget-small-final-unit` **2274项、0失败，31.186s**，`TEST EXECUTE SUCCEEDED`。12项数据回归全部通过，生产候选为 `b283ed1`。
- 五类158pt最小脸与158pt周列表、200pt周视图、medium/large网格经独立图片审查，未发现新增确定的错位或严重遮挡。

日志与结果包：`widget-small-red`、`widget-small-green-window-red`、`widget-small-final-build`、`widget-small-final-unit`。首两批保留预期RED及具体失败，不标成全部通过。

## 验收边界

PNG由实际生产EntryView离屏渲染，15脸矩阵验证可渲染并供目检，具体列数由独立三列数据像素参照锁定；这些不是主屏幕WidgetKit添加/刷新实测。Android可拉伸外框与iOS系统family外框不保证物理尺寸相同。iOS无Android滚动条带宿主，溢出保留列底+N窗口策略。真实主屏刷新、签名AppGroup分发及此前报告的其他真机边界保持未验收。
