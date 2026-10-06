# MouseLink Implementation Plan

Goal: direct Bluetooth mouse relay without a runtime Mac.
Spec: design.md
Architecture: testable Core; iOS input/transport adapter; SwiftUI UI; pinned upstream packaging.
Tech Stack: Swift 5.10+, CoreBluetooth, GameController, SwiftUI, XCTest.

## Constraints and review focus
No user's Mac access. Existing main unchanged. No pretend global edge handoff. Explicit receiver consent, stale callbacks, held buttons on pause, Bluetooth backpressure, fractional and extreme movement are priority failure cases.

- [x] Core: failing tests, then actual report encoding, accumulation, bounded FIFO, timeout/stop and host selection; 22 tests passed in local Linux Swift 6.2.1.
- [x] Native source: preserve HOGP topology, add target-specific send and mouse subscriptions, GCMouse generation guards and stop conditions.
- [x] Japanese pairing/host/relay UI and pointer-lock host; accessible guide/errors; no fake screen preview.
- [ ] Package: pin upstream blobs; generate offline .swiftpm and iOS project; native build/UI smoke tests via GitHub Actions.
- [ ] Review/retest: inspect actual native screenshots when produced; preserve actual logs and explicitly distinguish hardware validation.
