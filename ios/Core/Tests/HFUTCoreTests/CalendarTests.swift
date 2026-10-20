import XCTest
@testable import HFUTCore

final class CalendarTests: XCTestCase {
    func testSemesterBoundariesMatchAndroid() {
        XCTAssertEqual(Semester(date: SchoolDate.parse("2026-10-20")!).id, 354)
        XCTAssertEqual(Semester(date: SchoolDate.parse("2027-01-20")!).id, 354)
        XCTAssertEqual(Semester(date: SchoolDate.parse("2027-02-20")!).id, 374)
        XCTAssertEqual(Semester(id: 354).title, "2026–2027 第一学期")
        XCTAssertEqual(Semester(id: 374).title, "2026–2027 第二学期")
    }
    func testWeekUsesShanghaiMondayAcrossSundayBoundary() {
        let start = SchoolDate.parse("2026-08-31")!
        XCTAssertEqual(SchoolDate.week(on: SchoolDate.parse("2026-09-06")!, start: start), 1)
        XCTAssertEqual(SchoolDate.week(on: SchoolDate.parse("2026-09-07")!, start: start), 2)
        XCTAssertEqual(SchoolDate.week(on: SchoolDate.parse("2026-08-30")!, start: start), 0)
    }
    func testCalendarUTCEscapingFoldingAndStableUID() {
        let name = String(repeating: "测试课程", count: 20) + ",;\n备注"
        let entry = ScheduleEntry(id: "stable-1", lessonID: 1, name: name, date: "2026-08-31", week: 1, weekday: 1, startTime: 800, endTime: 940, room: "A,201", teacher: "教师")
        let calendar = CalendarExport.render([entry], generatedAt: SchoolDate.parse("2026-08-31")!)
        XCTAssertTrue(calendar.contains("DTSTART:20260831T000000Z"))
        XCTAssertTrue(calendar.contains("DTEND:20260831T014000Z"))
        XCTAssertTrue(calendar.contains("UID:stable-1@hfut-schedule"))
        let unfolded = calendar.replacingOccurrences(of: "\r\n ", with: "")
        XCTAssertTrue(unfolded.contains("\\,\\;\\n备注"))
        for line in calendar.components(separatedBy: "\r\n") { XCTAssertLessThanOrEqual(line.utf8.count, 75) }
    }
    func testBackupRoundTripKeepsEventsButContainsNoCredentials() throws {
        var snapshot = DemoData.snapshot(now: SchoolDate.parse("2026-10-20")!)
        snapshot.events = [PersonalEvent(title: "讨论", date: Date(), location: "图书馆", note: "小组")]
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try SnapshotCodec.decode(data)
        XCTAssertEqual(decoded.schedule, snapshot.schedule)
        XCTAssertEqual(decoded.events.first?.title, "讨论")
        let text = String(decoding: data, as: UTF8.self).lowercased()
        XCTAssertFalse(text.contains("password"))
        XCTAssertFalse(text.contains("cookie"))
    }
    func testCatalogUniqueAndValidForBothCampuses() {
        XCTAssertEqual(Set(CampusService.all.map(\.id)).count, CampusService.all.count)
        for campus in Campus.allCases {
            for service in CampusService.all { XCTAssertNotNil(service.url(campus: campus).host) }
        }
    }
    func testImportRejectsDuplicateIdentitiesAndUnboundedLayout() throws {
        var snapshot = DemoData.snapshot()
        snapshot.schedule.append(snapshot.schedule[0])
        XCTAssertThrowsError(try SnapshotCodec.decode(JSONEncoder().encode(snapshot)))
        snapshot = DemoData.snapshot()
        snapshot.schedule[0].week = Int.max
        XCTAssertThrowsError(try SnapshotCodec.decode(JSONEncoder().encode(snapshot)))
        snapshot = DemoData.snapshot()
        snapshot.schemaVersion = 2
        XCTAssertThrowsError(try SnapshotCodec.decode(JSONEncoder().encode(snapshot)))
    }
    func testChainedOverlappingClassesUseStableColumns() {
        let base = DemoData.snapshot().schedule[0]
        var a = base, b = base, c = base, d = base
        a.id = "a"; a.startTime = 800; a.endTime = 900
        b.id = "b"; b.startTime = 830; b.endTime = 1000
        c.id = "c"; c.startTime = 930; c.endTime = 1100
        d.id = "d"; d.startTime = 1100; d.endTime = 1200
        let placements = ScheduleLayout.placements([c, b, d, a])
        XCTAssertEqual(placements.map(\.columnCount), [2, 2, 2, 1])
        XCTAssertEqual(placements.map(\.column), [0, 1, 0, 0])
    }
}
