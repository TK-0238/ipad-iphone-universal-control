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
    private func finishKeyboardOnboardingIfPresent(_ app: XCUIApplication) {
        // Only the known first-use keyboard tutorial, identified in the failure's
        // accessibility tree. This is a disposable simulator, not a user device.
        let intro = app.otherElements["UIContinuousPathIntroductionView"]
        guard intro.waitForExistence(timeout: 2) else { return }
        capture("phone-keyboard-first-use")
        let orientation = XCUIDevice.shared.orientation
        // The first-use keyboard window reported portrait coordinates while the app
        // was landscape. Finish setup in portrait, then restore the tested orientation.
        if orientation.isLandscape { XCUIDevice.shared.orientation = .portrait }
        let next = intro.buttons.matching(NSPredicate(format:
            "label == 'Continue' OR label == '続ける' OR label == '続行'")).firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            app.windows.firstMatch.frame.width < app.windows.firstMatch.frame.height && next.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        next.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in !intro.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 8), .completed)
        if orientation.isLandscape {
            XCUIDevice.shared.orientation = orientation
            let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
                app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 8), .completed)
        }
        capture("phone-keyboard-ready")
    }
    private func checkTyping(_ app: XCUIApplication, text: String) {
        app.buttons["panel-typing"].tap()
        XCTAssertTrue(app.buttons["close-typing"].waitForExistence(timeout: 5))
        let field = app.descendants(matching: .any).matching(identifier: "typing-draft").firstMatch
        XCTAssertTrue(field.exists); field.tap()
        finishKeyboardOnboardingIfPresent(app)
        field.tap(); field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
        XCTAssertFalse(app.buttons["send-text-enter"].isEnabled)
        // With keyboard setup completed, use the app's own accessory to dismiss.
        // No return/submit key is synthesized and no remote input is authorized.
        let keyboardClose = app.buttons["キーボードを閉じる"]
        XCTAssertTrue(keyboardClose.waitForExistence(timeout: 5))
        keyboardClose.tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            !app.keyboards.firstMatch.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 8), .completed)
        capture("phone-typing-\(text)")
        // LazyVGrid has no accessibility nodes for off-screen keys in a short
        // landscape viewport. Scroll the actual typing sheet, not its background pad.
        let scroll = app.scrollViews.containing(.any, identifier: "typing-draft").firstMatch
        XCTAssertTrue(scroll.exists)
        let enter = app.buttons["remote-enter"]
        let screen = app.windows.firstMatch.frame
        let headerBottom = app.navigationBars["文字入力・Enter"].frame.maxY
        for _ in 0..<6 {
            if enter.exists, enter.frame.minY >= headerBottom, enter.frame.maxY <= screen.maxY - 20 { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(enter.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(enter.frame.minY, headerBottom)
        XCTAssertLessThanOrEqual(enter.frame.maxY, screen.maxY - 20)
        XCTAssertGreaterThanOrEqual(enter.frame.minX, screen.minX)
        XCTAssertLessThanOrEqual(enter.frame.maxX, screen.maxX)
        XCTAssertFalse(enter.isEnabled)
        capture("phone-enter-controls-\(text)")
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
