import XCTest

/// The food screens added in builds 30–33: coffee builder, restaurant menus, hard training days and
/// copying a whole day. Each test starts from a fresh in-memory store and goes through onboarding.
final class FoodUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestInMemory", "-UITestBypassAuth"]
        app.launch()
        onboard()
        app.tabBars.buttons["Food"].firstMatch.tap()
        XCTAssertTrue(app.buttons["add-breakfast"].waitForExistence(timeout: 10))
    }

    private func onboard() {
        let next = app.buttons["onboardingNext"]
        func tapNext() { XCTAssertTrue(next.waitForExistence(timeout: 10)); next.tap() }
        tapNext()                                               // Welcome
        let accept = app.switches["acceptDisclaimer"]
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        accept.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let name = app.textFields["nameField"]
        var taps = 0
        while !name.waitForExistence(timeout: 3) && taps < 6 { tapNext(); taps += 1 }   // Health, Privacy, Lock
        XCTAssertTrue(name.exists, "the profile step should appear")
        name.tap(); name.typeText("Sam")
        for _ in 0..<9 { tapNext() }                            // Profile ... Review -> Start my plan
        XCTAssertTrue(app.buttons["nextSession"].waitForExistence(timeout: 10))
    }

    private func waitUntil(_ element: XCUIElement, _ format: String, timeout: TimeInterval = 15) -> Bool {
        let e = expectation(for: NSPredicate(format: format), evaluatedWith: element)
        return XCTWaiter().wait(for: [e], timeout: timeout) == .completed
    }

    private func confirmPortion() {
        let add = app.buttons["addFoodConfirm"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "the portion sheet should open")
        add.tap()
        XCTAssertTrue(add.waitForNonExistence(timeout: 10))
    }

    private func text(_ contains: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", contains)).firstMatch
    }

    /// The number in the calorie ring ("1850, kcal left").
    private func caloriesLeft() -> Int? {
        let ring = app.descendants(matching: .any)["caloriesLeft"].firstMatch
        guard ring.waitForExistence(timeout: 5) else { return nil }
        return Int(ring.label.prefix { $0.isNumber || $0 == "," || $0 == "." || $0 == " " }.filter(\.isNumber))
    }

    func testCoffeeBuilderLogsACup() {
        app.buttons["add-breakfast"].tap()
        let coffee = app.buttons["coffee"]
        XCTAssertTrue(coffee.waitForExistence(timeout: 5))
        coffee.tap()
        let next = app.buttons["coffeeNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(next, "isEnabled == true"), "the food database should load")
        next.tap()
        confirmPortion()
        XCTAssertTrue(text("mL coffee").waitForExistence(timeout: 5), "the cup should be in breakfast")
    }

    func testRestaurantItemLogs() {
        app.buttons["add-lunch"].tap()
        let restaurants = app.buttons["restaurants"]
        XCTAssertTrue(restaurants.waitForExistence(timeout: 5))
        restaurants.tap()
        let chain = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Domino")).firstMatch
        XCTAssertTrue(chain.waitForExistence(timeout: 10), "Domino's should be listed")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("margherita classic")
        let row = app.buttons["menu-dominos-margherita-classic-crust"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "search should find the Domino's Margherita")
        row.tap()
        confirmPortion()
        XCTAssertTrue(app.staticTexts["Margherita, Classic Crust"].firstMatch.waitForExistence(timeout: 5), "the pizza should be in lunch")
    }

    func testHardDayRaisesTheTargetAndCanBeUndone() {
        guard let before = caloriesLeft() else { return XCTFail("no calorie ring") }
        let flame = app.buttons["hardDayToggle"].firstMatch
        XCTAssertTrue(flame.waitForExistence(timeout: 5))
        flame.tap()
        XCTAssertTrue(waitUntil(flame, "label CONTAINS '+200'", timeout: 5), flame.label)
        XCTAssertEqual(caloriesLeft(), before + 200)
        flame.tap()
        XCTAssertTrue(waitUntil(flame, "NOT (label CONTAINS '+200')", timeout: 5))
        XCTAssertEqual(caloriesLeft(), before)

        app.tabBars.buttons["Settings"].firstMatch.tap()
        let addBack = app.buttons["healthAddBack"].firstMatch
        var tries = 0
        while !addBack.exists && tries < 15 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(addBack.exists, "the Apple Health add-back setting should be in Settings")
    }

    func testCopyingYesterday() {
        app.buttons["Previous day"].tap()
        app.buttons["add-breakfast"].tap()
        let quick = app.buttons["quickAdd"]
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
        quick.tap()
        let kcal = app.textFields["quickKcal"]
        XCTAssertTrue(kcal.waitForExistence(timeout: 5))
        kcal.tap(); kcal.typeText("321")
        let what = app.textFields["What was it? (optional)"]
        what.tap(); what.typeText("Test porridge")
        app.buttons["quickSave"].tap()
        XCTAssertTrue(app.staticTexts["Test porridge"].firstMatch.waitForExistence(timeout: 5))

        app.buttons["Next day"].tap()
        XCTAssertFalse(app.staticTexts["Test porridge"].firstMatch.exists)
        let copy = app.buttons["copyDay"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        XCTAssertTrue(copy.label.contains("yesterday"), copy.label)
        copy.tap()
        XCTAssertTrue(app.staticTexts["Test porridge"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(copy.exists, "the button goes once the day has food")
    }
}
