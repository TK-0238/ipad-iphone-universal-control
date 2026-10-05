import XCTest

final class ContinuityUITests: XCTestCase {
    override func setUp() {
        super.setUp(); continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
    }
    private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages","(ja)","-AppleLocale","ja_JP"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); XCTAssertTrue(app.buttons["open-settings"].waitForExistence(timeout:15)); return app
    }
    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    func testDeviceArrangementAndOfflineActions() {
        let app = launch()
        XCTAssertTrue(app.buttons["place-left"].exists); XCTAssertTrue(app.buttons["place-right"].exists)
        XCTAssertFalse(app.buttons["start"].isEnabled); XCTAssertFalse(app.buttons["arm-edge"].isEnabled)
        XCTAssertTrue(app.buttons["open-typing"].isHittable)
        app.buttons["place-left"].tap(); XCTAssertEqual(app.buttons["place-left"].value as? String,"選択中")
        capture("ux-workspace-left")
        app.buttons["place-right"].tap(); capture("ux-workspace-right")
    }
    func testDraggingPlacementDoesNotStartRemoteInput() {
        let app = launch(); app.buttons["place-right"].tap()
        let handle = app.descendants(matching:.any).matching(identifier:"placement-drag-handle").firstMatch
        XCTAssertTrue(handle.isHittable)
        let start = handle.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        start.press(forDuration:0.15,thenDragTo:start.withOffset(CGVector(dx:-160,dy:0)))
        XCTAssertEqual(app.buttons["place-left"].value as? String,"選択中")
        XCTAssertFalse(app.buttons["start"].isEnabled); XCTAssertFalse(app.buttons["cancel-edge"].exists)
        capture("ux-dragged-placement")
        app.buttons["place-right"].tap()
    }
    func testPlacementPersistsButEdgePermissionDoesNot() {
        let app = launch(); app.buttons["place-left"].tap(); app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["place-left"].waitForExistence(timeout:10))
        XCTAssertEqual(app.buttons["place-left"].value as? String,"選択中")
        XCTAssertFalse(app.buttons["arm-edge"].isEnabled)
        XCTAssertFalse(app.buttons["cancel-edge"].exists)
        app.buttons["place-right"].tap()
    }
    func testSettingsAreSeparateAndDoNotConnectAutomatically() {
        let app = launch(); app.buttons["open-settings"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout:5))
        XCTAssertTrue(app.sliders["マウス感度"].exists); capture("ux-settings")
        app.buttons["close-settings"].tap()
        XCTAssertTrue(app.buttons["open-typing"].isHittable)
        XCTAssertFalse(app.buttons["start"].isEnabled)
    }
    func testLandscapeWorkspaceKeepsActionBarVisible() {
        let app = launch(); XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let e = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in app.frame.width > app.frame.height }, object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[e],timeout:10),.completed)
        XCTAssertTrue(app.buttons["open-typing"].isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(app.buttons["open-typing"].frame))
        capture("ux-workspace-landscape")
    }
    func testLargeTypeWorkspaceKeepsSettingsAndTypingReachable() {
        let app = launch(large:true)
        XCTAssertTrue(app.buttons["open-settings"].isHittable); XCTAssertTrue(app.buttons["open-typing"].isHittable)
        capture("ux-workspace-large-text")
        app.buttons["open-typing"].tap(); XCTAssertTrue(app.buttons["close-typing"].waitForExistence(timeout:5))
        app.buttons["close-typing"].tap(); XCTAssertFalse(app.buttons["start"].isEnabled)
    }
}
