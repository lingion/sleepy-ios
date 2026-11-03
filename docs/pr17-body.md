# feat(watch): watchOS 伴侣 App — 日程 + 通知

## 概览

Apple Watch 伴侣 App 全链路:watchOS target/嵌入管线 → 同步契约 v2(显示口径全量镜像)→ 镜像库(三视图直读共享 DAO)→ 本地通知(调度器共享)→ 手表 App 图标 + 双端隐私清单。基于 master(widget 堆叠线)rebase,线性 12 commit。

## 同步契约 v2(sleepy-watch-sync v1 payload)

- `WatchSyncSnapshot` 单点收敛序列化/反序列化/落地,三端(iPhone / Watch App / Watch Extension)编同一份文件杜绝漂移。
- 载荷 = applicationContext JSON:`periodTables / timeTables / courses / prefs(40 字段) / holidayYears / transfers / conflictDefaultTop / …`,上限内全量镜像,**载荷是唯一真源**——apply 事务内三表清空按原 id 直插重建,幂等、无 diff。
- prefs 镜像覆盖全部显示口径(timeMode/listAlias/gridAlias/showDate/visibleDays/neutralColor/nearestBusyDay/节假日灰显×4/autoHideEvening/eveningStart/主题/语言/提醒 9 键),键名与缺省语义逐项对齐 AppPrefs;手表端不写本地键、零独有开关。
- 「已同步」回执单源:手表 apply 后 ack(sentAt)→ context `watchAck` → iPhone 落 AppPrefs → 下轮 capture 镜像回手表。

## 通知

- 调度器/实体/策略(L10n/TimeTableUtils/HolidayManager/AppDatabase 等)编入 Watch target,手表到货重查三闸语义与手机同源;通知 payload courseId 直读(镜像 id 保留 → 跨端一致)。
- 手表侧请求授权(`requestAuthorization`)后 `addNotificationRequest`。

## 三视图

- 今日(Now/Next/On)/ 周(网格化,显示口径与手机同源)/ 详情 + 设置页(提醒只读,「于 iPhone 管理」)。
- 冷启动 `requestContents` 补拉;`didReceiveApplicationContext` 接收回调对位。

## 工程

- pbxproj:Watch App/Extension target、`SleepyWatch_*` bundle id 三处、共享源排除集收口、`WatchSyncSnapshotTests` 入 CI 测试集合(6 用例绿)。
- 上架补齐:手表 App 图标资源 + iPhone/Watch 双端 Privacy Manifest。
- `PeriodHeaderLayoutModel` 移入 util 供三 target 共用。

## verify

- `xcodebuild -project Sleepy.xcodeproj -scheme Sleepy -destination 'generic/platform=iOS' build` → `** BUILD SUCCEEDED **`(本机有效签名 identity 钉定,无 profile 进产物)
- `xcodebuild -scheme "Sleepy Watch" -destination 'generic/platform=watchOS' build` → 见本 PR 评论区实况(签名/装机进行中)
- `xcodebuild test -only-testing:SleepyTests/WatchSyncSnapshotTests` → 6 passed
- 真实 iPhone + Apple Watch Series 12 配对装机验收:进行中
