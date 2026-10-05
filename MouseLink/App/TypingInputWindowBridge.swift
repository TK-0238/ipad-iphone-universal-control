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
        // Being attached with isHidden == false does not imply that any pixels are visible.
        // Carry the visible rectangle through each ancestor's coordinate system, including
        // UIScrollView's nonzero bounds origin. Only clipping ancestors restrict overflow.
        var visible = view.bounds
        guard hasArea(visible) else { return false }
        var current: UIView? = view
        while let item=current {
            if item.isHidden || !item.alpha.isFinite || item.alpha <= 0.01 ||
                item.traitCollection.activeAppearance == .inactive { return false }
            if item.clipsToBounds || item === window {
                visible = visible.intersection(item.bounds)
                guard hasArea(visible) else { return false }
            }
            if item === window { return true }
            guard let parent = item.superview else { return false }
            visible = item.convert(visible, to: parent)
            guard hasArea(visible) else { return false }
            current=parent
        }
        return false
    }
    private static func hasArea(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite) &&
            rect.width > 0 && rect.height > 0
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
