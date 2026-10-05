// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI
import UIKit

/// Visibility and input focus are distinct from the app's foreground lifecycle in multiwindow UI.
@MainActor
enum InputWindowState {
    static func allowsInput(in view: UIView) -> Bool {
        guard let window=view.window, !window.isHidden, window.isKeyWindow,
              let scene = window.windowScene, scene.activationState == .foregroundActive,
              scene.traitCollection.activeAppearance != .inactive else { return false }
        // Read the scene and ancestors too: a descendant can have cached or overridden traits.
        // Some systems report .unspecified; the actual scene/key-window checks still apply.
        var current: UIView? = view
        while let item=current {
            if item.isHidden || item.alpha <= 0.01 || item.traitCollection.activeAppearance == .inactive { return false }
            current=item.superview
        }
        return true
    }
}

struct TypingInputWindowBridge: UIViewRepresentable {
    let session: TypingSession
    func makeUIView(context: Context) -> TypingInputWindowView { TypingInputWindowView(session:session) }
    func updateUIView(_ view: TypingInputWindowView, context: Context) {}
    static func dismantleUIView(_ view: TypingInputWindowView, coordinator: ()) { view.detach() }
}

/// No input interception or overlay: this transparent view only observes its OWN window.
@MainActor
final class TypingInputWindowView: UIView {
    private weak var session: TypingSession?
    private let owner=UUID()
    private var focusLost=false
    private var observers: [NSObjectProtocol]=[]
    init(session: TypingSession) {
        self.session=session
        super.init(frame:.zero)
        isUserInteractionEnabled=false;isAccessibilityElement=false
        for name in [UIWindow.didResignKeyNotification,UIWindow.didBecomeKeyNotification,
                     UIScene.willDeactivateNotification,UIScene.didActivateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self,let own=self.window else { return }
                    let ownWindow=(note.object as? UIWindow) === own
                    let ownScene=(note.object as? UIScene) === own.windowScene
                    guard ownWindow || ownScene else { return }
                    self.focusLost = note.name == UIWindow.didResignKeyNotification || note.name == UIScene.willDeactivateNotification
                    self.session?.inputSurfaceChanged()
                }
            })
        }
        registerForTraitChanges([UITraitActiveAppearance.self]) { (view: TypingInputWindowView, _: UITraitCollection) in
            view.session?.inputSurfaceChanged()
        }
    }
    @available(*,unavailable) required init?(coder:NSCoder) { fatalError("No storyboard") }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { detach();return }
        focusLost=false
        session?.bindInputSurface(owner:owner) { [weak self] in
            guard let self else { return false }
            return !self.focusLost && InputWindowState.allowsInput(in:self)
        }
    }
    func detach() { session?.unbindInputSurface(owner:owner) }
}
