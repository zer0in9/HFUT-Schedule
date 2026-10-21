import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AcademicSessionPolicy {
    public static func accepts(_ cookie: HTTPCookie) -> Bool {
        ["jxglstu.hfut.edu.cn", ".jxglstu.hfut.edu.cn", "cas.hfut.edu.cn", ".cas.hfut.edu.cn"].contains(cookie.domain)
    }

    public static func normalized(_ cookie: HTTPCookie) -> HTTPCookie? {
        guard accepts(cookie), var properties = cookie.properties else { return nil }
        // CAS credentials must never travel over HTTP, even when an upstream cookie omits Secure.
        if cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == "cas.hfut.edu.cn" {
            properties[.secure] = "TRUE"
            if cookie.name == "TGC" { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        }
        return HTTPCookie(properties: properties)
    }

    static func allows(_ url: URL, authentication: Bool) -> Bool {
        guard url.user == nil, url.password == nil,
              url.port == nil || url.port == (url.scheme == "https" ? 443 : 80) else { return false }
        if url.host == "jxglstu.hfut.edu.cn" { return ["http", "https"].contains(url.scheme ?? "") }
        return authentication && url.host == "cas.hfut.edu.cn" && url.scheme == "https" && url.path.hasPrefix("/cas/")
    }
}
