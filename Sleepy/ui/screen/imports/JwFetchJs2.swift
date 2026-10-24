// JwFetchJs2.swift — ← JwWebViewLoginScreen.kt v1.0.61 (WHUT/EAMS5/EAMS5_AHU/BJTU 续集)
//
// 接续 JwFetchJs.swift 的另 4 个 fetch JS 块(分文件避免单文件过大)。
// 桥回调统一 WKScriptMessage postMessage。

import Foundation

// MARK: - WHUT_FETCH_JS(← JwWebViewLoginScreen.kt WHUT_FETCH_JS 原文移植)
//
// 武汉理工大学 (whut.edu.cn, EMAP homeapp 角色机制): 切本科生 appRole → currentUser
// 取学期 → jcjcx.do 做 DM→物理节映射 → wdkbby/cxxszhxqkb.do 主通道, 空时回退
// 旧 kcbcxby/cxxskcb.do。
enum WhutFetchJs {
    static let js = """
    (function(){
      try {
        if (location.hostname.indexOf('whut.edu.cn') < 0) {
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:'请先登录并进入武汉理工教务后再点导入'})});
          return;
        }
        var post = function(url, body){
          return fetch(url, {
            method:'POST',
            headers:{'Content-Type':'application/x-www-form-urlencoded; charset=UTF-8','X-Requested-With':'XMLHttpRequest'},
            body: body || '',
            credentials:'include'
          }).then(function(r){ return r.json(); });
        };
        // 0) 切到本科生角色 (EMAP homeapp 角色机制; 值为 WHUT 全站固定的本科生 appRole GUID,
        //    与 iwut 掌上吾理 bachelor-import 一致)。失败不阻断 — 有些账号可能只有单角色。
        fetch('/jwapp/sys/homeapp/api/home/changeAppRole.do?appRole=ef212c48c8f84be79acbd9d81b090f51',
          {method:'POST', credentials:'include', headers:{'Content-Type':'application/x-www-form-urlencoded; charset=UTF-8','X-Requested-With':'XMLHttpRequest'}})
        .catch(function(){})
        .then(function(){
        // 1) 当前学期 (学号在 wdkbby 通道不需要 — 服务端按会话返回本人数据)
        return fetch('/jwapp/sys/homeapp/api/home/currentUser.do', {credentials:'include'})
        .then(function(r){ return r.json(); })
        .then(function(u){
          var d = u.datas || {};
          var xh = d.userId || '';
          var xnxq = (d.welcomeInfo && d.welcomeInfo.xnxqdm) || '';
          if (!xnxq) throw new Error('未取到当前学期, 请确认已登录本科教务');
          // 2) 节次 DM→物理节映射: jcjcx.do 按名称含"节"计数 (中课1/晚课等不带"节"的跳过)。
          //    2026-09 采集包实锤: DM 表 = 1..5,8..12,14..16, 与 fallback 一致。
          var fallbackMap = {"1":1,"2":2,"3":3,"4":4,"5":5,"8":6,"9":7,"10":8,"11":9,"12":10,"14":11,"15":12,"16":13};
          var sectionMap = {};
          var mapReady = post('/jwapp/sys/wdkbby/modules/dzkz/jcjcx.do', '').then(function(j){
            try {
              var rows = (j.datas && j.datas.jcjcx && j.datas.jcjcx.rows) || [];
              var n = 0;
              for (var i = 0; i < rows.length; i++) {
                var mc = String(rows[i].MC || '');
                if (mc.indexOf('节') >= 0) { n += 1; sectionMap[String(rows[i].DM)] = n; }
              }
              if (n < 10) sectionMap = fallbackMap;
            } catch(e) { sectionMap = fallbackMap; }
          }).catch(function(){ sectionMap = fallbackMap; });
          var applyMap = function(rows){
            for (var i = 0; i < rows.length; i++) {
              var r = rows[i];
              if (sectionMap[r.KSJC] != null) r.KSJC = String(sectionMap[r.KSJC]);
              if (sectionMap[r.JSJC] != null) r.JSJC = String(sectionMap[r.JSJC]);
            }
          };
          return mapReady.then(function(){
            // 3) 主通道: wdkbby/学生课程表 cxxszhxqkb.do (2026-09 用户采集包实锤 —
            //    学生"我的课表"页面走这条: POST XNXQDM → datas.cxxszhxqkb.rows[],
            //    字段 KCM/SKXQ/KSJC/JSJC/SKZC 与解析内核同构, KSJC 为 DM 值)。
            //    旧 kcbcxby/cxxskcb.do 是"教室课表"(教师端)微应用, 学生账号常 403/空。
            return post('/jwapp/sys/wdkbby/modules/xskcb/cxxszhxqkb.do', 'XNXQDM=' + encodeURIComponent(xnxq))
            .then(function(k){
              var rows = (k.datas && k.datas.cxxszhxqkb && k.datas.cxxszhxqkb.rows) || [];
              if (rows.length > 0) {
                applyMap(rows);
                window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:true, data:JSON.stringify(k), periods:[]})});
                return null;
              }
              // 4) 兜底: 老 kcbcxby/cxxskcb.do 通道 (部分老版本部署仍用它)
              return post('/jwapp/sys/kcbcxby/modules/xskcb/cxxskcb.do', 'XH=' + encodeURIComponent(xh) + '&XNXQDM=' + encodeURIComponent(xnxq))
              .then(function(k2){
                var rows2 = (k2.datas && k2.datas.cxxskcb && k2.datas.cxxskcb.rows) || [];
                if (rows2.length === 0) throw new Error('课表为空: 请确认已在教务"我的课表"页可见本学期课程');
                applyMap(rows2);
                window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:true, data:JSON.stringify(k2), periods:[]})});
              });
            });
          });
        });
        })
        .catch(function(e){
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(e)})});
        });
      } catch(err) {
        window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(err)})});
      }
    })();
    """
}

