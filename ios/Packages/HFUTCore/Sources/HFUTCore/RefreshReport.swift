import Foundation

public enum SyncResource: String, CaseIterable, Identifiable, Sendable {
    case timetable, grades, exams, profile, program, campusCard, shower, courseSearch
    public var id: String { rawValue }
    public static let academic: [Self] = [.timetable, .grades, .exams, .profile, .program]
    public var title: String {
        switch self {
        case .timetable: "课表与学期课程"
        case .grades: "成绩"
        case .exams: "考试"
        case .profile: "个人信息"
        case .program: "培养方案"
        case .campusCard: "校园卡余额"
        case .shower: "浴室余额"
        case .courseSearch: "开课查询"
        }
    }
}

public enum SyncOutcome: Equatable, Sendable {
    case success
    case failure(message: String, requiresLogin: Bool = false)
    case skipped
}

/// One result per planned resource, regardless of retries or completion order.
public struct RefreshReport: Equatable, Sendable {
    public let resources: [SyncResource]
    public private(set) var outcomes: [SyncResource: SyncOutcome] = [:]
    public private(set) var issues: [String] = []
    public init(resources: [SyncResource]) {
        var seen: Set<SyncResource> = []
        self.resources = resources.filter { seen.insert($0).inserted }
    }
    public mutating func record(_ resource: SyncResource, outcome: SyncOutcome) {
        guard resources.contains(resource) else { return }
        outcomes[resource] = outcome
    }
    public mutating func addIssue(_ message: String) {
        if !issues.contains(message) { issues.append(message) }
    }
    public var completed: Int { outcomes.count }
    public var total: Int { resources.count }
    public var isComplete: Bool { completed == total }
    public var successCount: Int { outcomes.values.filter { $0 == .success }.count }
    public var requiresAcademicLogin: Bool {
        outcomes.contains { resource, outcome in
            guard SyncResource.academic.contains(resource) || resource == .courseSearch,
                  case .failure(_, true) = outcome else { return false }
            return true
        }
    }
    public var onlyAcademicLoginFailed: Bool {
        guard issues.isEmpty, successCount == 0 else { return false }
        let failures = outcomes.filter { if case .failure = $0.value { return true }; return false }
        return !failures.isEmpty && failures.allSatisfy { resource, outcome in
            guard SyncResource.academic.contains(resource) || resource == .courseSearch,
                  case .failure(_, true) = outcome else { return false }
            return true
        }
    }
    public var failureMessage: String? {
        var grouped: [(message: String, names: [String])] = []
        for resource in resources {
            guard case .failure(let message, _) = outcomes[resource] else { continue }
            if let index = grouped.firstIndex(where: { $0.message == message }) {
                grouped[index].names.append(resource.title)
            } else { grouped.append((message, [resource.title])) }
        }
        let lines = grouped.map { "\($0.names.joined(separator: "、"))：\($0.message)" } + issues
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
