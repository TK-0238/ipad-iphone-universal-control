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
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testPanelAlongsideSafari() throws {
        continueAfterFailure=false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication(), safari=XCUIApplication(bundleIdentifier:"com.apple.mobilesafari")
        let spring=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        defer { safari.terminate(); app.terminate(); XCUIDevice.shared.orientation = .portrait }
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
        // Safari initially focuses its address field. Close its real keyboard before checking
        // whether the whole control pad is usable beside the other app.
        let cancel = safari.buttons.matching(NSPredicate(format: "label == 'Cancel' OR label == 'キャンセル'")).firstMatch
        if cancel.waitForExistence(timeout: 3) { cancel.tap() }
        let keyboardHidden = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            !safari.keyboards.firstMatch.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardHidden], timeout: 8), .completed)
        let pad = app.otherElements["panel-pad"]
        XCTAssertTrue(pad.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["panel-typing"].isHittable)
        XCTAssertGreaterThan(safari.windows.firstMatch.frame.width, 100)
        XCTAssertFalse(app.buttons["panel-enable"].isEnabled)
        capture("panel-real-split-view")

        // Drag the OS-owned split divider, not an artificial app preview, to the narrow size.
        let win = app.windows.firstMatch
        let before = win.frame
        let seam = win.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 4, dy: 0))
        let destination = win.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: fullWidth / 3 - before.minX, dy: before.height / 2))
        seam.press(forDuration: 0.3, thenDragTo: destination)
        let narrow = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            app.windows.firstMatch.frame.width < fullWidth * 0.45
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [narrow], timeout: 10), .completed)
        let frame = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(frame.width, 300)
        XCTAssertTrue(pad.isHittable)
        XCTAssertGreaterThanOrEqual(pad.frame.minX, frame.minX)
        XCTAssertLessThanOrEqual(pad.frame.maxX, frame.maxX)
        XCTAssertLessThan(pad.frame.maxY, app.buttons["panel-typing"].frame.minY)
        capture("panel-narrow-safari")
        let geometry = XCTAttachment(string: "panel=\(frame) pad=\(pad.frame) safari=\(safari.windows.firstMatch.frame)\n" + app.debugDescription)
        geometry.name = "panel-real-split-geometry"; geometry.lifetime = .keepAlways; add(geometry)

        app.buttons["panel-typing"].tap()
        XCTAssertTrue(app.buttons["close-typing"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["remote-enter"].isEnabled)
        let draft = app.descendants(matching: .any).matching(identifier: "typing-draft").firstMatch
        draft.tap(); draft.typeText("split view draft")
        XCTAssertFalse(app.buttons["send-text-enter"].isEnabled)
        if app.buttons["キーボードを閉じる"].exists { app.buttons["キーボードを閉じる"].tap() }
        capture("panel-narrow-typing")
        app.buttons["close-typing"].tap()
        XCTAssertTrue(app.buttons["panel-stop"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["panel-enable"].isEnabled)
        capture("panel-narrow-return")
    }
}
