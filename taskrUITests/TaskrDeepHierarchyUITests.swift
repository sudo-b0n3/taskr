import XCTest

final class TaskrDeepHierarchyUITests: XCTestCase {
    func testDeepHierarchyClearDoesNotCrash() {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestDeepClear", "18"]
        app.launch()

        let isForeground = app.wait(for: .runningForeground, timeout: 2)
        let isBackground = app.wait(for: .runningBackground, timeout: 0)
        XCTAssertTrue(isForeground || isBackground, "App did not launch successfully")

        RunLoop.current.run(until: Date().addingTimeInterval(2))

        XCTAssertNotEqual(app.state, .notRunning, "App terminated unexpectedly during deep clear automation")
    }
}
