import Foundation
import Combine
import QuartzCore

@MainActor
public final class LatencyEstimator: ObservableObject {
    @Published public private(set) var roundTripTime: TimeInterval = 0
    private var cancellables = Set<AnyCancellable>()
    private let timer: AnyPublisher<Date, Never>
    private let session: SessionCoordinator

    public init(session: SessionCoordinator, interval: TimeInterval = 1.0) {
        self.session = session
        self.timer = Timer.publish(every: interval, on: .main, in: .common).autoconnect().eraseToAnyPublisher()
        bind()
    }

    private func bind() {
        timer
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.measureRTT()
                }
            }
            .store(in: &cancellables)
    }

    private func measureRTT() async {
        let pingID = UUID()
        let start = CACurrentMediaTime()
        let payload = InputEventPayload.key(KeyEvent(key: "__ping__\(pingID.uuidString)", isKeyDown: true))
        try? session.send(event: payload)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let end = CACurrentMediaTime()
        DispatchQueue.main.async { [weak self] in
            self?.roundTripTime = end - start
        }
    }
}
