import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol AcademicServing: Sendable {
    func accept(cookies: [HTTPCookie]) async
    func currentCookies() async -> [HTTPCookie]
    func clearSession() async
    func identity() async throws -> (studentID: Int, businessID: Int)
    func timetable(studentID: Int, businessID: Int, semesterID: Int) async throws -> (CourseSummary, [ScheduleEntry])
    func grades(studentID: Int) async throws -> [Grade]
    func exams(studentID: Int) async throws -> [Exam]
    func profile(studentID: Int) async throws -> StudentProfile
    func program(studentID: Int) async throws -> ProgramModule
    func search(studentID: Int, semesterID: Int, name: String, page: Int) async throws -> [Course]
}
