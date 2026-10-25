// LicenseScreen.swift — ← ui/screen/mine/LicenseScreen.kt
// 开源许可与致谢二级页 (v1.0.46 从 AboutScreen 分离; v1.0.50 用户令:
// 致谢按「跨校普适项目 / 按学校致谢」两类组织, 单校卡展开看明细)。
//   - 顶层: 许可证区块 + 贡献者区块(v1.0.53) + 致谢导语(可折叠, 展开看 about_license_body 全文)
//   - 跨校普适 = 单卡不可展开 (title + meta + usage 说明)
//   - 按学校 = 1 校 1 卡, 默认收起, 点击展开看该校参考的全部学生维护项目
//   - 展开态按卡片 id 记忆, 进入页面不重置 (Kotlin mutableStateMapOf)
// 布局: SettingsTopBar 返回 + ScrollView + LazyVStack (contentPadding 16dp)。

import SwiftUI

// ← FoundationalEntry / PerSchoolEntry — Kotlin 1:1, 通用标识不翻译
private struct FoundationalEntry {
    let title: String
    let meta: String
    let usage: String
}

private struct PerSchoolEntry {
    let id: String
    let title: String
    let usage: String
}

private let foundationalEntries: [FoundationalEntry] = [
    FoundationalEntry(
        title: "WakeUp 课程表 (YZune)",
        meta: "Apache-2.0",
        usage: "JwCourse / JwParser 中间结构语义与强智系 HTML 解析的参考实现"
    ),
    FoundationalEntry(
        title: "WakeupSchedule_BUPT (dIT8Zv)",
        meta: "Apache-2.0",
        usage: "十二个教务解析器的上游: 强智全家族 (qz/qz_with_node/qz_br/qz_crazy/qz_old)、老版正方、URP、青果、新正方、HNUST 与 Parser 设计"
    ),
    FoundationalEntry(
        title: "WakeupSchedule_Kotlin (YZune)",
        meta: "Apache-2.0",
        usage: "经典金智 EAMS 导入实现 (TaskActivity 位图解析) 的参考"
    ),
    FoundationalEntry(
        title: "时光课程表 cqu.js",
        meta: "",
        usage: "重庆大学门户 REST 协议 (session / 课表 / 作息三接口) 的分析依据"
    ),
    FoundationalEntry(
        title: "shiguang_warehouse (XingHeYuZhuan)",
        meta: "MIT",
        usage: "武汉理工大学 kcbcxby 协议、经典金智 EAMS (hunnu/uestc/hpu) 与新正方网格视图 (zhengfang_01) 的协议形态参考"
    ),
    FoundationalEntry(
        title: "zfn_api (openschoolcn)",
        meta: "MPL-2.0",
        usage: "新正方 jwglxt kbList 接口形态交叉验证"
    ),
    FoundationalEntry(
        title: "FlowCourse (jiaweiyaya)",
        meta: "GPL-3.0",
        usage: "新正方 kbList 主流形态与 jc 多形态交叉验证"
    ),
    FoundationalEntry(
        title: "iwut (TokenTeam)",
        meta: "AGPL-3.0 · 仅参考协议形态",
        usage: "武汉理工大学节次 DM 映射的协议佐证 (未引用代码)"
    ),
    FoundationalEntry(
        title: "「上课」shangkeschedule (qiqqqqq517)",
        meta: "Apache-2.0",
        usage: "1776 校学校登记表在名单交叉复核中的对照数据源"
    ),
]

