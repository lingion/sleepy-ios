// ← WakeUpV6170Crypto.kt / 拾光 GLOBAL_TOOLS/wake_up.js (GPL-3.0)
// 协议兼容原语: 私有 DES 非标准, 禁止换成系统 DES。常量不是用户凭证。
import Foundation
import CryptoKit

enum WakeUpV6170Crypto {
    enum Failure: Error { case invalidKey, invalidCipher, invalidPadding }

    static func md5Hex(_ text: String) -> String {
        Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func androidQuote(_ text: String) -> String {
        text.utf8.map { byte -> String in
            switch byte {
            case 65...90, 97...122, 48...57, 45, 95, 46, 126: return String(UnicodeScalar(byte))
            case 32: return "+"
            default: return String(format: "%%%02X", byte)
            }
        }.joined()
    }

    static func formEncode(_ items: [(String, String)]) -> String {
        items.map { "\($0.0)=\(androidQuote($0.1))" }.joined(separator: "&")
    }

    private static func reverseNibble(_ value: Int) -> Int {
        ((value & 1) << 3) | ((value & 2) << 1) | ((value & 4) >> 1) | ((value & 8) >> 3)
    }

    static func nativeHexEncode(_ bytes: Data) -> String {
        bytes.map { String(format: "%02x%02x", reverseNibble(Int($0) & 15), reverseNibble(Int($0) >> 4)) }.joined()
    }

    static func nativeHexDecode(_ text: String) -> Data {
        let chars = Array(text.utf16)
        func digit(_ char: UInt16) -> Int {
            switch char {
            case 48...57: return Int(char - 48)
            case 65...70: return Int(char - 55)
            case 97...102: return Int(char - 87)
            default: return 0
            }
        }
        return Data((0..<(chars.count / 4)).map { index in
            UInt8(reverseNibble(digit(chars[index * 4 + 1])) |
                  (reverseNibble(digit(chars[index * 4 + 3])) << 4))
        })
    }

    static func rc4(_ input: Data, key: String) throws -> Data {
        let keyBytes = Array(key.utf8)
        guard !keyBytes.isEmpty else { throw Failure.invalidKey }
        var state = Array(0...255)
        var j = 0
        for i in 0..<256 {
            j = (j + state[i] + Int(keyBytes[i % keyBytes.count])) & 255
            state.swapAt(i, j)
        }
        var x = 0, y = 0
        return Data(input.map { byte in
            x = (x + 1) & 255
            y = (y + state[x]) & 255
            state.swapAt(x, y)
            return byte ^ UInt8(state[(state[x] + state[y]) & 255])
        })
    }

    static func desEncrypt(_ plain: String, key: String) throws -> Data {
        var source = Array(plain.utf8)
        let padLength = 8 - source.count % 8
        source += [UInt8](repeating: 0, count: padLength)
        source[source.count - 1] = UInt8(padLength)
        let keys = try subkeys(key)
        return Data(stride(from: 0, to: source.count, by: 8).flatMap {
            desBlock(Array(source[$0..<($0 + 8)]), keys: keys)
        })
    }

    static func desDecrypt(_ cipher: Data, key: String) throws -> Data {
        guard !cipher.isEmpty, cipher.count % 8 == 0 else { throw Failure.invalidCipher }
        let keys = Array((try subkeys(key)).reversed())
        let bytes = Array(cipher)
        let plain = stride(from: 0, to: bytes.count, by: 8).flatMap {
            desBlock(Array(bytes[$0..<($0 + 8)]), keys: keys)
        }
        let padding = Int(plain[plain.count - 1])
        guard padding >= 1, padding <= plain.count else { throw Failure.invalidPadding }
        return Data(plain.dropLast(padding))
    }

    private static func bits(_ bytes: [UInt8]) -> [Int] {
        (0..<(bytes.count * 8)).map { Int((bytes[$0 / 8] >> ($0 % 8)) & 1) }
    }

    private static func permute(_ bits: [Int], _ table: [Int]) -> [Int] {
        table.map { bits[$0] & 1 }
    }

    private static func subkeys(_ key: String) throws -> [[Int]] {
        let bytes = Array(key.utf8)
        guard bytes.count == 8 else { throw Failure.invalidKey }
        let scheduled = permute(bits(bytes), pc1)
        var left = Array(scheduled[..<28]), right = Array(scheduled[28...])
        return shifts.map { shift in
            left = Array(left.dropFirst(shift)) + Array(left.prefix(shift))
            right = Array(right.dropFirst(shift)) + Array(right.prefix(shift))
            return permute(left + right, pc2)
        }
    }

    private static func desFunction(_ right: [Int], _ key: [Int]) -> [Int] {
        let expanded = permute(right, expansion)
        let mixed = (0..<48).map { expanded[$0] ^ key[$0] }
        var output = [Int](repeating: 0, count: 32)
        for box in 0..<8 {
            let i = box * 6
            let row = mixed[i] * 2 + mixed[i + 5]
            let column = mixed[i + 1] * 8 + mixed[i + 2] * 4 + mixed[i + 3] * 2 + mixed[i + 4]
            let value = sbox[box][row][column]
            for bit in 0..<4 { output[box * 4 + bit] = (value >> (3 - bit)) & 1 }
        }
        return permute(output, permutation)
    }

    private static func desBlock(_ block: [UInt8], keys: [[Int]]) -> [UInt8] {
        let input = permute(bits(block), ip)
        var left = Array(input[..<32]), right = Array(input[32...])
        for key in keys {
            let mixed = desFunction(right, key)
            let next = (0..<32).map { left[$0] ^ mixed[$0] }
            left = right
            right = next
        }
        let output = permute(right + left, fp)
        return (0..<8).map { byte in
            var value: UInt8 = 0
            for bit in 0..<8 { value |= UInt8(output[byte * 8 + bit] & 1) << bit }
            return value
        }
    }

    private static let ip = [57,49,41,33,25,17,9,1,59,51,43,35,27,19,11,3,61,53,45,37,29,21,13,5,63,55,47,39,31,23,15,7,56,48,40,32,24,16,8,0,58,50,42,34,26,18,10,2,60,52,44,36,28,20,12,4,62,54,46,38,30,22,14,6]
    private static let fp = [39,7,47,15,55,23,63,31,38,6,46,14,54,22,62,30,37,5,45,13,53,21,61,29,36,4,44,12,52,20,60,28,35,3,43,11,51,19,59,27,34,2,42,10,50,18,58,26,33,1,41,9,49,17,57,25,32,0,40,8,48,16,56,24]
    private static let expansion = [31,0,1,2,3,4,3,4,5,6,7,8,7,8,9,10,11,12,11,12,13,14,15,16,15,16,17,18,19,20,19,20,21,22,23,24,23,24,25,26,27,28,27,28,29,30,31,0]
    private static let permutation = [15,6,19,20,28,11,27,16,0,14,22,25,4,17,30,9,1,7,23,13,31,26,2,8,18,12,29,5,21,10,3,24]
    private static let pc1 = [56,48,40,32,24,16,8,0,57,49,41,33,25,17,9,1,58,50,42,34,26,18,10,2,59,51,43,35,62,54,46,38,30,22,14,6,61,53,45,37,29,21,13,5,60,52,44,36,28,20,12,4,27,19,11,3]
    private static let pc2 = [13,16,10,23,0,4,2,27,14,5,20,9,22,18,11,3,25,7,15,6,26,19,12,1,40,51,30,36,46,54,29,39,50,44,32,46,43,48,38,55,33,52,45,41,49,35,28,31]
    private static let shifts = [1,1,2,2,2,2,2,2,1,2,2,2,2,2,2,1]
    private static let sbox = [
        [[14,4,13,1,2,15,11,8,3,10,6,12,5,9,0,7],[0,15,7,4,14,2,13,1,10,6,12,11,9,5,3,8],[4,1,14,8,13,6,2,11,15,12,9,7,3,10,5,0],[15,12,8,2,4,9,1,7,5,11,3,14,10,0,6,13]],
        [[15,1,8,14,6,11,3,4,9,7,2,13,12,0,5,10],[3,13,4,7,15,2,8,14,12,0,1,10,6,9,11,5],[0,14,7,11,10,4,13,1,5,8,12,6,9,3,2,15],[13,8,10,1,3,15,4,2,11,6,7,12,0,5,14,9]],
        [[10,0,9,14,6,3,15,5,1,13,12,7,11,4,2,8],[13,7,0,9,3,4,6,10,2,8,5,14,12,11,15,1],[13,6,4,9,8,15,3,0,11,1,2,12,5,10,14,7],[1,10,13,0,6,9,8,7,4,15,14,3,11,5,2,12]],
        [[7,13,14,3,0,6,9,10,1,2,8,5,11,12,4,15],[13,8,11,5,6,15,0,3,4,7,2,12,1,10,14,9],[10,6,9,0,12,11,7,13,15,1,3,14,5,2,8,4],[3,15,0,6,10,1,13,8,9,4,5,11,12,7,2,14]],
        [[2,12,4,1,7,10,11,6,8,5,3,15,13,0,14,9],[14,11,2,12,4,7,13,1,5,0,15,10,3,9,8,6],[4,2,1,11,10,13,7,8,15,9,12,5,6,3,0,14],[11,8,12,7,1,14,2,13,6,15,0,9,10,4,5,3]],
        [[12,1,10,15,9,2,6,8,0,13,3,4,14,7,5,11],[10,15,4,2,7,12,9,5,6,1,13,14,0,11,3,8],[9,14,15,5,2,8,12,3,7,0,4,10,1,13,11,6],[4,3,2,12,9,5,15,10,11,14,1,7,6,0,8,13]],
        [[4,11,2,14,15,0,8,13,3,12,9,7,5,10,6,1],[13,0,11,7,4,9,1,10,14,3,5,12,2,15,8,6],[1,4,11,13,12,3,7,14,10,15,6,8,0,5,9,2],[6,11,13,8,1,4,10,7,9,5,0,15,14,2,3,12]],
        [[13,2,8,4,6,15,11,1,10,9,3,14,5,0,12,7],[1,15,13,8,10,3,7,4,12,5,6,11,0,14,9,2],[7,11,4,1,9,12,14,2,0,6,10,13,15,3,5,8],[2,1,14,7,4,10,8,13,15,12,9,0,3,5,6,11]]
    ]
}
