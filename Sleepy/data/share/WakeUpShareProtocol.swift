// ← WakeUpShareProtocol.kt / 拾光 GLOBAL_TOOLS/wake_up.js (GPL-3.0)
import Foundation
import CoreFoundation

enum WakeUpShareError: LocalizedError, Equatable {
    case emptyCode, invalidCode, invalidResponse, missingSignature, invalidToken
    case missingEncryptedData, decryptionFailed, missingShareData, incompleteSchedule
    case http(Int), service(Int), responseTooLarge

    var errorDescription: String? {
        switch self {
        case .emptyCode: return "输入不能为空！"
        case .invalidCode: return "未检测到有效的 WakeUP 分享口令，请粘贴完整分享文本或口令。"
        case .invalidResponse: return "WakeUP 服务响应格式无效。"
        case .missingSignature: return "WakeUP antispam 响应未包含签名数据。"
        case .invalidToken: return "WakeUP antispam token 校验失败。"
        case .missingEncryptedData: return "WakeUP 课表响应未包含加密数据。"
        case .decryptionFailed: return "WakeUP 课表响应解密失败。"
        case .missingShareData: return "WakeUP 解密数据中未找到 shareData。"
        case .incompleteSchedule: return "分享课表为空、已失效或数据格式不完整。"
        case .http(let status): return "WakeUP 服务请求失败（HTTP \(status)）。"
        case .service(let code): return "WakeUP 服务拒绝请求（错误码 \(code)）。"
        case .responseTooLarge: return "WakeUP 响应超过大小限制。"
        }
    }
}

enum WakeUpShareProtocol {
    // 从 v6.1.70 官渠 APK 提取的公开协议参数; 非用户凭证。
    struct Constants {
        let host = "https://api.wakeup.fun"
        let antispamPath = "/pluto/app/antispam"
        let sharePath = "/share_schedule/getv2"
        let packageName = "com.suda.yzune.wakeupschedule"
        let versionName = "6.1.70"
        let versionCode = 450
        let channel = "100271a"
        let publicToken = "1_XPXQH3c5HRPtFHkSwi3sCCURmT25QfxM"
        let signatureMd5 = "318c6d4f74655d4f032fb0466bcfdfbc"
        let magic = "8&%d*"
        let signAKey = "@fG2SuLA"
        let keySalt = "@#AIjd83#@6B"
    }
    static let V6170 = Constants()

    /// 协议设备描述固定为上游默认值, 不读取 iOS 广告标识符或硬件标识。
    struct Device {
        let cuid: String
        let adid: String
        let did: String
        var sdk = "35", device = "Pixel 7", brand = "google", screensize = "1080x2400"
        var abis = "arm64-v8a", appBit = "64", appId = "wakeup", downloadType = "1", nt = "wifi"
        var province = "", city = "", area = "", deviceId = "", operatorid = ""

        init(androidId: String = "0000000000000000", adid: String = "", did: String = "") {
            self.cuid = WakeUpShareProtocol.cuidFromAndroidId(androidId)
            self.adid = adid.isEmpty ? WakeUpShareProtocol.adidFromAndroidId(androidId) : adid
            self.did = did
        }
    }

    static let keyPattern = "^[A-Za-z0-9_-]{8,200}$"
    private static let labelledPattern = "分享口令(?:为)?\\s*[「“\"]?\\s*([A-Za-z0-9_-]{1,200})\\s*[」”\"]?"
    private static let quotedPattern = "[「“\"]\\s*([A-Za-z0-9_-]{8,200})\\s*[」”\"]"