private let perSchoolEntries: [PerSchoolEntry] = [
    PerSchoolEntry(
        id: "school-hfut", title: "合肥工业大学 HFUT",
        usage: "HFUT-Schedule (Chiu-xaH, MIT)\nHfutOpenApi (BoynChan, MIT)\nhfut_schedule_hacker (Aoi-cn)\ndjango-hfut-auth (elonzh, MIT)\nhfut-api (hfut-soft-ware)\nhfut-api (SnowingFox)\nhfut_api_service (onlineG2)\nHFUTer (BrikerMan)\nHFUTICS (ssyu0808)\nAiSchedule-for-hfut (imnuke, GPL-3.0)\nAISchedule (HualiNox)\nclassduck (luyishui)"
    ),
    PerSchoolEntry(
        id: "school-seu", title: "东南大学 SEU",
        usage: "SEUTimetable (sakimidare, Apache-2.0)\nAetik-yue/hormone (SEU SSO 入口)\nluzy99/SEUAutoLogin"
    ),
    PerSchoolEntry(
        id: "school-zju", title: "浙江大学 ZJU",
        usage: "zju-ical-py (Xecades, LGPL-2.1)"
    ),
    PerSchoolEntry(
        id: "school-ustc", title: "中国科学技术大学 USTC",
        usage: "USTC-timetable-to-ics (1970633640)\nustc-course-timetable (HowardZorn, GPL-3.0)\nustc-timetable (kirsh1, AGPL-3.0)"
    ),
    PerSchoolEntry(
        id: "school-scu", title: "四川大学 SCU",
        usage: "ScuTimetable (Z-P-J)"
    ),
    PerSchoolEntry(
        id: "school-neu", title: "东北大学 NEU",
        usage: "neu_wisedu2wakeup (CreamPig233)\nPopulusYang/NeuTimetable\nneucn/elise\nRekaYOO/NEU-JWXT-Toolkit\nPeterPtroc/neu-jwxt-to-wakeup\nleavesvv-source/NEU-Timetable"
    ),
    PerSchoolEntry(
        id: "school-cqu", title: "重庆大学 CQU",
        usage: "时光课程表 cqu.js (茵符草)\n321CQU/pymycqu\nBillYang2016/CQU-class2ics\nhaowang02/CourseMonitor\nLengerHu/CQU_classtabletoics\nHagb/cqu_timetable_new\nVayneDuan/CQU-Grade-Monitor\nweearc/cm-http-api\nbarryZZJ/course_to_calander_converter"
    ),
    PerSchoolEntry(
        id: "school-whut", title: "武汉理工大学 WHUT",
        usage: "courseTable (acm910)"
    ),
    PerSchoolEntry(
        id: "school-uestc", title: "电子科技大学 UESTC",
        usage: "MilLoong/UESTC-EAMS-Helper-App\nMilLoong/UESTC-EAMS-Helper-Python\nKaranocaVe/UESTCJWCWatchdog\nwhtsky/uestc-eams-cleartimeout-userscript\nSunmxt/UESTC-EAMS"
    ),
    PerSchoolEntry(
        id: "school-gdut", title: "广东工业大学 GDUT",
        usage: "N0tExpectErr0r/GDUT-ClassTimeTable\nRichard-Zheng/GDUT-Schedule-ng\nStarArchive/gdut-course-frontend\nStarArchive/gdut-course-backend\nHoneQ7/GDUT_iOS_Timetable"
    ),
    PerSchoolEntry(
        id: "school-gdufe", title: "广东财经大学 GDUFE",
        usage: "jkgeekJack/Android-GDUFE-JWC-SDK-1.0.0\nKiteio/GDUFE-wrapper"
    ),
    PerSchoolEntry(
        id: "school-gduf", title: "广东金融学院 GDUf",
        usage: "Kiteio/Punica\ngduf-finmind"
    ),
    PerSchoolEntry(
        id: "school-gdufs", title: "广东外语外贸大学 GDUFS",
        usage: "yongjianzheng/Gdufszhushou\nCrazioker/agency"
    ),
    PerSchoolEntry(
        id: "school-gdmu", title: "广东医科大学 GDMU",
        usage: "用户采集包实锤 zf_new 协议形态 (新正方 zftal-ui-v5 裸 /kbcx/ 路径), 参见 docs/release-notes-v1.0.49.md"
    ),
    PerSchoolEntry(
        id: "school-csust", title: "长沙理工大学 CSUST",
        usage: "zHElEARN/CSUSTKit\nCreaMakers/EduSpider\ntimeisthe/CSUSTDataGet\nJulius-lq/EduAdminSystem\nJS-CAUTION/csust-course-schedule"
    ),
    PerSchoolEntry(
        id: "school-bupt", title: "北京邮电大学 BUPT",
        usage: "helium777/bupt-course-grab\nJmPotato/BUPT-Grader\nSeizzzz/Auto-Login-BUPT"
    ),
    PerSchoolEntry(
        id: "school-pku", title: "北京大学 PKU",
        usage: "zhongxinghong/PKUAutoElective\nthezzisu/pku-elective\nHovennnnn/PKUAutoElective2023\nLihhan/AutoElective_4_PKU\nAuYang261/PKU_Elective_Toolset"
    ),
    PerSchoolEntry(
        id: "school-buct", title: "北京化工大学 BUCT",
        usage: "MarkYangKp/ZhengFangJY"
    ),
    PerSchoolEntry(
        id: "school-ucas", title: "中国科学院大学 UCAS",
        usage: "ldiex/UCAS_Course_Schedule_Convertor\nHurray0/UCAS_GET_Course\ncld378632668/ucas_course_tool\nGentleCP/UCAS-Helper\nwirsbf/TraintimePda-UCAS\ntbjuechen/sep-api"
    ),
    PerSchoolEntry(
        id: "school-bjfu", title: "北京林业大学 BJFU",
        usage: "Bloomberg2000/bjfu_course_ics_generator\nBloomberg2000/bjfu_util.py"
    ),
    PerSchoolEntry(
        id: "school-ahu", title: "安徽大学 AHU",
        usage: "Tonyseth/AHU_JW_GPA_Calculator\nAhu_Plus (abydym, GPL-3.0)"
    ),
    PerSchoolEntry(
        id: "school-nefu", title: "东北林业大学 NEFU",
        usage: "bboy-xp/nefu-crawler\nheyMahalo/crouse_select"
    ),
    PerSchoolEntry(
        id: "school-dhu", title: "东华大学 DHU",
        usage: "tk.dcmmcc\nBad-086/DHU_CourseMonitor"
    ),
    PerSchoolEntry(
        id: "school-ynufe", title: "云南财经大学 YNUFE",
        usage: "NINIYOYYO/ynufe-campus-app\nMiaoWuNYA/ynufeRealLogin"
    ),
    PerSchoolEntry(
        id: "school-bit", title: "北京理工大学 BIT",
        usage: "BIT-Login (BIT101-dev)"
    ),
    PerSchoolEntry(
        id: "school-bistu", title: "北京信息科技大学 BISTU",
        usage: "iBistu (ProjektMing)"
    ),
    PerSchoolEntry(
        id: "school-ahujz", title: "安徽建筑大学 AHU-JZ",
        usage: "JdaAssist (CH4019, MIT)"
    ),
    PerSchoolEntry(
        id: "school-cqytu", title: "重庆邮电大学移通学院 CQYTU",
        usage: "CQYTZFCheckScores (xM3GAN, Apache-2.0)"
    ),
    PerSchoolEntry(
        id: "school-scau", title: "华南农业大学 SCAU",
        usage: "ScheduleXParser_SCAU (greyovo)"
    ),
    PerSchoolEntry(
        id: "school-qlu", title: "齐鲁工业大学 QLU",
        usage: "JW-spider (Zhy423310825)"
    ),
    PerSchoolEntry(
        id: "school-bhu", title: "渤海大学 BHU",
        usage: "BohaiServiceDome (joun233)"
    ),
    PerSchoolEntry(
        id: "school-nepu", title: "东北石油大学 NEPU",
        usage: "WeNEPU (cutiechi)"
    ),
    PerSchoolEntry(
        id: "school-nust", title: "南京理工大学 NUST",
        usage: "HeraldStudentCurriculum (idailylife)"
    ),
    PerSchoolEntry(
        id: "school-buaa-byxt", title: "北京航空航天大学 byxt (2026-09)",
        usage: "fontlos/buaa-api (Rust, MIT)\nBUAASubnet/UBAA (Kotlin, MIT)\nCoolwindHF/buaa2wakeup (Python, MIT)\nawesome-buaa-cs/buaa-curriculum (API.md 旁证)\ncantBeFoundGroup/OpenBUAA (Python)\nel-ev/BUAA-ics-gen (Python, MIT)\nKrignd/KAgenda (Kotlin)\nYiki21/iclass_buaa_tui (Rust, GPL-3.0)\nLidozs55/BUAAer-Smart-Schedule-on-electron (Vue)\nWhXcjm/buaa-byxt-aischedule (JS, GPL-3.0)\nMeanZhang/buaa-ai-schedule (JS, MIT, archived)\nAlyssumira/BUAA-Schedule (Kotlin, MIT)\nlyy1119/BuaaScheduleRender (Go, MIT, GSMIS 研究生形态参考)\nzjafb/BUAA-Hangzhou-Schedule (MIT, UBAA fork, 杭州校区旁证)"
    ),
    PerSchoolEntry(
        id: "school-bjtu", title: "北京交通大学 BJTU",
        usage: "bjtu_mis_Android (wan300, MIT)\nBJTU-MIS-HarmonyOS (Anyes666, MIT)\nBJTUselfService (HFDLYS, MIT)\nbjtu-cli (fish2lab)\nBJTUselfService-macOS (fish2lab)\nBJTU-course-assistant (s1y4x1)\nZiuChen/userscript (MIT)\nBJTU-iCalendar-Generator (ymzhang-cs, MIT)\nbjtu-timetable (Moliseeee)\nBJTU-course-autoget-program (hyskr)\nBjtuCoursePlatform (57Darling02)\nbjtuDean (jlytwhx, MIT)\nbjtubox_python (jlytwhx)\nCampus-Mate (Orien233)\nBJTU-STU-MCP (ymzhang-cs)\nCourseRobber (xschur)\nFuturemind-BJTU\nBJTU_ezRate (Yukikasu, MIT)\nbjtu_teaching_assessment (xxxand, MIT)\nBJTU-script (Coconut00)\nBJTU-CC (aooxin)\nCourseTable (etherealviator, MIT)\nZF-Assistant (mcdona1d)\nGreasy Fork 430918 北交大iCalender课表生成"
    ),
    PerSchoolEntry(
        id: "school-jou", title: "江苏海洋大学 JOU",
        usage: "酱海带 jianghaidai (sunjingquan, 闭源参考, 仅协议分析未复用)\nJOU-Campus-Guide (sunjingquan)\njou_course_bot (brodamndamn)\nWehhit-server (dengjj)\nWehhit (zqy1)\nGrain (LeeReindeer, 浙江海洋大学, GPL-3.0)\n家庭记账系统 finance (GeorgeLeoo)\nfinance-server (GeorgeLeoo)\nJStore (GeorgeLeoo)\nRSSHub jou 路由 (RSSHub, MIT)"
    ),
    PerSchoolEntry(
        id: "school-ysu", title: "燕山大学 YSU",
        usage: "LzBsA (github.com/LzBsA, boya_pp 协议适配原始提交, PR 复活)\nqnxg/hnu_query (qnxg, AGPL-3.0)\nqnxg/weihuda_backend (qnxg)\nheriec/suda-yjs-shedule (heriec)\ndlutor/chaoxingbook (dlutor, MIT)"
    ),
    PerSchoolEntry(
        id: "school-swjtu", title: "西南交通大学 SWJTU",
        usage: "AmaneSuzuha000/SWJTU_Login (YHXT CAS + ytoken cookie + common API 直接证据)\n1-nuo/swjtu-course-grabber (ytoken 请求头 + JWT sub 学号 + SM2 选课加密)\nArex-lbb/auto-course-grabber (JWT + SM2 + A0422 失效码)\n1837634311/SWJTU-Course-Management-Script (GPL-3.0, TMS/vatuu 反向证据)\nHackSwjtu/Postime (MIT, 老教务网反向证据)\nlpzams/swjtu-course-crawler (旧 vatuu 反向证据)\n949144093/SWJTU-JiaoWuAutoLogin (旧 vatuu 反向证据)\nkakasearch/course_download (旧 vatuu 反向证据)\nzx1411057234/VatuuSpider (旧 vatuu 反向证据)\nkashaku/no-vatuu-evaluation (旧 vatuu 反向证据)\nJoe-create-star/swjtu-dektx-reminder (MIT, OCW/YETHAN 多租户旁证)"
    ),
    PerSchoolEntry(
        id: "school-wakeup-family", title: "WakeUp 兼容协议族调研",
        usage: "Dawn-Course (HF-CYGG, GPL-3.0)\nWakeUp_SHU (ershiyidian)\nCourseHelper (jiangyiqi99, GPL-3.0)\naischedule-lit-kingosoft (icepie, MIT)\nXiaoAISchedule_hebust (web1n)\nai-schedule-chaoxing (moeshin, MIT)\ntzvcst-schedule-chaoxing (Sittymin, AGPL-3.0)\nxiaoai-shuwei-course (ZKJJaker, 反向证据)\njxufe-auto-evaluate (wzj1122, MIT)\nKINGOSOFT-LOGIN (52funny)\nxiaoaiSchedule (xiaxiaoyu8)\nmi-schedule (Kou-JunHao, MIT)\nAISchedule-xjsf (ltxhhz, MIT)\nAIScheduleSCAU (greyovo)\nMI_AI_Course_Schedule (ceresOPA)\nAISchedule-QiangZhi (MyLikeGirl)\nclasspush (sungithub270, GPL-3.0)\nXiaoAiScheduleOfSUOT (trueWangSyutung)\nXiaoAiCurriculumSchedule (LukeJean)\ngetICS (Konata09)\nWITClassScheduleToCalendar (DOROMOLLL, MIT)\nCrawlerCourseTable (canliture)\nSYU_KINGGOClassSel (XTAI9)\nhait_AICourseTable (zzzsq1)\nAIShedule_cqwu (cqwu-ehall, AGPL-3.0)\nWakeUpSchedule (Daydream357, MIT)\nshike-android (sw7943604-del)\nshiguang_Tester (XingHeYuZhuan, MIT)\ndutsso (yuanyuanzijin)\npub-docs (zfman, 青果接口文档)\neduData-GoBack (huhu415)\nNUISTTable (zyc-816)\nSCAU-Grad-Automatically-Fill-Evaluation-Form-JS (jiefing, Gwork 族控件命名旁证)"
    ),
    PerSchoolEntry(
        id: "school-four-school-jw", title: "四校教务协议交叉验证（2026-09）",
        usage: "NWUPL: dream2333/NWUPL-Pure-EMS (间接协议旁证)\nLIXIN: classic EAMS 采集形态（未复制代码）\nKMUST: linling-zy/kust-schedule (间接协议旁证, Apache-2.0)\nNUIT: 3056810551/nuit-class-schedule (直接字段旁证, 未复制代码)"
    ),
    PerSchoolEntry(
        id: "school-hzcu", title: "浙大城市学院 HZCU",
        usage: "用户采集包实锤 zf_new 协议 (新正方 zftal-ui-v5 裸 /kbcx/ 路径, SSO /sso/ddlogin 专用入口, issue #90)\nqiqqqqq517/shangkeschedule (Apache-2.0, 该校 zhengfang_new 条目互证)\nXu-Jack11/MySchedule (MIT, 同端点直接旁证)\nLanternCX/HZCUCourseChoose (MIT, 选课端点旁证)"
    ),
]

