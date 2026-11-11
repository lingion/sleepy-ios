# CI 与贡献流程

日常 PR 只执行一次模拟器构建和全部 `SleepyTests` 单元／集成测试。它同时编译应用、扩展和 UI 测试代码，不启动长时间的 UI 截图或拖拽矩阵。无需签名证书、私有凭据或外部 Android 仓库，fork 也使用相同流程。

| 触发 | 内容 | 硬超时 |
| --- | --- | --- |
| PR 打开／更新到 master | 一次构建＋全部单元／集成测试 | 20 分钟 |
| 手动 `task=unit` | 同上，检查指定 ref | 20 分钟 |
| 手动 `task=ui` | 一次构建＋指定一个 UI 类或方法 | 45 分钟 |
| 手动 `task=ipa` | 无签名 IPA | 45 分钟 |

只修改 Markdown、LICENSE 或 .gitignore 不触发构建。JSON 夹具等测试资源仍触发。没有分支 push、定时或 Gitee 自动镜像任务；同一 PR 的新提交取消旧运行，手动任务不取消 PR 检查。超时是上限，不是承诺耗时；冷启动、GitHub 排队和所选 UI 类的长度会影响实际时间。

2026-11-11 的旧矩阵样本中，构建＋全量单元约 8 分钟；五个分组累计占用约 254 分钟 runner、墙钟约 107 分钟，因此已移除自动全 UI 矩阵。测试源码和业务断言保留，UI 按改动范围选择运行。PR 的 `Build and tests` 通过只表示构建与单元通过，不代表所有 UI 已验证。

## 本地贡献

使用 macOS 和 Xcode，安装 XcodeGen 后生成工程。CI 固定使用 Xcode 26.3；本地可用兼容工具链，运行结果应注明版本。

```sh
brew install xcodegen
xcodegen generate --spec project.yml
xcodebuild -list -project Sleepy.xcodeproj
```

在 Xcode 选择 Sleepy scheme 和可用 iPhone 模拟器，按改动运行单元测试或对应 UI 用例。PR 描述写明问题、改动、真实验证和未覆盖范围。无需先跑所有截图流程，也无需配置 Gitee token。

## 手动运行

在 Actions → iOS Build → Run workflow 选择任务和 ref，或使用 GitHub CLI：

```sh
gh workflow run ios-build.yml -f ref=master -f task=unit
gh workflow run ios-build.yml -f ref=your-branch -f task=ui \
  -f ui_test=SleepyUITests/SwipeBackGestureUITests/testCourseEditorBackRestoresSchedule
gh workflow run ios-build.yml -f ref=master -f task=ipa -f config=Release
```

`ui_test` 必须是存在的 `SleepyUITests/类名` 或 `SleepyUITests/类名/test方法名`，构建前验证。空值、未知测试、整个 target 或多个选择器会立即失败，避免“零测试成功”和无界全量运行。长类可改选一个方法；45 分钟不够的整类应拆为相关方法分别检查，不自动重试。

每次诊断产物保存 7 天，包含实际检出提交 `revision.txt`、Xcode 版本、构建／测试日志及 xcresult。`workflow_dispatch` 的工作流分支和被测 `ref` 可以不同，以产物中的 revision 为准。

```sh
gh run list --workflow ios-build.yml --limit 5
gh run download <run-id>
```

IPA 不含分发签名，需要自行重签才能安装。脚本只执行一次 archive，构建失败原样返回，不靠再次构建掩盖错误。
