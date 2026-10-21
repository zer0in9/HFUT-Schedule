import Foundation
import SwiftSoup
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Networking stays ephemeral; the app stores a validated session separately in the device keychain.
public actor AcademicClient: AcademicServing {
    public static let baseURL = URL(string: "http://jxglstu.hfut.edu.cn/eams5-student/")!
    public static let loginURL: URL = {
        var components = URLComponents(string: "https://cas.hfut.edu.cn/cas/login")!
        components.queryItems = [URLQueryItem(name: "service", value: baseURL.appendingPathComponent("neusoft-sso/login").absoluteString)]
        return components.url!
    }()
    public static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1"
    private var session: URLSession
    private let configuration: URLSessionConfiguration
    private var generation = 0
    private let redirectDelegate: AcademicRedirectDelegate
    private let encryptPassword: @Sendable (String, String) throws -> String

    public init(configuration config: URLSessionConfiguration = .ephemeral,
                encryptPassword: (@Sendable (String, String) throws -> String)? = nil) {
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 90
        config.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        config.urlCache = nil
        self.encryptPassword = encryptPassword ?? { try CASPasswordCipher.encrypt($0, key: $1) }
        configuration = config
        let delegate = AcademicRedirectDelegate()
        redirectDelegate = delegate
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    public func accept(cookies: [HTTPCookie]) {
        for cookie in cookies {
            if let cookie = AcademicSessionPolicy.normalized(cookie) { session.configuration.httpCookieStorage?.setCookie(cookie) }
        }
    }

    public func clearSession() {
        generation += 1
        let previous = session
        let config = configuration.copy() as! URLSessionConfiguration
        config.httpCookieStorage = URLSessionConfiguration.ephemeral.httpCookieStorage
        session = URLSession(configuration: config, delegate: redirectDelegate, delegateQueue: nil)
        previous.invalidateAndCancel()
        previous.configuration.httpCookieStorage?.removeCookies(since: .distantPast)
    }

    public func currentCookies() -> [HTTPCookie] {
        (session.configuration.httpCookieStorage?.cookies ?? []).compactMap(AcademicSessionPolicy.normalized)
    }

    /// Explicit, bounded SSO flow; never replays a POST body across a redirect.
    private func exchange(_ original: URLRequest, authentication: Bool = false, expectedGeneration: Int? = nil) async throws -> (Data, HTTPURLResponse) {
        let epoch = expectedGeneration ?? generation
        let transport = session
        var request = original
        for _ in 0..<8 {
            guard epoch == generation else { throw CancellationError() }
            try Task.checkCancellation()
            guard let url = request.url, AcademicSessionPolicy.allows(url, authentication: authentication) else {
                throw AcademicError.unavailable
            }
            let (data, response) = try await transport.data(for: request)
            guard epoch == generation else { throw CancellationError() }
            guard let response = response as? HTTPURLResponse else { throw AcademicError.unavailable }
            // Normalize CAS cookies before any subsequent request, including upstream cookies lacking Secure.
            if let storage = transport.configuration.httpCookieStorage {
                for cookie in storage.cookies ?? [] {
                    if let normalized = AcademicSessionPolicy.normalized(cookie) { storage.setCookie(normalized) }
                    else { storage.deleteCookie(cookie) }
                }
            }
            guard (300...399).contains(response.statusCode) else { return (data, response) }
            guard let location = response.value(forHTTPHeaderField: "Location"),
                  let next = URL(string: location, relativeTo: url)?.absoluteURL else { throw AcademicError.server(response.statusCode) }
            guard AcademicSessionPolicy.allows(next, authentication: authentication) else {
                if next.host == "cas.hfut.edu.cn", next.scheme == "https" { throw AcademicError.sessionExpired }
                throw AcademicError.unavailable
            }
            guard request.httpMethod == "GET" || [301, 302, 303].contains(response.statusCode) else { throw AcademicError.unavailable }
            request = URLRequest(url: next, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        }
        throw AcademicError.unavailable
    }

    public func renewSession(account: String?, password: String?) async throws {
        let epoch = generation
        let login = URLRequest(url: Self.loginURL, cachePolicy: .reloadIgnoringLocalCacheData)
        let (initial, initialResponse) = try await exchange(login, authentication: true, expectedGeneration: epoch)
        if initialResponse.url?.host == Self.baseURL.host, initialResponse.statusCode == 200,
           initialResponse.url?.path.contains("/login") == false { return }
        guard initialResponse.statusCode == 200 else { throw AcademicError.server(initialResponse.statusCode) }
        guard let account, let password, !account.isEmpty, !password.isEmpty else { throw AcademicError.sessionExpired }
        let keyURL = URL(string: "https://cas.hfut.edu.cn/cas/checkInitParams")!
        let (parameters, response) = try await exchange(URLRequest(url: keyURL, cachePolicy: .reloadIgnoringLocalCacheData), authentication: true, expectedGeneration: epoch)
        guard response.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: parameters) as? [String: Any],
              let needCaptcha = json["vercode"] as? Bool else { throw AcademicError.invalidResponse("认证参数") }
        guard !needCaptcha else { throw AcademicError.verificationRequired }
        guard let key = session.configuration.httpCookieStorage?.cookies(for: keyURL)?.first(where: { $0.name == "LOGIN_FLAVORING" })?.value else {
            throw AcademicError.invalidResponse("认证密钥")
        }
        let document = try SwiftSoup.parse(String(decoding: initial, as: UTF8.self))
        guard let execution = try document.select("input[name=execution]").first()?.val(), !execution.isEmpty else {
            throw AcademicError.invalidResponse("认证页面")
        }
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "username", value: account),
                           URLQueryItem(name: "password", value: try encryptPassword(password, key)),
                           URLQueryItem(name: "execution", value: execution),
                           URLQueryItem(name: "_eventId", value: "submit"), URLQueryItem(name: "capcha", value: "")]
        var post = login
        post.httpMethod = "POST"
        post.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        post.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (_, result) = try await exchange(post, authentication: true, expectedGeneration: epoch)
        if result.statusCode == 401 { throw AcademicError.credentialsRejected }
        guard (200...299).contains(result.statusCode) else { throw AcademicError.server(result.statusCode) }
        guard result.url?.host == Self.baseURL.host, result.url?.path.contains("/login") == false else {
            throw AcademicError.credentialsRejected
        }
    }

    private func request(_ path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> (Data, URL) {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await exchange(request)
        guard let url = response.url else { throw AcademicError.unavailable }
        if response.statusCode == 401 {
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
        // All redirects are validated and reconstructed explicitly by exchange().
        completionHandler(nil)
    }
}
