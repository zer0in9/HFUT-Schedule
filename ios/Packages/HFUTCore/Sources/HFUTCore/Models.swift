import Foundation

public enum Campus: String, Codable, CaseIterable, Identifiable, Sendable {
    case hefei = "合肥", xuancheng = "宣城"
    public var id: String { rawValue }
}

public enum SchoolDate {
    // DateFormatter supports concurrent reads. Configure once and never mutate after publication.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()

    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    public static func parse(_ text: String) -> Date? {
        dayFormatter.date(from: text)
    }

    public static func string(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    public static func monday(of date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day)!
    }

    public static func week(on date: Date, start: Date) -> Int {
        let days = calendar.dateComponents([.day], from: monday(of: start), to: calendar.startOfDay(for: date)).day ?? 0
        return Int(floor(Double(days) / 7)) + 1
    }

    public static func time(_ value: Int) -> String { String(format: "%02d:%02d", value / 100, value % 100) }
}

public struct Semester: Equatable, Sendable {
    public let id: Int
    public init(id: Int) { self.id = id }
    public init(date: Date) {
        let year = SchoolDate.calendar.component(.year, from: date)
        let month = SchoolDate.calendar.component(.month, from: date)
        let startYear = month <= 7 ? year - 1 : year
        id = ((startYear - 2018) * 4 + 3) * 10 + 4 + ((2...7).contains(month) ? 20 : 0)
    }
    public var title: String {
        let code = (id - 4) / 10
        let year = 2018 + (code - 3) / 4
        return "\(year)–\(year + 1) 第\(code % 4 == 3 ? "一" : "二")学期"
    }
}

public struct Course: Codable, Identifiable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var code: String
    public var credits: Double?
    public var kind: String
    public var teachers: String
    public var arrangement: String
    public init(id: Int, name: String, code: String = "", credits: Double? = nil, kind: String = "", teachers: String = "", arrangement: String = "") {
        self.id = id; self.name = name; self.code = code; self.credits = credits
        self.kind = kind; self.teachers = teachers; self.arrangement = arrangement
    }
}

public struct ScheduleEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var lessonID: Int
    public var name: String
    public var date: String
    public var week: Int
    public var weekday: Int
    public var startTime: Int
    public var endTime: Int
    public var room: String
    public var teacher: String
    public init(id: String, lessonID: Int, name: String, date: String, week: Int, weekday: Int, startTime: Int, endTime: Int, room: String, teacher: String) {
        self.id = id; self.lessonID = lessonID; self.name = name; self.date = date
        self.week = week; self.weekday = weekday; self.startTime = startTime; self.endTime = endTime
        self.room = room; self.teacher = teacher
    }
    public var timeRange: String { "\(SchoolDate.time(startTime))–\(SchoolDate.time(endTime))" }
    public var startDate: Date? { dateAt(time: startTime) }
    public var endDate: Date? { dateAt(time: endTime) }
    private func dateAt(time: Int) -> Date? {
        guard let day = SchoolDate.parse(date) else { return nil }
        return SchoolDate.calendar.date(bySettingHour: time / 100, minute: time % 100, second: 0, of: day)
    }
}

public struct Grade: Codable, Identifiable, Sendable {
    public var id: String
    public var term: String
    public var name: String
    public var code: String
    public var credits: Double?
    public var gradePoint: Double?
    public var score: String
    public var detail: String
    public init(id: String, term: String, name: String, code: String, credits: Double?, gradePoint: Double?, score: String, detail: String) {
        self.id = id; self.term = term; self.name = name; self.code = code; self.credits = credits
        self.gradePoint = gradePoint; self.score = score; self.detail = detail
    }
    public static func weightedGPA(_ grades: [Grade]) -> Double? {
        let eligible = grades.filter { ($0.credits ?? 0) > 0 && $0.gradePoint != nil }
        let credits = eligible.reduce(0) { $0 + ($1.credits ?? 0) }
        guard credits > 0 else { return nil }
        return eligible.reduce(0) { $0 + ($1.credits ?? 0) * ($1.gradePoint ?? 0) } / credits
    }
}

public struct Exam: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var dateTime: String
    public var place: String
    public init(id: String, name: String, dateTime: String, place: String) {
        self.id = id; self.name = name; self.dateTime = dateTime; self.place = place
    }
}

public struct StudentProfile: Codable, Sendable {
    public var number: String = ""
    public var name: String = ""
    public var department: String = ""
    public var major: String = ""
    public var className: String = ""
    public var campus: String = ""
    public init() {}
}

public struct PersonalEvent: Codable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var date: Date
    public var location: String
    public var note: String
    public init(id: UUID = UUID(), title: String, date: Date, location: String, note: String) {
        self.id = id; self.title = title; self.date = date; self.location = location; self.note = note
    }
}

public struct ProgramModule: Codable, Identifiable, Sendable {
    public var id: Int
    public var title: String
    public var requiredCredits: Double?
    public var courses: [Course]
    public var children: [ProgramModule]
    public init(id: Int, title: String, requiredCredits: Double?, courses: [Course], children: [ProgramModule]) {
        self.id = id; self.title = title; self.requiredCredits = requiredCredits; self.courses = courses; self.children = children
    }
}

public struct AcademicSnapshot: Codable, Sendable {
    public var schemaVersion = 1
    public var semesterID: Int
    public var studentID: Int
    public var profile = StudentProfile()
    public var semesterStart: Date?
    public var courses: [Course] = []
    public var schedule: [ScheduleEntry] = []
    public var grades: [Grade] = []
    public var exams: [Exam] = []
    public var program: ProgramModule?
    public var events: [PersonalEvent] = []
    public var updatedAt: Date?
    public var isDemo = false
    public init(semesterID: Int, studentID: Int = 0) { self.semesterID = semesterID; self.studentID = studentID }
}
