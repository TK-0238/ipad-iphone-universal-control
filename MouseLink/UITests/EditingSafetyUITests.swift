import XCTest
final class EditingSafetyUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }
    private func openTyping(large:Bool=false) -> XCUIApplication {
        let app=XCUIApplication();app.launchArguments += ["-AppleLanguages","(ja)","-AppleLocale","ja_JP"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch();XCTAssertTrue(app.buttons["open-typing"].waitForExistence(timeout:15))
        for _ in 0..<5 where !app.buttons["open-typing"].isHittable { app.swipeUp() }
        app.buttons["open-typing"].tap();XCTAssertTrue(app.buttons["close-typing"].waitForExistence(timeout:5));return app
    }
    private func capture(_ app:XCUIApplication,_ name:String) {
        let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot());image.name=name;image.lifetime = .keepAlways;add(image)
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
        let app=openTyping()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 10), .completed)
        let window = app.windows.firstMatch.frame
        let close = app.buttons["close-typing"]
        XCTAssertTrue(close.isHittable)
        XCTAssertTrue(window.contains(close.frame))
        for _ in 0..<5 where !app.buttons["remote-enter"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["remote-enter"].exists);XCTAssertFalse(app.buttons["remote-enter"].isEnabled)
        XCTAssertTrue(window.intersects(app.buttons["remote-enter"].frame))
        let enterFrame = app.buttons["remote-enter"].frame
        let geometry = XCTAttachment(string: "Application: \(app.frame); window: \(window); close: \(close.frame); Enter: \(enterFrame)")
        geometry.name = "qa-landscape-geometry"; geometry.lifetime = .keepAlways; add(geometry)
        capture(app,"qa-landscape-full-screen")
    }
    func testAccessibilityTextSizeCanCloseTypingScreen() {
        let app=openTyping(large:true)
        XCTAssertTrue(app.buttons["close-typing"].isHittable)
        capture(app,"qa-large-text")
        let field = app.descendants(matching: .any).matching(identifier: "typing-draft").firstMatch
        // The typing form is a sheet. A full-application swipe can jump over the field.
        // Use short gestures inside its own scroll view, and reverse direction if needed.
        let scroll = app.scrollViews.containing(.any, identifier: "typing-draft").firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for _ in 0..<24 {
            if field.isHittable { break }
            let rect = field.frame, viewport = scroll.frame
            let down = !rect.isEmpty && rect.midY < viewport.midY
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: down ? 0.35 : 0.65))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: down ? 0.55 : 0.45))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        let positions = XCTAttachment(string: "scroll=\(scroll.frame) field=\(field.frame) hittable=\(field.isHittable)")
        positions.name="qa-large-text-field-geometry"; positions.lifetime = .keepAlways; add(positions)
        capture(app,"qa-large-text-field-visible")
        XCTAssertTrue(field.isHittable)
        field.tap(); field.typeText("A")
        XCTAssertTrue((field.value as? String)?.contains("A") == true)
        if app.buttons["キーボードを閉じる"].isHittable { app.buttons["キーボードを閉じる"].tap() }
        capture(app,"qa-large-text-editable")
        app.buttons["close-typing"].tap();XCTAssertTrue(app.navigationBars["MouseLink"].waitForExistence(timeout:5))
    }
}
