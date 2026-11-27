import Compression
import Foundation

/// 统一读取随包静态资源：优先读取系统原生 `.lzma` 压缩资产并解压，不存在时回退原始文件。
enum BundledAssetLoader {
    private static let shiguangPackCache: NSCache<NSString, NSDictionary> = {
        let cache = NSCache<NSString, NSDictionary>()
        cache.countLimit = 2
        return cache
    }()

    static func decompressLzma(_ data: Data) -> Data? {
        try? (data as NSData).decompressed(using: .lzma) as Data
    }

    static func gunzip(_ data: Data) -> Data? {
        guard data.count > 10, data[0] == 0x1f, data[1] == 0x8b else { return nil }
        let outSize = max(data.count * 4, 2 * 1024 * 1024)
        var out = [UInt8](repeating: 0, count: outSize)
        var i = 10
        let flg = data[3]
        if (flg & 0x04) != 0, i + 2 <= data.count {
            let xlen = Int(data[i]) | (Int(data[i + 1]) << 8)
            i += 2 + xlen
        }
        if (flg & 0x08) != 0 { while i < data.count && data[i] != 0 { i += 1 }; i += 1 }
        if (flg & 0x10) != 0 { while i < data.count && data[i] != 0 { i += 1 }; i += 1 }
        if (flg & 0x02) != 0 { i += 2 }
        guard i < data.count - 8 else { return nil }
        let payload = Data(data[i..<(data.count - 8)])
        let n = payload.withUnsafeBytes { sp in
            out.withUnsafeMutableBytes { dp in
                compression_decode_buffer(
                    dp.bindMemory(to: UInt8.self).baseAddress!, outSize,
                    sp.bindMemory(to: UInt8.self).baseAddress!, payload.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard n > 0 else { return nil }
        return Data(out[0..<n])
    }

    /// 依次查找 `<name>.<ext>.lzma`、`<name>.<ext>`、`<name>.<fallbackExt>` 并解压返回原始字节。
    static func loadData(
        name: String,
        ext: String,
        fallbackExts: [String] = [],
        bundles: [Bundle] = [.main]
    ) -> Data? {
        let compressedName = ext.isEmpty ? name : "\(name).\(ext)"
        for bundle in bundles {
            if let url = bundle.url(forResource: compressedName, withExtension: "lzma"),
               let raw = try? Data(contentsOf: url),
               let plain = decompressLzma(raw) {
                return plain
            }
            for candidateExt in [ext] + fallbackExts {
                if let url = bundle.url(forResource: name, withExtension: candidateExt),
                   let raw = try? Data(contentsOf: url) {
                    if candidateExt == "bin.gz" || candidateExt == "gz" {
                        return gunzip(raw) ?? raw
                    }
                    return raw
                }
            }
        }
        return nil
    }

    static func loadText(
        name: String,
        ext: String,
        fallbackExts: [String] = [],
        bundles: [Bundle] = [.main]
    ) -> String? {
        guard let data = loadData(name: name, ext: ext, fallbackExts: fallbackExts, bundles: bundles) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func shiguangPack(resourceRoot: URL?) -> [String: String]? {
        guard let root = resourceRoot else { return nil }
        let cacheKey = root.path as NSString
        if let cached = shiguangPackCache.object(forKey: cacheKey) as? [String: String] {
            return cached
        }
        let packURL = root.appendingPathComponent("third_party/shiguang.pack.lzma")
        guard let compressed = try? Data(contentsOf: packURL),
              let raw = decompressLzma(compressed),
              let dict = decodeShiguangPack(raw) else {
            return nil
        }
        shiguangPackCache.setObject(dict as NSDictionary, forKey: cacheKey)
        return dict
    }

    private static func decodeShiguangPack(_ raw: Data) -> [String: String]? {
        if raw.count >= 8, raw[0] == 0x53, raw[1] == 0x47, raw[2] == 0x50, raw[3] == 0x31 {
            let count = Int(raw[4]) | (Int(raw[5]) << 8) | (Int(raw[6]) << 16) | (Int(raw[7]) << 24)
            var out: [String: String] = [:]
            out.reserveCapacity(count)
            var idx = 8
            for _ in 0..<count {
                guard idx + 2 <= raw.count else { return nil }
                let pathLen = Int(raw[idx]) | (Int(raw[idx + 1]) << 8)
                idx += 2
                guard idx + pathLen + 4 <= raw.count else { return nil }
                guard let path = String(data: raw[idx..<(idx + pathLen)], encoding: .utf8) else { return nil }
                idx += pathLen
                let bodyLen = Int(raw[idx]) | (Int(raw[idx + 1]) << 8) | (Int(raw[idx + 2]) << 16) | (Int(raw[idx + 3]) << 24)
                idx += 4
                guard idx + bodyLen <= raw.count else { return nil }
                guard let body = String(data: raw[idx..<(idx + bodyLen)], encoding: .utf8) else { return nil }
                idx += bodyLen
                out[path] = body
            }
            return out
        }
        return (try? JSONSerialization.jsonObject(with: raw)) as? [String: String]
    }

    static func loadShiguangEntryData(path: String, resourceRoot: URL?) -> Data? {
        if let root = resourceRoot {
            let direct = root.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: direct.path),
               let data = try? Data(contentsOf: direct) {
                return data
            }
            if let text = shiguangPack(resourceRoot: root)?[path] {
                return Data(text.utf8)
            }
        }
        return nil
    }
}
