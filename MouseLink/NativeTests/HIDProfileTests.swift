import XCTest
import CoreBluetooth
@testable import MouseLink

// Earlier deterministic fixtures do not simulate connection changes. FaultSender overrides this.
extension KeyboardSending { var inputEpoch: UInt64 { 0 } }

@MainActor
final class HIDProfileTests: XCTestCase {
    func testConstructionDoesNotStartRadioOrAdvertise() {
        let p=HIDPeripheral();XCTAssertFalse(p.isAdvertising);XCTAssertTrue(p.mouseReceivers.isEmpty);XCTAssertTrue(p.keyboardReceivers.isEmpty)
    }
    func testControlPointCanReceiveSuspendCommands() throws {
        let service=HIDPeripheral().buildHIDService(includingBattery:nil)
        let c=try XCTUnwrap(service.characteristics?.first{$0.uuid==HIDProfile.hidControlPoint})
        XCTAssertTrue(c.properties.contains(.writeWithoutResponse));XCTAssertFalse(c.properties.contains(.read))
        XCTAssertEqual((c as? CBMutableCharacteristic)?.permissions,.writeEncryptionRequired)
    }
    func testCharacteristicOrderAndDistinctReportReferencesPreserved() throws {
        let service=HIDPeripheral().buildHIDService(includingBattery:nil)
        let chars=try XCTUnwrap(service.characteristics)
        XCTAssertEqual(chars.count,12)
        XCTAssertEqual(chars.prefix(7).map(\.uuid),[HIDProfile.hidControlPoint,HIDProfile.protocolMode,HIDProfile.hidInformation,HIDProfile.bootMouseInputReport,HIDProfile.bootKeyboardInputReport,HIDProfile.bootKeyboardOutputReport,HIDProfile.reportMap])
        let refs=chars.filter{$0.uuid==HIDProfile.report}.compactMap{ c in c.descriptors?.first{$0.uuid==HIDProfile.reportReference}?.value as? Data }
        XCTAssertEqual(refs,[Data([5,1]),Data([6,1]),Data([1,1]),Data([2,1]),Data([3,2])])
    }
    func testKeyboardAndMouseNotificationsRequireEncryption() throws {
        let chars=try XCTUnwrap(HIDPeripheral().buildHIDService(includingBattery:nil).characteristics)
        for c in chars where c.uuid==HIDProfile.bootKeyboardInputReport || c.uuid==HIDProfile.bootMouseInputReport || c.properties.contains(.notifyEncryptionRequired) {
            XCTAssertTrue(c.properties.contains(.notifyEncryptionRequired))
            XCTAssertTrue((c as? CBMutableCharacteristic)?.permissions.contains(.readEncryptionRequired)==true)
        }
    }
    func testHIDReportMapMatchesActualPayloadSizes() throws {
        let bytes=Array(HIDProfile.reportMapData);var index=0,report=0,size=0,count=0,depth=0
        var inputs:[Int:Int]=[:],outputs:[Int:Int]=[:]
        while index<bytes.count {
            let prefix=Int(bytes[index]);index+=1
            XCTAssertNotEqual(prefix,254,"Unexpected long HID item")
            let n=[0,1,2,4][prefix&3];XCTAssertLessThanOrEqual(index+n,bytes.count)
            guard index+n<=bytes.count else { return }
            var value=0;for offset in 0..<n { value |= Int(bytes[index+offset]) << (8*offset) };index+=n
            switch prefix&0xfc {
            case 0x84:report=value
            case 0x74:size=value
            case 0x94:count=value
            case 0x80:inputs[report,default:0]+=size*count
            case 0x90:outputs[report,default:0]+=size*count
            case 0xa0:depth+=1
            case 0xc0:depth-=1;XCTAssertGreaterThanOrEqual(depth,0)
            default:break
            }
        }
        XCTAssertEqual(inputs,[1:32,2:64,4:8,5:8,6:40]);XCTAssertEqual(outputs,[3:8]);XCTAssertEqual(depth,0)
        XCTAssertEqual(MouseFrame.zero.data.count*8,inputs[1]);XCTAssertEqual(KeyboardStroke.zero.data.count*8,inputs[2])
    }
    func testInvalidKeyboardPacketsAreRejectedWithoutRadio() {
        let p=HIDPeripheral(),peer=UUID()
        for data in [Data(),Data(repeating:0,count:7),Data(repeating:0,count:9),Data([0,1,4,0,0,0,0,0]),Data([0,0,255,0,0,0,0,0])] {
            XCTAssertEqual(p.sendKeyboardBytes(data,to:peer),.unavailable)
        }
        XCTAssertFalse(p.isAdvertising)
    }
    func testNeutralReportIsNotAConnection() {
        let p=HIDPeripheral();XCTAssertEqual(p.sendKeyboardBytes(KeyboardStroke.zero.data,to:UUID()),.unavailable)
    }
    func testResetInvalidatesTransportGenerationAndNeverStartsRadio() {
        let p=HIDPeripheral();let old=p.inputEpoch;p.hardDisconnect();XCTAssertNotEqual(p.inputEpoch,old)
        XCTAssertFalse(p.isAdvertising);XCTAssertFalse(p.isHIDServiceAdded)
    }
}
