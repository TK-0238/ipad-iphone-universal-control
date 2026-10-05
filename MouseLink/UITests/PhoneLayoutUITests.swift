import XCTest
import UIKit

/// App layout on an iPhone simulator. This does NOT test the receiving iPhone's HID/IME.
final class PhoneLayoutUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { XCUIApplication().terminate(); XCUIDevice.shared.orientation = .portrait; super.tearDown() }
    private func launch(_ orientation: UIDeviceOrientation, large: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            app.buttons["panel-typing"].exists || app.buttons["open-panel"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        if app.buttons["open-panel"].exists { app.buttons["open-panel"].tap() }
        XCTAssertTrue(app.buttons["panel-typing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["panel-typing"].isHittable)
        XCTAssertTrue(app.buttons["panel-stop"].isHittable)
        XCTAssertFalse(app.buttons["panel-enable"].isEnabled)
        return app
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func checkTyping(_ app: XCUIApplication, text: String) {
        app.buttons["panel-typing"].tap()
        XCTAssertTrue(app.buttons["close-typing"].waitForExistence(timeout: 5))
        let field = app.descendants(matching: .any).matching(identifier: "typing-draft").firstMatch
        XCTAssertTrue(field.exists); field.tap(); field.typeText(text)
        XCTAssertFalse(app.buttons["send-text-enter"].isEnabled)
        XCTAssertFalse(app.buttons["remote-enter"].isEnabled)
        capture("phone-typing-\(text)")
        app.buttons["close-typing"].tap()
        XCTAssertTrue(app.buttons["panel-stop"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["panel-enable"].isEnabled)
    }
    func testPortraitPanelAndTyping() {
        let app = launch(.portrait)
        XCTAssertLessThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height)
        capture("phone-portrait-panel"); checkTyping(app, text: "portrait 123")
    }
    func testLandscapePanelAndTyping() {
        let app = launch(.landscapeLeft)
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 8), .completed)
        capture("phone-landscape-panel"); checkTyping(app, text: "landscape 123")
    }
    func testPortraitLargestTextCanOpenAndCloseTyping() {
        let app = launch(.portrait, large: true)
        capture("phone-large-text-panel")
        app.buttons["panel-typing"].tap()
        XCTAssertTrue(app.buttons["close-typing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["close-typing"].isHittable)
        capture("phone-large-text-typing")
        app.buttons["close-typing"].tap()
        XCTAssertTrue(app.buttons["panel-stop"].isHittable)
    }
}