// ← ContributorEntry — Kotlin 1:1, 姓名/handle 通用标识不翻译
private struct ContributorEntry {
    let id: String
    let title: String
    let meta: String
    let usage: String
}

// 贡献者: 直接向本项目提交代码并合入的开发者 (与"上游参考仓库"致谢是两回事)。
// v1.0.53 用户令: 收录 PR #29 作者 jim139129 (NEU 教务导入修复)。
// v1.0.57 用户令: 收录 YYiChen (PR #43 课表自适应高度 + PR #48 前一晚明日预告)、
//                  LzBsA (PR #30 燕山大学研究生 boya_pp 协议,虽 PR 已 CLOSED 但 commit
//                  `1a0b78d4` 走 contributor-preserving merge `2b0a9119` 保留作者落 main)。
// Cold577 (PR #79 小组件选择器预览图修复) 同期收录。
// 贡献描述沿用本页硬编码中文说明的既有模式 (Kotlin 同为硬编码, 非资源键)。
private let contributorEntries: [ContributorEntry] = [
    ContributorEntry(
        id: "contributor-jim139129", title: "jim139129", meta: "GitHub @jim139129",
        usage: "已合并多项 PR 并持续反馈 issue — 全部提交与讨论记录见 github.com/jim139129"
    ),
    ContributorEntry(
        id: "contributor-YYiChen", title: "YYiChen", meta: "GitHub @YYiChen",
        usage: "已合并 PR #43 课表自适应高度、PR #48 前一晚明日预告 — 全部提交与讨论记录见 github.com/YYiChen"
    ),
    ContributorEntry(
        id: "contributor-LzBsA", title: "LzBsA", meta: "GitHub @LzBsA",
        usage: "已合并 PR #30 燕山大学研究生平台 boya_pp 协议适配 (贡献者保留式 merge) — 全部提交与讨论记录见 github.com/LzBsA"
    ),
    ContributorEntry(
        id: "contributor-Cold577", title: "冷冷冷 Cold577", meta: "GitHub @Cold577",
        usage: "已合并 PR #79 小组件选择器预览图修复 (运行时位图容器 previewLayout 摘除) — 全部提交与讨论记录见 github.com/Cold577"
    ),
]

