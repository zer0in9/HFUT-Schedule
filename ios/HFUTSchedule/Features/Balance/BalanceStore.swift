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
    @Published private(set) var restorationError: String?
    private let client: any CampusBalanceServing
    private let vault: any BalanceVault
    private let accounts: AccountStore?
    private var revisions: [BalanceKind: Int] = [:]
    private var tasks: [BalanceKind: Task<SyncOutcome, Never>] = [:]

    init(studentID: Int, client: any CampusBalanceServing = CampusBalanceClient(),
         vault: (any BalanceVault)? = nil, demo: Bool = false, accounts: AccountStore? = nil) {
        self.client = client
        self.accounts = accounts
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
        } catch {
            restorationError = error.localizedDescription
            errors = Dictionary(uniqueKeysWithValues: BalanceKind.allCases.map { ($0, error.localizedDescription) })
        }
    }

    func isConnected(_ kind: BalanceKind) -> Bool { saved.credentials[kind] != nil }

    func canRefresh(_ kind: BalanceKind) -> Bool {
        tasks[kind] != nil || saved.credentials[kind] != nil || accounts?.summaries[AccountSystem(kind)] != nil
    }

    func refresh() async {
        async let card = refresh(.campusCard)
        async let shower = refresh(.shower)
        _ = await (card, shower)
    }

    @discardableResult
    func refresh(_ kind: BalanceKind) async -> SyncOutcome {
        if let task = tasks[kind] { return await task.value }
        guard canRefresh(kind) else { return .skipped }
        let revision = revisions[kind, default: 0]
        let task = Task { await self.performRefresh(kind) }
        tasks[kind] = task
        let result = await task.value
        if revision == revisions[kind, default: 0] { tasks[kind] = nil }
        return result
    }

    private func performRefresh(_ kind: BalanceKind) async -> SyncOutcome {
        guard !Task.isCancelled else { return .skipped }
        let revision = revisions[kind, default: 0]
        loading.insert(kind); errors[kind] = nil
        defer { if revision == revisions[kind, default: 0] { loading.remove(kind) } }
        do {
            var credential = saved.credentials[kind]
            var value: CampusBalance?
            if let credential {
                do { value = try await client.balance(kind, credential: credential) }
                catch BalanceError.loginRequired { /* Renew once below, using this service's own password. */ }
            }
            guard revision == revisions[kind, default: 0], !Task.isCancelled else { return .skipped }
            if value == nil {
                guard let account = try accounts?.credential(AccountSystem(kind)) else {
                    throw BalanceError.loginRequired
                }
                guard accounts?.studentID == saved.studentID,
                      credential == nil || credential?.account == account.account else { throw BalanceError.loginRequired }
                do {
                    if kind == .campusCard {
                        credential = try await client.loginCard(account: account.account, queryPassword: account.password)
                    } else {
                        credential = try await client.loginShower(account: account.account, password: AccountStore.showerProof(account.password))
                    }
                } catch {
                    guard revision == revisions[kind, default: 0], !Task.isCancelled else { return .skipped }
                    if error as? BalanceError == .rejected || error as? BalanceError == .loginRequired {
                        try accounts?.pause(AccountSystem(kind))
                    }
                    throw error
                }
                guard revision == revisions[kind, default: 0], !Task.isCancelled, let renewed = credential else { return .skipped }
                // Preserve the new token even if the following balance query encounters a network failure.
                saved.credentials[kind] = renewed
                persist(kind)
                do { value = try await client.balance(kind, credential: renewed) }
                catch BalanceError.loginRequired {
                    guard revision == revisions[kind, default: 0], !Task.isCancelled else { return .skipped }
                    try accounts?.pause(AccountSystem(kind)); throw BalanceError.loginRequired
                }
            }
            guard revision == revisions[kind, default: 0], !Task.isCancelled else { return .skipped }
            saved.values[kind] = value
            persist(kind)
            if let error = errors[kind] { return .failure(message: error) }
            return .success
        } catch {
            guard revision == revisions[kind, default: 0], !Task.isCancelled else { return .skipped }
            if error as? BalanceError == .loginRequired {
                saved.credentials[kind] = nil
                persist(kind)
            }
            errors[kind] = error.localizedDescription
            return .failure(message: error.localizedDescription,
                            requiresLogin: error as? BalanceError == .loginRequired || error as? BalanceError == .rejected)
        }
    }

    func connectShower(account: String, password: String) async -> Bool {
        await connect(.shower, proof: password) { try await self.client.loginShower(account: account, password: password) }
    }

    func connectCard(account: String, queryPassword: String) async -> Bool {
        await connect(.campusCard, proof: queryPassword) { try await self.client.loginCard(account: account, queryPassword: queryPassword) }
    }

    private func connect(_ kind: BalanceKind, proof: String, authorize: @escaping () async throws -> BalanceCredential) async -> Bool {
        guard tasks[kind] == nil, !loading.contains(kind) else { return false }
        let revision = revisions[kind, default: 0]
        let task = Task { await self.performConnect(kind, proof: proof, authorize: authorize) }
        tasks[kind] = task
        let result = await task.value
        if revision == revisions[kind, default: 0] { tasks[kind] = nil }
        return result == .success
    }

    private func performConnect(_ kind: BalanceKind, proof: String, authorize: () async throws -> BalanceCredential) async -> SyncOutcome {
        guard !Task.isCancelled else { return .skipped }
        let revision = revisions[kind, default: 0]
        loading.insert(kind); errors[kind] = nil
        defer { if revision == revisions[kind, default: 0] { loading.remove(kind) } }
        do {
            let credential = try await authorize()
            guard revision == revisions[kind, default: 0], !Task.isCancelled else { return .skipped }
            let value = try await client.balance(kind, credential: credential)
            guard revision == revisions[kind, default: 0], !Task.isCancelled else { return .skipped }
            // Commit the new account only after a successful query; never relabel another account's cached balance.
            let system = AccountSystem(kind)
            if let stored = try accounts?.credential(system, forAutomaticLogin: false) {
                if stored.account != credential.account { try accounts?.remove(system) }
                else if (kind == .shower ? AccountStore.showerProof(stored.password) : stored.password) != proof {
                    try accounts?.pause(system)
                }
            }
            saved.credentials[kind] = credential
            saved.values[kind] = value
            persist(kind)
            if let error = errors[kind] { return .failure(message: error) }
            return .success
        } catch {
            guard revision == revisions[kind, default: 0], !Task.isCancelled else { return .skipped }
            errors[kind] = error.localizedDescription
            return .failure(message: error.localizedDescription)
        }
    }

    func disconnect(_ kind: BalanceKind) {
        revisions[kind, default: 0] += 1
        tasks[kind]?.cancel(); tasks[kind] = nil
        loading.remove(kind); errors[kind] = nil
        saved.credentials[kind] = nil; saved.values[kind] = nil
        persist(kind)
    }

    func reset(studentID: Int) {
        for kind in BalanceKind.allCases { revisions[kind, default: 0] += 1 }
        tasks.values.forEach { $0.cancel() }; tasks = [:]
        loading = []; errors = [:]
        saved = SavedBalances(studentID: studentID)
        do { try vault.clear(); restorationError = nil }
        catch {
            restorationError = error.localizedDescription
            errors = Dictionary(uniqueKeysWithValues: BalanceKind.allCases.map { ($0, error.localizedDescription) })
        }
    }

    @discardableResult
    func bind(studentID: Int) -> String? {
        guard saved.studentID != studentID else { return nil }
        if saved.studentID == 0 {
            saved.studentID = studentID
            if !saved.credentials.isEmpty || !saved.values.isEmpty {
                do { try vault.save(saved) }
                catch { restorationError = error.localizedDescription; return error.localizedDescription }
            }
        } else { reset(studentID: studentID) }
        return restorationError
    }

    private func persist(_ kind: BalanceKind) {
        do { try vault.save(saved); errors[kind] = nil; restorationError = nil }
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
