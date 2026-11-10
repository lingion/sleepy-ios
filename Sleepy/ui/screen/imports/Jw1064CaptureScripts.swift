// Transport scripts from the exact Android v1.0.64 source.
import Foundation

enum Jw1064CaptureScripts {
    static let JwAhuCapture = #"""
(function(){
  function finish(payload) {
    window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify(payload)});
  }
  function fail(message) { throw new Error(message); }
  function id(value) {
    if (typeof value !== 'string' && typeof value !== 'number') return null;
    if (typeof value === 'number' && !Number.isSafeInteger(value)) return null;
    var text = String(value).trim();
    return /^[1-9]\d*$/.test(text) ? text : null;
  }
  function requiredId(value) {
    var result = id(value);
    if (!result) fail('学期编号无效，请在课表页面重新选择学期后再导入');
    return result;
  }
  function objectId(value) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
    var keys = ['id', 'semesterId', 'value', 'code'];
    for (var i = 0; i < keys.length; i++) {
      if (Object.prototype.hasOwnProperty.call(value, keys[i])) return requiredId(value[keys[i]]);
    }
    return null;
  }
  function attr(attributes, name) {
    var found = attributes.match(new RegExp('(?:^|\\s)' + name + '\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))', 'i'));
    return found ? (found[1] !== undefined ? found[1] : found[2] !== undefined ? found[2] : found[3]) : null;
  }
  // Read string literals without evaluating any page script.
  function stringLiteral(text, start) {
    var quote = text[start], result = '';
    if (quote !== '"' && quote !== "'") fail('当前学期数据格式异常');
    for (var i = start + 1; i < text.length; i++) {
      var c = text[i];
      if (c === quote) return {value: result, end: i + 1};
      if (c !== '\\') { result += c; continue; }
      c = text[++i];
      var escapes = {n:'\n', r:'\r', t:'\t', b:'\b', f:'\f', v:'\v', '0':'\0'};
      if (c === 'u' || c === 'x') {
        var size = c === 'u' ? 4 : 2, hex = text.slice(i + 1, i + 1 + size);
        if (!new RegExp('^[0-9a-fA-F]{' + size + '}$').test(hex)) fail('当前学期数据格式异常');
        result += String.fromCharCode(parseInt(hex, 16)); i += size;
      } else if (c === '\n') {
        continue;
      } else if (c === '\r') {
        if (text[i + 1] === '\n') i++;
      } else if (c === undefined) {
        fail('当前学期数据格式异常');
      } else {
        result += Object.prototype.hasOwnProperty.call(escapes, c) ? escapes[c] : c;
      }
    }
    fail('当前学期数据格式异常');
  }
  function balanced(text, start) {
    var depth = 0;
    for (var i = start; i < text.length; i++) {
      var c = text[i];
      if (c === '"' || c === "'") { i = stringLiteral(text, i).end - 1; continue; }
      if (c === '{' || c === '[') depth++;
      if (c === '}' || c === ']') {
        depth--;
        if (depth === 0) return text.slice(start, i + 1);
      }
    }
    fail('学期数据未完整返回，请刷新课表页面后重试');
  }
  function currentObjectId(text) {
    try { return objectId(JSON.parse(text)); } catch (error) {
      // A JS object literal may have unquoted keys or single quoted values.
      // Split only top-level members so a nested object's id cannot win.
      var members = [], start = 1, depth = 0;
      for (var i = 1; i < text.length - 1; i++) {
        var c = text[i];
        if (c === '"' || c === "'") { i = stringLiteral(text, i).end - 1; continue; }
        if (c === '{' || c === '[') depth++;
        if (c === '}' || c === ']') depth--;
        if (c === ',' && depth === 0) { members.push(text.slice(start, i)); start = i + 1; }
      }
      members.push(text.slice(start, -1));
      for (var j = 0; j < members.length; j++) {
        var field = members[j].match(/^\s*["']?(?:id|semesterId|value|code)["']?\s*:\s*([\s\S]*?)\s*$/);
        if (!field) continue;
        var raw = field[1];
        return requiredId(raw[0] === '"' || raw[0] === "'" ? stringLiteral(raw, 0).value : raw);
      }
      return null;
    }
  }
  function liveSnapshot() {
    if (document.querySelectorAll('#allSemesters').length > 1) fail('课表页面存在多个学期控件，请重新选择学期后再导入');
    var select = document.querySelector('#allSemesters');
    if (!select) return null;
    var selected = [], options = select.selectedOptions || select.options || [];
    for (var i = 0; i < options.length; i++) {
      if (select.selectedOptions || options[i].selected) selected.push(options[i].value);
    }
    return {selected: selected, value: select.value};
  }
  function chooseSemester(html, live) {
    if (live) {
      if (live.selected.length > 1) fail('当前选择了多个学期，请只选择一个学期后再导入');
      var liveValue = live.selected.length === 1 ? live.selected[0] : live.value;
      if (liveValue !== undefined && liveValue !== null && String(liveValue).trim() !== '') return requiredId(liveValue);
    }
    var available = [], selected = [], selectRe = /<select\b([^>]*)>([\s\S]*?)<\/select>/gi, selectMatch;
    while ((selectMatch = selectRe.exec(html)) !== null) {
      if (attr(selectMatch[1], 'id') !== 'allSemesters') continue;
      var optionRe = /<option\b([^>]*)>/gi, optionMatch;
      while ((optionMatch = optionRe.exec(selectMatch[2])) !== null) {
        var value = attr(optionMatch[1], 'value');
        if (/(?:^|\s)selected(?:\s|=|$)/i.test(optionMatch[1])) selected.push(requiredId(value));
        if (id(value)) available.push(id(value));
      }
    }
    if (selected.length > 1) fail('课表页面返回多个已选学期，请重新选择学期后再导入');
    if (selected.length === 1) return selected[0];

    var current = [], currentRe = /\bcurrentSemester["']?\s*[:=]\s*/g, match;
    while ((match = currentRe.exec(html)) !== null) {
      var tail = html.slice(currentRe.lastIndex), value = null;
      if (/^JSON\.parse\s*\(/.test(tail)) {
        var opening = tail.match(/^JSON\.parse\s*\(\s*/)[0].length;
        var literal = stringLiteral(tail, opening);
        if (!/^\s*\)/.test(tail.slice(literal.end))) fail('当前学期数据格式异常');
        value = objectId(JSON.parse(literal.value));
      } else if (tail[0] === '{') {
        value = currentObjectId(balanced(tail, 0));
      }
      if (!value) fail('当前学期数据缺少有效编号');
      current.push(value);
    }
    var currentIdRe = /\bcurrentSemesterId["']?\s*[:=]\s*(?:"([^"]*)"|'([^']*)'|([^\s;,}\])<]+))/g;
    while ((match = currentIdRe.exec(html)) !== null) {
      current.push(requiredId(match[1] !== undefined ? match[1] : match[2] !== undefined ? match[2] : match[3]));
    }
    if (current.length) {
      for (var ci = 1; ci < current.length; ci++) {
        if (current[ci] !== current[0]) fail('当前学期信息不一致，请在课表页面明确选择学期后再导入');
      }
      return current[0];
    }

    var marked = [], listRe = /\b(?:allSemesters|semesters)["']?\s*[:=]\s*/g;
    while ((match = listRe.exec(html)) !== null) {
      if (html[listRe.lastIndex] !== '[') continue;
      var rows = JSON.parse(balanced(html, listRe.lastIndex));
      if (!Array.isArray(rows)) fail('学期列表格式异常');
      for (var ri = 0; ri < rows.length; ri++) {
        var row = rows[ri], rowId = objectId(row);
        if (!rowId) fail('学期列表包含无效编号');
        available.push(rowId);
        if (row.isCurrentSemester === true || row.isCurrent === true || row.current === true || row.status === 'CURRENT') marked.push(rowId);
      }
    }
    if (marked.length > 1) fail('学期列表标记了多个当前学期，请明确选择学期后再导入');
    if (marked.length === 1) return marked[0];
    var unique = available.filter(function(value, index) { return available.indexOf(value) === index; });
    if (unique.length === 1) return unique[0];
    fail('无法唯一确定学期，请在课表页面选择学期后再导入');
  }
  function loginUrl(text) {
    if (!text) return false;
    var url = new URL(text, location.href);
    return /\/(?:cas(?:\/login)?|login|sign-?in)(?:\/|$)/i.test(url.pathname);
  }
  function loginHtml(body) {
    if (!/^\s*</.test(body) || !/<(?:!doctype|html|form|input)\b/i.test(body)) return false;
    return (/\bname\s*=\s*["']lt["']/i.test(body) && /\bname\s*=\s*["']execution["']/i.test(body))
      || /casloginform|统一身份认证|请重新登录|session timeout|会话已过期/i.test(body)
      || (/<form\b/i.test(body) && /<input\b[^>]*\btype\s*=\s*["']password["']/i.test(body));
  }
  function request(url) {
    return fetch(url, {method:'GET', credentials:'include', redirect:'follow'}).then(function(response) {
      return response.text().then(function(body) {
        var destination = response.headers.get('location') || '';
        if (loginUrl(response.url) || loginUrl(destination) || loginHtml(body)) fail('登录态已失效，请在教务主页重新登录后再试');
        if (!response.ok || response.status < 200 || response.status >= 300) fail('教务请求失败，HTTP ' + response.status);
        if (response.url && new URL(response.url, location.href).origin !== location.origin) fail('教务请求离开当前站点，请返回教务主页后重试');
        return body;
      });
    });
  }
  function validatePrintData(text) {
    var root = JSON.parse(text);
    if (!root || typeof root !== 'object' || Array.isArray(root)) fail('课表接口返回格式异常');
    var tables = [], hasTables = false;
    if (Object.prototype.hasOwnProperty.call(root, 'studentTableVms')) {
      if (!Array.isArray(root.studentTableVms)) fail('课表列表格式异常');
      tables = tables.concat(root.studentTableVms); hasTables = true;
    }
    if (Object.prototype.hasOwnProperty.call(root, 'studentTableVm')) {
      tables.push(root.studentTableVm); hasTables = true;
    }
    if (!hasTables) fail('课表接口未返回课表列表');
    for (var i = 0; i < tables.length; i++) {
      var table = tables[i];
      if (!table || typeof table !== 'object' || Array.isArray(table) || !Array.isArray(table.activities)) fail('课表活动列表格式异常');
    }
  }
  try {
    if (!/(^|\.)ahu\.edu\.cn$/i.test(location.hostname)) fail('请先登录并进入安徽大学教务后再点导入');
    var PREFIX = '__EAMS5_PREFIX__';
    var initialUrl = location.href, initialSelect = document.querySelector('#allSemesters');
    var live = liveSnapshot();
    request(PREFIX + '/for-std/course-table').then(function(html) {
      var semesterId = chooseSemester(html, live);
      return request(PREFIX + '/for-std/course-table/semester/' + semesterId + '/print-data?semesterId=' + semesterId + '&hasExperiment=false');
    }).then(function(text) {
      validatePrintData(text);
      if (location.href !== initialUrl || loginUrl(location.href) || loginHtml(document.body && document.body.innerHTML || '') ||
          document.querySelector('#allSemesters') !== initialSelect || JSON.stringify(liveSnapshot()) !== JSON.stringify(live)) {
        fail('采集期间页面或学期已改变，请重新导入');
      }
      finish({ok:true, data:text, periods:[]});
    }).catch(function(error) { finish({ok:false, err:String(error)}); });
  } catch (error) { finish({ok:false, err:String(error)}); }
})();
"""#

    static let JwBuaaCapture = #"""
(function(){
  var finished = false;
  var controller = typeof AbortController !== 'undefined' ? new AbortController() : null;
  var deadline = setTimeout(function(){ fail('课表读取超时，请重试'); }, 20000);
  function finish(payload) {
    if (finished) return;
    finished = true;
    clearTimeout(deadline);
    if (controller) controller.abort();
    window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify(payload)});
  }
  function fail(message) { finish({ok:false, err:message, format:'buaa'}); }
  function scalar(value) { return typeof value === 'string' || typeof value === 'number' ? String(value).trim() : ''; }
  function object(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
  function term(value) {
    var text = scalar(value), code = /^(20[0-9]{2})-(20[0-9]{2})-([1-9])$/.exec(text);
    if (!code) {
      var named = /^(20[0-9]{2})-(20[0-9]{2})学年\s*第\s*([一二三四五六七八九1-9])\s*学期$/.exec(text);
      if (named) code = [text, named[1], named[2], String('一二三四五六七八九'.indexOf(named[3])+1 || Number(named[3]))];
    }
    if (!code || Number(code[2]) !== Number(code[1])+1) throw new Error('已选择的学期格式无法识别');
    return code[1]+'-'+code[2]+'-'+code[3];
  }
  function selectedTerms(W) {
    var values = [], nodes = W.document.querySelectorAll('#kbappTimeXQText,[name="termCode"],#termCode');
    for (var i=0; i<nodes.length; i++) {
      var node = nodes[i], value = scalar(node.value) || scalar(node.getAttribute('value')) || scalar(node.textContent);
      if (value) values.push(term(value));
    }
    var query = new URL(W.location.href).searchParams.getAll('termCode');
    for (var j=0; j<query.length; j++) if (scalar(query[j])) values.push(term(query[j]));
    return values.filter(function(value,index){ return values.indexOf(value) === index; });
  }
  var candidates = [], seen = [];
  function visit(W, depth) {
    if (!W || depth > 8 || seen.indexOf(W) >= 0) return;
    seen.push(W);
    try {
      var location = W.location, host = location.hostname.toLowerCase();
      if ((host === 'buaa.edu.cn' || host.endsWith('.buaa.edu.cn')) && /^https?:$/.test(location.protocol) &&
          location.origin === window.location.origin && /\/sys\/homeapp\//.test(location.pathname)) {
        var terms = selectedTerms(W);
        if (terms.length > 1) throw new Error('页面存在冲突学期，请只保留需要导入的课表');
        if (terms.length === 1) candidates.push({W:W, term:terms[0]});
      }
    } catch(error) {
      // Cross-origin frames are inaccessible. Selected-term validation errors must remain visible.
      if (error && error.message && /学期/.test(error.message)) throw error;
    }
    var frames;
    try { frames = W.frames; } catch(error) { return; }
    for (var i=0; i<frames.length; i++) visit(frames[i], depth+1);
  }
  try {
    visit(window,0);
    if (candidates.length !== 1) throw new Error(candidates.length ? '发现多个课表页面，请只保留需要导入的课表' : '请登录北航教务并打开课表，选择需要导入的学期');
    var selected = candidates[0], W = selected.W;
    var selectedHref = W.location.href;
    function verifySelection() {
      if (finished) throw new Error('采集已结束');
      candidates = []; seen = [];
      visit(window,0);
      if (candidates.length !== 1 || candidates[0].W !== W || candidates[0].term !== selected.term || W.location.href !== selectedHref)
        throw new Error('课表页面或学期已变化，请重新点击导入');
    }
    var prefix = W.location.pathname.indexOf('/jwapp/');
    var path = prefix >= 0 ? W.location.pathname.slice(0,prefix)+'/jwapp/sys/homeapp/api/home/student/getMyScheduleDetail.do' : '../../../sys/homeapp/api/home/student/getMyScheduleDetail.do';
    var url = new URL(path, W.location.href);
    if (url.origin !== W.location.origin) throw new Error('课表地址与当前页面不一致');
    var options = {method:'POST', credentials:'include', mode:'same-origin', redirect:'error',
      headers:{'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8','Accept':'application/json','X-Requested-With':'XMLHttpRequest'},
      body:'termCode='+encodeURIComponent(selected.term)+'&campusCode=&type=term'};
    if (controller) options.signal = controller.signal;
    W.fetch(url.href,options).then(async function(response){
      verifySelection();
      if (!response.ok) throw new Error('课表请求失败 HTTP '+response.status);
      if (response.url && new URL(response.url,url.href).origin !== url.origin) throw new Error('登录状态已变化，请重新登录');
      var text = await response.text();
      verifySelection();
      var result;
      try { result = JSON.parse(text); } catch(error) { throw new Error('课表接口返回不是 JSON，请重新登录'); }
      if (!object(result) || result.success === false || result.success === 'false' || !object(result.datas) || !Array.isArray(result.datas.arrangedList))
        throw new Error('课表响应中没有 arrangedList，请确认学期和登录状态');
      finish({ok:true, data:JSON.stringify(result), xnxq:selected.term, format:'buaa'});
    }).catch(function(error){ fail(String(error && error.message ? error.message : error)); });
  } catch(error) { fail(String(error && error.message ? error.message : error)); }
})();
"""#

    static let JwFduCapture = #"""
(function(){
  var finished = false, deadline = null, controller = null;
  function finish(result) {
    if (finished) return;
    finished = true;
    if (deadline !== null) clearTimeout(deadline);
    if (controller) controller.abort();
    result.format = 'fdu';
    window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify(result)});
  }
  function fail(message) { throw Error(message); }
  function own(object, key) { return Object.prototype.hasOwnProperty.call(object, key); }
  function record(value) { return !!value && typeof value === 'object' && !Array.isArray(value); }
  function id(value) {
    if (typeof value !== 'string' && typeof value !== 'number') return '';
    if (typeof value === 'number' && !Number.isSafeInteger(value)) return '';
    var text = String(value).trim();
    return /^[1-9]\d*$/.test(text) ? text : '';
  }
  function requiredId(value) {
    var result = id(value);
    if (!result) fail('学期编号无效，请在课表页重新选择学期');
    return result;
  }
  function loginUrl(url) {
    return /\/(?:login|cas|sso|sign-?in|auth)(?:\/|$)/i.test(url.pathname);
  }
  function loginDocument(doc) { return !!doc.querySelector('input[type="password"]'); }
  function selectionState(doc) {
    return JSON.stringify(Array.prototype.map.call(doc.querySelectorAll('select'), function(control) {
      return {id:control.id || '', name:control.name || '', value:String(control.value || ''),
        selected:Array.prototype.filter.call(control.options || [], function(option) {
          return option.selected;
        }).map(function(option) { return String(option.value); })};
    }));
  }
  function semesterControl(doc, live) {
    var choices = [], available = [];
    Array.prototype.forEach.call(doc.querySelectorAll('#allSemesters'), function(control) {
      var options = Array.prototype.slice.call(control.options || []);
      var selected = options.filter(function(option) { return option.hasAttribute('selected'); });
      if (selected.length > 1 || (control.selectedOptions && control.selectedOptions.length > 1)) {
        fail('课表页选择了多个学期，请只选择一个学期');
      }
      var valid = options.filter(function(option) { return !!id(option.value); });
      valid.forEach(function(option) { available.push(id(option.value)); });
      var value = String(control.value || ''), index = options.findIndex(function(option) {
        return String(option.value) === value;
      });
      if (live && value) {
        requiredId(value);
        if (index < 0) fail('所选学期不在课表页候选中，请重新选择');
        // An implicit first option among several is not evidence of a user choice.
        if (index > 0 || selected.length === 1 || valid.length === 1) choices.push(value);
      } else if (selected.length === 1) {
        choices.push(requiredId(selected[0].value));
      } else if (valid.length === 1) {
        choices.push(id(valid[0].value));
      }
    });
    choices = choices.filter(function(value, index) { return choices.indexOf(value) === index; });
    if (choices.length > 1) fail('课表页存在不同的学期选择，请重新选择学期');
    return {id:choices[0] || '', ids:available};
  }
  // Decode only a quoted literal; never execute a script from the school page.
  function quoted(text, start) {
    var quote = text[start], result = '';
    if (quote !== '"' && quote !== "'") fail('学期列表格式异常');
    for (var i = start + 1; i < text.length; i++) {
      var c = text[i];
      if (c === quote) return {value:result, end:i + 1};
      if (c === '\n' || c === '\r') fail('学期列表格式异常');
      if (c !== '\\') { result += c; continue; }
      c = text[++i];
      var escapes = {n:'\n', r:'\r', t:'\t', b:'\b', f:'\f', v:'\v', '0':'\0'};
      if (c === 'u' || c === 'x') {
        var size = c === 'u' ? 4 : 2, hex = text.slice(i + 1, i + 1 + size);
        if (!new RegExp('^[0-9a-fA-F]{' + size + '}$').test(hex)) fail('学期列表格式异常');
        result += String.fromCharCode(parseInt(hex, 16)); i += size;
      } else if (c === '\n') {
        continue;
      } else if (c === '\r') {
        if (text[i + 1] === '\n') i++;
      } else if (c === undefined) {
        fail('学期列表格式异常');
      } else {
        result += own(escapes, c) ? escapes[c] : c;
      }
    }
    fail('学期列表未完整返回');
  }
  function semesterRows(doc) {
    var rows = {}, ids = [];
    Array.prototype.forEach.call(doc.querySelectorAll('script'), function(script) {
      var text = script.textContent || '', pattern = /\bvar\s+semesters\s*=\s*JSON\.parse\s*\(\s*/g, match;
      while ((match = pattern.exec(text)) !== null) {
        var literal = quoted(text, pattern.lastIndex);
        if (!/^\s*\)\s*;/.test(text.slice(literal.end))) fail('学期列表格式异常');
        var list;
        try { list = JSON.parse(literal.value); } catch (error) { fail('学期列表 JSON 格式异常'); }
        if (!Array.isArray(list)) fail('学期列表格式异常');
        list.forEach(function(row) {
          if (!record(row)) fail('学期列表格式异常');
          var key = requiredId(row.id);
          if (own(rows, key) && rows[key].startDate !== row.startDate) fail('同一学期的开学日期不一致');
          rows[key] = row; ids.push(key);
        });
        pattern.lastIndex = literal.end;
      }
    });
    return {rows:rows, ids:ids};
  }
  function openingDate(value) {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return '';
    var parts = value.split('-').map(Number), date = new Date(Date.UTC(parts[0], parts[1] - 1, parts[2]));
    if (date.getUTCFullYear() !== parts[0] || date.getUTCMonth() !== parts[1] - 1 ||
        date.getUTCDate() !== parts[2] || date.getUTCDay() !== 0) return '';
    // JWGL's Sunday starts its week. Sleepy's week one begins the following Monday.
    date.setUTCDate(date.getUTCDate() + 1);
    var result = date.toISOString().slice(0, 10);
    return /^\d{4}-\d{2}-\d{2}$/.test(result) ? result : '';
  }
  function validate(text, undergraduate) {
    if (/^\s*</.test(text)) fail('登录态已失效或教务返回了非课表页面，请重新登录');
    var root;
    try { root = JSON.parse(text); } catch (error) { fail('教务课表 JSON 格式无效'); }
    if (!record(root) || root.success === false || root.code === 401 || root.code === '401' ||
        root.code === 403 || root.code === '403') fail('教务没有返回完整课表');
    if (undergraduate) {
      if (own(root, 'results') || !Array.isArray(root.studentTableVms) ||
          !record(root.studentTableVms[0]) || !Array.isArray(root.studentTableVms[0].activities)) {
        fail('本科课表信封无效，请确认已打开本科课表页');
      }
    } else {
      if (own(root, 'studentTableVms') || own(root, 'studentTableVm') || !Array.isArray(root.results) ||
          (root.results.length && !root.results.some(function(row) {
            return record(row) && ['KCMC','ZCBH','XQ','KSJCDM'].every(function(key) { return own(row, key); });
          }))) fail('研究生课表信封无效，请确认已打开研究生课表页');
    }
  }
  (async function(){
    var initial = new URL(window.location.href);
    var undergraduate = initial.origin === 'https://fdjwgl.fudan.edu.cn';
    var postgraduate = initial.origin === 'http://yjsxk.fudan.edu.cn' ||
      initial.origin === 'http://yjsxktest.fudan.sh.cn';
    if ((!undergraduate && !postgraduate) || initial.username || initial.password ||
        loginUrl(initial) || loginDocument(window.document)) {
      fail('请先在复旦本科或研究生教务完成登录，再打开课表页导入');
    }
    var initialSelection = selectionState(window.document);
    var live = undergraduate ? semesterControl(window.document, true) : null;
    controller = new AbortController();
    deadline = setTimeout(function(){ finish({ok:false,err:'教务请求超时，请重新导入'}); }, 18000);
    async function request(path) {
      var url = new URL(path, initial.origin);
      var response = await window.fetch(url.href, {method:'GET', credentials:'include', mode:'same-origin',
        redirect:'error', signal:controller.signal});
      if (finished) fail('采集已结束');
      if (!response.ok || response.status < 200 || response.status >= 300) fail('教务请求失败 HTTP ' + response.status);
      if (!response.url) fail('教务响应缺少最终地址');
      var finalUrl = new URL(response.url);
      if (finalUrl.origin !== initial.origin || loginUrl(finalUrl) || response.redirected ||
          response.headers.get('location') || finalUrl.href !== url.href) {
        fail('教务响应离开课表接口或登录态已失效，请重新登录');
      }
      var text = await response.text();
      if (finished) fail('采集已结束');
      return {text:text, contentType:response.headers.get('content-type') || ''};
    }
    var semesterId = '', sourceStartDate = '', startDate = '', data;
    if (undergraduate) {
      var index = await request('/student/for-std/course-table');
      if (!/^\s*</.test(index.text) || !/text\/html/i.test(index.contentType)) fail('本科课表入口响应格式无效');
      var doc = new DOMParser().parseFromString(index.text, 'text/html');
      if (loginDocument(doc)) fail('登录态已失效，请重新登录');
      var server = semesterControl(doc, false), metadata = semesterRows(doc);
      var available = server.ids.concat(metadata.ids).filter(function(value, index, all) { return all.indexOf(value) === index; });
      semesterId = live.id || server.id || (available.length === 1 ? available[0] : '');
      if (!semesterId || available.indexOf(semesterId) < 0 ||
          (metadata.ids.length && metadata.ids.indexOf(semesterId) < 0)) {
        fail('无法唯一确定学期，请在本科课表页明确选择学期后导入');
      }
      var row = metadata.rows[semesterId];
      sourceStartDate = row && typeof row.startDate === 'string' ? row.startDate : '';
      startDate = openingDate(sourceStartDate);
      data = await request('/student/for-std/course-table/semester/' + semesterId + '/print-data');
    } else {
      // The source establishes no semester query or opening date for this PG interface.
      data = await request('/yjsxkapp/sys/xsxkappfudan/xsxkCourse/loadKbxx.do?_=' + Date.now());
    }
    validate(data.text, undergraduate);
    if (window.location.href !== initial.href || selectionState(window.document) !== initialSelection ||
        loginDocument(window.document)) fail('采集期间页面或学期已改变，请重新导入');
    finish({ok:true, data:data.text, variant:undergraduate ? 'undergraduate' : 'postgraduate',
      semesterId:semesterId, sourceStartDate:sourceStartDate, startDate:startDate, periods:[]});
  })().catch(function(error){ finish({ok:false,err:String(error.message || error)}); });
})();
"""#

    static let JwJsonSchoolCapture = #"""
(async function () {
  'use strict';
  var type = '__SCHOOL_TYPE__', finished = false, W = null;
  var controller = typeof AbortController === 'function' ? new AbortController() : null;
  var timer = setTimeout(function () { fail('课表读取超时，请等待页面加载完成后重试'); }, 60000);
  function finish(result) {
    if (finished) return;
    finished = true; clearTimeout(timer);
    if (controller) controller.abort();
    window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify(result)});
  }
  function fail(message) { finish({ok:false, format:type, err:message}); }
  function object(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
  function text(value) { return typeof value === 'string' || typeof value === 'number' ? String(value).trim() : ''; }
  function query(name, root) {
    var values = [], doc = root || W.document;
    Array.prototype.forEach.call(doc.querySelectorAll('[name="' + name + '"],#' + name), function (node) {
      var value = text(node.value);
      if (value && values.indexOf(value) < 0) values.push(value);
    });
    if (values.length > 1) throw Error('页面有多个不同的' + name + '值，请仅打开需要导入的课表');
    return values[0] || '';
  }
  function eitherName(first, second) {
    var a = query(first), b = query(second);
    if (a && b && a !== b) throw Error('页面学期控件值不一致');
    return a || b;
  }
  function candidateFrames(w, depth, candidates) {
    if (depth > 8) throw Error('课表页面嵌套过深，请直接打开需要导入的课表');
    var children = [];
    try {
      var host = w.location.hostname.toLowerCase(), path = w.location.pathname;
      var allowed = type === 'sustech' ? host === 'tis.sustech.edu.cn' :
        type === 'shsmu' ? (host === 'jwstu.shsmu.edu.cn' || host === 'webvpn2.shsmu.edu.cn') && /\/Home\//i.test(path) :
        type === 'ygu' ? host === 'ygu.edu.cn' : !!w.document.querySelector('#kcbForm');
      if (allowed && /^https?:$/.test(w.location.protocol)) candidates.push(w);
      for (var i=0; i<w.frames.length; i++) children.push(w.frames[i]);
    } catch (_) {}
    for (var j=0; j<children.length; j++) candidateFrames(children[j], depth+1, candidates);
    return candidates;
  }
  try {
    var candidates = candidateFrames(window, 0, []);
    if (candidates.length !== 1) throw Error(candidates.length ? '页面有多个课表，请仅打开需要导入的课表' : '请登录教务系统并打开需要导入的课表页面');
    W = candidates[0];
  } catch (selectionError) { fail(String(selectionError)); return; }
  var initialHref = W.location.href, initialDocument = W.document;
  function samePage() {
    if (finished) throw Error('采集已结束');
    var candidates = candidateFrames(window, 0, []);
    if (candidates.length !== 1 || candidates[0] !== W || W.document !== initialDocument || W.location.href !== initialHref) throw Error('采集期间课表页面已切换，请重新导入');
  }
  async function request(target, body, json) {
    samePage();
    var url = new URL(target, initialHref);
    if (url.origin !== W.location.origin || url.username || url.password) throw Error('课表接口与当前登录页面不同源');
    var init = {method:body === undefined ? 'GET' : 'POST', credentials:'include', mode:'same-origin', redirect:'error'};
    if (controller) init.signal = controller.signal;
    if (body !== undefined) {
      init.headers = {'Content-Type':json ? 'application/json;charset=UTF-8' : 'application/x-www-form-urlencoded;charset=UTF-8'};
      if (json) init.body = JSON.stringify(body);
      else { var form = new URLSearchParams(); Object.keys(body).forEach(function (key) { form.append(key, body[key]); }); init.body = form.toString(); }
    }
    var response = await W.fetch(url.href, init);
    samePage();
    if (!response.ok) throw Error('课表请求失败 HTTP ' + response.status);
    var finalUrl = new URL(response.url || url.href, url.href);
    if (finalUrl.origin !== url.origin || finalUrl.pathname !== url.pathname || finalUrl.search !== url.search) throw Error('登录状态已变化，请重新登录');
    var raw = await response.text(); samePage();
    return raw;
  }
  function parseJson(raw) {
    var result = JSON.parse(raw);
    if (!object(result) && !Array.isArray(result)) throw Error('课表接口未返回 JSON 对象或数组');
    if (object(result) && (result.success === false || result.success === 'false')) throw Error('课表接口未返回成功结果');
    return result;
  }
  async function jsonRequest(target, body, json) { return parseJson(await request(target, body, json)); }
  function date(value) {
    value = text(value);
    if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(value)) return '';
    var ms = Date.parse(value + 'T00:00:00Z');
    return Number.isFinite(ms) && new Date(ms).toISOString().slice(0,10) === value && value.slice(0,4) !== '0000' ? value : '';
  }
  function recentRequest(pattern) {
    var entries = W.performance && W.performance.getEntriesByType('resource') || [];
    return entries.map(function (entry) {
      try { var url = new URL(entry.name, initialHref); return url.origin === W.location.origin && pattern.test(url.pathname) ? {url:url, time:entry.startTime} : null; }
      catch (_) { return null; }
    }).filter(Boolean).sort(function (a,b) { return b.time-a.time; })[0];
  }
  async function sustech() {
    var originalXn = eitherName('xn','XN'), originalXq = eitherName('xq','XQ');
    var xn = originalXn, xq = originalXq;
    if (!xn && !xq) {
      // Existing vendored SUSTECH script, not the pinned WakeUp login implementation.
      var current = await jsonRequest('/component/querydangqianxnxq', {});
      xn = text(current.XN); xq = text(current.XQ);
    }
    if (/^[0-9]{4}$/.test(xn)) xn += '-' + (Number(xn)+1);
    var years = /^([0-9]{4})-([0-9]{4})$/.exec(xn);
    if (!years || Number(years[2]) !== Number(years[1])+1 || !/^[0-9]+$/.test(xq) || Number(xq) <= 0) throw Error('未取得明确的学年学期，请在课表页面选择学期');
    var result = await jsonRequest('/xszykb/queryxszykbzong', {xn:xn,xq:xq});
    var rows = Array.isArray(result) ? result : Array.isArray(result.content) ? result.content : result.data;
    if (!Array.isArray(rows) || !rows.every(function (row) { return object(row) && (row.KEY === 'bz' || /^xq[1-7]_jc[0-9]+$/.test(text(row.KEY)) && typeof row.SKSJ === 'string'); })) throw Error('课表响应缺少完整课程数组');
    if (eitherName('xn','XN') !== originalXn || eitherName('xq','XQ') !== originalXq) throw Error('采集期间所选学期发生变化');
    if (!originalXn && !originalXq) {
      var check = await jsonRequest('/component/querydangqianxnxq', {});
      var checkXn = text(check.XN); if (/^[0-9]{4}$/.test(checkXn)) checkXn += '-' + (Number(checkXn)+1);
      if (checkXn !== xn || text(check.XQ) !== xq) throw Error('采集期间当前学期发生变化');
    }
    if (eitherName('xn','XN') !== originalXn || eitherName('xq','XQ') !== originalXq) throw Error('采集期间所选学期发生变化');
    finish({ok:true,format:type,data:JSON.stringify(rows),semester:xn+'-'+xq});
  }
  async function shsmu() {
    var current = new URL(initialHref), observed = /\/Home\/GetCurriculumTable$/i.test(current.pathname) ? current : null;
    var fromPerformance = !observed;
    if (!observed) { var latest = recentRequest(/\/Home\/GetCurriculumTable$/i); observed = latest && latest.url; }
    var controlStart = query('Start'), controlEnd = query('End');
    fromPerformance = fromPerformance && (!controlStart || !controlEnd);
    var rangeStart = controlStart || (observed && observed.searchParams.get('Start')) || '';
    var rangeEnd = controlEnd || (observed && observed.searchParams.get('End')) || '';
    rangeStart = date(rangeStart); rangeEnd = date(rangeEnd);
    if (!rangeStart || !rangeEnd || rangeEnd < rangeStart) throw Error('请在课表页面选择待导入的起止日期，等待课表加载后再导入');
    var marker = /\/Home\//i.exec(current.pathname);
    var target = new URL(current.pathname.slice(0,marker.index) + '/Home/GetCurriculumTable', initialHref);
    target.searchParams.set('Start',rangeStart); target.searchParams.set('End',rangeEnd);
    var result = await jsonRequest(target.href);
    if (!object(result) || !Array.isArray(result.list) || !result.list.every(object)) throw Error('课表接口未返回课程列表');
    var checkStart = query('Start'), checkEnd = query('End');
    if (checkStart !== controlStart || checkEnd !== controlEnd) throw Error('采集期间日期范围发生变化');
    if (fromPerformance) {
      var latestAfter = recentRequest(/\/Home\/GetCurriculumTable$/i), observedAfter = latestAfter && latestAfter.url;
      if (!observedAfter || observedAfter.pathname !== target.pathname || date(observedAfter.searchParams.get('Start')) !== rangeStart || date(observedAfter.searchParams.get('End')) !== rangeEnd) throw Error('采集期间日期范围发生变化');
    }
    result.sleepyShsmuCapture = true;
    result.rangeStart = rangeStart; result.rangeEnd = rangeEnd;
    // A requested range may be a single displayed week. It does not prove week one.
    delete result.semesterStartDate; delete result.semesterStartBasis;
    finish({ok:true,format:type,data:JSON.stringify(result),requiresSemesterStart:true,calendarBasis:'unknown'});
  }
  function yguSelected() {
    var selected = query('xqjc');
    var url = new URL(initialHref), direct = text(url.searchParams.get('xqjc'));
    var hashQuery = url.hash.indexOf('?') >= 0 ? new URLSearchParams(url.hash.slice(url.hash.indexOf('?')+1)).get('xqjc') : '';
    var values = [selected,direct,text(hashQuery)].filter(Boolean);
    if (values.some(function (value) { return value !== values[0]; })) throw Error('页面学期值不一致，请重新选择学期');
    return values[0] || '';
  }
  async function ygu() {
    var selected = yguSelected();
    var terms = await jsonRequest('/api/jw/xlgl/listR', {}, true);
    if (!object(terms) || text(terms.code) !== '0' || !Array.isArray(terms.data)) throw Error('获取学期列表失败');
    var values = terms.data.map(function (item) { return object(item) ? text(item.xqjc) : ''; });
    if (values.some(function (value) { return !value; }) || new Set(values).size !== values.length) throw Error('学期列表不完整或重复');
    var term = selected || (values.length === 1 ? values[0] : '');
    if (!term || values.indexOf(term) < 0) throw Error('请在课表页面明确选择学期后再导入');
    var user = await jsonRequest('/api/system/user/getInfo');
    if (!object(user) || text(user.code) !== '0' || !object(user.user)) throw Error('获取用户基本信息失败');
    var number = text(user.user.studentsNumber), name = text(user.user.nickName);
    if (!number || !name) throw Error('当前登录信息缺少学生学号或姓名');
    var result = await jsonRequest('/api/jw/kpkglkcb/student', {xm:name,xh:number,xqjc:term}, true);
    if (!object(result) || text(result.code) !== '0' || !Array.isArray(result.data) || !result.data.every(function (day) {
      return object(day) && Array.isArray(day.weekList) && day.weekList.every(function (week) { return object(week) && Array.isArray(week.kcbVoList); });
    })) throw Error('课表接口未返回完整日程数组');
    if (result.xqjc !== undefined && text(result.xqjc) !== term) throw Error('课表响应学期与所选学期不同');
    if (yguSelected() !== selected) throw Error('采集期间所选学期发生变化');
    finish({ok:true,format:type,data:JSON.stringify(result),semester:term});
  }
  function weekValues(doc) {
    var select = doc.querySelector('#zc');
    if (!select) return null;
    var options = Array.prototype.slice.call(select.options || []);
    if (!options.length) throw Error('课表周次列表为空');
    var all = options.filter(function (option) { return /全/.test(text(option.textContent)); });
    if (all.length > 1) throw Error('课表包含多个全部周次选项');
    var chosen = all.length ? all : options;
    var values = chosen.map(function (option) { return text(option.value); });
    if (values.some(function (value) { return !/^-?[0-9]+$/.test(value) || !Number.isSafeInteger(Number(value)) || !all.length && Number(value) <= 0; }) || new Set(values).size !== values.length) throw Error('课表周次列表无效');
    return values;
  }
  async function zju() {
    var form = W.document.querySelector('#kcbForm');
    if (!form || W.document.querySelector('input[type="password"]')) throw Error('请打开研究生课表页面再导入');
    var semester = [query('xnxq'),query('xn'),query('xq')];
    var values = weekValues(W.document), signature = JSON.stringify(values), pages = [];
    if (!values) pages.push(W.document.documentElement.outerHTML);
    else for (var i=0; i<values.length; i++) {
      var url = new URL(initialHref); url.searchParams.set('zc',values[i]);
      var raw = await request(url.href), page = new W.DOMParser().parseFromString(raw,'text/html');
      if (!page.querySelector('#kcbForm') || page.querySelector('input[type="password"]')) throw Error('第'+values[i]+'周未返回课表页面，请重新登录');
      var responseWeeks = weekValues(page);
      if (JSON.stringify(responseWeeks) !== signature) throw Error('采集期间课表周次列表发生变化');
      pages.push(raw);
    }
    if (JSON.stringify(weekValues(W.document)) !== signature) throw Error('采集期间周次列表发生变化');
    if (JSON.stringify([query('xnxq'),query('xn'),query('xq')]) !== JSON.stringify(semester)) throw Error('采集期间所选学期发生变化');
    finish({ok:true,format:type,data:JSON.stringify(pages),requestedWeeks:values || []});
  }
  try { await (type === 'sustech' ? sustech() : type === 'shsmu' ? shsmu() : type === 'ygu' ? ygu() : zju()); }
  catch (error) { fail(text(error && error.message) || '课表读取失败'); }
})();
"""#

    static let JwPagedSchoolCapture = #"""
(function(){
  var type='__SCHOOL_TYPE__', finished=false;
  var controller=typeof AbortController !== 'undefined' ? new AbortController() : null;
  var deadline=setTimeout(function(){ fail('课表读取超时，请重试'); },60000);
  function finish(result){
    if(finished)return;
    if(result.ok){try{samePage();}catch(e){result={ok:false,format:type,err:e.message};}}
    finished=true;clearTimeout(deadline);
    if(controller)controller.abort();
    window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify(result)});
  }
  function fail(message){ finish({ok:false,format:type,err:message}); }
  function object(value){ return value!==null && typeof value==='object' && !Array.isArray(value); }
  function scalar(value){ return typeof value==='string' || typeof value==='number' ? String(value).trim() : ''; }
  function candidateFrames(w,depth,candidates){
    if(depth>8)throw new Error('课表页面嵌套过深，请直接打开需要导入的课表');
    var children=[];
    try {
      var path=w.location.pathname;
      if(/^https?:$/.test(w.location.protocol) && (type==='fstvc' ? /\/studentportal\.php(?:\/|$)/.test(path) :
          /\/(?:Login\/MainDesktop|student(?:\/|$))/.test(path)))candidates.push(w);
      for(var i=0;i<w.frames.length;i++)children.push(w.frames[i]);
    }catch(e){}
    for(var j=0;j<children.length;j++)candidateFrames(children[j],depth+1,candidates);
  }
  function controlState(doc){
    var nodes=doc.querySelectorAll('input,select,textarea');
    if(nodes.length>10000)throw new Error('页面控件过多，请直接打开课表');
    return JSON.stringify(Array.prototype.map.call(nodes,function(n){
      return [n.tagName,n.name || '',n.id || '',n.type || '',scalar(n.value),!!n.checked,
        n.options ? Array.prototype.map.call(n.options,function(o){return [scalar(o.value),!!o.selected];}) : null];
    }));
  }
  var W,initialDocument,initialHref,initialControls;
  try{
    var candidates=[];candidateFrames(window,0,candidates);
    if(candidates.length!==1)throw new Error('请仅打开一个学生课表页面');
    W=candidates[0];initialDocument=W.document;initialHref=W.location.href;initialControls=controlState(initialDocument);
  }catch(e){fail(e.message);return;}
  function samePage(){
    if(finished)throw new Error('采集已结束');
    var candidates=[];candidateFrames(window,0,candidates);
    if(candidates.length!==1 || candidates[0]!==W || W.document!==initialDocument || W.location.href!==initialHref)
      throw new Error('采集期间课表页面发生变化，请重试');
    if(controlState(initialDocument)!==initialControls)throw new Error('采集期间所选学期或页面控件发生变化，请重试');
  }
  async function request(path,fields,html){
    samePage();
    var url=new URL(path,initialHref);
    if(url.origin!==W.location.origin || url.username || url.password)throw new Error('课表接口与当前页面不一致');
    var options={method:fields?'POST':'GET',credentials:'include',mode:'same-origin',redirect:'error'};
    if(controller)options.signal=controller.signal;
    if(fields)options.body=new URLSearchParams(fields);
    var response=await W.fetch(url.href,options);
    samePage();
    if(!response.ok)throw new Error('课表请求失败 HTTP '+response.status);
    var finalUrl=new URL(response.url || url.href,url.href);
    if(finalUrl.origin!==url.origin || finalUrl.pathname!==url.pathname || finalUrl.search!==url.search)
      throw new Error('登录状态已变化，请重新登录');
    var text=await response.text();
    samePage();
    if(html)return text;
    var data=JSON.parse(text);
    if(!object(data) || data.success===false || data.success==='false')throw new Error('课表接口未返回成功结果');
    return data;
  }
  function total(value){
    var text=scalar(value);
    if(!/^[0-9]+$/.test(text) || Number(text)>100000)throw new Error('课程总数无效');
    return Number(text);
  }
  async function fetchPages(fetchPage,key,size,requireTotal){
    var rows=[],knownTotal=null,seen=new Set(),first;
    for(var page=1;page<=4000;page++){
      var result=await fetchPage(page);
      if(!first)first=result;
      if(!Array.isArray(result[key]))throw new Error('课表接口未返回课程数组');
      var items=result[key];
      if(items.length>size)throw new Error('课表分页格式不正确');
      var count=result.total===undefined || result.total===null ? null : total(result.total);
      if(requireTotal && count===null)throw new Error('课表缺少课程总数');
      if(count!==null){
        if(knownTotal!==null && knownTotal!==count)throw new Error('采集期间课程总数发生变化，请重试');
        knownTotal=count;
      }
      if(knownTotal!==null && items.length!==Math.min(size,Math.max(0,knownTotal-rows.length)))throw new Error('课表分页不完整，请重试');
      if(items.length){
        var fingerprint=JSON.stringify(items);
        if(seen.has(fingerprint))throw new Error('课表接口返回重复页面，请重试');
        seen.add(fingerprint);
      }
      rows=rows.concat(items);
      if(rows.length>100000)throw new Error('课表数据过多');
      if(knownTotal!==null ? rows.length===knownTotal : items.length<size){first[key]=rows;return first;}
    }
    throw new Error('课表分页未结束');
  }
  function fstvcEndpoint(html,prefix){
    var table=new DOMParser().parseFromString(html,'text/html').querySelector('table#mainlist');
    var match=table && /\burl\s*:\s*(['"])(.*?)\1/.exec(table.getAttribute('data-options') || '');
    if(!match || !match[2].trim())throw new Error('未找到课表接口，请重新打开学习进度页面');
    var path=match[2].trim();
    if(/^(?:[a-z][a-z0-9+.-]*:|\/\/)/i.test(path)){
      var absolute=new URL(path,W.location.href);
      if(absolute.origin!==W.location.origin || absolute.username || absolute.password)throw new Error('课表接口与当前页面不一致');
      path=absolute.href;
    }else{path=prefix+'/'+path.replace(/^\/+/, '');}
    var resolved=new URL(path,initialHref);
    if(resolved.origin!==W.location.origin || resolved.username || resolved.password)throw new Error('课表接口与当前页面不一致');
    return resolved.href;
  }
  async function fstvc(){
    var prefix=W.location.pathname.slice(0,W.location.pathname.indexOf('/studentportal.php'));
    var sourcePath=prefix+'/studentportal.php/Jxxx/xxjdxx';
    var path=fstvcEndpoint(await request(sourcePath,null,true),prefix);
    var result=await fetchPages(function(page){return request(path,{page:String(page),rows:'30',zc:'0',sort:'skrq',order:'asc'});},'rows',30,true);
    if(fstvcEndpoint(await request(sourcePath,null,true),prefix)!==path)throw new Error('采集期间所选课表接口发生变化，请重试');
    finish({ok:true,format:type,data:JSON.stringify(result.rows)});
  }
  async function gdbh(){
    var marker=/\/(?:Login\/MainDesktop|student(?:\/|$))/.exec(W.location.pathname);
    var prefix=W.location.pathname.slice(0,marker.index);
    var info=await request(prefix+'/student/StuInfo');
    var term=scalar(info.term);
    if(!term)throw new Error('未取得当前学期，请重新登录教务系统');
    var result=await fetchPages(function(page){
      return request(prefix+'/student/getstutable?_dc='+Date.now()+'&term='+encodeURIComponent(term)+'&page='+page+'&start='+((page-1)*50)+'&limit=50');
    },'data',50,false);
    var check=await request(prefix+'/student/StuInfo');
    if(scalar(check.term)!==term)throw new Error('采集期间所选学期发生变化，请重试');
    finish({ok:true,format:type,data:JSON.stringify(result)});
  }
  (type==='fstvc'?fstvc():gdbh()).catch(function(e){fail(e && e.message ? e.message : '课表读取失败');});
})();
"""#

    static let JwSchoolApiCapture = #"""
(function(){
  var type = '__SCHOOL_TYPE__';
  var finished = false;
  var controller = typeof AbortController !== 'undefined' ? new AbortController() : null;
  var deadline = setTimeout(function(){ fail('课表读取超时，请重试'); }, 20000);
  function finish(result) {
    if (finished) return;
    if (result.ok) {
      try { samePage(); } catch(e) { result = {ok:false, err:e.message, format:type}; }
    }
    finished = true;
    clearTimeout(deadline);
    if (controller) controller.abort();
    window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify(result)});
  }
  function fail(message) { finish({ok:false, err:message, format:type}); }
  function object(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
  function scalar(value) {
    return typeof value === 'string' || typeof value === 'number' ? String(value).trim() : '';
  }
  function positiveInt(value) {
    var text = scalar(value);
    return /^[0-9]+$/.test(text) && Number(text) >= 1 && Number(text) <= 366 ? Number(text) : 0;
  }
  var selector = type === 'ccibe' ? '#rc_select_0_list [aria-selected="true"]' :
    type === 'jlu_post' ? '#myXnxqSelect' : '.je-grid-btnbar-queryStrategy';
  function candidateFrames(w, depth, candidates) {
    if (depth > 8) throw new Error('课表页面嵌套过深，请直接打开需要导入的课表');
    var children = [];
    try {
      var host = w.location.hostname.toLowerCase();
      var allowed = type === 'ccibe' ? host === 'my.vpn.ccibe.edu.cn' || host === 'my.ccibe.edu.cn' :
        type === 'jlu_post' ? (host === 'jlu.edu.cn' || host.endsWith('.jlu.edu.cn')) && w.location.pathname.indexOf('/gsapp/sys/') >= 0 :
        host === 'jw.cppu.edu.cn';
      if (allowed && /^https?:$/.test(w.location.protocol) && w.document.querySelector(selector)) candidates.push(w);
      for (var i=0; i<w.frames.length; i++) children.push(w.frames[i]);
    } catch(e) {}
    for (var j=0; j<children.length; j++) candidateFrames(children[j], depth+1, candidates);
  }
  function controlState(doc) {
    var nodes = doc.querySelectorAll('input,select,textarea');
    if (nodes.length > 10000) throw new Error('页面控件过多，请直接打开课表');
    return JSON.stringify(Array.prototype.map.call(nodes, function(n){
      return [n.tagName,n.name || '',n.id || '',n.type || '',scalar(n.value),!!n.checked,
        n.options ? Array.prototype.map.call(n.options,function(o){return [scalar(o.value),!!o.selected];}) : null];
    }));
  }
  function selectionState(doc) {
    var nodes = doc.querySelectorAll(selector);
    return JSON.stringify(Array.prototype.map.call(nodes, function(n){
      if (type === 'ccibe') return scalar(n.textContent);
      if (type === 'jlu_post') return scalar(n.value) || scalar(n.options && n.options[0] && n.options[0].value);
      return n.parentElement ? Array.prototype.filter.call(n.parentElement.childNodes,function(c){return c.nodeType === 3;})
        .map(function(c){return c.textContent || '';}).join(' ') : '';
    }));
  }
  var W, initialDocument, initialHref, initialControls, initialSelection;
  try {
    var candidates = []; candidateFrames(window,0,candidates);
    if (candidates.length !== 1) throw new Error('请仅打开一个已选择学期的教务课表页面');
    W = candidates[0]; initialDocument = W.document; initialHref = W.location.href;
    initialControls = controlState(initialDocument); initialSelection = selectionState(initialDocument);
  } catch(e) { fail(e.message); return; }
  function samePage() {
    if (finished) throw new Error('采集已结束');
    var candidates = []; candidateFrames(window,0,candidates);
    if (candidates.length !== 1 || candidates[0] !== W || W.document !== initialDocument || W.location.href !== initialHref)
      throw new Error('采集期间课表页面发生变化，请重试');
    if (controlState(initialDocument) !== initialControls || selectionState(initialDocument) !== initialSelection)
      throw new Error('采集期间所选学期或页面控件发生变化，请重试');
  }
  async function request(path, fields) {
    samePage();
    var url = new URL(path, initialHref);
    if (url.origin !== W.location.origin || url.username || url.password) throw new Error('课表地址与当前页面不一致');
    var options = {method:fields ? 'POST' : 'GET', credentials:'include', mode:'same-origin', redirect:'error'};
    if (controller) options.signal = controller.signal;
    if (fields) {
      var form = new FormData();
      Object.keys(fields).forEach(function(key){ form.append(key, fields[key]); });
      options.body = form;
    }
    var response = await W.fetch(url.href, options);
    samePage();
    if (!response.ok) throw new Error('课表请求失败 HTTP ' + response.status);
    var finalUrl = new URL(response.url || url.href, url.href);
    if (finalUrl.origin !== url.origin || finalUrl.pathname !== url.pathname || finalUrl.search !== url.search)
      throw new Error('登录状态已变化，请重新登录');
    var text = await response.text(); samePage();
    var result = JSON.parse(text);
    if (!object(result) || result.success === false || result.success === 'false') throw new Error('课表接口未返回成功结果');
    return result;
  }
  async function ccibe() {
    var selected = scalar(W.document.querySelector(selector).textContent);
    if (!selected) throw new Error('未找到已选择的学期');
    var path = '/api/manager/synchronize/synchronizestudent/curriculumNew';
    var first = await request(path + '?calendarId=' + encodeURIComponent(selected) + '&week=');
    var data = first.data;
    if (!object(data) || !object(data.calendar)) throw new Error('未取得学期日历');
    var calendar = data.calendar, id = scalar(calendar.id), count = positiveInt(calendar.allWeek);
    if (!id || !count || !scalar(calendar.startTime)) throw new Error('学期日历不完整');
    var weeks = [];
    for (var week=1; week<=count; week++) {
      var response = await request(path + '?calendarId=' + encodeURIComponent(id) + '&week=' + week);
      var page = response.data;
      if (!object(page) || !Array.isArray(page.wdkb)) throw new Error('第' + week + '周课表不完整');
      if (page.calendar && scalar(page.calendar.id) !== id) throw new Error('采集期间学期发生变化');
      weeks.push({week:week, data:page});
    }
    var check = await request(path + '?calendarId=' + encodeURIComponent(selected) + '&week=');
    var checked = check.data && check.data.calendar;
    if (!object(checked) || scalar(checked.id) !== id || positiveInt(checked.allWeek) !== count ||
        scalar(checked.startTime) !== scalar(calendar.startTime)) throw new Error('采集期间学期日历发生变化，请重试');
    finish({ok:true, format:type, data:JSON.stringify({calendar:calendar, time:data.time || [], weeks:weeks})});
  }
  async function cppu() {
    var control = W.document.querySelector(selector);
    // The upstream selector reads ownText(), excluding nested button labels.
    var label = control.parentElement ? Array.prototype.filter.call(control.parentElement.childNodes, function(n){
      return n.nodeType === 3;
    }).map(function(n){ return n.textContent || ''; }).join(' ') : '';
    var termPath = '/je/system/' + (label.indexOf('下一') >= 0 ? 'getNowNextXnxq' : 'getNowXnxq');
    var term = await request(termPath);
    var code = object(term.data) ? scalar(term.data.values && term.data.values.DM) : scalar(term.data);
    if (!code) throw new Error('未取得所选学期');
    var calendar = await request('/edumis_je/pkgl/pksz/xlsj/getClassFormDefault.action', {xnxqCode:code});
    var startDate = scalar(calendar.jxzqsrq);
    if (!startDate) throw new Error('未取得学期起始日期');
    var result = await request('/je/load', {
      funcCode:'V_JWBZK_PK_XSKBZHCX', funcId:'n3VPye8LJPUucKtVB1H', columnLazy:'true', mark:'false', postil:'',
      funcEdit:'false', coverJquery:'0', tableCode:'V_JWBZK_PK_XSKBZHCX', _isFunc_:'true',
      j_query:JSON.stringify({custom:[{type:'and',value:[{type:'=',code:'XNXQ_CODE',value:code,cn:'and'}]}],_custom_types:['strategy']}),
      j_order:'[]', dbQueryObj:'{}', page:'1', start:'0', limit:'100000'
    });
    if (!Array.isArray(result.rows)) throw new Error('课表接口未返回课程数组');
    for (var key of ['totalCount','total']) {
      if (result[key] !== undefined && result[key] !== null) {
        var total = scalar(result[key]);
        if (!/^[0-9]+$/.test(total) || Number(total) !== result.rows.length) throw new Error('课表响应不完整，请重试');
      }
    }
    var checkTerm = await request(termPath);
    var checkedCode = object(checkTerm.data) ? scalar(checkTerm.data.values && checkTerm.data.values.DM) : scalar(checkTerm.data);
    if (checkedCode !== code) throw new Error('采集期间所选学期发生变化，请重试');
    var checkCalendar = await request('/edumis_je/pkgl/pksz/xlsj/getClassFormDefault.action', {xnxqCode:code});
    if (scalar(checkCalendar.jxzqsrq) !== startDate) throw new Error('采集期间学期日历发生变化，请重试');
    result.startDate = startDate;
    finish({ok:true, format:type, data:JSON.stringify(result)});
  }
  async function jlu() {
    var select = W.document.querySelector(selector);
    var term = scalar(select.value) || scalar(select.options && select.options[0] && select.options[0].value);
    if (!term) throw new Error('未找到所选学期，请等待课表加载完成');
    var prefix = W.location.pathname.slice(0, W.location.pathname.indexOf('/gsapp/sys/'));
    var result = await request(prefix + '/gsapp/sys/wdkbapp/modules/xskcb/xsjxrwcx.do?XNXQDM=' + encodeURIComponent(term));
    var page = result.datas && result.datas.xsjxrwcx;
    if (!object(page) || !Array.isArray(page.rows)) throw new Error('课表接口未返回课程数组');
    if (page.totalSize !== undefined && page.totalSize !== null) {
      // WISEDU uses -1 when the query does not compute a total count.
      var total = scalar(page.totalSize);
      if (total !== '-1' && (!/^[0-9]+$/.test(total) || Number(total) !== page.rows.length)) {
        throw new Error('课表响应不完整，请重试');
      }
    }
    finish({ok:true, format:type, data:JSON.stringify(result)});
  }
  (type === 'ccibe' ? ccibe() : type === 'jlu_post' ? jlu() : cppu()).catch(function(e){
    fail(e && e.message ? e.message : '课表读取失败');
  });
})();
"""#

    static let JwTreewiseJsonCapture = #"""
(async function(){
  var type = '__TREEWISE_TYPE__', finished = false;
  var controller = typeof AbortController !== 'undefined' ? new AbortController() : null;
  var deadline = setTimeout(function(){fail('课表读取超时，请重试');},20000);
  function finish(result) {
    if (finished) return;
    finished = true; clearTimeout(deadline); if (controller) controller.abort();
    window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify(result)});
  }
  function fail(message) {finish({ok:false,err:message,format:'treewise-'+type});}
  function object(v) {return v !== null && typeof v === 'object' && !Array.isArray(v);}
  function scalar(v) {return typeof v === 'string' || typeof v === 'number' ? String(v).trim() : '';}
  function id(v) {if(typeof v==='number'&&!Number.isSafeInteger(v))throw new Error('页面标识不是精确整数');var s=scalar(v); if (!/^[1-9][0-9]*$/.test(s)) throw new Error('页面标识格式无法识别'); return s;}
  function unique(values,label,required) {
    values=values.filter(function(v,i){return values.indexOf(v)===i;});
    if (values.length>1) throw new Error('页面存在冲突的'+label);
    if (!values.length && required) throw new Error('页面没有当前'+label+'，请打开课表并完成选择');
    return values.length ? values[0] : '';
  }
  function semester(W) {
    var values=[], nodes=W.document.querySelectorAll('#allSemesters,[name="semesterId"],#semesterId,option[name="semesterAssoc"]');
    for(var i=0;i<nodes.length;i++) {
      var n=nodes[i]; if(String(n.tagName).toLowerCase()==='option' && !n.selected) continue;
      var v=scalar(n.value); if(v) values.push(id(v));
    }
    var query=new URL(W.location.href).searchParams.getAll('semesterId');
    for(var j=0;j<query.length;j++) if(scalar(query[j])) values.push(id(query[j]));
    var path=/\/semester\/([1-9][0-9]*)\//.exec(W.location.pathname);
    if(path) values.push(path[1]);
    return unique(values,'学期',true);
  }
  function pageId(W,name,array) {
    var values=[];
    function add(v) {
      if(array) {if(!Array.isArray(v)||v.length!==1) throw new Error('页面学生标识不是唯一值');v=v[0];}
      if(v!==undefined && v!==null && v!=='') values.push(id(v));
    }
    if(W[name]!==undefined) add(W[name]);
    var scripts=W.document.querySelectorAll('script'), pattern=new RegExp('(?:var|let|const)\\s+'+name+'\\s*=\\s*([^;]+);','g');
    for(var i=0;i<scripts.length;i++) {
      var text=scripts[i].textContent || '',m;
      while((m=pattern.exec(text))) {
        var raw=m[1].trim();if(!array && /^(?:null|undefined|''|""|['"].*\$.*['"])$/.test(raw))continue;var number=array ? /^\[\s*['"]?([1-9][0-9]*)['"]?\s*\]$/.exec(raw) : /^['"]?([1-9][0-9]*)['"]?$/.exec(raw);
        if(!number) throw new Error('页面'+name+'标识格式无法识别');
        values.push(number[1]);
      }
    }
    return unique(values,name,false);
  }
  function pageBiz(W) {
    var values=[], v=pageId(W,'bizTypeId',false);if(v)values.push(v);
    var scripts=W.document.querySelectorAll('script'),pattern=/bizTypeId\s*:\s*['"]?([1-9][0-9]*)['"]?\s*[,}]/g;
    for(var i=0;i<scripts.length;i++){var m;while((m=pattern.exec(scripts[i].textContent || '')))values.push(m[1]);}
    return unique(values,'业务类型',false) || '2';
  }
  function printUrl(W,base,term) {
    if(!W.performance || !W.performance.getEntriesByType) throw new Error('请先在教务页面打开打印课表后重试');
    var routes=[], entries=W.performance.getEntriesByType('resource');
    for(var i=0;i<entries.length;i++) {
      var u; try {u=new URL(entries[i].name,W.location.href);} catch(error){continue;}
      if(u.origin!==W.location.origin || u.username || u.password || u.hash) continue;
      var prefix=base+'/for-std/course-table/semester/'+term+'/print-data';
      if(u.pathname!==prefix && u.pathname.indexOf(prefix+'/')!==0) continue;
      var terms=u.searchParams.getAll('semesterId');
      if(terms.some(function(v){return v!==term;})) continue;
      routes.push(u.href);
    }
    return unique(routes,'当前学期打印接口',true);
  }
  function snapshot(W) {
    var href=W.location.href, marker='/for-std/course-table', index=W.location.pathname.indexOf(marker);
    if(index<0 || (W.location.pathname[index+marker.length] && W.location.pathname[index+marker.length]!=='/')) return null;
    var base=W.location.pathname.slice(0,index), term=semester(W), dataId='', studentId='', route='',bizId=(type==='jmu'||type==='cumtb')?pageBiz(W):'2';
    if(type==='hfu') {
      var info=/\/for-std\/course-table\/info\/([1-9][0-9]*)\/?$/.exec(W.location.pathname), ids=[];
      if(info) ids.push(info[1]);
      var buttons=W.document.querySelectorAll('body > div > div > div:nth-child(3) > div > div.student-panel-body.info-page > button');
      for(var b=0;b<buttons.length;b++) if(scalar(buttons[b].value)) ids.push(id(buttons[b].value));
      dataId=unique(ids,'学生标识',true);
    } else if(type==='cumtb' || type==='jmu' || type==='nwpu') dataId=pageId(W,'dataId',false);
    if(type==='nwpu' && !dataId) throw new Error('页面没有 dataId，请打开个人课表后重试');
    if(type==='jmu') studentId=pageId(W,'studentId',true);
    if(type==='shuwei_new') route=printUrl(W,base,term);
    return {href:href,base:base,term:term,dataId:dataId,studentId:studentId,route:route,bizId:bizId};
  }
  var candidates=[],seen=[];
  function visit(W,depth) {
    if(depth>8) throw new Error('课表页面嵌套过深，请直接打开需要导入的课表');
    if(!W || seen.indexOf(W)>=0) return; seen.push(W);
    var location,frames;
    try {location=W.location;if(location.origin!==window.location.origin || !/^https?:$/.test(location.protocol)) return;frames=W.frames;} catch(error){return;}
    var selection=snapshot(W);if(selection)candidates.push({W:W,selection:selection});
    for(var i=0;i<frames.length;i++) visit(frames[i],depth+1);
  }
  try {
    visit(window,0);
    if(candidates.length!==1) throw new Error(candidates.length?'发现多个课表页面，请只保留需要导入的课表':'请登录教务并打开个人课表，选择需要导入的学期');
    var chosen=candidates[0],W=chosen.W,selected=chosen.selection,initialDocument=W.document,fingerprint=JSON.stringify(selected);
    function verify() {
      if(finished) throw new Error('采集已结束');
      candidates=[];seen=[];visit(window,0);
      if(candidates.length!==1 || candidates[0].W!==W || W.document!==initialDocument || JSON.stringify(candidates[0].selection)!==fingerprint)
        throw new Error('课表页面或学期已变化，请重新点击导入');
    }
    async function request(path,body) {
      verify();var u=new URL(path,W.location.href);
      if(u.origin!==W.location.origin || u.username || u.password) throw new Error('课表接口与当前页面不同源');
      var options={method:body===undefined?'GET':'POST',credentials:'include',mode:'same-origin',redirect:'error',headers:{'Accept':'application/json','X-Requested-With':'XMLHttpRequest'}};
      if(controller)options.signal=controller.signal;
      if(body!==undefined){options.headers['Content-Type']='application/json';options.body=JSON.stringify(body);}
      var response=await W.fetch(u.href,options);verify();
      if(!response.ok)throw new Error('课表请求失败 HTTP '+response.status);
      var finalUrl=new URL(response.url || u.href,u.href);
      if(finalUrl.origin!==u.origin || finalUrl.pathname!==u.pathname || finalUrl.search!==u.search) throw new Error('登录状态已变化，请重新登录');
      var text=await response.text();verify();var result;
      try {result=JSON.parse(text);}catch(error){throw new Error('课表接口返回不是 JSON，请重新登录');}
      if(!object(result) || result.success===false || result.success==='false')throw new Error('课表接口返回错误');
      return result;
    }
    function studentShape(result) {
      var tables=[];
      if(result.studentTableVm!==undefined)tables.push(result.studentTableVm);
      if(result.studentTableVms!==undefined){if(!Array.isArray(result.studentTableVms))return false;tables=tables.concat(result.studentTableVms);}
      return tables.length>0 && tables.every(function(t){return object(t)&&Array.isArray(t.activities);});
    }
    var result,kind='student';
    if(type==='shuwei_new') result=await request(selected.route);
    else if(type==='nwpu') result=await request(selected.base+'/for-std/course-table/semester/'+selected.term+'/print-data/'+selected.dataId+'?hasExperiment=true');
    else {
      var endpoint=selected.base+'/for-std/course-table/get-data?bizTypeId=', query='&semesterId='+selected.term+'&dataId='+selected.dataId;
      var data=await request(endpoint+selected.bizId+query);
      if(type==='jmu') {
        if(Object.prototype.hasOwnProperty.call(data,'lessonIds'))throw new Error('当前接口不是 studentTable 课表，请重新打开打印课表');
        if(!selected.studentId)throw new Error('页面没有唯一 studentId，请打开个人课表后重试');
        result=await request(selected.base+'/for-std/course-table/semester/'+selected.term+'/print-data/0/'+selected.studentId);
      } else {
        kind='hfu';
        if(!Array.isArray(data.lessonIds))throw new Error('课表响应中没有 lessonIds');
        if(!data.lessonIds.length)data=await request(endpoint+'23'+query);
        if(!Array.isArray(data.lessonIds) || !data.lessonIds.length)throw new Error('当前学期没有课程，请确认学期后重试');
        if(!data.lessonIds.every(function(v){return (typeof v!=='number'||Number.isSafeInteger(v)) && /^[1-9][0-9]*$/.test(scalar(v));}))throw new Error('课表课程标识格式无法识别');
        result=await request(selected.base+'/ws/schedule-table/datum',{lessonIds:data.lessonIds,studentId:type==='hfu'?selected.dataId:'',weekIndex:''});
      }
    }
    if(kind==='student' ? !studentShape(result) : !(object(result.result)&&Array.isArray(result.result.lessonList)&&Array.isArray(result.result.scheduleList)))
      throw new Error('课表响应结构无法识别，请确认学期和登录状态');
    verify();finish({ok:true,data:JSON.stringify(result),xnxq:selected.term,format:'treewise-'+type});
  } catch(error) {fail(String(error && error.message || error));}
})();
"""#

    static let JwUstcCapture = #"""
(function(){
  var finished = false, deadline = null, controller = null;
  function finish(result) {
    if (finished) return;
    finished = true;
    if (deadline !== null) clearTimeout(deadline);
    if (controller) controller.abort();
    result.format = 'ustc';
    window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify(result)});
  }
  function fail(message) { finish({ok:false,err:message}); }
  function loginUrl(url) { return /\/(?:login|ucas-sso|cas|sso)(?:\/|$)/i.test(url.pathname); }
  function loginDocument(doc) { return !!doc.querySelector('input[type="password"]'); }
  function semesters(doc, live) {
    var choices = [], ids = [], controls = doc.querySelectorAll('select');
    for (var i = 0; i < controls.length; i++) {
      var control = controls[i], options = Array.prototype.slice.call(control.options || []);
      var terms = options.filter(function(option) {
        return /^\d+$/.test(String(option.value)) && /学期/.test(option.textContent || '');
      });
      if (!terms.length) continue;
      terms.forEach(function(option) { ids.push(String(option.value)); });
      var selected = terms.filter(function(option) { return option.hasAttribute('selected'); });
      var value = String(control.value || ''), index = options.findIndex(function(option) {
        return String(option.value) === value;
      });
      if (live && index >= 0 && terms.indexOf(options[index]) >= 0 &&
          (index > 0 || selected.length === 1 || terms.length === 1)) {
        choices.push(value);
      } else if (selected.length === 1) {
        choices.push(String(selected[0].value));
      } else if (selected.length > 1) {
        throw Error('学期选择不明确，请在课表页重新选择学期');
      } else if (terms.length === 1) {
        choices.push(String(terms[0].value));
      }
    }
    choices = choices.filter(function(value, index, all) { return all.indexOf(value) === index; });
    if (choices.length > 1) throw Error('课表页存在不同的学期选择，请重新选择学期');
    return {id:choices[0] || '', ids:ids};
  }
  (async function(){
    var initial = new URL(window.location.href);
    if (initial.origin !== 'https://jw.ustc.edu.cn' || loginUrl(initial) || loginDocument(window.document)) {
      throw Error('请先在中科大教务完成登录，再打开课表页导入');
    }
    var live = semesters(window.document, true);
    controller = new AbortController();
    deadline = setTimeout(function(){ fail('教务请求超时，请重新导入'); }, 18000);
    async function request(path, redirect) {
      var url = new URL(path, initial.origin);
      var response = await window.fetch(url.href, {method:'GET',credentials:'include',mode:'same-origin',
        redirect:redirect,signal:controller.signal});
      if (finished) throw Error('采集已结束');
      if (!response.ok) throw Error('教务请求失败 HTTP ' + response.status);
      if (!response.url) throw Error('教务响应缺少最终地址');
      var finalUrl = new URL(response.url);
      if (finalUrl.origin !== initial.origin || loginUrl(finalUrl)) throw Error('登录态已失效，请重新登录');
      var text = await response.text();
      if (finished) throw Error('采集已结束');
      return {url:finalUrl,text:text,contentType:response.headers.get('content-type') || ''};
    }
    var index = await request('/for-std/course-table', 'follow');
    var match = index.url.pathname.match(/^\/for-std\/course-table\/(\d+)\/?$/);
    if (!match) throw Error('教务没有返回有效学生课表地址');
    if (!/^\s*</.test(index.text) || !/text\/html/i.test(index.contentType)) {
      throw Error('教务课表入口响应格式无效');
    }
    var doc = new DOMParser().parseFromString(index.text, 'text/html');
    if (loginDocument(doc)) throw Error('登录态已失效，请重新登录');
    var server = semesters(doc, false), semesterId = live.id || server.id;
    if (!semesterId || server.ids.indexOf(semesterId) < 0) {
      throw Error('未确定学期，请在课表页明确选择学期后导入');
    }
    var studentId = match[1];
    var data = await request('/for-std/course-table/semester/' + semesterId +
      '/print-data/' + studentId + '?weekIndex=', 'error');
    if (/^\s*</.test(data.text)) throw Error('登录态已失效或教务返回了非课表页面');
    var payload;
    try { payload = JSON.parse(data.text); } catch(e) { throw Error('教务课表 JSON 格式无效'); }
    if (!payload || payload.success === false || payload.code === 401 ||
        !payload.studentTableVm || !Array.isArray(payload.studentTableVm.activities)) {
      throw Error('教务没有返回完整学期课表');
    }
    if (window.location.href !== initial.href || semesters(window.document, true).id !== live.id) {
      throw Error('采集期间页面或学期已改变，请重新导入');
    }
    finish({ok:true,data:data.text,semesterId:semesterId,studentId:studentId});
  })().catch(function(error){ fail(String(error.message || error)); });
})();
"""#

    static let JwSuesCaptureScript = #"""
(async function () {
  function finish(value) { window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify(value)}); }
  function hasActivities(table) { return table && typeof table === 'object' && Array.isArray(table.activities); }
  try {
    var entries = performance.getEntriesByType('resource').filter(function (entry) {
      try {
        var url = new URL(entry.name, location.href);
        return url.origin === location.origin && /\/print-data(?:\/|$)/.test(url.pathname);
      } catch (_) { return false; }
    }).sort(function (a, b) { return a.startTime - b.startTime; });
    if (!entries.length) {
      finish({ok:false, err:'请打开本学期课表打印页面，等待课表加载后再点导入'});
      return;
    }
    var target = new URL(entries[entries.length - 1].name, location.href);
    var response = await fetch(target.href, {method:'GET', credentials:'include', redirect:'follow'});
    if (!response.ok) throw new Error('课表数据请求失败 HTTP ' + response.status);
    var finalUrl = new URL(response.url || target.href, location.href);
    if (finalUrl.origin !== location.origin || /\/(?:login|cas)(?:\/|$)/i.test(finalUrl.pathname)) {
      throw new Error('请重新登录教务并打开课表打印页面');
    }
    var raw = await response.text();
    var root = JSON.parse(raw);
    if (!root || typeof root !== 'object' || Array.isArray(root)) throw new Error('返回数据不是课表对象');
    var tables = Array.isArray(root.studentTableVms) ? root.studentTableVms.slice() : [];
    if (root.studentTableVm && typeof root.studentTableVm === 'object') tables.push(root.studentTableVm);
    if (!tables.length || !tables.every(hasActivities)) throw new Error('返回数据缺少课程活动列表');
    finish({ok:true, data:raw, periods:[]});
  } catch (error) {
    finish({ok:false, err:String(error && error.message || error)});
  }
})();
"""#

    static let JwChaoxingShareCapture = #"""
