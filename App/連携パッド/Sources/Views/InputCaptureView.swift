import SwiftUI
import SharedControlKit
import UIKit

struct InputCaptureView: UIViewRepresentable {
    let frameSize: CGSize?
    let onEvent: (InputEventPayload) -> Void

    func makeUIView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.frameSize = frameSize
        view.onEvent = onEvent
        return view
    }

    func updateUIView(_ uiView: CaptureView, context: Context) {
        uiView.frameSize = frameSize
    }
}

final class CaptureView: UIView {
    var onEvent: ((InputEventPayload) -> Void)?
    var frameSize: CGSize?
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
        let normalized = normalizedPointer(for: location)
        let delta = CGVector(dx: normalized.x - lastLocation.x, dy: normalized.y - lastLocation.y)
        lastLocation = normalized
        let pointer = PointerEvent(location: normalized, delta: delta, buttons: [])
        onEvent?(.pointer(pointer))
    }

    private func normalizedPointer(for location: CGPoint) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else { return lastLocation }

        guard let frameSize else {
            return CGPoint(
                x: min(max(location.x / bounds.width, 0), 1),
                y: min(max(location.y / bounds.height, 0), 1)
            )
        }

        let safeWidth = max(frameSize.width, 1)
        let safeHeight = max(frameSize.height, 1)
        let scale = min(bounds.width / safeWidth, bounds.height / safeHeight)
        let renderedSize = CGSize(width: safeWidth * scale, height: safeHeight * scale)
        let origin = CGPoint(
            x: (bounds.width - renderedSize.width) / 2,
            y: (bounds.height - renderedSize.height) / 2
        )

        let relative = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
        let clamped = CGPoint(
            x: min(max(relative.x, 0), renderedSize.width),
            y: min(max(relative.y, 0), renderedSize.height)
        )

        return CGPoint(x: clamped.x / renderedSize.width, y: clamped.y / renderedSize.height)
    }
}
