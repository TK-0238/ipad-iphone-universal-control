import XCTest

final class PanelUITests:XCTestCase {
    override func setUp() { super.setUp();continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait }
    private func launch()->XCUIApplication {
        let app=XCUIApplication();app.launchArguments += ["-AppleLanguages","(ja)","-AppleLocale","ja_JP"]
        app.launch();XCTAssertTrue(app.buttons["open-panel"].waitForExistence(timeout:15));app.buttons["open-panel"].tap()
        XCTAssertTrue(app.buttons["panel-typing"].waitForExistence(timeout:5));return app
    }
    private func capture(_ name:String) { let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a) }
    func testPanelIsExplicitAndOfflineCannotSend() {
        let app=launch()
        XCTAssertFalse(app.buttons["panel-enable"].isEnabled)
        XCTAssertTrue(app.buttons["panel-stop"].isHittable)
        XCTAssertTrue(app.otherElements["panel-pad"].exists)
        XCTAssertFalse(app.buttons["pause"].exists)
        capture("panel-unconnected")
        app.buttons["panel-stop"].tap()
        XCTAssertFalse(app.buttons["panel-enable"].isEnabled)
    }
    func testPanelTypingAndReturnPreserveOfflineSafety() {
        let app=launch();app.buttons["panel-typing"].tap()
        XCTAssertTrue(app.buttons["remote-enter"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["remote-enter"].isEnabled)
        app.buttons["close-typing"].tap()
        XCTAssertTrue(app.buttons["panel-stop"].waitForExistence(timeout:5))
        capture("panel-after-typing")
    }
    func testPanelLargeTextControlsRemainReachable() {
        let app=XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch();XCTAssertTrue(app.buttons["open-panel"].waitForExistence(timeout:15));app.buttons["open-panel"].tap()
        XCTAssertTrue(app.buttons["panel-typing"].isHittable);XCTAssertTrue(app.buttons["panel-stop"].isHittable)
        capture("panel-large-text");app.buttons["panel-typing"].tap()
        XCTAssertTrue(app.buttons["close-typing"].waitForExistence(timeout:5));app.buttons["close-typing"].tap()
    }
    func testPanelGuideAndReturnToWorkspace() {
        let app=launch()
        for _ in 0..<4 where !app.buttons["panel-guide"].isHittable { app.swipeUp() }
        app.buttons["panel-guide"].tap()
        XCTAssertTrue(app.navigationBars["小窓の使い方"].waitForExistence(timeout:5))
        capture("panel-guide");app.buttons["閉じる"].tap()
        for _ in 0..<4 where !app.buttons["panel-expand"].isHittable { app.swipeUp() }
        app.buttons["panel-expand"].tap()
        XCTAssertTrue(app.buttons["open-panel"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["start"].isEnabled)
    }
}

/// Real system Split View attempt; no fake Safari UI or fake Bluetooth receiver.
final class SplitWindowUITests:XCTestCase {
    func testPanelAlongsideSafari() throws {
        continueAfterFailure=false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication(), safari=XCUIApplication(bundleIdentifier:"com.apple.mobilesafari")
        let spring=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        safari.launch();app.launch()
        let fullWidth=app.windows.firstMatch.frame.width
        XCTAssertTrue(app.buttons["open-panel"].waitForExistence(timeout:15))
        // UIKit's multitasking affordance is system-owned, above the app navigation bar.
        let menu=app.buttons.matching(NSPredicate(format:"label CONTAINS[c] 'Multitask' OR label CONTAINS 'マルチタスク'")).firstMatch
        if menu.exists { menu.tap() }
        else { app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0)).withOffset(CGVector(dx:0,dy:12)).tap() }
        let tree=XCTAttachment(string:app.debugDescription+"\nSPRINGBOARD\n"+spring.debugDescription)
        tree.name="split-menu-tree";tree.lifetime = .keepAlways;add(tree)
        let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot());image.name="split-menu";image.lifetime = .keepAlways;add(image)
        let query=NSPredicate(format:"label CONTAINS[c] 'Split View' OR label CONTAINS '画面分割'")
        let inApp=app.buttons.matching(query).firstMatch
        let inSystem=spring.buttons.matching(query).firstMatch
        guard inApp.exists || inSystem.exists else { throw XCTSkip("System Split View menu not exposed in this simulator; see split-menu evidence") }
        (inApp.exists ? inApp : inSystem).tap()
        let icon=spring.icons["Safari"].firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout:5));icon.tap()
        let compact=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in app.windows.firstMatch.frame.width < fullWidth*0.8 },object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[compact],timeout:10),.completed)
        let snap=XCTAttachment(screenshot:XCUIScreen.main.screenshot());snap.name="panel-real-split-view";snap.lifetime = .keepAlways;add(snap)
        XCTAssertTrue(app.buttons["panel-typing"].exists)
        XCTAssertGreaterThan(safari.windows.firstMatch.frame.width,100)
        XCTAssertFalse(app.buttons["panel-enable"].isEnabled)
        safari.terminate();app.terminate();XCUIDevice.shared.orientation = .portrait
    }
}