(function(){
  var finished = false;
  var controller = new AbortController();
  var timer;
  function finish(payload) {
    if (finished) return;
    finished = true;
    clearTimeout(timer);
    window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify(payload)});
  }
  timer = setTimeout(function(){
    finish({ok:false, err:'读取分享课表超时，请重试'});
    controller.abort();
  }, 20000);
  try {
    var shareUrlPattern = /^https?:\/\/kb\.chaoxing\.com\/[^?#]*\.html\?[^#]+(?:#.*)?$/;
    if (!shareUrlPattern.test(location.href)) throw new Error('请先打开超星分享课表链接');
    var list = document.querySelector('.selectList');
    var maxWeek = list ? list.querySelectorAll('li').length : 0;
    if (!maxWeek) throw new Error('页面中未找到学期周次，请等待分享课表加载完成');
    var endpoint = new URL('https://kb.chaoxing.com/curriculum/getOtherLessons');
    endpoint.search = new URL(location.href).search;
    var lessons = [];
    function readWeek(week) {
      if (finished) return;
      if (week > maxWeek) {
        finish({ok:true, protocol:'chaoxing_share', data:JSON.stringify(lessons), periods:[]});
        return;
      }
      endpoint.searchParams.set('week', String(week));
      return fetch(endpoint.href, {method:'GET', credentials:'same-origin',
        headers:{'X-Requested-With':'XMLHttpRequest'}, signal:controller.signal})
        .then(function(response){
          if (!response.ok) throw new Error('读取第 ' + week + ' 周失败，HTTP ' + response.status);
          return response.json();
        }).then(function(response){
          if (finished) return;
          var rows = response && response.data && response.data.lessonArray;
          if (!Array.isArray(rows)) throw new Error('第 ' + week + ' 周响应缺少课程数组');
          lessons = lessons.concat(rows);
          return readWeek(week + 1);
        });
    }
    Promise.resolve(readWeek(1)).catch(function(error){finish({ok:false, err:String(error)});});
  } catch(error) {
    finish({ok:false, err:String(error)});
  }
})();
"""#

    struct Selection { let script: String; let timeout: TimeInterval }
    static func isChaoxingShareUrl(_ url: String) -> Bool {
        url.range(of: #"^https?://kb\.chaoxing\.com/[^?#]*\.html\?[^#]+(?:#.*)?$"#, options: .regularExpression) != nil
    }
    static func selection(type: String?, currentUrl: String) -> Selection? {
        let type = type ?? ""
        let script: String, timeout: TimeInterval
        if type == "chaoxing_share" || isChaoxingShareUrl(currentUrl) { script = JwChaoxingShareCapture; timeout = 20 }
        else if ["shuwei_new", "jmu", "nwpu", "cumtb", "ahnu", "hfu"].contains(type) { script = JwTreewiseJsonCapture.replacingOccurrences(of: "__TREEWISE_TYPE__", with: type); timeout = 20 }
        else if ["fstvc", "gdbh"].contains(type) { script = JwPagedSchoolCapture.replacingOccurrences(of: "__SCHOOL_TYPE__", with: type); timeout = 65 }
        else if ["sustech", "shsmu", "ygu", "zju_post"].contains(type) { script = JwJsonSchoolCapture.replacingOccurrences(of: "__SCHOOL_TYPE__", with: type); timeout = 65 }
        else if type == "buaa" { script = JwBuaaCapture; timeout = 20 }
        else if type == "ustc" { script = JwUstcCapture; timeout = 20 }
        else if type == "fdu" { script = JwFduCapture; timeout = 20 }
        else if type == "sues" { script = JwSuesCaptureScript; timeout = 20 }
        else if ["ccibe", "cppu", "jlu_post"].contains(type) { script = JwSchoolApiCapture.replacingOccurrences(of: "__SCHOOL_TYPE__", with: type); timeout = 20 }
        else { return nil }
        return Selection(script: script, timeout: timeout)
    }
    static func shouldUseZfNewFetch(type: String?, currentUrl: String) -> Bool {
        let url = currentUrl.lowercased()
        let ieas = type == "qz_ieas" || url.contains("/ieas2.1/")
        return !ieas && (type == "zf_new" || url.contains("/jwglxt/") || url.contains("/kbcx/") ||
            url.range(of: #"/http/[0-9a-f]{4,8}/"#, options: .regularExpression) != nil)
    }
}