// MARK: - EAMS5_FETCH_JS(← JwWebViewLoginScreen.kt EAMS5_FETCH_JS 原文移植, v1.0.61 v2 四段链)
//
// 合肥工业大学 (jxglstu.hfut.edu.cn) EAMS5: course-table 拿 studentId(+finalUrl 学号兜底)
// → course-table/info 拿 bizTypeId(biz 空则跳过 get-data) → get-data 拿 lessonIds +
// timeTableLayoutId → 3.5) POST timetable-layout 拿 courseUnitList → POST datum →
// __layout/__datum 合并 + HHmm→'HH:MM' periods 转换 (issue #46)。
// 显式拦截 one.hfut.edu.cn 门户(只有本周/下周预览, 完整学期在 jxglstu)。
// 兼容 cumtb.edu.cn(中国矿业大学北京, 同 EAMS5 协议族)。
// __EAMS5_PREFIX__ 运行时由派发端用 Eams5PathPrefix.fromSchoolUrl() 替换。
enum Eams5FetchJs {
    static let js = """
    (function(){
      try {
        if (location.hostname === 'one.hfut.edu.cn') {
          // issue #25: 门户 (统一信息门户) 不是教务 — 且 'one.hfut.edu.cn'.indexOf('hfut.edu.cn')
          // >= 0 会误过下方弱包含守卫。显式拦截并引导用户去 jxglstu 教务入口。
          // issue #46 (2026-09): 门户上线了课表预览卡 (/api/operation/course-timetable/search/<n>/<date>,
          // Bearer token, 只有本周+下周), 全学期课表仍只有 jxglstu 的 datum 有 — 拦截策略不变, 文案改准确。
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false,
            err:'检测到您在合工大统一信息门户 (one.hfut.edu.cn)。门户里只有本周/下周的课表预览, 完整学期课表请到"我的学校"选择合肥工业大学, 进入 jxglstu 教务系统后再点导入'})});
          return;
        }
        if (location.hostname.indexOf('hfut.edu.cn') < 0 && location.hostname.indexOf('jxglstu') < 0
            && location.hostname.indexOf('ahu.edu.cn') < 0 && location.hostname.indexOf('cumtb.edu.cn') < 0) {
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:'请先登录并进入合工大教务后再点导入'})});
          return;
        }
        var PREFIX = '__EAMS5_PREFIX__';
        // 合工大当前课表页把当前学期放在 #allSemesters 的 selected option 中，
        // 而不是写成 semesterId=...；没有它时 get-data 会返回 500 (issue #46).
        var extractSemesterId = function(source) {
          var options = source.match(/<option\\b[^>]*>/gi) || [];
          for (var oi = 0; oi < options.length; oi++) {
            if (!/\\bselected(?:\\s*=\\s*["']?selected["']?)?\\b/i.test(options[oi])) continue;
            var selectedValue = options[oi].match(/\\bvalue\\s*=\\s*["']?(\\d+)/i);
            if (selectedValue) return selectedValue[1];
          }
          var explicit = source.match(/semesterId\\s*[=:]\\s*["']?(\\d+)/i);
          if (explicit) return explicit[1];
          return null;
        };
        // 1) GET course-table 拿 studentId (Cookie 已带)。
        //    fetch 默认跟随重定向: 已登录 → /for-std/course-table 重定向到
        //    /for-std/course-table/info/<studentId>, 页面 HTML <script> 段里有
        //    `var studentId = '2024210001';` 或对象字面量 `studentId:'2024210001',`。
        //    未登录 → 重定向到 /eams5-student/login, 页面无 studentId。
        fetch(PREFIX + '/for-std/course-table', {credentials:'include'})
        .then(function(r){
          if (!r.ok) throw new Error('course-table 取 studentId 失败 HTTP ' + r.status + '（请确认已在教务主页登录）');
          return r.text().then(function(html){ return {html: html, finalUrl: r.url || ''}; });
        })
        .then(function(ctx){
          var html = ctx.html || '';
          var extractedSemester = extractSemesterId(html);
          // 检测会话失效: 最终 URL 含 /login (302 落到登录页)
          if (ctx.finalUrl.indexOf('/login') >= 0 || ctx.finalUrl.indexOf('login?') >= 0) {
            window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:'登录态已失效,请在教务主页重新登录后再试'})});
            return null;
          }
          // 多形态匹配 — 2026-09 用户反馈 + 跨仓验证 (Chiu-xaH/HFUT-Schedule,
          // BoynChan/HfutOpenApi) 综合, 上游 script 段 studentId 写法不统一:
          //   A. var studentId = '2024210001';
          //   B. var studentId="2024210001";
          //   C. studentId:'2024210001',        ← supwisdom 对象字面量
          //   D. studentId: "2024210001",        ← supwisdom 对象字面量双引号
          //   E. studentId=2024210001;           ← 极少数裸数字
          //   F. studentId=2024210001&...        ← 在查询串里
          // 用一条宽松正则覆盖 A–F: 键名后 [=:] 可有引号, 值允许 \\w (数字/字母/下划线)。
          // 命中后取第一个纯数字/字母数字串; 不依赖引号, 不依赖分号终止。
          // 与 JVM 端 EAMS5_STUDENT_ID_REGEX (data/jw/Eams5PathPrefix.kt) 同形 —
          // 单测锁契约, JS 端保持字符串字面量 (WebView JS context 无 JVM 调用通道)。
          var m = html.match(/studentId\\s*[=:]\\s*['"]?([A-Za-z0-9]+)['"]?/);
          var sid = m ? m[1] : null;
          if (!sid) {
            // 参考仓 dev 分支实测口径: course-table 302 Location =
            // /eams5-student/for-std/course-table/info/<studentId>, 其直接截断该路径取学号。
            // fetch 已自动跟随重定向, r.url (ctx.finalUrl) 即 Location 的等价物。
            m = /for-std\\/course-table\\/info\\/(\\d+)/.exec(ctx.finalUrl);
            if (m) sid = m[1];
          }
          if (!sid) return null;
          var sem = extractedSemester;
          return {studentId: sid, semesterId: sem || ''};
        })
        .then(function(ctx){
          if (!ctx) {
            window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:'未取到 studentId,请在 course-table 页面停留后再试'})});
            return null;
          }
          var sid = ctx.studentId;
          var sem = ctx.semesterId;
          // 2) info 页拿 bizTypeId (参考仓 parseBizTypeId: /bizTypeId\\s*:\\s*(\\d+)/ 同形)
          return fetch(PREFIX + '/for-std/course-table/info/' + sid, {credentials:'include'})
          .then(function(r){ return r.ok ? r.text() : ''; })
          .catch(function(){ return ''; })
          .then(function(infoHtml){
            var biz = '';
            if (infoHtml) {
              var bm = infoHtml.match(/bizTypeId\\s*[=:]\\s*['"]?(\\d+)/);
              if (bm) biz = bm[1];
              if (!sem) sem = extractSemesterId(infoHtml);
            }
            // 3) get-data 拿 lessonIds[]; 任一环失败 → ids 留空数组 = v1 旧行为兜底
            var q = '/for-std/course-table/get-data?bizTypeId=' + biz + '&dataId=' + sid;
            if (sem) q += '&semesterId=' + sem;
            var chain = biz
              ? fetch(PREFIX + q, {credentials:'include'})
                  .then(function(r){ return r.ok ? r.text() : ''; })
                  .catch(function(){ return ''; })
              : Promise.resolve('');
            return chain.then(function(txt){
              var ids = [];
              var layoutId = null;
              try {
                var j = JSON.parse(txt);
                var got = j && (j.lessonIds || (j.result && j.result.lessonIds));
                if (got && got.length) ids = got;
                // issue #46: get-data 顶层带 timeTableLayoutId (采集包实锤 122),
                // 供第 3.5 段拉服务端权威节次表
                if (j && typeof j.timeTableLayoutId === 'number') layoutId = j.timeTableLayoutId;
              } catch (e) { /* get-data 异常 → 空数组兜底 */ }
              // 3.5) POST timetable-layout 拿 courseUnitList (各校区节次表, 宣城 12 节 ≠ 合肥 10 节)。
              //      参照 HFUTer/HFNewParserViewModel + 小爱系 provider + kirsh1/ustc-timetable 共识:
              //      节次不能客户端硬编码, 以 {timeTableLayoutId} 换取 courseUnitList。
              //      失败可降级: layoutId 空/接口 500 → units 留空, parser 走旧 heuristic 兜底。
              var layoutChain = layoutId
                ? fetch(PREFIX + '/ws/schedule-table/timetable-layout', {
                    method:'POST',
                    credentials:'include',
                    headers:{'Content-Type':'application/json'},
                    body: JSON.stringify({timeTableLayoutId: layoutId})
                  }).then(function(r){ return r.ok ? r.json() : null; })
                    .catch(function(){ return null; })
                : Promise.resolve(null);
              return layoutChain.then(function(layout){
                var units = (layout && layout.result && layout.result.courseUnitList) || [];
                // 4) POST schedule-table/datum — lessonIds 为真课时数组; 纯数字学号按 int 提交
                return fetch(PREFIX + '/ws/schedule-table/datum', {
                  method:'POST',
                  credentials:'include',
                  headers:{'Content-Type':'application/json'},
                  body: JSON.stringify({
                    lessonIds: ids,
                    studentId: /^\\d+$/.test(sid) ? Number(sid) : sid,
                    weekIndex: ''
                  })
                }).then(function(r){
                  if (!r.ok) throw new Error('POST schedule-table/datum 失败 HTTP ' + r.status + ' (lessonIds:' + ids.length + ')');
                  return r.text().then(function(datumTxt){
                    if (!units.length) return datumTxt;                 // 无布局 → 原样 (parser heuristic)
                    var periodUnits = units.map(function(u){            // 布局节次升序, 与 datum 原文合并
                      return {indexNo:u.indexNo, startTime:u.startTime, endTime:u.endTime};
                    }).sort(function(a,b){ return a.indexNo - b.indexNo; });
                    var merged;
                    try {
                      var dj = JSON.parse(datumTxt);
                      dj.courseUnitList = periodUnits;                  // parser 精确查表锚点
                      merged = JSON.stringify(dj);
                    } catch (e2) { merged = datumTxt; }
                    return JSON.stringify({__layout: periodUnits, __datum: merged});
                  });
                });
              });
            });
          });
        })
        .then(function(txt){
          if (!txt) return;
          // issue #46: 有布局时把 courseUnitList 转成 periods[] 供确认页作息表预填
          // (HHmm → 'HH:MM', 与 session-time-pattern 形态一致); 无布局 = 原行为 periods:[]
          var periods = [];
          var dataTxt = txt;
          try {
            var o = JSON.parse(txt);
            if (o && o.__layout && o.__datum) {
              dataTxt = o.__datum;
              for (var i = 0; i < o.__layout.length; i++) {
                var u = o.__layout[i];
                periods.push({
                  node: u.indexNo,
                  start: Math.floor(u.startTime/100) + ':' + (u.startTime%100 < 10 ? '0' : '') + (u.startTime%100),
                  end: Math.floor(u.endTime/100) + ':' + (u.endTime%100 < 10 ? '0' : '') + (u.endTime%100)
                });
              }
            }
          } catch (e) { /* 非 merged 形态 (CUMTB/AHU/无布局) → 原样 */ }
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:true, data:dataTxt, periods:periods})});
        })
        .catch(function(e){
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(e)})});
        });
      } catch(err) {
        window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(err)})});
      }
    })();
    """
}

