#!/usr/bin/env python3
"""Build the visible, resizable companion panel; no background-input entitlement is added."""
from pathlib import Path
import plistlib
import runpy
from package_keyboard_app import archive

ROOT=Path(__file__).resolve().parents[1]

def main():
    runpy.run_path(str(ROOT/'tools/package_ux_app.py'),run_name='__main__')
    app=ROOT/'out/MouseLink.swiftpm'
    p=app/'Package.swift';s=p.read_text()
    old='displayVersion: "0.3.1", bundleVersion: "5"'
    if s.count(old)!=1: raise ValueError('Unexpected base package version')
    s=s.replace(old,'displayVersion: "0.4.3", bundleVersion: "9"')
    s=s.replace('supportedInterfaceOrientations: [.portrait, .landscapeLeft, .landscapeRight]',
        'supportedInterfaceOrientations: [.portrait, .landscapeLeft, .landscapeRight, .portraitUpsideDown(.when(deviceFamilies: [.pad]))]')
    old='capabilities: [.bluetoothAlways(purposeString: "iPhoneへマウス操作を直接転送するためBluetoothを使用します。")]'
    if s.count(old)!=1: raise ValueError('Missing capabilities anchor')
    s=s.replace(old,old+',\n        additionalInfoPlistContentFilePath: "PanelInfo.plist"')
    p.write_text(s)
    extra={'UIRequiresFullScreen':False,'UIApplicationSupportsIndirectInputEvents':True,
           'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False}}
    (app/'PanelInfo.plist').write_bytes(plistlib.dumps(extra))
    p=ROOT/'out/project.yml';s=p.read_text()
    if '        UIRequiresFullScreen: true\n' not in s: raise ValueError('Full-screen opt-out anchor changed')
    s=s.replace('        UIRequiresFullScreen: true\n','        UIApplicationSceneManifest:\n          UIApplicationSupportsMultipleScenes: false\n')
    s=s.replace('        UILaunchScreen: {}','        UISupportedInterfaceOrientations~ipad: [UIInterfaceOrientationPortrait, UIInterfaceOrientationPortraitUpsideDown, UIInterfaceOrientationLandscapeLeft, UIInterfaceOrientationLandscapeRight]\n        UILaunchScreen: {}')
    s=s.replace('MARKETING_VERSION: 0.3.1','MARKETING_VERSION: 0.4.3').replace('CURRENT_PROJECT_VERSION: 5','CURRENT_PROJECT_VERSION: 9')
    p.write_text(s)
    (app/'小窓パネルの使い方.md').write_bytes((ROOT/'docs/companion-panel.md').read_bytes())
    # README links to this canonical relative path; retain the Japanese alias too.
    (app/'docs/companion-panel.md').write_bytes((ROOT/'docs/companion-panel.md').read_bytes())
    print('Windowed companion package:',archive(app))

if __name__=='__main__': main()
