#!/usr/bin/env python3
"""Extend the SHA-verified original package with targeted HID keyboard support."""
from pathlib import Path
import runpy
import zipfile
from harden_transport import harden

ROOT=Path(__file__).resolve().parents[1]

def once(text, old, new):
    if text.count(old)!=1:
        raise ValueError(f'Keyboard patch anchor changed: {old[:80]!r}')
    return text.replace(old,new,1)

def patch_keyboard(text):
    text=once(text, '    var onMouseWritable:', '''    @Published private(set) var keyboardReceivers: Set<UUID> = []
    private var keyboardSubscriptions: [UUID: Set<CBUUID>] = [:]
    private var keyboardBackpressured = false
    var onMouseWritable:''')
    text=once(text, '        mouseSubscriptions.removeAll()\n        relayModes.removeAll()', '''        mouseSubscriptions.removeAll()
        keyboardSubscriptions.removeAll()
        keyboardReceivers.removeAll()
        keyboardBackpressured = false
        cachedReports[ReportID.keyboard.rawValue] = KeyboardReport.zero.data
        relayModes.removeAll()''')
    text=once(text, '        subscribedCentrals[central.identifier, default: []].insert(ObjectIdentifier(characteristic))', '''        if reportID(forCharacteristic: characteristic) == ReportID.keyboard.rawValue || characteristic.uuid == HIDProfile.bootKeyboardInputReport {
            keyboardSubscriptions[central.identifier, default: []].insert(characteristic.uuid)
            keyboardReceivers = Set(keyboardSubscriptions.keys)
            cachedReports[ReportID.keyboard.rawValue] = KeyboardReport.zero.data
        }
        subscribedCentrals[central.identifier, default: []].insert(ObjectIdentifier(characteristic))''')
    text=once(text, '        guard var chars = subscribedCentrals[central.identifier] else { return }', '''        if reportID(forCharacteristic: characteristic) == ReportID.keyboard.rawValue || characteristic.uuid == HIDProfile.bootKeyboardInputReport {
            keyboardSubscriptions[central.identifier]?.remove(characteristic.uuid)
            if keyboardSubscriptions[central.identifier]?.isEmpty == true {
                keyboardSubscriptions.removeValue(forKey: central.identifier)
            }
            keyboardReceivers = Set(keyboardSubscriptions.keys)
        }
        guard var chars = subscribedCentrals[central.identifier] else { return }''')
    # Mouse report unsubscription alone must not reset the keyboard's per-host protocol mode.
    text=once(text,'                relayModes.removeValue(forKey: central.identifier)','')
    text=once(text,'            connectedCentrals.remove(central.identifier)','            connectedCentrals.remove(central.identifier)\n            relayModes.removeValue(forKey: central.identifier)')
    text=once(text, '        isReadyToSendNotification = true\n        drainPendingBroadcast()', '        keyboardBackpressured = false\n        isReadyToSendNotification = true\n        drainPendingBroadcast()')
    text=once(text, '            mouseReceivers.removeAll()\n            relayModes.removeAll()', '''            mouseReceivers.removeAll()
            keyboardSubscriptions.removeAll()
            keyboardReceivers.removeAll()
            keyboardBackpressured = false
            relayModes.removeAll()''')
    text=once(text, '        case HIDProfile.hidControlPoint:\n            if value.first == 0', '''        case HIDProfile.hidControlPoint:
            if value.first == 0 { keyboardReceivers.remove(request.central.identifier) }
            else if value.first == 1, keyboardSubscriptions[request.central.identifier] != nil { keyboardReceivers.insert(request.central.identifier) }
            if value.first == 0''')
    text+='''

// MouseLink 0.2: keyboard reports go only to the selected peer, not to activeRecipients().
@MainActor
extension HIDPeripheral: KeyboardSending {
    func sendKeyboardBytes(_ bytes: Data, to id: UUID) -> KeyboardSendResult {
        guard bytes.count == 8, let manager = pManager, manager.state == .poweredOn,
              keyboardReceivers.contains(id), let central = centralObjects[id] else { return .unavailable }
        guard !keyboardBackpressured else { return .busy }
        let boot = (relayModes[id] ?? 1) == 0
        let characteristic = boot ? bootKeyboardInputChar : charsByReportID[ReportID.keyboard.rawValue]
        let uuid = boot ? HIDProfile.bootKeyboardInputReport : HIDProfile.report
        guard keyboardSubscriptions[id]?.contains(uuid) == true, let characteristic else { return .unavailable }
        // Same eight-byte payload in boot/report protocol. Never send both paths: that doubles keystrokes.
        if manager.updateValue(bytes, for: characteristic, onSubscribedCentrals: [central]) { return .accepted }
        keyboardBackpressured = true
        return .busy
    }
}
'''
    return text

UNIT_TARGET='''  MouseLinkNativeTests:
    type: bundle.unit-test
    platform: iOS
    sources: [../NativeTests]
    dependencies:
      - target: MouseLink
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: jp.kawashimataiki.mouselink.nativetests
        GENERATE_INFOPLIST_FILE: YES
'''

def augment(app):
    vendor=app/'Sources/Vendor/HIDPeripheral.swift'
    before=patch_keyboard(vendor.read_text())
    (app.parent/'transport-before-hardening.swift').write_text(before)
    vendor.write_text(harden(before))
    p=app/'Package.swift';p.write_text(p.read_text().replace('displayVersion: "0.1.0", bundleVersion: "1"','displayVersion: "0.2.1", bundleVersion: "3"'))
    for src,dest in [('docs/keyboard-enter.md','文字入力とEnter.md'),('docs/qa-0.2.1.md','検証方針と変更点.md')]:
        readme=ROOT/src
        if readme.exists(): (app/dest).write_bytes(readme.read_bytes())
    p=app/'THIRD_PARTY_NOTICES.md'
    p.write_text(p.read_text()+'\nMouseLink 0.2 adds targeted keyboard notifications, boot/report selection, on-screen typing, bounded press/release transactions and kana-reading conversion. 0.2.1 adds connection epochs, callback identity checks, shared notification flow control, targeted bootstrap reports, suspend-state tracking and idempotent stop. All modifications remain AGPL-3.0-only.\n')

def archive(app):
    path=app.parent/'MouseLink-iPad.zip'
    with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED) as z:
        for p in sorted(app.rglob('*')):
            if p.is_file(): z.write(p,p.relative_to(app.parent))
    return path

def main():
    runpy.run_path(str(ROOT/'tools/package_app.py'),run_name='__main__')
    app=ROOT/'out/MouseLink.swiftpm'
    augment(app)
    p=ROOT/'out/project.yml';t=p.read_text()
    t=t.replace('schemes:\n',UNIT_TARGET+'schemes:\n')
    t=t.replace('        MouseLinkUITests: [test]','        MouseLinkUITests: [test]\n        MouseLinkNativeTests: [test]')
    t=t.replace('      targets: [MouseLinkUITests]','      targets: [MouseLinkUITests, MouseLinkNativeTests]')
    t=t.replace('MARKETING_VERSION: 0.1.0','MARKETING_VERSION: 0.2.1').replace('CURRENT_PROJECT_VERSION: 1','CURRENT_PROJECT_VERSION: 3')
    p.write_text(t)
    print('Keyboard package:',archive(app))

if __name__=='__main__': main()
