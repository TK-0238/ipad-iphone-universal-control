import Testing
import Foundation
import CoreGraphics
@testable import SharedControlKit

struct SharedControlKitTests {
    @Test("Pointer event roundtrip")
    func pointerEventEncodingDecoding() throws {
        let pointer = PointerEvent(location: CGPoint(x: 10, y: 20),
                                   delta: CGVector(dx: 1, dy: -1),
                                   buttons: [.primary])
        let event = InputEventPayload.pointer(pointer)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(InputEventPayload.self, from: data)
        #expect(decoded == event)
    }

    @Test("Key event roundtrip")
    func keyEventEncodingDecoding() throws {
        let key = KeyEvent(key: "A", modifiers: [], isKeyDown: true)
        let event = InputEventPayload.key(key)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(InputEventPayload.self, from: data)
        #expect(decoded == event)
    }
}
