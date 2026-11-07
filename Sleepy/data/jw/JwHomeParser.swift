// 仅登记已收录的教务入口；真正解析由 JwParseDispatch 自动识别。
final class JwHomeParser: JwParser {
    let source: String
    init(_ source: String) { self.source = source }
    func generateCourseList() throws -> [JwCourse] { [] }
}
