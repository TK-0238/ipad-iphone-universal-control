#!/usr/bin/env python3
"""Package a self-contained iPad app. Network is used only when packaging.
Pinned upstream source is checked against its Git blob SHA before use.
"""
from pathlib import Path
import hashlib
import json
import shutil
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'out'
UPSTREAM = 'ad7a76ce6132254fbd6085af87cea8d10aa8a82d'
FILES = {
    'BTRemote/LowEnergy/HIDPeripheral.swift': '9325cfde7cb451fb5c46614a8e89557529f2e856',
    'BTRemote/LowEnergy/HIDProfile.swift': '41a374f720540eeb22c12dbd9d53c7e50025481f',
    'BTRemote/LowEnergy/HIDReports.swift': '8b46279be56e350f055afeb57bfca83e456a156a',
    'LICENSE': '0ad25db4bd1d86c452db3f9602ccdbe172438f52',
}

def download(path: str, expected: str) -> str:
    url = f'https://raw.githubusercontent.com/jqssun/darwin-bt-remote/{UPSTREAM}/{path}'
    req = urllib.request.Request(url, headers={'User-Agent': 'MouseLink-source-packager'})
    with urllib.request.urlopen(req, timeout=40) as response:
        data = response.read(1_000_001)
    if len(data) > 1_000_000:
        raise ValueError('Unexpected upstream file size')
    actual = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    if actual != expected:
        raise ValueError(f'Upstream integrity mismatch for {path}: {actual}')
    return data.decode('utf-8')

def replace_once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise ValueError(f'Upstream patch anchor changed: {old[:90]!r}')
    return text.replace(old, new, 1)

