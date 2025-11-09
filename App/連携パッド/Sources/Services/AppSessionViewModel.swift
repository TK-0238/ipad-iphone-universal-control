import Foundation
import Combine
import SwiftUI
import SharedControlKit
import SidecarCastingKit
import MultipeerConnectivity

@MainActor
final class AppSessionViewModel: ObservableObject {
    @Published var role: ControlRole = .controller {
        didSet { configureRole() }
    }
    @Published var connectionState: SessionState = .idle
    @Published var remotePointer: PointerEvent?
    @Published var latestFrame: DisplayFrame?
    @Published var latency: TimeInterval = 0
    @Published var discoveredPeers: [MCPeerID] = []

    let sessionCoordinator = SessionCoordinator()
    private lazy var latencyEstimator = LatencyEstimator(session: sessionCoordinator, interval: 1.0)
    private let inputBridge = InputBridge()
    private var captureCoordinator: ScreenCaptureCoordinator?
    private var cancellables = Set<AnyCancellable>()

    init() {
        bind()
        configureRole()
    }

    private func bind() {
        sessionCoordinator.$state
            .assign(to: &$connectionState)

        sessionCoordinator.$discoveredPeers
            .assign(to: &$discoveredPeers)

        sessionCoordinator.inputEvents
            .sink { [weak self] event in
                switch event {
                case .pointer(let pointer):
                    self?.remotePointer = pointer
                case .key:
                    break
                }
            }
            .store(in: &cancellables)

        sessionCoordinator.frameEvents
            .receive(on: DispatchQueue.main)
            .assign(to: &$latestFrame)

        latencyEstimator.$roundTripTime
            .assign(to: &$latency)

        inputBridge.delegate = self
    }

    private func configureRole() {
        switch role {
        case .controller:
            sessionCoordinator.startBrowsing()
        case .display, .mirror:
            sessionCoordinator.startAdvertising()
        }
    }

    func invite(peer: MCPeerID) {
        sessionCoordinator.connect(to: peer)
    }

    func push(event: InputEventPayload) {
        try? sessionCoordinator.send(event: event)
    }

    func startScreenShare(targetSize: CGSize) {
        captureCoordinator = ScreenCaptureCoordinator(targetSize: targetSize)
        captureCoordinator?.frames
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                self?.pushFrame(frame)
            }
            .store(in: &cancellables)
        captureCoordinator?.start()
    }

    func stopScreenShare() {
        captureCoordinator?.stop()
        captureCoordinator = nil
    }

    private func pushFrame(_ frame: DisplayFrame) {
        try? sessionCoordinator.send(frame: frame)
    }

    func bindInput(_ handler: @escaping (InputEventPayload) -> Void) -> AnyCancellable {
        inputBridge.eventPublisher
            .sink(receiveValue: handler)
    }

    func emitLocal(_ event: InputEventPayload) {
        inputBridge.push(event)
    }
}

extension AppSessionViewModel: InputBridgeDelegate {
    func inputBridge(_ bridge: InputBridge, didProduce event: InputEventPayload) {
        push(event: event)
    }
}
