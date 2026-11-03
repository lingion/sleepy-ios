# Slice — UCAS + qz_ieas 教务协议层 (1.0.52 对齐)

对齐 原 commit fe389b4 (1.0.52) 的教务协议扩展: 新增 国科大选课系统(ucas) 与
强智 iEAS 网络版(qz_ieas) 两个协议 + 两校收录。

Android 源:
- `git -C ~/sleepy show fe389b4:app/src/main/java/com/lingion/sleepy/data/jw/JwUcasParser.kt`
- `git -C ~/sleepy show fe389b4:app/src/main/java/com/lingion/sleepy/data/jw/JwQzIeasParser.kt`
- diff 5f751f7b..fe389b4: JwProtocol / JwParserRegistry / JwImportViewModel / schools.json

## 入库内容

- 新增 `Sleepy/data/jw/JwUcasParser.swift` (~200 行, JwUcasParser.kt 1:1 翻译):
  - JSON 权威路径: extractCourseTimeList (跳过前导 HTML/注释找首个 `{`/`[`,
    兼容顶层 courseTimeList / data.courseTimeList / 顶层数组) →
    每项 courseName/coursePlace/courseWeek/courseTime;
    courseWeek = 周次位图 (低位=第1周), courseTime = 高位 dayBits + 低 12 位节次位图(反转)。
  - DAY_BITS hardcode {"10":1,"11":1,"100":2,"110":3,"1000":4,"1010":5,"1100":6,"1110":7}
    (ldiex/UCAS_Course_Schedule_Convertor 实测, POSITIVE 证据, 不发明新编码)。
  - HTML 回退路径: 找 thead 含「节次/星期」且含 coursetime 链接的表,
    th=节次 int, td 索引+1=星期, 同格同名去重, 周 1-16 占位;
    相邻节次同名同周域 endNode+1 链式合并 (JwCourse 字段全 let → 重建而非改)。
  - confidence()/matchedFeatures() 保留 (iOS 检测层不消费, 供对齐)。
- 新增 `Sleepy/data/jw/JwQzIeasParser.swift` (~170 行, JwQzIeasParser.kt 1:1 翻译):
  - `table#queryGrkb` 优先, 否则首表; 行 data-* 字段优先, 回退五列文本
    (课程名/教师/教室/周次/时间)。
  - parseWeeks「1-15单，17双」→ 三元组 (start,end,type), 单/双奇偶 start 对齐;
    cleanNull("null")→""; 周几正则 `周([一二三四五六日天1-7])`。
  - confidence() table#queryGrkb 命中=90。
- `JwProtocol.swift`: +TYPE_QZ_IEAS / TYPE_UCAS 常量 + displayName 两 case
  (强智教务(iEAS 网络版) / 国科大选课系统);
  category() qz 行加 TYPE_QZ_IEAS, UCAS 落 default "other" (与原实现一致)。
- `JwImportViewModel.swift`: parser 工厂 + QZ_IEAS/UCAS 两 case;
  tryAllParsers 候选表 + 两 parser (放 JwQzParser 前面, 与 Android 候选序一致);
  detectProtocolFromUrl: UCAS 锚点 (xkgo.ucas.ac.cn + /course/personschedule),
  QZ_IEAS 锚点 (/ieas2.1 / jwxt.buaa.edu.cn / jwxt-7001.e2.buaa.edu.cn),
  QZ_IEAS 必须先于通用 /kbcx/ 规则 — Android 侧同序。
- `Sleepy/resources/schools.json`: 159 → 161 校; 北航 (qz_ieas) 与 国科大 (ucas)
  按 Android 同位置同 URL 同 aliases 插入, 零格式扰动 (diff +23/−1)。
- `Sleepy.xcodeproj/project.pbxproj`: xcodegen 再生成, 两个新 parser 文件进 target。

## SwiftSoup 适配点 (Kotlin Jsoup → Swift SwiftSoup 差异)

- `Element.attr` / `Element.text()` 是 throwing → attrOf helper `(try? el.attr(k)) ?? ""`,
  text 一律 `(try? ...)` 包裹。
- `Elements` 非 Array: `(try? x.getElementsByTag(t)) ?? []` 编不过 →
  `((try? x.getElementsByTag(t)) ?? nil)?.array() ?? []`。
- `doc.select(...).first()` 可以 `try`, 裸用 OK。

## 验证

- xcodebuild -scheme Sleepy -destination 'generic/platform=iOS' build → BUILD SUCCEEDED
- rg marker/TODO/FIXME/placeholder/Truncation Junk on 4 个 jw 文件 = 0 命中
- git diff --check 干净; schools.json python json.load 校验 161 entries 有效
- Android JwClassicEamsParser 的 cleanCourseName 移除 delta:
  iOS 无 JwClassicEamsParser (iOS 教务栈没有 classic eams 协议文件), N/A 无需移植
