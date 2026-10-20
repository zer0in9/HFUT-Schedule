import SwiftUI
import HFUTCore

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var snapshot: AcademicSnapshot
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isBusy = false
    @Published private(set) var syncStatus: SyncStatus = .idle
    @Published var errorMessage: String?
    @Published var showLogin = false
    @Published var selectedSemester: Int
    @Published var campus: Campus { didSet { UserDefaults.standard.set(campus.rawValue, forKey: "campus") } }
    @Published var favorites: Set<String> { didSet { UserDefaults.standard.set(Array(favorites), forKey: "favorites") } }
    let client: any AcademicServing
    let balances: BalanceStore
    private let vault: any SessionVault
    private let cacheURL: URL
    private var generation = 0
    private var didRefreshOnLaunch = false
    private var refreshTask: Task<Void, Never>?
    private var completionTask: Task<Void, Never>?
    private static var defaultCacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HFUTSchedule", isDirectory: true).appendingPathComponent("snapshot.json")
    }

    init(client: any AcademicServing = AcademicClient(), vault: (any SessionVault)? = nil,
         cacheURL: URL? = nil, initialSnapshot: AcademicSnapshot? = nil, demoMode: Bool? = nil,
         balances: BalanceStore? = nil) {
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
        self.balances = balances ?? BalanceStore(studentID: initial.studentID, demo: initial.isDemo)
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
            if snapshot.studentID != identity.studentID || snapshot.isDemo {
                balances.reset(studentID: identity.studentID)
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

    /// Manual, pull-to-refresh and launch callers share the same in-flight operation.
    /// The store owns this task, so changing tabs doesn't cancel a launch refresh.
    func refresh() async {
        if let refreshTask { await refreshTask.value; return }
        guard !isBusy, !snapshot.isDemo else { return }
        completionTask?.cancel()
        isBusy = true
        syncStatus = .connecting
        let token = generation
        let semester = selectedSemester
        let task = Task {
            async let balanceRefresh: Void = self.balances.refresh()
            await self.performRefresh(token: token, semester: semester)
            await balanceRefresh
            if token == self.generation { self.isBusy = false; self.refreshTask = nil }
        }
        refreshTask = task
        await task.value
    }

    private func performRefresh(token: Int, semester: Int) async {
        do {
            var expectedStudentID = snapshot.studentID
            if !isAuthenticated {
                guard let saved = try vault.load() else {
                    syncStatus = snapshot.studentID > 0 ? .needsLogin : .idle
                    return
                }
                if expectedStudentID == 0 { expectedStudentID = saved.studentID }
                let cookies = saved.restoredCookies(studentID: expectedStudentID)
                guard !cookies.isEmpty else {
                    try vault.clear()
                    syncStatus = .needsLogin
                    return
                }
                await client.accept(cookies: cookies)
            }
            try Task.checkCancellation()
            let identity = try await client.identity()
            guard token == generation else { return }
            try Task.checkCancellation()
            guard identity.studentID == expectedStudentID else { throw AcademicError.sessionExpired }
            if balances.saved.studentID != identity.studentID { balances.reset(studentID: identity.studentID) }
            snapshot.studentID = identity.studentID
            isAuthenticated = true
            syncStatus = .updating(completed: 0, total: 4)
            var failures: [String] = []
            var succeeded = false
            var expired = false
            var completed = 0
            let client = self.client
            await withTaskGroup(of: RefreshResult.self) { group in
                group.addTask { .timetable(await capture { try await client.timetable(studentID: identity.studentID, businessID: identity.businessID, semesterID: semester) }) }
                group.addTask { .grades(await capture { try await client.grades(studentID: identity.studentID) }) }
                group.addTask { .exams(await capture { try await client.exams(studentID: identity.studentID) }) }
                group.addTask { .profile(await capture { try await client.profile(studentID: identity.studentID) }) }
                func record(_ error: Error, section: String) {
                    failures.append("\(section)：\(error.localizedDescription)")
                    if error as? AcademicError == .sessionExpired { expired = true }
                }
                for await result in group {
                    guard token == generation, !Task.isCancelled else { group.cancelAll(); continue }
                    switch result {
                    case .timetable(.success(let (summary, entries))):
                        snapshot.semesterID = semester; snapshot.courses = summary.courses; snapshot.schedule = entries
                        snapshot.semesterStart = summary.semesterStart; succeeded = true
                    case .timetable(.failure(let error)): record(error, section: "课表")
                    case .grades(.success(let value)): snapshot.grades = value; succeeded = true
                    case .grades(.failure(let error)): record(error, section: "成绩")
                    case .exams(.success(let value)): snapshot.exams = value; succeeded = true
                    case .exams(.failure(let error)): record(error, section: "考试")
                    case .profile(.success(let value)): snapshot.profile = value; succeeded = true
                    case .profile(.failure(let error)): record(error, section: "个人信息")
                    }
                    completed += 1
                    syncStatus = .updating(completed: completed, total: 4)
                }
            }
            guard token == generation else { return }
            try Task.checkCancellation()
            if succeeded { snapshot.updatedAt = Date() }
            if let message = persist(reportError: false) { failures.append(message) }
            if expired {
                isAuthenticated = false
                try vault.clear()
                await client.clearSession()
                guard token == generation else { return }
                syncStatus = .needsLogin
            } else {
                let cookies = await client.currentCookies()
                guard token == generation else { return }
                do { try vault.save(SavedAcademicSession(studentID: identity.studentID, cookies: cookies)) }
                catch { failures.append("保存登录会话失败：\(error.localizedDescription)") }
                if failures.isEmpty { showUpdated(token: token) }
                else { syncStatus = .failed(message: failures.joined(separator: "\n"), partial: succeeded) }
            }
        } catch {
            guard token == generation else { return }
            if error is CancellationError { syncStatus = .idle; return }
            if error as? AcademicError == .sessionExpired {
                isAuthenticated = false
                do { try vault.clear() } catch { /* Keep the sign-in prompt; the server still rejects the old session. */ }
                await client.clearSession()
                guard token == generation else { return }
                syncStatus = .needsLogin
            } else {
                syncStatus = .failed(message: error.localizedDescription, partial: false)
            }
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

    func loadProgram() async {
        guard isAuthenticated, !isBusy, !snapshot.isDemo else { return }
        completionTask?.cancel()
        isBusy = true
        syncStatus = .updating(completed: 0, total: 1)
        let token = generation
        defer { if token == generation { isBusy = false } }
        do {
            let program = try await client.program(studentID: snapshot.studentID)
            guard token == generation else { return }
            snapshot.program = program
            if let message = persist(reportError: false) { syncStatus = .failed(message: message, partial: true) }
            else { showUpdated(token: token) }
        } catch {
            guard token == generation else { return }
            if error as? AcademicError == .sessionExpired {
                isAuthenticated = false
                try? vault.clear()
                await client.clearSession()
                guard token == generation else { return }
                syncStatus = .needsLogin
            } else { syncStatus = .failed(message: error.localizedDescription, partial: false) }
        }
    }

    private func cancelRefresh() {
        generation += 1
        refreshTask?.cancel(); refreshTask = nil
        completionTask?.cancel(); completionTask = nil
        syncStatus = .idle
        isBusy = false
    }

    func useDemo() {
        guard !isBusy else { return }
        cancelRefresh()
        try? vault.clear()
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

private enum RefreshResult: Sendable {
    case timetable(Result<(CourseSummary, [ScheduleEntry]), Error>)
    case grades(Result<[Grade], Error>)
    case exams(Result<[Exam], Error>)
    case profile(Result<StudentProfile, Error>)
}
