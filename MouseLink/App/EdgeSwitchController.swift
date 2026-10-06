// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Combine

/// Owns only the UI gesture. Existing MouseSession.start still enforces connection and pointer lock.
@MainActor
final class EdgeSwitchController: ObservableObject {
    @Published private(set) var isArmed = false
    @Published private(set) var progress: Double = 0
    private var gate = EdgeHandoffGate()
    private var pointer: EdgePointer?
    private var placement: DevicePlacement = .right
    private let context: (DevicePlacement) -> EdgeHandoffContext?
    private let allowed: () -> Bool
    private let buttonsReleased: () -> Bool
    private let start: () -> Void
    private let clock: () -> TimeInterval
    private var timer: AnyCancellable?

    init(context: @escaping (DevicePlacement) -> EdgeHandoffContext?, allowed: @escaping () -> Bool,
         buttonsReleased: @escaping () -> Bool, start: @escaping () -> Void,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         ticks: AnyPublisher<Date,Never> = Timer.publish(every:0.05,on:.main,in:.common).autoconnect().eraseToAnyPublisher()) {
        self.context = context; self.allowed = allowed; self.buttonsReleased = buttonsReleased
        self.start = start; self.clock = clock
        timer = ticks.sink { [weak self] _ in self?.poll() }
    }
    convenience init(session: MouseSession) {
        self.init(context: { [weak session] side in
            guard let session, let selected = session.selected else { return nil }
            return EdgeHandoffContext(peer: selected.uuidString, epoch: session.bluetooth.inputEpoch, side: side)
        }, allowed: { [weak session] in session?.canArmEdgeHandoff == true },
        buttonsReleased: { [weak session] in session?.pointerButtonsReleased == true },
        start: { [weak session] in session?.start() })
    }
    func setPlacement(_ value: DevicePlacement) {
        guard placement != value else { return }; disarm(); placement = value
    }
    func arm() {
        disarm()
        guard allowed(), let c = context(placement) else { return }
        gate.arm(context:c); publish()
    }
    func disarm() { gate.disarm(); pointer = nil; publish() }
    func hover(_ value: EdgePointer?) { pointer = value; poll() }
    func poll() {
        guard gate.isArmed else { return }
        let fired = gate.observe(pointer, context:context(placement), allowed:allowed(),
                                 buttonsReleased:buttonsReleased(), at:clock())
        publish()
        if fired { pointer = nil; start() }
    }
    private func publish() {
        if isArmed != gate.isArmed { isArmed = gate.isArmed }
        if progress != gate.progress { progress = gate.progress }
    }
}
