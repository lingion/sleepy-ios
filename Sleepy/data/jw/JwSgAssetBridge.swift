// 固定来源：Android v1.0.64 / ShiGuangSchedule/shiguang_warehouse，MIT。
// 原 vendor 脚本只作为受版本控制的 bundle 资产加载；不下载或执行远端脚本。
import Foundation

enum JwSgAssetBridge {
    static let manifestPath = "third_party/shiguang/manifest.json"
    static let timeoutMilliseconds = 120_000

    struct Manifest: Decodable {
        let schools: [School]
        struct School: Decodable {
            let sgName: String
            let sgId: String?
            let adapters: [Adapter]
        }
        struct Adapter: Decodable, Equatable, Identifiable {
            var id: String { adapterId ?? jsPath + "|" + importUrl }
            let adapterId: String?
            let adapterName: String?
            let category: String?
            var schoolId: String?
            let jsPath: String
            let importUrl: String
        }
    }

    enum AssetError: LocalizedError {
        case missingManifest, missingSchool(String), invalidPath, missingScript, selectionRequired
        var errorDescription: String? {
            switch self {
            case .selectionRequired: return "请选择本次导入使用的适配入口"
            case .missingManifest: return "拾光适配目录缺失或损坏"
            case .missingSchool(let name): return "拾光适配目录未找到学校：\(name)"
            case .invalidPath: return "拾光适配脚本路径无效"
            case .missingScript: return "拾光适配脚本缺失或为空"
            }
        }
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCompatibilityMapping
    }

    static func entries(schoolName: String, manifest: Data) throws -> [Manifest.Adapter] {
        guard let parsed = try? JSONDecoder().decode(Manifest.self, from: manifest) else { throw AssetError.missingManifest }
        return parsed.schools.filter { normalize($0.sgName) == normalize(schoolName) }
            .flatMap { school in school.adapters.map { value in var adapter = value; adapter.schoolId = school.sgId; return adapter } }
            .filter { !$0.jsPath.isEmpty }
    }

    static func restoreChoice(_ entries: [Manifest.Adapter], savedId: String) -> Manifest.Adapter? {
        let matches = savedId.isEmpty ? entries : entries.filter { $0.id == savedId }
        return matches.count == 1 ? matches[0] : nil
    }

    static func entry(schoolName: String, manifest: Data, selectedAdapterId: String = "") throws -> Manifest.Adapter {
        let choices = try entries(schoolName: schoolName, manifest: manifest)
        guard !choices.isEmpty else { throw AssetError.missingSchool(schoolName) }
        guard let choice = restoreChoice(choices, savedId: selectedAdapterId) else { throw AssetError.selectionRequired }
        return choice
    }

    static func entries(schoolName: String, resourceRoot: URL? = Bundle.main.resourceURL) throws -> [Manifest.Adapter] {
        guard let root = resourceRoot, let manifest = try? Data(contentsOf: root.appendingPathComponent(manifestPath)) else { throw AssetError.missingManifest }
        return try entries(schoolName: schoolName, manifest: manifest)
    }

    static func bridgeJs(schoolName: String, resourceRoot: URL? = Bundle.main.resourceURL,
                         selectedAdapterId: String = "", sessionId: String = UUID().uuidString) throws -> String {
        guard let root = resourceRoot,
              let manifest = try? Data(contentsOf: root.appendingPathComponent(manifestPath)) else { throw AssetError.missingManifest }
        let adapter = try entry(schoolName: schoolName, manifest: manifest, selectedAdapterId: selectedAdapterId)
        let parts = adapter.jsPath.split(separator: "/", omittingEmptySubsequences: false)
        guard adapter.jsPath.hasPrefix("third_party/shiguang/js/"), adapter.jsPath.hasSuffix(".js"),
              !parts.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }),
              !adapter.jsPath.contains("\\") else { throw AssetError.invalidPath }
        guard let vendor = try? String(contentsOf: root.appendingPathComponent(adapter.jsPath), encoding: .utf8),
              !vendor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AssetError.missingScript }
        return assemble(vendorJs: vendor, sessionId: sessionId)
    }

    static func assemble(vendorJs: String, sessionId: String = UUID().uuidString) -> String {
        let quoted = (try? JwSgSourceMetadata.stringify([sessionId])).map { String($0.dropFirst().dropLast()) } ?? "\"\""
        return shim + "\n;SleepySgShim.install(" + quoted + ");\n(function(){try{\n" + vendorJs
            + "\n}catch(e){SleepySgShim._out({ok:false,captureId:" + quoted + ",err:String(e)});}})();\n;SleepySgShim.finish();"
    }

    static let shim = #"""
