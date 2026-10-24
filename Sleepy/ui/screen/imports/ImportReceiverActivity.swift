//
// ImportReceiverActivity.swift
// 1:1 移植自 Android ui/screen/imports/ImportReceiverActivity.kt (v1.0.61).
//
// 外部 app (文件管理器、邮件附件、其他课表 app) 打开 json 课表时:
//   Android: ACTION_VIEW → ImportReceiverActivity 读 URI 内容 → 写
//            MainActivity.pendingImportText(+EXTRA_IMPORT_TEXT) → forward
//            MainActivity → ImportSheet 自动弹预览 → 一键确认
//   iOS:     系统"打开方式"投递 file:// URL → AppRoot.handleDeepLink 的
//            isFileURL 分支调用 receive(url:) → PendingImportText.value = text
//            → AppRoot.onChange 切 Manage → ManagementPage(autoShowImportSheet:)
//            → ImportSheet.onAppear 一次性消费并弹预览
//
// 平台翻译(平台差异表#4, 见 util/PlatformParityNotes.swift):
//   - Intent extras EXTRA_FROM_IMPORT_RECEIVER / EXTRA_IMPORT_TEXT → iOS 无
//     Intent: 文本直写全局 PendingImportText(= MainActivity companion 的 iOS 形态);
//   - 外部「文本」经 URL 传入的兄弟路径 sleepy://import?text= 已由
//     AppRoot.handleDeepLink 的 "import" 分支实现, 与本文件互补不重复;
//   - uri == null → finishWithError("no_uri"): onOpenURL 必有 URL, 该分支平台不可达,
//     不再生造对应代码。
//

import Foundation

enum ImportReceiverActivity {

    /// 入口(← onCreate): 读 URI → 空/失败静默回主界面 → 成功写 PendingImportText。
    static func receive(url: URL) {
        // ← lifecycleScope.launch { withContext(Dispatchers.IO) { ... } }
        Task.detached(priority: .userInitiated) {
            do {
                let text = try readText(from: url)
                // ← text.isNullOrBlank() → finishWithError("empty")
                let blank = text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
                if blank {
                    finishWithError("empty")
                    return
                }
                await MainActor.run {
                    // ← MainActivity.pendingImportText = text
                    PendingImportText.value = text
                    // ← startActivity(forward: SINGLE_TOP|CLEAR_TOP + extras):
                    //   iOS 主壳此时已在前台(或冷启即达), PendingImportText 写入即触发
                    //   AppRoot.onChange(currentTab=.manage) + ImportSheet 自动弹预览,
                    //   等价 Android "forward MainActivity 由 ImportSheet 接收"。
                }
            } catch {
                // ← android.util.Log.e("Sleepy", "external import failed", e)
                NSLog("Sleepy: external import failed: %@", error.localizedDescription)
                // ← finishWithError(e.message ?: "unknown")
                finishWithError(error.localizedDescription)
            }
        }
    }

    /// ← withContext(Dispatchers.IO) 的读取体。两种来源 1:1:
    /// - file://: 先复制进 cache 读一次即删(Android 7+ Scoped Storage 对 file://
    ///   openInputStream 会 EACCES 的规避形态; iOS "打开方式"在
    ///   LSSupportsOpeningDocumentsInPlace=false 下通常已复制进容器 Inbox,
    ///   但来源可为 Files 远端/安全作用域 URL → 保留同一复制→读→删形态,
    ///   并按 ImportSheet.swift fileImporter 既有惯例做 security-scoped 访问)。
    /// - 非 file(← content:// SAF picker 已授权直读): 直接流式读取。
    static func readText(from url: URL) throws -> String? {
        if url.isFileURL {
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            // ← File(cacheDir, "shared_import_${System.currentTimeMillis()}.json")
            let cacheFile = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "shared_import_\(Int64(Date().timeIntervalSince1970 * 1000)).json")
            // ← inputStream().copyTo(out)
            try FileManager.default.copyItem(at: url, to: cacheFile)
            // ← cacheFile.readText().also { cacheFile.delete() }
            defer { try? FileManager.default.removeItem(at: cacheFile) }
            return try String(contentsOf: cacheFile, encoding: .utf8)
        }
        // ← contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
        //   iOS 无 ContentResolver: 通用 Data(contentsOf:) 直读; UTF-8 解码失败
        //   Android 走抛文本异常→catch, iOS String(data:encoding:) 返回 nil→"empty"
        //   分支, 用户可见结果一致(静默回主界面)。
        let data = try Data(contentsOf: url)
        return String(data: data, encoding: .utf8)
    }

    /// ← finishWithError(msg): 跳回 MainActivity 让用户看到主界面,
    /// 不弹任何 dialog(避免惊吓)。iOS: 不写 PendingImportText 即不弹任何浮层,
    /// 主壳本就停在当前页 = 同一"静默回主界面"体验; 外层 catch 已负责打日志
    /// (Android no_uri/empty 两分支同样不打日志)。
    private static func finishWithError(_ msg: String) {
        // 无操作即正确行为; msg 对齐 Android 签名便于断点排障。
    }
}
