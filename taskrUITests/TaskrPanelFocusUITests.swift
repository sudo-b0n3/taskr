import XCTest
import AppKit

final class TaskrPanelFocusUITests: XCTestCase {
    private let bundleID = "com.bone.taskr"
    private let resultFilename = "taskr_ui_panel_focus_result.txt"
    private lazy var resultURLs: [URL] = {
        let username = NSUserName()
        let hostBase = URL(fileURLWithPath: "/Users", isDirectory: true)
            .appendingPathComponent(username, isDirectory: true)
        let runnerHome = FileManager.default.homeDirectoryForCurrentUser
        let relativePath = ["Library", "Containers", bundleID, "Data", "tmp", resultFilename]
        func buildURL(base: URL) -> URL {
            relativePath.reduce(base) { partial, component in
                partial.appendingPathComponent(component, isDirectory: component != resultFilename)
            }
        }
        let hostURL = buildURL(base: hostBase)
        let runnerURL = buildURL(base: runnerHome)
        if hostURL == runnerURL {
            return [hostURL]
        }
        return [hostURL, runnerURL]
    }()

    func testPanelReopenKeepsKeyFocusSignal() {
        terminateExistingTaskrInstances()
        clearPanelFocusResultFile()

        let app = XCUIApplication()
        app.launchArguments.append("-UITestPanelReopenFocus")
        app.launch()

        let isForeground = app.wait(for: .runningForeground, timeout: 2)
        let isBackground = app.wait(for: .runningBackground, timeout: 0)
        XCTAssertTrue(isForeground || isBackground, "App did not launch successfully")

        let result = waitForPanelFocusResult(timeout: 8.0)
        XCTAssertEqual(result, "pass", "Expected panel reopen focus result to pass, got: \(result ?? "nil")")
    }

    private func terminateExistingTaskrInstances() {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for runningApp in apps {
            if !runningApp.terminate() {
                _ = runningApp.forceTerminate()
            }
        }
    }

    private func waitForPanelFocusResult(timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let result = readPanelFocusResult(), result != "pending" {
                return result
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return readPanelFocusResult()
    }

    private func readPanelFocusResult() -> String? {
        for url in resultURLs {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func clearPanelFocusResultFile() {
        let fileManager = FileManager.default
        for url in resultURLs {
            try? fileManager.removeItem(at: url)
        }
    }
}
