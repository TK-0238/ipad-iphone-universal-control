import XCTest
import Combine
@testable import MouseLink

@MainActor
final class TypingEditingObservationTests: XCTestCase {
    func testDraftAndModeRemainObservableWithoutAuthorizingInput() {
        let radio = HIDPeripheral()
        let model = TypingSession(sender: radio, ticks: Empty<Date, Never>().eraseToAnyPublisher())
        var changes = 0
        let token = model.objectWillChange.sink { changes += 1 }
        defer { token.cancel() }
        model.draft = "local only"
        XCTAssertEqual(model.draft, "local only")
        XCTAssertEqual(changes, 1, "SwiftUI must observe normal draft editing")
        model.mode = .kanaReading
        XCTAssertEqual(changes, 2, "The mode picker must retain normal observation")
        XCTAssertFalse(model.canSend)
        XCTAssertFalse(model.isSending)
        XCTAssertFalse(radio.isAdvertising)
    }
}
