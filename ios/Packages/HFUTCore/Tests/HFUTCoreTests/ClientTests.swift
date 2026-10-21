import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import HFUTCore

private final class AcademicStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class ClientTests: XCTestCase {
    override func tearDown() { AcademicStub.handler = nil; super.tearDown() }
    private func client() -> AcademicClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AcademicStub.self]
        return AcademicClient(configuration: config)
    }
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
    }
    func testTimetablePostsObjectAndUsesSelectedSemester() async throws {
        let summary = try fixture("summary")
        let schedule = try fixture("schedule")
        var sawDatum = false
        AcademicStub.handler = { request in
            let url = request.url!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), AcademicClient.userAgent)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            if url.path.hasSuffix("get-data") {
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
                XCTAssertEqual(query.first { $0.name == "semesterId" }?.value, "354")
                XCTAssertEqual(query.first { $0.name == "bizTypeId" }?.value, "23")
                XCTAssertEqual(query.first { $0.name == "dataId" }?.value, "170317")
                return (response, summary)
            }
            XCTAssertTrue(url.path.hasSuffix("ws/schedule-table/datum"))
            XCTAssertEqual(request.httpMethod, "POST")
            let body: Data
            if let data = request.httpBody { body = data }
            else {
                let stream = try XCTUnwrap(request.httpBodyStream)
                stream.open(); defer { stream.close() }
                var result = Data(), buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    result.append(contentsOf: buffer.prefix(count))
                }
                body = result
            }
            let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
            XCTAssertEqual(json["studentId"] as? Int, 170317)
            XCTAssertEqual(json["lessonIds"] as? [Int], [71801])
            XCTAssertEqual(json["weekIndex"] as? String, "")
            sawDatum = true
            return (response, schedule)
        }
        let (_, entries) = try await client().timetable(studentID: 170317, businessID: 23, semesterID: 354)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(sawDatum)
    }
    func testUnauthorizedAndMaintenanceAreErrors() async throws {
        AcademicStub.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        do { _ = try await client().exams(studentID: 1); XCTFail("Expected expiration") }
        catch { XCTAssertEqual(error as? AcademicError, .sessionExpired) }
        AcademicStub.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data())
        }
        do { _ = try await client().exams(studentID: 1); XCTFail("Expected server error") }
        catch { XCTAssertEqual(error as? AcademicError, .server(503)) }
    }

    func testForbiddenPreservesSessionAsServerError() async throws {
        AcademicStub.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, Data())
        }
        do { _ = try await client().exams(studentID: 1); XCTFail("Expected access failure") }
        catch { XCTAssertEqual(error as? AcademicError, .server(403)) }
    }

    func testUntrustedRedirectNeverReceivesRequestOrCredentials() async throws {
        var count = 0
        AcademicStub.handler = { request in
            count += 1
            XCTAssertEqual(request.url?.host, "cas.hfut.edu.cn")
            return (HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil,
                headerFields: ["Location": "https://untrusted.example/collect"])!, Data())
        }
        do { try await client().renewSession(account: "synthetic", password: "synthetic-secret"); XCTFail("Followed third party") }
        catch { XCTAssertEqual(error as? AcademicError, .unavailable) }
        XCTAssertEqual(count, 1)
    }

    func testCASCaptchaStopsBeforeSendingPassword() async throws {
        var posts = 0
        AcademicStub.handler = { request in
            if request.httpMethod == "POST" { posts += 1 }
            let text = request.url!.path.hasSuffix("checkInitParams") ? #"{"vercode":true}"# : "<input name='execution' value='synthetic'>"
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(text.utf8))
        }
        do { try await client().renewSession(account: "synthetic", password: "synthetic-secret"); XCTFail("Ignored captcha") }
        catch { XCTAssertEqual(error as? AcademicError, .verificationRequired) }
        XCTAssertEqual(posts, 0)
    }

    func testCASUsesEncryptedPasswordAndDoesNotForwardPOSTToAcademicService() async throws {
        var posts = 0, academicGets = 0
        AcademicStub.handler = { request in
            let url = request.url!
            var headers: [String: String] = [:]
            let status: Int
            let text: String
            if url.host == "jxglstu.hfut.edu.cn" {
                academicGets += 1
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertNil(request.httpBody)
                status = 200; text = "<html>synthetic home</html>"
            } else if request.httpMethod == "POST" {
                posts += 1
                XCTAssertEqual(url.scheme, "https")
                var body = request.httpBody ?? Data()
                if let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var bytes = [UInt8](repeating: 0, count: 1024)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&bytes, maxLength: bytes.count)
                        if count <= 0 { break }
                        body.append(contentsOf: bytes.prefix(count))
                    }
                }
                let encoded = String(decoding: body, as: UTF8.self)
                let fields = URLComponents(string: "https://example.com/?" + encoded)!.queryItems!
                XCTAssertEqual(fields.first { $0.name == "password" }?.value, "cipher+text/=")
                XCTAssertFalse(encoded.contains("synthetic-clear-password"))
                status = 302; text = ""
                headers["Location"] = "http://jxglstu.hfut.edu.cn/eams5-student/home"
            } else {
                status = 200
                text = url.path.hasSuffix("checkInitParams") ? #"{"vercode":false}"# : "<input name='execution' value='synthetic-execution'>"
            }
            return (HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!, Data(text.utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AcademicStub.self]
        let client = AcademicClient(configuration: config, encryptPassword: { password, key in
            XCTAssertEqual(password, "synthetic-clear-password")
            XCTAssertEqual(key, "0123456789abcdef")
            return "cipher+text/="
        })
        await client.accept(cookies: [HTTPCookie(properties: [.name: "LOGIN_FLAVORING", .value: "0123456789abcdef", .domain: "cas.hfut.edu.cn", .path: "/cas/"])!])
        try await client.renewSession(account: "synthetic-student", password: "synthetic-clear-password")
        XCTAssertEqual(posts, 1)
        XCTAssertEqual(academicGets, 1)
    }

    func testSessionPolicyRejectsSchoolWideCookiesAndCASDowngrade() {
        for domain in [".hfut.edu.cn", "cas.hfut.edu.cn.evil.example"] {
            let cookie = HTTPCookie(properties: [.name: "TGC", .value: "synthetic", .domain: domain, .path: "/"])!
            XCTAssertNil(AcademicSessionPolicy.normalized(cookie))
        }
        XCTAssertFalse(AcademicSessionPolicy.allows(URL(string: "http://cas.hfut.edu.cn/cas/login")!, authentication: true))
        XCTAssertFalse(AcademicSessionPolicy.allows(URL(string: "https://cas.hfut.edu.cn:444/cas/login")!, authentication: true))
    }

    func testClearSessionRemovesBusinessAndSSOCookies() async {
        let client = client()
        await client.accept(cookies: ["cas.hfut.edu.cn", "jxglstu.hfut.edu.cn"].map {
            HTTPCookie(properties: [.name: "SESSION", .value: "synthetic", .domain: $0, .path: "/"])!
        })
        let before = await client.currentCookies()
        XCTAssertEqual(before.count, 2)
        await client.clearSession()
        let after = await client.currentCookies()
        XCTAssertTrue(after.isEmpty)
    }

    func testSSORedirectPurgesSchoolWideCookiesBeforeAcademicHop() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AcademicStub.self]
        let storage = try XCTUnwrap(config.httpCookieStorage)
        let client = AcademicClient(configuration: config)
        storage.setCookie(HTTPCookie(properties: [.name: "TGC", .value: "synthetic-wide-token", .domain: ".hfut.edu.cn", .path: "/"])!)
        AcademicStub.handler = { request in
            if request.url!.host == "cas.hfut.edu.cn" {
                return (HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil,
                    headerFields: ["Location": "http://jxglstu.hfut.edu.cn/eams5-student/home"])!, Data())
            }
            XCTAssertFalse((request.value(forHTTPHeaderField: "Cookie") ?? "").contains("synthetic-wide-token"))
            XCTAssertFalse((storage.cookies ?? []).contains { $0.domain == ".hfut.edu.cn" })
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }
        try await client.renewSession(account: nil, password: nil)
    }

    #if canImport(CommonCrypto)
    func testCASPasswordEncryptionMatchesUpstreamAESInteroperabilityVector() throws {
        // OpenSSL AES-128-ECB with PKCS7 padding, using entirely synthetic input.
        XCTAssertEqual(try CASPasswordCipher.encrypt("synthetic-password", key: "0123456789abcdef"),
                       "eH0Kl0kaihxJei4fZ+oARFJcY8w1AcZRCQ3G6HTODJs=")
    }
    #endif
}
