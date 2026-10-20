import Foundation
import Security

struct SavedAcademicSession: Codable {
    struct Cookie: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let secure: Bool
        let expires: Date?
        init(_ cookie: HTTPCookie) {
            name = cookie.name; value = cookie.value; domain = cookie.domain; path = cookie.path
            secure = cookie.isSecure; expires = cookie.expiresDate
        }
        func restored(at now: Date) -> HTTPCookie? {
            guard domain == "jxglstu.hfut.edu.cn" || domain == ".jxglstu.hfut.edu.cn",
                  expires.map({ $0 > now }) ?? true else { return nil }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: value, .domain: domain, .path: path
            ]
            if secure { properties[.secure] = "TRUE" }
            if let expires { properties[.expires] = expires }
            return HTTPCookie(properties: properties)
        }
    }
    let studentID: Int
    let savedAt: Date
    let cookies: [Cookie]
    init(studentID: Int, cookies: [HTTPCookie], now: Date = Date()) {
        self.studentID = studentID; savedAt = now
        self.cookies = cookies.filter { $0.domain == "jxglstu.hfut.edu.cn" || $0.domain == ".jxglstu.hfut.edu.cn" }.map(Cookie.init)
    }
    func restoredCookies(studentID: Int, now: Date = Date()) -> [HTTPCookie] {
        // Upstream academic sessions last about three hours; don't revive stale session cookies.
        guard self.studentID > 0, self.studentID == studentID, now >= savedAt, now.timeIntervalSince(savedAt) < 3 * 60 * 60 else { return [] }
        return cookies.compactMap { $0.restored(at: now) }
    }
}

@MainActor
protocol SessionVault {
    func load() throws -> SavedAcademicSession?
    func save(_ session: SavedAcademicSession) throws
    func clear() throws
}

struct KeychainSessionVault: SessionVault {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.hfut.schedule.ios",
         kSecAttrAccount as String: "academic-session"]
    }
    func load() throws -> SavedAcademicSession? {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw VaultError(status: status) }
        return try JSONDecoder().decode(SavedAcademicSession.self, from: data)
    }
    func save(_ session: SavedAcademicSession) throws {
        let data = try JSONEncoder().encode(session)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw VaultError(status: update) }
        let status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError(status: status) }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError(status: status) }
    }
    private struct VaultError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "无法访问登录会话（\(status)）" }
    }
}
