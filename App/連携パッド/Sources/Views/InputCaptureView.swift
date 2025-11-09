import SwiftUI
import SharedControlKit
import UIKit

struct InputCaptureView: UIViewRepresentable {
    let onEvent: (InputEventPayload) -> Void

    func makeUIView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onEvent = onEvent
        return view
    }

    func updateUIView(_ uiView: CaptureView, context: Context) {}
}

final class CaptureView: UIView {
    var onEvent: ((InputEventPayload) -> Void)?
    private var lastLocation: CGPoint = .zero

    override var canBecomeFirstResponder: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        addGestureRecognizer(hover)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        handlePresses(presses, isKeyDown: true)
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        handlePresses(presses, isKeyDown: false)
        super.pressesEnded(presses, with: event)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        becomeFirstResponder()
    }

    private func handlePresses(_ presses: Set<UIPress>, isKeyDown: Bool) {
        presses.forEach { press in
            guard let key = press.key else { return }
            let event = KeyEvent(
                key: key.charactersIgnoringModifiers ?? key.keyCode.description,
                modifiers: key.modifierFlags,
                isKeyDown: isKeyDown
            )
            onEvent?(.key(event))
        }
    }

    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        let location = recognizer.location(in: self)
        emitPointer(location: location)
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: self)
        emitPointer(location: location)
    }

    private func emitPointer(location: CGPoint) {
        let delta = CGVector(dx: location.x - lastLocation.x, dy: location.y - lastLocation.y)
        lastLocation = location
        let pointer = PointerEvent(location: location, delta: delta, buttons: [])
        onEvent?(.pointer(pointer))
    }
}
