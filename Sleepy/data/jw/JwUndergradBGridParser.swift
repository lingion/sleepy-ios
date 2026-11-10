import Foundation
import SwiftSoup

final class JwUndergradBGridParser: JwParser {
    let source:String
    let protocolType:String
    init(_ source:String,protocolType:String) { self.source=source;self.protocolType=protocolType }
    private lazy var doc: Document? = {
        let document = try? SwiftSoup.parse(source)
        _ = document?.outputSettings().prettyPrint(pretty: false)
        return document
    }()
    func generateCourseList()->[JwCourse] {
        let rows:[JwCourse]
        switch protocolType { case "sicnu":rows=sicnu();case "nuist":rows=nuist();case "sit":rows=sit();case "sysu":rows=sysu();default:rows=[] }
        return rows.filter(JwUndergradBHtmlParser.valid)
    }
    private func sicnu()->[JwCourse] {
        guard let table = try? doc?.select(".PintTableStyle").first() else { return [] }
        var occupied=Array(repeating:0,count:7),out:[JwCourse]=[],node=1
        for row in jw1064Elements(table,"tr") {
            let cells=row.children().array().filter { $0.tagName()=="td" }
            if cells.contains(where:{$0.hasAttr("colspan")}) { continue }
            var column=0
            for cell in cells {
                if cell.hasAttr("width") { continue }
                while column<7 && occupied[column]>=node { column+=1 };if column>=7 { break }
                let rawSpan=jw1064Attribute(cell,"rowspan")
                guard let span=jw1064Integer(rawSpan.isEmpty ? "1":rawSpan),let last=JwUndergradBHtmlParser.endNode(node,span) else { break }
                let day=column+1;occupied[column]=last;column+=1
                let spanElement=try? cell.select("span").first(), raw=(try? spanElement?.html()) ?? (try? cell.html()) ?? ""
                var name="",parity=0
                for piece in raw.components(separatedBy:";") {
                    let parts=Array(jw1064Split(#"(?i)<br\s*/?>"#,piece.replacingOccurrences(of:#"\[\d+]"#,with:"",options:.regularExpression)).map(jw1064Plain).drop(while:{$0.isEmpty}))
                    guard !parts.isEmpty else { continue }
                    let teacher:String,detail:String
                    if parts.count==1 {
                        guard !name.isEmpty,parts[0].contains("[") else { continue };teacher=parts[0].components(separatedBy:"[")[0];detail=parts[0].components(separatedBy:"[").dropFirst().joined(separator:"[")
                    } else {
                        name=parts[0];parity=name.hasSuffix("**") ? 2:name.hasSuffix("*") ? 1:0
                        if name.hasSuffix("**") { name=String(name.dropLast(2)) };if name.hasSuffix("*") { name=String(name.dropLast()) }
                        if parts.count==2 { guard parts[1].contains("[") else { continue };teacher=parts[1].components(separatedBy:"[")[0];detail=parts[1].components(separatedBy:"[").dropFirst().joined(separator:"[") }
                        else { teacher=parts[1];detail=parts[2] }
                    }
                    guard detail.contains("(") else { continue }
                    let room=detail.components(separatedBy:"(")[0],weeks=detail.components(separatedBy:"(").dropFirst().joined(separator:"(").components(separatedBy:"周")[0].components(separatedBy:")")[0]
                    for (first,end,_) in JwUndergradBHtmlParser.weeks(weeks) { out.append(JwCourse(name:name,room:room,teacher:teacher,day:day,startNode:node,endNode:last,startWeek:first,endWeek:end,type:parity)) }
                }
            }
            node+=1
        }
        return out
    }
    private func nuist()->[JwCourse] {
        let rows=jw1064Elements(try? doc?.getElementById("TABLE1"),"tr");guard let first=rows.first else { return [] }
        let leading=jw1064Elements(first,"td").filter{!jw1064Text($0).hasPrefix("星期")}.count
        var out:[JwCourse]=[],doubleRow=false
        for (rowIndex,row) in rows.enumerated() where rowIndex>0 {
            for (column,cell) in jw1064Elements(row,"td").enumerated() {
                if column<leading { if jw1064Text(cell).contains("~") || jw1064Text(cell).contains("～") { doubleRow=true };continue }
                let day=column-leading+1
                for piece in jw1064Split(#"(?i)◆|(?:<br\s*/?>)+"#,(try? cell.html()) ?? "") {
                    let fields=jw1064Plain(piece).components(separatedBy:"◇").map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}
                    guard fields.count>=2,!fields[0].isEmpty else { continue }
                    func field(_ i:Int)->String { fields.indices.contains(i) ? fields[i]:"" }
                    func parenthesized(_ s:String)->String { s.contains("(") ? s.components(separatedBy:"(").dropFirst().joined(separator:"(").components(separatedBy:")")[0].trimmingCharacters(in:.whitespacesAndNewlines):"" }
                    func numeric(_ s:String)->Bool { s.range(of:#"^\d.*\d$"#,options:.regularExpression) != nil }
                    func afterBrace(_ s:String)->String { s.contains("}") ? s.components(separatedBy:"}").dropFirst().joined(separator:"}").trimmingCharacters(in:.whitespacesAndNewlines):"" }
                    let teacher=field(1).components(separatedBy:"(")[0].trimmingCharacters(in:.whitespacesAndNewlines),firstWeeks=parenthesized(field(1)),metadata=numeric(firstWeeks) ? firstWeeks:parenthesized(field(3)),roomA=afterBrace(field(4)),room=roomA.isEmpty ? afterBrace(field(2)):roomA
                    for timing in fields.last!.components(separatedBy:",") where !timing.isEmpty {
                        let encoded=timing.contains("{") ? timing.components(separatedBy:"{").dropFirst().joined(separator:"{").components(separatedBy:"}")[0].replacingOccurrences(of:#"节$"#,with:"",options:.regularExpression):""
                        let packed=encoded.range(of:#"^[0-9]{1,4}$"#,options:.regularExpression) != nil ? encoded:""
                        let nodes:(Int,Int)
                        switch packed.count {
                        case 1,2:nodes=(Int(String(packed.first!))!,Int(String(packed.last!))!)
                        case 3:nodes=(Int(String(packed.first!))!,Int(packed.dropFirst())!)
                        case 4:nodes=(Int(packed.prefix(2))!,Int(packed.suffix(2))!)
                        default:nodes=doubleRow ? (rowIndex*2-1,rowIndex*2):(rowIndex,rowIndex)
                        }
                        let weeks=(numeric(metadata) ? metadata:timing.components(separatedBy:"{")[0]).replacingOccurrences(of:"[单双]",with:"",options:.regularExpression)
                        for (first,last,_) in JwUndergradBHtmlParser.weeks(weeks) { out.append(JwCourse(name:fields[0],room:room,teacher:teacher,day:day,startNode:nodes.0,endNode:nodes.1,startWeek:first,endWeek:last,type:jw1064Parity(timing))) }
                    }
                }
            }
        }
        return out
    }
    private func sit()->[JwCourse] {
        guard let body=try? SwiftSoup.parse(source.components(separatedBy:"<body>").last ?? source),let table=try? body.select("form").first()?.select("table").first() else { return [] }
        _ = body.outputSettings().prettyPrint(pretty: false)
        var out:[JwCourse]=[],occupied=Array(repeating:0,count:7)
        for (index,row) in jw1064Elements(table,"tr").enumerated() where index>=2 {
            let cells=row.children().array().filter{$0.tagName()=="td"}
            guard let first=cells.first,let node=jw1064Integer(jw1064Text(first)),node>0 else { continue }
            var column=0
            for cell in cells.dropFirst() {
                while column<7 && occupied[column]>=node { column+=1 };if column>=7 { break }
                let day=column+1,raw=jw1064Attribute(cell,"rowspan")
                guard let span=jw1064Integer(raw.isEmpty ? "1":raw),let last=JwUndergradBHtmlParser.endNode(node,span) else { break }
                occupied[column]=last;column+=1
                for entry in jw1064Elements(cell,"[name=d1]") {
                    let f=jw1064Text(entry).components(separatedBy:" ").filter{!$0.isEmpty};guard f.count>=5 else { continue }
                    let raw=f[1],parity=raw.contains("**") ? 2:raw.contains("*") ? 1:0,stripped=raw.replacingOccurrences(of:"*",with:"")
                    guard let prefix=stripped.first,[Character("第"),"(","（","["].contains(prefix) else { continue }
                    let weeks=String(stripped.dropFirst()).replacingOccurrences(of:#"周$"#,with:"",options:.regularExpression)
                    for (first,end,_) in JwUndergradBHtmlParser.weeks(weeks) { out.append(JwCourse(name:f[0],room:f[2],teacher:f[4],day:day,startNode:node,endNode:last,startWeek:first,endWeek:end,type:parity)) }
                }
            }
        }
        return out
    }
    private func sysu()->[JwCourse] {
        let tables=jw1064Elements(doc,".com-table.class-schedule-table2");guard tables.count>=2,let headerRow=jw1064Elements(tables[0],"tr").first else { return [] }
        let headers=jw1064Elements(headerRow,"th"),sun=headers.firstIndex{jw1064Text($0).contains("星期日")},mon=headers.firstIndex{jw1064Text($0).contains("星期一")},sundayFirst=(sun != nil && mon != nil && sun!<mon!)
        var widths:[Int]=[]
        for header in headers where ((try? header.className()) ?? "") != "th2" { let raw=jw1064Attribute(header,"colspan");guard let n=jw1064Integer(raw.isEmpty ? "1":raw),n>0 else { return [] };widths.append(n) }
        guard (1...7).contains(widths.count) else { return [] }
        var boundaries=[0];for width in widths { boundaries.append(boundaries.last!+width) }
        struct Occupied { let first:Int;let last:Int;let until:Int }
        var occupied:[Occupied]=[],out:[JwCourse]=[]
        for (index,row) in jw1064Elements(try? tables[1].select("tbody").first(),"tr").enumerated() {
            let node=index+1;occupied.removeAll{$0.until<node};var offset=0
            for cell in jw1064Elements(row,"td") {
                if ((try? cell.className()) ?? "")=="td2-1" { continue }
                while let previous=occupied.first(where:{offset >= $0.first && offset < $0.last}) { offset=previous.last }
                let raw=jw1064Attribute(cell,"colspan");guard let span=jw1064Integer(raw.isEmpty ? "1":raw),span>0 else { break }
                guard let dayIndex=widths.indices.first(where:{offset>=boundaries[$0] && offset<boundaries[$0+1]}) else { break }
                let last=offset+span;guard last<=boundaries[dayIndex+1],!occupied.contains(where:{offset<$0.last && last>$0.first}) else { break }
                let height=jw1064Attribute(cell,"rowspan");guard let count=jw1064Integer(height.isEmpty ? "1":height),let end=JwUndergradBHtmlParser.endNode(node,count) else { break }
                occupied.append(Occupied(first:offset,last:last,until:end));offset=last
                if ((try? cell.className()) ?? "")=="11111" || jw1064Text(cell).isEmpty { continue }
                let parts=jw1064Elements(cell,"span").map{jw1064Text($0).replacingOccurrences(of:"/",with:"")};guard parts.count>=4 else { continue }
                let names=jw1064Split("[()]",parts[1]);guard names.count>2 else { continue }
                let day=sundayFirst ? (dayIndex==0 ? 7:dayIndex):dayIndex+1,parity=parts[0].contains("单周") ? 1:parts[0].contains("双周") ? 2:0,weeks=parts[0].replacingOccurrences(of:"每周",with:"").replacingOccurrences(of:"单周",with:"").replacingOccurrences(of:"双周",with:"")
                for (first,last,_) in JwUndergradBHtmlParser.weeks(weeks) { out.append(JwCourse(name:names[2],room:parts[3],teacher:parts[2],day:day,startNode:node,endNode:end,startWeek:first,endWeek:last,type:parity)) }
            }
        }
        return out
    }
}
