"""Small, checked adaptations of the pinned 0.2 HOGP engine. Never fetch or rewrite upstream originals."""
import re

def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('Safety patch anchor changed: ' + old[:90])
    return text.replace(old, new, 1)

def method(text, signature, replacement):
    start=text.find(signature)
    if start < 0 or text.count(signature) != 1: raise ValueError('Missing/ambiguous method: '+signature)
    begin=text.index('{',start); level=1; end=begin+1
    # The pinned method bodies have no unbalanced literal braces; source integrity is checked before this layer.
    while level and end < len(text):
        level += (text[end]=='{') - (text[end]=='}'); end += 1
    if level: raise ValueError('Unbalanced Swift method')
    return text[:start]+replacement+text[end:]

def harden(text):
    if '// MouseLink 0.2.1 safety adapter' in text: raise ValueError('Already hardened')
    text=once(text,'    private var centralObjects:', '''    private var inputRegistry = HIDPeerRegistry()
    var inputEpoch: UInt64 { inputRegistry.epoch }
    private var initialReports: [(UUID, CBMutableCharacteristic, Data)] = []
    private var serviceTask: Task<Void, Never>?
    private var centralObjects:''')
    # Same GATT topology/UUIDs, but Control Point must actually permit Suspend/Exit Suspend writes.
    text=once(text,'''type: HIDProfile.hidControlPoint,
            properties: .read,
            value: nil,
            permissions: .readEncryptionRequired''','''type: HIDProfile.hidControlPoint,
            properties: .writeWithoutResponse,
            value: nil,
            permissions: .writeEncryptionRequired''')
    text=once(text,'    private func buildHIDService(', '    func buildHIDService(')
    # Keep construction testable without initializing a radio; no test-only runtime branches.
    text=method(text,'    private func _resetForRestart()', '''    private func _resetForRestart() {
        if let manager = pManager {
            manager.delegate = nil
            if manager.state == .poweredOn { manager.stopAdvertising(); manager.removeAllServices() }
        }
        pManager = nil
        invalidateServices()
    }''')
    text=method(text,'    func scheduleServiceChanged()', '''    func scheduleServiceChanged() {
        guard UserDefaults.standard.bool(forKey: AppSettings.useServiceChangedKey), !serviceChangedArmed,
              let manager = pManager else { return }
        serviceChangedArmed = true
        serviceTask = Task { [weak self, weak manager] in
            do { try await Task.sleep(nanoseconds: Self.serviceChangedGrace) } catch { return }
            guard !Task.isCancelled, let self, let manager, manager === self.pManager else { return }
            self._cycleServiceChangedIfUnsubscribed()
        }
    }''')
    text=method(text,'    func peripheralManagerDidUpdateState(', '''    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral === pManager else { return }
        state = peripheral.state
        if peripheral.state == .poweredOn {
            if isHIDServiceAllowed && !isHIDServiceAdded {
                peripheral.removeAllServices()
                installServices()
            }
        } else { invalidateServices() }
    }''')
    text=method(text,'    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd', '''    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard peripheral === pManager,
              service === batteryServiceObj || service === deviceInfoServiceObj || service === hidServiceObj else { return }
        if let error {
            _resetForRestart()
            lastError = error.localizedDescription
            return
        }
        switch service.uuid {
        case HIDProfile.batteryService:
            let next = buildDeviceInfoService(); deviceInfoServiceObj = next; peripheral.add(next)
        case HIDProfile.deviceInformationService:
            let next = buildHIDService(includingBattery: batteryServiceObj); hidServiceObj = next; peripheral.add(next)
        case HIDProfile.hidService:
            isHIDServiceAdded = true
            if isHIDServiceAllowed { startAdvertisingNow() }
        default: break
        }
    }''')
    text=method(text,'    func peripheralManagerDidStartAdvertising(', '''    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        guard peripheral === pManager else { return }
        guard peripheral.state == .poweredOn, isHIDServiceAdded, isHIDServiceAllowed else {
            if peripheral.state == .poweredOn { peripheral.stopAdvertising() }
            isAdvertising = false; return
        }
        isAdvertising = error == nil
        if let error { lastError = error.localizedDescription }
    }''')
    subscribe='''    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        guard peripheral === pManager, currentCharacteristic(characteristic) else { return }
        // Duplicate callbacks must not inject a neutral report into a held key or drag.
        guard subscribedCentrals[central.identifier]?.contains(ObjectIdentifier(characteristic)) != true else { return }
        _trackInteraction(from: central)
        subscribedCentrals[central.identifier, default: []].insert(ObjectIdentifier(characteristic))
        if let endpoint = endpoint(for: characteristic) {
            inputRegistry.subscribe(endpoint, peer: central.identifier)
        }
        publishInputReadiness()
        // Never broadcast a new host's neutral baseline into another host's in-flight key/drag.
        let value: Data?
        switch endpoint(for: characteristic) {
        case .mouseReport: value = MouseReport.zero.data
        case .mouseBoot: value = Data(MouseReport.zero.data.prefix(3))
        case .keyboardReport, .keyboardBoot: value = KeyboardReport.zero.data
        case nil:
            if characteristic === batteryLevelChar { value = Data([batteryLevel]) }
            else if let id = reportID(forCharacteristic: characteristic) { value = cachedReports[id] }
            else { value = nil }
        }
        if let value, let mutable = characteristic as? CBMutableCharacteristic {
            initialReports.removeAll { $0.0 == central.identifier && $0.1 === mutable }
            guard initialReports.count < 64 else { hardDisconnect(); return }
            initialReports.append((central.identifier, mutable, value))
            flushInitialReports()
        }
    }'''
    text=method(text,'    func peripheralManager(\n        _ peripheral: CBPeripheralManager,\n        central: CBCentral,\n        didSubscribeTo',subscribe)
    text=method(text,'    func peripheralManager(\n        _ peripheral: CBPeripheralManager,\n        central: CBCentral,\n        didUnsubscribeFrom', '''    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        guard peripheral === pManager, currentCharacteristic(characteristic) else { return }
        if let endpoint = endpoint(for: characteristic) { inputRegistry.unsubscribe(endpoint, peer: central.identifier) }
        initialReports.removeAll { $0.0 == central.identifier && $0.1 === characteristic }
        if var chars = subscribedCentrals[central.identifier] {
            chars.remove(ObjectIdentifier(characteristic))
            if chars.isEmpty {
                subscribedCentrals.removeValue(forKey: central.identifier)
                centralObjects.removeValue(forKey: central.identifier)
                inactiveCentrals.remove(central.identifier); connectedCentrals.remove(central.identifier)
                inputRegistry.forget(central.identifier); relayModes.removeValue(forKey: central.identifier)
                serviceChangedArmed = false
            } else { subscribedCentrals[central.identifier] = chars }
        }
        publishInputReadiness()
    }''')
    text=method(text,'    func peripheralManagerIsReady(', '''    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        guard peripheral === pManager else { return }
        isReadyToSendNotification = true; keyboardBackpressured = false
        flushInitialReports()
        onMouseWritable?()
    }''')
    text=once(text,'        _trace("read:', '''        guard peripheral === pManager, currentCharacteristic(request.characteristic) else {
            peripheral.respond(to: request, withResult: .requestNotSupported); return
        }
        _trace("read:''')
    text=once(text,'        guard let first = requests.first else { return }', '''        guard let first = requests.first else { return }
        guard peripheral === pManager, requests.allSatisfy({ currentCharacteristic($0.characteristic) }) else {
            peripheral.respond(to: first, withResult: .requestNotSupported); return
        }''')
    text=once(text,'            return type == HIDProfile.bootKeyboardOutputReport || type == HIDProfile.report', '''            return request.characteristic === bootKeyboardOutputChar ||
                reportID(forCharacteristic: request.characteristic) == ReportID.keyboardLEDs.rawValue''')
    text=once(text, '        case HIDProfile.protocolMode:\n            if let mode = value.first, mode <= 1 { relayModes[request.central.identifier] = mode }', '''        case HIDProfile.protocolMode:
            if let mode = value.first, mode <= 1 {
                relayModes[request.central.identifier] = mode
                inputRegistry.setProtocol(mode, peer: request.central.identifier)
                publishInputReadiness()
            }''')
    # Existing block is bounded by the next switch default; preserve all unrelated output handling.
    old='''        case HIDProfile.hidControlPoint:
            if value.first == 0 { keyboardReceivers.remove(request.central.identifier) }
            else if value.first == 1, keyboardSubscriptions[request.central.identifier] != nil { keyboardReceivers.insert(request.central.identifier) }
            if value.first == 0 { mouseReceivers.remove(request.central.identifier) }
            else if value.first == 1, mouseSubscriptions[request.central.identifier] != nil { mouseReceivers.insert(request.central.identifier) }'''
    text=once(text,old,'''        case HIDProfile.hidControlPoint:
            if let state = value.first {
                inputRegistry.setSuspended(state == 0, peer: request.central.identifier)
                publishInputReadiness()
            }''')
    text=method(text,'    func tryRelayMouse(', '''    func tryRelayMouse(_ report: MouseReport, to id: UUID) -> MouseSendResult {
        guard let manager = pManager, manager.state == .poweredOn,
              mouseReceivers.contains(id), let central = centralObjects[id] else { return .unavailable }
        flushInitialReports()
        guard isReadyToSendNotification, initialReports.isEmpty else { return .busy }
        let boot = inputRegistry.protocolMode(for: id) == 0
        guard let characteristic = boot ? bootMouseInputChar : charsByReportID[ReportID.mouse.rawValue] else { return .unavailable }
        let bytes = boot ? Data(report.data.prefix(3)) : report.data
        if manager.updateValue(bytes, for: characteristic, onSubscribedCentrals: [central]) { return .accepted }
        isReadyToSendNotification = false
        return .busy
    }''')
    text=method(text,'    func sendKeyboardBytes(', '''    func sendKeyboardBytes(_ bytes: Data, to id: UUID) -> KeyboardSendResult {
        guard bytes.count == 8, bytes[bytes.startIndex + 1] == 0,
              bytes.dropFirst(2).allSatisfy({ $0 <= 0xDD }),
              let manager = pManager, manager.state == .poweredOn,
              keyboardReceivers.contains(id), let central = centralObjects[id] else { return .unavailable }
        flushInitialReports()
        guard isReadyToSendNotification, initialReports.isEmpty else { return .busy }
        let boot = inputRegistry.protocolMode(for: id) == 0
        guard let characteristic = boot ? bootKeyboardInputChar : charsByReportID[ReportID.keyboard.rawValue] else { return .unavailable }
        if manager.updateValue(bytes, for: characteristic, onSubscribedCentrals: [central]) { return .accepted }
        isReadyToSendNotification = false
        return .busy
    }''')
    text += HELPERS
    return text

