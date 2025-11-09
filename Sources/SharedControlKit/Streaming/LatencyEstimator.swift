import Foundation
import Combine
import QuartzCore

@MainActor
public final class LatencyEstimator: ObservableObject {
    @Published public private(set) var roundTripTime: TimeInterval = 0

    private var cancellables = Set<AnyCancellable>()
    private let timer: AnyPublisher<Date, Never>
    private let session: SessionCoordinator
    private var pendingPings: [UUID: TimeInterval] = [:]

    public init(session: SessionCoordinator, interval: TimeInterval = 1.0) {
        self.session = session
        self.timer = Timer.publish(every: interval, on: .main, in: .common).autoconnect().eraseToAnyPublisher()
        bind()
    }

    private func bind() {
        timer
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.sendPing()
                }
            }
            .store(in: &cancellables)

        session.inputEvents
            .sink { [weak self] event in
                guard case .system(let systemEvent) = event else { return }
                Task { @MainActor in
                    self?.handle(systemEvent)
                }
            }
            .store(in: &cancellables)
    }

    private func sendPing() {
        let pingID = UUID()
        let start = CACurrentMediaTime()
        pendingPings[pingID] = start
        let payload = InputEventPayload.system(.ping(id: pingID, timestamp: start))
        do {
            try session.send(event: payload)
        } catch {
            pendingPings.removeValue(forKey: pingID)
        }
    }

    private func handle(_ event: SystemEvent) {
        switch event {
        case .pong(let id, _):
            guard let start = pendingPings.removeValue(forKey: id) else { return }
            roundTripTime = CACurrentMediaTime() - start
        case .ping:
            break
        }
    }
}
