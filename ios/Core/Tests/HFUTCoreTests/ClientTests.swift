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
}