(function(){
  if (window.SleepySgShim) return;
  var state;
  function out(payload){ try{ window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify(payload)}); }catch(e){} }
  function promiseResult(v){ return new Promise(function(res){ res(v); }); }
  function active(){ return state && !state.cancelled && !state.completed; }
  function metadataFailure(message){
    state.failure = message;
    return Promise.reject(new Error(message));
  }
  function clock(value){
    return typeof value === 'string' && /^\d{2}:\d{2}$/.test(value) &&
      Number(value.slice(0,2)) < 24 && Number(value.slice(3)) < 60;
  }
  function validDate(value){
    if (typeof value !== 'string' || !/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(value) || value.slice(0,4) === '0000') return false;
    var date = new Date(value + 'T00:00:00Z');
    return !isNaN(date.getTime()) && date.toISOString().slice(0,10) === value;
  }
  function cancelled(kind){ return kind === 'alert' ? false : null; }
  function request(kind, fields, validator){
    if (!active()) return Promise.resolve(cancelled(kind));
    return new Promise(function(resolve, reject){
      var id = ++state.nextRequest;
      var message = {sessionId:state.sessionId, requestId:id, kind:kind};
      Object.keys(fields).forEach(function(key){ message[key] = fields[key]; });
      state.pending[id] = {kind:kind, fields:fields, validator:validator, resolve:resolve, lastAttempt:0};
      try { window.webkit.messageHandlers.__sleepySgInteraction.postMessage(message); }
      catch(e) { delete state.pending[id]; reject(new Error('无法打开导入交互窗口')); }
    });
  }
  function ack(id, attempt, accepted, error){
    window.webkit.messageHandlers.__sleepySgAcknowledged.postMessage({
      sessionId:state.sessionId, requestId:id, attemptId:attempt, accepted:accepted, error:error || ''
    });
  }
  var promiseApi = {
    showAlert: function(title, content, confirmText){
      return request('alert', {title:String(title || ''),content:String(content || ''),confirmText:String(confirmText || '')});
    },
    showPrompt: function(title, tip, defaultText, validatorJsFunction){
      return request('prompt', {title:String(title || ''),tip:String(tip || ''),defaultText:String(defaultText || '')}, validatorJsFunction);
    },
    showSingleSelection: function(title, itemsJsonString, defaultSelectedIndex){
      try {
        var items = JSON.parse(itemsJsonString);
        if (!Array.isArray(items) || !items.length || !items.every(function(item){ return typeof item === 'string'; })) {
          throw new Error('选项列表无效');
        }
        var idx = Number.isInteger(defaultSelectedIndex) && defaultSelectedIndex >= 0 && defaultSelectedIndex < items.length
          ? defaultSelectedIndex : -1;
        return request('selection', {title:String(title || ''),items:items,defaultSelectedIndex:idx});
      } catch(e) { return Promise.reject(e); }
    },
    saveImportedCourses: function(coursesJsonString){
      if (!active()) return Promise.reject(new Error('采集 session 已结束或取消'));
      state.submitted = true;
      // SUDA/HAUE 等适配器会在课程之后提交作息和配置，完成通知前只暂存。
      state.data = String(coursesJsonString);
      return promiseResult(true);
    },
    savePresetTimeSlots: function(timeSlotsJsonString){
      if (!active()) return Promise.reject(new Error('采集 session 已结束或取消'));
      try {
        var slots = JSON.parse(timeSlotsJsonString);
        if (!Array.isArray(slots) || !slots.length || slots.length > 366) throw new Error('基础作息必须是完整节次数组');
        slots.forEach(function(slot,index){
          if (!slot || slot.number !== index + 1 || !clock(slot.startTime) || !clock(slot.endTime) ||
              slot.startTime >= slot.endTime || index > 0 && slots[index - 1].endTime > slot.startTime) {
            throw new Error('基础作息编号或钟点无效');
          }
        });
        state.periods = slots.map(function(s){ return {node:s.number, start:s.startTime, end:s.endTime}; });
      } catch(e){ return metadataFailure('来源基础作息无效，请检查后重新导入'); }
      return promiseResult(true);
    },
    saveCourseConfig: function(configJsonString){
      if (!active()) return Promise.reject(new Error('采集 session 已结束或取消'));
      try {
        var cfg = JSON.parse(configJsonString);
        if (!cfg || typeof cfg !== 'object' || Array.isArray(cfg)) throw new Error('配置必须是对象');
        Object.keys(cfg).forEach(function(key){
          var value = cfg[key];
          if (key === 'semesterStartDate' && value !== null && !validDate(value)) throw new Error('学期日期无效');
          if (key === 'semesterTotalWeeks' && (!Number.isInteger(value) || value < 1 || value > 366)) throw new Error('学期周数无效');
          if (key === 'firstDayOfWeek' && (!Number.isInteger(value) || value < 1 || value > 7)) throw new Error('每周首日无效');
          if (key === 'defaultClassDuration' || key === 'defaultBreakDuration') {
            if (!Number.isSafeInteger(value) || value < (key === 'defaultClassDuration' ? 1 : 0)) throw new Error('课程或课间时长无效');
          }
        });
        Object.keys(cfg).forEach(function(key){ state.config[key] = cfg[key]; });
        if (Object.prototype.hasOwnProperty.call(cfg, 'semesterStartDate')) {
          state.startDate = cfg.semesterStartDate === null ? '' : cfg.semesterStartDate;
        }
      } catch(e){ return metadataFailure('来源课表配置无效，请检查后重新导入'); }
      return promiseResult(true);
    },
    saveComboSchedule: function(comboScheduleJsonString){
      if (!active()) return Promise.reject(new Error('采集 session 已结束或取消'));
      return metadataFailure('来源包含按日期切换的作息，本次导入尚不能完整保存该方案');
    }
  };
  var syncApi = {
    showToast: function(message){},
    notifyTaskCompletion: function(){
      if (!active()) return;
      state.completed = true;
      var unanswered = Object.keys(state.pending).length > 0;
      Object.keys(state.pending).forEach(function(id){
        var pending = state.pending[id]; pending.resolve(cancelled(pending.kind));
      });
      state.pending = {};
      if (state.failure || unanswered) {
        out({ok:false,captureId:state.sessionId,err:state.failure || '来源尚有未完成的导入选择，请重新导入'});
      } else if (state.submitted) {
        out({ok:true, captureId:state.sessionId, data:state.data, periods:state.periods, startDate:state.startDate, sgConfig:state.config, sgAsset:'saveImportedCourses'});
      } else {
        out({ok:false, captureId:state.sessionId, err:'拾光适配脚本已结束但未提交课表 (可能需要手动导航到课表页后重试)'});
      }
    }
  };
  window.SleepySgShim = {
    install: function(sessionId){
      // 来源异步代码可能在稍后读取全局 API。换 session 必须换文档，不能原页重装。
      if (state) throw new Error('再次导入前请重新加载页面');
      state = {sessionId:sessionId, submitted:false, completed:false, cancelled:false,
        nextRequest:0,pending:{},data:'', periods:[], startDate:'', config:{},failure:''};
      window.shiguangBridgePromise = promiseApi;
      window.shiguangBridge = syncApi;
      window.AndroidBridgePromise = promiseApi;
      window.AndroidBridge = syncApi;
      window.__sgState = state;
    },
    respond: function(sessionId, requestId, attemptId, value){
      if (!active() || state.sessionId !== sessionId) return;
      var pending = state.pending[requestId];
      if (!pending || !Number.isInteger(attemptId) || attemptId <= pending.lastAttempt) return;
      pending.lastAttempt = attemptId;
      var error = '';
      if (pending.kind === 'alert') {
        if (typeof value !== 'boolean') error = '请确认或取消';
      } else if (value !== null && pending.kind === 'prompt') {
        if (typeof value !== 'string') error = '输入内容无效';
        else if (pending.validator) {
          try {
            var validator = window[pending.validator];
            if (typeof validator !== 'function') error = '输入校验函数不存在';
            else {
              var validation = validator(value);
              if (validation !== false) error = typeof validation === 'string' && validation ? validation : '输入校验未通过';
            }
          } catch(e) { error = '输入校验失败，请重试'; }
        }
      } else if (value !== null && pending.kind === 'selection') {
        if (!Number.isInteger(value) || value < 0 || value >= pending.fields.items.length) error = '请选择有效选项';
      }
      ack(requestId, attemptId, !error, error);
      if (error) return;
      delete state.pending[requestId];
      pending.resolve(value);
    },
    cancelSession: function(sessionId){
      if (!state || state.sessionId !== sessionId) return;
      state.cancelled = true;
      Object.keys(state.pending).forEach(function(id){
        var pending = state.pending[id]; pending.resolve(cancelled(pending.kind));
      });
      state.pending = {};
    },
    finish: function(){
      // 同步段跑完仍未提交: 不立刻报错 — 脚本多为 async; 超时闸兜底。
      // 但同步即抛错的场景由外层 try/catch 处理。
    },
    _out: out
  };
})();
"""#
}
