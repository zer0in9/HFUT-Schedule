import XCTest
import UIKit

/// CI-only: no real account, network access, or portal credentials required.
final class HFUTScheduleUITests: XCTestCase {
    func testDemoNavigationAndPersonalEvent() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        app.launch()
        XCTAssertTrue(app.navigationBars["聚在工大"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["演示模式 · 所有数据均为示例"].exists)

        selectTab("课表", in: app)
        XCTAssertTrue(app.navigationBars["我的课表"].exists)
        app.segmentedControls.buttons["周视图"].tap()
        XCTAssertTrue(app.staticTexts["周一"].exists)

        selectTab("教务", in: app)
        app.buttons["grades-link"].tap()
        XCTAssertTrue(app.navigationBars["成绩查询"].exists)
        XCTAssertTrue(app.staticTexts["程序设计基础"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        selectTab("校园", in: app)
        XCTAssertTrue(app.navigationBars["校园服务"].exists)
        XCTAssertTrue(app.links["图书馆"].firstMatch.exists || app.staticTexts["图书馆"].exists)

        selectTab("我的", in: app)
        let events = app.buttons["personal-events"]
        for _ in 0..<3 {
            if events.isHittable { break }
            app.swipeUp()
        }
        events.tap()
        app.buttons["添加日程"].tap()
        app.textFields["日程标题"].tap()
        app.textFields["日程标题"].typeText("CI meeting")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["CI meeting"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Native iOS personal event"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func selectTab(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title].firstMatch
        if tab.exists && tab.isHittable { tab.tap(); return }
        // iPad can present the native sidebar instead of a tab bar.
        let sidebarItem = app.buttons[title].firstMatch
        XCTAssertTrue(sidebarItem.waitForExistence(timeout: 5))
        sidebarItem.tap()
    }
}
