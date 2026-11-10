import Foundation
import SwiftSoup

final class JwUndergradCParser:JwParser,JwParserConfidenceReporting {
    let source:String
    let protocolType:String
    init(_ source:String,protocolType:String) { self.source=source;self.protocolType=protocolType }
    private var doc:Document? { try? SwiftSoup.parse(source) }
    func generateCourseList()->[JwCourse] {
        let rows:[JwCourse]
        switch protocolType { case "xhtd":rows=xhtd();case "xytc":rows=xytc();case "cidp":rows=cidp();case "sdpei":rows=sdpei();case "shu":rows=shu();case "cqu":rows=cqu();case "jmpt":rows=jmpt();case "lngd":rows=lngd();case "vatuu":rows=vatuu();case "yzzy":rows=yzzy();default:rows=[] }
        var seen:Set<JwCourse>=[];return rows.filter{seen.insert($0).inserted}
    }
    var confidenceValue:Int {
        let selectors=["xhtd":"#kbtable div[id]","xytc":"#report_tSxsgrkbcx","cidp":"#scheduleTable .Content","sdpei":"#tableMain","shu":"[name=rowclass]","cqu":".item-box","jmpt":".admintable","lngd":"#root .kbappTimetableDayColumnRoot___1DlDV, #wdkb-kb .kbappTimetableDayColumnRoot","vatuu":".table_border","yzzy":"#timetable .kbcontent"]
        guard let selector=selectors[protocolType],protocolType != "cqu" || source.contains("print-schedule-table") else { return 0 }
        let count=jw1064Elements(doc,selector).count;return (protocolType == "jmpt" ? count>1:count>0) ? 100:0
    }
    var matchedFeatureList:[String] { [] }
    private func weeks(_ raw:String)->[(Int,Int,Int)] {
        var text=raw.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"（",with:"(").replacingOccurrences(of:"）",with:")").replacingOccurrences(of:"、",with:",").replacingOccurrences(of:"\\",with:",").replacingOccurrences(of:"~",with:"-").replacingOccurrences(of:"～",with:"-")
        if let m=jw1064Matches(#"^(.*?)隔([①-⑳])周?$"#,text).first {
            let base=schoolWeekRanges(m[1].trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:#"周$"#,with:"",options:.regularExpression))
            guard !base.isEmpty,base.allSatisfy({$0.2==0}),let scalar=m[2].unicodeScalars.first else { return [] }
            let step=Int(scalar.value)-9312+1
            return base.flatMap { a,b,_ in stride(from:a,through:b,by:step).map{($0,$0,0)} }
        }
        if text.contains("隔") { return [] }
        if text.hasPrefix("("),text.hasSuffix(")"),text.filter({$0=="("}).count==1 { text=String(text.dropFirst().dropLast()) }
        text=text.replacingOccurrences(of:#"\(([单双])\)周$"#,with:"周($1)",options:.regularExpression)
        return schoolWeekRanges(text,trailingParityAppliesToAll:true)
    }
    private func slots(_ name:String,_ room:String,_ teacher:String,_ day:Int,_ nodes:String,_ weekText:String,credit:Float=0,note:String="",parity:Int=0)->[JwCourse] {
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,(1...7).contains(day),credit.isFinite,credit>=0 else { return [] }
        var out:[JwCourse]=[]
        for (start,end,kind) in weeks(weekText) { for (first,last) in schoolNodeRanges(nodes) {
            if parity != 0 && kind != 0 && parity != kind { continue };let type=parity==0 ? kind:parity
            if type != 0 && start%2 != type%2 && end==start { continue }
            out.append(JwCourse(name:name.trimmingCharacters(in:.whitespacesAndNewlines),room:room.trimmingCharacters(in:.whitespacesAndNewlines),teacher:teacher.trimmingCharacters(in:.whitespacesAndNewlines),day:day,startNode:first,endNode:last,startWeek:start,endWeek:end,type:type,credit:credit,note:note.trimmingCharacters(in:.whitespacesAndNewlines)))
        } }
        return out
    }
    private func lines(_ html:String)->[String] { jw1064Split(#"(?i)<br\s*/?>"#,html).map(jw1064Plain) }
    private func xhtd()->[JwCourse] {
        var out:[JwCourse]=[]
        for cell in jw1064Elements(doc,"#kbtable div[id]") {
            guard let coordinate=jw1064Matches(#"^([0-9]+)-([1-7])$"#,cell.id()).first,!jw1064Elements(cell,"nobr").isEmpty,let block=Int(coordinate[1]),block>0,block<=Int(Int32.max)/2 else { continue }
            var f=lines((try? cell.html()) ?? "");if f.count%5==1 && f.last!.isEmpty { f.removeLast() };if f.count%5 != 0 { continue }
            for index in stride(from:0,to:f.count,by:5) { out += slots(f[index],f[index+4],f[index+2],Int(coordinate[2])!,"\(block*2-1)-\(block*2)",f[index+3]) }
        }
        return out
    }
    private func bridge(_ html:String)->(String,String)? {
        let p=jw1064Split(#"(?i)<br\s*/?>"#,html)
        if p.count==2 { return(p[0],p[1]) };if p.count==3 { return p[0].utf16.count+p[1].utf16.count<4 ? (p[0]+p[1],p[2]):(p[0],p[1]+p[2]) };return nil
    }
    private func xytc()->[JwCourse] {
        var out:[JwCourse]=[]
        for cell in jw1064Elements(doc,"#report_tSxsgrkbcx td") {
            let t=((try? cell.html()) ?? "").components(separatedBy:"&nbsp;");var entries:[[String]]=[]
            switch t.count {
            case 6:entries=[t]
            case 7:entries=[[t[0],t[1],t[3],t[4],t[5],t[6]]]
            case 11,13:
                let extra=t.count==13 ? 1:0,offset=5+(t.count==13 ? 1:0);guard let split=bridge(t[offset]) else { continue }
                entries=[[t[0],t[1],t[2+extra],t[3+extra],t[4+extra],split.0],[split.1,t[offset+1],t[offset+2+extra],t[offset+3+extra],t[offset+4+extra],t[offset+5+extra]]]
            default:break
            }
            for e in entries { out += slots(jw1064Plain(e[0]),jw1064Plain(e[4]),jw1064Plain(e[5]),jw1064Day(jw1064Plain(e[2])),jw1064Plain(e[3]).replacingOccurrences(of:#"节$"#,with:"",options:.regularExpression),lines(e[1]).last(where:{!$0.isEmpty}) ?? "") }
        }
        return out
    }
    private func spanCourse(_ item:Element,_ day:Int,_ first:Int,_ last:Int)->[JwCourse] {
        slots(jw1064Text(item,".spLUName").replacingOccurrences(of:#"^《|》$"#,with:"",options:.regularExpression),jw1064Text(item,".spBuilding")+jw1064Text(item,".spClassroom"),jw1064Text(item,".spTeacherName"),day,"\(first)-\(last)",jw1064Text(item,".spWeekInfo"))
    }
    private func cidp()->[JwCourse] {
        var out:[JwCourse]=[]
        for cell in jw1064Elements(doc,"#scheduleTable .Content") {
            guard let first=jw1064Integer(jw1064Attribute(cell,"data-class")),first>0,first<Int(Int32.max),let day=jw1064Integer(jw1064Attribute(cell,"data-week")) else { continue }
            for item in jw1064Elements(cell,".divOneClass") { out += spanCourse(item,day,first,first+1) }
        };return out
    }
    private func sdpei()->[JwCourse] {
        guard let table=try? doc?.getElementById("tableMain") else { return [] }
        var occupied=Array(repeating:0,count:7),node=0,out:[JwCourse]=[]
        for row in jw1064Elements(table,"tr") {
            guard let th=try? row.select("th").first(),!jw1064Text(th).isEmpty else { continue };node+=1;var column=0
            for cell in row.children().array().filter({$0.tagName()=="td"}) {
                if jw1064Attribute(cell,"align").lowercased()=="center" { continue }
                while column<7 && occupied[column]>=node { column+=1 };if column>=7 { break }
                let raw=jw1064Attribute(cell,"rowspan");guard let span=jw1064Integer(raw.isEmpty ? "1":raw),span>0,node+span-1<=Int(Int32.max) else { break }
                let end=node+span-1;occupied[column]=end
                for item in jw1064Elements(cell,".divOneClass") { out += spanCourse(item,column+1,node,end) };column+=1
            }
        };return out
    }
    private func shu()->[JwCourse] {
        var out:[JwCourse]=[]
        for row in jw1064Elements(doc,"[name=rowclass]") {
            let f=row.children().array().map{jw1064Text($0)};guard f.count>=8 else { continue }
            let value=Float(f[3]) ?? 0,credit=value.isFinite && value>=0 ? value:0
            guard let regex=try? NSRegularExpression(pattern:#"([一二三四五六七日])([0-9]+-[0-9]+)"#) else { continue }
            let ns=f[6] as NSString,matches=regex.matches(in:f[6],range:NSRange(location:0,length:ns.length))
            for (index,m) in matches.enumerated() {
                let start=m.range.location+m.range.length,end=index+1<matches.count ? matches[index+1].range.location:ns.length
                var week=ns.substring(with:NSRange(location:start,length:end-start)).trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"（",with:"(").replacingOccurrences(of:"）",with:")")
                if week.hasPrefix("(") { week=String(week.dropFirst()) };if week.hasSuffix(")") { week=String(week.dropLast()) }
                let prefix=week.hasPrefix("单") ? 1:week.hasPrefix("双") ? 2:0
                out += slots(f[2],f[7],f[5],jw1064Day(ns.substring(with:m.range(at:1))),ns.substring(with:m.range(at:2)),prefix==0 ? week:String(week.dropFirst()),credit:credit,parity:prefix)
            }
        };return out
    }
    private func cqu()->[JwCourse] {
        guard source.contains("print-schedule-table") else { return [] };var out:[JwCourse]=[]
        for item in jw1064Elements(doc,".item-box") {
            guard let m=jw1064Matches(#"^([^\s]+周)\s+([^\s]+)节\s+(星期[一二三四五六七日天1-7])$"#,jw1064Text(item,".item-time")).first else { continue }
            let rawName=jw1064Text(item,".item-name"),name=rawName.contains("[") ? rawName.components(separatedBy:"[").dropLast().joined(separator:"["):rawName
            out += slots(name,jw1064Text(item,".item-location"),jw1064Text(item,".item-instr").components(separatedBy:"-")[0],jw1064Day(m[3]),m[2],m[1])
        };return out
    }
    private func jmpt()->[JwCourse] {
        let tables=jw1064Elements(doc,".admintable");guard tables.count>1 else { return [] }
        var carried=0,remaining=0,out:[JwCourse]=[]
        for row in jw1064Elements(tables[1],"tr") {
            let c=row.children().array().filter{$0.tagName()=="td"};guard !c.isEmpty else { continue };let offset:Int
            if c[0].hasAttr("rowspan") { carried=jw1064Day(jw1064Text(c[0]));remaining=jw1064Integer(jw1064Attribute(c[0],"rowspan")) ?? 0;offset=1 } else { offset=0 }
            guard remaining>0,c.count>=offset+9 else { carried=0;remaining=0;continue };remaining-=1
            let f=c.dropFirst(offset).map{jw1064Text($0)},instruction=f[8],parity=instruction.contains("双") ? (instruction.contains("不") ? 1:2):instruction.contains("单") ? (instruction.contains("不") ? 2:1):0
            out += slots(f[3],f[6],f[5],carried,"\(f[1])-\(f[2])",f[0],note:f[7],parity:parity)
        };return out
    }
    private func lngd()->[JwCourse] {
        let modern=(try? doc?.getElementById("root")) != nil,columns=jw1064Elements(doc,(try? doc?.getElementById("root")) != nil ? "#root .kbappTimetableDayColumnRoot___1DlDV":"#wdkb-kb .kbappTimetableContentContainer .kbappTimetableDayColumnRoot")
        var out:[JwCourse]=[]
        for (index,column) in columns.prefix(7).enumerated() {
            for item in jw1064Elements(column,modern ? ".kbappTimetableCourseRenderCourseItem___MgPtp":".kbappTimetableCourseRenderCourseItemContainer") {
                let details=jw1064Elements(item,modern ? ".kbappTimetableCourseRenderCourseItemInfoText___2Zmwu":".kbappTimetableCourseRenderCourseItemInfoText"),title=modern ? jw1064Text(item,".title___3o2RH"):jw1064Text(details.first)
                guard let m=jw1064Matches(#"^(.+?)\s+([0-9]+(?:\.[0-9]+)?)\s*学分?$"#,title).first ?? jw1064Matches(#"^(.+?)\s+([0-9]+(?:\.[0-9]+)?)$"#,title).first,let credit=Float(m[2]) else { continue }
                for detail in (modern ? details:Array(details.dropFirst())) {
                    let content=jw1064Text(detail);guard let nodes=jw1064Matches(#"第([0-9]+)节-第([0-9]+)节"#,content).first else { continue }
                    let week=jw1064Matches(#"[0-9]+(?:-+[0-9]+)?周"#,content).map{$0[0].replacingOccurrences(of:#"-+"#,with:"-",options:.regularExpression)}.joined(separator:","),teacher=jw1064Matches(#"周([\u4e00-\u9fa5]+)"#,content).first?[1] ?? "",fields=jw1064Split(#"\s+"#,content.trimmingCharacters(in:.whitespacesAndNewlines))
                    out += slots(m[1],fields.count>2 ? fields.last!:"",teacher,index+1,nodes[1]+"-"+nodes[2],week,credit:credit)
                }
            }
        };return out
    }
    private func vatuu()->[JwCourse] {
        guard let table=try? doc?.select(".table_border").first(),table.id() != "table3" else { return [] }
        let rows=jw1064Elements(table,"tr");guard let header=rows.first,let start=jw1064Elements(header,"td").firstIndex(where:{jw1064Text($0).contains("星期一")}) else { return [] }
        var out:[JwCourse]=[]
        for (index,row) in rows.enumerated() where index>0 {
            for (column,cell) in row.children().array().filter({$0.tagName()=="td"}).enumerated() {
                let day=column-start+1;guard (1...7).contains(day) else { continue }
                let f=lines(((try? cell.html()) ?? "").replacingOccurrences(of:"&nbsp;",with:"<br>"));guard f.count>=4 else { continue }
                for i in 0...(f.count-4) { guard let m=jw1064Matches(#"^(.*)[（(]([^()（）]*)[）)]$"#,f[i]).first else { continue };out += slots(m[1],f[i+2],m[2],day,String(index),f[i+1]) }
            }
        };return out
    }
    private func yzzy()->[JwCourse] {
        var out:[JwCourse]=[]
        for (node,row) in jw1064Elements(doc,"#timetable tr").enumerated() where (1...13).contains(node) {
            for (column,cell) in row.children().array().filter({$0.tagName()=="td"}).enumerated() { for item in jw1064Elements(cell,".kbcontent") {
                let name=jw1064Elements(item,"font").first{jw1064Attribute($0,"onmouseover").replacingOccurrences(of:#";$"#,with:"",options:.regularExpression)=="kbtc(this)"}.map{jw1064Text($0)} ?? "",raw=jw1064Text(item,"font[title=周次(节次)]")
                guard let week=jw1064Matches(#"^([^()]+)\(周\)(?:.*)$"#,raw).first?[1] else { continue }
                out += slots(name,jw1064Text(item,"font[title=教室]"),jw1064Text(item,"font[title=教师]"),column+1,String(node),week)
            } }
        };return out
    }
}
