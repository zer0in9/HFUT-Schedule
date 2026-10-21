import XCTest
import HFUTCore
@testable import HFUTSchedule

@MainActor
final class AccountStoreTests: XCTestCase {
    func testPasswordsStayInVaultAndBlankEditPreservesOnlySameAccount() throws {
        let vault = MemoryAccountVault()
        let store = AccountStore(studentID: 42, vault: vault)
        try store.save(.cas, account: " student ", password: "synthetic-secret")
        XCTAssertEqual(store.summaries[.cas]?.account, "student")
        XCTAssertEqual(try store.credential(.cas)?.password, "synthetic-secret")
        try store.save(.cas, account: "student", password: "")
        XCTAssertEqual(try store.credential(.cas)?.password, "synthetic-secret")
        XCTAssertThrowsError(try store.save(.cas, account: "different", password: ""))
        XCTAssertEqual(vault.saved?.entries[.cas]?.account, "student")
    }

    func testPausedPasswordIsNotRetriedAfterRelaunchAndEditReenablesIt() throws {
        let vault = MemoryAccountVault()
        let store = AccountStore(studentID: 42, vault: vault)
        try store.save(.cas, account: "student", password: "synthetic")
        try store.pause(.cas)
        let restored = AccountStore(studentID: 42, vault: vault)
        XCTAssertNil(try restored.credential(.cas))
        XCTAssertNotNil(try restored.credential(.cas, forAutomaticLogin: false))
        try restored.save(.cas, account: "student", password: "new-synthetic")
        XCTAssertEqual(try restored.credential(.cas)?.password, "new-synthetic")
    }

    func testAccountSwitchClearsEverySystemButInitialBindingPreservesConfiguration() throws {
        let vault = MemoryAccountVault()
        let store = AccountStore(studentID: 0, vault: vault)
        for system in AccountSystem.allCases { try store.save(system, account: system.rawValue, password: "synthetic") }
        try store.bind(studentID: 42)
        XCTAssertEqual(store.summaries.count, 3)
        try store.bind(studentID: 43)
        XCTAssertTrue(store.summaries.isEmpty)
        XCTAssertNil(vault.saved)
    }

    func testDeletingOneSystemDoesNotDeleteOtherPasswords() throws {
        let store = AccountStore(studentID: 42, vault: MemoryAccountVault())
        try store.save(.cas, account: "student", password: "synthetic-cas")
        try store.save(.campusCard, account: "student", password: "synthetic-card")
        try store.remove(.cas)
        XCTAssertNil(try store.credential(.cas))
        XCTAssertEqual(try store.credential(.campusCard)?.password, "synthetic-card")
    }

    func testFailedSaveDoesNotPublishUnsavedAccount() throws {
        let vault = MemoryAccountVault()
        let store = AccountStore(studentID: 42, vault: vault)
        vault.failWrites = true
        XCTAssertThrowsError(try store.save(.cas, account: "student", password: "synthetic"))
        XCTAssertTrue(store.summaries.isEmpty)
    }

    func testLogoutClearsPasswordsAndTokens() async throws {
        let vault = MemoryAccountVault()
        let accounts = AccountStore(studentID: 42, vault: vault)
        try accounts.save(.shower, account: "13000000000", password: "synthetic")
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(vault: MemorySessionVault(), cacheURL: cache, initialSnapshot: AcademicSnapshot(semesterID: 354, studentID: 42),
                             demoMode: false, balances: BalanceStore(studentID: 42, vault: MemoryBalanceVault()), accounts: accounts)
        await store.signOut()
        XCTAssertTrue(accounts.summaries.isEmpty)
        XCTAssertNil(vault.saved)
        XCTAssertEqual(store.snapshot.studentID, 0)
    }

    func testExportedBackupExcludesConfiguredPasswordsAndAccounts() throws {
        let accounts = AccountStore(studentID: 42, vault: MemoryAccountVault())
        try accounts.save(.cas, account: "synthetic-private-account", password: "synthetic-private-password")
        let store = AppStore(vault: MemorySessionVault(), initialSnapshot: AcademicSnapshot(semesterID: 354, studentID: 42),
                             demoMode: false, balances: BalanceStore(studentID: 42, vault: MemoryBalanceVault()), accounts: accounts)
        let url = try store.exportSnapshot()
        defer { try? FileManager.default.removeItem(at: url) }
        let backup = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(backup.contains("synthetic-private-account"))
        XCTAssertFalse(backup.contains("synthetic-private-password"))
    }
}

@MainActor
final class MemoryAccountVault: AccountVault {
    var saved: SavedAccounts?
    var failWrites = false
    func load() -> SavedAccounts? { saved }
    func save(_ accounts: SavedAccounts) throws {
        if failWrites { throw AcademicError.unavailable }
        saved = accounts
    }
    func clear() { saved = nil }
}
