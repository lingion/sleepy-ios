// 南开 / 宁波城市职业技术学院：Android v1.0.63 ClassicEamsWebVpn 形态 B。
// 只抓取同源原文，不在 JS 解码课程；JwClassicEamsParser 为唯一解析落点。
import Foundation

enum JwClassicEamsFetch {
    static let idsPattern = #"addInput\(\s*form\s*,\s*["']ids["']\s*,\s*["'](\d+)["']"#
    static let semesterPattern = #"semesterCalendar\(\{[^}]*value\s*:\s*["'](\d+)["']"#
    static let actionPath = "courseTableForStd!courseTable.action"
    static let entryPath = "courseTableForStd.action"

    static func initialDesktopUa(_ school: JwSchoolInfo) -> Bool {
        guard school.type == JwProtocol.TYPE_CLASSIC_EAMS, let url = URL(string: school.url),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
        return url.host?.lowercased() == "webvpn.nbcc.edu.cn"
    }

    static let js = #"""
    (function(){
      if (window.__sleepyClassicCancel) window.__sleepyClassicCancel();
      var finished = false;
      var timer;
      function out(payload){
        if (finished) return;
        finished = true;
        clearTimeout(timer);
        window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify(payload)});
      }
      function fail(message){out({ok:false, err:message});}
      function success(text){out({ok:true, data:text, periods:[]});}
      window.__sleepyClassicCancel = function(){finished = true; clearTimeout(timer);};
      timer = setTimeout(function(){fail('教务课表抓取超时，请重新登录后重试');}, 20000);
      var loginRe = /\/login(?:[/?#]|$)|\/users\/sign_in|\/authserver\/|\/cas\/login/i;
      var idsRe = /\#(idsPattern)/;
      var semesterRe = /\#(semesterPattern)/;
      var origin = location.origin;
      function sameOrigin(url){return new URL(url, location.href).origin === origin;}
      function hasCourses(text){return text.indexOf('new TaskActivity(') >= 0;}
      function hidden(doc, name){
        var form = doc.querySelector('form[name="courseTableForm"],form[action*="courseTableForStd"]');
        var inputs = (form || doc).querySelectorAll('input,select');
        for (var i=0;i<inputs.length;i++) {
          if (inputs[i].name === name && /^\d+$/.test(inputs[i].value)) return inputs[i].value;
        }
        return null;
      }
      function context(doc, url){
        if (!doc || !doc.documentElement || !sameOrigin(url)) return null;
        var text = doc.documentElement.outerHTML;
        if (hasCourses(text)) return {courses:text};
        var lower = text.toLowerCase();
        var bind = lower.indexOf('coursetableforstd');
        if (bind < 0) bind = lower.indexOf('coursetableform');
        if (bind < 0) return null;
        var scope = text.substring(bind);
        var ids = scope.match(idsRe);
        var semester = scope.match(semesterRe);
        var id = ids ? ids[1] : hidden(doc, 'ids');
        var semHidden = hidden(doc, 'semester.id');
        var sem = semester ? semester[1] : semHidden;
        if (!id || !sem) return null;
        return {url:url, ids:id, semester:sem, hiddenSemester:semHidden,
                project:hidden(doc, 'project.id') || '1'};
      }
      function find(doc, url, depth){
        var own = context(doc, url);
        if (own || depth >= 8) return own;
        var frames = doc.querySelectorAll('iframe,frame');
        for (var i=0;i<frames.length;i++) {
          try {
            var child = frames[i].contentDocument;
            if (!child || !child.defaultView) continue;
            var hit = find(child, child.defaultView.location.href, depth+1);
            if (hit) return hit;
          } catch(e) {}
        }
        return null;
      }
      function read(response){
        if (loginRe.test(response.url)) throw new Error('登录态已失效，请在 WebView 内重新登录后再试');
        if (!response.ok) throw new Error('教务服务器返回 HTTP ' + response.status);
        return response.text().then(function(text){
          if (/<input[^>]*type\s*=\s*["']password["']/i.test(text) && !hasCourses(text))
            throw new Error('登录态已失效，请在 WebView 内重新登录后再试');
          return {text:text, url:response.url};
        });
      }
      function run(ctx){
        if (finished) return;
        if (ctx.courses) {success(ctx.courses); return;}
        var semesters = [ctx.semester];
        if (ctx.hiddenSemester && ctx.hiddenSemester !== ctx.semester) semesters.push(ctx.hiddenSemester);
        var candidates = [];
        semesters.forEach(function(sem){
          candidates.push('ignoreHead=1&setting.kind=std&startWeek=&project.id=' + ctx.project + '&semester.id=' + sem + '&ids=' + ctx.ids);
          candidates.push('ignoreHead=1&setting.kind=std&startWeek=&semester.id=' + sem + '&ids=' + ctx.ids);
        });
        candidates = candidates.filter(function(v,i,a){return a.indexOf(v) === i;}).slice(0,3);
        var endpoint = new URL('\#(actionPath)', ctx.url).href;
        if (!sameOrigin(endpoint)) {fail('课表入口不在当前登录域，请先进入教务页面'); return;}
        function next(i){
          if (finished) return;
          if (i >= candidates.length) {fail('教务页未返回课表数据，请进入我的课表页面后重试'); return;}
          fetch(endpoint, {method:'POST', credentials:'same-origin',
            headers:{'Content-Type':'application/x-www-form-urlencoded; charset=UTF-8','X-Requested-With':'XMLHttpRequest'},
            body:candidates[i]})
          .then(read).then(function(response){
            if (hasCourses(response.text)) success(response.text); else next(i+1);
          }).catch(function(error){fail(String(error));});
        }
        next(0);
      }
      try {
        var ctx = find(document, location.href, 0);
        if (ctx) {run(ctx); return;}
        // 仅南开固定 host 自动进入课表；NBCC 门户需要用户先点 PC 教务。
        if (location.hostname.toLowerCase() !== 'eamis.nankai.edu.cn') {
          fail('请先在门户进入教务管理→我的课表页面后再点导入'); return;
        }
        var entry = new URL('\#(entryPath)', location.href).href;
        fetch(entry, {credentials:'same-origin',headers:{'X-Requested-With':'XMLHttpRequest'}})
        .then(read).then(function(response){
          var doc = new DOMParser().parseFromString(response.text, 'text/html');
          var found = context(doc, response.url || entry);
          if (found) run(found); else fail('未能从课表入口提取学号和学期，请登录后进入我的课表');
        }).catch(function(error){fail(String(error));});
      } catch(error){fail(String(error));}
    })();
    """#
}
