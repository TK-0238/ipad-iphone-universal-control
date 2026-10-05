"""Checks generated metadata as well as the local-only panel input path; not radio tests."""
from pathlib import Path
import plistlib,unittest
ROOT=Path(__file__).resolve().parents[1]
APP=ROOT/'out/MouseLink.swiftpm'
class PanelPackageTests(unittest.TestCase):
    def test_playground_declares_resizing_and_indirect_input(self):
        info=plistlib.loads((APP/'PanelInfo.plist').read_bytes())
        self.assertFalse(info['UIRequiresFullScreen'])
        self.assertTrue(info['UIApplicationSupportsIndirectInputEvents'])
        self.assertFalse(info['UIApplicationSceneManifest']['UIApplicationSupportsMultipleScenes'])
        self.assertIn('additionalInfoPlistContentFilePath: "PanelInfo.plist"',(APP/'Package.swift').read_text())
    def test_native_project_does_not_opt_out_of_multitasking(self):
        text=(ROOT/'out/project.yml').read_text()
        self.assertNotIn('UIRequiresFullScreen: true',text)
        self.assertIn('UIInterfaceOrientationPortraitUpsideDown',text)
        self.assertIn('UIApplicationSupportsMultipleScenes: false',text)
    def test_panel_never_installs_raw_capture_or_pointer_lock(self):
        text=(APP/'Sources/PanelSession.swift').read_text()+(APP/'Sources/PanelPadView.swift').read_text()
        for forbidden in ['mouseMovedHandler =','pressedChangedHandler =','prefersPointerLocked','UIBackgroundModes']:
            self.assertNotIn(forbidden,text)
        self.assertIn('UIHoverGestureRecognizer',text)
        self.assertIn('surfaceIsUsable()',text)
    def test_companion_contains_typing_stop_and_real_offline_state(self):
        text=(APP/'Sources/CompanionPanel.swift').read_text()
        for key in ['panel-stop','panel-typing','panel-connection','panel-enable','g.size.width < 700']:
            self.assertIn(key,text)
        self.assertIn('session.bluetooth.mouseReceivers.contains',text)
    def test_multitasking_changes_do_not_add_background_permissions(self):
        text=(APP/'PanelInfo.plist').read_text()+(APP/'Package.swift').read_text()
        self.assertNotIn('UIBackgroundModes',text)
        self.assertNotIn('bluetooth-peripheral',text)
        self.assertIn('.portraitUpsideDown',text)
if __name__=='__main__': unittest.main()