// MARK: - EAMS5_AHU_FETCH_JS(← JwWebViewLoginScreen.kt EAMS5_AHU_FETCH_JS 原文移植)
//
// 安徽大学 (jw.ahu.edu.cn, 金智 EAMS 新版部署) EAMS5: 与合工大 EAMS5 协议同源但走
// GET print-data 三段 (5 仓共识: 安大 POST /ws/schedule-table/datum 返 HTTP 500
// 不存在该 endpoint)。登录态判定更严: 302 落 /cas/login OR 200 落 CAS 登录页
// (双字段 name="lt" + name="execution")。学期从 allSemesters <select> 取 id 最大
// (newest-first), JSON / selected 兜底; 拿不到即报错不硬猜。
enum Eams5AhuFetchJs {
    static let js = """
    (function(){
      try {
        if (location.hostname.indexOf('ahu.edu.cn') < 0) {
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:'请先登录并进入安徽大学教务后再点导入'})});
          return;
        }
        var PREFIX = '__EAMS5_PREFIX__';
        // 1) GET course-table HTML, 提取 allSemesters (学期 JSON 数组) + 检测登录态
        fetch(PREFIX + '/for-std/course-table', {credentials:'include', redirect:'follow'})
        .then(function(r){
          // 会话失效判定 (Zeraora client.ts:608-617 + abydym SessionAuthenticator.kt + Landon-3314 isLoginExpired 共识):
          //   1) 302-399 redirect + Location 落到 CAS (/cas/login, one.ahu.edu.cn/cas)
          //   2) 200 OK + HTML 含 'name="lt"' AND 'name="execution"' 双字段 (CAS 登录页)
          //   3) URL 含 casloginform / 统一身份认证 / 请重新登录 (兜底)
          // 5 仓 cross-verified 2026-09-06 (a999c385/aa707ac2033872402 agents)
          var status = r.status;
          var locHeader = r.headers.get('location') || '';
          var isCasRedirect = status >= 300 && status < 400
            && (locHeader.indexOf('one.ahu.edu.cn/cas') >= 0
                || /\\/cas\\/login/.test(locHeader)
                || /\\/cas\\b/.test(locHeader));
          // r.text() 单次消费 — 先一次性读再判
          return r.text().then(function(body){
            // 同时读 r.url, fetch redirect:'follow' 后 finalUrl 是最终 URL (CAS 登录页)
            var finalUrl = r.url || '';
            var hasLtField = /name=["']lt["']/i.test(body);
            var hasExecField = /name=["']execution["']/i.test(body);
            var hasCasLoginUi = /统一身份认证|请重新登录|session timeout|会话已过期|name=["']casloginform["']/i.test(body);
            var loginExpired = finalUrl.indexOf('/login') >= 0
                            || finalUrl.indexOf('cas/login') >= 0
                            || finalUrl.indexOf('one.ahu.edu.cn/cas') >= 0
                            || finalUrl.indexOf('casloginform') >= 0
                            || isCasRedirect
                            || (hasLtField && hasExecField)
                            || hasCasLoginUi;
            return {html: body, finalUrl: finalUrl, status: status, loginExpired: loginExpired};
          });
        })
        .then(function(ctx){
          if (ctx.loginExpired) {
            window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false,
              err:'登录态已失效,请在教务主页重新登录后再试'})});
            return null;
          }
          var html = ctx.html || '';
          // 学期列表提取 — 5 仓共识 (a999c385 agent):
          //   AHU 是 Thymeleaf/J2EE 模板渲染, 学期列表嵌入 HTML 内
          //   `<select id="allSemesters"><option value="112">2024-2025-2</option>...`
          //   qiqqqqq517 ahu.js:37 / abydym CourseRepository.kt:119-167 / Zeraora client.ts:480-489
          //   共识 regex: <select[^>]*id=["']allSemesters["'][^>]*>([\\s\\S]*?)</select>
          //   + 内部 <option value="(\\d+)"[^>]*>([^<]+)</option> 循环
          // 按 id 倒序取首 (服务器返回 newest-first, abydym + Zeraora 一致)
          var semesterId = null;
          var selectMatch = html.match(/<select[^>]*\\bid=["']allSemesters["'][^>]*>([\\s\\S]*?)<\\/select>/i);
          if (selectMatch) {
            var inner = selectMatch[1];
            var optionRegex = /<option[^>]*\\bvalue=["'](\\d+)["'][^>]*>([^<]*)<\\/option>/gi;
            var m;
            var opts = [];
            while ((m = optionRegex.exec(inner)) !== null) {
              opts.push({id: parseInt(m[1], 10), name: m[2].trim()});
            }
            // 取 id 最大 (newest first; abydym .sortedByDescending { it.id }.first())
            if (opts.length) {
              opts.sort(function(a, b) { return b.id - a.id; });
              semesterId = String(opts[0].id);
            }
          }
          // 优先级 2 fallback: Vue/Nuxt 嵌入的 JSON 形态 (防御性)
          // 形如 var allSemesters = [...] 或 semesters = [...]
          if (!semesterId) {
            var jsonMatch = html.match(/(?:allSemesters|semesters)\\s*[=:]\\s*(\\[[\\s\\S]*?\\])\\s*[;,]?/);
            if (jsonMatch) {
              try {
                var arr = JSON.parse(jsonMatch[1]);
                if (arr && arr.length) {
                  // 优先 isCurrentSemester 标志
                  var cur = null;
                  for (var i = 0; i < arr.length; i++) {
                    if (arr[i].isCurrentSemester === true || arr[i].isCurrent === true ||
                        arr[i].current === true || arr[i].status === 'CURRENT') { cur = arr[i]; break; }
                  }
                  var semObj = cur || arr[0];
                  semesterId = String(semObj.id || semObj.semesterId || semObj.value || semObj.code);
                }
              } catch(e) {}
            }
          }
          // 优先级 3 fallback: <option selected value="X">
          if (!semesterId) {
            var sel = html.match(/<option[^>]*\\bselected\\b[^>]*\\bvalue=["']?(\\d+)["']?/i);
            if (sel) semesterId = sel[1];
          }
          // v1 兜底: abydym hardcoded DEFAULT_SEMESTER_ID = 112 (2024-2025-2 已知)
          // 不强行猜, 直接报"未取到学期列表"
          if (!semesterId) {
            window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false,
              err:'未取到学期列表 (allSemesters), 请在课表页面停留几秒后再点导入'})});
            return null;
          }
          return semesterId;
        })
        .then(function(semesterId){
          if (!semesterId) return null;
          // 2) GET print-data (含 weekday/weekIndexes/startUnit/endUnit 的真实课表数据)
          // followRedirects: 'follow' (服务端按 session 绑定学生, 不需要 studentId — 5 仓共识)
          var url = PREFIX + '/for-std/course-table/semester/' + encodeURIComponent(semesterId)
                  + '/print-data?semesterId=' + encodeURIComponent(semesterId) + '&hasExperiment=false';
          return fetch(url, {credentials:'include', redirect:'follow'}).then(function(r){
            if (!r.ok) throw new Error('print-data 失败 HTTP ' + r.status);
            return r.text();
          });
        })
        .then(function(txt){
          if (!txt) return;
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:true, data:txt, periods:[]})});
        })
        .catch(function(e){
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(e)})});
        });
      } catch(err) {
        window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(err)})});
      }
    })();
    """
}

