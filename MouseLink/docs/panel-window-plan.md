# Companion panel implementation plan — 2026-10-05

Goal: use MouseLink as one small visible window beside another iPad app, without a Mac, external bridge or physical keyboard.

Design: remove the multitasking opt-out; provide a width-adaptive (below 700pt) compact UI and a manual panel switch. A UIKit pad receives only local hover, button and wheel events. It does not request pointer lock, monitor another app or pretend to know the iPhone cursor location. Pointer entry establishes a relative baseline; leaving drops queued motion and releases buttons. An app/scene/key-window deactivation, hidden view, resize, receiver or transport-epoch change disables input and requires explicit re-enable. Touch movement is optional; keyboard/Enter uses the existing separately confirmed UI.

Full-screen raw-mouse mode remains separate. Only one MouseLink scene is supported so two panels cannot compete for the Bluetooth transport. iPadOS Windowed Apps/Stage Manager/legacy Split View or Slide Over arrange MouseLink alongside other apps; the app does not secretly position or pin an overlay above them.

Reference: Apple WWDC20/10094 requires a foreground-active full-screen scene for pointer lock. Apple UIRequiresFullScreen documentation and TN3192 require removing the opt-out and supporting resizing/all orientations. Apple support 125309 documents side-by-side windows and Slide Over in iPadOS 26.2+.

- [ ] Add and run failing PanelPointerTests for bounds, entry, fractional movement, exits and unexpected button states. Implement LocalPadPointer in the tested core.
- [ ] Add PanelSessionTests for selected-target-only FIFO, pressure, expiry, focus loss, cancellation and reconnect. Implement PanelSession with an injectable sender and a live view authorization closure.
- [ ] Add the compact panel, UIKit local event pad and integration with existing MouseSession; preserve the full-screen interface and typing UX. Keep remote state truthful when offline.
- [ ] Generate both Xcode and Swift Playground multitasking metadata. Verify generated plist and package source/license integrity.
- [ ] Build/run existing plus new suites; attempt real system Split View on an iPad simulator, and test 320pt/large-text UI. Inspect exported screenshots; never count simulated radio delivery as hardware success.
- [ ] Review source, record exact CI results and remaining hardware conditions; update existing Draft PR #2 without merge/release.

Review focus: clicks beginning outside the pad, leaving while dragging, late callbacks after panel resize, keyboard/modal transitions, OS focus changes before the next timer tick.
