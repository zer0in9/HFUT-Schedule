import XCTest
import Observation
import HFUTCore
@testable import HFUTSchedule

@MainActor
final class RefreshTests: XCTestCase {
    private func snapshot() -> AcademicSnapshot {
        var snapshot = DemoData.snapshot()
        snapshot.isDemo = false
        snapshot.studentID = 42
        snapshot.program = ProgramModule(id: 1, title: "缓存培养方案", requiredCredits: nil, courses: [], children: [])
        return snapshot
    }
    private func cookie(domain: String = "jxglstu.hfut.edu.cn", expires: Date? = nil) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: "SESSION", .value: "synthetic", .domain: domain, .path: "/"]
        if let expires { properties[.expires] = expires }
        return HTTPCookie(properties: properties)!
    }
    private func store(client: StubAcademicClient, vault: MemorySessionVault, balances: BalanceStore? = nil, accounts: AccountStore? = nil) -> AppStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return AppStore(client: client, vault: vault, cacheURL: directory.appendingPathComponent("snapshot.json"), initialSnapshot: snapshot(), demoMode: false,
                        balances: balances ?? BalanceStore(studentID: 42, vault: MemoryBalanceVault()),
                        accounts: accounts ?? AccountStore(studentID: 42, vault: MemoryAccountVault()))
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
        XCTAssertEqual(store.snapshot.program?.title, "最新培养方案")
        XCTAssertEqual(store.refreshReport?.total, 5)
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

    func testRefreshProgressDoesNotInvalidateSnapshotOrRootPresentation() async {
        let client = StubAcademicClient()
        await client.holdIdentity()
        let store = store(client: client, vault: vault())
        let snapshotChange = ObservationChange()
        let presentationChange = ObservationChange()
        let progressChange = ObservationChange()
        withObservationTracking {
            _ = store.snapshot
        } onChange: {
            MainActor.assumeIsolated { snapshotChange.occurred = true }
        }
        withObservationTracking {
            _ = store.showLogin
            _ = store.errorMessage
        } onChange: {
            MainActor.assumeIsolated { presentationChange.occurred = true }
        }
        withObservationTracking {
            _ = store.syncStatus
        } onChange: {
            MainActor.assumeIsolated { progressChange.occurred = true }
        }

        let refresh = Task { await store.refresh() }
        await client.waitForIdentity()
        XCTAssertTrue(store.isBusy)
        XCTAssertTrue(progressChange.occurred)
        XCTAssertFalse(snapshotChange.occurred)
        XCTAssertFalse(presentationChange.occurred)

        await client.releaseIdentity()
        await refresh.value
        XCTAssertTrue(snapshotChange.occurred, "Successful data updates must still refresh page content")
        XCTAssertFalse(presentationChange.occurred)
        XCTAssertEqual(store.syncStatus, .updated)
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
        guard case .failed(let message, true) = store.syncStatus else { return XCTFail("Balance success must produce a partial update") }
        XCTAssertTrue(message.contains("登录"))
        XCTAssertEqual(store.refreshReport?.successCount, 1)
        XCTAssertTrue(store.refreshReport?.requiresAcademicLogin == true)
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
        XCTAssertEqual(saved.restoredCookies(studentID: 42, now: now.addingTimeInterval(24 * 3600)).count, 1)
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
                             balances: BalanceStore(studentID: 0, vault: MemoryBalanceVault()),
                             accounts: AccountStore(studentID: 0, vault: MemoryAccountVault()))
        await store.refreshOnLaunch()
        XCTAssertEqual(store.snapshot.studentID, 42)
        XCTAssertEqual(store.snapshot.courses.first?.name, "最新课程")
        XCTAssertTrue(store.isAuthenticated)
    }

    func testExpiredSessionRenewsOnceAndRevalidatesIdentity() async {
        let client = StubAcademicClient()
        await client.failIdentity(with: AcademicError.sessionExpired)
        await client.allowRenewal()
        let store = store(client: client, vault: vault())
        await store.refresh()
        XCTAssertTrue(store.isAuthenticated)
        XCTAssertEqual(store.syncStatus, .updated)
        let counts = await client.renewalCounts()
        XCTAssertEqual(counts, 1)
    }

    func testForbiddenDoesNotDiscardSessionOrAttemptLogin() async {
        let client = StubAcademicClient()
        await client.failIdentity(with: AcademicError.server(403))
        let vault = vault()
        let store = store(client: client, vault: vault)
        await store.refresh()
        XCTAssertNotNil(vault.saved)
        let count = await client.renewalCounts()
        XCTAssertEqual(count, 0)
        guard case .failed = store.syncStatus else { return XCTFail("Expected retryable failure") }
    }

    func testSavedPasswordWithoutSessionLogsInOnlyOnceAndCaptchaPausesFutureAttempts() async throws {
        let client = StubAcademicClient()
        await client.rejectRenewalWithCaptcha()
        let accounts = AccountStore(studentID: 42, vault: MemoryAccountVault())
        try accounts.save(.cas, account: "synthetic-student", password: "synthetic")
        let store = store(client: client, vault: MemorySessionVault(), accounts: accounts)
        await store.refresh()
        await store.refresh()
        let count = await client.renewalCounts()
        XCTAssertEqual(count, 1)
        XCTAssertNil(try accounts.credential(.cas))
        XCTAssertEqual(store.syncStatus, .needsLogin)
    }

    func testServerStillRejectingRenewedSessionDoesNotLoop() async {
        let client = StubAcademicClient()
        await client.failIdentity(with: AcademicError.sessionExpired)
        await client.allowRenewal(keepIdentityError: true)
        let store = store(client: client, vault: vault())
        await store.refresh()
        let count = await client.renewalCounts()
        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.syncStatus, .needsLogin)
    }

    func testCASCookieSurvivesBusinessSessionExpirationAndIsSecure() {
        let saved = SavedAcademicSession(studentID: 42, cookies: [cookie(domain: "cas.hfut.edu.cn"), cookie(domain: ".hfut.edu.cn")])
        let restored = saved.restoredCookies(studentID: 42)
        XCTAssertEqual(restored.count, 1)
        XCTAssertTrue(restored[0].isSecure)
    }

    func testSessionCookieRetainsHTTPOnlyAcrossKeychainSerialization() throws {
        let cookie = HTTPCookie(properties: [.name: "SESSION", .value: "synthetic", .domain: "jxglstu.hfut.edu.cn",
            .path: "/", HTTPCookiePropertyKey("HttpOnly"): "TRUE"])!
        let saved = SavedAcademicSession(studentID: 42, cookies: [cookie])
        let restored = try JSONDecoder().decode(SavedAcademicSession.self, from: JSONEncoder().encode(saved))
        XCTAssertTrue(restored.restoredCookies(studentID: 42)[0].isHTTPOnly)
    }

    func testGlobalRefreshJoinsBalanceDetailAndWaitsForItsFailure() async {
        let client = StubAcademicClient()
        let balanceClient = HeldRefreshBalanceClient(fail: true)
        let saved = SavedBalances(studentID: 42, credentials: [.campusCard: BalanceCredential(account: "synthetic", token: "synthetic")])
        let balances = BalanceStore(studentID: 42, client: balanceClient, vault: MemoryBalanceVault(saved: saved))
        let detail = Task { await balances.refresh(.campusCard) }
        await balanceClient.waitForRequest()
        let store = store(client: client, vault: vault(), balances: balances)
        let refresh = Task { await store.refresh() }
        for _ in 0..<1000 {
            if store.refreshReport?.completed == 5 { break }
            await Task.yield()
        }
        XCTAssertEqual(store.refreshReport?.completed, 5)
        XCTAssertEqual(store.refreshReport?.total, 6)
        XCTAssertTrue(store.syncStatus.isActive)
        XCTAssertTrue(store.isBusy)
        XCTAssertNotEqual(store.syncStatus, .updated)
        let count = await balanceClient.count
        XCTAssertEqual(count, 1)
        await balanceClient.release()
        await refresh.value
        _ = await detail.value
        guard case .failed(let message, true) = store.syncStatus else { return XCTFail("Expected combined partial failure") }
        XCTAssertTrue(message.contains("校园卡余额"))
        XCTAssertTrue(store.refreshReport?.isComplete == true)
        XCTAssertEqual(store.refreshReport?.successCount, 5)
        XCTAssertFalse(store.isBusy)
    }

    func testProgramFailurePreservesCachedProgramAndAppearsInGlobalResult() async {
        let client = StubAcademicClient()
        await client.failProgram()
        let store = store(client: client, vault: vault())
        await store.refresh()
        XCTAssertEqual(store.snapshot.program?.title, "缓存培养方案")
        XCTAssertEqual(store.snapshot.courses.first?.name, "最新课程")
        guard case .failed(let message, true) = store.syncStatus else { return XCTFail("Expected partial result") }
        XCTAssertTrue(message.contains("培养方案"))
    }

    func testProgramSessionExpiryRetriesOnlyExpiredResource() async {
        let client = StubAcademicClient()
        await client.expireProgram()
        await client.allowRenewal()
        let store = store(client: client, vault: vault())
        await store.refresh()
        let counts = await client.counts()
        let renewals = await client.renewalCounts()
        XCTAssertEqual(counts.timetable, 1)
        XCTAssertEqual(counts.program, 2)
        XCTAssertEqual(renewals, 1)
        XCTAssertEqual(store.refreshReport?.completed, 5)
        XCTAssertEqual(store.syncStatus, .updated)
    }

    func testProgramButtonAndPullJoinTheSameOperation() async {
        let client = StubAcademicClient()
        await client.holdIdentity()
        let store = store(client: client, vault: vault())
        let loading = Task { await store.loadProgram() }
        await client.waitForIdentity()
        let pull = Task { await store.refresh() }
        await Task.yield()
        await client.releaseIdentity()
        await loading.value
        await pull.value
        let counts = await client.counts()
        XCTAssertEqual(counts.timetable, 1)
        XCTAssertEqual(counts.program, 1)
        XCTAssertEqual(store.snapshot.program?.title, "最新培养方案")
    }

    func testGlobalRefreshUpdatesSubmittedSearchAndResetsPaginationWithoutLosingFailedCache() async {
        let client = StubAcademicClient()
        let store = store(client: client, vault: vault())
        await store.searchCourses(query: "算法")
        await store.loadMoreCourses()
        XCTAssertEqual(store.courseSearch?.rows.count, 2)
        await store.refresh()
        XCTAssertEqual(store.courseSearch?.rows.count, 1)
        var requests = await client.searchRequests()
        XCTAssertEqual(requests.map(\.page), [1, 2, 1])
        XCTAssertEqual(store.refreshReport?.total, 6)
        let oldRows = store.courseSearch?.rows
        await client.failSearch()
        await store.refresh()
        XCTAssertEqual(store.courseSearch?.rows, oldRows)
        guard case .failed(let message, true) = store.syncStatus else { return XCTFail("Expected search failure in global result") }
        XCTAssertTrue(message.contains("开课查询"))
        XCTAssertNil(store.errorMessage)
        requests = await client.searchRequests()
        XCTAssertEqual(requests.last?.page, 1)
    }

    func testGlobalRefreshUsesNewSemesterForExistingSearch() async {
        let client = StubAcademicClient()
        let store = store(client: client, vault: vault())
        await store.searchCourses(query: "算法")
        store.selectedSemester += 20
        await store.refresh()
        XCTAssertEqual(store.courseSearch?.semesterID, store.selectedSemester)
        let requests = await client.searchRequests()
        XCTAssertEqual(requests.last?.semester, store.selectedSemester)
        XCTAssertEqual(requests.last?.page, 1)
    }

    func testPullDuringLoginWaitsThenRefreshesInsteadOfBeingDropped() async {
        let client = StubAcademicClient()
        await client.holdIdentity()
        let store = store(client: client, vault: MemorySessionVault())
        let login = Task { await store.connect(cookies: [cookie()]) }
        await client.waitForIdentity()
        var requested = false
        var finished = false
        let pull = Task { requested = true; await store.refresh(); finished = true }
        while !requested { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(finished)
        await client.releaseIdentity()
        let connected = await login.value
        XCTAssertTrue(connected)
        await pull.value
        let counts = await client.counts()
        XCTAssertEqual(counts.identity, 2)
        XCTAssertEqual(counts.timetable, 1)
        XCTAssertEqual(store.syncStatus, .updated)
    }

    func testFreshUnconfiguredAppDoesNotRequestAnythingOrClaimUpdated() async {
        let client = StubAcademicClient()
        let store = AppStore(client: client, vault: MemorySessionVault(),
            initialSnapshot: AcademicSnapshot(semesterID: 354), demoMode: false,
            balances: BalanceStore(studentID: 0, vault: MemoryBalanceVault()),
            accounts: AccountStore(studentID: 0, vault: MemoryAccountVault()))
        await store.refresh()
        let counts = await client.counts()
        XCTAssertEqual(counts.identity, 0)
        XCTAssertEqual(store.refreshReport?.total, 0)
        XCTAssertEqual(store.syncStatus, .idle)
    }

    func testFullRefreshRequestedDuringSearchRunsAllResourcesAfterSearchFinishes() async {
        let client = StubAcademicClient()
        await client.holdSearch()
        let store = store(client: client, vault: vault())
        let search = Task { await store.searchCourses(query: "算法") }
        await client.waitForSearch()
        var requested = false
        let full = Task { requested = true; await store.refresh() }
        while !requested { await Task.yield() }
        await client.releaseSearch()
        await search.value
        await full.value
        let counts = await client.counts()
        let requests = await client.searchRequests()
        XCTAssertEqual(counts.timetable, 1)
        XCTAssertEqual(counts.program, 1)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(store.refreshReport?.total, 6)
        XCTAssertEqual(store.syncStatus, .updated)
    }

    func testLogoutDiscardsRefreshQueuedBehindLogin() async {
        let client = StubAcademicClient()
        await client.holdIdentity()
        let store = store(client: client, vault: MemorySessionVault())
        let login = Task { await store.connect(cookies: [cookie()]) }
        await client.waitForIdentity()
        var requested = false
        let pull = Task { requested = true; await store.refresh() }
        while !requested { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        await store.signOut()
        await client.releaseIdentity()
        _ = await login.value
        await pull.value
        let counts = await client.counts()
        XCTAssertEqual(counts.timetable, 0)
        XCTAssertEqual(store.snapshot.studentID, 0)
        XCTAssertNil(store.refreshReport)
        XCTAssertEqual(store.syncStatus, .idle)
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
final class MemorySessionVault: SessionVault {
    var saved: SavedAcademicSession?
    init(saved: SavedAcademicSession? = nil) { self.saved = saved }
    func load() throws -> SavedAcademicSession? { saved }
    func save(_ session: SavedAcademicSession) throws { saved = session }
    func clear() throws { saved = nil }
}

@MainActor
private final class ObservationChange {
    var occurred = false
}

private actor StubAcademicClient: AcademicServing {
    private var identityCount = 0, timetableCount = 0, acceptCount = 0
    private var identityError: Error?
    private var gradesFail = false
    private var programFail = false, searchFail = false, programExpired = false
    private var programCount = 0
    private var searches: [(query: String, page: Int, semester: Int)] = []
    private var searchHeld = false
    private var searchPending: CheckedContinuation<Void, Never>?
    private var searchWaiters: [CheckedContinuation<Void, Never>] = []
    func holdSearch() { searchHeld = true }
    func waitForSearch() async {
        if !searches.isEmpty { return }
        await withCheckedContinuation { searchWaiters.append($0) }
    }
    func releaseSearch() { searchHeld = false; searchPending?.resume(); searchPending = nil }
    func failProgram() { programFail = true }
    func failSearch() { searchFail = true }
    func expireProgram() { programExpired = true }
    func searchRequests() -> [(query: String, page: Int, semester: Int)] { searches }
    private var held = false
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var identityWaiters: [CheckedContinuation<Void, Never>] = []
    private var cookies: [HTTPCookie] = []
    private var renewalAllowed = false
    private var renewalError: AcademicError?
    private var keepIdentityError = false
    private var renewals = 0
    func allowRenewal(keepIdentityError: Bool = false) { renewalAllowed = true; self.keepIdentityError = keepIdentityError }
    func rejectRenewalWithCaptcha() { renewalError = .verificationRequired }
    func renewalCounts() -> Int { renewals }
    func renewSession(account: String?, password: String?) throws {
        renewals += 1
        if let renewalError { throw renewalError }
        guard renewalAllowed else { throw AcademicError.sessionExpired }
        if !keepIdentityError { identityError = nil }
        programExpired = false
    }
    func counts() -> (identity: Int, timetable: Int, accept: Int, program: Int) { (identityCount, timetableCount, acceptCount, programCount) }
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
    func program(studentID: Int) async throws -> ProgramModule {
        programCount += 1
        if programExpired { throw AcademicError.sessionExpired }
        if programFail { throw AcademicError.server(503) }
        return ProgramModule(id: 1, title: "最新培养方案", requiredCredits: nil, courses: [], children: [])
    }
    func search(studentID: Int, semesterID: Int, name: String, page: Int) async throws -> [Course] {
        searches.append((name, page, semesterID))
        searchWaiters.forEach { $0.resume() }; searchWaiters = []
        if searchHeld { await withCheckedContinuation { searchPending = $0 } }
        if searchFail { throw AcademicError.server(503) }
        return [Course(id: page, name: "\(name) 第\(page)页")]
    }
}


private actor HeldRefreshBalanceClient: CampusBalanceServing {
    private let fail: Bool
    private var held = true
    private var pending: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var count = 0
    init(fail: Bool) { self.fail = fail }
    func waitForRequest() async {
        if count > 0 { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() { held = false; pending?.resume(); pending = nil }
    func loginCard(account: String, queryPassword: String) -> BalanceCredential { BalanceCredential(account: account, token: "synthetic") }
    func loginShower(account: String, password: String) -> BalanceCredential { BalanceCredential(account: account, token: "synthetic") }
    func balance(_ kind: BalanceKind, credential: BalanceCredential) async throws -> CampusBalance {
        count += 1
        waiters.forEach { $0.resume() }; waiters = []
        if held { await withCheckedContinuation { pending = $0 } }
        if fail { throw BalanceError.server(503) }
        return CampusBalance(amount: 88)
    }
}
