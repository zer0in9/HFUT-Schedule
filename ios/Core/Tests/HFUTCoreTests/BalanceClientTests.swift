import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import HFUTCore

private final class BalanceStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, json) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class BalanceClientTests: XCTestCase {
    override func tearDown() { BalanceStub.handler = nil; super.tearDown() }
    private func client() -> CampusBalanceClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BalanceStub.self]
        return CampusBalanceClient(configuration: config)
    }
    private func form(_ request: URLRequest) throws -> [String: String] {
        let data: Data
        if let body = request.httpBody { data = body }
        else {
            let stream = try XCTUnwrap(request.httpBodyStream)
            stream.open(); defer { stream.close() }
            var result = Data(), buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                result.append(contentsOf: buffer.prefix(count))
            }
            data = result
        }
        let query = try XCTUnwrap(String(data: data, encoding: .utf8))
        let items = try XCTUnwrap(URLComponents(string: "https://example.com/?\(query)")?.queryItems)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func testCardUsesHuiXinPasswordGrantAndCentsIncludingUnsettledAmount() async throws {
        BalanceStub.handler = { request in
            XCTAssertEqual(request.url?.scheme, "http")
            XCTAssertEqual(request.url?.host, "121.251.19.62")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            if request.url?.path == "/berserker-auth/oauth/token" {
                XCTAssertEqual(request.httpMethod, "POST")
                let basic = Data("mobile_service_platform:mobile_service_platform_secret".utf8).base64EncodedString()
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic \(basic)")
                let fields = try self.form(request)
                XCTAssertEqual(fields["username"], "synthetic-student")
                XCTAssertEqual(fields["password"], "a+b&c=中")
                XCTAssertEqual(fields["grant_type"], "password")
                XCTAssertEqual(fields["logintype"], "sno")
                return (200, #"{"access_token":"synthetic-card-token"}"#)
            }
            XCTAssertEqual(request.url?.path, "/berserker-app/ykt/tsm/getCampusCards")
            XCTAssertEqual(request.value(forHTTPHeaderField: "synjones-auth"), "bearer synthetic-card-token")
            return (200, #"{"code":200,"success":true,"data":{"card":[{"db_balance":12860,"unsettle_amount":-125}]}}"#)
        }
        let client = client()
        let credential = try await client.loginCard(account: "synthetic-student", queryPassword: "a+b&c=中")
        XCTAssertEqual(credential.account, "synthetic-student")
        let value = try await client.balance(.campusCard, credential: credential)
        XCTAssertEqual(value.amount, Decimal(string: "127.35"))
    }

    func testShowerUsesLoginCodeAndThousandthsWithoutAddingPromotionalCredit() async throws {
        BalanceStub.handler = { request in
            XCTAssertEqual(request.url?.host, CampusBalanceClient.showerURL.host)
            if request.url?.path == "/user/login" {
                let form = try self.form(request)
                XCTAssertEqual(form["telPhone"], "13000000000")
                XCTAssertEqual(form["password"], "a+b&c=中")
                XCTAssertEqual(form["typeId"], "0")
                return (200, #"{"message":"登录成功","data":{"loginCode":"synthetic-shower-token"}}"#)
            }
            XCTAssertEqual(request.url?.path, "/user/info")
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(items.first { $0.name == "loginCode" }?.value, "synthetic-shower-token")
            XCTAssertEqual(items.first { $0.name == "telPhone" }?.value, "13000000000")
            return (200, #"{"message":"查询成功","data":{"accountMoney":5,"accountGivenMoney":9000}}"#)
        }
        let client = client()
        let credential = try await client.loginShower(account: "13000000000", password: "a+b&c=中")
        let value = try await client.balance(.shower, credential: credential)
        XCTAssertEqual(value.amount, Decimal(string: "0.005"))
    }

    func testUnknownBalanceDoesNotBecomeZeroAndZeroIsValid() async throws {
        let credential = BalanceCredential(account: "synthetic", token: "token")
        for money in ["null", "true", #""12garbage""#, #""--""#, "{}", "1.5"] {
            BalanceStub.handler = { _ in (200, "{\"data\":{\"card\":[{\"db_balance\":\(money),\"unsettle_amount\":0}]}}") }
            do { _ = try await client().balance(.campusCard, credential: credential); XCTFail("Accepted \(money)") }
            catch { XCTAssertEqual(error as? BalanceError, .invalidResponse) }
        }
        BalanceStub.handler = { _ in (200, #"{"data":{"card":[{"db_balance":0,"unsettle_amount":0}]}}"#) }
        let zero = try await client().balance(.campusCard, credential: credential)
        XCTAssertEqual(zero.amount, 0)
    }

    func testHTTPAndBusinessFailuresRemainErrors() async throws {
        let credential = BalanceCredential(account: "synthetic", token: "token")
        for (status, json, expected) in [
            (401, "{}", BalanceError.loginRequired),
            (503, "{}", .server(503)),
            (200, #"{"code":401}"#, .loginRequired),
            (200, #"{"success":false,"data":{"card":[{"db_balance":0,"unsettle_amount":0}]}}"#, .rejected),
            (200, #"{"data":{"card":[]}}"#, .invalidResponse),
            (200, "<html>login</html>", .invalidResponse)
        ] {
            BalanceStub.handler = { _ in (status, json) }
            do { _ = try await client().balance(.campusCard, credential: credential); XCTFail("Expected \(expected)") }
            catch { XCTAssertEqual(error as? BalanceError, expected) }
        }
    }

    func testRejectedCardLoginIsNotRetried() async throws {
        var count = 0
        BalanceStub.handler = { request in
            count += 1
            return (200, #"{"error":"invalid_grant","error_description":"synthetic rejection"}"#)
        }
        do { _ = try await client().loginCard(account: "synthetic", queryPassword: "synthetic"); XCTFail("Accepted rejected login") }
        catch { XCTAssertEqual(error as? BalanceError, .rejected) }
        XCTAssertEqual(count, 1)
    }
}