    static func extractKeyFromText(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }
        for pattern in [labelledPattern, quotedPattern] {
            if let match = matches(pattern, text).first,
               let range = Range(match.range(at: 1), in: text) { return String(text[range]) }
        }
        if let match = matches("[A-Za-z0-9_-]{8,200}", text).last,
           let range = Range(match.range, in: text) { return String(text[range]) }
        return text
    }

    static func validatedKey(_ input: String) throws -> String {
        let key = extractKeyFromText(input)
        guard !key.isEmpty else { throw WakeUpShareError.emptyCode }
        guard matches(keyPattern, key).first?.range.length == key.utf16.count else {
            throw WakeUpShareError.invalidCode
        }
        return key
    }

    /// 在线路由窄窗: 既有 JSON/ICS/HTML 文本继续走原离线解析器。
    static func looksLikeShareCode(_ input: String) -> Bool {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if matches(keyPattern, text).first?.range.length == text.utf16.count, !text.isEmpty { return true }
        return text.contains("分享口令") && (try? validatedKey(text)) != nil
    }

    private static func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func cuidFromAndroidId(_ value: String) -> String {
        WakeUpV6170Crypto.md5Hex("com.baidu" + value).uppercased() + "|0"
    }

    static func adidFromAndroidId(_ value: String) -> String {
        let prefix = WakeUpV6170Crypto.md5Hex("alpha.beta" + value)
        let folded = UInt64(prefix.prefix(16), radix: 16)! ^ UInt64(prefix.suffix(16), radix: 16)!
        let checksum = UInt32(truncatingIfNeeded: (folded >> 32) ^ folded)
        return prefix + String(format: "%08x", checksum)
    }

    static func generateRand10() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        var random = SystemRandomNumberGenerator()
        return String((0..<10).map { _ in alphabet[Int(UInt8.random(in: .min ... .max, using: &random)) % 62] })
    }

    static func makeCommonParams(_ d: Device) -> [(String, String)] {
        let c = V6170
        return [("area", d.area), ("screensize", d.screensize), ("cuid", d.cuid), ("os", "android"),
                ("city", d.city), ("abis", d.abis), ("channel", c.channel), ("appBit", d.appBit),
                ("vc", String(c.versionCode)), ("deviceId", d.deviceId), ("token", c.publicToken),
                ("adid", d.adid), ("province", d.province), ("pkgName", c.packageName), ("appId", d.appId),
                ("download_type", d.downloadType), ("vcname", c.versionName), ("sdk", d.sdk),
                ("device", d.device), ("brand", d.brand), ("operatorid", d.operatorid)]
    }

    static func makeSignA(cuid: String, rand10: String) throws -> String {
        guard rand10.utf8.count == 10, rand10.utf8.allSatisfy({ $0 < 128 }) else {
            throw WakeUpShareError.invalidToken
        }
        let c = V6170
        return WakeUpV6170Crypto.nativeHexEncode(try WakeUpV6170Crypto.desEncrypt(
            "\(c.magic)##\(rand10)##\(c.signatureMd5)##\(cuid)", key: c.signAKey))
    }

    static func tokenFromSignB(_ signB: String, rand10: String) throws -> String {
        guard rand10.utf8.count == 10 else { throw WakeUpShareError.invalidToken }
        do {
            let plain = try WakeUpV6170Crypto.desDecrypt(WakeUpV6170Crypto.nativeHexDecode(signB),
                                                        key: String(rand10.prefix(5)) + "#G4")
            let bytes = Array(plain)
            guard bytes.count >= 22, Array(bytes.prefix(10)) == Array(rand10.utf8) else {
                throw WakeUpShareError.invalidToken
            }
            // Latin-1 映射与上游一致, 不把高位字节误当 UTF-8 替换字符。
            return bytes[12..<22].map { String(UnicodeScalar($0)) }.joined()
        } catch { throw WakeUpShareError.invalidToken }
    }

    static func getRc4Key(_ token: String) -> String {
        let first = WakeUpV6170Crypto.md5Hex(V6170.keySalt)
        let second = WakeUpV6170Crypto.md5Hex(String(V6170.versionCode))
        let raw = Array(WakeUpV6170Crypto.md5Hex("[\(token)]@"))
        let reversed = Array(raw[17...].reversed()) + Array(raw[15..<17]) + Array(raw[..<15].reversed())
        var chars = Array(first + second) + reversed
        for i in 0..<3 { chars.swapAt(i, chars.count - 1 - i) }
        let joined = String(chars)
        var output = Array(joined + WakeUpV6170Crypto.md5Hex(joined))
        for i in 0..<60 { output.swapAt(i, output.count - 1 - i) }
        return String(output)
    }

    static func getSign(_ base64: String, token: String) -> String {
        WakeUpV6170Crypto.md5Hex("\(V6170.magic)[\(WakeUpV6170Crypto.md5Hex(token))]@\(base64)")
    }

    struct ShareRequest { let rc4Key: String; let body: String }

    static func buildShareRequest(code: String, token: String, device: Device, nowMs: Int64) throws -> ShareRequest {
        let common = makeCommonParams(device)
        let key = getRc4Key(token)
        let data = try WakeUpV6170Crypto.rc4(Data("key=\(WakeUpV6170Crypto.androidQuote(code))".utf8), key: key)
            .base64EncodedString()
        let time = nowMs / 1000
        let extras = device.did.isEmpty ? [] : [("did", device.did)]
        let fields = [("data", data)] + common + extras + [("nt", device.nt)]
        let signFields = fields + [("_t_", String(time)), ("kakorrhaphiophobia", String(nowMs))]
        let sorted = signFields.map { "\($0.0)=\($0.1)" }.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
        let sign = getSign(Data(sorted.joined().utf8).base64EncodedString(), token: token)
        let body = "&" + WakeUpV6170Crypto.formEncode(fields) + "&sign=\(sign)&_t_=\(time)&kakorrhaphiophobia=\(nowMs)"
        return ShareRequest(rc4Key: key, body: body)
    }

    static func antispamBody(signA: String, device: Device) -> String {
        WakeUpV6170Crypto.formEncode([("data", signA)] + makeCommonParams(device)) + "&"
    }

    static func extractSignB(_ root: [String: Any]) -> String? {
        for candidate in [root["data"], (root["data"] as? [String: Any])?["data"],
                          (root["result"] as? [String: Any])?["data"]] {
            if let value = candidate as? String, !value.isEmpty { return value }
        }
        return nil
    }

    static func decodeSharePayload(_ root: [String: Any], rc4Key: String) throws -> String {
        let field = (root["data"] as? [String: Any])?["data"] ?? root["data"]
        guard let encrypted = field as? String, !encrypted.isEmpty else { throw WakeUpShareError.missingEncryptedData }
        guard let cipher = Data(base64Encoded: encrypted),
              let plain = try? WakeUpV6170Crypto.rc4(cipher, key: rc4Key),
              let value = try? JSONSerialization.jsonObject(with: plain),
              let decoded = value as? [String: Any] else { throw WakeUpShareError.decryptionFailed }
        guard let shareData = decoded["shareData"] as? String else { throw WakeUpShareError.missingShareData }
        return shareData
    }

    struct ShareParts {
        let baseConfig: [String: Any]
        let timeSlots: [[String: Any]]
        let uiConfig: [String: Any]
        let courses: [[String: Any]]
        let details: [[String: Any]]
    }

    static func parseRawScheduleData(_ raw: String) throws -> ShareParts {
        let lines = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        guard lines.count >= 5 else { throw WakeUpShareError.incompleteSchedule }
        do {
            let blocks = try lines.prefix(5).map { try JSONSerialization.jsonObject(with: Data($0.utf8)) }
            guard let base = blocks[0] as? [String: Any], let time = blocks[1] as? [Any],
                  let ui = blocks[2] as? [String: Any], let courses = blocks[3] as? [Any],
                  let details = blocks[4] as? [Any] else { throw WakeUpShareError.incompleteSchedule }
            return ShareParts(baseConfig: base, timeSlots: time.compactMap { $0 as? [String: Any] },
                              uiConfig: ui, courses: courses.compactMap { $0 as? [String: Any] },
                              details: details.compactMap { $0 as? [String: Any] })
        } catch { throw WakeUpShareError.incompleteSchedule }
    }

    static func int(_ value: Any?) -> Int? {
        if let text = value as? String { return Int(text) }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return Int(number.stringValue)
    }

    private static func primitiveString(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.stringValue }
        return nil
    }

    static func normalizeNodes(_ ui: [String: Any]) throws -> Set<Int> {
        if let values = ui["nodes"] as? [Any] { return Set(values.compactMap(int)) }
        if let count = int(ui["nodes"]), count > 0 {
            // 拒绝不合理展开, 不能静默变成空作息再宣称导入成功。
            guard count <= 10000 else { throw WakeUpShareError.incompleteSchedule }
            return Set(1...count)
        }
        return []
    }

    static func convertToSemesterStartDate(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard let match = matches("^(\\d{1,4})-(\\d{1,2})-(\\d{1,4})T?", text).first else { return nil }
        let ns = text as NSString
        let parts = (1...3).map { ns.substring(with: match.range(at: $0)) }
        guard let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]) else { return nil }
        let year = parts[0].count == 4 ? a : c
        let month = parts[0].count == 4 ? b : a
        let day = parts[0].count == 4 ? c : b
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard year > 0, let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// 输出直接交给既有 ScheduleParser/ImportSheet 预览; 此层不写数据库。
    static func buildScheduleJson(_ parts: ShareParts) throws -> String {
        let nodes = try normalizeNodes(parts.uiConfig)
        var names: [String: String] = [:]
        for course in parts.courses {
            if let id = primitiveString(course["id"]), names[id] == nil,
               let name = primitiveString(course["courseName"]), !name.isEmpty { names[id] = name }
        }
        let courses: [[String: Any]] = parts.details.compactMap { detail in
            guard let id = primitiveString(detail["id"]), let name = names[id],
                  let day = int(detail["day"]), let start = int(detail["startNode"]), let step = int(detail["step"]),
                  let first = int(detail["startWeek"]), let last = int(detail["endWeek"]), let type = int(detail["type"]) else { return nil }
            return ["name": name, "teacher": primitiveString(detail["teacher"]) ?? "",
                    "position": primitiveString(detail["room"]) ?? "", "day": day,
                    "startNode": start, "step": step, "startWeek": first, "endWeek": last, "type": type]
        }
        let times: [[String: Any]] = parts.timeSlots.compactMap { slot in
            guard let node = int(slot["node"]), nodes.contains(node),
                  let start = slot["startTime"] as? String, let end = slot["endTime"] as? String,
                  start != "00:00", end != "00:00" else { return nil }
            return ["node": node, "startTime": start, "endTime": end]
        }
        var info: [String: Any] = ["timeList": times]
        if let max = nodes.max() { info["nodesPerDay"] = max }
        if let weeks = int(parts.uiConfig["maxWeek"]) { info["maxWeek"] = weeks }
        var root: [String: Any] = ["name": "WakeUP 分享课表", "courses": courses, "tableInfo": info]
        if let date = convertToSemesterStartDate(parts.uiConfig["startDate"] as? String) { root["startDate"] = date }
        return String(decoding: try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]), as: UTF8.self)
    }
}