def adapt_peripheral(text: str) -> str:
    # Keep the original GATT service tree, characteristic order and HID report map.
    text = text.replace('L10n.Bluetooth.advertisedName', '"MouseLink"')
    text = text.replace('extension HIDPeripheral: @preconcurrency CBPeripheralManagerDelegate', 'extension HIDPeripheral: CBPeripheralManagerDelegate')
    text = text.replace('[UUID: Set<CBUUID>]', '[UUID: Set<ObjectIdentifier>]')
    text = text.replace('.insert(characteristic.uuid)', '.insert(ObjectIdentifier(characteristic))')
    text = text.replace('chars.remove(characteristic.uuid)', 'chars.remove(ObjectIdentifier(characteristic))')
    text = replace_once(text, '    private var centralObjects:', '''    @Published private(set) var mouseReceivers: Set<UUID> = []
    var onMouseWritable: (() -> Void)?
    private var mouseSubscriptions: [UUID: Set<CBUUID>] = [:]
    private var relayModes: [UUID: UInt8] = [:]

    private var centralObjects:''')
    text = replace_once(text, '    func start() {', '    func start() {\n        lastError = nil')
    text = replace_once(text, '        centralObjects.removeAll()', '''        centralObjects.removeAll()
        mouseSubscriptions.removeAll()
        relayModes.removeAll()
        mouseReceivers.removeAll()
        cachedReports[ReportID.mouse.rawValue] = MouseReport.zero.data''')
    text = replace_once(text, '            lastError = error.localizedDescription\n        }\n        switch service.uuid', '            lastError = error.localizedDescription\n            return\n        }\n        switch service.uuid')
    text = replace_once(text, '        _trackInteraction(from: central)\n        subscribedCentrals', '''        _trackInteraction(from: central)
        if reportID(forCharacteristic: characteristic) == ReportID.mouse.rawValue || characteristic.uuid == HIDProfile.bootMouseInputReport {
            mouseSubscriptions[central.identifier, default: []].insert(characteristic.uuid)
            mouseReceivers = Set(mouseSubscriptions.keys)
            cachedReports[ReportID.mouse.rawValue] = MouseReport.zero.data
        }
        subscribedCentrals''')
    text = replace_once(text, '        guard var chars = subscribedCentrals[central.identifier] else { return }', '''        if reportID(forCharacteristic: characteristic) == ReportID.mouse.rawValue || characteristic.uuid == HIDProfile.bootMouseInputReport {
            mouseSubscriptions[central.identifier]?.remove(characteristic.uuid)
            if mouseSubscriptions[central.identifier]?.isEmpty == true {
                mouseSubscriptions.removeValue(forKey: central.identifier)
                relayModes.removeValue(forKey: central.identifier)
            }
            mouseReceivers = Set(mouseSubscriptions.keys)
        }
        guard var chars = subscribedCentrals[central.identifier] else { return }''')
    text = replace_once(text, '        drainPendingBroadcast()\n    }', '        drainPendingBroadcast()\n        onMouseWritable?()\n    }')
    text = replace_once(text, '            isAdvertising = false\n        }\n    }\n\n    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd', '''            isAdvertising = false
            mouseSubscriptions.removeAll()
            mouseReceivers.removeAll()
            relayModes.removeAll()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd''')
    text = text.replace('return Data([0x01]) // report protocol', 'return Data([relayModes[request.central.identifier] ?? 1]) // per-host protocol')
    text = replace_once(text, '        case HIDProfile.protocolMode, HIDProfile.hidControlPoint:\n            break', '''        case HIDProfile.protocolMode:
            if let mode = value.first, mode <= 1 { relayModes[request.central.identifier] = mode }
        case HIDProfile.hidControlPoint:
            if value.first == 0 { mouseReceivers.remove(request.central.identifier) }
            else if value.first == 1, mouseSubscriptions[request.central.identifier] != nil { mouseReceivers.insert(request.central.identifier) }''')
    text = text.replace('guard request.offset <= value.count else', 'guard request.offset >= 0, request.offset <= value.count else')
    text = replace_once(text, '        for request in requests {\n            _trace("write:', '''        guard let first = requests.first else { return }
        guard requests.allSatisfy({ $0.offset == 0 && ($0.value?.count ?? 0) == 1 }) else {
            peripheral.respond(to: first, withResult: .invalidAttributeValueLength)
            return
        }
        guard requests.allSatisfy({ request in
            let type = request.characteristic.uuid
            guard let value = request.value?.first else { return false }
            if type == HIDProfile.protocolMode || type == HIDProfile.hidControlPoint { return value <= 1 }
            return type == HIDProfile.bootKeyboardOutputReport || type == HIDProfile.report
        }) else {
            peripheral.respond(to: first, withResult: .requestNotSupported)
            return
        }
        for request in requests {
            _trace("write:''')
    text += '''

// MouseLink adaptation, 2026. Actual outgoing input uses the tested RelayBuffer.
enum MouseSendResult { case accepted, busy, unavailable }
@MainActor
extension HIDPeripheral {
    func hardDisconnect() {
        stop()
        _resetForRestart()
    }
    func tryRelayMouse(_ report: MouseReport, to id: UUID) -> MouseSendResult {
        guard let manager = pManager, manager.state == .poweredOn,
              mouseReceivers.contains(id), let central = centralObjects[id] else { return .unavailable }
        let boot = (relayModes[id] ?? 1) == 0
        let characteristic = boot ? bootMouseInputChar : charsByReportID[ReportID.mouse.rawValue]
        let required = boot ? HIDProfile.bootMouseInputReport : HIDProfile.report
        guard mouseSubscriptions[id]?.contains(required) == true, let characteristic else { return .unavailable }
        let bytes = boot ? Data(report.data.prefix(3)) : report.data
        return manager.updateValue(bytes, for: characteristic, onSubscribedCentrals: [central]) ? .accepted : .busy
    }
}
'''
    return '// SPDX-License-Identifier: AGPL-3.0-only\n// Derived from Jingqian Sun, darwin-bt-remote; see THIRD_PARTY_NOTICES.md.\n' + text

MANIFEST = '''// swift-tools-version: 5.10
import PackageDescription
import AppleProductTypes
let package = Package(
    name: "MouseLink", platforms: [.iOS("17.0")],
    products: [.iOSApplication(
        name: "MouseLink", targets: ["AppModule"],
        bundleIdentifier: "jp.kawashimataiki.mouselink",
        displayVersion: "0.1.0", bundleVersion: "1",
        appIcon: .placeholder(icon: .star), accentColor: .presetColor(.blue),
        supportedDeviceFamilies: [.pad, .phone],
        supportedInterfaceOrientations: [.portrait, .landscapeLeft, .landscapeRight],
        capabilities: [.bluetoothAlways(purposeString: "iPhoneへマウス操作を直接転送するためBluetoothを使用します。")]
    )],
    targets: [.executableTarget(name: "AppModule", path: "Sources", resources: [.process("Resources")])]
)
'''
SHIM = '''import Foundation
// Only these upstream preferences are consulted. No mouse events are persisted.
enum AppSettings {
    static let advertisedNameKey = "MouseLink.advertisedName"
    static let developerModeKey = "MouseLink.developerMode"
    static let useServiceChangedKey = "MouseLink.useServiceChanged"
}
'''
PROJECT = '''name: MouseLink
options:
  deploymentTarget:
    iOS: "17.0"
settings:
  base:
    SWIFT_VERSION: "5.0"
    SWIFT_STRICT_CONCURRENCY: minimal
    CODE_SIGNING_ALLOWED: NO
    TARGETED_DEVICE_FAMILY: "1,2"
targets:
  MouseLink:
    type: application
    platform: iOS
    sources:
      - path: MouseLink.swiftpm/Sources
    info:
      path: GeneratedInfo.plist
      properties:
        CFBundleDisplayName: MouseLink
        NSBluetoothAlwaysUsageDescription: iPhoneへマウス操作を直接転送するためBluetoothを使用します。
        UIApplicationSupportsIndirectInputEvents: true
        UIRequiresFullScreen: true
        UILaunchScreen: {}
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait, UIInterfaceOrientationLandscapeLeft, UIInterfaceOrientationLandscapeRight]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: jp.kawashimataiki.mouselink
        GENERATE_INFOPLIST_FILE: YES
        MARKETING_VERSION: 0.1.0
        CURRENT_PROJECT_VERSION: 1
  MouseLinkUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [../UITests]
    dependencies:
      - target: MouseLink
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: jp.kawashimataiki.mouselink.uitests
        GENERATE_INFOPLIST_FILE: YES
schemes:
  MouseLink:
    build:
      targets:
        MouseLink: all
        MouseLinkUITests: [test]
    test:
      targets: [MouseLinkUITests]
'''

