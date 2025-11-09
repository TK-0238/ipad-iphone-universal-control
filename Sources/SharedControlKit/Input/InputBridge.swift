import Foundation
import Combine

public protocol InputBridgeDelegate: AnyObject {
    func inputBridge(_ bridge: InputBridge, didProduce event: InputEventPayload)
}

public final class InputBridge: ObservableObject {
    public weak var delegate: InputBridgeDelegate?
    private let eventSubject = PassthroughSubject<InputEventPayload, Never>()
    public var eventPublisher: AnyPublisher<InputEventPayload, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    public init() {}

    public func push(_ event: InputEventPayload) {
        delegate?.inputBridge(self, didProduce: event)
        eventSubject.send(event)
    }
}
