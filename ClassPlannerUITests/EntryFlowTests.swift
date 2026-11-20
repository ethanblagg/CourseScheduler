import XCTest

@MainActor
final class EntryFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
        }
    }

    private func button(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func hasFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    private func goBack(_ app: XCUIApplication) {
        app.buttons["BackButton"].firstMatch.tap()
    }

    func testFirstCourseEntry() {
        let app = launch()
        XCTAssertTrue(app.textFields["Plan name"].waitForExistence(timeout: 5))
        app.buttons["Add course"].tap()

        let code = app.textFields["Course code"]
        XCTAssertTrue(code.waitForExistence(timeout: 3))
        let focused = expectation(for: NSPredicate { _, _ in self.hasFocus(code) }, evaluatedWith: code)
        wait(for: [focused], timeout: 3)
        code.typeText("BIO 110")
        app.buttons["Monday"].tap()
        app.buttons["Wednesday"].tap()
        app.buttons["Start"].tap()
        app.buttons["End"].tap()
        XCTAssertFalse(app.staticTexts["End must be after start"].exists)
        XCTAssertGreaterThanOrEqual(app.buttons["Monday"].frame.height, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["Color: Blue"].frame.height, 44)
        capture(app, "01-first-course")

        app.buttons["Section"].tap()
        XCTAssertTrue(app.buttons["Section 02 options"].waitForExistence(timeout: 2))
        capture(app, "02-second-section")

        goBack(app)
        let finish = app.buttons["Finish BIO 110"]
        XCTAssertTrue(finish.waitForExistence(timeout: 2))
        finish.tap()
        XCTAssertTrue(app.buttons["Section 02 options"].waitForExistence(timeout: 2))
        capture(app, "03-finish-highlights-missing")
    }

    func testUnavailableTimeWithAnInlineError() {
        let app = launch()
        XCTAssertTrue(app.buttons["Add time"].waitForExistence(timeout: 5))
        app.buttons["Add time"].tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        let focused = expectation(for: NSPredicate { _, _ in self.hasFocus(name) }, evaluatedWith: name)
        wait(for: [focused], timeout: 3)
        name.typeText("Work")
        app.buttons["Tuesday"].tap()
        app.buttons["Start"].tap()
        app.buttons["End"].tap()

        XCTAssertEqual(app.datePickers["Start"].label, "Start")
        app.datePickers["Start"].buttons.firstMatch.tap()
        let hour = app.pickerWheels.element(boundBy: 0)
        XCTAssertTrue(hour.waitForExistence(timeout: 3))
        hour.adjust(toPickerWheelValue: "11")
        XCTAssertEqual(hour.value as? String, "11 o’clock")
        app.buttons["PopoverDismissRegion"].tap()
        XCTAssertTrue((app.datePickers["Start"].buttons.firstMatch.value as? String)?.hasPrefix("11:00") == true)
        XCTAssertTrue(app.staticTexts["End must be after start"].waitForExistence(timeout: 3))
        capture(app, "04-work-inline-error")

        goBack(app)
        XCTAssertTrue(app.staticTexts["Incomplete"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Finish Work"].exists)
    }

    func testPreviousCoursesCanBePickedChangedAndCopied() {
        let app = launch(["-seed-sample"])
        XCTAssertTrue(app.buttons["New plan"].waitForExistence(timeout: 5))
        app.buttons["New plan"].tap()
        app.buttons["Add course"].tap()

        let chemistry = button(app, startingWith: "CHEM 101")
        XCTAssertTrue(chemistry.waitForExistence(timeout: 3))
        XCTAssertTrue(button(app, startingWith: "MATH 120").exists)
        capture(app, "05-previous-courses")
        chemistry.tap()
        XCTAssertEqual(app.textFields["Course code"].value as? String, "CHEM 101")
        XCTAssertEqual(app.textFields["Name"].value as? String, "Chemistry")

        app.textFields["Course code"].tap()
        let math = button(app, startingWith: "MATH 120")
        XCTAssertTrue(math.waitForExistence(timeout: 2))
        math.tap()
        XCTAssertEqual(app.textFields["Course code"].value as? String, "MATH 120")

        let copy = app.buttons["Copy 1 section from Fall 2026"]
        XCTAssertTrue(copy.waitForExistence(timeout: 2))
        copy.tap()
        let tutorial = app.textFields.matching(NSPredicate(format: "value == 'Tutorial'")).firstMatch
        XCTAssertTrue(tutorial.waitForExistence(timeout: 2))
        app.buttons["Undo"].tap()
        XCTAssertFalse(tutorial.waitForExistence(timeout: 1))
    }

    func testDeletesCanBeUndone() {
        let app = launch(["-seed-sample"])
        XCTAssertTrue(button(app, startingWith: "Fall 2026").waitForExistence(timeout: 5))
        button(app, startingWith: "Fall 2026").tap()
        button(app, startingWith: "CHEM 101").tap()

        app.buttons["Section 01 options"].tap()
        app.buttons["Delete section"].tap()
        XCTAssertFalse(app.buttons["Section 01 options"].exists)
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 2))
        capture(app, "06-undo-toast")
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.buttons["Section 01 options"].waitForExistence(timeout: 2))

        let labs = app.textFields.matching(NSPredicate(format: "value == 'Lab'"))
        let visibleLabs = labs.count
        XCTAssertGreaterThan(visibleLabs, 0)
        app.buttons["Remove Lab"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Removed Lab"].waitForExistence(timeout: 2))
        app.buttons["Undo"].tap()
        XCTAssertFalse(app.staticTexts["Removed Lab"].waitForExistence(timeout: 1))
        XCTAssertEqual(labs.count, visibleLabs)

        let delete = app.buttons["Delete course"]
        for _ in 0..<8 where !(delete.exists && delete.isHittable) { app.swipeUp() }
        delete.tap()
        XCTAssertFalse(button(app, startingWith: "CHEM 101").waitForExistence(timeout: 1))
        app.buttons["Undo"].tap()
        XCTAssertTrue(button(app, startingWith: "CHEM 101").waitForExistence(timeout: 2))
    }

    func testLargerText() {
        let app = launch(["-seed-sample", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        XCTAssertTrue(button(app, startingWith: "Fall 2026").waitForExistence(timeout: 5))
        button(app, startingWith: "Fall 2026").tap()
        capture(app, "07-large-text-plan")
        button(app, startingWith: "CHEM 101").tap()
        XCTAssertTrue(app.buttons["Monday"].firstMatch.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Monday"].firstMatch.isHittable)
        capture(app, "08-large-text-course")
    }
}
