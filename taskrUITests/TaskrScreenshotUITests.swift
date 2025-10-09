import XCTest

final class TaskrScreenshotUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shouldCapture = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        shouldCapture = environment["SKIP_SCREENSHOT_CAPTURE"] != "1"
        guard shouldCapture else {
            throw XCTSkip("Screenshot automation disabled via SKIP_SCREENSHOT_CAPTURE=1.")
        }

        app = XCUIApplication()
        app.launchEnvironment["SCREENSHOT_CAPTURE"] = "1"
        app.launchArguments.append("--uitests")
        app.launch()
    }

    override func tearDownWithError() throws {
        if shouldCapture {
            app.terminate()
        }
        app = nil
    }

    func testCaptureScreenshots() throws {
        try captureTasksScreenshot()
        try captureTemplatesScreenshot()
        try captureSettingsScreenshot()
    }

    private func captureTasksScreenshot() throws {
        let window = try mainWindow()
        tapHeaderButton("HeaderTasksButton")

        XCTAssertTrue(window.staticTexts["Launch Campaign"].waitForExistence(timeout: 2))

        try XCTContext.runActivity(named: "Tasks View") { _ in
            attachScreenshot(from: window, named: "01-Tasks")
        }
    }

    private func captureTemplatesScreenshot() throws {
        let window = try mainWindow()
        tapHeaderButton("HeaderTemplatesButton")

        XCTAssertTrue(window.staticTexts["Product Launch"].waitForExistence(timeout: 2))

        try XCTContext.runActivity(named: "Templates View") { _ in
            attachScreenshot(from: window, named: "02-Templates")
        }
    }

    private func captureSettingsScreenshot() throws {
        let window = try mainWindow()
        tapHeaderButton("HeaderSettingsButton")

        XCTAssertTrue(window.staticTexts["Launch Taskr at login"].waitForExistence(timeout: 2))

        try XCTContext.runActivity(named: "Settings View") { _ in
            attachScreenshot(from: window, named: "03-Settings")
        }
    }

    private func tapHeaderButton(_ identifier: String) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 2), "Expected header button \(identifier) to exist.")
        button.click()
    }

    private func mainWindow() throws -> XCUIElement {
        let window = app.windows["Taskr"]
        let exists = window.waitForExistence(timeout: 5)
        XCTAssertTrue(exists, "Expected Taskr window to exist for screenshot capture.")
        return window
    }

    private func attachScreenshot(from element: XCUIElement, named name: String) {
        let screenshot = element.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
