import XCTest
@testable import Sleepy

/// 1.0.62 崩溃修复回归 — 锁死 SharePresentationGate 的转场忙判定与重试终止。
///
/// 崩溃复盘(iPhone8,2 / iOS 15.8.8, Last Exception Backtrace 全在 UIKitCore
/// `_applyBlocks:releaseBlocks:` → `_presentViewController`): 旧版 JwCaptureDump.share()
/// 爬 presentedViewController 链拿到最顶 sheet 宿主后直接 present; 该宿主正处于
/// 自己的 presentation 动画时, UIKit 在转场完成回调里抛 NSInvalidArgumentException。
///
/// share() 本体依赖真机 UIApplication/UIViewController, 无法在此直测;
/// 故把「能否 present」与「重试是否耗尽」抽成纯函数 gate, 这里全量覆盖真值表。
/// 门逻辑一旦被改坏(漏判某个忙信号 / 上限归零导致死循环), 本组测试即失败。
final class JwCaptureDumpShareGateTests: XCTestCase {

    // MARK: - mustWait: 四信号忙判定真值表

    /// 全空闲(挂窗、无转场、未呈现/未消失)→ 可直接 present(mustWait=false)。
    func testIdleHostAllowsPresent() {
        XCTAssertFalse(
            SharePresentationGate.mustWait(isBeingPresented: false,
                                           isBeingDismissed: false,
                                           hasTransitionCoordinator: false,
                                           hasWindow: true))
    }

    func testBeingPresentedMustWait() {
        XCTAssertTrue(
            SharePresentationGate.mustWait(isBeingPresented: true,
                                           isBeingDismissed: false,
                                           hasTransitionCoordinator: false,
                                           hasWindow: true))
    }

    func testBeingDismissedMustWait() {
        XCTAssertTrue(
            SharePresentationGate.mustWait(isBeingPresented: false,
                                           isBeingDismissed: true,
                                           hasTransitionCoordinator: false,
                                           hasWindow: true))
    }

    /// transitionCoordinator 非空即当前有并行动画 — 这正是崩溃命中态, 必须等待。
    func testActiveTransitionCoordinatorMustWait() {
        XCTAssertTrue(
            SharePresentationGate.mustWait(isBeingPresented: false,
                                           isBeingDismissed: false,
                                           hasTransitionCoordinator: true,
                                           hasWindow: true))
    }

    /// 未挂窗是防御项: 视图没进 window, present 无意义, 一律等待。
    func testNoWindowMustWait() {
        XCTAssertTrue(
            SharePresentationGate.mustWait(isBeingPresented: false,
                                           isBeingDismissed: false,
                                           hasTransitionCoordinator: false,
                                           hasWindow: false))
    }

    /// 穷举 16 种组合: 只要任一忙信号为真(含 hasWindow=false), mustWait 必为真;
    /// 唯一 false 的是「全空闲且已挂窗」。防止 gate 逻辑漏判或被误改成短路。
    func testTruthTableExhaustive() {
        for presented in [false, true] {
            for dismissed in [false, true] {
                for coordinator in [false, true] {
                    for window in [false, true] {
                        let busy = presented || dismissed || coordinator
                        let wantWait = !window || busy
                        let got = SharePresentationGate.mustWait(
                            isBeingPresented: presented,
                            isBeingDismissed: dismissed,
                            hasTransitionCoordinator: coordinator,
                            hasWindow: window)
                        XCTAssertEqual(got, wantWait,
                                       "presented=\(presented) dismissed=\(dismissed) " +
                                       "coordinator=\(coordinator) window=\(window)")
                    }
                }
            }
        }
    }

    // MARK: - shouldGiveUp: 重试必然终止

    /// 上限内(含首帧 attempts=0)一律不放弃 → 走重试路径。
    func testBelowLimitKeepsRetrying() {
        for a in 0..<SharePresentationGate.maxAttempts {
            XCTAssertFalse(SharePresentationGate.shouldGiveUp(attempts: a),
                           "attempts=\(a) 应继续重试")
        }
    }

    /// 达到上限即放弃 — 保证递归必然终止, 不死循环。
    func testAtLimitGivesUp() {
        XCTAssertTrue(SharePresentationGate.shouldGiveUp(attempts: SharePresentationGate.maxAttempts))
        XCTAssertTrue(SharePresentationGate.shouldGiveUp(attempts: SharePresentationGate.maxAttempts + 1))
    }

    /// 节奏参数护栏: 上限必须为正、间隔必须为正 — 归零会让 present 永远进不来或空转打满 CPU。
    func testRetryParametersAreSane() {
        XCTAssertGreaterThan(SharePresentationGate.maxAttempts, 0)
        XCTAssertGreaterThan(SharePresentationGate.retryInterval, 0)
        // 20 次 × 50ms ≈ 1s: 覆盖 sheet 呈现动画(~0.3–0.5s)且不拖垮分享体验。
        XCTAssertLessThanOrEqual(
            Double(SharePresentationGate.maxAttempts) * SharePresentationGate.retryInterval,
            1.5)
    }
}
