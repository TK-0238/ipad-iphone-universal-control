import XCTest
final class MouseLinkUITests: XCTestCase {
    func testNoAutomaticInputAndGuideAvailable() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        XCTAssertTrue(app.navigationBars["MouseLink"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["start"].exists)
        XCTAssertFalse(app.buttons["start"].isEnabled)
        XCTAssertTrue(app.buttons["advertise"].exists)
        let start = XCTAttachment(screenshot: app.screenshot()); start.name = "MouseLink-start"; start.lifetime = .keepAlways; add(start)
        for _ in 0..<3 where !app.buttons["guide"].isHittable { app.swipeUp() }
        app.buttons["guide"].tap()
        XCTAssertTrue(app.navigationBars["接続ガイド"].waitForExistence(timeout: 5))
        let guide = XCTAttachment(screenshot: app.screenshot()); guide.name = "MouseLink-guide"; guide.lifetime = .keepAlways; add(guide)
        app.buttons["閉じる"].tap()
        app.buttons["license"].tap()
        XCTAssertTrue(app.navigationBars["ライセンス"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.links["上流プロジェクト"].exists)
    }
}
