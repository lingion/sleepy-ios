import XCTest
@testable import Sleepy

final class WakeUpV6170CryptoTests: XCTestCase {
    func testMD5AndProtocolDeviceIDsMatchVendorGoldenValues() {
        XCTAssertEqual(WakeUpV6170Crypto.md5Hex(""), "d41d8cd98f00b204e9800998ecf8427e")
        XCTAssertEqual(WakeUpV6170Crypto.md5Hex("abc"), "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(WakeUpV6170Crypto.md5Hex("8&%d*"), "6560c614ae407a4cf1f1c069e1f028c3")
        let device = WakeUpShareProtocol.Device()
        XCTAssertEqual(device.cuid, "C77D5D04D94F5F56C8A0A6DC3DBF240A|0")
        XCTAssertEqual(device.adid, "d58a81f457529caf0e642e7f9d97e447112bd763")
    }

    func testPrivateDESMatchesVendorCiphertextIncludingFullBlockPadding() throws {
        let cases = [
            ("01234567", "passkey!", "bad1a3e396360ae3143e58313a6d02e8"),
            ("x", "abcdefgh", "5f77ae39c891a811"),
            ("12345678901234567890123456789012", "@fG2SuLA", "1ff5b33babcf4d57229464a8a497b188d6ecce379ef3e595da6ecabb85a0cbe25d66121da989294f")
        ]
        for (plain, key, expected) in cases {
            let encrypted = try WakeUpV6170Crypto.desEncrypt(plain, key: key)
            XCTAssertEqual(encrypted.map { String(format: "%02x", $0) }.joined(), expected)
            XCTAssertEqual(try WakeUpV6170Crypto.desDecrypt(encrypted, key: key), Data(plain.utf8))
        }
    }

    func testNativeHexMatchesVendorGoldenBytesAndDropsRaggedTail() {
        let bytes = Data((0..<33).map { UInt8(($0 * 53 + 7) & 255) })
        let expected = "0e00030c080e06050d0b00080a02050e0f050207090807020c01010d0b0704040e0a03010803060f0d0400060a0905030f0f020c090607090c0b01000b0c040e0e05"
        XCTAssertEqual(WakeUpV6170Crypto.nativeHexEncode(bytes), expected)
        XCTAssertEqual(WakeUpV6170Crypto.nativeHexDecode(expected + "0"), bytes)
    }

    func testSignAAndSignBMatchIndependentVendorVectors() throws {
        let f = WakeUpShareFixtures.self
        XCTAssertEqual(try WakeUpShareProtocol.makeSignA(cuid: WakeUpShareProtocol.Device().cuid, rand10: f.signANonce), f.signA)
        XCTAssertEqual(try WakeUpShareProtocol.tokenFromSignB(f.signB, rand10: f.nonce), f.token)
        XCTAssertThrowsError(try WakeUpShareProtocol.tokenFromSignB(f.signB, rand10: "ABCDEFGHIX"))
        XCTAssertThrowsError(try WakeUpShareProtocol.tokenFromSignB("", rand10: f.nonce))
        XCTAssertThrowsError(try WakeUpV6170Crypto.desDecrypt(Data(), key: "abcdefgh"))
        XCTAssertThrowsError(try WakeUpV6170Crypto.desDecrypt(Data([1]), key: "abcdefgh"))
        XCTAssertThrowsError(try WakeUpV6170Crypto.desEncrypt("x", key: "short"))
    }

    func testRC4AndKeyDerivationMatchVendorVectors() throws {
        XCTAssertEqual(WakeUpShareProtocol.getRc4Key(WakeUpShareFixtures.token), WakeUpShareFixtures.rc4Key)
        XCTAssertEqual(try WakeUpV6170Crypto.rc4(Data("hello".utf8), key: "worldkey").base64EncodedString(), "K/obS2E=")
        XCTAssertEqual(try WakeUpV6170Crypto.rc4(Data("key=AbCdEf123456".utf8), key: WakeUpShareFixtures.rc4Key).base64EncodedString(), "MBR1ZaMNSIYcUxqu85MJ5w==")
        XCTAssertThrowsError(try WakeUpV6170Crypto.rc4(Data([0]), key: ""))
    }

    func testFullSignedShareRequestMatchesGoldenBodyByteForByte() throws {
        let request = try WakeUpShareProtocol.buildShareRequest(code: "AbCdEf123456", token: WakeUpShareFixtures.token,
                                                               device: .init(), nowMs: WakeUpShareFixtures.nowMs)
        XCTAssertEqual(request.rc4Key, WakeUpShareFixtures.rc4Key)
        XCTAssertEqual(request.body, WakeUpShareFixtures.shareRequestBody)
        XCTAssertEqual(WakeUpShareProtocol.getSign(Data("a=1b=2".utf8).base64EncodedString(), token: WakeUpShareFixtures.token),
                       "79efc9dc38e1d2dbe38dc6b6279980df")
    }

    func testFormEncodingPreservesVendorSpacePunctuationAndUTF8Semantics() {
        for (input, expected) in [("a b", "a+b"), ("!'()*~", "%21%27%28%29%2A~"),
                                  ("中文&=", "%E4%B8%AD%E6%96%87%26%3D"), ("+%", "%2B%25")] {
            XCTAssertEqual(WakeUpV6170Crypto.androidQuote(input), expected)
        }
        XCTAssertEqual(WakeUpV6170Crypto.formEncode([("data", "SIGN A±"), ("k1", "v 1"), ("k2", "k")]),
                       "data=SIGN+A%C2%B1&k1=v+1&k2=k")
    }
}
