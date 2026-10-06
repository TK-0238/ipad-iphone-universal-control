import XCTest
final class KeyboardUITests: XCTestCase {
    func testTypingAndEnterAreAvailableButOfflineCannotSend() {
        let app=XCUIApplication()
        app.launchArguments += ["-AppleLanguages","(ja)","-AppleLocale","ja_JP"]
        app.launch()
        XCTAssertTrue(app.buttons["open-typing"].waitForExistence(timeout:10))
        for _ in 0..<3 where !app.buttons["open-typing"].isHittable { app.swipeUp() }
        app.buttons["open-typing"].tap()
        XCTAssertTrue(app.navigationBars["文字入力・Enter"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["send-text-enter"].exists)
        XCTAssertFalse(app.buttons["send-text-enter"].isEnabled)
        XCTAssertTrue(app.buttons["remote-enter"].exists)
        XCTAssertFalse(app.buttons["remote-enter"].isEnabled)
        let form=XCTAttachment(screenshot:app.screenshot());form.name="MouseLink-typing-enter";form.lifetime = .keepAlways;add(form)
        let field=app.descendants(matching:.any).matching(identifier:"typing-draft").firstMatch
        XCTAssertTrue(field.exists);field.tap();field.typeText("hello 123")
        XCTAssertFalse(app.buttons["send-text-enter"].isEnabled)
        if app.buttons["キーボードを閉じる"].exists { app.buttons["キーボードを閉じる"].tap() }
        for _ in 0..<4 where !app.buttons["direct-keys"].isHittable { app.swipeUp() }
        app.buttons["direct-keys"].tap()
        let q=app.buttons["remote-char-q"]
        for _ in 0..<3 where !q.isHittable { app.swipeUp() }
        XCTAssertTrue(q.exists);XCTAssertFalse(q.isEnabled)
        let keys=XCTAttachment(screenshot:app.screenshot());keys.name="MouseLink-onscreen-keyboard";keys.lifetime = .keepAlways;add(keys)
        app.buttons["close-typing"].tap()
        XCTAssertTrue(app.navigationBars["MouseLink"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["start"].isEnabled)
    }
}
