// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI
import UIKit
import GameController

struct PanelPadView: UIViewRepresentable {
    @ObservedObject var panel: PanelSession
    func makeUIView(context: Context) -> LocalPadView { LocalPadView(panel:panel) }
    func updateUIView(_ view: LocalPadView, context: Context) { view.refreshLabel() }
    static func dismantleUIView(_ view: LocalPadView, coordinator: ()) { view.dismantle() }
}

/// UIKit routes events to this view. There is intentionally no global/raw mouse capture.
@MainActor
final class LocalPadView: UIView {
    weak var panel: PanelSession?
    private let label = UILabel()
    private var observers:[NSObjectProtocol]=[]
    private var lastSize:CGSize = .zero
    private var tracked:UITouch?
    private var trackedGeneration:UInt64?
    private var origin:CGPoint = .zero
    private var moved = false
    private var cancelled = false
    private let owner = UUID()
    private weak var boundWindow: UIWindow?
    private var dismantled = false
    private var isCurrentSurface: Bool { !dismantled && panel?.ownsInputSurface(owner) == true }

    init(panel:PanelSession) {
        self.panel=panel
        super.init(frame:.zero)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius=18; layer.borderWidth=1
        isMultipleTouchEnabled=false
        isAccessibilityElement=true
        accessibilityLabel="iPhone操作パッド"
        accessibilityHint="パッドを有効にした後、中でマウスを動かしてクリック。指はなぞって移動、タップでクリック。"
        accessibilityIdentifier="panel-pad"
        label.textAlignment = .center;label.numberOfLines=0;label.isUserInteractionEnabled=false
        label.font = .preferredFont(forTextStyle:.subheadline);label.adjustsFontForContentSizeCategory=true
        label.adjustsFontSizeToFitWidth=true;label.minimumScaleFactor=0.6
        label.translatesAutoresizingMaskIntoConstraints=false;addSubview(label)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo:leadingAnchor,constant:16),
            label.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-16),label.centerYAnchor.constraint(equalTo:centerYAnchor),
            label.topAnchor.constraint(greaterThanOrEqualTo:topAnchor,constant:12),label.bottomAnchor.constraint(lessThanOrEqualTo:bottomAnchor,constant:-12)])
        let hover=UIHoverGestureRecognizer(target:self,action:#selector(hovered(_:)))
        hover.allowedTouchTypes=[NSNumber(value:UITouch.TouchType.indirectPointer.rawValue)]
        addGestureRecognizer(hover)
        let wheel=UIPanGestureRecognizer(target:self,action:#selector(scrolled(_:)))
        wheel.allowedScrollTypesMask = .all;wheel.allowedTouchTypes=[];wheel.cancelsTouchesInView=false
        addGestureRecognizer(wheel)
        for name in [UIWindow.didResignKeyNotification,UIScene.willDeactivateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, self.isCurrentSurface, let own = self.window else { return }
                    if (note.object as? UIWindow) === own || (note.object as? UIScene) === own.windowScene {
                        self.panel?.invalidateInputSurface(owner:self.owner,reason:"操作ウインドウが非アクティブになったため停止しました。")
                        self.cancelled=true
                    }
                }
            })
        }
        registerForTraitChanges([UITraitActiveAppearance.self]) { (view: LocalPadView, _: UITraitCollection) in
            if view.isCurrentSurface && !view.usable {
                view.panel?.invalidateInputSurface(owner:view.owner,reason:"操作パッドの表示状態が変わったため停止しました。")
                view.cancelled=true
            }
        }
        refreshLabel()
    }
    @available(*,unavailable) required init?(coder:NSCoder) { fatalError("No storyboard") }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    var usable:Bool {
        isCurrentSurface && InputWindowState.allowsInput(in:self) && bounds.width > 0 && bounds.height > 0
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard !dismantled else { return }
        guard let window else { detach(); return }
        guard boundWindow !== window else { return }
        detach()
        boundWindow = window
        panel?.bindInputSurface(owner:owner) { [weak self] in self?.usable == true }
    }
    private func detach() {
        panel?.unbindInputSurface(owner:owner)
        boundWindow=nil; resetContact()
    }
    func dismantle() {
        dismantled=true
        detach()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if isCurrentSurface && lastSize != .zero && lastSize != bounds.size {
            panel?.invalidateInputSurface(owner:owner,reason:"ウインドウの大きさが変わったため停止しました。")
            resetContact()
        }
        lastSize=bounds.size
        layer.borderColor=UIColor.separator.cgColor
    }
    func refreshLabel() {
        let enabled=isCurrentSurface && panel?.isEnabled == true
        label.text=enabled ? "iPhone操作パッド\n移動・クリック・ホイール" : "操作パッド\n接続後に有効にしてください"
        label.textColor=enabled ? .label : .secondaryLabel
        accessibilityValue=enabled ? "有効" : "停止中"
        accessibilityTraits=enabled ? [.allowsDirectInteraction] : [.notEnabled]
    }
    private func point(_ p:CGPoint, externalButtonsDown:Bool = false) {
        guard isCurrentSurface else { return }
        guard usable else { panel?.disable(); return }
        panel?.move(x:p.x,y:p.y,width:bounds.width,height:bounds.height,externalButtonsDown:externalButtonsDown)
    }
    @objc private func hovered(_ g:UIHoverGestureRecognizer) {
        guard isCurrentSurface else { return }
        switch g.state {
        case .began,.changed:
            let input=(GCMouse.current ?? GCMouse.mice().first)?.mouseInput
            let held=input?.leftButton.isPressed == true || input?.rightButton?.isPressed == true
            point(g.location(in:self),externalButtonsDown:held)
        default:
            panel?.leave();if tracked != nil { cancelled=true }
        }
    }
    @objc private func scrolled(_ g:UIPanGestureRecognizer) {
        guard isCurrentSurface, g.state == .began || g.state == .changed else { return }
        point(g.location(in:self))
        let delta=g.translation(in:self);g.setTranslation(.zero,in:self)
        panel?.scroll(-delta.y/12)
    }
    private var hasCurrentContact: Bool {
        guard tracked != nil, let generation=trackedGeneration else { return false }
        return isCurrentSurface && panel?.isEnabled == true && panel?.inputGeneration == generation
    }
    private func accepts(_ touch:UITouch, generation:UInt64?) -> Bool {
        tracked === touch && trackedGeneration == generation && hasCurrentContact
    }
    private func resetContact() {
        tracked=nil; trackedGeneration=nil; moved=false; cancelled=true
    }
    private func discard(_ touch:UITouch, generation:UInt64?) {
        // A send callback may already have installed another contact. Do not erase it.
        if tracked === touch && trackedGeneration == generation { resetContact() }
    }
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?) {
        if tracked != nil && !hasCurrentContact { resetContact() }
        guard tracked == nil, let t=touches.first, let panel, panel.isEnabled, usable else { return }
        let generation=panel.inputGeneration
        let start=t.location(in:self)
        point(start)
        guard tracked == nil, panel.isEnabled, panel.isInside,
              panel.inputGeneration == generation, isCurrentSurface else { return }
        tracked=t; trackedGeneration=generation; origin=start; moved=false; cancelled=false
        if t.type == .indirectPointer { panel.buttons(UInt8((event?.buttonMask.rawValue ?? 1) & 3)) }
    }
    override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent?) {
        guard let t=tracked,touches.contains(t) else { return }
        let generation=trackedGeneration
        guard accepts(t,generation:generation), !cancelled else { discard(t,generation:generation);return }
        let p=t.location(in:self)
        if hypot(p.x-origin.x,p.y-origin.y) > 6 { moved=true }
        point(p)
        if !accepts(t,generation:generation) { discard(t,generation:generation) }
    }
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?) {
        guard let t=tracked,touches.contains(t) else { return }
        let generation=trackedGeneration
        defer { discard(t,generation:generation) }
        guard accepts(t,generation:generation) else { return }
        guard usable else { panel?.disable();return }
        let p=t.location(in:self)
        guard !cancelled,bounds.contains(p) else { panel?.leave();return }
        // The terminal location can differ from the last touchesMoved sample.
        // Consume it before deciding tap versus drag, and before releasing a mouse button.
        if hypot(p.x-origin.x,p.y-origin.y) > 6 { moved=true }
        point(p)
        guard accepts(t,generation:generation) else { return }
        if t.type == .indirectPointer { panel?.buttons(0) }
        else if !moved {
            panel?.buttons(1)
            if accepts(t,generation:generation) { panel?.buttons(0) }
        }
        if t.type != .indirectPointer, accepts(t,generation:generation) { panel?.leave() }
    }
    override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent?) {
        guard let t=tracked, touches.isEmpty || touches.contains(t) else { return }
        let generation=trackedGeneration
        defer { discard(t,generation:generation) }
        if accepts(t,generation:generation) { panel?.leave() }
    }
}
