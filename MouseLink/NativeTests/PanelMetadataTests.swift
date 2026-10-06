import XCTest
import UIKit
import Combine
@testable import MouseLink

@MainActor
final class PanelMetadataTests:XCTestCase {
    func testNativeAppDoesNotRequestFullScreenCompatibility() {
        XCTAssertNotEqual(Bundle.main.object(forInfoDictionaryKey:"UIRequiresFullScreen") as? Bool,true)
        let orientations=Bundle.main.object(forInfoDictionaryKey:"UISupportedInterfaceOrientations~ipad") as? [String]
        XCTAssertEqual(Set(orientations ?? []),Set(["UIInterfaceOrientationPortrait","UIInterfaceOrientationPortraitUpsideDown","UIInterfaceOrientationLandscapeLeft","UIInterfaceOrientationLandscapeRight"]))
    }
    func testSingleMouseLinkSceneCanCoexistWithOtherApps() {
        let manifest=Bundle.main.object(forInfoDictionaryKey:"UIApplicationSceneManifest") as? [String:Any]
        XCTAssertEqual(manifest?["UIApplicationSupportsMultipleScenes"] as? Bool,false)
    }
    func testPadUsesLocalHoverAndScrollWithoutEnablingRadio() {
        let radio=HIDPeripheral()
        let panel=PanelSession(sender:radio,ticks:Empty<Date,Never>().eraseToAnyPublisher())
        let view=LocalPadView(panel:panel);view.frame=CGRect(x:0,y:0,width:320,height:200);view.layoutIfNeeded()
        XCTAssertFalse(panel.isEnabled);XCTAssertFalse(view.usable)
        XCTAssertTrue(view.gestureRecognizers?.contains{$0 is UIHoverGestureRecognizer} == true)
        let scroll=view.gestureRecognizers?.compactMap{$0 as? UIPanGestureRecognizer}.first
        XCTAssertEqual(scroll?.allowedScrollTypesMask,.all)
        XCTAssertEqual(scroll?.allowedTouchTypes,[])
        XCTAssertFalse(radio.isAdvertising)
    }
}
