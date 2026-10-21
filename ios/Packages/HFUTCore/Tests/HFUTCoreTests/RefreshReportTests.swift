import XCTest
@testable import HFUTCore

final class RefreshReportTests: XCTestCase {
    func testCompletionWaitsForBalancesAndRetriesDoNotDoubleCount() {
        var report = RefreshReport(resources: SyncResource.academic + [.campusCard, .shower])
        for resource in SyncResource.academic { report.record(resource, outcome: .success) }
        XCTAssertEqual(report.completed, 5)
        XCTAssertFalse(report.isComplete)
        report.record(.campusCard, outcome: .failure(message: "offline"))
        report.record(.campusCard, outcome: .success)
        XCTAssertEqual(report.completed, 6)
        report.record(.shower, outcome: .success)
        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.successCount, 7)
        XCTAssertNil(report.failureMessage)
    }

    func testBalanceFailureAppearsInCombinedResult() {
        var report = RefreshReport(resources: [.grades, .shower])
        report.record(.grades, outcome: .success)
        report.record(.shower, outcome: .failure(message: "登录过期", requiresLogin: true))
        XCTAssertEqual(report.successCount, 1)
        XCTAssertEqual(report.failureMessage, "浴室余额：登录过期")
        XCTAssertFalse(report.requiresAcademicLogin)
        XCTAssertFalse(report.onlyAcademicLoginFailed)
    }

    func testMissingAcademicLoginDoesNotHideBalanceSuccess() {
        var report = RefreshReport(resources: SyncResource.academic + [.campusCard])
        for resource in SyncResource.academic { report.record(resource, outcome: .failure(message: "请登录", requiresLogin: true)) }
        XCTAssertTrue(report.onlyAcademicLoginFailed)
        report.record(.campusCard, outcome: .success)
        XCTAssertFalse(report.onlyAcademicLoginFailed)
        XCTAssertTrue(report.requiresAcademicLogin)
        XCTAssertEqual(report.failureMessage, "课表与学期课程、成绩、考试、个人信息、培养方案：请登录")
    }

    func testUnconfiguredResourcesAreNotRequiredAndStorageErrorsAreIncluded() {
        var report = RefreshReport(resources: [.shower, .shower])
        report.record(.grades, outcome: .success)
        XCTAssertEqual(report.total, 1)
        XCTAssertEqual(report.completed, 0)
        report.record(.shower, outcome: .success)
        report.addIssue("保存失败")
        XCTAssertEqual(report.failureMessage, "保存失败")
        XCTAssertTrue(RefreshReport(resources: []).isComplete)
        XCTAssertEqual(RefreshReport(resources: []).successCount, 0)
    }
}
