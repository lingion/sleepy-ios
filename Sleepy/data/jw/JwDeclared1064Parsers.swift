import Foundation
import SwiftSoup

final class JwDeclaredJinZhiParser:JwParser {
    let source:String
    let protocolType:String
    init(_ source:String,protocolType:String) { self.source=source;self.protocolType=protocolType }
    func generateCourseList()->[JwCourse] {
        switch protocolType {
        case "jz_1":return WakeUpCompat.parseJzHtml(source)
        case "jz_x":return WakeUpCompat.parseJzX(source)
        case "wist":return WakeUpCompat.parseJzWist(source)
        case "xmu":return WakeUpCompat.parseJzXmu(source)
        case "swjtu_post":return WakeUpCompat.parseJzNativeChain(source)
        default:return []
        }
    }
}

final class JwQzSchoolParser:JwQzParser {
    let protocolType:String
    init(_ source:String,protocolType:String) { self.protocolType=protocolType;super.init(source) }
    override var usesSchoolRowMapping:Bool { true }
    override var tableName:String { ["qz_wit","qz_ahut"].contains(protocolType) ? "kbcontent1":"kbcontent" }
    override func rowNodes(_ row:Int)->(Int,Int) {
        if protocolType=="qz_single_node" { return(row,row) }
        let mapping:[(Int,Int)]
        switch protocolType {
        case "qz_njust":mapping=[(1,3),(4,5),(6,7),(8,10),(11,13)]
        case "qz_wit":mapping=[(1,2),(3,4),(6,7),(8,9),(10,12)]
        case "qz_ecust":mapping=[(1,2),(3,4),(4,4),(5,6),(7,8),(8,8),(9,10),(11,12)]
        case "qz_ahut":mapping=[(1,2),(3,4),(5,6),(7,8),(9,11),(12,12)]
        case "qz_bjfu":mapping=[(1,2),(3,4),(5,5),(6,7),(8,9),(10,11),(12,12)]
        default:mapping=[]
        }
        return mapping.indices.contains(row-1) ? mapping[row-1]:super.rowNodes(row)
    }
    override func parseCourseName(_ infoStr:String)->String {
        protocolType=="qz_bjfu" ? jw1064Plain(infoStr.components(separatedBy:"<br>")[0]):super.parseCourseName(infoStr)
    }
    override var matchedFeatureList:[String] { super.matchedFeatureList+["declared-row-map=\(protocolType)"] }
}
final class JwQzFsptParser:JwQzParser {
    override var usesSchoolRowMapping:Bool { true }
    override func convert(day:Int,nodeCount:Int,infoStr:String,courseList:inout[JwCourse]) {
        guard let body=try? SwiftSoup.parseBodyFragment(infoStr).body(),let time=try? body.getElementsByAttributeValue("title","周次(节次)").first() else { return }
        _ = try? time.text(jw1064Text(time).components(separatedBy:"[")[0].replacingOccurrences(of:"(周)",with:"周"))
        _ = try? body.getElementsByAttributeValue("title","节次").remove()
        super.convert(day:day,nodeCount:nodeCount,infoStr:(try? body.html()) ?? "",courseList:&courseList)
    }
}
final class JwQzUstbParser:JwQzParser {
    override var usesSchoolRowMapping:Bool { true }
    override func convert(day:Int,nodeCount:Int,infoStr:String,courseList:inout[JwCourse]) {
        guard let body=try? SwiftSoup.parseBodyFragment(infoStr).body(),let room=try? body.getElementsByAttributeValue("title","教室").first() else { return }
        let raw=(try? room.html()) ?? ""
        guard let range=raw.range(of:#"(?:&nbsp;)+"#,options:.regularExpression) else { return }
        let parts=[jw1064Plain(String(raw[..<range.lowerBound])),jw1064Plain(String(raw[range.upperBound...]))]
        var location=jw1064Text(body,"[title=上课地点]");if location.hasPrefix("[") && location.hasSuffix("]") { location=String(location.dropFirst().dropLast()) }
        _ = try? room.text(location+parts[0]);_ = try? body.getElementsByAttributeValue("title","节次").remove()
        _ = try? body.appendElement("font").attr("title","周次").text(parts[1])
        super.convert(day:day,nodeCount:nodeCount,infoStr:(try? body.html()) ?? "",courseList:&courseList)
    }
}

final class JwZfClassParser:JwParser,JwParserConfidenceReporting {
    let source:String
    init(_ source:String) { self.source=source }
    func generateCourseList()->[JwCourse] { JwZfVariantHtml.parseClass(source) }
    var confidenceValue:Int { guard let doc=try? SwiftSoup.parse(source) else { return 0 };return jw1064Elements(doc,"table#Table6, table#table6").isEmpty ? 0:100 }
    var matchedFeatureList:[String] { confidenceValue>0 ? ["zf-class-table6"]:[] }
}
