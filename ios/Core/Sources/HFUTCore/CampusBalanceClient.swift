import Foundation
import CoreFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum BalanceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case campusCard, shower
    public var id: String { rawValue }
    public var title: String { self == .campusCard ? "校园卡余额" : "浴室水费余额" }
    public var symbol: String { self == .campusCard ? "creditcard.fill" : "drop.fill" }
}

public struct BalanceCredential: Codable, Sendable {
    public let account: String
    public let token: String
    public init(account: String, token: String) { self.account = account; self.token = token }
}

public struct CampusBalance: Codable, Sendable {
    public let amount: Decimal
    public let updatedAt: Date
    public init(amount: Decimal, updatedAt: Date = Date()) { self.amount = amount; self.updatedAt = updatedAt }
    public var formatted: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "—"
    }
}

public protocol CampusBalanceServing: Sendable {
    /// The shower service expects the final ten uppercase hex digits of an MD5 password hash.
    func loginShower(account: String, password: String) async throws -> BalanceCredential
    func loginCard(account: String, queryPassword: String) async throws -> BalanceCredential
    func balance(_ kind: BalanceKind, credential: BalanceCredential) async throws -> CampusBalance
}

public enum BalanceError: LocalizedError, Equatable {
    case loginRequired, rejected, invalidResponse, server(Int)
    public var errorDescription: String? {
        switch self {
        case .loginRequired: "登录已过期，请重新连接账号。"
        case .rejected: "查询未成功，请检查账号、密码及服务状态。"
        case .invalidResponse: "暂时无法读取余额，请稍后重试。"
        case .server(let code): "余额服务暂时不可用（\(code)）。"
        }
    }
}

/// Contracts mirror HuiXinService/GuaGuaService and their response models in network-api.
public actor CampusBalanceClient: CampusBalanceServing {
    public static let cardURL = URL(string: "http://121.251.19.62/")!
    public static let showerURL = URL(string: "https://bathing.hfut.edu.cn/")!
    private let session: URLSession
    private let redirects = BalanceRedirectDelegate()

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration, delegate: redirects, delegateQueue: nil)
    }

    private func request(_ kind: BalanceKind, path: String, query: [URLQueryItem] = [],
                         form: [URLQueryItem]? = nil, authorization: (String, String)? = nil) async throws -> [String: Any] {
        let base = kind == .campusCard ? Self.cardURL : Self.showerURL
        var url = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { url.queryItems = query }
        var request = URLRequest(url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authorization { request.setValue(authorization.1, forHTTPHeaderField: authorization.0) }
        if let form {
            var body = URLComponents()
            body.queryItems = form
            request.httpMethod = "POST"
            // '+' must be encoded in application/x-www-form-urlencoded values.
            request.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw BalanceError.invalidResponse }
        if [301, 302, 303, 307, 308, 401, 403].contains(response.statusCode) { throw BalanceError.loginRequired }
        guard (200...299).contains(response.statusCode) else { throw BalanceError.server(response.statusCode) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BalanceError.invalidResponse }
        let code = String(describing: json["code"] ?? json["status"] ?? "")
        if ["401", "403", "-401"].contains(code) || json["error"] as? String == "invalid_token" { throw BalanceError.loginRequired }
        if json["success"] as? Bool == false || json["error"] != nil { throw BalanceError.rejected }
        return json
    }

    public func loginShower(account: String, password: String) async throws -> BalanceCredential {
        let json = try await request(.shower, path: "user/login", form: [
            .init(name: "telPhone", value: account), .init(name: "password", value: password), .init(name: "typeId", value: "0")
        ])
        guard (json["message"] as? String)?.contains("成功") == true,
              let token = (json["data"] as? [String: Any])?["loginCode"] as? String,
              !token.isEmpty else { throw BalanceError.rejected }
        return BalanceCredential(account: account, token: token)
    }

    public func loginCard(account: String, queryPassword: String) async throws -> BalanceCredential {
        let basic = Data("mobile_service_platform:mobile_service_platform_secret".utf8).base64EncodedString()
        let json = try await request(.campusCard, path: "berserker-auth/oauth/token", form: [
            .init(name: "username", value: account), .init(name: "password", value: queryPassword),
            .init(name: "grant_type", value: "password"), .init(name: "logintype", value: "sno")
        ], authorization: ("Authorization", "Basic \(basic)"))
        guard let token = json["access_token"] as? String, !token.isEmpty else { throw BalanceError.rejected }
        return BalanceCredential(account: account, token: token)
    }

    public func balance(_ kind: BalanceKind, credential: BalanceCredential) async throws -> CampusBalance {
        let json: [String: Any]
        let amount: Decimal
        if kind == .campusCard {
            json = try await request(kind, path: "berserker-app/ykt/tsm/getCampusCards",
                                     authorization: ("synjones-auth", "bearer \(credential.token)"))
            guard let data = json["data"] as? [String: Any], let cards = data["card"] as? [[String: Any]],
                  let card = cards.first else { throw BalanceError.invalidResponse }
            // Match Android: settled and unsettled balances are signed integer cents.
            amount = try (integerMoney(card["db_balance"]) + integerMoney(card["unsettle_amount"])) / 100
        } else {
            json = try await request(kind, path: "user/info", query: [
                .init(name: "telPhone", value: credential.account), .init(name: "loginCode", value: credential.token)
            ])
            guard (json["message"] as? String)?.contains("成功") == true else { throw BalanceError.loginRequired }
            guard let data = json["data"] as? [String: Any] else { throw BalanceError.invalidResponse }
            // GuaGua accountMoney is in thousandths of a yuan; promotional credit is separate.
            amount = try integerMoney(data["accountMoney"]) / 1000
        }
        return CampusBalance(amount: amount)
    }

    private func integerMoney(_ value: Any?) throws -> Decimal {
        if let numeric = value as? NSNumber, CFGetTypeID(numeric) == CFBooleanGetTypeID() {
            throw BalanceError.invalidResponse
        }
        guard let value, !(value is NSNull),
              String(describing: value).range(of: "^-?[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
              let number = Decimal(string: String(describing: value), locale: Locale(identifier: "en_US_POSIX")),
              !number.isNaN, number >= -1_000_000_000, number <= 1_000_000_000 else {
            throw BalanceError.invalidResponse
        }
        var source = number, rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .plain)
        guard rounded == number else { throw BalanceError.invalidResponse }
        return number
    }
}

private final class BalanceRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // These JSON endpoints do not redirect. In particular, never forward credentials to a login page.
        completionHandler(nil)
    }
}
