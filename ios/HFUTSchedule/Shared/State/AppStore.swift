import SwiftUI
import Observation
import HFUTCore

@MainActor
@Observable
final class AppStore {
    private(set) var snapshot: AcademicSnapshot
    private(set) var isAuthenticated = false
    private(set) var isBusy = false {
        didSet {
            if !isBusy {
                let waiters = idleWaiters; idleWaiters = []
                waiters.forEach { $0.resume() }
            }
        }
    }
    private(set) var syncStatus: SyncStatus = .idle
    private(set) var refreshReport: RefreshReport?
    private(set) var courseSearch: CourseSearchSnapshot?
    var errorMessage: String?
    var showLogin = false
    var selectedSemester: Int
    var campus: Campus { didSet { UserDefaults.standard.set(campus.rawValue, forKey: "campus") } }
    var favorites: Set<String> { didSet { UserDefaults.standard.set(Array(favorites), forKey: "favorites") } }
    let client: any AcademicServing
    let balances: BalanceStore
    let accounts: AccountStore
    private let vault: any SessionVault
    private let cacheURL: URL
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var didRefreshOnLaunch = false
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var completionTask: Task<Void, Never>?
    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var refreshingAll = false
    private static var defaultCacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HFUTSchedule", isDirectory: true).appendingPathComponent("snapshot.json")
    }

    init(client: any AcademicServing = AcademicClient(), vault: (any SessionVault)? = nil,
         cacheURL: URL? = nil, initialSnapshot: AcademicSnapshot? = nil, demoMode: Bool? = nil,
         balances: BalanceStore? = nil, accounts: AccountStore? = nil) {
        self.client = client
        self.vault = vault ?? KeychainSessionVault()
        let resolvedCacheURL = cacheURL ?? Self.defaultCacheURL
        self.cacheURL = resolvedCacheURL
        let empty = AcademicSnapshot(semesterID: Semester(date: Date()).id)
        var initial = empty
        var loadingError: String?
        if demoMode ?? ProcessInfo.processInfo.arguments.contains("--demo") {
            initial = DemoData.snapshot()
        } else if let initialSnapshot {
            initial = initialSnapshot
        } else if FileManager.default.fileExists(atPath: resolvedCacheURL.path) {
            do {
                initial = try SnapshotCodec.decode(Data(contentsOf: resolvedCacheURL))
            } catch {
                initial = empty
                loadingError = "无法读取本地缓存：\(error.localizedDescription)"
            }
        }
        snapshot = initial
        let accounts = accounts ?? AccountStore(studentID: initial.studentID, demo: initial.isDemo)
        self.accounts = accounts
        self.balances = balances ?? BalanceStore(studentID: initial.studentID > 0 ? initial.studentID : accounts.studentID,
                                               demo: initial.isDemo, accounts: accounts)
        selectedSemester = initial.semesterID
        campus = Campus(rawValue: UserDefaults.standard.string(forKey: "campus") ?? "") ?? .hefei
        favorites = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? ["portal", "library", "news", "vpn"])
        errorMessage = loadingError
    }

    var week: Int {
        if let start = snapshot.semesterStart { return SchoolDate.week(on: Date(), start: start) }
        return snapshot.schedule.first(where: { $0.date == SchoolDate.string(Date()) })?.week ?? 1
    }

    var weekNumbers: [Int] {
        Array(Set(snapshot.schedule.map(\.week))).sorted()
    }

    /// A store is shared by all windows; entering the home page starts exactly one launch refresh.
    func refreshOnLaunch() async {
        guard !didRefreshOnLaunch else { return }
        didRefreshOnLaunch = true
        guard !snapshot.isDemo else { return }
        await refresh()
    }

    func connect(cookies: [HTTPCookie]) async -> Bool {
        guard !isBusy else { return false }
        completionTask?.cancel()
        isBusy = true
        syncStatus = .connecting
        isAuthenticated = false
        let token = generation
        defer { if token == generation { isBusy = false } }
        do {
            try vault.clear()
            await client.clearSession()
            await client.accept(cookies: cookies)
            let identity = try await client.identity()
            guard token == generation else { return false }
            if accounts.studentID == 0, let configured = accounts.summaries[.cas] {
                // A manual web login may select a different account from a preconfigured password.
                let profile = try await client.profile(studentID: identity.studentID)
                guard token == generation else { return false }
                guard !profile.number.isEmpty else { throw AcademicError.invalidResponse("登录账号") }
                if configured.account != profile.number { try accounts.clear(studentID: identity.studentID) }
            }
            try accounts.bind(studentID: identity.studentID)
            if snapshot.studentID != identity.studentID || snapshot.isDemo {
                if let message = balances.bind(studentID: identity.studentID) { errorMessage = message }
                snapshot = AcademicSnapshot(semesterID: selectedSemester, studentID: identity.studentID)
                persist()
            }
            let currentCookies = await client.currentCookies()
            guard token == generation else { return false }
            try vault.save(SavedAcademicSession(studentID: identity.studentID, cookies: currentCookies))
            isAuthenticated = true
            syncStatus = .idle
            return true
        } catch {
            if token == generation {
                errorMessage = error.localizedDescription
                syncStatus = .failed(message: error.localizedDescription, partial: false)
            }
            return false
        }
    }

    func loginCookies() async -> [HTTPCookie] {
        if let saved = try? vault.load(), snapshot.studentID == 0 || saved.studentID == snapshot.studentID {
            return saved.restoredCookies(studentID: saved.studentID)
        }
        return await client.currentCookies()
    }

    /// All pages share one coordinator. A full refresh also joins service-specific work.
    func refresh() async { await runRefresh(full: true) }

    func searchCourses(query: String) async {
        guard !isBusy, !snapshot.isDemo else { return }
        await runRefresh(full: false, query: CourseSearchRequest(query: query, page: 1, append: false))
    }

    func loadMoreCourses() async {
        guard !isBusy, let current = courseSearch, current.hasMore,
              current.studentID == snapshot.studentID, current.semesterID == selectedSemester else { return }
        await runRefresh(full: false, query: CourseSearchRequest(query: current.query, page: current.nextPage, append: true))
    }

    private func runRefresh(full: Bool, query: CourseSearchRequest? = nil) async {
        let token = generation
        if let task = refreshTask {
            let coversRequest = refreshingAll || !full
            await task.value
            guard token == generation, !Task.isCancelled else { return }
            if coversRequest { return }
            await runRefresh(full: full, query: query)
            return
        }
        if isBusy {
            await withCheckedContinuation { idleWaiters.append($0) }
            guard token == generation, !Task.isCancelled else { return }
            await runRefresh(full: full, query: query)
            return
        }
        guard !snapshot.isDemo, !Task.isCancelled else { return }
        completionTask?.cancel()
        let session = Result { try vault.load() }
        let hasSession: Bool
        switch session { case .success(let saved): hasSession = saved != nil; case .failure: hasSession = true }
        let hasAcademicAccount = isAuthenticated || snapshot.studentID > 0 || accounts.summaries[.cas] != nil || hasSession
        let semester = selectedSemester
        let search = query ?? (full ? courseSearch.flatMap {
            $0.studentID == snapshot.studentID ? CourseSearchRequest(query: $0.query, page: 1, append: false) : nil
        } : nil)
        let academic = (full && hasAcademicAccount ? SyncResource.academic : []) + (search != nil ? [.courseSearch] : [])
        let kinds = full ? BalanceKind.allCases.filter { balances.canRefresh($0) } : []
        let resources = academic + kinds.map { $0 == .campusCard ? SyncResource.campusCard : .shower }
        refreshReport = RefreshReport(resources: resources)
        guard !resources.isEmpty else {
            if let error = accounts.error { refreshReport?.addIssue(error) }
            if full, let error = balances.restorationError { refreshReport?.addIssue(error) }
            if let message = refreshReport?.failureMessage { syncStatus = .failed(message: message, partial: false) }
            else { syncStatus = .idle }
            return
        }
        isBusy = true
        refreshingAll = full
        syncStatus = .connecting
        let task = Task {
            await withTaskGroup(of: Void.self) { group in
                if !academic.isEmpty {
                    group.addTask { await self.performAcademicRefresh(resources: academic, token: token, semester: semester,
                                                                      session: session, search: search) }
                }
                for kind in kinds {
                    group.addTask {
                        let result = await self.balances.refresh(kind)
                        await self.record(kind == .campusCard ? .campusCard : .shower, outcome: result, token: token)
                    }
                }
            }
            guard token == self.generation else { return }
            if let error = self.accounts.error { self.refreshReport?.addIssue(error) }
            if full, let error = self.balances.restorationError { self.refreshReport?.addIssue(error) }
            self.refreshTask = nil
            self.refreshingAll = false
            self.isBusy = false
            guard !Task.isCancelled, let report = self.refreshReport else { self.syncStatus = .idle; return }
            if !report.isComplete {
                self.syncStatus = .failed(message: "部分数据未完成更新，请重试。", partial: report.successCount > 0)
            } else if report.onlyAcademicLoginFailed { self.syncStatus = .needsLogin }
            else if let message = report.failureMessage {
                self.syncStatus = .failed(message: message, partial: report.successCount > 0)
            } else if report.successCount > 0 { self.showUpdated(token: token) }
            else { self.syncStatus = .idle }
        }
        refreshTask = task
        await task.value
    }

    private func record(_ resource: SyncResource, outcome: SyncOutcome, token: Int) {
        guard token == generation, !Task.isCancelled, refreshReport != nil else { return }
        refreshReport?.record(resource, outcome: outcome)
        if let report = refreshReport { syncStatus = .updating(completed: report.completed, total: report.total) }
    }

    private func recordIssue(_ message: String, token: Int) {
        guard token == generation, !Task.isCancelled else { return }
        refreshReport?.addIssue(message)
    }

    private func performAcademicRefresh(resources: [SyncResource], token: Int, semester: Int,
                                        session: Result<SavedAcademicSession?, Error>, search: CourseSearchRequest?,
                                        canRenew: Bool = true) async {
        var pending = resources
        var mayRenew = canRenew
        do {
            var expectedStudentID = snapshot.studentID > 0 ? snapshot.studentID : accounts.studentID
            if !isAuthenticated {
                let saved = try session.get()
                if expectedStudentID == 0 { expectedStudentID = saved?.studentID ?? accounts.studentID }
                let cookies = saved?.restoredCookies(studentID: expectedStudentID) ?? []
                if cookies.isEmpty {
                    guard mayRenew, accounts.summaries[.cas]?.automaticLogin == true else {
                        let outcome = await authenticationFailure(AcademicError.sessionExpired, token: token)
                        for resource in pending { record(resource, outcome: outcome, token: token) }
                        return
                    }
                    mayRenew = false
                    try await renewAcademicSession(token: token)
                    guard token == generation else { return }
                } else { await client.accept(cookies: cookies) }
            }
            try Task.checkCancellation()
            let identity = try await client.identity()
            guard token == generation else { return }
            try Task.checkCancellation()
            guard expectedStudentID == 0 || identity.studentID == expectedStudentID else { throw AcademicError.credentialsRejected }
            try accounts.bind(studentID: identity.studentID)
            if let message = balances.bind(studentID: identity.studentID) { recordIssue(message, token: token) }
            // Revalidating the same session must not invalidate every snapshot reader.
            if snapshot.studentID != identity.studentID { snapshot.studentID = identity.studentID }
            isAuthenticated = true
            var expired: [SyncResource] = []
            var changedSnapshot = false
            let client = self.client
            await withTaskGroup(of: RefreshResult.self) { group in
                for resource in resources {
                    switch resource {
                    case .timetable:
                        group.addTask { .timetable(await capture { try await client.timetable(studentID: identity.studentID, businessID: identity.businessID, semesterID: semester) }) }
                    case .grades: group.addTask { .grades(await capture { try await client.grades(studentID: identity.studentID) }) }
                    case .exams: group.addTask { .exams(await capture { try await client.exams(studentID: identity.studentID) }) }
                    case .profile: group.addTask { .profile(await capture { try await client.profile(studentID: identity.studentID) }) }
                    case .program: group.addTask { .program(await capture { try await client.program(studentID: identity.studentID) }) }
                    case .courseSearch:
                        if let search {
                            group.addTask { .search(await capture { try await client.search(studentID: identity.studentID, semesterID: semester, name: search.query, page: search.page) }) }
                        }
                    default: break
                    }
                }
                for await result in group {
                    guard token == generation, !Task.isCancelled else { group.cancelAll(); continue }
                    if let error = result.error {
                        if error as? AcademicError == .sessionExpired { expired.append(result.resource) }
                        else { record(result.resource, outcome: .failure(message: error.localizedDescription), token: token) }
                        continue
                    }
                    switch result {
                    case .timetable(.success(let (summary, entries))):
                        snapshot.semesterID = semester; snapshot.courses = summary.courses; snapshot.schedule = entries
                        snapshot.semesterStart = summary.semesterStart
                    case .grades(.success(let value)): snapshot.grades = value
                    case .exams(.success(let value)): snapshot.exams = value
                    case .profile(.success(let value)): snapshot.profile = value
                    case .program(.success(let value)): snapshot.program = value
                    case .search(.success(let rows)):
                        if let search {
                            let previous = courseSearch
                            let canAppend = search.append && previous?.studentID == identity.studentID &&
                                previous?.semesterID == semester && previous?.query == search.query
                            let old = canAppend ? previous?.rows ?? [] : []
                            let seen = Set(old.map(\.id))
                            let added = rows.filter { !seen.contains($0.id) }
                            courseSearch = CourseSearchSnapshot(studentID: identity.studentID, semesterID: semester,
                                query: search.query, rows: old + added, nextPage: search.page + 1,
                                hasMore: !rows.isEmpty && !added.isEmpty)
                        }
                    default: break
                    }
                    if result.resource != .courseSearch { changedSnapshot = true }
                    record(result.resource, outcome: .success, token: token)
                }
            }
            guard token == generation else { return }
            try Task.checkCancellation()
            if changedSnapshot {
                snapshot.updatedAt = Date()
                if let message = persist(reportError: false) { recordIssue(message, token: token) }
            }
            if !expired.isEmpty {
                pending = expired
                guard mayRenew else { throw AcademicError.sessionExpired }
                mayRenew = false
                isAuthenticated = false
                try await renewAcademicSession(token: token)
                guard token == generation else { return }
                isAuthenticated = true
                await performAcademicRefresh(resources: expired, token: token, semester: semester,
                                             session: session, search: search, canRenew: false)
                return
            }
            let cookies = await client.currentCookies()
            guard token == generation else { return }
            do { try vault.save(SavedAcademicSession(studentID: identity.studentID, cookies: cookies)) }
            catch { recordIssue("保存登录会话失败：\(error.localizedDescription)", token: token) }
        } catch {
            guard token == generation, !Task.isCancelled else { return }
            if error as? AcademicError == .sessionExpired && mayRenew {
                isAuthenticated = false
                do {
                    try await renewAcademicSession(token: token)
                    guard token == generation else { return }
                    isAuthenticated = true
                    await performAcademicRefresh(resources: pending, token: token, semester: semester,
                                                 session: session, search: search, canRenew: false)
                    return
                } catch {
                    let outcome = await authenticationFailure(error, token: token)
                    for resource in pending { record(resource, outcome: outcome, token: token) }
                }
            } else {
                let outcome = await authenticationFailure(error, token: token)
                for resource in pending { record(resource, outcome: outcome, token: token) }
            }
        }
    }

    private func renewAcademicSession(token: Int) async throws {
        let credential = try accounts.credential(.cas)
        do { try await client.renewSession(account: credential?.account, password: credential?.password) }
        catch {
            guard token == generation else { throw CancellationError() }
            if error as? AcademicError == .verificationRequired || error as? AcademicError == .credentialsRejected {
                try accounts.pause(.cas)
            }
            throw error
        }
    }

    private func authenticationFailure(_ error: Error, token: Int) async -> SyncOutcome {
        guard token == generation, !Task.isCancelled else { return .skipped }
        let academicError = error as? AcademicError
        if let academicError, [.sessionExpired, .verificationRequired, .credentialsRejected].contains(academicError) {
            isAuthenticated = false
            let cookies = await client.currentCookies().filter { $0.domain == "cas.hfut.edu.cn" || $0.domain == ".cas.hfut.edu.cn" }
            guard token == generation else { return .skipped }
            await client.clearSession()
            guard token == generation else { return .skipped }
            await client.accept(cookies: cookies)
            guard token == generation else { return .skipped }
            do {
                let owner = snapshot.studentID > 0 ? snapshot.studentID : accounts.studentID
                if cookies.isEmpty || owner == 0 { try vault.clear() }
                else { try vault.save(SavedAcademicSession(studentID: owner, cookies: cookies)) }
                if academicError == .verificationRequired || academicError == .credentialsRejected { try accounts.pause(.cas) }
            } catch {
                return .failure(message: "\(academicError.localizedDescription)\n\(error.localizedDescription)", requiresLogin: true)
            }
            return .failure(message: academicError.localizedDescription, requiresLogin: true)
        }
        if error is CancellationError { return .skipped }
        return .failure(message: error.localizedDescription)
    }

    func configureAccount(_ system: AccountSystem, account: String, password: String) async throws {
        guard !isBusy, !snapshot.isDemo else { throw AcademicError.unavailable }
        let entered = account.trimmingCharacters(in: .whitespacesAndNewlines)
        if system == .cas {
            let previous = accounts.summaries[.cas]?.account ?? snapshot.profile.number
            if !previous.isEmpty && previous != entered {
                await signOut()
                guard accounts.summaries.isEmpty, accounts.studentID == 0 else { throw AcademicError.unavailable }
            }
        }
        isBusy = true
        defer { isBusy = false }
        if system == .cas {
            try accounts.save(system, account: entered, password: password)
            try vault.clear()
            await client.clearSession()
            isAuthenticated = false
            syncStatus = .idle
        } else {
            try accounts.save(system, account: entered, password: password)
            if let kind = system.balanceKind { balances.disconnect(kind) }
        }
    }

    func removeAccount(_ system: AccountSystem) async throws {
        guard !isBusy else { throw AcademicError.unavailable }
        isBusy = true
        defer { isBusy = false }
        try accounts.remove(system)
        if let kind = system.balanceKind { balances.disconnect(kind) }
        else {
            try vault.clear()
            await client.clearSession()
            isAuthenticated = false
            syncStatus = .needsLogin
        }
    }

    private func showUpdated(token: Int) {
        syncStatus = .updated
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self, token == self.generation, self.syncStatus == .updated else { return }
            self.syncStatus = .idle
        }
    }

    func loadProgram() async { await refresh() }

    private func cancelRefresh() {
        generation += 1
        refreshTask?.cancel(); refreshTask = nil
        refreshingAll = false; refreshReport = nil; courseSearch = nil
        completionTask?.cancel(); completionTask = nil
        syncStatus = .idle
        isBusy = false
    }

    func useDemo() {
        guard !isBusy else { return }
        cancelRefresh()
        do { try accounts.clear(); try vault.clear() }
        catch { errorMessage = error.localizedDescription; return }
        balances.reset(studentID: 0)
        snapshot = DemoData.snapshot()
        selectedSemester = snapshot.semesterID
        isAuthenticated = false
        Task { await client.clearSession() }
        persist()
    }

    func signOut() async {
        cancelRefresh()
        isBusy = true
        defer { isBusy = false }
        isAuthenticated = false
        do { try accounts.clear() } catch { errorMessage = error.localizedDescription }
        do { try vault.clear() } catch { errorMessage = error.localizedDescription }
        balances.reset(studentID: 0)
        await client.clearSession()
        snapshot = AcademicSnapshot(semesterID: Semester(date: Date()).id)
        selectedSemester = snapshot.semesterID
        do {
            if FileManager.default.fileExists(atPath: cacheURL.path) { try FileManager.default.removeItem(at: cacheURL) }
        } catch { errorMessage = "清除缓存失败：\(error.localizedDescription)" }
    }

    func toggleFavorite(_ service: CampusService) {
        if favorites.contains(service.id) { favorites.remove(service.id) } else { favorites.insert(service.id) }
    }

    func addEvent(_ event: PersonalEvent) { snapshot.events.append(event); persist() }
    func deleteEvent(_ id: UUID) { snapshot.events.removeAll { $0.id == id }; persist() }

    func exportSnapshot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HFUT-backup.json")
        try JSONEncoder().encode(snapshot).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    func exportCalendar() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HFUT-\(snapshot.semesterID).ics")
        try CalendarExport.render(snapshot.schedule).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func importSnapshot(from url: URL) throws {
        guard !isBusy else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 20_000_000 else { throw AcademicError.invalidResponse("备份文件大小") }
        let value = try SnapshotCodec.decode(Data(contentsOf: url))
        cancelRefresh()
        try accounts.clear(studentID: value.studentID)
        try vault.clear()
        balances.reset(studentID: value.studentID)
        snapshot = value
        selectedSemester = value.semesterID
        isAuthenticated = false
        Task { await client.clearSession() }
        persist()
    }

    @discardableResult
    private func persist(reportError: Bool = true) -> String? {
        do {
            let directory = cacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var protectedDirectory = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try protectedDirectory.setResourceValues(values)
            try JSONEncoder().encode(snapshot).write(to: cacheURL, options: [.atomic, .completeFileProtection])
            return nil
        } catch {
            let message = "保存本地数据失败：\(error.localizedDescription)"
            if reportError { errorMessage = message }
            return message
        }
    }
}

private func capture<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
    do { return .success(try await operation()) } catch { return .failure(error) }
}

struct CourseSearchSnapshot {
    let studentID: Int
    let semesterID: Int
    let query: String
    let rows: [Course]
    let nextPage: Int
    let hasMore: Bool
}

private struct CourseSearchRequest: Sendable {
    let query: String
    let page: Int
    let append: Bool
}

private enum RefreshResult: Sendable {
    case timetable(Result<(CourseSummary, [ScheduleEntry]), Error>)
    case grades(Result<[Grade], Error>)
    case exams(Result<[Exam], Error>)
    case profile(Result<StudentProfile, Error>)
    case program(Result<ProgramModule, Error>)
    case search(Result<[Course], Error>)

    var resource: SyncResource {
        switch self {
        case .timetable: .timetable; case .grades: .grades; case .exams: .exams
        case .profile: .profile; case .program: .program; case .search: .courseSearch
        }
    }
    var error: Error? {
        switch self {
        case .timetable(.failure(let error)), .grades(.failure(let error)), .exams(.failure(let error)),
             .profile(.failure(let error)), .program(.failure(let error)), .search(.failure(let error)): error
        default: nil
        }
    }
}
