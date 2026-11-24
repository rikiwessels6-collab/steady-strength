import XCTest

/// Switches program from Settings and checks Today follows. Saves screenshots to $SCREENSHOT_DIR when CI sets it.
final class ProgramSwitchUITests: XCTestCase {
    var dir: String?
    var count = 0

    func shot(_ app: XCUIApplication, _ name: String) {
        guard let dir else { return }
        count += 1
        let data = app.screenshot().pngRepresentation
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "switch-%02d-%@.png", count, name)))
    }

    func testSwitchingProgramUpdatesToday() {
        continueAfterFailure = false
        dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"]
        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemory", "-UITestBypassAuth"]
        app.launch()
        let next = app.buttons["onboardingNext"]
        func tapNext() { XCTAssertTrue(next.waitForExistence(timeout: 10)); next.tap() }

        tapNext()                                               // Welcome
        let accept = app.switches["acceptDisclaimer"]
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        accept.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        for _ in 0..<3 { tapNext() }                            // Health, Privacy, Lock
        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Sam")
        for _ in 0..<9 { tapNext() }                            // Profile ... Review -> Start my plan

        let nextSession = app.buttons["nextSession"]
        XCTAssertTrue(nextSession.waitForExistence(timeout: 10))
        XCTAssertTrue(nextSession.label.contains("Full Body A"), nextSession.label)
        shot(app, "today-before")

        app.tabBars.buttons["Settings"].firstMatch.tap()
        let change = app.buttons["changeProgram"]
        XCTAssertTrue(change.waitForExistence(timeout: 5))
        change.tap()

        let row = app.buttons["switch-ss-full-body-hypertrophy-2day"]
        var tries = 0
        while !(row.exists && row.isHittable) && tries < 15 { app.swipeUp(); tries += 1 }
        shot(app, "program-list")
        XCTAssertTrue(row.exists && row.isHittable, "Full Body Hypertrophy should be selectable")
        row.tap()

        let confirm = app.buttons["confirmSwitch"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        shot(app, "confirm-sheet")
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        sleep(1)
        shot(app, "after-confirm")

        app.tabBars.buttons["Today"].firstMatch.tap()
        XCTAssertTrue(nextSession.waitForExistence(timeout: 5))
        shot(app, "today-after")
        XCTAssertTrue(nextSession.label.contains("Full Body A"), nextSession.label)
        XCTAssertTrue(nextSession.label.contains("8 exercises"), "Today still shows: \(nextSession.label)")
    }
}
