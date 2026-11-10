// Exact Android v1.0.63 (b16aa84d11c250acdf644cd8b7812ab27d03dc6a)
// JwWebViewLoginScreen.kt WISEDU_FETCH_JS with TYPE_SEU dispatch replacements.
// Android bridge spelling is preserved; the test harness supplies its transport.
(function(){
  try {
    var pathOk = location.pathname.indexOf('/jwapp/') >= 0 || location.hostname.toLowerCase() === 'ehall.seu.edu.cn';
    if (!pathOk) {
      window.__sleepyBridge.onWiseduResult(JSON.stringify({ok:false, err:'请先登录并进入教务系统后再点导入'}));
      return;
    }
    // 0. 先 GET 我的课表(wdkb)微应用入口，初始化 app 会话；否则 module API 返回 403
    // 会话已死时入口/module API 返回 403 HTML 页（如 AHYZ openresty 金智壳），
    // 必须先看状态码再解析，否则 r.json() 抛 SyntaxError 文案不可读。
    fetch('/jwapp/sys/wdkb/*default/index.do', {credentials:'include'})
    .then(function(response){
      if (!response.ok) {
        throw new Error('WISEDU_HTTP_403: 会话已过期或无权访问，请返回上一步退出登录后重新进入教务登录');
      }
      return fetch('/jwapp/sys/wdkb/modules/jshkcb/dqxnxq.do', {
        method:'POST',
        headers:{'X-Requested-With':'XMLHttpRequest'},
        credentials:'include'
      });
    })
    .then(function(response){
      if (!response.ok) {
        throw new Error('WISEDU_HTTP_403: 会话已过期或无权访问，请返回上一步退出登录后重新进入教务登录');
      }
      return response.json();
    })
    .then(function(d){
      var rows = [];
      try { rows = d.datas.dqxnxq.rows || []; } catch(e) {}

      // 教务页面允许用户切换学期，但 dqxnxq 的 rows[0] 不一定是页面当前选项。
      // 先从当前页面的 select/option 读取用户实际选中的 XNXQDM，避免静默回退到旧学期。
      var xnxq = '';
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
      for (var i = 0; i < selects.length && !xnxq; i++) {
        var selected = selects[i].options && selects[i].options[selects[i].selectedIndex];
        var candidates = selected ? [selected.value, selected.textContent || ''] : [];
        for (var j = 0; j < candidates.length; j++) {
          var match = candidates[j].match(/20[0-9]{2}-20[0-9]{2}-[12]/);
          if (match && rows.some(function(row) { return String(row.DM || '') === match[0]; })) {
            xnxq = match[0];
            break;
          }
        }
      }
      // 某些 Wisedu 页面不是原生 select，而是自定义控件；这时匹配已选/激活节点文本。
      if (!xnxq) {
        var active = document.querySelectorAll('.selected,.active,[aria-selected="true"]');
        for (var k = 0; k < active.length && !xnxq; k++) {
          var activeText = active[k].value || active[k].textContent || '';
          var activeMatch = activeText.match(/20[0-9]{2}-20[0-9]{2}-[12]/);
          if (activeMatch && rows.some(function(row) { return String(row.DM || '') === activeMatch[0]; })) {
            xnxq = activeMatch[0];
          }
        }
      }
      // HEU 当前课表页使用 data-elem="XNXQMC" 展示当前学期，不是 select 或 active 节点。
      // 例如："2026-2027学年1学期"；将展示文本映射到接口中的 DM："2026-2027-1"。
      if (!xnxq) {
        var termNode = document.querySelector('[data-elem="XNXQMC"]');
        var termText = termNode ? (termNode.textContent || '') : '';
        var termMatch = termText.match(/(20[0-9]{2})-(20[0-9]{2})\s*学年\s*([12])\s*学期/);
        if (termMatch) {
          var termDm = termMatch[1] + '-' + termMatch[2] + '-' + termMatch[3];
          // HEU 的 dqxnxq 接口可能只返回旧的当前学期，而页面已切到下一学期。
          // 页面显示的学期才是用户选择，不能再要求它必须出现在这份旧列表中。
          xnxq = termDm;
        }
      }
      // 若页面没有学期控件，才使用接口标记的当前学期；禁止无条件取 rows[0]。
      // 兼容标记字段: SFDQ / CURRENT / SFSY (在服/有效标志, 2026-10-01 ahyz 采集包实锤 SFSY=1)。
      // 多学期部署仍必须靠上述 DOM 先识别, 只有列表唯一才允许直接取, 防止误选旧学期。
      if (!xnxq) {
        var current = rows.find(function(row) {
          var dm = row.DM;
          if (!dm) return false;
          return row.SFDQ === '1' || row.SFDQ === 1
            || row.CURRENT === '1' || row.current === true
            || row.SFSY === '1' || row.SFSY === 1;
        });
        if (current) {
          xnxq = String(current.DM);
        } else if (rows.length === 1 && rows[0].DM) {
          // 唯一学期: 无显式 current 标记时安全取 rows[0]。
          xnxq = String(rows[0].DM);
        }
      }
      if (!xnxq) throw new Error('无法识别当前选中的学期，请先在教务页面选择学期后再点导入');
      return fetch('/jwapp/sys/wdkb/modules/xskcb/xskcb.do', {
        method:'POST',
        headers:{'Content-Type':'application/x-www-form-urlencoded','X-Requested-With':'XMLHttpRequest'},
        body:'XNXQDM='+encodeURIComponent(xnxq),
        credentials:'include'
      }).then(function(r){
        if (!r.ok) throw new Error('WISEDU_HTTP_' + r.status + '：课表接口拒绝访问，请重新登录后重试');
        return r.text().then(function(txt){
          var payload;
          try { payload = JSON.parse(txt); }
          catch(e) { throw new Error('课表接口返回非 JSON，登录态可能失效'); }
          if (!payload || !payload.datas || !payload.datas.xskcb ||
              !Array.isArray(payload.datas.xskcb.rows)) {
            throw new Error('课表接口响应缺少 xskcb.rows 数组，请重新登录后重试');
          }
          return {xnxq:xnxq, txt:txt};
        });
      });
    })
    .then(function(o){
      // 抓节次时间：从页面 DOM 找"是否显示节次时间"开启后的节次文本
      // 格式：节次列每个 cell 含 "1:08:00~08:45" 或 "1\\n08:00~08:45"
      var periods = [];
      try {
        var nodes = document.querySelectorAll('[class*="jc"],[class*="jcdm"],[class*="jcbz"],[id*="node"],[id*="jc"]');
        var seen = {};
        for (var i = 0; i < nodes.length; i++) {
          var txt = (nodes[i].innerText || nodes[i].textContent || '').trim();
          // 匹配 "1:08:00~08:45" 或 "1 08:00~08:45"
          var m = txt.match(/^([0-9]{1,2})[:\\s]+([0-2]?[0-9]:[0-5][0-9])[~～-]([0-2]?[0-9]:[0-5][0-9])$/);
          if (m && !seen[m[1]]) {
            seen[m[1]] = true;
            periods.push({node:parseInt(m[1],10), start:m[2], end:m[3]});
          }
        }
        // 如果没抓到（DOM 选择器不对），从整个 body innerText 用 regex 全局抓
        if (periods.length === 0) {
          var allText = document.body.innerText || '';
          // 跨多行匹配节次文本 "1\n08:00~08:45"
          var re = /([0-9]{1,2})[:\s]\s*([0-2]?[0-9]:[0-5][0-9])[~～-]([0-2]?[0-9]:[0-5][0-9])/g;
          var mm;
          while ((mm = re.exec(allText)) !== null) {
            var n = parseInt(mm[1], 10);
            if (n >= 1 && n <= 20 && !seen[n]) {
              seen[n] = true;
              periods.push({node:n, start:mm[2], end:mm[3]});
            }
          }
        }
        // 按 node 排序
        periods.sort(function(a,b){ return a.node - b.node; });
      } catch(e) { periods = []; }
      window.__sleepyBridge.onWiseduResult(JSON.stringify({
        ok:true,
        data:o.txt,
        xnxq:o.xnxq,
        periods:periods
      }));
    })
    .catch(function(e){
      window.__sleepyBridge.onWiseduResult(JSON.stringify({ok:false, err:String(e)}));
    });
  } catch(err) {
    window.__sleepyBridge.onWiseduResult(JSON.stringify({ok:false, err:String(err)}));
  }
})();
