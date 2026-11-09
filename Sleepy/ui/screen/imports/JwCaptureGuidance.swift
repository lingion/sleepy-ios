import Foundation

/// School-specific recovery guidance from Android v1.0.63.
/// Keep the capture status authoritative so login and transport errors retain their diagnostics.
enum JwCaptureGuidance {
    static func navigationHint(for schoolType: String?) -> String {
        L10n.t(schoolType == JwProtocol.TYPE_THU ? "jw_nav_hint_thu" : "jw_nav_hint")
    }

    static func errorHint(for result: FrameCaptureResult, schoolType: String?, currentURL: String) -> String {
        guard result.status == .wrongPage else { return result.diagnosticHint }
        if schoolType == JwProtocol.TYPE_THU {
            return L10n.t("jw_err_thu_course_page")
        }
        if schoolType == JwProtocol.TYPE_UCAS && currentURL.contains("sep.ucas.ac.cn") {
            return L10n.t("jw_err_ucas_sep_portal")
        }
        return result.diagnosticHint
    }
}
