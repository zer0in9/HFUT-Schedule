import Foundation
import SwiftSoup

public enum AcademicError: LocalizedError, Equatable {
    case sessionExpired, verificationRequired, credentialsRejected, invalidResponse(String), server(Int), unavailable
    public var errorDescription: String? {
        switch self {
        case .sessionExpired: return "登录已过期，请重新登录。已缓存的数据仍可离线查看。"
        case .verificationRequired: return "学校要求验证码，请在统一认证页面完成登录。自动登录已暂停。"
        case .credentialsRejected: return "学校未接受保存的账号密码，请检查配置或在统一认证页面登录。自动登录已暂停。"
        case .invalidResponse(let part): return "无法解析\(part)，教务接口可能已变更。已保留上次数据。"
        case .server(let code): return "教务系统返回 HTTP \(code)，请稍后重试。"
        case .unavailable: return "暂时无法连接教务系统，请检查校园网或 VPN 连接。"
        }
    }
}

public struct CourseSummary: Sendable {
    public var lessonIDs: [Int]
    public var courses: [Course]
    public var semesterStart: Date?
    public init(lessonIDs: [Int], courses: [Course], semesterStart: Date?) {
        self.lessonIDs = lessonIDs; self.courses = courses; self.semesterStart = semesterStart
    }
}

