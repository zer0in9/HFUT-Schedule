import SwiftUI
import Security
import CryptoKit
import HFUTCore

enum AccountSystem: String, Codable, CaseIterable, Identifiable {
    case cas, campusCard, shower
    var id: String { rawValue }
    var title: String {
        switch self { case .cas: "统一认证"; case .campusCard: "慧新易校校园卡"; case .shower: "呱呱淋浴" }
    }
    var accountLabel: String { self == .shower ? "手机号" : "学号" }
    var passwordLabel: String {
        switch self { case .cas: "信息门户密码"; case .campusCard: "校园卡查询密码"; case .shower: "呱呱淋浴密码" }
    }
    var balanceKind: BalanceKind? {
        switch self { case .cas: nil; case .campusCard: .campusCard; case .shower: .shower }
    }
    init(_ kind: BalanceKind) { self = kind == .campusCard ? .campusCard : .shower }
}

struct StoredAccount: Codable {
    var account: String
    var password: String
    var automaticLogin = true
}

struct SavedAccounts: Codable {
    var studentID: Int
    var entries: [AccountSystem: StoredAccount] = [:]
}

@MainActor
protocol AccountVault {
    func load() throws -> SavedAccounts?
    func save(_ accounts: SavedAccounts) throws
    func clear() throws
}

/// Publishes account metadata only. Passwords are read from Keychain just for an operation.
@MainActor
final class AccountStore: ObservableObject {
    struct Summary {
        let account: String
        let automaticLogin: Bool
    }
    @Published private(set) var summaries: [AccountSystem: Summary] = [:]
    @Published private(set) var error: String?
    private let vault: any AccountVault
    private(set) var studentID: Int

    init(studentID: Int, vault: (any AccountVault)? = nil, demo: Bool = false) {
        self.studentID = studentID
        self.vault = vault ?? KeychainAccountVault()
        guard !demo else { return }
        do {
            if let saved = try self.vault.load() {
                guard saved.studentID == studentID || studentID == 0 else { try self.vault.clear(); return }
                self.studentID = saved.studentID
                updateMetadata(saved)
            }
        } catch { self.error = error.localizedDescription }
    }

    private func updateMetadata(_ saved: SavedAccounts) {
        summaries = saved.entries.mapValues { Summary(account: $0.account, automaticLogin: $0.automaticLogin) }
        error = nil
    }

    func credential(_ system: AccountSystem, forAutomaticLogin: Bool = true) throws -> StoredAccount? {
        guard let saved = try vault.load(), saved.studentID == studentID,
              let entry = saved.entries[system], !forAutomaticLogin || entry.automaticLogin else { return nil }
        return entry
    }

    func save(_ system: AccountSystem, account: String, password: String) throws {
        let account = account.trimmingCharacters(in: .whitespacesAndNewlines)
        var saved = try vault.load() ?? SavedAccounts(studentID: studentID)
        guard saved.studentID == studentID else { throw AccountError.accountMismatch }
        let old = saved.entries[system]
        let secret = password.isEmpty && old?.account == account ? old?.password ?? "" : password
        guard !account.isEmpty, account.utf8.count <= 128, !secret.isEmpty, secret.utf8.count <= 1024 else { throw AccountError.invalidInput }
        saved.entries[system] = StoredAccount(account: account, password: secret)
        try vault.save(saved)
        updateMetadata(saved)
    }

    func pause(_ system: AccountSystem) throws {
        guard var saved = try vault.load(), saved.studentID == studentID else { return }
        saved.entries[system]?.automaticLogin = false
        try vault.save(saved)
        updateMetadata(saved)
    }

    func remove(_ system: AccountSystem) throws {
        guard var saved = try vault.load(), saved.studentID == studentID else { return }
        saved.entries[system] = nil
        try vault.save(saved)
        updateMetadata(saved)
    }

    func bind(studentID: Int) throws {
        if self.studentID == studentID { return }
        if self.studentID == 0 {
            var saved = try vault.load() ?? SavedAccounts(studentID: studentID)
            saved.studentID = studentID
            try vault.save(saved)
            self.studentID = studentID
            updateMetadata(saved)
        } else {
            try clear(studentID: studentID)
        }
    }

    func clear(studentID: Int = 0) throws {
        try vault.clear()
        self.studentID = studentID
        summaries = [:]; error = nil
    }

    static func showerProof(_ password: String) -> String {
        String(Insecure.MD5.hash(data: Data(password.utf8)).map { String(format: "%02X", $0) }.joined().suffix(10))
    }
}

private enum AccountError: LocalizedError {
    case invalidInput, accountMismatch
    var errorDescription: String? {
        self == .invalidInput ? "请输入账号与密码；修改已有账号时，密码留空可保留原密码。" : "账号归属已改变，请重新打开账号配置。"
    }
}

struct KeychainAccountVault: AccountVault {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.hfut.schedule.ios",
         kSecAttrAccount as String: "system-accounts-v1",
         kSecAttrSynchronizable as String: false]
    }
    func load() throws -> SavedAccounts? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw VaultError(status: status) }
        return try JSONDecoder().decode(SavedAccounts.self, from: data)
    }
    func save(_ accounts: SavedAccounts) throws {
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(accounts),
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
        var errorDescription: String? { "无法访问账号钥匙串（\(status)）" }
    }
}
