# CI 自动化 / 免费算力手册 ("CI 白嫖厨房")

本仓库是 **public**,GitHub Actions 的 macOS/Linux runner 对 public 仓库免费。对本项目这条尤其关键:**开发机是 Linux,没有 Xcode/iOS SDK,iOS 构建与模拟器测试只能靠 CI 的 macOS runner**。

## 1. 手动触发构建 ("点菜")

### 1.1 无签名 IPA 构建
```bash
gh workflow run "iOS Build" -f ref=master -f config=Release
```
- macOS runner 上 `brew install xcodegen` 后走 `scripts/build-ipa.sh`(CODE_SIGNING_ALLOWED=NO 管线)。
- 产物 `Sleepy-unsigned.ipa` 存 7 天,用 AltStore/Sideloadly 重签后装真机。
- `-f config=Debug` 出 Debug 包;`-f tests=yes` 顺带跑 iPhone 15 模拟器单元测试(排队会久一些)。

### 1.2 下载产物
```bash
gh run list --workflow "iOS Build" --limit 3   # 找 run-id
gh run download <run-id>                        # 拉全部产物
```
> 产物回传走 GitHub CDN。如果本地代理很慢,用手机浏览器开 run 页面直接下。

## 2. 自动同步
`sync-to-gitee.yml`:每次 push 任意分支/tag 自动镜像到 Gitee,无需手动操作。

## 3. 限制与注意
- 单 job 上限 6 小时;本仓库构建 job 设 45 分钟(实测 xcodegen+xcodebuild archive 约 10–15 分钟)。
- macOS runner free plan 并发低,dispatch 任务可能要排队几分钟。
- 签名相关:`project.yml` 里的 Personal Team 证书(7 天过期)只在本机 Xcode 有效;CI 一律走无签名管线,由用户侧 AltStore 重签——这是设计如此,不是遗漏。

## 4. 给贡献者:加一条新能力
1. `.github/workflows/` 新建 `*.yml`,用 `workflow_dispatch + inputs` 参数化。
2. 加 `concurrency`、`timeout-minutes`、`permissions: contents: read`。
3. **合进默认分支(master)**,否则 dispatch 触发不了。
4. 回本页补一行说明。

Android 侧的对应文档在 [lingion/sleepy/docs/ci-automation.md](https://github.com/lingion/sleepy/blob/main/docs/ci-automation.md)(debug APK 参数化打包、KVM 模拟器测试、dependabot、nightly)。
