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
    private func dragHandle(in app: XCUIApplication) -> XCUIElement {
        let matches = app.descendants(matching:.any).matching(identifier:"placement-drag-handle")
        let handle = matches.firstMatch
        let snapshot = XCTAttachment(string: app.debugDescription)
        snapshot.name = "ux-placement-accessibility-tree"
        snapshot.lifetime = .keepAlways
        add(snapshot)
        XCTAssertTrue(handle.waitForExistence(timeout:5), "The visible drag handle must be exposed independently")
        XCTAssertEqual(matches.count, 1, "A container must not duplicate or overwrite this control's identifier")
        XCTAssertTrue(handle.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(handle.frame))
        return handle
    }
    private func assertRemainsLocal(_ app: XCUIApplication) {
        XCTAssertFalse(app.buttons["start"].isEnabled)
        XCTAssertFalse(app.buttons["pause"].exists)
        XCTAssertFalse(app.buttons["cancel-edge"].exists)
    }
    private func dragPlacement(in app: XCUIApplication, dx: CGFloat, expected: String) {
        let handle = dragHandle(in: app)
        let start = handle.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        start.press(forDuration:0.15,thenDragTo:start.withOffset(CGVector(dx:dx,dy:0)))
        let selected = app.buttons["place-\(expected)"]
        let settled = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@", "選択中"), object:selected)
        XCTAssertEqual(XCTWaiter.wait(for:[settled],timeout:3),.completed)
        assertRemainsLocal(app)
    }
    func testDraggingPlacementDoesNotStartRemoteInput() {
        let app = launch(); app.buttons["place-right"].tap()
        dragPlacement(in:app, dx:-160, expected:"left")
        capture("ux-dragged-placement-left")
        // Return using a real drag on the newly positioned handle, not a left/right button.
        dragPlacement(in:app, dx:160, expected:"right")
        capture("ux-dragged-placement-right")
    }
    func testPlacementTapAndShortDragDoNotMoveOrStartInput() {
        let app = launch(); app.buttons["place-right"].tap()
        let handle = dragHandle(in:app)
        handle.tap()
        let start = handle.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        start.press(forDuration:0.15,thenDragTo:start.withOffset(CGVector(dx:-35,dy:0)))
        XCTAssertEqual(app.buttons["place-right"].value as? String,"選択中")
        assertRemainsLocal(app)
    }
    func testPlacementDragWorksAfterRotation() {
        let app = launch(); app.buttons["place-right"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let rotated = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in app.frame.width > app.frame.height },object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[rotated],timeout:10),.completed)
        dragPlacement(in:app, dx:-160, expected:"left")
        capture("ux-landscape-drag-left")
        dragPlacement(in:app, dx:160, expected:"right")
        capture("ux-landscape-drag-right")
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
