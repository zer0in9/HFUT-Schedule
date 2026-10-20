import XCTest
import HFUTCore
@testable import HFUTSchedule

@MainActor
final class BalanceStoreTests: XCTestCase {
    private func cached() -> SavedBalances {
        SavedBalances(studentID: 42, credentials: [
            .campusCard: BalanceCredential(account: "synthetic-student", token: "card-token"),
            .shower: BalanceCredential(account: "13000000000", token: "shower-token")
        ], values: [.campusCard: CampusBalance(amount: 50), .shower: CampusBalance(amount: 10)])
    }

    func testRestoresOnlyMatchingAccountAndSkipsDemo() {
        let vault = MemoryBalanceVault(saved: cached())
        let client = StubBalanceClient()
        let matching = BalanceStore(studentID: 42, client: client, vault: vault)
        XCTAssertEqual(matching.saved.values[.campusCard]?.amount, 50)
        XCTAssertTrue(matching.isConnected(.shower))
        XCTAssertFalse(BalanceStore(studentID: 43, client: client, vault: vault).isConnected(.shower))
        XCTAssertTrue(BalanceStore(studentID: 42, client: client, vault: vault, demo: true).saved.values.isEmpty)
    }

    func testOldPortalCredentialsAreDiscardedWithoutLosingShowerAccount() throws {
        var legacy = cached()
        legacy.cardProvider = nil
        let vault = MemoryBalanceVault(saved: legacy)
        let store = BalanceStore(studentID: 42, client: StubBalanceClient(), vault: vault)
        XCTAssertFalse(store.isConnected(.campusCard))
        XCTAssertNil(store.saved.values[.campusCard])
        XCTAssertNil(vault.saved?.credentials[.campusCard])
        XCTAssertEqual(vault.saved?.cardProvider, "huixin")
        XCTAssertTrue(store.isConnected(.shower))
        XCTAssertEqual(store.saved.values[.shower]?.amount, 10)
        // A cache written before the provider field existed must decode as legacy, not HuiXin.
        let data = try JSONEncoder().encode(cached())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "cardProvider")
        let decoded = try JSONDecoder().decode(SavedBalances.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.cardProvider)
    }

    func testPartialFailurePreservesOldAmountAndUpdatesOtherBalance() async {
        let client = StubBalanceClient()
        await client.fail(.campusCard, error: URLError(.notConnectedToInternet))
        let vault = MemoryBalanceVault(saved: cached())
        let store = BalanceStore(studentID: 42, client: client, vault: vault)
        let oldDate = store.saved.values[.campusCard]?.updatedAt
        await store.refresh()
        XCTAssertEqual(store.saved.values[.campusCard]?.amount, 50)
        XCTAssertEqual(store.saved.values[.campusCard]?.updatedAt, oldDate)
        XCTAssertEqual(store.saved.values[.shower]?.amount, 25)
        XCTAssertNotNil(store.errors[.campusCard])
        XCTAssertNil(store.errors[.shower])
        XCTAssertTrue(store.isConnected(.campusCard))
        XCTAssertTrue(store.loading.isEmpty)
        await client.fail(.campusCard, error: nil)
        await store.refresh()
        XCTAssertEqual(store.saved.values[.campusCard]?.amount, 100)
        XCTAssertNil(store.errors[.campusCard])
    }

    func testExpiredCredentialIsRemovedButLastKnownBalanceRemains() async {
        let client = StubBalanceClient()
        await client.fail(.shower, error: BalanceError.loginRequired)
        let vault = MemoryBalanceVault(saved: cached())
        let store = BalanceStore(studentID: 42, client: client, vault: vault)
        await store.refresh()
        XCTAssertFalse(store.isConnected(.shower))
        XCTAssertNil(vault.saved?.credentials[.shower])
        XCTAssertEqual(store.saved.values[.shower]?.amount, 10)
        XCTAssertTrue(store.isConnected(.campusCard))
    }

    func testFailedAccountChangeKeepsPreviousAccountAndBalance() async {
        let client = StubBalanceClient()
        await client.fail(.campusCard, error: BalanceError.rejected)
        let store = BalanceStore(studentID: 42, client: client, vault: MemoryBalanceVault(saved: cached()))
        let connected = await store.connectCard(account: "new-account", queryPassword: "synthetic")
        XCTAssertFalse(connected)
        XCTAssertEqual(store.saved.credentials[.campusCard]?.account, "synthetic-student")
        XCTAssertEqual(store.saved.values[.campusCard]?.amount, 50)
    }

    func testResetDiscardsInFlightResponseAndClearsPersistedAccounts() async {
        let client = StubBalanceClient()
        await client.holdCard()
        let vault = MemoryBalanceVault(saved: cached())
        let store = BalanceStore(studentID: 42, client: client, vault: vault)
        let task = Task { await store.refresh(.campusCard) }
        await client.waitForCard()
        store.reset(studentID: 43)
        await client.releaseCard()
        await task.value
        XCTAssertEqual(store.saved.studentID, 43)
        XCTAssertTrue(store.saved.values.isEmpty)
        XCTAssertTrue(store.saved.credentials.isEmpty)
        XCTAssertTrue(store.loading.isEmpty)
        XCTAssertNil(vault.saved)
    }

    func testDisconnectDiscardsLateResponseWithoutAffectingOtherAccount() async {
        let client = StubBalanceClient()
        await client.holdCard()
        let vault = MemoryBalanceVault(saved: cached())
        let store = BalanceStore(studentID: 42, client: client, vault: vault)
        let task = Task { await store.refresh(.campusCard) }
        await client.waitForCard()
        // An overlapping refresh must not query the same service again.
        await store.refresh(.campusCard)
        store.disconnect(.campusCard)
        await client.releaseCard()
        await task.value
        let count = await client.cardCount
        XCTAssertEqual(count, 1)
        XCTAssertNil(store.saved.values[.campusCard])
        XCTAssertNil(vault.saved?.credentials[.campusCard])
        XCTAssertTrue(store.isConnected(.shower))
    }
}

@MainActor
final class MemoryBalanceVault: BalanceVault {
    var saved: SavedBalances?
    init(saved: SavedBalances? = nil) { self.saved = saved }
    func load() -> SavedBalances? { saved }
    func save(_ value: SavedBalances) { saved = value }
    func clear() { saved = nil }
}

private actor StubBalanceClient: CampusBalanceServing {
    private var errors: [BalanceKind: Error] = [:]
    private var held = false
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var cardCount = 0
    func fail(_ kind: BalanceKind, error: Error?) { errors[kind] = error }
    func holdCard() { held = true }
    func waitForCard() async {
        if cardCount > 0 { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func releaseCard() { held = false; pending.forEach { $0.resume() }; pending = [] }
    func loginShower(account: String, password: String) -> BalanceCredential {
        BalanceCredential(account: account, token: "new-token")
    }
    func loginCard(account: String, queryPassword: String) -> BalanceCredential {
        BalanceCredential(account: account, token: "new-token")
    }
    func balance(_ kind: BalanceKind, credential: BalanceCredential) async throws -> CampusBalance {
        if kind == .campusCard {
            cardCount += 1
            waiters.forEach { $0.resume() }; waiters = []
            if held { await withCheckedContinuation { pending.append($0) } }
        }
        if let error = errors[kind] { throw error }
        return CampusBalance(amount: kind == .campusCard ? 100 : 25)
    }
}
