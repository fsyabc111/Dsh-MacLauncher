import XCTest

final class DshMacLauncherUITests: XCTestCase {
    func testFirstRunShowsOnboarding() {
        let application = XCUIApplication()
        application.launchEnvironment["DSH_UI_TEST_MODE"] = "1"
        application.launchEnvironment["DSH_RUNTIME_MANIFEST_URL"] = "file:///nonexistent/runtime-manifest.json"
        application.launch()

        XCTAssertTrue(application.staticTexts["DSH Launcher"].waitForExistence(timeout: 5))
        XCTAssertTrue(application.buttons["下载并安装"].exists)
        XCTAssertTrue(application.buttons["选择…"].exists)
        XCTAssertTrue(application.buttons["完成并启动"].exists)
    }
}

