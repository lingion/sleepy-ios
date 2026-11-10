import Foundation

/// Exact Android v1.0.63 SEU variant of the shared Wisedu fetch script.
/// The gateway root is valid, and #dqxnxq2 in the page or a same-origin iframe
/// carries the user's selected term even when the API still marks an older term current.
enum JwSeuFetchJs {
    static func script(for schoolType: String?) -> String? {
        schoolType == JwProtocol.TYPE_SEU ? js : nil
    }

    static let js = WiseduFetchJs.js
        .replacingOccurrences(
            of: "var pathOk = location.pathname.indexOf('/jwapp/') >= 0;",
            with: "var pathOk = location.pathname.indexOf('/jwapp/') >= 0 || location.hostname.toLowerCase() === 'ehall.seu.edu.cn';")
        .replacingOccurrences(
            of: "var selects = document.querySelectorAll('select');",
            with: """
            var selected = document.querySelector('#dqxnxq2');
                  if (!selected) {
                    var frames = document.querySelectorAll('iframe');
                    for (var fi = 0; fi < frames.length && !selected; fi++) {
                      try { selected = frames[fi].contentDocument.querySelector('#dqxnxq2'); }
                      catch(e) { /* cross-origin frame cannot expose its selected term */ }
                    }
                  }
                  var selectedCode = selected && (selected.value || selected.getAttribute('value'));
                  if (selectedCode) xnxq = String(selectedCode);
                  var selects = document.querySelectorAll('select');
            """)
}
