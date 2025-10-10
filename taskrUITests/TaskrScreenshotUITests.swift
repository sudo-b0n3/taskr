import Foundation
import XCTest

final class TaskrScreenshotUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shouldCapture = false
    private var themeOverride: String?
    private lazy var automationConfigURLs: [URL] = {
        let username = NSUserName()
        let hostBase = URL(fileURLWithPath: "/Users", isDirectory: true)
            .appendingPathComponent(username, isDirectory: true)
        let runnerHome = FileManager.default.homeDirectoryForCurrentUser
        let relativePath = ["Library", "Containers", "com.bone.taskr", "Data", "tmp", "taskr_screenshot_config.json"]
        func buildURL(base: URL) -> URL {
            relativePath.reduce(base) { partial, component in
                partial.appendingPathComponent(component, isDirectory: component != "taskr_screenshot_config.json")
            }
        }
        let hostURL = buildURL(base: hostBase)
        let runnerURL = buildURL(base: runnerHome)
        if hostURL == runnerURL {
            return [hostURL]
        }
        return [hostURL, runnerURL]
    }()

    private struct AutomationConfig: Decodable {
        let capture: Bool
        let theme: String?
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        shouldCapture = environment["SCREENSHOT_CAPTURE"] == "1" || environment["SIMCTL_CHILD_SCREENSHOT_CAPTURE"] == "1"
        var configTheme: String?
        if let data = automationConfigURLs.compactMap({ try? Data(contentsOf: $0) }).first,
           let config = try? JSONDecoder().decode(AutomationConfig.self, from: data) {
            if !shouldCapture {
                shouldCapture = config.capture
            }
            configTheme = config.theme
        }
        guard shouldCapture else {
            throw XCTSkip("Screenshot automation disabled (set SCREENSHOT_CAPTURE=1 to enable).")
        }

        themeOverride = environment["SCREENSHOT_THEME"] ?? configTheme

        app = XCUIApplication()
        app.launchEnvironment["SCREENSHOT_CAPTURE"] = "1"
        if let themeOverride {
            app.launchEnvironment["SCREENSHOT_THEME"] = themeOverride
        }
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