public enum AcademicParser {
    private static func object(_ data: Data, part: String) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AcademicError.invalidResponse(part)
        }
        return object
    }

    private static func text(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        return Int(text(value))
    }

    private static func double(_ value: Any?) -> Double? { Double(text(value)) }
    private static func name(_ value: Any?) -> String {
        let object = value as? [String: Any] ?? [:]
        return text(object["nameZh"] ?? object["nameEn"])
    }

    private static func course(_ lesson: [String: Any]) -> Course? {
        guard let id = int(lesson["id"]), let course = lesson["course"] as? [String: Any] else { return nil }
        let assignments = lesson["teacherAssignmentList"] as? [[String: Any]] ?? []
        let teachers = assignments.map { assignment -> String in
            let teacher = assignment["teacher"] as? [String: Any]
            return name(assignment["person"] ?? teacher?["person"])
        }.filter { !$0.isEmpty }.joined(separator: "、")
        let schedule = lesson["scheduleText"] as? [String: Any]
        let detail = schedule?["dateTimePlacePersonText"] as? [String: Any]
        return Course(id: id, name: name(course), code: text(lesson["code"]), credits: double(course["credits"]), kind: name(lesson["courseType"]), teachers: teachers, arrangement: text(detail?["textZh"]))
    }

    public static func summary(_ data: Data) throws -> CourseSummary {
        let root = try object(data, part: "课程汇总")
        guard let ids = root["lessonIds"] as? [Int], let lessons = root["lessons"] as? [[String: Any]] else {
            throw AcademicError.invalidResponse("课程汇总")
        }
        let parsed = lessons.compactMap(course)
        guard parsed.count == lessons.count else { throw AcademicError.invalidResponse("课程汇总") }
        let semester = lessons.first?["semester"] as? [String: Any]
        return CourseSummary(lessonIDs: ids, courses: parsed, semesterStart: SchoolDate.parse(text(semester?["startDate"])))
    }

    public static func schedule(_ data: Data, courses: [Course]) throws -> [ScheduleEntry] {
        let root = try object(data, part: "课表")
        guard let result = root["result"] as? [String: Any],
              let rows = result["scheduleList"] as? [[String: Any]] else { throw AcademicError.invalidResponse("课表") }
        let lessonNames = Dictionary(courses.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return try rows.enumerated().map { index, row in
            guard let lessonID = int(row["lessonId"]), let week = int(row["weekIndex"]), (1...60).contains(week),
                  let weekday = int(row["weekday"]), (1...7).contains(weekday),
                  let start = int(row["startTime"]), let end = int(row["endTime"]),
                  (0...2359).contains(start), (0...2359).contains(end), start % 100 < 60, end % 100 < 60, end > start,
                  let date = row["date"] as? String, SchoolDate.parse(date) != nil else {
                throw AcademicError.invalidResponse("课表时间")
            }
            return ScheduleEntry(id: "\(lessonID)-\(date)-\(start)-\(index)", lessonID: lessonID,
                                 name: lessonNames[lessonID] ?? "课程 \(lessonID)", date: date, week: week, weekday: weekday,
                                 startTime: start, endTime: end, room: name(row["room"]), teacher: text(row["personName"]))
        }.sorted { ($0.date, $0.startTime, $0.id) < ($1.date, $1.startTime, $1.id) }
    }

    public static func studentID(from url: URL) -> Int? {
        let prefix = "/eams5-student/for-std/course-table/info/"
        guard url.host == "jxglstu.hfut.edu.cn", url.path.hasPrefix(prefix) else { return nil }
        return Int(url.path.dropFirst(prefix.count).trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    public static func businessID(_ html: String) throws -> Int {
        let expression = try NSRegularExpression(pattern: #"bizTypeId\s*:\s*(\d+)"#)
        guard let match = expression.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html), let value = Int(html[range]) else {
            throw AcademicError.invalidResponse("学生业务类型")
        }
        return value
    }

    private static func document(_ html: String) throws -> Document {
        let doc = try SwiftSoup.parse(html)
        if try !doc.select("input[name=execution], input[type=password]").isEmpty() { throw AcademicError.sessionExpired }
        return doc
    }

    public static func grades(_ html: String) throws -> [Grade] {
        let doc = try document(html)
        let tables = try doc.select("table.student-grade-table")
        guard !tables.isEmpty() else { throw AcademicError.invalidResponse("成绩单") }
        let headings = try doc.select("h3")
        var grades: [Grade] = []
        for (index, table) in tables.array().enumerated() {
            let term = index < headings.size() ? try headings.get(index).text() : "未标注学期"
            for (rowIndex, row) in try table.select("tr").array().enumerated() {
                let cells = try row.select("td")
                if cells.isEmpty() { continue }
                // Empty-state rows span all columns; incomplete data rows are a schema error.
                if cells.size() == 1, try !cells.get(0).attr("colspan").isEmpty { continue }
                guard cells.size() >= 7 else { throw AcademicError.invalidResponse("成绩行") }
                let values = try cells.array().map { try $0.text() }
                grades.append(Grade(id: "\(index)-\(rowIndex)-\(values[2])", term: term, name: values[0], code: values[2],
                                    credits: Double(values[3]), gradePoint: Double(values[4]), score: values[6], detail: values[5]))
            }
        }
        return grades
    }

    public static func exams(_ html: String) throws -> [Exam] {
        let doc = try document(html)
        guard try !doc.select("table").isEmpty() else { throw AcademicError.invalidResponse("考试安排") }
        var exams: [Exam] = []
        for (index, row) in try doc.select("tbody tr").array().enumerated() {
            let cells = try row.select("td")
            if cells.isEmpty() { continue }
            if cells.size() == 1, try !cells.get(0).attr("colspan").isEmpty { continue }
            guard cells.size() >= 3 else { throw AcademicError.invalidResponse("考试行") }
            let values = try cells.array().map { try $0.text() }
            exams.append(Exam(id: "\(index)-\(values[0])-\(values[1])", name: values[0], dateTime: values[1], place: values[2]))
        }
        return exams.sorted { $0.dateTime < $1.dateTime }
    }

    public static func profile(_ html: String) throws -> StudentProfile {
        let doc = try document(html)
        var result = StudentProfile()
        for item in try doc.select("li.list-group-item").array() {
            let value = try item.select("span").last()?.text() ?? ""
            let title = try item.text()
            if title.contains("学号") { result.number = value }
            if title.contains("中文姓名") { result.name = value }
        }
        for title in try doc.select("dl dt").array() {
            let key = try title.text()
            let value = try title.nextElementSibling()?.text() ?? ""
            if key.contains("院系") { result.department = value }
            if key == "专业" || key == "专业：" { result.major = value }
            if key.contains("班级") { result.className = value }
            if key.contains("校区") { result.campus = value }
        }
        guard !result.name.isEmpty || !result.number.isEmpty else { throw AcademicError.invalidResponse("个人信息") }
        return result
    }

    public static func program(_ data: Data) throws -> ProgramModule {
        func module(_ root: [String: Any], depth: Int) throws -> ProgramModule {
            guard depth < 30, let id = int(root["id"]), let plans = root["planCourses"] as? [[String: Any]],
                  let children = root["children"] as? [[String: Any]] else { throw AcademicError.invalidResponse("培养方案") }
            let courses = try plans.map { plan -> Course in
                guard let value = plan["course"] as? [String: Any], let id = int(value["id"]) else {
                    throw AcademicError.invalidResponse("培养方案课程")
                }
                let terms = plan["readableSuggestTerms"] as? [String] ?? []
                return Course(id: id, name: name(value), code: text(value["code"]), credits: double(value["credits"]),
                              kind: (plan["compulsory"] as? Bool == true) ? "必修" : "选修", arrangement: terms.joined(separator: "、"))
            }
            let requirement = root["requireInfo"] as? [String: Any]
            let title = name(root["type"])
            return ProgramModule(id: id, title: title.isEmpty ? "培养方案" : title, requiredCredits: double(requirement?["requiredCredits"]),
                                 courses: courses, children: try children.map { try module($0, depth: depth + 1) })
        }
        return try module(object(data, part: "培养方案"), depth: 0)
    }

    public static func searchResults(_ data: Data) throws -> [Course] {
        let root = try object(data, part: "开课查询")
        guard let rows = root["data"] as? [[String: Any]] else { throw AcademicError.invalidResponse("开课查询") }
        let result = rows.compactMap { ($0["lesson"] as? [String: Any]).flatMap(course) }
        guard result.count == rows.count else { throw AcademicError.invalidResponse("开课查询") }
        return result
    }
}
