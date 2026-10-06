"""Packaging/source-wiring checks. These do not replace native tests or a physical Bluetooth test."""
from pathlib import Path
import os,re,hashlib,json,unittest
from harden_transport import harden

ROOT=Path(__file__).resolve().parents[1]
APP=Path(os.environ.get('MOUSELINK_TEST_APP',str(ROOT/'out/MouseLink.swiftpm')))

def body(source,name):
    start=source.index(name);begin=source.index('{',start);end=begin+1;depth=1
    while depth:
        depth+=(source[end]=='{')-(source[end]=='}');end+=1
    return source[start:end]

class PackagingSafetyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source=(APP/'Sources/Vendor/HIDPeripheral.swift').read_text()
    def test_every_delegate_checks_current_manager(self):
        for name in ['func peripheralManagerDidUpdateState(', 'func peripheralManagerDidStartAdvertising(',
                     'func peripheralManagerIsReady(', 'func peripheralManager(_ peripheral: CBPeripheralManager, didAdd',
                     'func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead',
                     'func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite',
                     'didSubscribeTo characteristic:', 'didUnsubscribeFrom characteristic:']:
            with self.subTest(name=name): self.assertIn('peripheral === pManager',body(self.source,name))
    def test_bootstrap_is_not_broadcast(self):
        subscribe=body(self.source,'didSubscribeTo characteristic:')
        self.assertNotIn('updateValue(cached',subscribe)
        self.assertIn('initialReports.append((central.identifier',subscribe)
        self.assertIn('onSubscribedCentrals: [central]',body(self.source,'func flushInitialReports('))
    def test_duplicate_subscription_cannot_inject_another_baseline(self):
        subscribe=body(self.source,'didSubscribeTo characteristic:')
        self.assertIn('subscribedCentrals[central.identifier]?.contains(ObjectIdentifier(characteristic)) != true',subscribe)
        self.assertLess(subscribe.index('subscribedCentrals[central.identifier]?.contains'),subscribe.index('initialReports.append'))
    def test_control_point_is_writable(self):
        declaration=self.source.split('type: HIDProfile.hidControlPoint,',1)[1].split(')',1)[0]
        self.assertIn('properties: .writeWithoutResponse',declaration)
        self.assertIn('permissions: .writeEncryptionRequired',declaration)
    def test_keyboard_and_mouse_share_pressure_gate(self):
        for method in ['func sendKeyboardBytes(', 'func tryRelayMouse(']:
            text=body(self.source,method)
            self.assertIn('guard isReadyToSendNotification',text)
            self.assertIn('isReadyToSendNotification = false',text)
            self.assertIn('onSubscribedCentrals: [central]',text)
            self.assertNotIn('onSubscribedCentrals: nil',text)
    def test_keyboard_epoch_is_live_not_constant(self):
        self.assertIn('var inputEpoch: UInt64 { inputRegistry.epoch }',self.source)
        session=(APP/'Sources/TypingSession.swift').read_text()
        self.assertIn('transactionEpoch == sender.inputEpoch',session)
    def test_delayed_service_tasks_are_canceled(self):
        self.assertIn('serviceTask?.cancel()',body(self.source,'func invalidateServices('))
        self.assertIn('manager === self.pManager',body(self.source,'func scheduleServiceChanged('))
    def test_draft_buttons_do_not_schedule_unbound_future_send(self):
        view=(APP/'Sources/TypingView.swift').read_text()
        self.assertNotIn('DispatchQueue.main.async',view)
    def test_mouse_gate_runs_at_write_boundary(self):
        session=(APP/'Sources/MouseSession.swift').read_text()
        text=body(session,'private func drain()')
        self.assertLess(text.index('MouseDispatchSafety.decide'),text.index('bluetooth.tryRelayMouse'))
    def test_upstream_files_match_declared_git_blob_hashes(self):
        lock=json.loads((APP/'upstream-lock.json').read_text())
        self.assertEqual(lock['commit'],'ad7a76ce6132254fbd6085af87cea8d10aa8a82d')
        for path,expected in lock['files'].items():
            data=(APP/'UpstreamSource'/Path(path).name).read_bytes()
            self.assertEqual(hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest(),expected)
    def test_hid_descriptors_and_report_bytes_are_not_rewritten(self):
        for file in ['HIDProfile.swift','HIDReports.swift']:
            self.assertEqual((APP/'Sources/Vendor'/file).read_bytes(),(APP/'UpstreamSource'/file).read_bytes())
    def test_no_runtime_network_dependencies_or_background_mode(self):
        manifest=(APP/'Package.swift').read_text()
        self.assertNotIn('.package(url:',manifest)
        self.assertNotIn('.outgoingNetworkConnections',manifest)
        self.assertNotIn('bluetooth-peripheral',manifest)
    def test_complete_license_is_in_app_and_source(self):
        original=(APP/'UpstreamSource/LICENSE').read_bytes()
        self.assertEqual((APP/'LICENSE.txt').read_bytes(),original)
        self.assertEqual((APP/'Sources/Resources/LICENSE.txt').read_bytes(),original)
    def test_adapter_rejects_reapplication(self):
        with self.assertRaises(ValueError): harden(self.source)
    def test_adapter_rejects_changed_anchor_before_output(self):
        before=ROOT/'out/transport-before-hardening.swift'
        if not before.exists(): self.skipTest('Requires packaging before-hardening snapshot')
        text=before.read_text().replace('    private var centralObjects:', '    private var renamedCentralObjects:',1)
        with self.assertRaises(ValueError): harden(text)

if __name__=='__main__': unittest.main()
