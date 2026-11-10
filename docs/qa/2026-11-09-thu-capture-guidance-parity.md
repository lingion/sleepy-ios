# THU 抓取动线对齐

日期：2026-11-09。基线为 Android 精确 `v1.0.63` / `b16aa84d11c250acdf644cd8b7812ab27d03dc6a`，全部证据通过 `git show` 读取。

此项仅补齐已支持学校的页面引导和错误恢复，不新增协议或来源。Android `JwWebViewLoginScreen.kt:438` 对 THU 显示「整体课表 → 选择学期 → 导入此页」；同文件 `:618–622` 在 `WRONG_PAGE` 时提供相同的精确恢复路径。iOS 原先总显示泛用「个人课表」，且错误分流只有 UCAS 门户特例。

新增 `JwCaptureGuidance`，供实际页面导航提示与抓取失败回调共用。仅 THU 的 `.wrongPage` 替换为课程脚本缺失指引，原有会话过期、跨域、容器未就绪和其他诊断保持原文；UCAS 门户分流保持原行为。

五语的 `jw_nav_hint_thu` / `jw_err_thu_course_page` 直接取自该精确标签 `app/src/main/res/{values,values-zh-rTW,values-en,values-ja,values-es}/strings.xml`，追加至现有 iOS 对应资源，未覆盖其余未提交键。

新增 `JwCaptureGuidanceTests` 共五个测试：专属/泛用导航、真实 frame 快照经 `FrameTraversalTree` 分类为 wrongPage 后的 THU 分流、非 wrongPage 状态保留、UCAS/泛用路由、五语精确文案。不是源码 contains 检查。测试在生产修改前写入并冻结；中央 build-7 发现学校类型为可选值后，经 root 授权追加 nil 学校类型的泛用导航及原诊断断言并重新冻结，SHA256 为 `baaa1578953d099c6e69e62d2175b3aaa03ba85f5fe590713c149e4283ae2077`；原有测试未修改。

实施代理只做静态差异检查，构建与测试结果由中央统一运行记录。此项未做清华真实账号登录验证，不改变任何学校目录支持或验证状态；原有 THU 协议、fixture、致谢保持不变。
