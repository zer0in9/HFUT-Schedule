import XCTest

final class LaunchTests: XCTestCase {
    func testLaunchAndRotate() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["聚在工大"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["添加课程"].exists)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.staticTexts["聚在工大"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Landscape schedule"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCUIDevice.shared.orientation = .portrait
    }
}
