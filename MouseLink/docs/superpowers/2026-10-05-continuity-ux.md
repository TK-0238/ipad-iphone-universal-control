# MouseLink 0.3 — continuity workspace design and implementation plan

Goal: Bring the existing iPad/iPhone workflow closer to Universal Control without claiming OS-wide control. User requested UI/UX refinement after the 0.2.1 safety pass.
Architecture: Preserve HID transport and typing source. Add a native device arrangement, persistent left/right placement, contextual status, fixed action bar, settings and explicitly armed foreground-only edge handoff. A Foundation gate decides when intentional pointer dwell can call existing MouseSession.start().
Constraints: iPad+iPhone+mouse at runtime. No user Mac/shared GUI/new subagent/automatic input/reconnection/merge/release/App Store. Preserve AGPL and original upstream source. Diagram is not a screen capture or remote cursor position.

Interaction: optional one-shot handoff bound to selected peer/epoch/side; require interior visit, then 24pt edge dwell for 0.7s. Ignore 48pt top/bottom, dragging, invalid/outside coordinates, gaps over 250ms, inactive state, sheets, missing mouse and missing peer. Reconnect, placement, window size and screen changes disarm. Existing actual-pointer-lock checks remain authoritative. Return via middle button or stop; do not infer iPhone cursor coordinates.

Validation:
- Baseline: 85 core tests passed before change.
- Edge core: 24 new tests written before implementation; observed missing types, implemented gate; 109 tests green in Debug and Release.
- Add native controller tests for one-shot callbacks and lifecycle gates; no physical Bluetooth substitute.
- Add UI tests for persistent placement without persisted permission, offline disabled actions, settings, landscape and large text. Retain prior suites.
- Run GitHub Actions simulator/device builds, package checks, native/UI tests. Inspect actual screenshots and preserve evidence. Hardware hover/Bluetooth/IME/Playground remains unverified.

Sources: https://support.apple.com/102459 ; https://developer.apple.com/documentation/uikit/uipointerlockstate/islocked
