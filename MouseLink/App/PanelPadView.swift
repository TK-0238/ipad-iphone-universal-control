// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI
import UIKit
import GameController

struct PanelPadView: UIViewRepresentable {
    @ObservedObject var panel: PanelSession
    func makeUIView(context: Context) -> LocalPadView { LocalPadView(panel:panel) }
    func updateUIView(_ view: LocalPadView, context: Context) { view.refreshLabel() }
    static func dismantleUIView(_ view: LocalPadView, coordinator: ()) { view.panel?.disable() }
}

/// UIKit routes events to this view. There is intentionally no global/raw mouse capture.
@MainActor
final class LocalPadView: UIView {
    weak var panel: PanelSession?
    private let label = UILabel()
    private var observers:[NSObjectProtocol]=[]
    private var lastSize:CGSize = .zero
    private var tracked:UITouch?
    private var origin:CGPoint = .zero
    private var moved = false
    private var cancelled = false

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
        panel.surfaceIsUsable={ [weak self] in self?.usable == true }
        for name in [UIWindow.didResignKeyNotification,UIScene.willDeactivateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let own = self.window else { return }
                    if (note.object as? UIWindow) === own || (note.object as? UIScene) === own.windowScene {
                        self.panel?.disable(reason:"操作ウインドウが非アクティブになったため停止しました。")
                        self.cancelled=true
                    }
                }
            })
        }
        registerForTraitChanges([UITraitActiveAppearance.self]) { (view: LocalPadView, _: UITraitCollection) in
            if !view.usable { view.panel?.disable();view.cancelled=true }
        }
        refreshLabel()
    }
    @available(*,unavailable) required init?(coder:NSCoder) { fatalError("No storyboard") }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    var usable:Bool {
        InputWindowState.allowsInput(in:self) && bounds.width > 0 && bounds.height > 0
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { panel?.disable(reason:"操作パッドが非表示になったため停止しました。") }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if lastSize != .zero && lastSize != bounds.size { panel?.geometryChanged();tracked=nil;cancelled=true }
        lastSize=bounds.size
        layer.borderColor=UIColor.separator.cgColor
    }
    func refreshLabel() {
        let enabled=panel?.isEnabled == true
        label.text=enabled ? "iPhone操作パッド\n移動・クリック・ホイール" : "操作パッド\n接続後に有効にしてください"
        label.textColor=enabled ? .label : .secondaryLabel
        accessibilityValue=enabled ? "有効" : "停止中"
        accessibilityTraits=enabled ? [.allowsDirectInteraction] : [.notEnabled]
    }
    private func point(_ p:CGPoint, externalButtonsDown:Bool = false) {
        guard usable else { panel?.disable(); return }
        panel?.move(x:p.x,y:p.y,width:bounds.width,height:bounds.height,externalButtonsDown:externalButtonsDown)
    }
    @objc private func hovered(_ g:UIHoverGestureRecognizer) {
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
        guard g.state == .began || g.state == .changed else { return }
        point(g.location(in:self))
        let delta=g.translation(in:self);g.setTranslation(.zero,in:self)
        panel?.scroll(-delta.y/12)
    }
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?) {
        guard tracked == nil,let t=touches.first,usable else { return }
        tracked=t;origin=t.location(in:self);moved=false;cancelled=false
        point(origin)
        if t.type == .indirectPointer { panel?.buttons(UInt8((event?.buttonMask.rawValue ?? 1) & 3)) }
    }
    override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent?) {
        guard let t=tracked,touches.contains(t),!cancelled else { return }
        let p=t.location(in:self)
        if hypot(p.x-origin.x,p.y-origin.y) > 6 { moved=true }
        point(p)
        if panel?.isInside != true { cancelled=true;panel?.leave() }
    }
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?) {
        guard let t=tracked,touches.contains(t) else { return }
        let p=t.location(in:self)
        if !cancelled,bounds.contains(p),usable {
            if t.type == .indirectPointer { panel?.buttons(0) }
            else if !moved { panel?.tap() }
        }
        if t.type != .indirectPointer || cancelled || !bounds.contains(p) { panel?.leave() }
        tracked=nil
    }
    override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent?) {
        tracked=nil;cancelled=true;panel?.leave()
    }
}
