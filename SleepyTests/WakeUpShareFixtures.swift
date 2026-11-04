import Foundation

/// 固定值逐字来自 Android app/src/test/resources/jw/wakeup/vectors.json。
/// 不是本地重新计算的“期望”; 服务端错误/格式响应为显式合成 HTTP fixture。
enum WakeUpShareFixtures {
    static let nonce = "ABCDEFGHIJ"
    static let token = "ZX9kQ3r7Lp"
    static let nowMs: Int64 = 1730000000000
    static let rc4Key = "60c35ea2c56de5819745b87f5153eeef6a54b16abe53329c432da1b4e118d4d9dcccede2ea6e77349e45a85dc0958f5f31cd22941af1d9898bc5ba70303e7187"
    static let signB = "010c05000f0804090f0c07040b04020f0009020b05060f0e050a0402030301050c020c000e010d070e070e0402020c050d07080302080e03080a070e0c060e0b080905060009060306080d0002090908"
    static let signANonce = "DKRYfmt07E"
    static let signA = "0b0c05040d05030200060c0c030b0106060900090a000f0a0c08090d09010007000b0d0b010501020c0d00020605010f090c0f00020f00080b0b0b04060e050907010300080b0b06000804070e0f050c0e00090b00060f04010d08070103080306020109030f0007010f0d00050b060e0103060b09020d04050106060c0e0e040d030e000402080e020f09020d03050e0805010a020e04070b030600010c070904010f0f040e010f0407070e05000a05"
    static let shareRequestBody = "&data=MBR1ZaMNSIYcUxqu85MJ5w%3D%3D&area=&screensize=1080x2400&cuid=C77D5D04D94F5F56C8A0A6DC3DBF240A%7C0&os=android&city=&abis=arm64-v8a&channel=100271a&appBit=64&vc=450&deviceId=&token=1_XPXQH3c5HRPtFHkSwi3sCCURmT25QfxM&adid=d58a81f457529caf0e642e7f9d97e447112bd763&province=&pkgName=com.suda.yzune.wakeupschedule&appId=wakeup&download_type=1&vcname=6.1.70&sdk=35&device=Pixel+7&brand=google&operatorid=&nt=wifi&sign=2bbb5b354c38d2c071aed5bb291ed3c3&_t_=1730000000&kakorrhaphiophobia=1730000000000"
    static let rawSchedule = #"""
    {"courseLen":2,"theBreakLen":10}
    [{"node":1,"startTime":"08:00","endTime":"08:55"},{"node":2,"startTime":"09:05","endTime":"10:00"},{"node":5,"startTime":"14:00","endTime":"14:55"},{"node":3,"startTime":"00:00","endTime":"00:00"},{"node":11,"startTime":"19:00","endTime":"19:55"}]
    {"nodes":[1,2,3,4,5],"startDate":"2025/9/1","maxWeek":20}
    [{"id":7,"courseName":"高等数学"},{"id":9,"courseName":"大学英语"},{"id":404,"courseName":"孤儿课"}]
    [{"id":7,"teacher":"张老师","room":"A101","day":1,"startNode":1,"step":2,"startWeek":1,"endWeek":8,"type":0},{"id":9,"teacher":"","room":"","day":3,"startNode":5,"step":1,"startWeek":2,"endWeek":10,"type":2},{"id":7,"teacher":"张老师","room":"B202","day":5,"startNode":3,"step":2,"startWeek":1,"endWeek":7,"type":1},{"id":null,"teacher":"x","room":"y","day":2,"startNode":1,"step":1,"startWeek":1,"endWeek":2,"type":0}]
    """#
    static let antispamBody = Data("{\"errNo\":0,\"data\":{\"data\":\"\(signB)\"}}".utf8)
    static let serverRejection = Data(#"{"errNo":6,"data":{}}"#.utf8)
    static let invalidJSON = Data("<html>service unavailable</html>".utf8)
}
