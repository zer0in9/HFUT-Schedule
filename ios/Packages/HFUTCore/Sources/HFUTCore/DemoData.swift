import Foundation

public enum DemoData {
    public static func snapshot(now: Date = Date()) -> AcademicSnapshot {
        var snapshot = AcademicSnapshot(semesterID: Semester(date: now).id)
        snapshot.isDemo = true
        snapshot.profile.name = "工大同学"
        snapshot.profile.department = "计算机与信息学院（演示）"
        snapshot.profile.major = "计算机科学与技术"
        snapshot.semesterStart = SchoolDate.calendar.date(byAdding: .day, value: -35, to: SchoolDate.monday(of: now))
        snapshot.courses = [
            Course(id: 1, name: "高等数学", code: "DEMO-001", credits: 5, kind: "必修", teachers: "示例教师"),
            Course(id: 2, name: "程序设计基础", code: "DEMO-002", credits: 4, kind: "必修", teachers: "示例教师"),
            Course(id: 3, name: "大学英语", code: "DEMO-003", credits: 2, kind: "必修", teachers: "示例教师")
        ]
        let monday = SchoolDate.monday(of: now)
        for day in 0..<5 {
            let date = SchoolDate.calendar.date(byAdding: .day, value: day, to: monday)!
            for slot in 0..<2 {
                let course = snapshot.courses[(day + slot) % 3]
                snapshot.schedule.append(ScheduleEntry(id: "demo-\(day)-\(slot)", lessonID: course.id, name: course.name,
                    date: SchoolDate.string(date), week: 6, weekday: day + 1, startTime: slot == 0 ? 800 : 1400,
                    endTime: slot == 0 ? 940 : 1540, room: "示例教室 A-\(201 + day)", teacher: course.teachers))
            }
        }
        snapshot.grades = [
            Grade(id: "demo-1", term: "示例学期", name: "程序设计基础", code: "DEMO-002", credits: 4, gradePoint: 4.0, score: "92", detail: "演示成绩"),
            Grade(id: "demo-2", term: "示例学期", name: "大学英语", code: "DEMO-003", credits: 2, gradePoint: 3.5, score: "85", detail: "演示成绩")
        ]
        let examDay = SchoolDate.calendar.date(byAdding: .day, value: 14, to: now)!
        snapshot.exams = [Exam(id: "demo", name: "高等数学（演示）", dateTime: "\(SchoolDate.string(examDay)) 09:00–11:00", place: "示例教室 A-201")]
        snapshot.updatedAt = now
        return snapshot
    }
}
