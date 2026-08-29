import XCTest

/// Walks the product's whole story — station → pass → frame → satellite —
/// asserting each screen's real content before capturing it. The captures
/// feed the App Store screenshots and the review demo video.
final class DemoWalk: XCTestCase {
    func testWalk() throws {
        let app = XCUIApplication()
        app.launch()

        // Station list → a busy station with a real baseline
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20), "no station list")
        search.tap()
        search.typeText("UX5UL")
        let row = app.staticTexts["UX5UL-KO50ei"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "station not found")
        sleep(2)
        row.tap()

        // Station page: verdict + baseline must be REAL before we shoot it
        let baseline = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'baseline'")).firstMatch
        XCTAssertTrue(baseline.waitForExistence(timeout: 25), "no health card")
        sleep(4)
        shoot(app, "1-station")
        sleep(2)

        // Recent passes → a pass that heard frames AND decoded fields from
        // them. Live data shifts between runs, so hunt through the heard
        // passes instead of trusting the first.
        app.swipeUp()
        sleep(1)
        var frameRow: XCUIElement?
        for i in 0..<5 {
            let rows = app.buttons.matching(
                NSPredicate(format: "label CONTAINS ' frames'"))
            guard rows.count > i else { break }
            rows.element(boundBy: i).tap()
            let timeline = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'position in the pass'")).firstMatch
            XCTAssertTrue(timeline.waitForExistence(timeout: 25), "no timeline")
            sleep(3)
            let candidate = app.buttons.matching(
                NSPredicate(format: "label CONTAINS 'fields decoded'")).firstMatch
            if candidate.waitForExistence(timeout: 6) {
                shoot(app, "2-pass")
                sleep(2)
                frameRow = candidate
                break
            }
            app.navigationBars.buttons.firstMatch.tap()   // back, try the next
            sleep(2)
            app.swipeUp()
        }
        guard let frameRow else {
            XCTFail("no pass with decoded frames among the recent five")
            return
        }
        sleep(1)
        frameRow.tap()
        sleep(4)
        XCTAssertTrue(app.cells.count > 2 || app.staticTexts.count > 6,
                      "frame view empty")
        shoot(app, "3-frame")
        // the finale must be SEEN, not implied: linger, browse the values,
        // linger again — the first cut ended before a viewer could register
        // where the story landed
        app.swipeUp()
        sleep(3)
        app.swipeDown()
        sleep(4)
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
