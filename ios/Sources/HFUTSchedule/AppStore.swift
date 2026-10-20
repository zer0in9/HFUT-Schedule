import SwiftUI
import HFUTCore

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var snapshot: AcademicSnapshot
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    @Published var showLogin = false
    @Published var selectedSemester: Int
    @Published var campus: Campus { didSet { UserDefaults.standard.set(campus.rawValue, forKey: "campus") } }
    @Published var favorites: Set<String> { didSet { UserDefaults.standard.set(Array(favorites), forKey: "favorites") } }
    let client = AcademicClient()
    private var generation = 0
    private static var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HFUTSchedule", isDirectory: true).appendingPathComponent("snapshot.json")
    }

    init() {
        let empty = AcademicSnapshot(semesterID: Semester(date: Date()).id)
        var initial = empty
        var loadingError: String?
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            initial = DemoData.snapshot()
        } else if FileManager.default.fileExists(atPath: Self.cacheURL.path) {
            do {
                initial = try SnapshotCodec.decode(Data(contentsOf: Self.cacheURL))
            } catch {
                initial = empty
                loadingError = "无法读取本地缓存：\(error.localizedDescription)"
            }
        }
        snapshot = initial
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

    func connect(cookies: [HTTPCookie]) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        let token = generation
        do {
            await client.accept(cookies: cookies)
            let identity = try await client.identity()
            guard token == generation else { return false }
            // Never mix personal data across accounts or between demo and a real account.
            if snapshot.studentID != identity.studentID || snapshot.isDemo {
                snapshot = AcademicSnapshot(semesterID: selectedSemester, studentID: identity.studentID)
                persist()
            }
            isAuthenticated = true
            return true
        } catch {
            if token == generation { errorMessage = error.localizedDescription }
            return false
        }
    }

    func refresh() async {
        guard !isBusy, isAuthenticated, !snapshot.isDemo else { return }
        isBusy = true
        defer { isBusy = false }
        let token = generation
        let semester = selectedSemester
        do {
            let identity = try await client.identity()
            guard identity.studentID == snapshot.studentID else { throw AcademicError.sessionExpired }
            async let timetable = capture { try await self.client.timetable(studentID: identity.studentID, businessID: identity.businessID, semesterID: semester) }
            async let grades = capture { try await self.client.grades(studentID: identity.studentID) }
            async let exams = capture { try await self.client.exams(studentID: identity.studentID) }
            async let profile = capture { try await self.client.profile(studentID: identity.studentID) }
            let results = await (timetable, grades, exams, profile)
            guard token == generation else { return }
            var next = snapshot
            var failures: [String] = []
            var succeeded = false
            func record(_ error: Error, section: String) {
                failures.append("\(section)：\(error.localizedDescription)")
                if error as? AcademicError == .sessionExpired { isAuthenticated = false }
            }
            switch results.0 {
            case .success(let (summary, entries)):
                next.semesterID = semester; next.courses = summary.courses; next.schedule = entries
                next.semesterStart = summary.semesterStart; succeeded = true
            case .failure(let error): record(error, section: "课表")
            }
            switch results.1 {
            case .success(let value): next.grades = value; succeeded = true
            case .failure(let error): record(error, section: "成绩")
            }
            switch results.2 {
            case .success(let value): next.exams = value; succeeded = true
            case .failure(let error): record(error, section: "考试")
            }
            switch results.3 {
            case .success(let value): next.profile = value
            case .failure(let error): record(error, section: "个人信息")
            }
            if succeeded { next.updatedAt = Date() }
            snapshot = next
            persist()
            if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
        } catch {
            guard token == generation else { return }
            if error as? AcademicError == .sessionExpired { isAuthenticated = false }
            errorMessage = error.localizedDescription
        }
    }

    func loadProgram() async {
        guard isAuthenticated, !isBusy, !snapshot.isDemo else { return }
        isBusy = true
        defer { isBusy = false }
        let token = generation
        do {
            let program = try await client.program(studentID: snapshot.studentID)
            guard token == generation else { return }
            snapshot.program = program
            persist()
        } catch {
            guard token == generation else { return }
            if error as? AcademicError == .sessionExpired { isAuthenticated = false }
            errorMessage = error.localizedDescription
        }
    }

    func useDemo() {
        guard !isBusy else { return }
        generation += 1
        snapshot = DemoData.snapshot()
        selectedSemester = snapshot.semesterID
        isAuthenticated = false
        Task { await client.clearSession() }
        persist()
    }

    func signOut() async {
        generation += 1
        isAuthenticated = false
        await client.clearSession()
        snapshot = AcademicSnapshot(semesterID: Semester(date: Date()).id)
        selectedSemester = snapshot.semesterID
        do {
            if FileManager.default.fileExists(atPath: Self.cacheURL.path) { try FileManager.default.removeItem(at: Self.cacheURL) }
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
        generation += 1
        snapshot = value
        selectedSemester = value.semesterID
        isAuthenticated = false
        Task { await client.clearSession() }
        persist()
    }

    private func persist() {
        do {
            let directory = Self.cacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var protectedDirectory = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try protectedDirectory.setResourceValues(values)
            try JSONEncoder().encode(snapshot).write(to: Self.cacheURL, options: [.atomic, .completeFileProtection])
        } catch { errorMessage = "保存本地数据失败：\(error.localizedDescription)" }
    }
}

private func capture<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
    do { return .success(try await operation()) } catch { return .failure(error) }
}
