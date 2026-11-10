import Foundation

/// The public calendar is fetched without the school's WebView cookies.
enum JwThuSemesterCapture {
    static let liveHtmlJs = #"""
(function() {
  var doc = win.document;
  var root = doc.documentElement.cloneNode(true);
  var live = doc.querySelectorAll('[name=p_xnxq]');
  var saved = root.querySelectorAll('[name=p_xnxq]');
  for (var i = 0; i < live.length; i++) {
    if (!saved[i]) throw new Error('semester snapshot mismatch');
    if (String(live[i].tagName).toLowerCase() === 'select') {
      for (var j = 0; j < live[i].options.length; j++) {
        if (live[i].options[j].selected) saved[i].options[j].setAttribute('selected', 'selected');
        else saved[i].options[j].removeAttribute('selected');
      }
    } else saved[i].setAttribute('value', String(live[i].value || ''));
  }
  return root.outerHTML;
})()
"""#
    static func capture(_ html: String) async throws -> String {
        try await captureWith(html) { target in
            guard let url = URL(string: target) else { throw JwParseError(message: "清华学期日历地址无效") }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
            configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 30
            configuration.urlCache = nil
            let delegate = CalendarRedirectDelegate()
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            var request = URLRequest(url: url); request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw JwParseError(message: "清华学期日历请求失败") }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 2 * 1024 * 1024 else { throw JwParseError(message: "清华学期日历响应过大") }
                data.append(byte)
            }
            guard let text = String(data: data, encoding: .utf8) else { throw JwParseError(message: "清华学期日历编码无效") }
            return text
        }
    }
    static func captureWith(_ html: String, load: (String) async throws -> String) async throws -> String {
        guard let target = JwThuCapturePayload.calendarUrl(html) else { throw JwParseError(message: "请打开清华所选学期课表后再导入") }
        return try JwThuCapturePayload.wrap(html, await load(target))
    }
}
private final class CalendarRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
