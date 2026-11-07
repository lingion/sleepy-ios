// 固定来源：Android v1.0.63 / ShiGuangSchedule/shiguang_warehouse，MIT。
// 原 vendor 脚本只作为受版本控制的 bundle 资产加载；不下载或执行远端脚本。
import Foundation

enum JwSgAssetBridge {
    static let manifestPath = "third_party/shiguang/manifest.json"
    static let timeoutMilliseconds = 120_000

    struct Manifest: Decodable {
        let schools: [School]
        struct School: Decodable {
            let sgName: String
            let adapters: [Adapter]
        }
        struct Adapter: Decodable {
            let jsPath: String
            let importUrl: String
        }
    }

    enum AssetError: LocalizedError {
        case missingManifest, missingSchool(String), invalidPath, missingScript
        var errorDescription: String? {
            switch self {
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

    static func entry(schoolName: String, manifest: Data) throws -> Manifest.Adapter {
        guard let parsed = try? JSONDecoder().decode(Manifest.self, from: manifest) else {
            throw AssetError.missingManifest
        }
        guard let school = parsed.schools.first(where: { normalize($0.sgName) == normalize(schoolName) }),
              let adapter = school.adapters.first(where: { !$0.jsPath.isEmpty }) else {
            throw AssetError.missingSchool(schoolName)
        }
        return adapter
    }

    static func bridgeJs(schoolName: String, resourceRoot: URL? = Bundle.main.resourceURL) throws -> String {
        guard let root = resourceRoot,
              let manifest = try? Data(contentsOf: root.appendingPathComponent(manifestPath)) else {
            throw AssetError.missingManifest
        }
        let adapter = try entry(schoolName: schoolName, manifest: manifest)
        let parts = adapter.jsPath.split(separator: "/", omittingEmptySubsequences: false)
        guard adapter.jsPath.hasPrefix("third_party/shiguang/js/"), adapter.jsPath.hasSuffix(".js"),
              !parts.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }),
              !adapter.jsPath.contains("\\") else { throw AssetError.invalidPath }
        guard let vendor = try? String(contentsOf: root.appendingPathComponent(adapter.jsPath), encoding: .utf8),
              !vendor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AssetError.missingScript }
        return assemble(vendorJs: vendor)
    }

    static func assemble(vendorJs: String) -> String {
        // 每次运行新闭包，防止重复导入时 vendor 顶层 const 重声明，以及旧 submitted 状态泄漏。
        shim + "\ntry {\n" + vendorJs + "\n} catch(e) { fail(String(e)); }\n})();"
    }

    static let shim = #"""
    (function(){
      if (window.SleepySgShim && window.SleepySgShim.cancel) window.SleepySgShim.cancel();
      var state = {submitted:false, finished:false, courses:'', periods:[], startDate:''};
      var timer;
      function out(payload){
        if (state.finished) return;
        state.finished = true;
        clearTimeout(timer);
        window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify(payload)});
      }
      function fail(message){ out({ok:false, err:message}); }
      function result(value){ return Promise.resolve(value); }
      var promiseApi = {
        showAlert: function(title, content, confirmText){ return result(true); },
        showPrompt: function(title, tip, defaultText, validatorJsFunction){ return result(defaultText); },
        showSingleSelection: function(title, itemsJsonString, defaultSelectedIndex){
          return result(typeof defaultSelectedIndex === 'number' && defaultSelectedIndex >= 0 ? defaultSelectedIndex : 0);
        },
        saveImportedCourses: function(coursesJsonString){
          state.submitted = true;
          // AUFE 等脚本先存课程再存作息/学期；必须等完成消息后统一传输。
          state.courses = String(coursesJsonString);
          return result(true);
        },
        savePresetTimeSlots: function(timeSlotsJsonString){
          try {
            state.periods = JSON.parse(timeSlotsJsonString).map(function(s){
              return {node:s.number, start:s.startTime, end:s.endTime};
            });
          } catch(e){ state.periods = []; }
          return result(true);
        },
        saveCourseConfig: function(configJsonString){
          try {
            var cfg = JSON.parse(configJsonString);
            if (cfg && cfg.semesterStartDate) state.startDate = String(cfg.semesterStartDate);
          } catch(e){}
          return result(true);
        },
        saveComboSchedule: function(comboScheduleJsonString){
          fail('拾光脚本返回组合课表，当前导入通路暂不支持');
          return result(false);
        }
      };
      var syncApi = {
        showToast: function(message){},
        notifyTaskCompletion: function(){
          if (!state.submitted) fail('拾光适配脚本已结束但未提交课表，请进入课表页后重试');
          else out({ok:true, data:state.courses, periods:state.periods,
                    startDate:state.startDate, sgAsset:'saveImportedCourses'});
        }
      };
      window.SleepySgShim = {cancel:function(){state.finished = true; clearTimeout(timer);}};
      window.shiguangBridgePromise = promiseApi;
      window.shiguangBridge = syncApi;
      window.AndroidBridgePromise = promiseApi;
      window.AndroidBridge = syncApi;
      timer = setTimeout(function(){fail('拾光适配脚本抓取超时，请进入课表页后重试');}, 120000);
    """#
}
