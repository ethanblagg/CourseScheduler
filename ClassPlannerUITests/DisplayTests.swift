import XCTest

@MainActor
final class DisplayTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.appearance = .light
    }

    override func tearDown() {
        XCUIDevice.shared.appearance = .light
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-seed-display"] + arguments
        app.launch()
        let plan = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Display test'")).firstMatch
        XCTAssertTrue(plan.waitForExistence(timeout: 5))
        plan.tap()
        let schedules = app.buttons["1 schedule fits"]
        XCTAssertTrue(schedules.waitForExistence(timeout: 5))
        schedules.tap()
        XCTAssertTrue(app.staticTexts["1 schedule fits"].waitForExistence(timeout: 5))
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

    private func dismissSheet(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
    }

    func testWeekShowsEveryMeetingAtItsTime() {
        let app = launch()
        let early = app.buttons["ENVS 1015, Section 01 · Lecture, Monday 7:30–8:20 AM"]
        let lecture = app.buttons["MATH 120, Section 01 · Lecture, Wednesday 11 AM–12 PM"]
        let tutorial = app.buttons["MATH 120, Section 01 · Tutorial, Wednesday 12–12:15 PM"]
        let lab = app.buttons["BIO 110, Section 01 · Lab, Saturday 9 AM–12 PM"]
        let late = app.buttons["ART 240, Section 01 · Studio, Thursday 7–9:40 PM"]
        let work = app.buttons["Work, unavailable, Tuesday 1–6 PM"]
        for element in [early, lecture, tutorial, lab, late, work] {
            XCTAssertTrue(element.waitForExistence(timeout: 3), element.description)
            XCTAssertGreaterThanOrEqual(element.frame.minX, 0)
            XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX)
        }
        let ratio = lecture.frame.height / tutorial.frame.height
        XCTAssertTrue((3.5...4.7).contains(ratio), "60- vs 15-minute heights: \(ratio)")
        XCTAssertLessThan(early.frame.minY, lecture.frame.minY)
        XCTAssertEqual(tutorial.frame.minY, lecture.frame.maxY, accuracy: 2)
        XCTAssertGreaterThan(late.frame.minY, work.frame.maxY)
        XCTAssertTrue(app.otherElements["Saturday"].exists && app.otherElements["Sunday"].exists)
        capture(app, "10-week")

        app.buttons["Calendar options"].tap()
        let weekends = app.switches["Weekends"]
        XCTAssertTrue(weekends.waitForExistence(timeout: 2))
        weekends.switches.firstMatch.tap()
        dismissSheet(app)
        XCTAssertFalse(app.otherElements["Sunday"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.otherElements["Saturday"].exists)
        capture(app, "11-week-no-weekends")

        app.buttons["Calendar options"].tap()
        XCTAssertTrue(app.switches["Weekends"].waitForExistence(timeout: 2))
        app.switches["Weekends"].switches.firstMatch.tap()
        app.buttons["Sun"].tap()
        dismissSheet(app)
        XCTAssertTrue(app.otherElements["Sunday"].waitForExistence(timeout: 2))
        XCTAssertLessThan(app.otherElements["Sunday"].frame.minX, app.otherElements["Monday"].frame.minX)
        capture(app, "12-week-starts-sunday")

        app.buttons["Agenda"].tap()
        XCTAssertTrue(app.buttons["ART 240, Section 01 · Studio, Thursday 7–9:40 PM"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Introduction to Environmental Science and Sustainability"].exists == false)
        capture(app, "13-agenda")
    }

    func testEventDetailChangesColorAndOpensTheEditor() {
        let app = launch()
        let lecture = app.buttons["MATH 120, Section 01 · Lecture, Wednesday 11 AM–12 PM"]
        XCTAssertTrue(lecture.waitForExistence(timeout: 3))
        lecture.tap()
        let dot = app.buttons["Color: Blue"]
        XCTAssertTrue(dot.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Section 01 · Lecture"].exists)
        dot.tap()
        let purple = app.buttons["Purple"]
        XCTAssertTrue(purple.waitForExistence(timeout: 2))
        purple.tap()
        XCTAssertTrue(app.buttons["Color: Purple"].waitForExistence(timeout: 2))
        capture(app, "14-event-detail")

        app.buttons["Edit"].tap()
        XCTAssertTrue(app.textFields["Course code"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["Course code"].value as? String, "MATH 120")
        XCTAssertTrue(app.buttons["Color: Purple"].exists)
        app.buttons["BackButton"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["1 schedule fits"].waitForExistence(timeout: 3))
    }

    func testDarkAppearance() {
        XCUIDevice.shared.appearance = .dark
        let app = launch()
        XCTAssertTrue(app.buttons["Work, unavailable, Tuesday 1–6 PM"].waitForExistence(timeout: 3))
        capture(app, "15-week-dark")
        app.buttons["Agenda"].tap()
        capture(app, "16-agenda-dark")
    }

    func testLargerText() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        let early = app.buttons["ENVS 1015, Section 01 · Lecture, Monday 7:30–8:20 AM"]
        XCTAssertTrue(early.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(early.frame.maxX, app.frame.maxX)
        capture(app, "17-week-large-text")
        app.buttons["Agenda"].tap()
        XCTAssertTrue(app.buttons["ENVS 1015, Section 01 · Lecture, Monday 7:30–8:20 AM"].waitForExistence(timeout: 2))
        capture(app, "18-agenda-large-text")
    }
}