def main() -> None:
    OUT.mkdir(exist_ok=True)
    app = OUT / 'MouseLink.swiftpm'
    if app.exists():
        shutil.rmtree(app)  # Only this script's generated output.
    source = app / 'Sources'
    resources = source / 'Resources'
    resources.mkdir(parents=True)
    vendor = source / 'Vendor'; vendor.mkdir()
    original = app / 'UpstreamSource'; original.mkdir()
    for path, sha in FILES.items():
        text = download(path, sha)
        name = Path(path).name
        (original / name).write_text(text, encoding='utf-8')
        if name == 'LICENSE':
            (resources / 'LICENSE.txt').write_text(text, encoding='utf-8')
            (app / 'LICENSE.txt').write_text(text, encoding='utf-8')
        else:
            if name == 'HIDPeripheral.swift': text = adapt_peripheral(text)
            (vendor / name).write_text(text, encoding='utf-8')
    (vendor / 'UpstreamSettings.swift').write_text(SHIM, encoding='utf-8')
    for path in sorted((ROOT / 'App').glob('*.swift')):
        shutil.copy2(path, source / path.name)
    shutil.copytree(ROOT / 'Sources' / 'MouseLinkCore', source / 'Core')
    (app / 'Package.swift').write_text(MANIFEST, encoding='utf-8')
    (OUT / 'project.yml').write_text(PROJECT, encoding='utf-8')
    notices = f'''# Third-party notices

MouseLink contains and adapts Jingqian Sun / jqssun, darwin-bt-remote.
Source: https://github.com/jqssun/darwin-bt-remote
Pinned commit: {UPSTREAM}
License: AGPL-3.0-only. The full license and all corresponding source are included.

The GATT service tree/report descriptor are preserved. MouseLink adds targeted
mouse writes, a bounded queue, lifecycle stops, neutral readback, subscription
identity fixes, registration error propagation, protocol mode tracking and Japanese UI.
Original vendor files are in UpstreamSource; compiled versions are in Sources/Vendor.

This is source for personal running in Swift Playground, not a closed-source
commercial distribution or an App Store submission. No permission to relicense upstream
code is implied. No upstream endorsement or independent security audit is claimed.
'''
    (app / 'THIRD_PARTY_NOTICES.md').write_text(notices, encoding='utf-8')
    for path in ['README.md', 'docs/design.md', 'docs/plan.md']:
        if (ROOT / path).exists():
            dest = app / path; dest.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(ROOT / path, dest)
    privacy = {'NSPrivacyTracking': False, 'NSPrivacyCollectedDataTypes': [], 'NSPrivacyAccessedAPITypes': [
        {'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategoryUserDefaults', 'NSPrivacyAccessedAPITypeReasons': ['CA92.1']},
        {'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategorySystemBootTime', 'NSPrivacyAccessedAPITypeReasons': ['35F9.1']}
    ]}
    import plistlib
    (resources / 'PrivacyInfo.xcprivacy').write_bytes(plistlib.dumps(privacy))
    (app / 'upstream-lock.json').write_text(json.dumps({'commit': UPSTREAM, 'files': FILES}, indent=2) + '\n')
    with zipfile.ZipFile(OUT / 'MouseLink-iPad.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(app.rglob('*')):
            if path.is_file(): archive.write(path, path.relative_to(OUT))
    print(f'Packaged {app}; {len(list(source.rglob("*.swift")))} Swift sources')

if __name__ == '__main__':
    main()
