import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Cookies live only in this ephemeral session. No password or token is written to the snapshot.
public actor AcademicClient {
    public static let baseURL = URL(string: "http://jxglstu.hfut.edu.cn/eams5-student/")!
    public static let loginURL: URL = {
        var components = URLComponents(string: "https://cas.hfut.edu.cn/cas/login")!
        components.queryItems = [URLQueryItem(name: "service", value: baseURL.appendingPathComponent("neusoft-sso/login").absoluteString)]
        return components.url!
    }()
    public static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1"
    private let session: URLSession
    private let redirectDelegate: AcademicRedirectDelegate

    public init(configuration config: URLSessionConfiguration = .ephemeral) {
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 90
        config.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        let delegate = AcademicRedirectDelegate()
        redirectDelegate = delegate
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    public func accept(cookies: [HTTPCookie]) {
        for cookie in cookies where cookie.domain == "jxglstu.hfut.edu.cn" || cookie.domain == ".jxglstu.hfut.edu.cn" {
            session.configuration.httpCookieStorage?.setCookie(cookie)
        }
    }

    public func clearSession() {
        session.configuration.httpCookieStorage?.removeCookies(since: .distantPast)
        session.reset(completionHandler: {})
    }

    private func request(_ path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> (Data, URL) {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, let url = response.url else { throw AcademicError.unavailable }
        if (300...399).contains(response.statusCode) || response.statusCode == 401 || response.statusCode == 403 {
            throw AcademicError.sessionExpired
        }
        guard (200...299).contains(response.statusCode) else { throw AcademicError.server(response.statusCode) }
        if url.path.contains("/login") || url.host != Self.baseURL.host { throw AcademicError.sessionExpired }
        if let html = String(data: data, encoding: .utf8),
           html.contains("name=\"execution\"") || html.contains("name=\"password\"") { throw AcademicError.sessionExpired }
        return (data, url)
    }

    private func html(_ path: String) async throws -> String {
        let (data, _) = try await request(path)
        guard let text = String(data: data, encoding: .utf8) else { throw AcademicError.invalidResponse("网页编码") }
        return text
    }

    public func identity() async throws -> (studentID: Int, businessID: Int) {
        let (_, finalURL) = try await request("for-std/course-table")
        guard let studentID = AcademicParser.studentID(from: finalURL) else { throw AcademicError.invalidResponse("学生 ID") }
        let businessID = try AcademicParser.businessID(await html("for-std/course-table/info/\(studentID)"))
        return (studentID, businessID)
    }

    public func timetable(studentID: Int, businessID: Int, semesterID: Int) async throws -> (CourseSummary, [ScheduleEntry]) {
        let (data, _) = try await request("for-std/course-table/get-data", query: [
            URLQueryItem(name: "bizTypeId", value: String(businessID)),
            URLQueryItem(name: "semesterId", value: String(semesterID)),
            URLQueryItem(name: "dataId", value: String(studentID))
        ])
        let summary = try AcademicParser.summary(data)
        if summary.lessonIDs.isEmpty { return (summary, []) }
        let body = try JSONSerialization.data(withJSONObject: ["lessonIds": summary.lessonIDs, "studentId": studentID, "weekIndex": ""])
        let (scheduleData, _) = try await request("ws/schedule-table/datum", body: body)
        return (summary, try AcademicParser.schedule(scheduleData, courses: summary.courses))
    }

    public func grades(studentID: Int) async throws -> [Grade] {
        try AcademicParser.grades(await html("for-std/grade/sheet/info/\(studentID)"))
    }
    public func exams(studentID: Int) async throws -> [Exam] {
        try AcademicParser.exams(await html("for-std/exam-arrange/info/\(studentID)"))
    }
    public func profile(studentID: Int) async throws -> StudentProfile {
        try AcademicParser.profile(await html("for-std/student-info/info/\(studentID)"))
    }
    public func program(studentID: Int) async throws -> ProgramModule {
        let (data, _) = try await request("for-std/program/root-module-json/\(studentID)")
        return try AcademicParser.program(data)
    }
    public func search(studentID: Int, semesterID: Int, name: String, page: Int) async throws -> [Course] {
        let (data, _) = try await request("for-std/lesson-search/semester/\(semesterID)/search/\(studentID)", query: [
            URLQueryItem(name: "courseNameZhLike", value: name), URLQueryItem(name: "queryPage__", value: "\(page)")
        ])
        return try AcademicParser.searchResults(data)
    }
}

private final class AcademicRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward an academic request (including cookies/body) to CAS or a third party.
        completionHandler(request.url?.host == AcademicClient.baseURL.host ? request : nil)
    }
}
