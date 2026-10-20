import XCTest
import HFUTCore
@testable import HFUTSchedule

@MainActor
final class RefreshTests: XCTestCase {
    private func snapshot() -> AcademicSnapshot {
        var snapshot = DemoData.snapshot()
        snapshot.isDemo = false
        snapshot.studentID = 42
        return snapshot
    }
    private func cookie(domain: String = "jxglstu.hfut.edu.cn", expires: Date? = nil) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: "SESSION", .value: "synthetic", .domain: domain, .path: "/"]
        if let expires { properties[.expires] = expires }
        return HTTPCookie(properties: properties)!
    }
    private func store(client: StubAcademicClient, vault: MemorySessionVault, balances: BalanceStore? = nil) -> AppStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return AppStore(client: client, vault: vault, cacheURL: directory.appendingPathComponent("snapshot.json"), initialSnapshot: snapshot(), demoMode: false,
                        balances: balances ?? BalanceStore(studentID: 42, vault: MemoryBalanceVault()))
    }
    private func vault() -> MemorySessionVault {
        MemorySessionVault(saved: SavedAcademicSession(studentID: 42, cookies: [cookie()]))
    }

    func testColdLaunchRestoresSessionAndUpdatesOnlyOnce() async {
        let client = StubAcademicClient()
        let vault = vault()
        let store = store(client: client, vault: vault)
        await store.refreshOnLaunch()
        await store.refreshOnLaunch()
        let counts = await client.counts()
        XCTAssertEqual(counts.identity, 1)
        XCTAssertEqual(counts.timetable, 1)
        XCTAssertEqual(counts.accept, 1)
        XCTAssertEqual(store.snapshot.courses.first?.name, "最新课程")
        XCTAssertTrue(store.isAuthenticated)
        XCTAssertFalse(store.isBusy)
        XCTAssertEqual(store.syncStatus, .updated)
        XCTAssertNil(store.errorMessage)
        XCTAssertNotNil(vault.saved)
    }

    func testPullAndLaunchJoinTheSameInFlightRefresh() async throws {
        let client = StubAcademicClient()
        await client.holdIdentity()
        let store = store(client: client, vault: vault())
        let launch = Task { await store.refreshOnLaunch() }
        await client.waitForIdentity()
        XCTAssertEqual(store.syncStatus, .connecting)
        var didStartPull = false
        let pull = Task { didStartPull = true; await store.refresh() }
        while !didStartPull { await Task.yield() }
        await client.releaseIdentity()
        await launch.value
        await pull.value
        let counts = await client.counts()
        XCTAssertEqual(counts.identity, 1)
        XCTAssertEqual(counts.timetable, 1)
        // A subsequent pull starts another request rather than applying a stale cache result.
        await store.refresh()
        let afterPull = await client.counts()
        XCTAssertEqual(afterPull.timetable, 2)
    }

    func testMissingSessionPromptsSignInWithoutRequestsOrPopup() async {
        let client = StubAcademicClient()
        let store = store(client: client, vault: MemorySessionVault())
        await store.refreshOnLaunch()
        let counts = await client.counts()
        XCTAssertEqual(counts.identity, 0)
        XCTAssertEqual(store.syncStatus, .needsLogin)
        XCTAssertFalse(store.showLogin)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.snapshot.schedule.isEmpty)
    }

    func testConnectedBalanceRefreshesEvenWithoutAcademicSession() async {
        let client = StubAcademicClient()
        let balanceClient = StubRefreshBalanceClient()
        let saved = SavedBalances(studentID: 42,
            credentials: [.campusCard: BalanceCredential(account: "synthetic-student", token: "synthetic")])
        let balances = BalanceStore(studentID: 42, client: balanceClient, vault: MemoryBalanceVault(saved: saved))
        let store = store(client: client, vault: MemorySessionVault(), balances: balances)
        await store.refreshOnLaunch()
        let academicCounts = await client.counts()
        let balanceCount = await balanceClient.count
        XCTAssertEqual(academicCounts.identity, 0)
        XCTAssertEqual(balanceCount, 1)
        XCTAssertEqual(store.balances.saved.values[.campusCard]?.amount, 88)
        XCTAssertEqual(store.syncStatus, .needsLogin)
        XCTAssertFalse(store.isBusy)
    }

    func testExpiredServerSessionClearsCredentialsAndKeepsCache() async {
        let client = StubAcademicClient()
        await client.failIdentity(with: AcademicError.sessionExpired)
        let vault = vault()
        let store = store(client: client, vault: vault)
        let original = store.snapshot.schedule
        await store.refreshOnLaunch()
        XCTAssertEqual(store.syncStatus, .needsLogin)
        XCTAssertNil(vault.saved)
        XCTAssertEqual(store.snapshot.schedule, original)
        XCTAssertFalse(store.isBusy)
        XCTAssertFalse(store.isAuthenticated)
        XCTAssertNil(store.errorMessage)
    }

    func testOfflineFailureRetainsCredentialForRetry() async {
        let client = StubAcademicClient()
        await client.failIdentity(with: URLError(.notConnectedToInternet))
        let vault = vault()
        let store = store(client: client, vault: vault)
        await store.refreshOnLaunch()
        guard case .failed(_, false) = store.syncStatus else { return XCTFail("Expected retryable top-bar failure") }
        XCTAssertNotNil(vault.saved)
        XCTAssertNil(store.errorMessage)
        await client.failIdentity(with: nil)
        await store.refresh()
        XCTAssertEqual(store.syncStatus, .updated)
    }

    func testPartialFailureRetainsOldSectionAndUpdatesSuccessfulSections() async {
        let client = StubAcademicClient()
        await client.failGrades()
        let store = store(client: client, vault: vault())
        let oldGrades = store.snapshot.grades.map(\.score)
        await store.refreshOnLaunch()
        XCTAssertEqual(store.snapshot.courses.first?.name, "最新课程")
        XCTAssertEqual(store.snapshot.grades.map(\.score), oldGrades)
        guard case .failed(let message, true) = store.syncStatus else { return XCTFail("Expected partial-update state") }
        XCTAssertTrue(message.contains("成绩"))
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isBusy)
    }

    func testLogoutDiscardsLateResponseAndClearsVault() async {
        let client = StubAcademicClient()
        await client.holdIdentity()
        let vault = vault()
        let store = store(client: client, vault: vault)
        let refresh = Task { await store.refreshOnLaunch() }
        await client.waitForIdentity()
        await store.signOut()
        await client.releaseIdentity()
        await refresh.value
        XCTAssertEqual(store.snapshot.studentID, 0)
        XCTAssertTrue(store.snapshot.courses.isEmpty)
        XCTAssertNil(vault.saved)
        XCTAssertEqual(store.syncStatus, .idle)
        XCTAssertFalse(store.isAuthenticated)
    }

    func testSavedSessionIsAccountScopedDomainLimitedAndExpires() {
        let now = Date()
        let saved = SavedAcademicSession(studentID: 42, cookies: [cookie(), cookie(domain: "example.com")], now: now)
        XCTAssertEqual(saved.restoredCookies(studentID: 42, now: now).count, 1)
        XCTAssertTrue(saved.restoredCookies(studentID: 43, now: now).isEmpty)
        XCTAssertTrue(saved.restoredCookies(studentID: 42, now: now.addingTimeInterval(3 * 3600)).isEmpty)
        XCTAssertFalse(saved.restoredCookies(studentID: 42, now: now).first!.isSecure)
        let expired = SavedAcademicSession(studentID: 42, cookies: [cookie(expires: now.addingTimeInterval(-1))], now: now)
        XCTAssertTrue(expired.restoredCookies(studentID: 42, now: now).isEmpty)
    }

    func testColdLaunchCanRebuildMissingCacheFromValidatedSavedSession() async {
        let client = StubAcademicClient()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(client: client, vault: vault(), cacheURL: directory.appendingPathComponent("cache.json"),
                             initialSnapshot: AcademicSnapshot(semesterID: 354), demoMode: false,
                             balances: BalanceStore(studentID: 0, vault: MemoryBalanceVault()))
        await store.refreshOnLaunch()
        XCTAssertEqual(store.snapshot.studentID, 42)
        XCTAssertEqual(store.snapshot.courses.first?.name, "最新课程")
        XCTAssertTrue(store.isAuthenticated)
    }
}

