import XCTest
@testable import Sleepy

/// DiagDumpProgress 进度模型镜像测试 — 1:1 移植 Android
/// app/src/test/java/com/lingion/sleepy/ui/screen/imports/DiagDumpProgressTest.kt
/// (2026-09-21: 导出排查全量包必须有原子步骤进度+百分比, 禁止无止境"正在生成"黑箱)。
///
/// 锁 6 条契约: ①9 段枚举顺序=管线真实采集序 ②起始段 0%
/// ③percent 单调不减 ④终段完成=100% ⑤计数器超进钳位 100 ⑥totalCount=0 除零守卫。
final class DiagDumpProgressTests: XCTestCase {

    // MARK: - 契约 1: 管线声明 9 个原子段, 顺序 = 真实采集序

    func testPipelineDeclaresNineAtomicStagesInRealCaptureOrder() {
        // 顺序 = exportDiagnosticDump 真实管线: JS 现抓三段 → 网络快照 →
        // 网络重放 → 资源重取 → Cookie → 打包 → 保存分享
        XCTAssertEqual(
            ["domInventory", "storage", "links",
             "networkSnapshot", "networkReplay", "resourceReplay",
             "cookies", "zipAssembly", "saveShare"],
            DumpStage.allCases.map { String(describing: $0) }
        )
        XCTAssertEqual(9, DumpStage.allCases.count)
    }

    // MARK: - 契约 2: 起始段报 0%

    func testStartingStageReportsZeroPercent() {
        let p = DiagDumpProgress(stage: .domInventory,
                                 stepsDone: DumpStage.allCases.firstIndex(of: .domInventory)!)
        XCTAssertEqual(0, p.percent)
    }

    // MARK: - 契约 3: percent 随阶段推进单调不减

    func testPercentIsMonotonicAcrossStageAdvancement() {
        var last = -1
        for (index, stage) in DumpStage.allCases.enumerated() {
            let begin = DiagDumpProgress(stage: stage, stepsDone: index)
            let done = DiagDumpProgress(stage: stage, stepsDone: index + 1)
            XCTAssertGreaterThanOrEqual(begin.percent, last, "begin(\(stage)) 不得倒退")
            XCTAssertGreaterThanOrEqual(done.percent, begin.percent,
                                        "done(\(stage)) 必须不小于 begin")
            last = done.percent
        }
    }

    // MARK: - 契约 4: 终段完成 = 100%

    func testFinalStageCompletionReports100Percent() {
        let last = DumpStage.allCases.last!
        let done = DiagDumpProgress(stage: last, stepsDone: DumpStage.allCases.count)
        XCTAssertEqual(100, done.percent)
    }

    // MARK: - 契约 5: 计数器超进钳位 100, 不出现 120% 荒唐值

    func testPercentNeverExceeds100EvenIfCounterOverruns() {
        // 防御: 计数器被重复推进时百分比钳在 100
        let p = DiagDumpProgress(stage: .saveShare, stepsDone: DumpStage.allCases.count + 5)
        XCTAssertEqual(100, p.percent)
    }

    // MARK: - 契约 6: totalCount=0 除零守卫

    func testZeroTotalIsGuardedAgainstDivisionByZero() {
        XCTAssertEqual(0,
                       DiagDumpProgress(stage: .domInventory, stepsDone: 0, totalCount: 0).percent)
    }

    // MARK: - iOS 侧 stepIndex 钳位 (跨端展示一致契约)
    // iOS 流程在 SaveShare 完成时发 stepsDone = 9 (Android 侧 last entering() 后
    // UI 裸值最高 "9/9"), stepIndex 钳到 totalCount 后两端同为 "步骤 9/9"。

    func testStepIndexClampsToTotalAtCompletion() {
        let p = DiagDumpProgress(stage: .saveShare, stepsDone: DumpStage.allCases.count)
        XCTAssertEqual(9, p.stepIndex)
        XCTAssertEqual(DumpStage.allCases.count, p.stepIndex)
    }

    func testStepIndexIsOneBasedMidPipeline() {
        let p = DiagDumpProgress(stage: .networkSnapshot, stepsDone: 3)
        XCTAssertEqual(4, p.stepIndex)
    }
}