// MARK: - BJTU_FETCH_JS(← JwWebViewLoginScreen.kt BJTU_FETCH_JS 原文移植)
//
// 北京交通大学 (aa.bjtu.edu.cn): 并发取 stuschedule (个人课表) + schedule (含节次时间表) 两页,
// 双双命中登录页 (a&&b) 才报"登录已失效", 双双 <200 字符报"课表页返回内容为空"; 拼
// '<!--sleepy-bjtu-doc:stuschedule-->' + a + '<!--sleepy-bjtu-doc:schedule-->' + b 组合源交
// JwBjtuParser 切段; periods 先 a 后 b 兜底。跨语言 invariant (SOP 铁律 3): LABEL_RE / TIME_RE
// 的 JS 字符串字面量与 JwBjtuParser.PERIOD_LABEL_RE_SRC / PERIOD_TIME_RE_SRC 逐字符相等。
enum BjtuFetchJs {
    static let js = """
    (function(){
      function finish(payload) {
        window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify(payload)});
      }
      function err(msg) {
        finish({ok:false, err:msg});
      }
      try {
        if (location.hostname.indexOf('bjtu.edu.cn') < 0) {
          err('请先在北京交通大学教务页面 (aa.bjtu.edu.cn) 登录后再点导入');
          return;
        }
        var LABEL_RE = new RegExp('第\\\\s*(\\\\d+)\\\\s*节');
        var TIME_RE = new RegExp('(\\\\d{1,2}:\\\\d{2})\\\\s*[-–—~至]\\\\s*(\\\\d{1,2}:\\\\d{2})');
        function get(path) {
          return fetch(path, {credentials:'include'}).then(function(r){
            return r.text().then(function(body){ return {status: r.status, body: body}; });
          });
        }
        function isLoginExpired(ctx) {
          return (ctx.body || '').indexOf('/client/login/') >= 0 &&
                 (ctx.body || '').indexOf('星期一') < 0;
        }
        function periodsFrom(html) {
          var periods = [];
          try {
            var doc = new DOMParser().parseFromString(html, 'text/html');
            var rows = doc.querySelectorAll('tr');
            var seen = {};
            for (var i = 0; i < rows.length; i++) {
              var cell = rows[i].querySelector('th,td');
              if (!cell) continue;
              var text = cell.textContent || '';
              var lm = text.match(LABEL_RE);
              if (!lm) continue;
              var node = parseInt(lm[1], 10);
              if (seen[node]) continue;
              seen[node] = true;
              var tm = text.match(TIME_RE);
              periods.push({node: node, start: tm ? tm[1] : '', end: tm ? tm[2] : ''});
            }
            periods.sort(function(a,b){ return a.node - b.node; });
          } catch(e) { periods = []; }
          return periods;
        }
        Promise.all([
          get('/course_selection/courseselect/stuschedule/'),
          get('/course_selection/courseselecttask/schedule/')
        ])
        .then(function(rs){
          var a = rs[0], b = rs[1];
          // 双双失效才判登录过期 (conjunctive, 与 Android 一致; 单页失效另一页仍可用)
          if (isLoginExpired(a) && isLoginExpired(b)) {
            err('登录已失效，请重新登录后再点导入');
            return;
          }
          // 双双内容过短 (空壳页) → 明确报空, 不落伪"0 课"
          if ((a.body || '').length < 200 && (b.body || '').length < 200) {
            err('课表页返回内容为空，请先在教务里打开课表页后再点导入');
            return;
          }
          var combined = '<!--sleepy-bjtu-doc:stuschedule-->' + (a.body || '') +
                         '<!--sleepy-bjtu-doc:schedule-->' + (b.body || '');
          var periods = periodsFrom(a.body || '');
          if (periods.length === 0) periods = periodsFrom(b.body || '');
          finish({ok:true, data:combined, periods:periods});
        })
        .catch(function(e){
          err('抓取失败: ' + String(e && e.message ? e.message : e) + '（登录会话可能已失效，请重新登录）');
        });
      } catch(e) {
        err(String(e && e.message ? e.message : e));
      }
    })();
    """
}