struct LicenseScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let onDismiss: () -> Void
    // ← mutableStateMapOf: 展开态按 id 记忆, 进入页面不重置
    @State private var expanded: [String: Bool] = [:]
    @State private var bodyExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("license_page_title"), onBack: onDismiss)
            ScrollView {
                LazyVStack(spacing: 12) {
                    // ---- 许可证区块 ----
                    LicenseCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.format("license_gpl_section"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colors.onSurface)
                            Text(L10n.format("license_gpl_body"))
                                .font(.system(size: 14))
                                .foregroundColor(colors.onSurfaceVariant)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // ---- 贡献者区块 (直接向本项目提交代码并合入的开发者, 与上游参考仓库致谢区分) ----
                    SectionHeader(L10n.format("license_contributor_section"))
                    ForEach(contributorEntries, id: \.id) { e in
                        AttributionCard(
                            title: e.title,
                            subtitle: e.meta,
                            description: e.usage,
                            lines: nil,
                            expanded: false,
                            onToggle: nil)
                    }

                    // ---- 致谢导语区块 (可折叠: 展开看 about_license_body 全文) ----
                    LicenseCard {
                        VStack(alignment: .leading, spacing: 0) {
                            // ← Android: 整个头部 Row .clickable 切换 + 尾部 IconButton (两处都可点)
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L10n.format("license_attribution_section"))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(colors.onSurface)
                                    Text(L10n.format("license_attribution_note"))
                                        .font(.system(size: 14))
                                        .foregroundColor(colors.onSurfaceVariant)
                                }
                                Spacer()
                                Button {
                                    withAnimation { bodyExpanded.toggle() }
                                } label: {
                                    Image(systemName: bodyExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 24)) // ← Android IconButton 内 Icon 默认 24dp
                                        .foregroundColor(colors.onSurfaceVariant)
                                        .frame(width: 36, height: 36)
                                }
                                .buttonStyle(SleepyButtonStyle())
                                .accessibilityLabel(bodyExpanded ? "collapse" : "expand")
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation { bodyExpanded.toggle() }
                            }
                            if bodyExpanded {
                                Text(L10n.format("about_license_body"))
                                    .font(.system(size: 12))
                                    .foregroundColor(colors.onSurfaceVariant)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 8)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // ---- 跨校普适项目 ----
                    SectionHeader(L10n.format("license_foundational_section"))
                    ForEach(foundationalEntries, id: \.title) { e in
                        AttributionCard(
                            title: e.title,
                            subtitle: e.meta,
                            description: e.usage,
                            lines: nil,
                            expanded: false,
                        onToggle: nil)
                    }

                    // ---- 按学校致谢 (可展开, 展开态按 id 记忆) ----
                    SectionHeader(L10n.format("license_perschool_section"))
                    ForEach(perSchoolEntries, id: \.id) { e in
                        AttributionCard(
                            title: e.title,
                            subtitle: nil,
                            description: nil,
                            lines: e.usage.components(separatedBy: "\n"),
                            expanded: expanded[e.id] ?? false,
                            onToggle: {
                                withAnimation { expanded[e.id] = !(expanded[e.id] ?? false) }
                            })
                    }

                }
                .padding(16) // ← Android LazyColumn contentPadding 16dp(末尾无额外 Spacer)
            }
        }
        .background(colors.background)
    }

    // ← SectionHeader: 分区标题 (titleSmall semibold primary, start 4 / top 8 / bottom 4)
    private func SectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(colors.primary)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }

    // ← AttributionCard: 顶层致谢卡 (跨校=不可展开, 单校=可展开)
    private struct AttributionCard: View {
        @Environment(\.localWakeUpColors) private var colors
        let title: String
        let subtitle: String?
        let description: String?
        let lines: [String]?
        let expanded: Bool
        let onToggle: (() -> Void)?

        var body: some View {
            LicenseCard {
                VStack(alignment: .leading, spacing: 6) {
                    if let onToggle = onToggle {
                        Button(action: onToggle) { row }
                            .buttonStyle(SleepyButtonStyle())
                    } else {
                        row
                    }
                    if onToggle == nil, let d = description, !d.isEmpty {
                        Text(d)
                            .font(.system(size: 14))
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                    if expanded, let lines = lines {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 12))
                                    .foregroundColor(colors.onSurfaceVariant)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        private var row: some View {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.onSurface)
                    if let s = subtitle, !s.isEmpty {
                        Text(s)
                            .font(.system(size: 12))
                            .foregroundColor(colors.primary)
                    }
                }
                Spacer()
                if onToggle != nil {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 24)) // ← Android IconButton 内 Icon 默认 24dp
                        .foregroundColor(colors.onSurfaceVariant)
                    // ← Android contentDescription = collapse/expand
                        .accessibilityLabel(expanded ? "collapse" : "expand")
                }
            }
        }
    }

    // ← LicenseCard: 本页专用卡 (Android 显式 RoundedCornerShape(20dp) + padding 16dp)
    private struct LicenseCard<Content: View>: View {
        @Environment(\.localWakeUpColors) private var colors
        @ViewBuilder let content: () -> Content

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surfaceContainer)
            .cornerRadius(20)
        }
    }
}