HELPERS='''

// MouseLink 0.2.1 safety adapter. All callbacks and notification queues belong to one live manager.
@MainActor
private extension HIDPeripheral {
    func invalidateServices() {
        serviceTask?.cancel(); serviceTask = nil
        inputRegistry.reset(); initialReports.removeAll()
        isAdvertising = false; isHIDServiceAdded = false; isReadyToSendNotification = true
        pendingBroadcast = nil; keyboardBackpressured = false
        batteryServiceObj = nil; deviceInfoServiceObj = nil; hidServiceObj = nil
        serviceChangedObj = nil; serviceChangedArmed = false; batteryLevelChar = nil
        bootMouseInputChar = nil; bootKeyboardInputChar = nil; bootKeyboardOutputChar = nil
        charsByReportID.removeAll(); subscribedCentrals.removeAll(); inactiveCentrals.removeAll()
        connectedCentrals.removeAll(); centralObjects.removeAll()
        mouseSubscriptions.removeAll(); keyboardSubscriptions.removeAll(); relayModes.removeAll()
        cachedReports[ReportID.mouse.rawValue] = MouseReport.zero.data
        cachedReports[ReportID.keyboard.rawValue] = KeyboardReport.zero.data
        publishInputReadiness()
    }
    func publishInputReadiness() {
        let mice = inputRegistry.mouseReceivers, keyboards = inputRegistry.keyboardReceivers
        if mice != mouseReceivers { mouseReceivers = mice }
        if keyboards != keyboardReceivers { keyboardReceivers = keyboards }
    }
    func currentCharacteristic(_ characteristic: CBCharacteristic) -> Bool {
        [batteryServiceObj, deviceInfoServiceObj, hidServiceObj, serviceChangedObj]
            .compactMap { $0 }.flatMap { $0.characteristics ?? [] }.contains { $0 === characteristic }
    }
    func endpoint(for characteristic: CBCharacteristic) -> HIDInputEndpoint? {
        if characteristic === bootMouseInputChar { return .mouseBoot }
        if characteristic === bootKeyboardInputChar { return .keyboardBoot }
        if characteristic === charsByReportID[ReportID.mouse.rawValue] { return .mouseReport }
        if characteristic === charsByReportID[ReportID.keyboard.rawValue] { return .keyboardReport }
        return nil
    }
    func flushInitialReports() {
        guard isReadyToSendNotification, let manager = pManager, manager.state == .poweredOn else { return }
        while let (peer, characteristic, bytes) = initialReports.first {
            guard let central = centralObjects[peer],
                  subscribedCentrals[peer]?.contains(ObjectIdentifier(characteristic)) == true,
                  currentCharacteristic(characteristic) else { initialReports.removeFirst(); continue }
            if manager.updateValue(bytes, for: characteristic, onSubscribedCentrals: [central]) {
                initialReports.removeFirst()
            } else { isReadyToSendNotification = false; return }
        }
    }
}
'''
