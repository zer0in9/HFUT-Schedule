import SwiftUI
import Security
import HFUTCore

struct SavedBalances: Codable {
    var studentID: Int
    var credentials: [BalanceKind: BalanceCredential] = [:]
    var values: [BalanceKind: CampusBalance] = [:]
    var cardProvider: String? = "huixin"
}

@MainActor
protocol BalanceVault {
    func load() throws -> SavedBalances?
    func save(_ value: SavedBalances) throws
    func clear() throws
}

@MainActor
final class BalanceStore: ObservableObject {
    @Published private(set) var saved: SavedBalances
    @Published private(set) var loading: Set<BalanceKind> = []
    @Published private(set) var errors: [BalanceKind: String] = [:]
    private let client: any CampusBalanceServing
    private let vault: any BalanceVault
    private var revisions: [BalanceKind: Int] = [:]

    init(studentID: Int, client: any CampusBalanceServing = CampusBalanceClient(),
         vault: (any BalanceVault)? = nil, demo: Bool = false) {
        self.client = client
        let vault = vault ?? KeychainBalanceVault()
        self.vault = vault
        saved = SavedBalances(studentID: studentID)
        guard !demo else { return }
        do {
            if var cached = try vault.load(), cached.studentID == studentID {
                // Never send a previously saved portal token to the HuiXin origin.
                if cached.cardProvider != "huixin" {
                    cached.credentials[.campusCard] = nil
                    cached.values[.campusCard] = nil
                    cached.cardProvider = "huixin"
                    try vault.save(cached)
                }
                saved = cached
            }
        } catch { errors = Dictionary(uniqueKeysWithValues: BalanceKind.allCases.map { ($0, error.localizedDescription) }) }
    }

    func isConnected(_ kind: BalanceKind) -> Bool { saved.credentials[kind] != nil }

    func refresh() async {
        async let card: Void = refresh(.campusCard)
        async let shower: Void = refresh(.shower)
        _ = await (card, shower)
    }

    func refresh(_ kind: BalanceKind) async {
        guard !loading.contains(kind), let credential = saved.credentials[kind] else { return }
        let revision = revisions[kind, default: 0]
        loading.insert(kind); errors[kind] = nil
        defer { if revision == revisions[kind, default: 0] { loading.remove(kind) } }
        do {
            let value = try await client.balance(kind, credential: credential)
            guard revision == revisions[kind, default: 0], !Task.isCancelled else { return }
            saved.values[kind] = value
            persist(kind)
        } catch {
            guard revision == revisions[kind, default: 0], !Task.isCancelled else { return }
            if error as? BalanceError == .loginRequired {
                saved.credentials[kind] = nil
                persist(kind)
            }
            errors[kind] = error.localizedDescription
        }
    }

    func connectShower(account: String, password: String) async -> Bool {
        await connect(.shower) { try await self.client.loginShower(account: account, password: password) }
    }

    func connectCard(account: String, queryPassword: String) async -> Bool {
        await connect(.campusCard) { try await self.client.loginCard(account: account, queryPassword: queryPassword) }
    }

    private func connect(_ kind: BalanceKind, authorize: () async throws -> BalanceCredential) async -> Bool {
        guard !loading.contains(kind) else { return false }
        let revision = revisions[kind, default: 0]
        loading.insert(kind); errors[kind] = nil
        defer { if revision == revisions[kind, default: 0] { loading.remove(kind) } }
        do {
            let credential = try await authorize()
            guard revision == revisions[kind, default: 0], !Task.isCancelled else { return false }
            let value = try await client.balance(kind, credential: credential)
            guard revision == revisions[kind, default: 0], !Task.isCancelled else { return false }
            // Commit the new account only after a successful query; never relabel another account's cached balance.
            saved.credentials[kind] = credential
            saved.values[kind] = value
            persist(kind)
            return true
        } catch {
            guard revision == revisions[kind, default: 0], !Task.isCancelled else { return false }
            errors[kind] = error.localizedDescription
            return false
        }
    }

    func disconnect(_ kind: BalanceKind) {
        revisions[kind, default: 0] += 1
        loading.remove(kind); errors[kind] = nil
        saved.credentials[kind] = nil; saved.values[kind] = nil
        persist(kind)
    }

    func reset(studentID: Int) {
        for kind in BalanceKind.allCases { revisions[kind, default: 0] += 1 }
        loading = []; errors = [:]
        saved = SavedBalances(studentID: studentID)
        do { try vault.clear() }
        catch { errors = Dictionary(uniqueKeysWithValues: BalanceKind.allCases.map { ($0, error.localizedDescription) }) }
    }

    private func persist(_ kind: BalanceKind) {
        do { try vault.save(saved) }
        catch { errors[kind] = "保存余额和登录状态失败：\(error.localizedDescription)" }
    }
}

/// Tokens and last known balances stay on this device, outside exported academic backups.
struct KeychainBalanceVault: BalanceVault {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.hfut.schedule.ios",
         kSecAttrAccount as String: "campus-balances"]
    }
    func load() throws -> SavedBalances? {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw VaultError(status: status) }
        return try JSONDecoder().decode(SavedBalances.self, from: data)
    }
    func save(_ value: SavedBalances) throws {
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(value),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw VaultError(status: status) }
        let added = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        guard added == errSecSuccess else { throw VaultError(status: added) }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError(status: status) }
    }
    private struct VaultError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "无法访问余额登录状态（\(status)）" }
    }
}
