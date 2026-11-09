import XCTest
@testable import Sleepy

final class JwCaptureGuidanceTests: XCTestCase {
    private func result(_ status: FrameCaptureStatus, hint: String = "original diagnostic") -> FrameCaptureResult {
        FrameCaptureResult(selectedFramePath: nil, html: "", matchedAnchors: [],
                           status: status, diagnosticHint: hint)
    }

    func testThuNavigationNamesOverallTimetableAndOtherSchoolsKeepGenericHint() {
        XCTAssertEqual(JwCaptureGuidance.navigationHint(for: JwProtocol.TYPE_THU),
                       L10n.t("jw_nav_hint_thu"))
        XCTAssertEqual(JwCaptureGuidance.navigationHint(for: JwProtocol.TYPE_UCAS), L10n.t("jw_nav_hint"))
        XCTAssertEqual(JwCaptureGuidance.navigationHint(for: JwProtocol.TYPE_SEU), L10n.t("jw_nav_hint"))
        XCTAssertEqual(JwCaptureGuidance.navigationHint(for: nil), L10n.t("jw_nav_hint"))
    }

    func testPortalFrameActuallyClassifiesWrongPageThenGetsThuRecoveryRoute() throws {
        let fixture = #"{"ok":true,"url":"https://zhjwxk.cic.tsinghua.edu.cn/","depth":8,"frames":[{"name":"(top)","src":"https://zhjwxk.cic.tsinghua.edu.cn/","depth":0,"path":[],"html":"<html><body><h1>选课系统</h1><a href='overall'>整体课表</a></body></html>","blocked":""}]}"#
        let captured = FrameTraversalTree.selectBestFrame(FrameSnapshotList.fromJson(fixture))
        XCTAssertEqual(captured.status, .wrongPage)
        XCTAssertEqual(JwCaptureGuidance.errorHint(for: captured, schoolType: JwProtocol.TYPE_THU,
                                                  currentURL: "https://zhjwxk.cic.tsinghua.edu.cn/"),
                       L10n.t("jw_err_thu_course_page"))
        XCTAssertNotEqual(JwCaptureGuidance.errorHint(for: captured, schoolType: JwProtocol.TYPE_THU,
                                                     currentURL: "https://zhjwxk.cic.tsinghua.edu.cn/"),
                          captured.diagnosticHint)
    }

    func testThuRecoveryDoesNotReplaceOtherCaptureDiagnostics() {
        let statuses: [FrameCaptureStatus] = [.ok, .emptySemester, .sessionExpired,
            .crossDomainIframeBlocked, .containerEmptyAfterDelay, .iframeNavPending, .unknown]
        for status in statuses {
            let captured = result(status)
            XCTAssertEqual(JwCaptureGuidance.errorHint(for: captured, schoolType: JwProtocol.TYPE_THU,
                                                       currentURL: "https://zhjwxk.cic.tsinghua.edu.cn/"),
                           captured.diagnosticHint)
        }
    }

    func testUcasPortalAndGenericFailureRoutesRemainIntact() {
        let captured = result(.wrongPage)
        XCTAssertEqual(JwCaptureGuidance.errorHint(for: captured, schoolType: JwProtocol.TYPE_UCAS,
                                                   currentURL: "https://sep.ucas.ac.cn/"),
                       L10n.t("jw_err_ucas_sep_portal"))
        XCTAssertEqual(JwCaptureGuidance.errorHint(for: captured, schoolType: JwProtocol.TYPE_UCAS,
                                                   currentURL: "https://xkgo.ucas.ac.cn/"),
                       captured.diagnosticHint)
        XCTAssertEqual(JwCaptureGuidance.errorHint(for: captured, schoolType: JwProtocol.TYPE_SEU,
                                                   currentURL: "https://sep.ucas.ac.cn/"),
                       captured.diagnosticHint)
        XCTAssertEqual(JwCaptureGuidance.errorHint(for: captured, schoolType: nil,
                                                   currentURL: "https://sep.ucas.ac.cn/"),
                       captured.diagnosticHint)
    }

    func testAllFiveTranslationsMatchTheAndroid1063Guidance() throws {
        let expected: [(String, String, String)] = [
            ("zh-Hans", "导航到选课系统「整体课表」页，选好学期后点「导入此页」",
             "尚未检测到清华大学「整体课表」的课程脚本。请登录选课系统、打开「整体课表」、选好学期后再点「导入此页」"),
            ("zh-Hant", "導航到選課系統「整體課表」頁，選好學期後點「匯入此頁」",
             "尚未偵測到清華大學「整體課表」的課程腳本。請登入選課系統、開啟「整體課表」、選好學期後再點「匯入此頁」"),
            ("en", "Open the course system’s Overall Timetable, select the semester, then tap Import This Page",
             "No THU Overall Timetable course script was found. Sign in, open Overall Timetable, select the semester, then tap Import This Page."),
            ("ja", "履修システムの「全体時間割」を開き、学期を選んでから「このページを取り込む」をタップ",
             "清華大学の「全体時間割」の授業スクリプトが見つかりません。ログインし、全体時間割を開いて学期を選び、再度取り込んでください。"),
            ("es", "Abra el horario general en el sistema de cursos, elija el semestre y toque Importar esta página",
             "No se encontró el script de cursos del horario general de THU. Inicie sesión, abra el horario general, elija el semestre y toque Importar esta página.")
        ]
        for (language, navigation, failure) in expected {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(NSLocalizedString("jw_nav_hint_thu", bundle: bundle, comment: ""), navigation)
            XCTAssertEqual(NSLocalizedString("jw_err_thu_course_page", bundle: bundle, comment: ""), failure)
        }
    }
}
