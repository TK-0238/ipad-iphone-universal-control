# MouseLink QA 0.4.3 Implementation Plan

Goal: verify and repair remaining typing publication/reentrancy and input visibility faults without expanding the app's runtime permissions.
Architecture: keep authoritative input cancellation synchronous; notify SwiftUI only after the current view update, coalescing output-only notifications. Reject new transactions inside cancellation callbacks and recheck authorization after a transport callback. Multiply ancestor opacity when deciding whether a surface is visible.
Tech stack: existing Swift5/iOS17+, Combine/UIKit/XCTest, SwiftPM Linux, GitHub Actions.
Spec: existing companion-panel.md and keyboard-enter.md; the approved functionality is unchanged.

Constraints: existing Draft PR2 only; no main merge, release, user Mac/GUI/device access, extra runtime devices, upstream license changes, private input APIs, or simulated hardware-success claims.

- [ ] Add regression tests first; confirm failure on unchanged production code in native CI.
- [ ] Separate presentation notification from synchronous input state, guard cancellation, revalidate post-write, and fix composite opacity.
- [ ] Run full core Debug/Release/ASan, native, iPad UI/Split View, phone-layout UI, and packaging tests.
- [ ] Inspect actual screenshots and log warnings; save exact evidence and a CI-identical package only after success.

Review focus: queued UI invalidation must never grant input, cancel callbacks must not reenter begin, old-epoch releases must not go to new connections, no retained sessions from deferred notifications, draft/mode bindings must still update.
