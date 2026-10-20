import XCTest
@testable import HFUTCore

final class ParserTests: XCTestCase {
    func fixture(_ name: String, _ ext: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")))
    }
    func testSummaryAndScheduleUseActualAndroidContract() throws {
        let summary = try AcademicParser.summary(fixture("summary", "json"))
        XCTAssertEqual(summary.lessonIDs, [71801])
        XCTAssertEqual(summary.courses.first?.credits, 4)
        XCTAssertEqual(summary.courses.first?.teachers, "示例教师")
        XCTAssertEqual(summary.semesterStart, SchoolDate.parse("2026-08-31"))
        let entries = try AcademicParser.schedule(fixture("schedule", "json"), courses: summary.courses)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.name, "程序设计基础")
        XCTAssertEqual(entries.first?.timeRange, "08:00–09:40")
        XCTAssertEqual(entries.last?.room, "")
        XCTAssertEqual(entries.first?.startDate, SchoolDate.calendar.date(bySettingHour: 8, minute: 0, second: 0, of: SchoolDate.parse("2026-08-31")!))
    }
    func testMalformedScheduleDoesNotSilentlyBecomeEmpty() throws {
        XCTAssertThrowsError(try AcademicParser.schedule(Data("{}".utf8), courses: []))
        let valid = String(data: try fixture("schedule", "json"), encoding: .utf8)!
        XCTAssertThrowsError(try AcademicParser.schedule(Data(valid.replacingOccurrences(of: "800", with: "860").utf8), courses: []))
        let empty = Data(#"{"result":{"scheduleList":[]}}"#.utf8)
        XCTAssertTrue(try AcademicParser.schedule(empty, courses: []).isEmpty)
    }
    func testGradesPreserveEntitiesAndNonNumericScores() throws {
        let grades = try AcademicParser.grades(String(decoding: fixture("grades", "html"), as: UTF8.self))
        XCTAssertEqual(grades.count, 3)
        XCTAssertEqual(grades[0].name, "程序设计 & 实践")
        XCTAssertEqual(grades[0].score, "92")
        XCTAssertEqual(grades[1].score, "良好")
        XCTAssertNil(grades[2].gradePoint)
        XCTAssertEqual(Grade.weightedGPA(grades)!, 3.8, accuracy: 0.0001)
        XCTAssertNil(Grade.weightedGPA([]))
    }
    func testLoginPageAndSchemaChangesFailInsteadOfErasingCache() {
        XCTAssertThrowsError(try AcademicParser.grades("<input type='password'>")) { XCTAssertEqual($0 as? AcademicError, .sessionExpired) }
        XCTAssertThrowsError(try AcademicParser.grades("<h1>维护中</h1>"))
        XCTAssertThrowsError(try AcademicParser.exams("<h1>维护中</h1>"))
        XCTAssertThrowsError(try AcademicParser.grades("<table class='student-grade-table'><tr><td>字段变更</td></tr></table>"))
        XCTAssertTrue(try AcademicParser.exams("<table><tbody><tr><td colspan='3'>暂无考试</td></tr></tbody></table>").isEmpty)
    }
    func testExamsSortedAndUndeterminedDatesRetained() throws {
        let exams = try AcademicParser.exams(String(decoding: fixture("exams", "html"), as: UTF8.self))
        XCTAssertEqual(exams.first?.name, "高等数学")
        XCTAssertEqual(exams.count, 2)
    }
    func testIdentityOnlyAcceptsOfficialStudentURL() throws {
        XCTAssertEqual(AcademicParser.studentID(from: URL(string: "http://jxglstu.hfut.edu.cn/eams5-student/for-std/course-table/info/170317?x=1")!), 170317)
        XCTAssertNil(AcademicParser.studentID(from: URL(string: "https://example.com/eams5-student/for-std/course-table/info/170317")!))
        XCTAssertEqual(try AcademicParser.businessID("var data = {bizTypeId : 23};"), 23)
        XCTAssertThrowsError(try AcademicParser.businessID("登录已过期"))
    }
    func testSearchUnwrapsLessonObject() throws {
        let source = try JSONSerialization.jsonObject(with: fixture("summary", "json")) as! [String: Any]
        let lessons = source["lessons"] as! [[String: Any]]
        let data = try JSONSerialization.data(withJSONObject: ["data": lessons.map { ["lesson": $0] }])
        let result = try AcademicParser.searchResults(data)
        XCTAssertEqual(result.first?.id, 71801)
        XCTAssertEqual(result.first?.name, "程序设计基础")
    }
    func testProfileOnlyCachesNeededFields() throws {
        let html = """
        <li class='list-group-item text-right'>学号<span>2026000001</span></li>
        <li class='list-group-item text-right'>中文姓名<span>测试同学</span></li>
        <li class='list-group-item text-right'>证件号<span>不应缓存</span></li>
        <dl><dt>院系</dt><dd>测试学院</dd><dt>专业</dt><dd>计算机</dd><dt>班级</dt><dd>测试班</dd></dl>
        """
        let profile = try AcademicParser.profile(html)
        XCTAssertEqual(profile.number, "2026000001")
        XCTAssertEqual(profile.major, "计算机")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(profile), as: UTF8.self).contains("不应缓存"))
    }
    func testNestedProgram() throws {
        let data = Data(#"{"id":1,"type":{"nameZh":"专业课程"},"requireInfo":{"requiredCredits":60},"planCourses":[],"children":[{"id":2,"type":{"nameZh":"必修"},"planCourses":[{"course":{"id":9,"nameZh":"编译原理","credits":3,"code":"CS9"},"compulsory":true,"readableSuggestTerms":["5"]}],"children":[]}]}"#.utf8)
        let program = try AcademicParser.program(data)
        XCTAssertEqual(program.requiredCredits, 60)
        XCTAssertEqual(program.children.first?.courses.first?.name, "编译原理")
    }
}
