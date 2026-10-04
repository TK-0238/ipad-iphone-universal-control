import XCTest
final class EditingSafetyUITests: XCTestCase {
    private func openTyping(large:Bool=false) -> XCUIApplication {
        let app=XCUIApplication();app.launchArguments += ["-AppleLanguages","(ja)","-AppleLocale","ja_JP"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch();XCTAssertTrue(app.buttons["open-typing"].waitForExistence(timeout:15))
        for _ in 0..<5 where !app.buttons["open-typing"].isHittable { app.swipeUp() }
        app.buttons["open-typing"].tap();XCTAssertTrue(app.buttons["close-typing"].waitForExistence(timeout:5));return app
    }
    private func capture(_ app:XCUIApplication,_ name:String) {
        let image=XCTAttachment(screenshot:app.screenshot());image.name=name;image.lifetime = .keepAlways;add(image)
    }
    func testDraftSurvivesCloseAndReopenWithoutAnyAutomaticSending() {
        let app=openTyping();let field=app.descendants(matching:.any).matching(identifier:"typing-draft").firstMatch
        field.tap();field.typeText("safe local draft")
        if app.buttons["キーボードを閉じる"].isHittable { app.buttons["キーボードを閉じる"].tap() }
        app.buttons["close-typing"].tap();app.buttons["open-typing"].tap()
        XCTAssertTrue(field.waitForExistence(timeout:5));XCTAssertTrue((field.value as? String)?.contains("safe local draft")==true)
        XCTAssertFalse(app.buttons["send-text-enter"].isEnabled);XCTAssertFalse(app.buttons["remote-enter"].isEnabled)
        capture(app,"qa-draft-preserved")
    }
    func testOversizedDraftShowsErrorAndCanBeCleared() {
        let app=openTyping();let field=app.descendants(matching:.any).matching(identifier:"typing-draft").firstMatch
        field.tap();field.typeText(String(repeating:"a",count:257))
        XCTAssertTrue(app.staticTexts["draft-error"].waitForExistence(timeout:5))
        if app.buttons["キーボードを閉じる"].isHittable { app.buttons["キーボードを閉じる"].tap() }
        capture(app,"qa-draft-too-long")
        app.buttons["下書きを消去"].tap();XCTAssertFalse(app.staticTexts["draft-error"].exists)
        XCTAssertFalse(app.buttons["send-text-enter"].isEnabled)
    }
    func testLandscapeTypingAndEnterRemainAccessible() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app=openTyping()
        XCTAssertTrue(app.buttons["close-typing"].isHittable)
        for _ in 0..<5 where !app.buttons["remote-enter"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["remote-enter"].exists);XCTAssertFalse(app.buttons["remote-enter"].isEnabled)
        capture(app,"qa-landscape")
    }
    func testAccessibilityTextSizeCanCloseTypingScreen() {
        let app=openTyping(large:true)
        XCTAssertTrue(app.buttons["close-typing"].isHittable)
        capture(app,"qa-large-text")
        app.buttons["close-typing"].tap();XCTAssertTrue(app.navigationBars["MouseLink"].waitForExistence(timeout:5))
    }
}