private actor StubRefreshBalanceClient: CampusBalanceServing {
    private(set) var count = 0
    func loginShower(account: String, password: String) throws -> BalanceCredential { throw BalanceError.rejected }
    func loginCard(account: String, queryPassword: String) throws -> BalanceCredential { throw BalanceError.rejected }
    func balance(_ kind: BalanceKind, credential: BalanceCredential) -> CampusBalance {
        count += 1
        return CampusBalance(amount: 88)
    }
}

@MainActor
private final class MemorySessionVault: SessionVault {
    var saved: SavedAcademicSession?
    init(saved: SavedAcademicSession? = nil) { self.saved = saved }
    func load() throws -> SavedAcademicSession? { saved }
    func save(_ session: SavedAcademicSession) throws { saved = session }
    func clear() throws { saved = nil }
}

private actor StubAcademicClient: AcademicServing {
    private var identityCount = 0, timetableCount = 0, acceptCount = 0
    private var identityError: Error?
    private var gradesFail = false
    private var held = false
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var identityWaiters: [CheckedContinuation<Void, Never>] = []
    private var cookies: [HTTPCookie] = []
    func counts() -> (identity: Int, timetable: Int, accept: Int) { (identityCount, timetableCount, acceptCount) }
    func accept(cookies: [HTTPCookie]) { acceptCount += 1; self.cookies = cookies }
    func currentCookies() -> [HTTPCookie] { cookies }
    func clearSession() { cookies = [] }
    func failIdentity(with error: Error?) { identityError = error }
    func failGrades() { gradesFail = true }
    func holdIdentity() { held = true }
    func waitForIdentity() async {
        if identityCount > 0 { return }
        await withCheckedContinuation { identityWaiters.append($0) }
    }
    func releaseIdentity() { held = false; pending.forEach { $0.resume() }; pending = [] }
    func identity() async throws -> (studentID: Int, businessID: Int) {
        identityCount += 1
        identityWaiters.forEach { $0.resume() }; identityWaiters = []
        if held { await withCheckedContinuation { pending.append($0) } }
        if let identityError { throw identityError }
        return (42, 26)
    }
    func timetable(studentID: Int, businessID: Int, semesterID: Int) async throws -> (CourseSummary, [ScheduleEntry]) {
        timetableCount += 1
        return (CourseSummary(lessonIDs: [1], courses: [Course(id: 1, name: "最新课程")], semesterStart: nil), [])
    }
    func grades(studentID: Int) async throws -> [Grade] {
        if gradesFail { throw AcademicError.server(503) }
        return []
    }
    func exams(studentID: Int) async throws -> [Exam] { [] }
    func profile(studentID: Int) async throws -> StudentProfile { StudentProfile() }
    func program(studentID: Int) async throws -> ProgramModule { throw AcademicError.unavailable }
    func search(studentID: Int, semesterID: Int, name: String, page: Int) async throws -> [Course] { [] }
}
